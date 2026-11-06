--!strict
-- Крипы: появление по плотности, мутации, реген, поведение трёх размеров, смерть.
-- Сервер владеет HP. Клиенты читают атрибуты модели: CreepId, Zone, Size, Mutation, Hp, MaxHp.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)

local notice = ReplicatedStorage.Remotes.Notice :: RemoteEvent

type Flock = { center: Vector3, members: { Creep }, nextMove: number, zone: number }

export type Creep = {
	id: number,
	zone: number,
	size: number,
	mutation: number,
	hp: number,
	maxHp: number,
	alive: boolean,
	model: Model,
	root: BasePart,
	velocity: LinearVelocity,
	align: AlignOrientation,
	flock: Flock?,
	offset: Vector3, -- место малого внутри стайки
	fleeUntil: number,
	fleeDir: Vector3,
	knockUntil: number,
	target: Vector3?,
	nextWander: number,
	sentHp: number,
}

type ZoneState = {
	players: number,
	rifts: { Vector3 },
	alive: { number }, -- по размерам
	pending: { number }, -- ждут возрождения, по размерам
	flocks: { Flock },
}

local Creeps = {}

local rng = Random.new()
local creeps: { [number]: Creep } = {}
local zones: { ZoneState } = {}
local nextId = 0
local folder: Folder

local C = Config.Creeps
local W = Config.World

local function now(): number
	return os.clock()
end

local function zoneBounds(zone: number): (number, number, number)
	local z = Config.Zones[zone]
	local m = C.Sizes[3].radius + W.CreepEdgeMargin
	return z.xStart + m, z.xEnd - m, W.RoadHalfWidth - W.CreepEdgeMargin
end

local function clampToZone(zone: number, p: Vector3): Vector3
	local x0, x1, hz = zoneBounds(zone)
	return Vector3.new(math.clamp(p.X, x0, x1), p.Y, math.clamp(p.Z, -hz, hz))
end

local function rollMutation(): number
	for i = #Config.CreepMutations, 1, -1 do
		if rng:NextNumber() < Config.CreepMutations[i].chance then
			return i
		end
	end
	return 0
end

-- Сколько крипов каждого размера должно быть в зоне.
local function desired(zone: number): { number }
	local total = C.BasePerZone + C.PerPlayerInZone * zones[zone].players
	local small = math.floor(total * C.Sizes[1].share + 0.5)
	local large = math.floor(total * C.Sizes[3].share + 0.5)
	return { small, total - small - large, large }
end

local function nearestRift(zone: number, p: Vector3): Vector3
	local best, bestD = zones[zone].rifts[1], math.huge
	for _, r in zones[zone].rifts do
		local d = (r - p).Magnitude
		if d < bestD then
			best, bestD = r, d
		end
	end
	return best
end

local function randomRift(zone: number): Vector3
	local rifts = zones[zone].rifts
	return rifts[rng:NextInteger(1, #rifts)]
end

-- Точка рядом с разломом, чуть ближе к середине дороги.
local function spawnPointNear(zone: number, rift: Vector3): Vector3
	local inward = if rift.Z > 0 then -1 else 1
	local p = rift + Vector3.new(rng:NextNumber(-3, 3), 0, inward * rng:NextNumber(3, 6))
	return clampToZone(zone, p)
end

local function spawnOne(zone: number, size: number, at: Vector3, flock: Flock?): Creep
	nextId += 1
	local s = C.Sizes[size]
	local mutation = rollMutation()
	local maxHp = Formulas.creepMaxHp(zone, size, mutation)
	local cf = CFrame.new(at.X, W.GroundY + s.height / 2 + 0.3, at.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model = Models.creep(zone, size, mutation, cf)
	local root = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Creeps"
		end
	end

	local att = Instance.new("Attachment")
	att.Name = "Mover"
	att.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = att
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.zero
	velocity.MaxForce = root.AssemblyMass * 400
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = true
	align.CFrame = cf.Rotation
	align.Parent = root

	model:SetAttribute("CreepId", nextId)
	model:SetAttribute("Zone", zone)
	model:SetAttribute("Size", size)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("MaxHp", maxHp)
	model:SetAttribute("Hp", maxHp)
	model.Parent = folder
	root:SetNetworkOwner(nil)

	local creep: Creep = {
		id = nextId,
		zone = zone,
		size = size,
		mutation = mutation,
		hp = maxHp,
		maxHp = maxHp,
		alive = true,
		model = model,
		root = root,
		velocity = velocity,
		align = align,
		flock = flock,
		offset = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * C.FlockSpread,
		fleeUntil = 0,
		fleeDir = Vector3.zero,
		knockUntil = 0,
		target = nil,
		nextWander = now() + rng:NextNumber(0, C.WanderEveryMax),
		sentHp = maxHp,
	}
	creeps[nextId] = creep
	zones[zone].alive[size] += 1
	if flock then
		table.insert(flock.members, creep)
	end

	local m = Config.CreepMutations[mutation]
	if m and m.announce then
		notice:FireAllClients("announce", `{m.name} крип появился: {Config.Zones[zone].name}!`)
	end
	return creep
end

local function newFlock(zone: number, center: Vector3): Flock
	local flock: Flock = { center = center, members = {}, nextMove = now() + rng:NextNumber(C.WanderEveryMin, C.WanderEveryMax), zone = zone }
	table.insert(zones[zone].flocks, flock)
	return flock
end

local function spawnFlock(zone: number, count: number, rift: Vector3)
	local center = spawnPointNear(zone, rift)
	local flock = newFlock(zone, center)
	for _ = 1, count do
		spawnOne(zone, 1, center + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)), flock)
	end
end

-- Возрождённый малый присоединяется к ближайшей неполной стайке или начинает свою.
local function spawnSmallNear(zone: number, rift: Vector3)
	local at = spawnPointNear(zone, rift)
	local best: Flock? = nil
	local bestD = 40
	for _, f in zones[zone].flocks do
		local d = (f.center - at).Magnitude
		if #f.members < C.FlockMax and d < bestD then
			best, bestD = f, d
		end
	end
	spawnOne(zone, 1, at, best or newFlock(zone, at))
end

local function removeFromFlock(creep: Creep)
	local flock = creep.flock
	if not flock then
		return
	end
	local i = table.find(flock.members, creep)
	if i then
		table.remove(flock.members, i)
	end
	if #flock.members == 0 then
		local list = zones[flock.zone].flocks
		local j = table.find(list, flock)
		if j then
			table.remove(list, j)
		end
	end
	creep.flock = nil
end

local function scheduleRespawn(zone: number, size: number, deathPos: Vector3)
	local zs = zones[zone]
	zs.pending[size] += 1
	task.delay(rng:NextNumber(C.RespawnMin, C.RespawnMax), function()
		zs.pending[size] -= 1
		if zs.alive[size] + zs.pending[size] >= desired(zone)[size] then
			return -- игроков стало меньше, норма уже набрана
		end
		local rift = nearestRift(zone, deathPos)
		if size == 1 then
			spawnSmallNear(zone, rift)
		else
			spawnOne(zone, size, spawnPointNear(zone, rift), nil)
		end
	end)
end

-- Публичное ------------------------------------------------------------------

function Creeps.get(id: number): Creep?
	return creeps[id]
end

function Creeps.setPlayers(zone: number, count: number)
	if zones[zone] then
		zones[zone].players = count
	end
end

-- Ближайший живой крип в радиусе удара (считаем до поверхности крипа, по горизонтали).
function Creeps.nearest(pos: Vector3, radius: number): Creep?
	local best: Creep? = nil
	local bestD = math.huge
	for _, c in creeps do
		if c.alive then
			local d = (c.root.Position - pos) * Vector3.new(1, 0, 1)
			local gap = d.Magnitude - C.Sizes[c.size].radius
			if gap <= radius and gap < bestD then
				best, bestD = c, gap
			end
		end
	end
	return best
end

-- Наносит урон. Возвращает true, если крип умер. Награды раздаёт вызывающий.
function Creeps.damage(creep: Creep, amount: number, attackerPos: Vector3): boolean
	if not creep.alive then
		return false
	end
	creep.hp -= amount
	if creep.hp <= 0 then
		creep.alive = false
		creep.hp = 0
		local pos = creep.root.Position
		zones[creep.zone].alive[creep.size] -= 1
		removeFromFlock(creep)
		creeps[creep.id] = nil
		creep.model:Destroy()
		scheduleRespawn(creep.zone, creep.size, pos)
		return true
	end
	creep.model:SetAttribute("Hp", creep.hp)
	creep.sentHp = creep.hp

	-- Отброс от удара: короткий толчок прочь от игрока.
	local push = (creep.root.Position - attackerPos) * Vector3.new(1, 0, 1)
	if push.Magnitude > 0.1 then
		local v = push.Unit * C.Sizes[creep.size].knockback
		creep.velocity.PlaneVelocity = Vector2.new(v.X, v.Z)
		creep.knockUntil = now() + C.KnockbackTime
	end

	-- Малые разбегаются всей стайкой.
	local flock = creep.flock
	if creep.size == 1 and flock then
		for _, m in flock.members do
			local away = (m.root.Position - attackerPos) * Vector3.new(1, 0, 1)
			if away.Magnitude < 0.1 then
				away = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
			end
			local dir = CFrame.Angles(0, math.rad(rng:NextNumber(-50, 50)), 0):VectorToWorldSpace(away.Unit)
			m.fleeDir = dir
			m.fleeUntil = now() + C.Sizes[1].fleeTime
		end
	end
	return false
end

-- Цикл -------------------------------------------------------------------

local function steer(c: Creep, want: Vector3, speed: number)
	local flat = (want - c.root.Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude < 1 or speed <= 0 then
		c.velocity.PlaneVelocity = Vector2.zero
		return
	end
	local v = flat.Unit * speed
	c.velocity.PlaneVelocity = Vector2.new(v.X, v.Z)
	c.align.CFrame = CFrame.lookAt(Vector3.zero, flat.Unit)
end

local function tickCreep(c: Creep, t: number, dt: number)
	-- Реген идёт всегда: стена урона работает только так.
	if c.hp < c.maxHp then
		c.hp = math.min(c.maxHp, c.hp + Formulas.regenPerSecond(c.maxHp) * dt)
		if math.abs(c.hp - c.sentHp) >= c.maxHp * 0.005 or c.hp == c.maxHp then
			c.sentHp = c.hp
			c.model:SetAttribute("Hp", c.hp)
		end
	end

	if t < c.knockUntil then
		return -- летит от удара
	end
	local s = C.Sizes[c.size]
	local pos = c.root.Position
	local inside = clampToZone(c.zone, pos)
	if (inside - pos).Magnitude > 0.5 then
		-- Вышел за край — возвращаем к середине зоны.
		steer(c, Vector3.new(inside.X, pos.Y, inside.Z * 0.5), math.max(s.speed, 6))
		return
	end

	if c.size == 1 then
		if t < c.fleeUntil then
			steer(c, pos + c.fleeDir * 10, s.fleeSpeed)
		elseif c.flock then
			steer(c, c.flock.center + c.offset, s.speed)
		end
	elseif c.size == 3 then
		if t >= c.nextWander then
			c.nextWander = t + rng:NextNumber(C.WanderEveryMin, C.WanderEveryMax)
			local a = rng:NextNumber(0, math.pi * 2)
			c.target = clampToZone(c.zone, pos + Vector3.new(math.cos(a), 0, math.sin(a)) * C.WanderDistance)
		end
		if c.target then
			steer(c, c.target, s.speed)
		end
	end
end

local function tickFlocks(t: number)
	for zi, zs in zones do
		for _, f in zs.flocks do
			if t >= f.nextMove then
				f.nextMove = t + rng:NextNumber(C.WanderEveryMin, C.WanderEveryMax)
				-- После бегства стайка собирается там, где оказалась, и идёт дальше.
				local sum = Vector3.zero
				for _, m in f.members do
					sum += m.root.Position
				end
				local mid = if #f.members > 0 then sum / #f.members else f.center
				local a = rng:NextNumber(0, math.pi * 2)
				f.center = clampToZone(zi, mid + Vector3.new(math.cos(a), 0, math.sin(a)) * C.WanderDistance)
			end
		end
	end
end

-- Добираем норму плотности: по одному крипу (или одной стайке) за шаг.
local function fillZones()
	for zi, zs in zones do
		if #zs.rifts == 0 then
			continue
		end
		local want = desired(zi)
		local bestSize, bestGap = 0, 0
		for size = 1, 3 do
			local gap = want[size] - zs.alive[size] - zs.pending[size]
			if gap > bestGap then
				bestSize, bestGap = size, gap
			end
		end
		if bestSize == 1 then
			spawnFlock(zi, math.min(bestGap, rng:NextInteger(C.FlockMin, C.FlockMax)), randomRift(zi))
		elseif bestSize > 1 then
			spawnOne(zi, bestSize, spawnPointNear(zi, randomRift(zi)), nil)
		end
	end
end

function Creeps.start()
	folder = Instance.new("Folder")
	folder.Name = "Creeps"
	folder.Parent = Workspace

	for i = 1, #Config.Zones do
		zones[i] = { players = 0, rifts = {}, alive = { 0, 0, 0 }, pending = { 0, 0, 0 }, flocks = {} }
	end
	for _, rift in CollectionService:GetTagged("RiftPoint") do
		local zone = rift:GetAttribute("Zone")
		if rift:IsA("BasePart") and type(zone) == "number" and zones[zone] then
			table.insert(zones[zone].rifts, rift.Position)
		end
	end
	for i, zs in zones do
		if #zs.rifts == 0 then
			warn(`В зоне {i} нет точек RiftPoint. Запусти tools/build_map.luau.`)
		end
	end

	local acc, fillAcc = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		fillAcc += dt
		if fillAcc >= 1 / C.SpawnPerSecond then
			fillAcc = 0
			fillZones()
		end
		if acc < C.TickInterval then
			return
		end
		local step = acc
		acc = 0
		local t = now()
		tickFlocks(t)
		for _, c in creeps do
			if c.alive then
				tickCreep(c, t, step)
			end
		end
	end)
end

return Creeps

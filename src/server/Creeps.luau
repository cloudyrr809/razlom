--!strict
-- Крипы: стоят на месте в лагерях-нишах у тропы. Мутации, реген, смерть, возрождение на своём месте.
-- Сервер владеет HP. Клиенты читают атрибуты модели: CreepId, Zone, Size, Mutation, Hp, MaxHp.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)

local notice = ReplicatedStorage.Remotes.Notice :: RemoteEvent

-- Место в лагере: на нём всегда стоит один крип или ждёт возрождения.
type Slot = { zone: number, size: number, cf: CFrame }

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
	slot: Slot,
	sentHp: number,
}

local Creeps = {}

local rng = Random.new()
local creeps: { [number]: Creep } = {}
local nextId = 0
local folder: Folder

local C = Config.Creeps
local W = Config.World

local function rollMutation(): number
	for i = #Config.CreepMutations, 1, -1 do
		if rng:NextNumber() < Config.CreepMutations[i].chance then
			return i
		end
	end
	return 0
end

local function spawnAt(slot: Slot)
	nextId += 1
	local s = C.Sizes[slot.size]
	local mutation = rollMutation()
	local maxHp = Formulas.creepMaxHp(slot.zone, slot.size, mutation)
	-- Каждый раз чуть иначе: сдвиг и поворот на месте.
	local J = Config.Camps
	local shift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * J.SlotJitter
	local cf = (slot.cf + shift + Vector3.new(0, W.GroundY + s.height / 2, 0)) * CFrame.Angles(0, math.rad(rng:NextNumber(-J.SlotTurn, J.SlotTurn)), 0)
	local model = Models.creep(slot.zone, slot.size, mutation, cf)
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true
	-- Целиком: клиенту для полоски и реакции нужны все детали сразу.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Creeps"
		end
	end

	model:SetAttribute("CreepId", nextId)
	model:SetAttribute("Zone", slot.zone)
	model:SetAttribute("Size", slot.size)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("MaxHp", maxHp)
	model:SetAttribute("Hp", maxHp)
	model.Parent = folder

	creeps[nextId] = {
		id = nextId,
		zone = slot.zone,
		size = slot.size,
		mutation = mutation,
		hp = maxHp,
		maxHp = maxHp,
		alive = true,
		model = model,
		root = root,
		slot = slot,
		sentHp = maxHp,
	}

	local m = Config.CreepMutations[mutation]
	if m and m.announce then
		notice:FireAllClients("announce", `{m.name} крип появился: {Config.Zones[slot.zone].name}!`)
	end
end

-- Публичное ------------------------------------------------------------------

function Creeps.get(id: number): Creep?
	return creeps[id]
end

-- Расстояние от точки до поверхности крипа по горизонтали.
local function gapTo(c: Creep, pos: Vector3): number
	return ((c.root.Position - pos) * Vector3.new(1, 0, 1)).Magnitude - C.Sizes[c.size].radius
end

function Creeps.inRange(c: Creep, pos: Vector3, radius: number): boolean
	return c.alive and gapTo(c, pos) <= radius
end

-- Наносит урон. Возвращает true, если крип умер. Награды раздаёт вызывающий.
function Creeps.damage(creep: Creep, amount: number): boolean
	if not creep.alive then
		return false
	end
	creep.hp -= amount
	if creep.hp > 0 then
		creep.model:SetAttribute("Hp", creep.hp)
		creep.sentHp = creep.hp
		return false
	end
	creep.alive = false
	creep.hp = 0
	creeps[creep.id] = nil
	creep.model:Destroy()
	task.delay(rng:NextNumber(C.RespawnMin, C.RespawnMax), spawnAt, creep.slot)
	return true
end

-- Цикл: только реген (стена урона работает только так) -------------------------

local function tickRegen(dt: number)
	for _, c in creeps do
		if c.alive and c.hp < c.maxHp then
			c.hp = math.min(c.maxHp, c.hp + Formulas.regenPerSecond(c.maxHp) * dt)
			if math.abs(c.hp - c.sentHp) >= c.maxHp * 0.005 or c.hp == c.maxHp then
				c.sentHp = c.hp
				c.model:SetAttribute("Hp", c.hp)
			end
		end
	end
end

function Creeps.start()
	folder = Instance.new("Folder")
	folder.Name = "Creeps"
	folder.Parent = Workspace

	local campsPerZone = table.create(#Config.Zones, 0)
	for _, camp in CollectionService:GetTagged("CreepCamp") do
		local zone = camp:GetAttribute("Zone")
		if camp:IsA("BasePart") and type(zone) == "number" and Config.Zones[zone] then
			campsPerZone[zone] += 1
			local center = CFrame.new(camp.Position.X, 0, camp.Position.Z) * camp.CFrame.Rotation
			for _, slot in Config.Camps.Slots do
				local pos = center:PointToWorldSpace(slot.offset)
				-- Каждый смотрит на тропу, как и сама ниша.
				spawnAt({ zone = zone, size = slot.size, cf = CFrame.new(pos) * center.Rotation })
			end
		end
	end
	for i, n in campsPerZone do
		if n == 0 then
			warn(`В зоне {i} нет лагерей CreepCamp. Запусти tools/build_map.luau.`)
		end
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= C.TickInterval then
			tickRegen(acc)
			acc = 0
		end
	end)
end

return Creeps

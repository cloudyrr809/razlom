--!strict
-- Сферы: склад, лишние на земле у базы, вскрытие кликами в гнезде, мутации, гарантия.
-- Результат вскрытия сервер выбирает в момент оплаты; клиент узнаёт его только на последнем ударе.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
local PlayerState = require(script.Parent.PlayerState)
local Bases = require(script.Parent.Bases)
local Inventory = require(script.Parent.Inventory)
local RateLimit = require(script.Parent.RateLimit)

local Remotes = ReplicatedStorage.Remotes
local openRemote = Remotes.OpenSphere :: RemoteEvent
local hitRemote = Remotes.RevealHit :: RemoteEvent
local revealFx = Remotes.RevealFx :: RemoteEvent
local notice = Remotes.Notice :: RemoteEvent

type Reveal = {
	owner: Player,
	sphere: PlayerState.Sphere,
	result: Formulas.Weapon,
	need: number,
	hits: number,
	model: Model,
}

local S = Config.Spheres
local Spheres = {}
local rng = Random.new()
local reveals: { [number]: { [number]: Reveal } } = {} -- [база][гнездо]
local openLimiter = RateLimit.new()
local hitLimiter = RateLimit.new()

local function near(player: Player, part: BasePart, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local d = root.Position - part.Position
	return Vector3.new(d.X, 0, d.Z).Magnitude <= range and math.abs(d.Y) <= 10
end

-- Лишние Сферы лежат кучкой у базы (видно до OverflowShown штук).
local function redrawOverflow(session: PlayerState.Session)
	local info = Bases.of(session)
	if not info then
		return
	end
	local old = info.model:FindFirstChild("OverflowSpheres")
	if old then
		old:Destroy()
	end
	if #session.overflow == 0 then
		return
	end
	local pile = Instance.new("Folder")
	pile.Name = "OverflowSpheres"
	for i, sphere in session.overflow do
		if i > S.OverflowShown then
			break
		end
		local ring = math.floor((i - 1) / 6)
		local a = (i - 1) * 1.05
		local offset = Vector3.new(math.cos(a) * (1.6 + ring * 2.2), 1.4 + ring * 0.8, math.sin(a) * (1.6 + ring * 2.2))
		local m = Models.sphere(sphere.zone, CFrame.new(info.overflow.Position + offset))
		m.Parent = pile
	end
	pile.Parent = info.model
end

local function refill(session: PlayerState.Session)
	local moved = false
	while #session.storage < S.StorageSize and #session.overflow > 0 do
		table.insert(session.storage, table.remove(session.overflow, 1) :: PlayerState.Sphere)
		moved = true
	end
	if moved then
		redrawOverflow(session)
	end
end

-- Добавляет Сферу игроку. Возвращает true, если она легла на склад, false — на землю у базы.
function Spheres.give(session: PlayerState.Session, zone: number, fromMutation: number): boolean
	local m = Config.CreepMutations[fromMutation]
	local minMutation = 0
	if fromMutation > 0 and session.firstMutantSphere then
		session.firstMutantSphere = false
		minMutation = Config.Spheres.FirstMutantMinMutation
	end
	local sphere: PlayerState.Sphere = {
		id = PlayerState.newId(session, "s"),
		zone = zone,
		boost = if m then m.weaponMutationBoost else 1,
		minMutation = minMutation,
		fromMutation = fromMutation,
	}
	PlayerState.markDirty(session, "spheres")
	if #session.storage < S.StorageSize then
		table.insert(session.storage, sphere)
		return true
	end
	table.insert(session.overflow, sphere)
	redrawOverflow(session)
	notice:FireClient(session.player, "storageFull")
	return false
end

local function rollWeapon(session: PlayerState.Session, sphere: PlayerState.Sphere): Formulas.Weapon
	local minRarity = if session.freeOpen then S.FirstOpenMinRarity else 1
	local outcomes: { EconomyMath.WeightedOutcome } = {}
	for i, r in Config.Rarities do
		if i >= minRarity then
			table.insert(outcomes, { id = tostring(i), weight = r.weight })
		end
	end
	local rarity = tonumber(EconomyMath.pickWeighted(outcomes, rng:NextNumber())) or 1

	-- Мутация: от редкой к частой, первая сработавшая побеждает.
	local mutation = 0
	local chances = Formulas.weaponMutationChances(sphere.boost)
	for i = #chances, 1, -1 do
		if rng:NextNumber() < chances[i] then
			mutation = i
			break
		end
	end
	local minMutation = sphere.minMutation
	if session.pity >= S.PityAfter then
		minMutation = math.max(minMutation, 1)
	end
	if mutation < minMutation then
		mutation = minMutation
	end
	if mutation > 0 then
		session.pity = 0
	else
		session.pity += 1
	end
	return { id = PlayerState.newId(session, "w"), zone = sphere.zone, rarity = rarity, mutation = mutation }
end

local function onOpen(player: Player, sphereId: unknown, nestIndex: unknown)
	local session = PlayerState.get(player)
	if not session or type(sphereId) ~= "string" or #sphereId > 24 then
		return
	end
	if type(nestIndex) ~= "number" or nestIndex ~= math.floor(nestIndex) or nestIndex < 1 or nestIndex > 3 then
		return
	end
	if not openLimiter.consume(player, 2, 3) then
		return
	end
	local info = Bases.of(session)
	if not info then
		return
	end
	local nest = info.nests[nestIndex]
	reveals[info.index] = reveals[info.index] or {}
	if reveals[info.index][nestIndex] or not near(player, nest, Config.Base.NestRange) then
		return
	end
	local slot: number? = nil
	for i, s in session.storage do
		if s.id == sphereId then
			slot = i
		end
	end
	if not slot then
		return
	end
	local sphere = session.storage[slot]

	-- Платим до любых ожиданий. Первое вскрытие бесплатное.
	if not session.freeOpen then
		if not EconomyMath.trySpend(session.wallet, { shards = Formulas.openPrice(sphere.zone) }) then
			return
		end
		PlayerState.markDirty(session, "wallet")
	end
	table.remove(session.storage, slot)
	local result = rollWeapon(session, sphere)
	session.freeOpen = false
	refill(session)
	PlayerState.markDirty(session, "spheres")

	local model = Models.sphere(sphere.zone, CFrame.new(nest.Position + Vector3.new(0, 2.4, 0)))
	model:SetAttribute("Owner", player.UserId)
	model.Parent = info.model
	local reveal: Reveal = {
		owner = player,
		sphere = sphere,
		result = result,
		need = rng:NextInteger(S.RevealHitsMin, S.RevealHitsMax),
		hits = 0,
		model = model,
	}
	reveals[info.index][nestIndex] = reveal
	revealFx:FireAllClients("start", info.index, nestIndex, { zone = sphere.zone, need = reveal.need, owner = player.UserId })
end

local function finish(session: PlayerState.Session, baseIndex: number, nestIndex: number, reveal: Reveal)
	reveals[baseIndex][nestIndex] = nil
	reveal.model:Destroy()
	Inventory.add(session, reveal.result)
	revealFx:FireAllClients("done", baseIndex, nestIndex, {
		owner = session.player.UserId,
		weapon = reveal.result,
	})
end

local function onHit(player: Player, nestIndex: unknown)
	local session = PlayerState.get(player)
	if not session or type(nestIndex) ~= "number" then
		return
	end
	local info = Bases.of(session)
	local list = info and reveals[info.index]
	local reveal = list and list[nestIndex]
	if not info or not reveal or reveal.owner ~= player then
		return
	end
	if not near(player, info.nests[nestIndex], Config.Base.NestRange) then
		return
	end
	if not hitLimiter.consume(player, S.RevealRate, 2) then
		return
	end
	reveal.hits += 1
	if reveal.hits >= reveal.need then
		finish(session, info.index, nestIndex, reveal)
	else
		revealFx:FireAllClients("crack", info.index, nestIndex, { hits = reveal.hits, need = reveal.need })
	end
end

function Spheres.start()
	openRemote.OnServerEvent:Connect(onOpen)
	hitRemote.OnServerEvent:Connect(onHit)
	PlayerState.onRemoving(function(session)
		openLimiter.forget(session.player)
		hitLimiter.forget(session.player)
		local info = Bases.of(session)
		if info then
			local list = reveals[info.index]
			if list then
				for k, reveal in list do
					reveal.model:Destroy()
					list[k] = nil
				end
			end
			local pile = info.model:FindFirstChild("OverflowSpheres")
			if pile then
				pile:Destroy()
			end
		end
	end)
end

return Spheres

--!strict
-- Сферы: падают в инвентарь (до 50), разбиваются бесплатно кликами по центру экрана.
-- Результат сервер выбирает в момент начала вскрытия; клиент узнаёт его только на последнем ударе.
-- Гарантии: первые 5 Сфер не слабее самого слабого в постаментах, Сфера с первого мутанта —
-- минимум Заряженная, 25 подряд без мутации — следующая с мутацией.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local PlayerState = require(script.Parent.PlayerState)
local Arsenal = require(script.Parent.Arsenal)
local RateLimit = require(script.Parent.RateLimit)

local Remotes = ReplicatedStorage.Remotes
local openRemote = Remotes.OpenSphere :: RemoteEvent
local hitRemote = Remotes.RevealHit :: RemoteEvent
local revealFx = Remotes.RevealFx :: RemoteEvent
local notice = Remotes.Notice :: RemoteEvent

type Reveal = { sphere: PlayerState.Sphere, result: Formulas.Weapon, need: number, hits: number }

local S = Config.Spheres
local Spheres = {}
local rng = Random.new()
local reveals: { [Player]: Reveal } = {}
local openLimiter = RateLimit.new()
local hitLimiter = RateLimit.new()

-- Кладёт Сферу в инвентарь. false — инвентарь Сфер полон.
function Spheres.give(session: PlayerState.Session, zone: number, fromMutation: number): boolean
	if #session.spheres >= S.MaxStored then
		notice:FireClient(session.player, "spheresFull")
		return false
	end
	local m = Config.CreepMutations[fromMutation]
	local minMutation = 0
	if fromMutation > 0 and session.firstMutantSphere then
		session.firstMutantSphere = false
		minMutation = S.FirstMutantMinMutation
	end
	table.insert(session.spheres, {
		id = PlayerState.newId(session, "s"),
		zone = zone,
		boost = if m then m.weaponMutationBoost else 1,
		minMutation = minMutation,
		fromMutation = fromMutation,
	})
	PlayerState.markDirty(session, "spheres")
	return true
end

function Spheres.isFull(session: PlayerState.Session): boolean
	return #session.spheres >= S.MaxStored
end

local function rollWeapon(session: PlayerState.Session, sphere: PlayerState.Sphere): Formulas.Weapon
	-- Гарантия первых Сфер: не слабее самого слабого в постаментах (если они заполнены).
	local minRarity = 1
	if session.opened < S.GuaranteedFirst then
		local weakest = Arsenal.weakest(session)
		minRarity = #Config.Rarities
		for r = 1, #Config.Rarities do
			local probe: Formulas.Weapon = { id = "", zone = sphere.zone, rarity = r, mutation = 0 }
			if Formulas.weaponDamage(probe) >= weakest then
				minRarity = r
				break
			end
		end
	end
	local outcomes: { EconomyMath.WeightedOutcome } = {}
	for i, r in Config.Rarities do
		if i >= minRarity then
			table.insert(outcomes, { id = tostring(i), weight = r.weight })
		end
	end
	local rarity = tonumber(EconomyMath.pickWeighted(outcomes, rng:NextNumber())) or minRarity

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
	mutation = math.max(mutation, minMutation)
	session.pity = if mutation > 0 then 0 else session.pity + 1
	return { id = PlayerState.newId(session, "w"), zone = sphere.zone, rarity = rarity, mutation = mutation }
end

local function sendStart(player: Player, reveal: Reveal, session: PlayerState.Session)
	revealFx:FireClient(player, "start", {
		zone = reveal.sphere.zone,
		need = reveal.need,
		hits = reveal.hits,
		fromMutation = reveal.sphere.fromMutation,
		left = #session.spheres,
	})
end

-- «Открыть»: берём первую Сферу из инвентаря. Если вскрытие уже идёт — продолжаем его.
local function onOpen(player: Player)
	local session = PlayerState.get(player)
	if not session or not openLimiter.consume(player, 3, 3) then
		return
	end
	local current = reveals[player]
	if current then
		sendStart(player, current, session)
		return
	end
	if #session.spheres == 0 then
		return
	end
	if Arsenal.isFull(session) then
		notice:FireClient(player, "weaponsFull")
		return
	end
	local sphere = table.remove(session.spheres, 1) :: PlayerState.Sphere
	local reveal: Reveal = {
		sphere = sphere,
		result = rollWeapon(session, sphere),
		need = rng:NextInteger(S.RevealHitsMin, S.RevealHitsMax),
		hits = 0,
	}
	session.opened += 1
	reveals[player] = reveal
	PlayerState.markDirty(session, "spheres")
	sendStart(player, reveal, session)
end

local function onHit(player: Player)
	local session = PlayerState.get(player)
	local reveal = reveals[player]
	if not session or not reveal or not hitLimiter.consume(player, S.RevealRate, 2) then
		return
	end
	reveal.hits += 1
	if reveal.hits < reveal.need then
		revealFx:FireClient(player, "crack", { hits = reveal.hits, need = reveal.need })
		return
	end
	reveals[player] = nil
	local w = reveal.result
	local gain = Arsenal.gainOf(session, w)
	Arsenal.add(session, w)
	revealFx:FireClient(player, "done", { weapon = w, gain = gain, left = #session.spheres })
	-- Редкое видно всему серверу (полный столб света — Шаг 2).
	if w.mutation >= 2 then
		notice:FireAllClients("announce", `{player.DisplayName} выбил: {Formulas.weaponName(w)}!`)
	end
end

function Spheres.start()
	openRemote.OnServerEvent:Connect(onOpen)
	hitRemote.OnServerEvent:Connect(onHit)
	PlayerState.onRemoving(function(session)
		openLimiter.forget(session.player)
		hitLimiter.forget(session.player)
		reveals[session.player] = nil
	end)
end

return Spheres

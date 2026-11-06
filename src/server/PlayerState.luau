--!strict
-- Данные игрока на время сессии. Сохранение — в Шаге 3.
-- Клиенту уходят разделы, которые изменились (не чаще Config.Net.StateFlushInterval).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)

local stateRemote = ReplicatedStorage.Remotes.State :: RemoteEvent

export type Weapon = Formulas.Weapon
export type Sphere = {
	id: string,
	zone: number,
	boost: number, -- множитель шанса мутации оружия
	minMutation: number, -- 0 — без гарантии
	fromMutation: number, -- мутация крипа, с которого упала
}
export type Section = "wallet" | "levels" | "spheres" | "arsenal" | "monolith" | "base"

export type Session = {
	player: Player,
	wallet: { [string]: number }, -- wallet.shards
	ring: number,
	aura: number,
	openZones: number,
	zoneKills: { [number]: number },
	seenZones: { [number]: boolean },
	zone: number, -- 0 — не на дороге
	weapons: { Weapon }, -- всё оружие, включая вставленное
	pedestals: { string }, -- id оружия по номеру постамента; "" — пусто
	hand: string, -- id оружия в руке (только вид)
	spheres: { Sphere },
	opened: number, -- сколько Сфер вскрыто всего
	pity: number, -- Сфер подряд без мутации
	firstLargeSphere: boolean, -- гарантия Сферы с первого Крупного ещё не использована
	firstMutantSphere: boolean, -- гарантия мутации со Сферы первого мутанта ещё не использована
	monolithLevel: number,
	monolithProgress: number, -- осколков влито в текущий уровень
	streak: number, -- ступени серии убийств
	lastKill: number,
	baseIndex: number?,
	nextId: number,
	dirty: { [string]: boolean },
}

local PlayerState = {}

local sessions: { [Player]: Session } = {}
local added: { (Session) -> () } = {}
local removing: { (Session) -> () } = {}

function PlayerState.get(player: Player): Session?
	return sessions[player]
end

function PlayerState.all(): { [Player]: Session }
	return sessions
end

function PlayerState.onAdded(fn: (Session) -> ())
	table.insert(added, fn)
end

function PlayerState.onRemoving(fn: (Session) -> ())
	table.insert(removing, fn)
end

function PlayerState.newId(session: Session, prefix: string): string
	session.nextId += 1
	return prefix .. session.nextId
end

function PlayerState.markDirty(session: Session, section: Section)
	session.dirty[section] = true
end

function PlayerState.weapon(session: Session, id: string): Weapon?
	for _, w in session.weapons do
		if w.id == id then
			return w
		end
	end
	return nil
end

-- Открытые зоны растут, когда игрок добивает первых крипов зоны.
function PlayerState.addZoneKill(session: Session, zone: number): boolean
	session.zoneKills[zone] = (session.zoneKills[zone] or 0) + 1
	if zone > session.openZones and session.zoneKills[zone] >= Config.ZoneUnlock.KillsToOpen then
		session.openZones = zone
		PlayerState.markDirty(session, "levels")
		return true
	end
	return false
end

local function snapshot(session: Session, section: string): any
	if section == "wallet" then
		return { shards = session.wallet.shards }
	elseif section == "levels" then
		return { ring = session.ring, aura = session.aura, openZones = session.openZones }
	elseif section == "spheres" then
		return { spheres = session.spheres, pity = session.pity, opened = session.opened }
	elseif section == "arsenal" then
		return { weapons = session.weapons, pedestals = session.pedestals, hand = session.hand }
	elseif section == "monolith" then
		return { monolithLevel = session.monolithLevel, monolithProgress = session.monolithProgress }
	else
		return { baseIndex = session.baseIndex }
	end
end

local function create(player: Player)
	local slots = {}
	for i = 1, Formulas.pedestalCount(0) do
		slots[i] = ""
	end
	slots[1] = "starter" -- тренировочный меч сразу стоит в первом постаменте
	local session: Session = {
		player = player,
		wallet = { shards = 0 },
		ring = 0,
		aura = 0,
		openZones = 1,
		zoneKills = {},
		seenZones = {},
		zone = 0,
		weapons = { { id = "starter", zone = 1, rarity = 1, mutation = 0 } },
		pedestals = slots,
		hand = "starter",
		spheres = {},
		opened = 0,
		pity = 0,
		firstLargeSphere = Config.Spheres.FirstLargeGivesSphere,
		firstMutantSphere = Config.Spheres.FirstMutantMinMutation > 0,
		monolithLevel = 0,
		monolithProgress = 0,
		streak = 0,
		lastKill = -math.huge,
		baseIndex = nil,
		nextId = 0,
		dirty = { wallet = true, levels = true, spheres = true, arsenal = true, monolith = true, base = true },
	}
	sessions[player] = session
	for _, fn in added do
		fn(session)
	end
end

function PlayerState.start()
	Players.PlayerAdded:Connect(create)
	for _, p in Players:GetPlayers() do
		if not sessions[p] then
			create(p)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if not session then
			return
		end
		for _, fn in removing do
			fn(session)
		end
		sessions[player] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < Config.Net.StateFlushInterval then
			return
		end
		acc = 0
		for player, session in sessions do
			for section in session.dirty do
				stateRemote:FireClient(player, section, snapshot(session, section))
			end
			table.clear(session.dirty)
		end
	end)
end

return PlayerState

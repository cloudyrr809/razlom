--!strict
-- Копия данных игрока, которую присылает сервер. Только для показа: решает всё сервер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)

export type Sphere = { id: string, zone: number, boost: number, minMutation: number, fromMutation: number }
export type Data = {
	shards: number,
	ring: number,
	aura: number,
	openZones: number,
	spheres: { Sphere },
	pity: number,
	opened: number,
	weapons: { Formulas.Weapon },
	pedestals: { string },
	hand: string,
	monolithLevel: number,
	monolithProgress: number,
	baseIndex: number?,
}

local Store = {}

Store.data = {
	shards = 0,
	ring = 0,
	aura = 0,
	openZones = 1,
	spheres = {},
	pity = 0,
	opened = 0,
	weapons = { { id = "starter", zone = 1, rarity = 1, mutation = 0 } },
	pedestals = { "starter", "", "" },
	hand = "starter",
	monolithLevel = 0,
	monolithProgress = 0,
	baseIndex = nil,
} :: Data

local listeners: { (section: string) -> () } = {}

function Store.onChanged(fn: (section: string) -> ())
	table.insert(listeners, fn)
end

function Store.emit(section: string)
	for _, fn in listeners do
		task.spawn(fn, section)
	end
end

function Store.weapon(id: string): Formulas.Weapon?
	for _, w in Store.data.weapons do
		if w.id == id then
			return w
		end
	end
	return nil
end

function Store.handWeapon(): Formulas.Weapon
	return Store.weapon(Store.data.hand) or Store.data.weapons[1]
end

function Store.inPedestal(id: string): boolean
	return table.find(Store.data.pedestals, id) ~= nil
end

-- Сумма урона оружия в постаментах.
function Store.arsenal(): number
	local sum = 0
	for _, id in Store.data.pedestals do
		local w = if id ~= "" then Store.weapon(id) else nil
		if w then
			sum += Formulas.weaponDamage(w)
		end
	end
	return sum
end

-- Урон самого слабого в постаментах; 0, если есть пустой.
function Store.weakest(): number
	local weakest = math.huge
	for _, id in Store.data.pedestals do
		local w = if id ~= "" then Store.weapon(id) else nil
		if not w then
			return 0
		end
		weakest = math.min(weakest, Formulas.weaponDamage(w))
	end
	return if weakest == math.huge then 0 else weakest
end

-- Есть ли вне постаментов оружие сильнее самого слабого вставленного (повод бежать на базу).
function Store.betterWaiting(): boolean
	local weakest = Store.weakest()
	for _, w in Store.data.weapons do
		if not Store.inPedestal(w.id) and Formulas.weaponDamage(w) > weakest then
			return true
		end
	end
	return false
end

function Store.hitDamage(): number
	return Formulas.hitDamage(Store.arsenal(), Store.data.monolithLevel, 0)
end

-- Урон в секунду игрока (для замка «до пробоя»).
function Store.dps(): number
	return Formulas.dps(Store.hitDamage(), Formulas.hitsPerSecond(Store.data.ring))
end

function Store.start()
	local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("State") :: RemoteEvent
	remote.OnClientEvent:Connect(function(section: string, payload: any)
		local d = Store.data :: any
		for k, v in payload do
			d[k] = v
		end
		if section == "base" then
			d.baseIndex = payload.baseIndex
		end
		Store.emit(section)
	end)
end

return Store

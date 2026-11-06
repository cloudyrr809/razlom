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
	storage: { Sphere },
	overflow: number,
	pity: number,
	freeOpen: boolean,
	weapons: { Formulas.Weapon },
	equipped: string,
	baseIndex: number?,
}

local Store = {}

Store.data = {
	shards = 0,
	ring = 0,
	aura = 0,
	openZones = 1,
	storage = {},
	overflow = 0,
	pity = 0,
	freeOpen = true,
	weapons = { { id = "starter", zone = 1, rarity = 1, mutation = 0 } },
	equipped = "starter",
	baseIndex = nil,
} :: Data

-- Идущие вскрытия в гнёздах своей базы: [гнездо] = { hits, need }.
Store.reveals = {} :: { [number]: { hits: number, need: number } }

local listeners: { (section: string) -> () } = {}

function Store.onChanged(fn: (section: string) -> ())
	table.insert(listeners, fn)
end

function Store.emit(section: string)
	for _, fn in listeners do
		task.spawn(fn, section)
	end
end

function Store.equippedWeapon(): Formulas.Weapon
	for _, w in Store.data.weapons do
		if w.id == Store.data.equipped then
			return w
		end
	end
	return Store.data.weapons[1]
end

-- Урон в секунду игрока (для замка «до пробоя»).
function Store.dps(): number
	local w = Store.equippedWeapon()
	return Formulas.dps(Formulas.weaponDamage(w) * Formulas.damageBonus(0), Formulas.hitsPerSecond(Store.data.ring))
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

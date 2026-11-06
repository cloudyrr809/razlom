--!strict
-- Формулы игры. Чистые функции без сервисов: одинаково считают и сервер, и клиент.
-- Сервер по ним решает, клиент — только показывает.

local Config = require(script.Parent.Config)
local EconomyMath = require(script.Parent.EconomyMath)

local Formulas = {}

export type Weapon = { id: string, zone: number, rarity: number, mutation: number }
export type UpgradeId = "Ring" | "Aura"

local function zoneOf(zone: number)
	local z = Config.Zones[zone]
	assert(z, "нет зоны " .. tostring(zone))
	return z
end

-- Крипы ---------------------------------------------------------------------

function Formulas.creepMaxHp(zone: number, size: number, mutation: number): number
	local s = Config.Creeps.Sizes[size]
	local m = Config.CreepMutations[mutation]
	return Config.Creeps.BaseHp * zoneOf(zone).hpMult * s.hpUnits * (if m then m.hp else 1)
end

function Formulas.creepShards(zone: number, size: number, mutation: number): number
	local s = Config.Creeps.Sizes[size]
	local m = Config.CreepMutations[mutation]
	return s.reward * zoneOf(zone).rewardMult * (if m then m.shards else 1)
end

-- Сколько HP в секунду восстанавливает крип.
function Formulas.regenPerSecond(maxHp: number): number
	return maxHp * Config.Creeps.RegenPerSecond
end

-- Шанс Сферы с крипа (без учёта гарантий первого Крупного).
function Formulas.sphereChance(size: number, mutation: number): number
	local m = Config.CreepMutations[mutation]
	if m and m.guaranteedSphere then
		return 1
	end
	local chance = Config.Creeps.Sizes[size].sphereChance * (if m then m.sphereChanceMult else 1)
	return math.min(chance, 1)
end

-- Оружие --------------------------------------------------------------------

function Formulas.weaponDamage(w: Weapon): number
	local base = Config.WeaponDamage[w.zone][w.rarity]
	local m = Config.WeaponMutations[w.mutation]
	return base * (if m then m.mult else 1)
end

function Formulas.weaponName(w: Weapon): string
	if w.id == "starter" then
		return Config.StarterWeaponName
	end
	local r = Config.Rarities[w.rarity]
	local m = Config.WeaponMutations[w.mutation]
	if not m then
		return r.weapon
	end
	return (if r.weaponFem then m.nameFem else m.name) .. " " .. string.lower(r.weapon)
end

-- Общий множитель урона. В Шаге 2 сюда добавятся индекс и уровень Монолита.
function Formulas.damageBonus(bonusPercent: number): number
	return 1 + bonusPercent / 100
end

-- Средний вклад критов в урон: 1 + шанс × (множитель − 1). При 10% и ×3 это 1,2.
function Formulas.averageCritFactor(): number
	return 1 + Config.Combat.CritChance * (Config.Combat.CritMult - 1)
end

function Formulas.dps(damagePerHit: number, hitsPerSecond: number): number
	return damagePerHit * hitsPerSecond * Formulas.averageCritFactor()
end

-- Улучшения -----------------------------------------------------------------

function Formulas.hitsPerSecond(ringLevel: number): number
	local u = Config.Upgrades.Ring
	return u.start + u.perLevel * ringLevel
end

function Formulas.walkSpeed(auraLevel: number): number
	local u = Config.Upgrades.Aura
	return u.start + u.perLevel * auraLevel
end

function Formulas.upgradeCap(id: UpgradeId, openZones: number): number
	return Config.Upgrades[id].capPerZone * openZones
end

function Formulas.upgradeCost(id: UpgradeId, owned: number): number
	local u = Config.Upgrades[id]
	return EconomyMath.levelCost(u.baseCost, u.costGrowth, owned)
end

-- Сколько уровней можно купить сразу и за сколько.
function Formulas.upgradeMax(id: UpgradeId, owned: number, money: number, openZones: number): (number, number)
	local u = Config.Upgrades[id]
	return EconomyMath.maxAffordable(u.baseCost, u.costGrowth, owned, money, Formulas.upgradeCap(id, openZones))
end

-- Сферы ---------------------------------------------------------------------

function Formulas.openPrice(zone: number): number
	local s = Config.Spheres
	return s.OpenBase * s.OpenGrowth ^ (zone - 1)
end

-- Шансы мутации оружия в Сфере с данным усилением: [номер мутации] = шанс.
function Formulas.weaponMutationChances(boost: number): { number }
	local out = {}
	for i, m in Config.WeaponMutations do
		out[i] = math.min(m.chance * boost, 1)
	end
	return out
end

-- Итоговая вероятность каждого исхода мутации при проверке «от редкой к частой».
-- [0] = без мутации. Сумма ровно 1.
function Formulas.weaponMutationOdds(boost: number): { [number]: number }
	local chances = Formulas.weaponMutationChances(boost)
	local odds: { [number]: number } = {}
	local remaining = 1
	for i = #chances, 1, -1 do
		odds[i] = remaining * chances[i]
		remaining -= odds[i]
	end
	odds[0] = remaining
	return odds
end

-- Мир -----------------------------------------------------------------------

-- Номер зоны по позиции, 0 — не на дороге.
function Formulas.zoneAt(pos: Vector3): number
	local W = Config.World
	if math.abs(pos.Z) > W.RoadHalfWidth + W.ZoneSideSlack then
		return 0
	end
	for i, z in Config.Zones do
		if pos.X >= z.xStart and pos.X < z.xEnd then
			return i
		end
	end
	return 0
end

-- Числа на экране -----------------------------------------------------------

-- 12400 → «12,4K». Округление до выбора суффикса делает EconomyMath.
function Formulas.short(value: number): string
	if value < 1000 then
		local rounded = math.floor(value * 10 + 0.5) / 10
		local text = if rounded == math.floor(rounded) then tostring(math.floor(rounded)) else string.format("%.1f", rounded)
		return (string.gsub(text, "%.", ","))
	end
	return (string.gsub(EconomyMath.formatNumber(value, 1), "%.", ","))
end

return Formulas

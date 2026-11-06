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
	local z = zoneOf(zone)
	local sizeMult = z.sizeHpMult[size] or 1
	return Config.Creeps.BaseHp * z.hpMult * s.hpUnits * sizeMult * (if m then m.hp else 1)
end

function Formulas.creepShards(zone: number, size: number, mutation: number): number
	local s = Config.Creeps.Sizes[size]
	local m = Config.CreepMutations[mutation]
	local z = zoneOf(zone)
	return s.reward * Config.Creeps.ShardGrowth ^ (zone - 1) * z.shardBonus * (if m then m.shards else 1)
end

-- Сколько HP в секунду восстанавливает крип.
function Formulas.regenPerSecond(maxHp: number): number
	return maxHp * Config.Creeps.RegenPerSecond
end

-- Шанс Сферы с крипа (без учёта гарантии первого Крупного).
function Formulas.sphereChance(zone: number, size: number, mutation: number): number
	local m = Config.CreepMutations[mutation]
	if m and m.guaranteedSphere then
		return 1
	end
	local chance = Config.Creeps.Sizes[size].sphereChance * zoneOf(zone).sphereBonus * (if m then m.sphereChanceMult else 1)
	return math.min(chance, 1)
end

-- Оружие --------------------------------------------------------------------

function Formulas.weaponDamage(w: Weapon): number
	local base = Config.Weapons.ZoneGrowth ^ (w.zone - 1) * Config.Rarities[w.rarity].mult
	local m = Config.WeaponMutations[w.mutation]
	return base * (if m then m.mult else 1)
end

function Formulas.weaponName(w: Weapon): string
	if w.id == "starter" then
		return Config.Weapons.StarterName
	end
	local r = Config.Rarities[w.rarity]
	local m = Config.WeaponMutations[w.mutation]
	if not m then
		return r.weapon
	end
	return (if r.weaponFem then m.nameFem else m.name) .. " " .. string.lower(r.weapon)
end

-- Множитель урона: 1 + индекс% + уровень Монолита × 2%.
function Formulas.damageBonus(monolithLevel: number, indexPercent: number): number
	return 1 + indexPercent / 100 + monolithLevel * Config.Monolith.DamagePerLevel
end

-- Урон одного удара (без крита) по сумме урона оружия в постаментах.
function Formulas.hitDamage(arsenal: number, monolithLevel: number, indexPercent: number): number
	return arsenal * Formulas.damageBonus(monolithLevel, indexPercent)
end

-- Сколько прогресса Монолиту даёт скормленное оружие (в осколках).
function Formulas.feedValue(w: Weapon): number
	local m = Config.WeaponMutations[w.mutation]
	return Config.Monolith.FeedMult * Formulas.creepShards(w.zone, 2, 0) * Config.Rarities[w.rarity].mult * (if m then m.mult else 1)
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

-- Монолит и серия --------------------------------------------------------

function Formulas.monolithCost(level: number): number
	local m = Config.Monolith
	return EconomyMath.levelCost(m.BaseCost, m.CostGrowth, level)
end

function Formulas.pedestalCount(monolithLevel: number): number
	local m = Config.Monolith
	return math.min(m.MaxPedestals, m.BasePedestals + math.floor(monolithLevel / m.LevelsPerTier))
end

function Formulas.tier(monolithLevel: number): number
	return math.floor(monolithLevel / Config.Monolith.LevelsPerTier) + 1
end

-- Множитель осколков от серии убийств: 1 + 5% за ступень, до ×2.
function Formulas.streakMult(steps: number): number
	local s = Config.Streak
	return 1 + s.StepBonus * math.clamp(steps, 0, s.MaxSteps)
end

-- Сферы -----------------------------------------------------------------------

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
-- Z середины тропы в точке X (сумма волн, на входе X = RoadStart.X — ровно 0).
function Formulas.pathZ(x: number): number
	local W = Config.World
	local t = x - W.RoadStart.X
	local z = 0
	for _, w in W.PathWaves do
		z += w.amp * math.sin(t / w.length * math.pi * 2)
	end
	return z
end

function Formulas.zoneAt(pos: Vector3): number
	local W = Config.World
	if math.abs(pos.Z - Formulas.pathZ(pos.X)) > W.RoadHalfWidth + W.ZoneSideSlack then
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

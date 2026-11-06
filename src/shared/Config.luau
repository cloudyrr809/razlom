--!strict
-- Все числа игры в одном месте. Читают и сервер, и клиент.
-- В логике чисел нет: если число надо поменять — меняй здесь.
-- Источник: раздел «Баланс» дизайн-документа (Шаг 1.5).

local Config = {}

-- Мир. Дорога идёт вдоль оси X, середина дороги — Z = 0, земля — Y = 0.
Config.World = {
	RoadHalfWidth = 25, -- половина ширины дороги
	GroundY = 0, -- верх песка
	CreepEdgeMargin = 3, -- насколько крипы держатся от края дороги
	ZoneTrackInterval = 0.25, -- как часто сервер смотрит, кто в какой зоне, сек
	ZoneSideSlack = 12, -- насколько за краем дороги игрок ещё считается «в зоне»
	-- Вход в зону 1 (портал). Все базы стоят на дуге вокруг него на одном расстоянии.
	RoadStart = Vector3.new(30, 0, 0),
	BaseRingRadius = 118, -- от входа до центра каждой базы
	BaseArcFrom = 98, -- дуга баз, градусы (0 — вдоль дороги, 180 — прямо за входом)
	BaseArcTo = 262,
	BaseRadius = 22,
	BaseHeight = 5,
	PlazaCenter = Vector3.new(-28, 0, 0),
	PlazaRadius = 26,
}

-- Зоны. hpMult — множитель HP к зоне 1.
-- shardBonus и sphereBonus — «пир» зоны 1: осколки ×3, шанс Сферы ×2.
Config.Zones = {
	{ name = "Светлые дюны", xStart = 30, xEnd = 180, hpMult = 1, shardBonus = 3, sphereBonus = 2 },
	{ name = "Ржавый каньон", xStart = 180, xEnd = 330, hpMult = 70, shardBonus = 1, sphereBonus = 1 },
}
-- Множители HP будущих зон (для расчётов и следующих обновлений): 1 / 70 / 2100 / 31500 / 504000.
Config.FutureZoneHpMult = { 1, 70, 2100, 31500, 504000 }

-- Зона открыта для игрока, когда он добил в ней первого крипа (пробежать через врата мало).
Config.ZoneUnlock = {
	KillsToOpen = 1,
}

-- Крипы. HP = BaseHp × hpMult зоны × hpUnits.
-- Осколки = reward × ShardGrowth^(зона − 1) × shardBonus зоны.
Config.Creeps = {
	BaseHp = 4,
	ShardGrowth = 8,
	RegenPerSecond = 0.04, -- доля максимального HP в секунду, идёт всегда
	InCombatTime = 1.5, -- сколько секунд после удара крип считается «в бою» (для полоски)
	TickInterval = 0.1, -- шаг серверного цикла крипов, сек
	BasePerZone = 20, -- крипов в зоне всегда
	PerPlayerInZone = 8, -- плюс за каждого игрока в зоне
	RespawnMin = 3,
	RespawnMax = 5,
	SpawnPerSecond = 6, -- сколько новых крипов зона выпускает в секунду, пока не наберёт норму
	FlockMin = 3,
	FlockMax = 5,
	Sizes = {
		{
			id = "Small",
			name = "Малый",
			hpUnits = 1,
			reward = 1,
			sphereChance = 0.02,
			share = 0.5,
			radius = 1.4, -- радиус для дистанции удара и размер модели, стады
			height = 2.6,
			speed = 7,
			fleeSpeed = 14,
			fleeTime = 2,
			knockback = 16, -- скорость отброса от удара, стад/с
		},
		{
			id = "Medium",
			name = "Средний",
			hpUnits = 3,
			reward = 4,
			sphereChance = 0.04,
			share = 0.35,
			radius = 2.4,
			height = 4.2,
			speed = 0,
			fleeSpeed = 0,
			fleeTime = 0,
			knockback = 10,
		},
		{
			id = "Large",
			name = "Крупный",
			hpUnits = 8,
			reward = 11,
			sphereChance = 0.08,
			share = 0.15,
			radius = 4,
			height = 7,
			speed = 3,
			fleeSpeed = 0,
			fleeTime = 0,
			knockback = 5,
		},
	},
	KnockbackTime = 0.12, -- сколько длится отброс, сек
	WanderEveryMin = 3, -- как часто бродячие крипы выбирают новую точку, сек
	WanderEveryMax = 7,
	WanderDistance = 18,
	FlockSpread = 4, -- разброс малых вокруг центра стайки
}

-- Мутации крипов. Проверяются от редкой к частой: первая сработавшая побеждает.
-- sphereChanceMult — множитель шанса Сферы; guaranteedSphere — Сфера всегда;
-- weaponMutationBoost — во сколько раз чаще мутация оружия в этой Сфере.
Config.CreepMutations = {
	{ id = "Charged", name = "Заряженный", chance = 1 / 10, hp = 2, shards = 3, sphereChanceMult = 3, guaranteedSphere = false, weaponMutationBoost = 1, announce = false, pointer = false },
	{ id = "Golden", name = "Золотой", chance = 1 / 100, hp = 5, shards = 10, sphereChanceMult = 1, guaranteedSphere = true, weaponMutationBoost = 1, announce = false, pointer = true },
	{ id = "Prismatic", name = "Призматический", chance = 1 / 1000, hp = 10, shards = 25, sphereChanceMult = 1, guaranteedSphere = true, weaponMutationBoost = 5, announce = false, pointer = true },
	{ id = "Void", name = "Пустотный", chance = 1 / 10000, hp = 20, shards = 50, sphereChanceMult = 1, guaranteedSphere = true, weaponMutationBoost = 20, announce = true, pointer = true },
}

-- Бой.
Config.Combat = {
	HitRadius = 10, -- от игрока до поверхности крипа, стады
	CritChance = 0.1,
	CritMult = 3,
	HitBurst = 2, -- сколько ударов можно «накопить» на случай сетевых рывков
}

-- Серия убийств: убийство быстрее Window секунд после прошлого — серия +1.
-- Каждая ступень +StepBonus к осколкам, не больше MaxSteps ступеней (×2).
Config.Streak = {
	Window = 2,
	StepBonus = 0.05,
	MaxSteps = 20,
}

-- Оружие. Урон = ZoneGrowth^(зона − 1) × множитель редкости × множитель мутации.
-- weaponFem — род названия («Коса» — женский).
Config.Rarities = {
	{ id = "Common", name = "Обычное", weapon = "Меч", weaponFem = false, weight = 60, mult = 1 },
	{ id = "Uncommon", name = "Необычное", weapon = "Топор", weaponFem = false, weight = 25, mult = 2 },
	{ id = "Rare", name = "Редкое", weapon = "Посох", weaponFem = false, weight = 10, mult = 4 },
	{ id = "Epic", name = "Эпическое", weapon = "Молот", weaponFem = false, weight = 4, mult = 8 },
	{ id = "Legendary", name = "Легендарное", weapon = "Коса", weaponFem = true, weight = 1, mult = 16 },
}
Config.Weapons = {
	ZoneGrowth = 7,
	MaxInventory = 100, -- всего оружия у игрока, вместе с постаментами
	StarterName = "Тренировочный меч",
}

-- Мутации оружия. chance — для обычной Сферы.
Config.WeaponMutations = {
	{ id = "Charged", name = "Заряженный", nameFem = "Заряженная", mult = 1.5, chance = 0.05 },
	{ id = "Golden", name = "Золотой", nameFem = "Золотая", mult = 2.5, chance = 0.005 },
	{ id = "Prismatic", name = "Призматический", nameFem = "Призматическая", mult = 5, chance = 0.0005 },
	{ id = "Void", name = "Пустотный", nameFem = "Пустотная", mult = 10, chance = 0.00004 },
}

-- Сферы: падают в инвентарь, разбиваются бесплатно кликами по центру экрана.
Config.Spheres = {
	MaxStored = 50,
	RevealHitsMin = 8,
	RevealHitsMax = 10,
	TeaseFromHit = 4, -- с какого удара свет перебирает цвета редкости
	RevealRate = 6, -- ударов по Сфере в секунду максимум
	PityAfter = 25, -- столько Сфер подряд без мутации — следующая с мутацией
	GuaranteedFirst = 5, -- первые столько Сфер не слабее самого слабого в постаментах
	FirstLargeGivesSphere = true, -- первый убитый Крупный — Сфера гарантированно
	FirstMutantMinMutation = 1, -- Сфера с первого мутанта — минимум Заряженное
}

-- Монолит и постаменты.
-- Цена уровня = BaseCost × CostGrowth^уровень (без потолка).
-- Постаментов = BasePedestals + floor(уровень / LevelsPerTier), не больше MaxPedestals.
-- Урон удара = сумма урона оружия в постаментах × (1 + индекс% + уровень × DamagePerLevel).
Config.Monolith = {
	BaseCost = 30,
	CostGrowth = 1.23,
	DamagePerLevel = 0.02,
	LevelsPerTier = 10,
	BasePedestals = 3,
	MaxPedestals = 10,
	-- Скармливание: FeedMult × награда Среднего крипа зоны оружия × редкость × мутация.
	FeedMult = 5,
	-- Ковка в АФК (Шаг 2): доля дохода на дороге, идёт в Монолит.
	ForgeShare = 0.4,
	Range = 20, -- от центра Монолита, чтобы вставлять оружие и вливать осколки
}

-- Улучшения. Цена уровня = baseCost × costGrowth^куплено.
-- Потолок = capPerZone × число открытых зон. Покупаются из интерфейса где угодно.
Config.Upgrades = {
	Ring = {
		name = "Кольцо",
		baseCost = 10,
		costGrowth = 1.23,
		capPerZone = 10,
		start = 2.5, -- ударов в секунду на старте
		perLevel = 0.15,
		lookEvery = 10, -- каждые 10 уровней новый вид
	},
	Aura = {
		name = "Аура",
		baseCost = 20,
		costGrowth = 1.414,
		capPerZone = 6,
		start = 16, -- скорость бега на старте
		perLevel = 0.6,
		lookEvery = 10,
	},
}

Config.Base = {
	Count = 8,
}

-- Ощущение удара (только клиент).
Config.Juice = {
	HitStop = 0.05, -- замирание на попадании, сек
	MagnetTime = 0.75, -- за сколько осколки долетают до игрока
}

-- Отправка данных игроку.
Config.Net = {
	StateFlushInterval = 0.1, -- не чаще, чем раз в столько секунд на раздел
}

return Config

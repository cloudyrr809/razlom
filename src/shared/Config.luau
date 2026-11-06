--!strict
-- Все числа игры в одном месте. Читают и сервер, и клиент.
-- В логике чисел нет: если число надо поменять — меняй здесь.
-- Источник: раздел «Баланс» дизайн-документа.

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

-- Зоны. hpMult и rewardMult — множители к зоне 1.
Config.Zones = {
	{
		name = "Светлые дюны",
		xStart = 30,
		xEnd = 180,
		hpMult = 1,
		rewardMult = 1,
	},
	{
		name = "Ржавый каньон",
		xStart = 180,
		xEnd = 330,
		hpMult = 7,
		rewardMult = 8,
	},
}

-- Зона считается открытой для игрока, когда он добил в ней первого крипа.
-- Просто пробежать через врата мало.
Config.ZoneUnlock = {
	KillsToOpen = 1,
}

-- Крипы трёх размеров. HP = BaseHp × hpMult зоны × hpUnits.
-- Осколки = reward × rewardMult зоны.
Config.Creeps = {
	BaseHp = 4,
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
		},
	},
	WanderEveryMin = 3, -- как часто бродячие крипы выбирают новую точку, сек
	WanderEveryMax = 7,
	WanderDistance = 18,
	FlockSpread = 4, -- разброс малых вокруг центра стайки
}

-- Мутации крипов. Проверяются от редкой к частой: первая сработавшая побеждает.
-- sphereChanceMult — множитель шанса Сферы; guaranteedSphere — Сфера всегда;
-- weaponMutationBoost — во сколько раз чаще мутация оружия в этой Сфере.
Config.CreepMutations = {
	{
		id = "Charged",
		name = "Заряженный",
		chance = 1 / 10,
		hp = 2,
		shards = 3,
		sphereChanceMult = 3,
		guaranteedSphere = false,
		weaponMutationBoost = 1,
		announce = false,
		pointer = false,
	},
	{
		id = "Golden",
		name = "Золотой",
		chance = 1 / 100,
		hp = 5,
		shards = 10,
		sphereChanceMult = 1,
		guaranteedSphere = true,
		weaponMutationBoost = 1,
		announce = false,
		pointer = true,
	},
	{
		id = "Prismatic",
		name = "Призматический",
		chance = 1 / 1000,
		hp = 10,
		shards = 25,
		sphereChanceMult = 1,
		guaranteedSphere = true,
		weaponMutationBoost = 5,
		announce = false,
		pointer = true,
	},
	{
		id = "Void",
		name = "Пустотный",
		chance = 1 / 10000,
		hp = 20,
		shards = 50,
		sphereChanceMult = 1,
		guaranteedSphere = true,
		weaponMutationBoost = 20,
		announce = true,
		pointer = true,
	},
}

-- Бой.
Config.Combat = {
	HitRadius = 10, -- от игрока до поверхности крипа, стады
	CritChance = 0.1,
	CritMult = 3,
	HitBurst = 2, -- сколько ударов можно «накопить» на случай сетевых рывков
}

-- Редкости оружия: вид, вес в Сфере. weaponFem — род названия («Коса» — женский).
Config.Rarities = {
	{ id = "Common", name = "Обычное", weapon = "Меч", weaponFem = false, weight = 60 },
	{ id = "Uncommon", name = "Необычное", weapon = "Топор", weaponFem = false, weight = 25 },
	{ id = "Rare", name = "Редкое", weapon = "Посох", weaponFem = false, weight = 10 },
	{ id = "Epic", name = "Эпическое", weapon = "Молот", weaponFem = false, weight = 4 },
	{ id = "Legendary", name = "Легендарное", weapon = "Коса", weaponFem = true, weight = 1 },
}

-- Урон за удар: [зона][редкость].
Config.WeaponDamage = {
	{ 1, 1.5, 2.5, 4, 7 },
	{ 7, 11, 18, 28, 49 },
}

-- Мутации оружия. chance — для обычной Сферы.
Config.WeaponMutations = {
	{ id = "Charged", name = "Заряженный", nameFem = "Заряженная", mult = 1.5, chance = 0.05 },
	{ id = "Golden", name = "Золотой", nameFem = "Золотая", mult = 2.5, chance = 0.005 },
	{ id = "Prismatic", name = "Призматический", nameFem = "Призматическая", mult = 5, chance = 0.0005 },
	{ id = "Void", name = "Пустотный", nameFem = "Пустотная", mult = 10, chance = 0.00004 },
}

Config.StarterWeaponName = "Тренировочный меч"

-- Сферы.
Config.Spheres = {
	StorageSize = 10,
	OverflowShown = 20, -- сколько лишних Сфер видно на земле у базы (данные не теряются)
	OpenBase = 100, -- цена вскрытия = OpenBase × OpenGrowth^(зона − 1)
	OpenGrowth = 10,
	RevealHitsMin = 8,
	RevealHitsMax = 10,
	TeaseFromHit = 4, -- с какого удара свет перебирает цвета редкости
	RevealRate = 6, -- ударов по Сфере в секунду максимум
	PityAfter = 25, -- столько Сфер подряд без мутации — следующая с мутацией
	FirstOpenFree = true,
	FirstOpenMinRarity = 2, -- первое вскрытие — минимум Топор
	FirstLargeGivesSphere = true, -- первый убитый Крупный — Сфера гарантированно
	FirstMutantMinMutation = 1, -- Сфера с первого мутанта — минимум Заряженное
	MaxWeapons = 200, -- предохранитель размера инвентаря
}

-- Улучшения. Цена уровня = baseCost × costGrowth^куплено.
-- Потолок = capPerZone × число открытых зон.
Config.Upgrades = {
	Ring = {
		name = "Кольцо",
		baseCost = 25,
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

-- Расстояния взаимодействия на базе.
Config.Base = {
	NestRange = 9, -- до центра гнезда
	StationRange = 11,
	Count = 8,
}

-- Отправка данных игроку.
Config.Net = {
	StateFlushInterval = 0.1, -- не чаще, чем раз в столько секунд на раздел
}

return Config

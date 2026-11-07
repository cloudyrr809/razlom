--!strict
-- Все числа игры в одном месте. Читают и сервер, и клиент.
-- В логике чисел нет: если число надо поменять — меняй здесь.
-- Источник: раздел «Баланс» дизайн-документа (Шаг 1.5).

local Config = {}

-- Мир. Тропа идёт вдоль оси X и петляет: Z середины = сумма волн amp × sin(2π × (X − RoadStart.X) / length).
-- Земля на тропе — Y = 0, по бокам рельеф поднимается.
Config.World = {
	RoadHalfWidth = 12, -- половина ширины тропы (средняя)
	PathWaves = { -- крупный изгиб + две мелкие волны с некратными длинами, чтобы рисунок не повторялся
		{ amp = 22, length = 150 },
		{ amp = 7, length = 61 },
		{ amp = 2.5, length = 37 },
	},
	PathWidthJitter = 0.5, -- ширина тропы гуляет: × (1 ± это × шум), шум обычно в пределах ±0.5
	PathWidthScale = 40, -- длина «волны» шума ширины, стады
	GroundY = 0, -- верх песка
	ZoneTrackInterval = 0.25, -- как часто сервер смотрит, кто в какой зоне, сек
	ZoneSideSlack = 22, -- насколько за краем тропы игрок ещё считается «в зоне» (лагеря в нишах)
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
-- sizeHpMult — множитель HP по размерам (Малый, Средний, Крупный):
-- в первой зоне Крупные слабее, чтобы первая Сфера давалась быстро.
-- shardBonus и sphereBonus — «пир» зоны 1: осколки ×3, шанс Сферы ×2.
Config.Zones = {
	{ name = "Светлые дюны", xStart = 30, xEnd = 180, hpMult = 1, sizeHpMult = { 1, 1, 0.4 }, shardBonus = 3, sphereBonus = 2 },
	{ name = "Ржавый каньон", xStart = 180, xEnd = 330, hpMult = 70, sizeHpMult = { 1, 1, 1 }, shardBonus = 1, sphereBonus = 1 },
}
-- Множители HP будущих зон (для расчётов и следующих обновлений): 1 / 70 / 2100 / 31500 / 504000.
Config.FutureZoneHpMult = { 1, 70, 2100, 31500, 504000 }

-- Зона открыта для игрока, когда он добил в ней первого крипа (пробежать через врата мало).
Config.ZoneUnlock = {
	KillsToOpen = 1,
}

-- Крипы стоят на месте, в лагерях-нишах у тропы. HP = BaseHp × hpMult зоны × hpUnits.
-- Осколки = reward × ShardGrowth^(зона − 1) × shardBonus зоны.
Config.Creeps = {
	BaseHp = 4,
	ShardGrowth = 8,
	RegenPerSecond = 0.04, -- доля максимального HP в секунду, идёт всегда
	TickInterval = 0.1, -- шаг серверного цикла регена, сек
	RespawnMin = 3, -- через сколько секунд убитый крип возрождается на своём месте в лагере
	RespawnMax = 5,
	Sizes = {
		{
			id = "Small",
			name = "Малый",
			hpUnits = 1,
			reward = 1,
			sphereChance = 0.02,
			radius = 1.4, -- радиус для дистанции удара и размер модели, стады
			height = 2.6,
		},
		{
			id = "Medium",
			name = "Средний",
			hpUnits = 3,
			reward = 4,
			sphereChance = 0.04,
			radius = 2.4,
			height = 4.2,
		},
		{
			id = "Large",
			name = "Крупный",
			hpUnits = 8,
			reward = 11,
			sphereChance = 0.08,
			radius = 4,
			height = 7,
		},
	},
}

-- Разброс внешности крипов (только вид, на бой не влияет).
Config.CreepLooks = {
	Proportion = 0.12, -- ± доля к толщине, росту ножки и ширине шляпки
	ColorJitter = 0.05, -- ± к насыщенности и яркости (оттенок — втрое меньше)
	CapTilt = 12, -- наклон шляпки до, градусы
	Crystals = 1, -- гнёзд кристаллов на шляпке; ещё + (номер размера − 1)
	-- Форма ножки: { доля высоты (0 — земля, 1 — под шляпкой), полуширина × радиус крипа }.
	-- По этим точкам строится гладкий меш (tools/creep_meshes.py) и ставятся глаза и трещины.
	StemProfile = { { 0, 0.8 }, { 0.06, 0.86 }, { 0.17, 0.76 }, { 0.34, 0.62 }, { 0.58, 0.56 }, { 0.84, 0.53 }, { 1, 0.5 } },
	-- Шляпка: купол и широкий тонкий край под ним — силуэт гриба, а не «блин».
	-- { высота центра, полуширина, полувысота } в долях высоты / радиуса шляпки.
	CapDome = { 0.06, 0.88, 0.56 },
	CapBrim = { -0.12, 1, 0.24 },
	CapSmooth = 0.08, -- плавность перехода купола в край (доля высоты шляпки)
	CapUnder = 0.8, -- насколько низ шляпки выпуклый вниз (1 — как верх края)
	CapWave = { Count = 7, Amp = 0.035 }, -- волны по краю шляпки в меше: сколько и насколько
	-- Лицо, вылепленное в меше ножки (tools/creep_sculpt.py). Углы — радианы от середины лица,
	-- высоты — доли высоты ножки, размеры — в радиусах крипа. Глаза-свечение ставятся в глазницы.
	FaceAspect = 1.2, -- высота ножки к её радиусу у среднего крипа (чтобы круглое было круглым)
	FaceEyeAngle = 0.42, -- насколько глаза разнесены по кругу ножки
	FaceEyeU = 0.58, -- высота глаз
	FaceEyeW = 0.17, -- полуширина глазницы
	FaceEyeH = 0.08, -- полувысота глазницы
	FaceSocketDepth = 0.14, -- глубина глазницы (доля радиуса ножки)
	FaceEyeSlant = 0.32, -- наклон глаз: внутренние углы ниже — злой взгляд, радианы
	FaceMouthU = 0.36, -- высота рта
	FaceMouthW = 0.38, -- полуширина рта
	-- Переливающаяся плёнка (материал ForceField) поверх шляпки и ножки:
	-- прозрачность по мутации, 1 — плёнки нет. У обычного нет: прозрачное дорого рисовать.
	Sheen = { [0] = 1, [1] = 0.2, [2] = 0.25, [3] = 0, [4] = 0.15 },
	SheenBody = { [0] = 1, [1] = 0.4, [2] = 0.45, [3] = 0.1, [4] = 0.3 },
	SheenHueShift = 0.06, -- насколько «гуляет» оттенок плёнки (у Призматического — вся радуга)
	-- Искры над мутантом: в секунду (ещё + номер мутации), жизнь и скорость подъёма, размер.
	Motes = { Rate = 3, Life = 2.2, Speed = 1.6, Size = 0.35 },
}

-- Детальные меши крипа, загруженные в Roblox (tools/creep_sculpt.py в Blender, импорт в Studio).
-- min/max — рамка меша в единицах генератора (у ножки и её свечения общая, у шляпки — тоже),
-- height — высота меша в Studio (MeshSize.Y), tex — серая текстура (цвет даёт игра).
-- После правки формы или лица в CreepLooks меши надо пересобрать и загрузить заново.
local stemBox = { min = Vector3.new(-1, -0.02, -1), max = Vector3.new(1, 1.02, 1), height = 1.04 }
local capBox = { min = Vector3.new(-1.1, -0.36, -1.1), max = Vector3.new(1.1, 0.75, 1.1), height = 1.11 }
Config.CreepMeshes = {
	Stem = { id = "rbxassetid://130309028070556", tex = "rbxassetid://137368824558146", min = stemBox.min, max = stemBox.max, height = stemBox.height },
	StemGlow = { id = "rbxassetid://132943823083710", tex = "", min = stemBox.min, max = stemBox.max, height = stemBox.height },
	Cap = { id = "rbxassetid://87149098542218", tex = "rbxassetid://133680578842158", min = capBox.min, max = capBox.max, height = capBox.height },
	CapGlow = { id = "rbxassetid://133276037805457", tex = "", min = capBox.min, max = capBox.max, height = capBox.height },
}

-- «Жизнь» крипа на клиенте: поворот к игроку, взгляд, моргание. Только у этого игрока.
Config.CreepLife = {
	-- Анимируются только LiveCount ближайших в пределах LiveRange — остальные стоят неподвижно.
	LiveCount = 4,
	LiveRange = 26, -- стады
	LookRange = 26, -- с какого расстояния крип следит глазами за игроком, стады
	GazeSpeed = 14, -- как быстро зрачки переводятся на цель
	PupilRangeX = 0.08, -- ход зрачка вбок и вверх-вниз, × радиус крипа
	PupilRangeY = 0.035,
	JitterMin = 0.35, -- зрачки «бегают»: новый мелкий сдвиг раз в столько секунд
	JitterMax = 1.6,
	Jitter = 0.3, -- размер этого сдвига, доля хода зрачка
	BlinkMin = 2.5, -- моргание раз в столько секунд
	BlinkMax = 6,
	BlinkTime = 0.16, -- длительность моргания, с
}

-- Лагеря крипов: ниши по краям тропы, по очереди слева и справа.
-- slots — кто стоит в лагере: size из Config.Creeps.Sizes, offset — от центра ниши
-- (−Z смотрит на тропу, +X — вправо, если смотреть из ниши на тропу).
Config.Camps = {
	PerZone = 6,
	NicheRadius = 10, -- средний радиус ниши; у каждой свой, ± NicheRadiusJitter
	NicheRadiusJitter = 1.5,
	NicheDepth = 9, -- насколько центр ниши дальше края тропы
	NicheTurn = 18, -- ниша развёрнута к тропе не строго, а ± столько градусов
	SlotJitter = 1, -- крип встаёт со сдвигом до стольких стад от своего места
	SlotTurn = 35, -- и повёрнут на ± столько градусов
	Slots = {
		{ size = 1, offset = Vector3.new(-5, 0, -3) },
		{ size = 1, offset = Vector3.new(5, 0, -3) },
		{ size = 3, offset = Vector3.new(0, 0, 3) },
	},
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
	TargetSlack = 3, -- запас к радиусу удара на сервере (сетевой рывок), стады
	ClickQueueWindow = 0.15, -- клик раньше срока ждёт, только если до удара осталось меньше, сек
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
		start = 1.6, -- ударов в секунду на старте
		perLevel = 0.1,
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
	RecoilAngle = 18, -- наклон крипа от удара, градусы (делится на √радиуса: крупный качается меньше)
	RecoilTime = 0.3, -- сколько длится отшатывание, сек
	SfxVolume = 0.6, -- общая громкость звуков игры (группа Sfx)
	SoundPool = 6, -- сколько копий каждого звука держим загруженными (столько могут звучать разом)
	PredictWindow = 0.6, -- ответ сервера позже этого — реакцию на свой удар показываем заново
}

-- Отправка данных игроку.
Config.Net = {
	StateFlushInterval = 0.1, -- не чаще, чем раз в столько секунд на раздел
}

return Config

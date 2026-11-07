--!strict
-- Модели из простых деталей: крип, оружие, Сфера, осколок.
-- Финальный арт заменит эти функции, остальной код не трогаем.

local Config = require(script.Parent.Config)
local Palette = require(script.Parent.Palette)

local Models = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Эллипсоид: деталь с мешем-сферой, его можно сплющивать (Scale) и покачивать (Offset).
local function blob(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material): Part
	local p = part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

export type CreepLook = { body: Color3, cap: Color3, glow: Color3, material: Enum.Material }

function Models.creepLook(zone: number, mutation: number): CreepLook
	local colors = Palette.Zones[zone] or Palette.Zones[1]
	local look: CreepLook = {
		body = colors.sand:Lerp(Color3.fromRGB(200, 190, 170), 0.3),
		-- Шляпка темнее и теплее ножки: силуэт читается издалека.
		cap = colors.sand:Lerp(Color3.fromRGB(165, 105, 70), 0.5),
		glow = colors.glow,
		material = Enum.Material.Sand,
	}
	if mutation == 1 then
		look.glow = Color3.fromRGB(150, 235, 255)
	elseif mutation == 2 then
		look.body, look.cap = Palette.Gold, Color3.fromRGB(255, 220, 110)
		look.glow = Color3.fromRGB(255, 170, 60) -- тёплый янтарь: трещины видны на золоте
		look.material = Enum.Material.Foil
	elseif mutation == 3 then
		look.body, look.cap = Color3.fromRGB(225, 225, 255), Color3.fromRGB(240, 240, 255)
		look.glow = Palette.Rainbow[1]
		look.material = Enum.Material.Glass
	elseif mutation == 4 then
		look.body, look.cap = Palette.VoidBody, Color3.fromRGB(40, 28, 56)
		look.glow = Palette.Mutation[4]
		look.material = Enum.Material.Slate
	end
	return look
end

-- Крип-«гриб»: ножка с утолщением и юбочкой, корни по земле, шляпка с пластинками снизу,
-- пятнами и светящимися трещинами, глаза под шляпкой. Каждый немного другой: пропорции,
-- наклон шляпки, оттенок, число пятен. Крупного окружают маленькие грибы-ростки.
-- Корень (Root) — невидимый блок, по нему считается дистанция и клик. Перёд — −Z корня.
local function jitter(c: Color3, rng: Random, amount: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV((h + rng:NextNumber(-amount, amount) * 0.3) % 1, math.clamp(s + rng:NextNumber(-amount, amount), 0, 1), math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
end

-- Форма крипа. Те же формулы повторяет tools/creep_meshes.py, когда строит гладкие меши,
-- поэтому глаза, пятна и трещины ложатся точно на поверхность меша.

-- Полуширина ножки (× радиус крипа) на доле высоты u: гладкая кривая через StemProfile.
function Models.stemRadius(u: number): number
	local P = Config.CreepLooks.StemProfile
	u = math.clamp(u, 0, 1)
	local i = 1
	while i < #P - 1 and u > P[i + 1][1] do
		i += 1
	end
	local function slope(j: number): number
		local a, b = P[math.max(1, j - 1)], P[math.min(#P, j + 1)]
		return (b[2] - a[2]) / (b[1] - a[1])
	end
	local p0, p1 = P[i], P[i + 1]
	local span = p1[1] - p0[1]
	local t = (u - p0[1]) / span
	local t2, t3 = t * t, t * t * t
	return (2 * t3 - 3 * t2 + 1) * p0[2] + (t3 - 2 * t2 + t) * span * slope(i) + (-2 * t3 + 3 * t2) * p1[2] + (t3 - t2) * span * slope(i + 1)
end

-- Верх шляпки над её центром на доле k радиуса (в долях высоты шляпки):
-- купол плавно переходит в широкий край.
function Models.capTop(k: number): number
	local L = Config.CreepLooks
	local D, B, s = L.CapDome, L.CapBrim, L.CapSmooth
	local dome = if k < D[2] then D[1] + D[3] * math.sqrt(1 - (k / D[2]) ^ 2) else D[1] - (k - D[2]) * 4
	local brim = B[1] + B[3] * math.sqrt(math.max(0, 1 - (k / B[2]) ^ 2))
	return 0.5 * (dome + brim + math.sqrt((dome - brim) ^ 2 + s * s))
end

-- Низ шляпки на доле k радиуса.
function Models.capBottom(k: number): number
	local L = Config.CreepLooks
	local B = L.CapBrim
	return B[1] - B[3] * L.CapUnder * math.sqrt(math.max(0, 1 - (k / B[2]) ^ 2))
end

-- Деталь с мешем из Config.CreepMeshes. Деталь с SpecialMesh: клиент сплющивает её масштабом.
-- unit — сколько стадов в одной единице генератора по каждой оси; frame — начало координат
-- генератора в мире. Меш встаёт по центру своей рамки (min..max), рамка — размер детали для клика.
-- textured: серая текстура меша × цвет крипа (VertexColor) — так один меш на все цвета.
local function meshPart(source: string, name: string, unit: Vector3, frame: CFrame, color: Color3, material: Enum.Material, textured: boolean): Part
	local src = Config.CreepMeshes[source]
	local box = src.max - src.min
	-- Studio при импорте glTF разворачивает меш на 180° вокруг вертикали — возвращаем лицом вперёд.
	local at = frame * CFrame.new(unit * (src.min + src.max) / 2) * CFrame.Angles(0, math.pi, 0)
	local p = part({ Name = name, Size = unit * box, CFrame = at, Color = color, Material = material })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.FileMesh
	m.MeshId = src.id
	m.Scale = unit * (box.Y / src.height)
	if textured and src.tex ~= "" then
		m.TextureId = src.tex
		m.VertexColor = Vector3.new(color.R, color.G, color.B)
	end
	m.Parent = p
	return p
end

function Models.creep(zone: number, size: number, mutation: number, cf: CFrame): Model
	local s = Config.Creeps.Sizes[size]
	local r, h = s.radius, s.height
	local look = Models.creepLook(zone, mutation)
	local rng = Random.new()
	local V = Config.CreepLooks
	if mutation == 0 then
		look.body = jitter(look.body, rng, V.ColorJitter)
		look.cap = jitter(look.cap, rng, V.ColorJitter)
	end
	local w = rng:NextNumber(1 - V.Proportion, 1 + V.Proportion) -- толщина
	local tall = rng:NextNumber(1 - V.Proportion, 1 + V.Proportion) -- рост ножки
	local capW = rng:NextNumber(1 - V.Proportion, 1 + V.Proportion)

	local model = Instance.new("Model")
	model.Name = "Creep"
	local root = part({
		Name = "Root",
		Size = Vector3.new(r * 2, h, r * 2),
		CFrame = cf,
		Transparency = 1,
		CanCollide = true,
		CanQuery = true,
		Massless = false,
	})
	root.Parent = model
	model.PrimaryPart = root
	local bottom = cf * CFrame.new(0, -h / 2, 0)

	local function add(p: BasePart): BasePart
		p.Parent = model
		weld(root, p)
		return p
	end
	-- По видимым частям тоже можно кликнуть.
	local function solid(p: BasePart): BasePart
		p.CanQuery = true
		return add(p)
	end

	-- Холмик песка, из которого крип растёт: пара бугорков цвета земли, а не тёмная «тарелка».
	local ground = (Palette.Zones[zone] or Palette.Zones[1]).sand
	for i = 1, 3 do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / 3 * math.pi * 2
		local d = r * rng:NextNumber(0.75, 1.05)
		add(blob("Mound", Vector3.new(d, h * 0.06, d * 0.8), bottom * CFrame.Angles(0, a, 0) * CFrame.new(0, h * 0.01, -r * 0.45), ground:Lerp(Color3.new(0, 0, 0), 0.06), Enum.Material.Sand))
	end
	-- Ножка и шляпка — детальные меши (tools/creep_sculpt.py): злое лицо, разломы вглубь,
	-- неровности и текстура уже вылеплены в них. Начало ножки — её низ, шляпки — её центр.
	local bodyH = h * 0.5 * tall
	local stemY0, stemY1 = -h * 0.03, h * 0.1 + bodyH * 1.1
	local stemH = stemY1 - stemY0
	local sw = r * w
	local stemUnit = Vector3.new(sw, stemH, sw)
	local stemFrame = bottom * CFrame.new(0, stemY0, 0)
	solid(meshPart("Stem", "Body", stemUnit, stemFrame, look.body, look.material, true))
	-- Свет из глубины трещин и оскала: отдельный меш на дне борозд.
	add(meshPart("StemGlow", "Crack", stemUnit, stemFrame, look.glow, Enum.Material.Neon, false))

	-- Глаза в вылепленных глазницах: светящаяся капля, зрачок-щель и блик.
	-- Клиент двигает зрачки вслед за игроком и моргает (CreepFx).
	local dark = look.glow:Lerp(Color3.new(0, 0, 0), 0.88)
	local eyeY = stemY0 + V.FaceEyeU * stemH
	local eyeR = sw * Models.stemRadius(V.FaceEyeU) * (1 - V.FaceSocketDepth * 0.8)
	local eyeW = 2 * sw * V.FaceEyeW * 0.8
	local eyeH = 2 * V.FaceEyeH / V.FaceAspect * stemH * 0.9
	for side = -1, 1, 2 do
		local a = side * V.FaceEyeAngle
		local at = bottom * CFrame.new(math.sin(a) * eyeR, eyeY, -math.cos(a) * eyeR) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, side * V.FaceEyeSlant)
		add(blob("Eye", Vector3.new(eyeW, eyeH, r * 0.12), at, look.glow, Enum.Material.Neon))
		add(blob("Pupil", Vector3.new(r * 0.05, eyeH * 0.8, r * 0.05), at * CFrame.new(0, 0, -r * 0.05), dark, Enum.Material.SmoothPlastic))
		add(blob("Glint", Vector3.new(r * 0.03, r * 0.03, r * 0.02), at * CFrame.new(eyeW * 0.18, eyeH * 0.2, -r * 0.07), Color3.new(1, 1, 1), Enum.Material.Neon))
	end

	-- Шляпка чуть наклонена и повёрнута случайно: разломы на ней у каждого крипа в другую сторону.
	local capH = h * rng:NextNumber(0.42, 0.55)
	local capR = r * 1.1 * capW
	local capY = h * 0.1 + bodyH + capH * 0.12
	local tilt = math.rad(rng:NextNumber(0, V.CapTilt))
	local capCf = bottom * CFrame.new(0, capY, 0) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(tilt, 0, 0)
	local capUnit = Vector3.new(capR, capH, capR)
	local cap = solid(meshPart("Cap", "Cap", capUnit, capCf, look.cap, look.material, true))
	add(meshPart("CapGlow", "Crack", capUnit, capCf, look.glow, Enum.Material.Neon, false))
	local function capTop(k: number): number
		return capH * Models.capTop(k)
	end

	-- Переливающаяся плёнка поверх шляпки (и ножки у мутантов) — та же форма, чуть больше.
	local sheenColor = if mutation == 0 then look.glow:Lerp(Color3.new(1, 1, 1), 0.3) else look.glow
	local sheenT = V.Sheen[mutation] or 1
	if sheenT < 1 then
		local sh = meshPart("Cap", "Sheen", capUnit * 1.03, capCf, sheenColor, Enum.Material.ForceField, false)
		sh.Transparency = sheenT
		add(sh)
	end
	local sheenBodyT = V.SheenBody[mutation] or 1
	if sheenBodyT < 1 then
		local sb = meshPart("Stem", "SheenBody", stemUnit * Vector3.new(1.04, 1.01, 1.04), stemFrame, sheenColor, Enum.Material.ForceField, false)
		sb.Transparency = sheenBodyT
		add(sb)
	end

	-- Точка на поверхности шляпки: k — доля радиуса от центра, a — угол.
	local function onCap(a: number, k: number, lift: number): CFrame
		local y = capTop(k)
		-- Наклон поверхности — по разнице высот рядом.
		local e = 0.02
		local slope = math.atan((capTop(math.max(0, k - e)) - capTop(math.min(0.999, k + e))) / (capR * 2 * e))
		return capCf * CFrame.Angles(0, -a, 0) * CFrame.new(capR * k, y + lift, 0) * CFrame.Angles(0, 0, -slope)
	end

	-- Кристаллы прорастают у края шляпки гнёздами по 2: гладкие капли-«леденцы» со светящимся
	-- ядром внутри, наклонены наружу — не торчат «антеннами» и не выглядят кубиками.
	local crystalColor = look.glow:Lerp(Color3.new(1, 1, 1), 0.55)
	for _ = 1, V.Crystals + size - 1 do
		local base = onCap(rng:NextNumber(0, math.pi * 2), rng:NextNumber(0.6, 0.82), 0)
		for j = 1, 2 do
			local len = r * (if j == 1 then rng:NextNumber(0.28, 0.36) else rng:NextNumber(0.16, 0.22))
			local thick = len * 0.32
			local at = base * CFrame.new(0, 0, (j - 1.5) * thick * 2) * CFrame.Angles(math.rad(rng:NextNumber(-15, 15)), 0, math.rad(-rng:NextNumber(15, 35)))
			-- Капля-основание и тонкое остриё над ней: кристалл сужается к кончику.
			local shell = add(blob("Crystal", Vector3.new(thick, len * 0.7, thick), at * CFrame.new(0, len * 0.3, 0), crystalColor, Enum.Material.Glass))
			shell.Transparency = 0.3
			local tip = add(blob("Crystal", Vector3.new(thick * 0.5, len * 0.55, thick * 0.5), at * CFrame.new(0, len * 0.68, 0), crystalColor, Enum.Material.Glass))
			tip.Transparency = 0.3
			add(blob("Crack", Vector3.new(thick * 0.4, len * 0.75, thick * 0.4), at * CFrame.new(0, len * 0.42, 0), look.glow, Enum.Material.Neon))
		end
	end

	-- Ростки вокруг Крупного.
	if size == 3 then
		for _ = 1, rng:NextInteger(2, 4) do
			local a = rng:NextNumber(math.pi * 0.4, math.pi * 1.6) -- по бокам и сзади, не перед лицом
			local sh = rng:NextNumber(0.9, 1.6)
			local at = bottom * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r * rng:NextNumber(0.9, 1.15)) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12)))
			add(blob("Sprout", Vector3.new(0.45, sh, 0.45), at * CFrame.new(0, sh / 2, 0), look.body, look.material))
			add(blob("SproutCap", Vector3.new(sh * 0.9, sh * 0.45, sh * 0.9), at * CFrame.new(0, sh, 0), look.cap, look.material))
		end
	end

	if mutation >= 1 then
		-- Мелкие искры медленно поднимаются от шляпки (старые Sparkles — крупные звёзды на всю сцену).
		local P = Config.CreepLooks.Motes
		local motes = Instance.new("ParticleEmitter")
		motes.Name = "Motes"
		motes.Color = ColorSequence.new(look.glow)
		motes.LightEmission = 1
		motes.Rate = P.Rate + mutation
		motes.Lifetime = NumberRange.new(P.Life * 0.7, P.Life)
		motes.Speed = NumberRange.new(P.Speed * 0.5, P.Speed)
		motes.SpreadAngle = Vector2.new(25, 25)
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, P.Size * (0.6 + r * 0.15)), NumberSequenceKeypoint.new(1, 0) })
		motes.Transparency = NumberSequence.new(0.2, 1)
		motes.Parent = cap
		local light = Instance.new("PointLight")
		light.Color = look.glow
		light.Range = r * 3 + 4
		light.Brightness = 0.6 + mutation * 0.35 -- ярче слепит, особенно на золоте
		light.Parent = cap
	end
	if mutation == 4 then
		local fire = Instance.new("Fire")
		fire.Color = Palette.Mutation[4]
		fire.SecondaryColor = Color3.new(0, 0, 0)
		fire.Size = r * 1.6
		fire.Parent = cap
	end
	return model
end

-- Ручка оружия для Tool. Форма по редкости: Меч, Топор, Посох, Молот, Коса.
function Models.weaponHandle(zone: number, rarity: number, mutation: number): Part
	local colors = Palette.Zones[zone] or Palette.Zones[1]
	local metal = colors.crystal
	local material = Enum.Material.Glass
	if mutation == 2 then
		metal = Palette.Gold
		material = Enum.Material.Foil
	elseif mutation == 4 then
		metal = Palette.VoidBody
		material = Enum.Material.Slate
	elseif mutation == 3 then
		metal = Color3.fromRGB(240, 240, 255)
	end
	local grip = Color3.fromRGB(86, 60, 46)
	local accent = if mutation > 0 then Palette.Mutation[mutation] else Palette.Rarity[rarity]

	local handle = part({
		Name = "Handle",
		Size = Vector3.new(0.35, 1.6, 0.35),
		Color = grip,
		Material = Enum.Material.Wood,
	})

	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material)
		local p = part({ Name = name, Size = size, CFrame = handle.CFrame * offset, Color = color, Material = mat })
		p.Parent = handle
		weld(handle, p)
		return p
	end

	local head: Part
	if rarity == 1 then
		head = add("Blade", Vector3.new(0.2, 3.2, 0.7), CFrame.new(0, 2.4, 0), metal, material)
		add("Edge", Vector3.new(0.24, 3, 0.12), CFrame.new(0, 2.4, 0.3), accent, Enum.Material.Neon)
		add("Guard", Vector3.new(0.35, 0.3, 1.5), CFrame.new(0, 0.85, 0), accent, Enum.Material.Metal)
	elseif rarity == 2 then
		handle.Size = Vector3.new(0.35, 3.4, 0.35)
		head = add("Head", Vector3.new(0.25, 1.5, 1.7), CFrame.new(0, 1.3, 0.75), metal, material)
		add("Edge", Vector3.new(0.3, 1.5, 0.15), CFrame.new(0, 1.3, 1.6), accent, Enum.Material.Neon)
	elseif rarity == 3 then
		handle.Size = Vector3.new(0.3, 5, 0.3)
		head = add("Orb", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, 2.95, 0), accent, Enum.Material.Neon)
		head.Shape = Enum.PartType.Ball
		add("Claw", Vector3.new(0.2, 1, 1.3), CFrame.new(0, 2.6, 0), metal, material)
	elseif rarity == 4 then
		handle.Size = Vector3.new(0.4, 3.6, 0.4)
		head = add("Head", Vector3.new(1.3, 1.3, 2.3), CFrame.new(0, 1.9, 0), metal, material)
		add("Band", Vector3.new(1.4, 0.3, 2.4), CFrame.new(0, 1.9, 0), accent, Enum.Material.Neon)
	else
		handle.Size = Vector3.new(0.3, 5, 0.3)
		head = add("Blade", Vector3.new(0.15, 0.7, 3.3), CFrame.new(0, 2.4, 1.45) * CFrame.Angles(math.rad(-15), 0, 0), metal, material)
		add("Edge", Vector3.new(0.18, 0.15, 3.2), CFrame.new(0, 2.05, 1.45) * CFrame.Angles(math.rad(-15), 0, 0), accent, Enum.Material.Neon)
	end
	if mutation >= 1 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Palette.Mutation[mutation]
		sparkles.Parent = head
	end
	if mutation == 4 then
		local fire = Instance.new("Fire")
		fire.Color = Palette.Mutation[4]
		fire.SecondaryColor = Color3.new(0, 0, 0)
		fire.Size = 2
		fire.Parent = head
	end
	return handle
end

-- Сфера: шершавый каменный шар с выступами, внутри кристалл (Core) — его свет виден в трещинах.
function Models.sphere(zone: number, cf: CFrame): Model
	local colors = Palette.Zones[zone] or Palette.Zones[1]
	local stone = colors.sandDark:Lerp(Color3.fromRGB(190, 130, 80), 0.4)
	local model = Instance.new("Model")
	model.Name = "Sphere"
	local shell = part({
		Name = "Shell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3,
		CFrame = cf,
		Color = stone,
		Material = Enum.Material.Sandstone,
		Anchored = true,
		Massless = false,
	})
	shell.Parent = model
	model.PrimaryPart = shell
	local rng = Random.new(zone * 31)
	for _ = 1, 8 do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit
		local bump = part({
			Name = "Bump",
			Size = Vector3.new(0.9, 0.6, 0.9) * rng:NextNumber(0.8, 1.3),
			CFrame = CFrame.lookAt(cf.Position + dir * 1.35, cf.Position + dir * 3) * CFrame.Angles(math.rad(90), 0, 0),
			Color = stone:Lerp(Color3.new(0, 0, 0), 0.08),
			Material = Enum.Material.Sandstone,
			Anchored = true,
		})
		bump.Parent = model
	end
	local core = part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.4,
		CFrame = cf,
		Color = colors.glow,
		Material = Enum.Material.Neon,
		Anchored = true,
		Transparency = 1,
	})
	core.Parent = model
	local light = Instance.new("PointLight")
	light.Color = colors.glow
	light.Range = 7
	light.Brightness = 0.5
	light.Parent = core
	return model
end

-- Осколок — основная валюта: вытянутый светящийся кристалл.
function Models.shard(cf: CFrame, color: Color3, scale: number): Part
	local p = part({
		Name = "Shard",
		Size = Vector3.new(0.32, 0.9, 0.32) * scale,
		CFrame = cf * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Neon,
		Anchored = true,
	})
	return p
end

return Models

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
		cap = colors.sand:Lerp(Color3.fromRGB(230, 220, 200), 0.25),
		glow = colors.glow,
		material = Enum.Material.Sand,
	}
	if mutation == 1 then
		look.glow = Color3.fromRGB(150, 235, 255)
	elseif mutation == 2 then
		look.body, look.cap = Palette.Gold, Color3.fromRGB(255, 220, 110)
		look.glow = Color3.fromRGB(255, 250, 200)
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

-- Крип-«гриб»: круглое тело на коротких ножках, широкая шляпка с трещинами, светящиеся глаза.
-- Корень (Root) — невидимый блок, по нему считается физика и дистанция. Перёд — −Z корня.
function Models.creep(zone: number, size: number, mutation: number, cf: CFrame): Model
	local s = Config.Creeps.Sizes[size]
	local r, h = s.radius, s.height
	local look = Models.creepLook(zone, mutation)

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

	local function add(p: BasePart)
		p.Parent = model
		weld(root, p)
	end

	-- Ножки.
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		add(blob("Foot", Vector3.new(r * 0.5, h * 0.18, r * 0.55), bottom * CFrame.new(math.cos(a) * r * 0.5, h * 0.08, math.sin(a) * r * 0.5), look.body, look.material))
	end
	-- Тело.
	local bodyH = h * 0.55
	add(blob("Body", Vector3.new(r * 1.7, bodyH, r * 1.65), bottom * CFrame.new(0, h * 0.1 + bodyH / 2, 0), look.body, look.material))
	-- Глаза: две светящиеся щёлочки под шляпкой.
	for side = -1, 1, 2 do
		add(blob("Eye", Vector3.new(r * 0.3, r * 0.12, r * 0.1), bottom * CFrame.new(side * r * 0.3, h * 0.1 + bodyH * 0.78, -r * 0.8), look.glow, Enum.Material.Neon))
	end
	-- Шляпка.
	local capH = h * 0.5
	local capY = h * 0.1 + bodyH + capH * 0.18
	local cap = blob("Cap", Vector3.new(r * 2.2, capH, r * 2.2), bottom * CFrame.new(0, capY, 0), look.cap, look.material)
	add(cap)
	-- Трещины на шляпке: тонкие светящиеся полоски, лежащие на её поверхности.
	local cracks = 3 + size
	for i = 1, cracks do
		local a = i / cracks * math.pi * 2 + size
		local dist = r * (0.45 + 0.35 * ((i % 2) * 0.5 + 0.25))
		-- Высота поверхности эллипсоида шляпки над её центром на этом расстоянии.
		local k = math.clamp(dist / (r * 1.1), 0, 0.98)
		local y = capH / 2 * math.sqrt(1 - k * k)
		local tilt = math.atan2(capH / 2 * k, r * 1.1 * math.sqrt(1 - k * k))
		add(part({
			Name = "Crack",
			Size = Vector3.new(r * 0.08 + 0.06, 0.08, r * 0.55),
			CFrame = bottom
				* CFrame.new(0, capY, 0)
				* CFrame.Angles(0, -a, 0)
				* CFrame.new(dist, y + 0.02, 0)
				* CFrame.Angles(0, math.rad(70 + i * 17), 0)
				* CFrame.Angles(tilt * 0.6, 0, 0),
			Color = look.glow,
			Material = Enum.Material.Neon,
		}))
	end

	if mutation >= 1 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = look.glow
		sparkles.Parent = cap
		local light = Instance.new("PointLight")
		light.Color = look.glow
		light.Range = r * 4 + 6
		light.Brightness = 1 + mutation * 0.6
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

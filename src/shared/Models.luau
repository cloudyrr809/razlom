--!strict
-- Модели-заглушки из простых деталей: крип, оружие, Сфера.
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

-- Крип: толстое основание + купол + светящиеся трещины.
-- Корень (Root) — невидимый блок, по нему считается физика и дистанция.
function Models.creep(zone: number, size: number, mutation: number, cf: CFrame): Model
	local s = Config.Creeps.Sizes[size]
	local colors = Palette.Zones[zone]
	local r, h = s.radius, s.height

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

	local bodyColor = colors.sandDark
	local crackColor = colors.glow
	local material = Enum.Material.Sand
	if mutation == 2 then
		bodyColor = Palette.Gold
		material = Enum.Material.Foil
		crackColor = Color3.fromRGB(255, 240, 170)
	elseif mutation == 3 then
		bodyColor = Color3.fromRGB(235, 235, 255)
		material = Enum.Material.Glass
		crackColor = Palette.Rainbow[1]
	elseif mutation == 4 then
		bodyColor = Palette.VoidBody
		material = Enum.Material.Slate
		crackColor = Palette.Mutation[4]
	elseif mutation == 1 then
		crackColor = Palette.Mutation[1]
	end

	local baseH = h * 0.45
	local basePart = part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(baseH, r * 2, r * 2),
		CFrame = cf * CFrame.new(0, -h / 2 + baseH / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = bodyColor,
		Material = material,
	})
	basePart.Parent = model
	weld(root, basePart)

	local dome = part({
		Name = "Dome",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (r * 1.9),
		CFrame = cf * CFrame.new(0, -h / 2 + baseH + r * 0.35, 0),
		Color = if mutation == 0 then colors.crystal else bodyColor,
		Material = if mutation == 0 then Enum.Material.Glass else material,
		Transparency = if mutation == 0 then 0.15 else 0,
	})
	dome.Parent = model
	weld(root, dome)

	-- Трещины: тонкие светящиеся полоски вокруг основания.
	for i = 1, 3 do
		local angle = math.rad(i * 120)
		local crack = part({
			Name = "Crack",
			Size = Vector3.new(0.18, baseH * 0.9, r * 0.5),
			CFrame = cf
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(r * 0.98, -h / 2 + baseH / 2, 0)
				* CFrame.Angles(0, 0, math.rad(12)),
			Color = crackColor,
			Material = Enum.Material.Neon,
		})
		crack.Parent = model
		weld(root, crack)
	end

	if mutation >= 1 then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = crackColor
		sparkles.Parent = dome
		local light = Instance.new("PointLight")
		light.Color = crackColor
		light.Range = r * 4 + 6
		light.Brightness = 1.5 + mutation
		light.Parent = dome
	end
	if mutation == 4 then
		local fire = Instance.new("Fire")
		fire.Color = Palette.Mutation[4]
		fire.SecondaryColor = Color3.new(0, 0, 0)
		fire.Size = r * 1.5
		fire.Parent = basePart
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
		material = Enum.Material.Glass
	end
	local grip = Color3.fromRGB(70, 56, 46)

	local handle = part({
		Name = "Handle",
		Size = Vector3.new(0.35, 1.6, 0.35),
		Color = grip,
		Material = Enum.Material.Wood,
		Massless = true,
	})

	local function add(name: string, size: Vector3, offset: CFrame, color: Color3, mat: Enum.Material)
		local p = part({
			Name = name,
			Size = size,
			CFrame = handle.CFrame * offset,
			Color = color,
			Material = mat,
		})
		p.Parent = handle
		weld(handle, p)
		return p
	end

	local head: Part
	if rarity == 1 then
		head = add("Blade", Vector3.new(0.2, 3.2, 0.7), CFrame.new(0, 2.4, 0), metal, material)
		add("Guard", Vector3.new(0.3, 0.25, 1.4), CFrame.new(0, 0.85, 0), grip, Enum.Material.Wood)
	elseif rarity == 2 then
		handle.Size = Vector3.new(0.35, 3.4, 0.35)
		head = add("Head", Vector3.new(0.25, 1.4, 1.6), CFrame.new(0, 1.3, 0.7), metal, material)
	elseif rarity == 3 then
		handle.Size = Vector3.new(0.3, 5, 0.3)
		head = add("Orb", Vector3.new(1, 1, 1), CFrame.new(0, 2.9, 0), metal, Enum.Material.Neon)
		head.Shape = Enum.PartType.Ball
	elseif rarity == 4 then
		handle.Size = Vector3.new(0.4, 3.6, 0.4)
		head = add("Head", Vector3.new(1.3, 1.3, 2.2), CFrame.new(0, 1.9, 0), metal, material)
	else
		handle.Size = Vector3.new(0.3, 5, 0.3)
		head = add("Blade", Vector3.new(0.15, 0.6, 3.2), CFrame.new(0, 2.4, 1.4) * CFrame.Angles(math.rad(-15), 0, 0), metal, material)
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

-- Сфера: каменный шар с кристаллом внутри.
function Models.sphere(zone: number, cf: CFrame): Model
	local colors = Palette.Zones[zone] or Palette.Zones[1]
	local model = Instance.new("Model")
	model.Name = "Sphere"
	local shell = part({
		Name = "Shell",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 3,
		CFrame = cf,
		Color = colors.sandDark,
		Material = Enum.Material.Slate,
		Anchored = true,
		Massless = false,
	})
	shell.Parent = model
	model.PrimaryPart = shell
	local core = part({
		Name = "Core",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 1.6,
		CFrame = cf,
		Color = colors.glow,
		Material = Enum.Material.Neon,
		Anchored = true,
		Transparency = 0.6,
	})
	core.Parent = model
	local light = Instance.new("PointLight")
	light.Color = colors.glow
	light.Range = 8
	light.Brightness = 0.6
	light.Parent = core
	return model
end

return Models

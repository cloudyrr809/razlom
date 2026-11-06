--!nocheck
-- Строит карту «Разломов»: рельеф (Terrain) + детали в Workspace.Map.
-- Запуск: Roblox Studio MCP, execute_luau (Edit):
--   loadstring(game.ServerScriptService.MapTools.BuildMap.Source)()
-- Повторный запуск стирает рельеф и Workspace.Map и строит заново.
-- Размеры зон, дороги и баз берёт из ReplicatedStorage.Shared.Config.
--
-- Теги для скриптов:
--   RiftPoint (Zone) — точки, откуда появляются крипы
--   Gate (Zone) — портал на входе в зону
--   Base (Index) — база; внутри SpawnPoint, Sign, Overflow
--   Nest (Base, Index) — гнездо для Сферы
--   Station (Base) — станция Ауры и Кольца
--   Glow — светящиеся детали, которые клиент мягко «дышит»
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Clone: в режиме редактирования require кэширует модуль, а нам нужна свежая версия.
local Config = require(ReplicatedStorage.Shared.Config:Clone())
local Palette = require(ReplicatedStorage.Shared.Palette:Clone())

local W = Config.World
local HALF = W.RoadHalfWidth
local G = W.RoadStart
local rng = Random.new(7)
local terrain = workspace.Terrain

local old = workspace:FindFirstChild("Map")
if old then
	old:Destroy()
end
for _, name in { "Baseplate", "SpawnLocation" } do
	local x = workspace:FindFirstChild(name)
	if x then
		x:Destroy()
	end
end
terrain:Clear()

local map = Instance.new("Folder")
map.Name = "Map"

local function block(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		if k ~= "ClassName" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function deco(parent, props)
	props.CanCollide = false
	props.CanQuery = false
	props.CanTouch = false
	return block(parent, props)
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function glow(p)
	CollectionService:AddTag(p, "Glow")
	return p
end

local function label(parent, text, color, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.5
	t.Parent = gui
	gui.Parent = parent
	return t
end

-- Камень с «фаской»: блок, слегка повёрнутый случайно.
local function rock(parent, pos, size, color, material)
	return block(parent, {
		Name = "Rock",
		Size = size,
		CFrame = CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, math.pi), rng:NextNumber(-0.25, 0.25)),
		Color = color,
		Material = material or Enum.Material.Slate,
	})
end

-- Кристалл: вытянутый блок с острым верхом (клин сверху).
local function crystal(parent, pos, height, color, tilt)
	local m = Instance.new("Model")
	m.Name = "Crystal"
	local w = height * 0.32
	local cf = CFrame.new(pos) * CFrame.Angles(tilt.X, tilt.Y, tilt.Z)
	deco(m, {
		Name = "Shaft",
		Size = Vector3.new(w, height * 0.75, w),
		CFrame = cf * CFrame.new(0, height * 0.375, 0) * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
		Reflectance = 0.1,
	})
	deco(m, {
		Name = "Tip",
		ClassName = "WedgePart",
		Size = Vector3.new(w, height * 0.25, w),
		CFrame = cf * CFrame.new(0, height * 0.875, 0) * CFrame.Angles(0, math.rad(45), 0),
		Color = color,
		Material = Enum.Material.Glass,
		Transparency = 0.15,
	})
	local core = glow(deco(m, {
		Name = "Core",
		Size = Vector3.new(w * 0.45, height * 0.6, w * 0.45),
		CFrame = cf * CFrame.new(0, height * 0.4, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	}))
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = height * 1.6
	light.Brightness = 0.9
	light.Parent = core
	m.Parent = parent
	return m
end

-- Ломаная светящаяся трещина по земле из точки в направлении.
local function crack(parent, from, dir, length, width, color, branches)
	local p = from
	local d = dir.Unit
	local left = length
	while left > 0 do
		local seg = math.min(left, rng:NextNumber(2.5, 5))
		d = (CFrame.Angles(0, math.rad(rng:NextNumber(-35, 35)), 0):VectorToWorldSpace(d)).Unit
		local q = p + d * seg
		deco(parent, {
			Name = "Crack",
			Size = Vector3.new(width, 0.12, seg + width),
			CFrame = CFrame.lookAt((p + q) / 2, q),
			Color = color,
			Material = Enum.Material.Neon,
		})
		if branches > 0 and rng:NextNumber() < 0.3 then
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			crack(parent, q, CFrame.Angles(0, math.rad(side * rng:NextNumber(40, 75)), 0):VectorToWorldSpace(d), left * 0.45, width * 0.7, color, branches - 1)
		end
		p = q
		left -= seg
		width *= 0.93
	end
end

local function tree(parent, pos, s)
	local m = Instance.new("Model")
	m.Name = "Tree"
	block(m, {
		Name = "Trunk",
		Size = Vector3.new(1.4, 6, 1.4) * s,
		Position = pos + Vector3.new(0, 3 * s, 0),
		Color = Color3.fromRGB(120, 82, 56),
		Material = Enum.Material.Wood,
	})
	for i = 1, 3 do
		local o = Vector3.new(rng:NextNumber(-1.5, 1.5), 6.5 + i * 0.8, rng:NextNumber(-1.5, 1.5)) * s
		block(m, {
			Name = "Leaves",
			Size = Vector3.new(rng:NextNumber(3.5, 5), rng:NextNumber(2.5, 3.5), rng:NextNumber(3.5, 5)) * s,
			CFrame = CFrame.new(pos + o) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Color = Color3.fromRGB(86, 150, 70):Lerp(Color3.fromRGB(120, 180, 80), rng:NextNumber()),
			Material = Enum.Material.Grass,
			CanCollide = false,
		})
	end
	m.Parent = parent
end

local function torch(parent, pos)
	local m = Instance.new("Model")
	m.Name = "Torch"
	block(m, {
		Name = "Pole",
		Size = Vector3.new(0.5, 4, 0.5),
		Position = pos + Vector3.new(0, 2, 0),
		Color = Color3.fromRGB(90, 66, 50),
		Material = Enum.Material.Wood,
	})
	local bowl = block(m, {
		Name = "Bowl",
		Size = Vector3.new(1.1, 0.6, 1.1),
		Position = pos + Vector3.new(0, 4.2, 0),
		Color = Color3.fromRGB(70, 66, 64),
		Material = Enum.Material.Metal,
	})
	local fire = Instance.new("Fire")
	fire.Size = 2.5
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 170, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 90, 30)
	fire.Parent = bowl
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Range = 14
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = bowl
	m.Parent = parent
end

-- Портал-кольцо из каменных блоков, нижняя часть уходит в землю. Сквозь него пробегают.
local function portal(parent, center, radius, color, name)
	local m = Instance.new("Model")
	m.Name = name
	local n = 34
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local p = center + Vector3.new(0, math.sin(a) * radius, math.cos(a) * radius)
		if p.Y > -2 then
			block(m, {
				Name = "Stone",
				Size = Vector3.new(4.5, 3.8, radius * 2 * math.pi / n + 0.6),
				CFrame = CFrame.new(p) * CFrame.Angles(-a, 0, 0),
				Color = Color3.fromRGB(122, 126, 140),
				Material = Enum.Material.Slate,
			})
			if i % 3 == 0 then
				glow(deco(m, {
					Name = "Rune",
					Size = Vector3.new(4.7, 1.2, 1.2),
					CFrame = CFrame.new(p) * CFrame.Angles(-a, 0, 0) * CFrame.Angles(0, 0, math.rad(45)),
					Color = color,
					Material = Enum.Material.Neon,
				}))
			end
		end
	end
	-- Светящаяся завеса внутри кольца.
	local veil = glow(deco(m, {
		Name = "Veil",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2 - 3, radius * 2 - 3),
		CFrame = CFrame.new(center),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.82,
	}))
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.6, 0)
	emitter.Transparency = NumberSequence.new(0.2, 1)
	emitter.Lifetime = NumberRange.new(1.5, 2.5)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 30
	emitter.Parent = veil
	-- Парящие кристаллы вокруг.
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		crystal(m, center + Vector3.new(rng:NextNumber(-2, 2), math.sin(a) * (radius + 4), math.cos(a) * (radius + 4)), 3, color, Vector3.new(a, 0, 0.4))
	end
	m.Parent = parent
	return m
end

-- Рельеф ------------------------------------------------------------------
terrain:SetMaterialColor(Enum.Material.Sand, Palette.Zones[1].sand)
terrain:SetMaterialColor(Enum.Material.Sandstone, Palette.Zones[2].sand)
terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(150, 140, 128))
terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(176, 120, 84))

local MIN_X, MAX_X, MAX_Z = -170, Config.Zones[#Config.Zones].xEnd + 40, 175
local zone2x = Config.Zones[2].xStart
-- Видимая поверхность рельефа встаёт примерно на 2 стада выше верха заливки.
terrain:FillBlock(CFrame.new((MIN_X + zone2x) / 2, -6, 0), Vector3.new(zone2x - MIN_X, 8, MAX_Z * 2), Enum.Material.Sand)
terrain:FillBlock(CFrame.new((zone2x + MAX_X) / 2, -6, 0), Vector3.new(MAX_X - zone2x, 8, MAX_Z * 2), Enum.Material.Sandstone)
task.wait()

-- Дюны в зоне 1 и за базами, скалы в зоне 2 — только за краями дороги.
for _ = 1, 70 do
	local x = rng:NextNumber(MIN_X, MAX_X)
	local z = rng:NextNumber(-MAX_Z, MAX_Z)
	local nearRoad = x > G.X - 10 and math.abs(z) < HALF + 14
	local nearBases = (Vector3.new(x, 0, z) - G).Magnitude < W.BaseRingRadius + W.BaseRadius + 14 and x < G.X + 10
	if not nearRoad and not nearBases then
		local r = rng:NextNumber(10, 26)
		local mat = if x > zone2x then Enum.Material.Sandstone else Enum.Material.Sand
		terrain:FillBall(Vector3.new(x, -r * 0.55, z), r, mat)
	end
end
task.wait()

-- Дорога ------------------------------------------------------------------
local road = folder(map, "Road")
for zi, zone in Config.Zones do
	local colors = Palette.Zones[zi]
	local len = zone.xEnd - zone.xStart
	local cx = (zone.xStart + zone.xEnd) / 2
	block(road, {
		Name = "Road" .. zi,
		Size = Vector3.new(len, 2, HALF * 2 + 6),
		Position = Vector3.new(cx, W.GroundY - 1, 0),
		Color = colors.sand:Lerp(Color3.new(1, 1, 1), 0.08),
		Material = if zi == 1 then Enum.Material.Sand else Enum.Material.Ground,
	})
	-- Протоптанная тропа посередине.
	block(road, {
		Name = "Path",
		Size = Vector3.new(len, 0.1, 14),
		Position = Vector3.new(cx, W.GroundY + 0.03, 0),
		Color = colors.sandDark,
		Material = Enum.Material.Sand,
		CanCollide = false,
	})

	-- Низкие каменные стены по краям, в зоне 2 — ещё и высокие скалы-столбы.
	for side = -1, 1, 2 do
		local x = zone.xStart
		while x < zone.xEnd do
			local s = rng:NextNumber(3, 5)
			rock(road, Vector3.new(x, 1.2, side * (HALF + 3 + rng:NextNumber(-0.5, 0.5))), Vector3.new(s, rng:NextNumber(2.5, 4), s), Color3.fromRGB(128, 126, 130))
			x += s * 0.8
		end
		if zi == 2 then
			for _ = 1, 7 do
				local px = rng:NextNumber(zone.xStart + 5, zone.xEnd - 5)
				local pz = side * rng:NextNumber(HALF + 9, HALF + 28)
				local h = rng:NextNumber(14, 30)
				local base = rng:NextNumber(7, 12)
				for k = 0, 2 do
					rock(road, Vector3.new(px, h * (k + 0.5) / 3, pz), Vector3.new(base * (1 - k * 0.18), h / 3 + 1, base * (1 - k * 0.15)), colors.sandDark:Lerp(colors.sand, k * 0.3), Enum.Material.Sandstone)
				end
			end
		end

		-- Разлом вдоль края и точки появления крипов.
		local px = zone.xStart + 8
		while px < zone.xEnd - 4 do
			local z = side * (HALF - 1.5)
			local hole = deco(road, {
				Name = "RiftPoint",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.15, 2.2, 2.2),
				CFrame = CFrame.new(px, W.GroundY + 0.08, z) * CFrame.Angles(0, 0, math.rad(90)),
				Color = colors.glow,
				Material = Enum.Material.Neon,
				Transparency = 0.45,
			})
			hole:SetAttribute("Zone", zi)
			CollectionService:AddTag(hole, "RiftPoint")
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(colors.glow)
			emitter.LightEmission = 1
			emitter.Size = NumberSequence.new(0.4, 0)
			emitter.Transparency = NumberSequence.new(0.3, 1)
			emitter.Lifetime = NumberRange.new(1, 2)
			emitter.Speed = NumberRange.new(2, 4)
			emitter.SpreadAngle = Vector2.new(15, 15)
			emitter.EmissionDirection = Enum.NormalId.Right
			emitter.Rate = 4
			emitter.Parent = hole
			crack(road, Vector3.new(px, W.GroundY + 0.06, z), Vector3.new(rng:NextNumber(-1, 1), 0, -side * 0.6), rng:NextNumber(4, 9), 0.28, colors.glow, 1)
			px += 15
		end
	end

	-- Ветвистые трещины по дороге (зона 1 — голубые, зона 2 — лава).
	for _ = 1, (if zi == 1 then 7 else 4) do
		local p = Vector3.new(rng:NextNumber(zone.xStart + 6, zone.xEnd - 6), W.GroundY + 0.07, rng:NextNumber(-HALF + 4, HALF - 4))
		crack(road, p, Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), rng:NextNumber(8, 14), 0.3, colors.glow, 2)
	end
	-- Кристаллы по обочинам зоны 1.
	if zi == 1 then
		for _ = 1, 12 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			crystal(road, Vector3.new(rng:NextNumber(zone.xStart, zone.xEnd), 0, side * rng:NextNumber(HALF + 7, HALF + 18)), rng:NextNumber(4, 9), colors.crystal, Vector3.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)))
		end
	end
	task.wait()
end

-- Порталы: вход в зону 1 и врата между зонами ---------------------------------
local gates = folder(map, "Gates")
for zi = 1, #Config.Zones do
	local x = Config.Zones[zi].xStart
	local p = portal(gates, Vector3.new(x, 7, 0), HALF + 1, Palette.Zones[zi].glow, "Gate" .. zi)
	p:SetAttribute("Zone", zi)
	CollectionService:AddTag(p, "Gate")
	local sign = deco(p, {
		Name = "Sign",
		Size = Vector3.new(0.3, 4, 24),
		Position = Vector3.new(x - 1, HALF + 13, 0),
		Transparency = 1,
	})
	label(sign, `Зона {zi} · {Config.Zones[zi].name}`, Color3.new(1, 1, 1), Enum.NormalId.Left)
	label(sign, `Зона {zi} · {Config.Zones[zi].name}`, Color3.new(1, 1, 1), Enum.NormalId.Right)
end

-- Закрытый разлом «Скоро» в конце.
do
	local x = Config.Zones[#Config.Zones].xEnd
	local wall = Instance.new("Model")
	wall.Name = "SoonRift"
	for i = -5, 5 do
		local s = rng:NextNumber(9, 14)
		rock(wall, Vector3.new(x + 5, s * 0.6, i * 6), Vector3.new(s, s * rng:NextNumber(1.3, 2.4), s), Palette.Zones[2].sandDark, Enum.Material.Sandstone)
	end
	block(wall, { Name = "Blocker", Size = Vector3.new(2, 60, HALF * 2 + 30), Position = Vector3.new(x, 30, 0), Transparency = 1 })
	local closed = deco(wall, {
		Name = "ClosedCrack",
		Size = Vector3.new(0.5, 16, 10),
		Position = Vector3.new(x - 1, 10, 0),
		Color = Color3.fromRGB(90, 70, 130),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
	})
	label(closed, "Скоро", Color3.new(1, 1, 1), Enum.NormalId.Left)
	wall.Parent = map
end

-- Невидимые стены по краю карты.
for _, w in {
	{ Vector3.new(MAX_X - MIN_X, 80, 2), Vector3.new((MIN_X + MAX_X) / 2, 40, MAX_Z) },
	{ Vector3.new(MAX_X - MIN_X, 80, 2), Vector3.new((MIN_X + MAX_X) / 2, 40, -MAX_Z) },
	{ Vector3.new(2, 80, MAX_Z * 2), Vector3.new(MIN_X, 40, 0) },
	{ Vector3.new(2, 80, MAX_Z * 2), Vector3.new(MAX_X, 40, 0) },
} do
	block(map, { Name = "Edge", Size = w[1], Position = w[2], Transparency = 1 })
end
task.wait()

-- Спавн: круглая арена со ступенями и светящимися кольцами ----------------------
do
	local plaza = Instance.new("Model")
	plaza.Name = "Plaza"
	local c = W.PlazaCenter
	local R = W.PlazaRadius
	local stone = Color3.fromRGB(214, 190, 150)
	block(plaza, {
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, R * 2, R * 2),
		CFrame = CFrame.new(c.X, -0.45, c.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = stone,
		Material = Enum.Material.Sandstone,
	})
	-- Ступени-кольца по краю (как трибуны).
	for i = 1, 3 do
		local r = R + i * 2.5
		local n = 40
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2
			-- Проход к дороге и к базам оставляем открытым.
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local toRoad = dir.X > 0.85
			if not toRoad then
				block(plaza, {
					Name = "Step",
					Size = Vector3.new(2.6, i * 0.9, r * 2 * math.pi / n + 0.4),
					CFrame = CFrame.new(c + dir * r + Vector3.new(0, i * 0.45 - 0.1, 0)) * CFrame.Angles(0, -a, 0),
					Color = stone:Lerp(Color3.fromRGB(170, 140, 100), i * 0.15),
					Material = Enum.Material.Sandstone,
				})
			end
		end
	end
	-- Светящиеся кольца в полу: голубое снаружи, два золотых внутри.
	for _, ring in { { R - 3, Palette.Zones[1].glow, 0.5 }, { R * 0.62, Color3.fromRGB(255, 210, 90), 0.4 }, { R * 0.45, Color3.fromRGB(255, 210, 90), 0.35 } } do
		local n = 48
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2
			deco(plaza, {
				Name = "RingGlow",
				Size = Vector3.new(ring[3], 0.1, ring[1] * 2 * math.pi / n + 0.1),
				CFrame = CFrame.new(c + Vector3.new(math.cos(a), 0, math.sin(a)) * ring[1] + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, -a, 0),
				Color = ring[2],
				Material = Enum.Material.Neon,
			})
		end
	end
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		crack(plaza, c + Vector3.new(math.cos(a), 0, math.sin(a)) * R * 0.5 + Vector3.new(0, 0.07, 0), Vector3.new(math.cos(a), 0, math.sin(a)), R * 0.5, 0.3, Palette.Zones[1].glow, 1)
	end
	-- В центре — кристалл-друза; таблица лидеров появится в Шаге 2.
	block(plaza, {
		Name = "Pedestal",
		Size = Vector3.new(7, 1.2, 7),
		CFrame = CFrame.new(c + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = Color3.fromRGB(150, 140, 170),
		Material = Enum.Material.Slate,
	})
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		crystal(plaza, c + Vector3.new(math.cos(a) * 1.4, 1.2, math.sin(a) * 1.4), rng:NextNumber(3, 5), if i % 2 == 0 then Color3.fromRGB(190, 120, 255) else Color3.fromRGB(120, 220, 255), Vector3.new(math.sin(a) * 0.5, 0, math.cos(a) * 0.5))
	end
	crystal(plaza, c + Vector3.new(0, 1.2, 0), 7, Color3.fromRGB(150, 230, 255), Vector3.zero)
	-- Факелы по кругу.
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2 + 0.3
		torch(plaza, c + Vector3.new(math.cos(a), 0, math.sin(a)) * (R + 9))
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = c + Vector3.new(8, 0.3, 0)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = plaza
	-- Деревья и камни вокруг арены.
	for _ = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local p = c + Vector3.new(math.cos(a), 0, math.sin(a)) * rng:NextNumber(R + 13, R + 24)
		if p.X < c.X - 4 or math.abs(p.Z) > 18 then
			tree(plaza, p, rng:NextNumber(0.9, 1.4))
		end
	end
	plaza.Parent = map
end
task.wait()

-- Базы на дуге вокруг входа: до входа у всех одинаково --------------------------
local bases = folder(map, "Bases")
local R, H = W.BaseRadius, W.BaseHeight
local count = Config.Base.Count
for index = 1, count do
	local deg = W.BaseArcFrom + (W.BaseArcTo - W.BaseArcFrom) * (index - 1) / (count - 1)
	local a = math.rad(deg)
	local center = G + Vector3.new(math.cos(a), 0, math.sin(a)) * W.BaseRingRadius
	local top = Vector3.new(center.X, H, center.Z)
	local frame = CFrame.lookAt(top, Vector3.new(G.X, H, G.Z)) -- «вперёд» базы — ко входу в зону
	local base = Instance.new("Model")
	base.Name = "Base" .. index

	-- Утёс-платформа: песчаный верх, каменный обод, скальное основание.
	block(base, {
		Name = "Platform",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, R * 2, R * 2),
		CFrame = CFrame.new(center.X, H - 0.6, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Palette.Base,
		Material = Enum.Material.Sand,
	})
	block(base, {
		Name = "Cliff",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(H + 2, R * 2 + 1, R * 2 + 1),
		CFrame = CFrame.new(center.X, H / 2 - 1.6, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(150, 112, 84),
		Material = Enum.Material.Sandstone,
	})
	for k = 0, 27 do
		local ang = k / 28 * math.pi * 2
		local dir = frame:VectorToWorldSpace(Vector3.new(math.sin(ang), 0, -math.cos(ang)))
		-- Спереди проход для лестницы.
		if math.abs(ang) > 0.35 and math.abs(ang - math.pi * 2) > 0.35 then
			block(base, {
				Name = "Rim",
				Size = Vector3.new(2, 1.4, R * 2 * math.pi / 28 + 0.4),
				CFrame = CFrame.lookAt(top + dir * (R - 1) + Vector3.new(0, 0.7, 0), top + dir * R) * CFrame.Angles(0, math.rad(90), 0),
				Color = Color3.fromRGB(140, 136, 140),
				Material = Enum.Material.Slate,
			})
		end
	end
	-- Лестница к входу.
	for s = 1, 6 do
		block(base, {
			Name = "Stair",
			Size = Vector3.new(9, H * (7 - s) / 6, 2.2),
			CFrame = frame * CFrame.new(0, -H + H * (7 - s) / 12, -(R - 0.5 + s * 2.2)),
			Color = Color3.fromRGB(150, 146, 150),
			Material = Enum.Material.Slate,
		})
	end
	-- Светящиеся трещины по песку базы.
	for _ = 1, 6 do
		local ang = rng:NextNumber(0, math.pi * 2)
		crack(base, top + Vector3.new(math.cos(ang), 0, math.sin(ang)) * R * 0.55 + Vector3.new(0, 0.05, 0), Vector3.new(math.cos(ang), 0, math.sin(ang)), R * 0.4, 0.3, Palette.Zones[1].glow, 1)
	end

	-- Монолит: высокий кристалл на круглом постаменте (уровни и цвет — Шаг 2).
	block(base, {
		Name = "MonolithPedestal",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.6, 9, 9),
		CFrame = CFrame.new(top + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(130, 128, 136),
		Material = Enum.Material.Slate,
	})
	local mono = crystal(base, top + Vector3.new(0, 1.6, 0), 13, Color3.fromRGB(160, 215, 255), Vector3.zero)
	mono.Name = "Monolith"

	-- Три гнезда вокруг Монолита: каменная чаша с зубцами.
	for k = 1, 3 do
		local nestCf = frame * CFrame.Angles(0, math.rad((k - 2) * 60 + 180), 0) * CFrame.new(0, 0, -11)
		local nest = block(base, {
			Name = "Nest" .. k,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1, 6, 6),
			CFrame = nestCf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(120, 116, 124),
			Material = Enum.Material.Slate,
		})
		deco(base, {
			Name = "NestGlow",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.12, 4.2, 4.2),
			CFrame = nestCf * CFrame.new(0, 1.04, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Palette.Zones[1].glow,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
		})
		for p = 1, 5 do
			local pa = math.rad(p * 72)
			block(base, {
				Name = "NestProng",
				Size = Vector3.new(0.8, 2.4, 0.8),
				CFrame = nestCf * CFrame.Angles(0, pa, 0) * CFrame.new(0, 1.6, -2.6) * CFrame.Angles(math.rad(-18), 0, 0),
				Color = Color3.fromRGB(120, 116, 124),
				Material = Enum.Material.Slate,
			})
		end
		nest:SetAttribute("Base", index)
		nest:SetAttribute("Index", k)
		CollectionService:AddTag(nest, "Nest")
	end

	-- Станция Ауры и Кольца — справа от входа.
	local stationCf = frame * CFrame.Angles(0, math.rad(-65), 0) * CFrame.new(0, 0, -16)
	local station = Instance.new("Model")
	station.Name = "Station"
	local pedestal = block(station, {
		Name = "Pedestal",
		Size = Vector3.new(9, 1, 5),
		CFrame = stationCf * CFrame.new(0, 0.5, 0),
		Color = Color3.fromRGB(120, 116, 124),
		Material = Enum.Material.Slate,
	})
	crystal(station, (stationCf * CFrame.new(-2.6, 1, 0)).Position, 6, Color3.fromRGB(90, 200, 255), Vector3.zero)
	crystal(station, (stationCf * CFrame.new(2.6, 1, 0)).Position, 6, Color3.fromRGB(255, 200, 80), Vector3.zero)
	local sign = deco(station, {
		Name = "StationSign",
		Size = Vector3.new(8, 2, 0.3),
		CFrame = stationCf * CFrame.new(0, 8.2, 0) * CFrame.Angles(0, math.rad(180), 0),
		Transparency = 1,
	})
	label(sign, "Аура · Кольцо", Color3.new(1, 1, 1), Enum.NormalId.Front)
	label(sign, "Аура · Кольцо", Color3.new(1, 1, 1), Enum.NormalId.Back)
	station.PrimaryPart = pedestal
	station:SetAttribute("Base", index)
	CollectionService:AddTag(station, "Station")
	station.Parent = base

	block(base, {
		Name = "SpawnPoint",
		Size = Vector3.new(2, 1, 2),
		CFrame = frame * CFrame.new(0, 3, -17),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	block(base, {
		Name = "Overflow",
		Size = Vector3.new(2, 1, 2),
		CFrame = frame * CFrame.Angles(0, math.rad(65), 0) * CFrame.new(0, 0.5, -16),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	local post = block(base, {
		Name = "Sign",
		Size = Vector3.new(0.6, 5, 0.6),
		CFrame = frame * CFrame.new(6.5, 2.5, -(R - 2)),
		Color = Color3.fromRGB(110, 84, 64),
		Material = Enum.Material.Wood,
	})
	local bb = Instance.new("BillboardGui")
	bb.Name = "OwnerGui"
	bb.Size = UDim2.fromOffset(240, 44)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.MaxDistance = 70
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.Name = "Label"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "Свободная база"
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = bb
	bb.Parent = post
	torch(base, (frame * CFrame.new(-6.5, 0, -(R - 2))).Position)
	torch(base, (frame * CFrame.new(10, 0, -(R - 6))).Position)

	base:SetAttribute("Index", index)
	CollectionService:AddTag(base, "Base")
	base.Parent = bases
	task.wait()
end

-- Свет: тёплый закат, холодный неон ----------------------------------------------
for _, c in Lighting:GetChildren() do
	if c:IsA("PostEffect") or c:IsA("Atmosphere") or c:IsA("Sky") then
		c:Destroy()
	end
end
Lighting.ClockTime = 15.8
Lighting.GeographicLatitude = 30
Lighting.Brightness = 2.4
Lighting.Ambient = Color3.fromRGB(90, 90, 120)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 160)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.6
Lighting.ShadowSoftness = 0.3
local atm = Instance.new("Atmosphere")
atm.Density = 0.28
atm.Offset = 0.1
atm.Haze = 1.4
atm.Glare = 0.4
atm.Color = Color3.fromRGB(255, 214, 170)
atm.Decay = Color3.fromRGB(110, 120, 190)
atm.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity = 0.7
bloom.Size = 28
bloom.Threshold = 1.6
bloom.Parent = Lighting
local cc = Instance.new("ColorCorrectionEffect")
cc.Saturation = 0.28
cc.Contrast = 0.08
cc.TintColor = Color3.fromRGB(255, 248, 240)
cc.Parent = Lighting
local rays = Instance.new("SunRaysEffect")
rays.Intensity = 0.06
rays.Spread = 0.6
rays.Parent = Lighting
local clouds = terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
clouds.Cover = 0.45
clouds.Density = 0.6
clouds.Color = Color3.fromRGB(255, 236, 220)
clouds.Parent = terrain

map.Parent = workspace
return "Карта построена: баз " .. count

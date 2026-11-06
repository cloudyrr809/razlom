--!nocheck
-- Строит карту-заглушку «Разломов» в Workspace.Map.
-- Запуск: Roblox Studio MCP, execute_luau (Edit): loadstring(исходник)().
-- Повторный запуск стирает Workspace.Map и строит заново.
-- Все размеры зон и дороги берёт из ReplicatedStorage.Shared.Config.
--
-- Теги для серверных скриптов:
--   RiftPoint (Zone) — точки, откуда появляются крипы
--   Gate (Zone) — врата на границе зоны
--   Base (Index) — база; внутри SpawnPoint, Sign, Overflow, Monolith
--   Nest (Base, Index) — гнездо для Сферы
--   Station (Base) — станция Ауры и Кольца
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Palette)

local W = Config.World
local HALF = W.RoadHalfWidth
local rng = Random.new(7)

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

local map = Instance.new("Folder")
map.Name = "Map"

local function block(parent, props)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Sand
	for k, v in props do
		if k ~= "ClassName" then
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
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
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.Parent = t
	gui.Parent = parent
	return t
end

-- Земля -------------------------------------------------------------------
local ground = folder(map, "Ground")
local MIN_X, MAX_X, MAX_Z = -130, Config.Zones[#Config.Zones].xEnd + 30, 140
block(ground, {
	Name = "Ground1",
	Size = Vector3.new(Config.Zones[1].xEnd - MIN_X, 4, MAX_Z * 2),
	Position = Vector3.new((MIN_X + Config.Zones[1].xEnd) / 2, W.GroundY - 2, 0),
	Color = Palette.Zones[1].sand,
})
block(ground, {
	Name = "Ground2",
	Size = Vector3.new(MAX_X - Config.Zones[2].xStart, 4, MAX_Z * 2),
	Position = Vector3.new((MAX_X + Config.Zones[2].xStart) / 2, W.GroundY - 2, 0),
	Color = Palette.Zones[2].sand,
})

-- Невидимые стены по краю карты.
for _, w in {
	{ Vector3.new(MAX_X - MIN_X, 60, 2), Vector3.new((MIN_X + MAX_X) / 2, 30, MAX_Z) },
	{ Vector3.new(MAX_X - MIN_X, 60, 2), Vector3.new((MIN_X + MAX_X) / 2, 30, -MAX_Z) },
	{ Vector3.new(2, 60, MAX_Z * 2), Vector3.new(MIN_X, 30, 0) },
	{ Vector3.new(2, 60, MAX_Z * 2), Vector3.new(MAX_X, 30, 0) },
} do
	block(ground, { Name = "Edge", Size = w[1], Position = w[2], Transparency = 1 })
end

-- Дорога и разломы ---------------------------------------------------------
local road = folder(map, "Road")
for zi, zone in Config.Zones do
	local colors = Palette.Zones[zi]
	local len = zone.xEnd - zone.xStart
	local cx = (zone.xStart + zone.xEnd) / 2
	block(road, {
		Name = "Road" .. zi,
		Size = Vector3.new(len, 1, HALF * 2),
		Position = Vector3.new(cx, W.GroundY - 0.4, 0),
		Color = colors.sandDark:Lerp(colors.sand, 0.55),
	})

	-- Трещины по краям дороги.
	for side = -1, 1, 2 do
		local x = zone.xStart
		while x < zone.xEnd do
			local seg = rng:NextNumber(6, 11)
			local segLen = math.min(seg, zone.xEnd - x)
			block(road, {
				Name = "Crack",
				Size = Vector3.new(segLen + 0.6, 0.2, rng:NextNumber(0.5, 1.1)),
				CFrame = CFrame.new(x + segLen / 2, W.GroundY + 0.12, side * (HALF + rng:NextNumber(-0.8, 0.8)))
					* CFrame.Angles(0, math.rad(rng:NextNumber(-8, 8)), 0),
				Color = colors.glow,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
			x += seg
		end

		-- Точки появления крипов: светящиеся «дыры» в разломе каждые 15 стадов.
		local px = zone.xStart + 8
		while px < zone.xEnd - 4 do
			local hole = block(road, {
				Name = "RiftPoint",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 4.5, 4.5),
				CFrame = CFrame.new(px, W.GroundY + 0.1, side * (HALF - 1.5)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = colors.glow,
				Material = Enum.Material.Neon,
				Transparency = 0.25,
				CanCollide = false,
				CanQuery = false,
			})
			hole:SetAttribute("Zone", zi)
			CollectionService:AddTag(hole, "RiftPoint")
			px += 15
		end
	end

	-- Перепады высот: дюны и скалы за краями дороги.
	for _ = 1, 26 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local x = rng:NextNumber(zone.xStart, zone.xEnd)
		local z = side * rng:NextNumber(HALF + 8, MAX_Z - 6)
		-- Не ставим скалы на базы.
		local onBase = math.abs(math.abs(z) - 75) < 40 and x < 175
		if not onBase then
			local s = rng:NextNumber(6, 18)
			block(road, {
				Name = "Dune",
				Size = Vector3.new(s * rng:NextNumber(1, 2), s * rng:NextNumber(0.3, 0.8), s),
				CFrame = CFrame.new(x, W.GroundY, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = colors.sandDark,
			})
		end
	end
end

-- Врата между зонами -------------------------------------------------------
local gates = folder(map, "Gates")
for zi = 2, #Config.Zones do
	local x = Config.Zones[zi].xStart
	local colors = Palette.Zones[zi]
	local gate = Instance.new("Model")
	gate.Name = "Gate" .. zi
	for side = -1, 1, 2 do
		block(gate, {
			Name = "Pillar",
			Size = Vector3.new(5, 24, 5),
			CFrame = CFrame.new(x, W.GroundY + 12, side * (HALF + 3)) * CFrame.Angles(0, math.rad(side * 10), math.rad(side * 4)),
			Color = Palette.Stone,
			Material = Enum.Material.Slate,
		})
	end
	-- Разлом в воздухе: ломаная светящаяся линия поверху и полупрозрачная завеса.
	local points = {}
	for i = 0, 8 do
		local z = -HALF + i * (HALF * 2 / 8)
		local y = W.GroundY + 20 + (if i % 2 == 0 then 0 else -2.5) + rng:NextNumber(-0.6, 0.6)
		table.insert(points, Vector3.new(x, y, z))
	end
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		block(gate, {
			Name = "Tear",
			Size = Vector3.new(0.8, 0.8, (b - a).Magnitude + 0.6),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = colors.glow,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end
	local veil = block(gate, {
		Name = "Veil",
		Size = Vector3.new(0.3, 19, HALF * 2),
		Position = Vector3.new(x, W.GroundY + 9.5, 0),
		Color = colors.glow,
		Material = Enum.Material.Neon,
		Transparency = 0.88,
		CanCollide = false,
		CanQuery = false,
	})
	label(veil, Config.Zones[zi].name, Color3.new(1, 1, 1), Enum.NormalId.Back)
	gate:SetAttribute("Zone", zi)
	CollectionService:AddTag(gate, "Gate")
	gate.Parent = gates
end

-- Закрытый разлом «Скоро» в конце -------------------------------------------
do
	local x = Config.Zones[#Config.Zones].xEnd
	local wall = Instance.new("Model")
	wall.Name = "SoonRift"
	for i = -4, 4 do
		local s = rng:NextNumber(8, 13)
		block(wall, {
			Name = "Rock",
			Size = Vector3.new(s, s * rng:NextNumber(1.2, 2.2), s),
			CFrame = CFrame.new(x + 4, W.GroundY + s * 0.6, i * 7) * CFrame.Angles(0, rng:NextNumber(0, 3), 0),
			Color = Palette.Stone,
			Material = Enum.Material.Slate,
		})
	end
	block(wall, {
		Name = "Blocker",
		Size = Vector3.new(2, 60, HALF * 2 + 20),
		Position = Vector3.new(x, 30, 0),
		Transparency = 1,
	})
	local crack = block(wall, {
		Name = "ClosedCrack",
		Size = Vector3.new(0.5, 16, 10),
		Position = Vector3.new(x - 2, W.GroundY + 10, 0),
		Color = Color3.fromRGB(60, 50, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
	})
	label(crack, "Скоро", Color3.new(1, 1, 1), Enum.NormalId.Back)
	wall.Parent = map
end

-- Спавн --------------------------------------------------------------------
do
	local plaza = Instance.new("Model")
	plaza.Name = "Plaza"
	local c = W.PlazaCenter
	block(plaza, {
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, W.PlazaRadius * 2, W.PlazaRadius * 2),
		CFrame = CFrame.new(c.X, W.GroundY + 0.1, c.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(205, 196, 180),
		Material = Enum.Material.Limestone,
	})
	local board = block(plaza, {
		Name = "Leaderboard",
		Size = Vector3.new(12, 8, 1),
		CFrame = CFrame.new(c.X - 14, W.GroundY + 5, c.Z) * CFrame.Angles(0, math.rad(-90), 0),
		Color = Palette.Stone,
		Material = Enum.Material.Slate,
	})
	label(board, "Таблица лидеров\n(Шаг 2)", Color3.fromRGB(230, 230, 230), Enum.NormalId.Front)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlazaSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = Vector3.new(c.X, W.GroundY + 0.5, c.Z)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = plaza
	plaza.Parent = map
end

-- Базы ---------------------------------------------------------------------
local bases = folder(map, "Bases")
local BASE_X = { -60, 5, 70, 135 }
local BASE_Z = 75
local BASE_R = 30
local BASE_H = 4
local index = 0
for _, side in { 1, -1 } do
	for _, bx in BASE_X do
		index += 1
		local base = Instance.new("Model")
		base.Name = "Base" .. index
		local center = Vector3.new(bx, W.GroundY + BASE_H, side * BASE_Z)
		-- Смотрим на дорогу: «вперёд» базы — к оси X.
		local frame = CFrame.lookAt(center, Vector3.new(bx, center.Y, 0))

		block(base, {
			Name = "Platform",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(BASE_H, BASE_R * 2, BASE_R * 2),
			CFrame = CFrame.new(bx, W.GroundY + BASE_H / 2, side * BASE_Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Palette.Base,
		})
		-- Пандус к дороге. У WedgePart высокая сторона сзади (+Z), склон смотрит вперёд (−Z).
		block(base, {
			ClassName = "WedgePart",
			Name = "Ramp",
			Size = Vector3.new(14, BASE_H, 16),
			CFrame = frame * CFrame.new(0, -BASE_H / 2, -(BASE_R + 6)),
			Color = Palette.Base,
		})
		-- Светящиеся трещины по краю базы.
		for i = 1, 10 do
			local a = math.rad(i * 36 + rng:NextNumber(-8, 8))
			block(base, {
				Name = "EdgeCrack",
				Size = Vector3.new(0.6, 0.2, rng:NextNumber(3, 6)),
				CFrame = frame * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.1, -(BASE_R - 2)) * CFrame.Angles(0, math.rad(90), 0),
				Color = Palette.Zones[1].glow,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
		end

		-- Монолит-заглушка (Шаг 2).
		local monolith = block(base, {
			Name = "Monolith",
			Size = Vector3.new(6, 14, 6),
			CFrame = frame * CFrame.new(0, 7, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(176, 160, 128),
			Material = Enum.Material.Sandstone,
		})
		block(base, {
			Name = "MonolithCrystal",
			Size = Vector3.new(3, 4, 3),
			CFrame = frame * CFrame.new(0, 16, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0),
			Color = Palette.Zones[1].crystal,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
		})
		local _ = monolith

		-- Гнёзда вокруг Монолита.
		for k = 1, 3 do
			local a = math.rad((k - 1) * 120)
			local nestCf = frame * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -12)
			local nest = block(base, {
				Name = "Nest" .. k,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 6, 6),
				CFrame = nestCf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Palette.Stone,
				Material = Enum.Material.Slate,
			})
			for p = 1, 4 do
				local pa = math.rad(p * 90 + 45)
				block(base, {
					Name = "NestProng",
					Size = Vector3.new(0.6, 2.2, 0.6),
					CFrame = nestCf * CFrame.Angles(0, pa, 0) * CFrame.new(0, 1.6, -2.4) * CFrame.Angles(math.rad(-20), 0, 0),
					Color = Palette.Stone,
					Material = Enum.Material.Slate,
				})
			end
			nest:SetAttribute("Base", index)
			nest:SetAttribute("Index", k)
			CollectionService:AddTag(nest, "Nest")
		end

		-- Станция Ауры и Кольца.
		local stationCf = frame * CFrame.Angles(0, math.rad(90), 0) * CFrame.new(0, 0, -21)
		local station = Instance.new("Model")
		station.Name = "Station"
		local pedestal = block(station, {
			Name = "Pedestal",
			Size = Vector3.new(8, 1, 4),
			CFrame = stationCf * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(180), 0),
			Color = Palette.Stone,
			Material = Enum.Material.Slate,
		})
		block(station, {
			Name = "AuraPillar",
			Size = Vector3.new(1.6, 5, 1.6),
			CFrame = stationCf * CFrame.new(-2.5, 3.5, 0),
			Color = Color3.fromRGB(90, 200, 255),
			Material = Enum.Material.Neon,
		})
		block(station, {
			Name = "RingPillar",
			Size = Vector3.new(1.6, 5, 1.6),
			CFrame = stationCf * CFrame.new(2.5, 3.5, 0),
			Color = Color3.fromRGB(255, 200, 80),
			Material = Enum.Material.Neon,
		})
		local sign = block(station, {
			Name = "StationSign",
			Size = Vector3.new(7, 1.8, 0.4),
			CFrame = stationCf * CFrame.new(0, 7, 0) * CFrame.Angles(0, math.rad(180), 0),
			Color = Palette.Stone,
			Material = Enum.Material.Slate,
		})
		label(sign, "Аура и Кольцо", Color3.new(1, 1, 1), Enum.NormalId.Front)
		label(sign, "Аура и Кольцо", Color3.new(1, 1, 1), Enum.NormalId.Back)
		station.PrimaryPart = pedestal
		station:SetAttribute("Base", index)
		CollectionService:AddTag(station, "Station")
		station.Parent = base

		-- Точка появления игрока, место для лишних Сфер, табличка владельца.
		block(base, {
			Name = "SpawnPoint",
			Size = Vector3.new(2, 1, 2),
			CFrame = frame * CFrame.new(0, 3, -22),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		block(base, {
			Name = "Overflow",
			Size = Vector3.new(2, 1, 2),
			CFrame = frame * CFrame.Angles(0, math.rad(-90), 0) * CFrame.new(0, 0.5, -21),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
		})
		local post = block(base, {
			Name = "Sign",
			Size = Vector3.new(0.6, 6, 0.6),
			CFrame = frame * CFrame.new(9, 3, -(BASE_R - 1)),
			Color = Palette.Stone,
			Material = Enum.Material.Slate,
		})
		local bb = Instance.new("BillboardGui")
		bb.Name = "OwnerGui"
		bb.Size = UDim2.fromOffset(220, 50)
		bb.StudsOffset = Vector3.new(0, 4.5, 0)
		bb.MaxDistance = 250
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Label"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "Свободная база"
		t.TextScaled = true
		t.Font = Enum.Font.GothamBold
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.4
		t.Parent = bb
		bb.Parent = post

		base:SetAttribute("Index", index)
		CollectionService:AddTag(base, "Base")
		base.Parent = bases
	end
end

-- Свет: холодный неон на тёплом песке.
Lighting.ClockTime = 16.5
Lighting.Brightness = 2
Lighting.Ambient = Color3.fromRGB(70, 80, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(120, 125, 140)
if not Lighting:FindFirstChildOfClass("Atmosphere") then
	local atm = Instance.new("Atmosphere")
	atm.Density = 0.3
	atm.Haze = 1.2
	atm.Color = Color3.fromRGB(230, 210, 180)
	atm.Decay = Color3.fromRGB(120, 140, 180)
	atm.Parent = Lighting
end

map.Parent = workspace
return "Карта построена: баз " .. index

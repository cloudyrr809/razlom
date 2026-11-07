--!nocheck
-- Строит карту «Разломов»: рельеф (Terrain) + детали в Workspace.Map.
-- Запуск: Roblox Studio MCP, execute_luau (Edit):
--   loadstring(game.ServerScriptService.MapTools.BuildMap.Source)()
-- Повторный запуск стирает рельеф и Workspace.Map и строит заново.
-- Размеры зон, дороги и баз берёт из ReplicatedStorage.Shared.Config.
--
-- Теги для скриптов:
--   CreepCamp (Zone) — центр лагеря крипов в нише; −Z смотрит (примерно) на тропу
--   Base (Index) — база; внутри SpawnPoint, Sign, Monolith
--   Pedestal (Base, Index) — постамент для оружия; внутри деталь Top
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
local function crystal(parent, pos, height, color, tilt, widthK)
	local m = Instance.new("Model")
	m.Name = "Crystal"
	local w = height * (widthK or 0.32)
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

-- Монолит: ступенчатый постамент с рунными камнями, главный кристалл в кластере малых,
-- парящее кольцо осколков (клиент вращает, тег Spin) и луч в небо.
-- Опорная точка (WorldPivot) — та же, что у прежнего одиночного кристалла: от неё считают ярусы и эффекты.
local function monolith(parent, top, color)
	local m = Instance.new("Model")
	m.Name = "Monolith"
	local stone = Color3.fromRGB(130, 128, 136)
	local dark = Color3.fromRGB(92, 90, 100)
	local glowColor = color:Lerp(Color3.new(1, 1, 1), 0.2)

	-- Три ступени, между ними светящиеся пояса.
	local steps = { { r = 6, h = 0.8 }, { r = 4.9, h = 0.8 }, { r = 3.8, h = 1 } }
	local y = 0
	for i, s in steps do
		block(m, {
			Name = "MonolithPedestal",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(s.h, s.r * 2, s.r * 2),
			CFrame = CFrame.new(top + Vector3.new(0, y + s.h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i == 2 then dark else stone,
			Material = Enum.Material.Slate,
		})
		if i < #steps then
			glow(deco(m, {
				Name = "Band",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.12, s.r * 2 - 0.5, s.r * 2 - 0.5),
				CFrame = CFrame.new(top + Vector3.new(0, y + s.h + 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = glowColor,
				Material = Enum.Material.Neon,
				Transparency = 0.2,
			}))
		end
		y += s.h
	end
	local floor = top + Vector3.new(0, y, 0)

	-- Рунные камни по краю нижней ступени: стоячий камень и светящаяся руна на нём.
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = CFrame.lookAt(top + dir * 5.2 + Vector3.new(0, 0.8 + 1.1, 0), top + Vector3.new(0, 1.9, 0))
		block(m, {
			Name = "RuneStone",
			Size = Vector3.new(1.2, 2.2, 0.7),
			CFrame = at * CFrame.Angles(math.rad(-6), 0, math.rad(rng:NextNumber(-4, 4))),
			Color = dark,
			Material = Enum.Material.Slate,
		})
		glow(deco(m, {
			Name = "Rune",
			Size = Vector3.new(0.3, 1.3, 0.08),
			CFrame = at * CFrame.Angles(math.rad(-6), 0, 0) * CFrame.new(0, 0.1, 0.36), -- наружная сторона камня
			Color = glowColor,
			Material = Enum.Material.Neon,
		}))
		glow(deco(m, {
			Name = "Rune",
			Size = Vector3.new(0.8, 0.22, 0.08),
			CFrame = at * CFrame.Angles(math.rad(-6), 0, 0) * CFrame.new(0, 0.35, 0.36) * CFrame.Angles(0, 0, math.rad(25)),
			Color = glowColor,
			Material = Enum.Material.Neon,
		}))
	end

	-- Главный кристалл и кластер вокруг него, наклонённый наружу.
	local mainH = 12
	-- Главный тоньше обычного кристалла: толстый выглядел блоком.
	crystal(m, floor, mainH, color, Vector3.zero, 0.2).Name = "MainCrystal"
	for k = 0, 4 do
		local a = math.rad(k * 72 + rng:NextNumber(-12, 12))
		local hgt = rng:NextNumber(3.5, 6)
		local lean = math.rad(rng:NextNumber(22, 36))
		local pos = floor + Vector3.new(math.cos(a), 0, math.sin(a)) * 2.3
		local c = crystal(m, pos, hgt, color:Lerp(Color3.new(1, 1, 1), rng:NextNumber(0, 0.25)), Vector3.zero, 0.24)
		-- Наклон наружу: поворот вокруг основания по оси «вверх × наружу».
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local turn = CFrame.new(pos) * CFrame.fromAxisAngle(Vector3.yAxis:Cross(dir), lean) * CFrame.new(-pos)
		c:PivotTo(turn * c:GetPivot())
		local core = c:FindFirstChild("Core")
		local light = core and core:FindFirstChildOfClass("PointLight")
		if light then
			light:Destroy() -- свет даёт главный кристалл, лишние источники — лишняя нагрузка
		end
	end
	-- Осколки у подножия.
	for _ = 1, 7 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(2.6, 3.5)
		deco(m, {
			Name = "Shard",
			Size = Vector3.new(0.4, rng:NextNumber(0.7, 1.4), 0.4),
			CFrame = CFrame.new(floor + Vector3.new(math.cos(a) * d, 0.3, math.sin(a) * d)) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, math.pi), rng:NextNumber(-0.6, 0.6)),
			Color = color,
			Material = Enum.Material.Glass,
			Transparency = 0.15,
		})
	end

	-- Парящее кольцо из осколков на середине кристалла, клиент его медленно вращает.
	local halo = Instance.new("Model")
	halo.Name = "Halo"
	local haloCenter = floor + Vector3.new(0, mainH * 0.55, 0)
	local haloCount = 12
	for k = 1, haloCount do
		local a = k / haloCount * math.pi * 2
		glow(deco(halo, {
			Name = "HaloShard",
			Size = Vector3.new(0.35, 0.9, 0.35),
			CFrame = CFrame.new(haloCenter + Vector3.new(math.cos(a) * 3.6, math.sin(a * 3) * 0.25, math.sin(a) * 3.6)) * CFrame.Angles(0, -a, math.rad(30)),
			Color = glowColor,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		}))
	end
	halo.WorldPivot = CFrame.new(haloCenter)
	halo:SetAttribute("Speed", 0.35) -- радиан в секунду
	CollectionService:AddTag(halo, "Spin")
	halo.Parent = m

	-- Луч в небо: виден издалека, помогает найти свою базу.
	deco(m, {
		Name = "Beam",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(60, 0.6, 0.6),
		CFrame = CFrame.new(floor + Vector3.new(0, mainH + 30, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = glowColor,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})

	-- Искры поднимаются от подножия.
	local emitterPart = deco(m, {
		Name = "Sparks",
		Size = Vector3.new(4, 0.2, 4),
		CFrame = CFrame.new(floor + Vector3.new(0, 0.2, 0)),
		Transparency = 1,
	})
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(glowColor)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(2, 3.5)
	pe.Rate = 6
	pe.Speed = NumberRange.new(1.5, 3)
	pe.SpreadAngle = Vector2.new(15, 15)
	pe.Parent = emitterPart

	-- Опорная точка как у прежнего Монолита (кристалл 13 на высоте top + 1.6).
	m.WorldPivot = CFrame.new(top + Vector3.new(0, 1.6 + 13 / 2, 0))
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

-- Рельеф ------------------------------------------------------------------
-- Тропа идёт по дну долины (в зоне 2 — каньона), лагеря — карманы-ниши в её склонах.
-- Высота считается по точке: чем дальше от тропы, ниш и баз, тем выше склон.
terrain:SetMaterialColor(Enum.Material.Sand, Palette.Zones[1].sand)
terrain:SetMaterialColor(Enum.Material.Sandstone, Palette.Zones[2].sand)
terrain:SetMaterialColor(Enum.Material.Limestone, Palette.Zones[2].sandDark)
terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(150, 140, 128))
terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(176, 128, 90))
terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(128, 74, 52))

local MIN_X, MAX_X, MAX_Z = -170, Config.Zones[#Config.Zones].xEnd + 40, 175
local zone2x = Config.Zones[2].xStart
local roadEnd = Config.Zones[#Config.Zones].xEnd

-- Тропа. Та же формула, что Formulas.pathZ (модуль тут не подключить: клон без родителя).
local function pathZ(x)
	local t, z = x - G.X, 0
	for _, w in W.PathWaves do
		z += w.amp * math.sin(t / w.length * math.pi * 2)
	end
	return z
end
local function halfWidth(x)
	return HALF * (1 + W.PathWidthJitter * math.noise(x / W.PathWidthScale, 3.7, 1.3))
end
-- Рамка тропы в точке X: LookVector — вдоль тропы, RightVector — вбок.
local function pathFrame(x)
	return CFrame.lookAt(Vector3.new(x, 0, pathZ(x)), Vector3.new(x + 1, 0, pathZ(x + 1)))
end
-- Расстояние до края тропы (≤ 0 — на тропе). Поперёк, а не по Z: на крутых изгибах это важно.
local function pathEdge(x, z)
	if x < G.X - 4 or x > roadEnd + 6 then
		return math.huge
	end
	local slope = pathZ(x + 0.5) - pathZ(x - 0.5)
	local edgeNoise = math.noise(x / 9, z / 9, 5.1) * 2.5
	return math.abs(z - pathZ(x)) / math.sqrt(1 + slope * slope) - halfWidth(x) - edgeNoise
end

local function smooth(a, b, t)
	local k = math.clamp((t - a) / (b - a), 0, 1)
	return k * k * (3 - 2 * k)
end
local function fbm(x, z, scale, octaves, seed)
	local sum, amp, f = 0, 1, 1 / scale
	for i = 1, octaves do
		sum += amp * math.noise(x * f, z * f, seed + i * 17.31)
		amp *= 0.5
		f *= 2
	end
	return sum
end

-- Лагеря: заранее, чтобы рельеф вырезал под них ниши.
local NC = Config.Camps
local campList = {}
for zi, zone in Config.Zones do
	local len = zone.xEnd - zone.xStart
	for i = 1, NC.PerZone do
		local cx = zone.xStart + (i - 0.5) * len / NC.PerZone + rng:NextNumber(-3, 3)
		local side = if i % 2 == 1 then 1 else -1
		local frame = pathFrame(cx)
		local radius = NC.NicheRadius + rng:NextNumber(-NC.NicheRadiusJitter, NC.NicheRadiusJitter)
		local depth = halfWidth(cx) + NC.NicheDepth + rng:NextNumber(-1.5, 1.5)
		local center = frame.Position + frame.RightVector * side * depth
		local turn = CFrame.Angles(0, math.rad(rng:NextNumber(-NC.NicheTurn, NC.NicheTurn)), 0)
		table.insert(campList, {
			zone = zi,
			index = i,
			center = center,
			radius = radius,
			cf = CFrame.lookAt(center, frame.Position) * turn, -- −Z смотрит на тропу
		})
	end
end
local function campEdge(x, z)
	local best = math.huge
	for _, c in campList do
		local d = math.sqrt((x - c.center.X) ^ 2 + (z - c.center.Z) ^ 2) - c.radius
		if d < best then
			best = d
		end
	end
	return best
end

-- Плоская площадка баз и арены: круг вокруг входа, только по эту сторону от него.
local function basesEdge(x, z)
	local disc = math.sqrt((x - G.X) ^ 2 + z * z) - (W.BaseRingRadius + W.BaseRadius + 14)
	return math.max(disc, x - (G.X + 8))
end

-- Высота и материал поверхности в точке.
local function ground(x, z)
	local dPath, dCamp, dBase = pathEdge(x, z), campEdge(x, z), basesEdge(x, z)
	local d = math.min(dPath, dCamp, dBase)
	local zone2 = smooth(zone2x - 12, zone2x + 12, x + math.noise(z / 30, 2.2, 0) * 14)
	local onPath = dPath <= 0 or dCamp <= 0

	-- Склоны долины: в зоне 1 — пологие дюны, в зоне 2 — крутые стены каньона.
	local bank1 = 7 + 6 * fbm(x, z, 45, 3, 1)
	local bank2 = 15 + 9 * fbm(x, z, 38, 4, 2)
	local ramp1, ramp2 = 14, 9
	-- У ниш склон круче — карман виден сразу.
	-- Только рядом с нишей и там, где ниша ближе тропы.
	local nicheSteep = smooth(12, 3, dCamp) * smooth(-1, 3, dPath - dCamp)
	local ramp = (ramp1 + (ramp2 - ramp1) * zone2) * (1 - 0.6 * nicheSteep)
	local bank = bank1 + (bank2 - bank1) * zone2
	local h = bank * smooth(0, ramp, d)
	-- Вдали — крупные дюны и выходы скал.
	local far = smooth(15, 70, d)
	h += far * (9 * fbm(x, z, 95, 3, 3) + 4)
	local outcrop = math.max(0, fbm(x, z, 40, 2, 4) - 0.42) * 40 * far
	h += outcrop
	-- Край карты поднимается: долину замыкают холмы.
	h += 28 * smooth(MAX_Z - 55, MAX_Z, math.abs(z)) + 28 * smooth(MIN_X + 50, MIN_X, x) + 34 * smooth(MAX_X - 45, MAX_X, x)
	-- Мелкая рябь, кроме площадок.
	h += math.noise(x / 7, z / 7, 9.9) * 0.8 * smooth(0, 4, d)
	h = math.clamp(h, 0, 60)

	local mat
	if onPath then
		mat = if zone2 > 0.5 then Enum.Material.Mud else Enum.Material.Ground
	elseif dBase <= 0 then
		mat = Enum.Material.Sand
	elseif zone2 > 0.5 then
		mat = "strata"
	elseif outcrop > 3 or (nicheSteep > 0.4 and d > 1.5) then
		mat = Enum.Material.Rock
	else
		mat = Enum.Material.Sand
	end
	return h, mat
end

-- Пишем вокселями (4 стада) кусками вдоль X, чтобы Studio не зависал.
do
	local VOX = 4
	local Y0, Y1 = -12, 64
	local x0, x1 = math.floor(MIN_X / VOX) * VOX, math.ceil(MAX_X / VOX) * VOX
	local z0, z1 = -math.ceil(MAX_Z / VOX) * VOX, math.ceil(MAX_Z / VOX) * VOX
	local ny, nz = (Y1 - Y0) / VOX, (z1 - z0) / VOX
	local CHUNK = 8
	local cx = x0
	while cx < x1 do
		local nx = math.min(CHUNK, (x1 - cx) / VOX)
		local mats, occs = {}, {}
		for ix = 1, nx do
			mats[ix], occs[ix] = {}, {}
			for iy = 1, ny do
				mats[ix][iy], occs[ix][iy] = {}, {}
			end
			local x = cx + (ix - 0.5) * VOX
			for iz = 1, nz do
				local z = z0 + (iz - 0.5) * VOX
				local h, mat = ground(x, z)
				for iy = 1, ny do
					local y = Y0 + (iy - 1) * VOX
					-- Видимая поверхность встаёт на полвокселя выше заполненного — сдвигаем вниз.
					local occ = math.clamp((h - y) / VOX - 0.5, 0, 1)
					local m = mat
					if m == "strata" then
						-- Слоистые стены каньона.
						m = if math.floor((y + math.noise(x / 20, z / 20) * 3) / 6) % 2 == 0 then Enum.Material.Sandstone else Enum.Material.Limestone
					end
					mats[ix][iy][iz] = if occ > 0 then m else Enum.Material.Air
					occs[ix][iy][iz] = occ
				end
			end
		end
		local region = Region3.new(Vector3.new(cx, Y0, z0), Vector3.new(cx + nx * VOX, Y1, z1))
		terrain:WriteVoxels(region, VOX, mats, occs)
		cx += nx * VOX
		task.wait()
	end
end

-- Высота поверхности в точке (для расстановки деталей).
local function groundY(x, z)
	return (ground(x, z))
end

-- Мелочь для пейзажа ----------------------------------------------------------
-- Валун, утопленный в землю.
local function boulder(parent, x, z, s, color, material)
	return rock(parent, Vector3.new(x, groundY(x, z) + s * 0.25, z), Vector3.new(s * rng:NextNumber(0.9, 1.4), s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.9, 1.3)), color, material)
end

-- Сухой куст: несколько жёлто-зелёных комков.
local function shrub(parent, x, z, s)
	local y = groundY(x, z)
	for _ = 1, rng:NextInteger(2, 4) do
		local b = rng:NextNumber(0.8, 1.5) * s
		deco(parent, {
			Name = "Shrub",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * b,
			Position = Vector3.new(x + rng:NextNumber(-0.8, 0.8) * s, y + b * 0.3, z + rng:NextNumber(-0.8, 0.8) * s),
			Color = Color3.fromRGB(150, 140, 80):Lerp(Color3.fromRGB(110, 120, 60), rng:NextNumber()),
			Material = Enum.Material.Grass,
		})
	end
end

-- Сухое дерево: кривой ствол и пара голых веток.
local function deadTree(parent, x, z, s)
	local m = Instance.new("Model")
	m.Name = "DeadTree"
	local base = CFrame.new(x, groundY(x, z) - 0.5, z) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, 6.3), math.rad(rng:NextNumber(-8, 8)))
	local wood = Color3.fromRGB(110, 86, 70)
	local trunkH = 7 * s
	block(m, { Name = "Trunk", Size = Vector3.new(0.9, trunkH, 0.9) * Vector3.new(s, 1, s), CFrame = base * CFrame.new(0, trunkH / 2, 0), Color = wood, Material = Enum.Material.Wood })
	for i = 1, rng:NextInteger(2, 4) do
		local len = rng:NextNumber(2.5, 4.5) * s
		local at = base * CFrame.new(0, trunkH * rng:NextNumber(0.5, 0.95), 0) * CFrame.Angles(0, i * 2.1 + rng:NextNumber(-0.4, 0.4), 0) * CFrame.Angles(math.rad(rng:NextNumber(35, 60)), 0, 0)
		deco(m, { Name = "Branch", Size = Vector3.new(0.4 * s, len, 0.4 * s), CFrame = at * CFrame.new(0, len / 2, 0), Color = wood, Material = Enum.Material.Wood })
	end
	m.Parent = parent
end

-- Тропа и лагеря --------------------------------------------------------------
local road = folder(map, "Road")
for zi, zone in Config.Zones do
	local colors = Palette.Zones[zi]
	local rockColor = if zi == 1 then Color3.fromRGB(128, 126, 130) else colors.sandDark
	local rockMaterial = if zi == 1 then Enum.Material.Slate else Enum.Material.Sandstone

	-- Камни и кусты вдоль краёв тропы.
	local x = zone.xStart + rng:NextNumber(2, 6)
	while x < zone.xEnd do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local frame = pathFrame(x)
		local p = frame.Position + frame.RightVector * side * (halfWidth(x) + rng:NextNumber(0, 5))
		if campEdge(p.X, p.Z) > 3 then
			if rng:NextNumber() < 0.6 then
				for _ = 1, rng:NextInteger(1, 3) do
					boulder(road, p.X + rng:NextNumber(-2, 2), p.Z + rng:NextNumber(-2, 2), rng:NextNumber(1.2, 3.5), rockColor, rockMaterial)
				end
			elseif zi == 1 then
				shrub(road, p.X, p.Z, rng:NextNumber(0.8, 1.3))
			end
		end
		x += rng:NextNumber(5, 11)
	end

	-- На склонах: сухие деревья, кусты, валуны, в зоне 1 — кристаллы.
	for _ = 1, (if zi == 1 then 40 else 28) do
		local px = rng:NextNumber(zone.xStart, zone.xEnd)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local pz = pathZ(px) + side * rng:NextNumber(HALF + 6, HALF + 45)
		if campEdge(px, pz) > 4 and pathEdge(px, pz) > 3 then
			local roll = rng:NextNumber()
			if zi == 1 and roll < 0.25 then
				crystal(road, Vector3.new(px, groundY(px, pz) - 0.6, pz), rng:NextNumber(4, 9), colors.crystal, Vector3.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 3), rng:NextNumber(-0.3, 0.3)))
			elseif roll < 0.45 then
				deadTree(road, px, pz, rng:NextNumber(0.8, 1.4))
			elseif roll < 0.7 and zi == 1 then
				shrub(road, px, pz, rng:NextNumber(0.9, 1.6))
			else
				boulder(road, px, pz, rng:NextNumber(2.5, 6), rockColor, rockMaterial)
			end
		end
	end

	-- Ветвистые трещины по тропе (зона 1 — голубые, зона 2 — лава).
	for _ = 1, (if zi == 1 then 7 else 5) do
		local px = rng:NextNumber(zone.xStart + 6, zone.xEnd - 6)
		local p = Vector3.new(px, W.GroundY + 0.07, pathZ(px) + rng:NextNumber(-0.6, 0.6) * halfWidth(px))
		crack(road, p, Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)), rng:NextNumber(8, 14), 0.3, colors.glow, 2)
	end
	task.wait()
end

-- Ниши: разлом в глубине, валуны у стен, факелы у входа, метка для сервера.
local camps = folder(map, "Camps")
for _, c in campList do
	local colors = Palette.Zones[c.zone]
	local rockColor = if c.zone == 1 then Color3.fromRGB(128, 126, 130) else colors.sandDark
	local rockMaterial = if c.zone == 1 then Enum.Material.Slate else Enum.Material.Sandstone
	local R = c.radius
	local niche = Instance.new("Model")
	niche.Name = `Camp{c.zone}_{c.index}`

	-- Валуны у задней стены, разные, кучками.
	for _ = 1, rng:NextInteger(4, 7) do
		local a = rng:NextNumber(-2.1, 2.1) -- угол от задней точки ниши
		local s = rng:NextNumber(1.5, 4.5)
		local p = c.cf:PointToWorldSpace(Vector3.new(math.sin(a) * (R - s * 0.3), 0, math.cos(a) * (R - s * 0.3)))
		boulder(niche, p.X, p.Z, s, rockColor, rockMaterial)
	end
	-- Разлом в глубине ниши — отсюда крипы и берутся.
	local back = rng:NextNumber(-0.5, 0.5)
	local riftPos = c.cf:PointToWorldSpace(Vector3.new(math.sin(back) * R * 0.72, W.GroundY + 0.08, math.cos(back) * R * 0.72))
	local hole = deco(niche, {
		Name = "Rift",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, rng:NextNumber(2.4, 3.6), rng:NextNumber(2.4, 3.6)),
		CFrame = CFrame.new(riftPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = colors.glow,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(colors.glow)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.EmissionDirection = Enum.NormalId.Right
	emitter.Rate = 5
	emitter.Parent = hole
	for _ = 1, rng:NextInteger(2, 4) do
		local dir = c.cf:VectorToWorldSpace(Vector3.new(rng:NextNumber(-1, 1), 0, -rng:NextNumber(0.3, 1)))
		crack(niche, riftPos, dir, rng:NextNumber(5, 9), 0.3, colors.glow, 1)
	end
	-- Факелы у входа, не всегда оба.
	for _, sgn in { -1, 1 } do
		if rng:NextNumber() < 0.8 then
			local a = sgn * rng:NextNumber(1.9, 2.3)
			torch(niche, c.cf:PointToWorldSpace(Vector3.new(math.sin(a) * (R - 1.5), 0, math.cos(a) * (R - 1.5))))
		end
	end
	-- Невидимая метка лагеря: сервер ставит крипов по Config.Camps.Slots от неё.
	local marker = deco(niche, {
		Name = "CampPoint",
		Size = Vector3.new(1, 1, 1),
		CFrame = c.cf + Vector3.new(0, W.GroundY + 0.5, 0),
		Transparency = 1,
	})
	marker:SetAttribute("Zone", c.zone)
	CollectionService:AddTag(marker, "CreepCamp")
	niche.Parent = camps
end
task.wait()

-- Указатели зон у начала каждой зоны, у края тропы ---------------------------------
local signs = folder(map, "ZoneSigns")
for zi = 1, #Config.Zones do
	local x = Config.Zones[zi].xStart + 3
	local frame = pathFrame(x)
	local at = frame.Position - frame.RightVector * (halfWidth(x) + 1)
	local cf = CFrame.lookAt(at, at + frame.LookVector)
	local sign = Instance.new("Model")
	sign.Name = "Zone" .. zi
	for _, dx in { -5, 5 } do
		block(sign, {
			Name = "Post",
			Size = Vector3.new(0.8, 9, 0.8),
			CFrame = cf * CFrame.new(dx, 4.5, 0),
			Color = Color3.fromRGB(90, 66, 50),
			Material = Enum.Material.Wood,
		})
	end
	local board = block(sign, {
		Name = "Board",
		Size = Vector3.new(12, 3.5, 0.5),
		CFrame = cf * CFrame.new(0, 7, 0),
		Color = Color3.fromRGB(70, 58, 52),
		Material = Enum.Material.Wood,
	})
	glow(deco(sign, {
		Name = "Trim",
		Size = Vector3.new(12.4, 0.3, 0.6),
		CFrame = cf * CFrame.new(0, 8.9, 0),
		Color = Palette.Zones[zi].glow,
		Material = Enum.Material.Neon,
	}))
	label(board, `Зона {zi} · {Config.Zones[zi].name}`, Color3.new(1, 1, 1), Enum.NormalId.Front)
	label(board, `Зона {zi} · {Config.Zones[zi].name}`, Color3.new(1, 1, 1), Enum.NormalId.Back)
	sign.Parent = signs
end

-- Закрытый разлом «Скоро» в конце.
do
	local x = roadEnd
	local z0 = pathZ(x)
	local wall = Instance.new("Model")
	wall.Name = "SoonRift"
	for i = -5, 5 do
		local s = rng:NextNumber(9, 14)
		rock(wall, Vector3.new(x + 5, s * 0.6, z0 + i * 6), Vector3.new(s, s * rng:NextNumber(1.3, 2.4), s), Palette.Zones[2].sandDark, Enum.Material.Sandstone)
	end
	block(wall, { Name = "Blocker", Size = Vector3.new(2, 60, HALF * 2 + 30), Position = Vector3.new(x, 30, z0), Transparency = 1 })
	local closed = deco(wall, {
		Name = "ClosedCrack",
		Size = Vector3.new(0.5, 16, 10),
		Position = Vector3.new(x - 1, 10, z0),
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

	-- Монолит (ярусы растут поверх — сервер, Monolith.luau).
	monolith(base, top, Color3.fromRGB(160, 215, 255))

	-- Кольцо постаментов вокруг Монолита: 10 мест, работают первые 3 + 1 за ярус.
	for k = 1, Config.Monolith.MaxPedestals do
		local a = math.rad((k - 1) * 360 / Config.Monolith.MaxPedestals + 18)
		local pcf = frame * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -10)
		local ped = block(base, {
			Name = "Pedestal" .. k,
			Size = Vector3.new(2.2, 2.6, 2.2),
			CFrame = pcf * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(130, 126, 150),
			Material = Enum.Material.Slate,
			Transparency = if k <= Config.Monolith.BasePedestals then 0 else 0.7,
		})
		deco(ped, {
			Name = "Top",
			Size = Vector3.new(1.9, 0.3, 1.9),
			CFrame = pcf * CFrame.new(0, 2.75, 0) * CFrame.Angles(0, math.rad(45), 0),
			Color = Color3.fromRGB(110, 140, 170),
			Material = Enum.Material.Neon,
			Transparency = if k <= Config.Monolith.BasePedestals then 0.2 else 0.85,
		})
		ped:SetAttribute("Base", index)
		ped:SetAttribute("Index", k)
		CollectionService:AddTag(ped, "Pedestal")
	end

	block(base, {
		Name = "SpawnPoint",
		Size = Vector3.new(2, 1, 2),
		CFrame = frame * CFrame.new(0, 3, -17),
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

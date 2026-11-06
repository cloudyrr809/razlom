--!strict
-- Вскрытие Сферы по центру экрана; игра на фоне идёт.
-- 8–10 кликов или зажатие, трещины, с 4-го удара свет перебирает цвета редкости
-- и задерживается на редких, раскол → карточка оружия. Если Сфер несколько — сразу следующая.
-- Результат знает только сервер; клиент лишь показывает.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local Input = require(script.Parent.Input)
local CreepFx = require(script.Parent.CreepFx)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local openRemote = Remotes:WaitForChild("OpenSphere") :: RemoteEvent
local revealFx = Remotes:WaitForChild("RevealFx") :: RemoteEvent

local RevealScreen = {}
local player = Players.LocalPlayer
local SOUND_DING = "rbxasset://sounds/electronicpingshort.wav"
local SOUND_CRACK = "rbxasset://sounds/swordslash.wav"

local active = false -- идёт вскрытие (удары идут по Сфере)
local showing = false -- экран открыт
local pending = false -- на сервере есть начатое вскрытие
local hits, need = 0, 10
local gui: ScreenGui
local root: Frame
local viewport: ViewportFrame
local sphereModel: Model?
local core: BasePart?
local counter: TextLabel
local hintText: TextLabel
local card: Frame
local oddsWin: Window.Win
local spin = 0
local shakeUntil = 0

function RevealScreen.isActive(): boolean
	return active and showing
end

local function pct(p: number): string
	local v = p * 100
	local text = if v >= 1 then string.format("%.1f", v) elseif v >= 0.01 then string.format("%.2f", v) else string.format("%.4f", v)
	return (string.gsub(text, "%.", ",")) .. "%"
end

local function pityText(): string
	local left = Config.Spheres.PityAfter - Store.data.pity
	if left <= 0 then
		return "Следующая Сфера — гарантированно с мутацией"
	end
	return `До гарантированной мутации: {left}`
end

local function buildOdds()
	oddsWin = Window.new("Odds", "Шансы", 560, 520)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = oddsWin.content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	local order = 0
	local function line(text: string, color: Color3?, size: number?)
		order += 1
		Theme.text("Line" .. order, scroll, text, size or 17, {
			Size = UDim2.new(1, -10, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = color or Theme.Color.Text,
			LayoutOrder = order,
		})
	end
	local function fill()
		for _, c in scroll:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		order = 0
		line(pityText(), Theme.Color.Crit, 19)
		if Store.data.opened < Config.Spheres.GuaranteedFirst then
			line(`Ещё {Config.Spheres.GuaranteedFirst - Store.data.opened} Сфер не дадут оружие слабее самого слабого в постаментах.`, Theme.Color.Good)
		end
		line("Редкость оружия (одинакова для всех Сфер):", Theme.Color.TextDim)
		local total = 0
		for _, r in Config.Rarities do
			total += r.weight
		end
		for i, r in Config.Rarities do
			line(`  {r.weapon} · {r.name} (урон ×{r.mult}): {pct(r.weight / total)}`, Palette.Rarity[i])
		end
		local boosts: { number } = { 1 }
		for _, m in Config.CreepMutations do
			if m.weaponMutationBoost > 1 and not table.find(boosts, m.weaponMutationBoost) then
				table.insert(boosts, m.weaponMutationBoost)
			end
		end
		for _, boost in boosts do
			line(if boost == 1 then "Мутация оружия (обычная Сфера):" else `Мутация в Сфере с шансом ×{boost}:`, Theme.Color.TextDim)
			local odds = Formulas.weaponMutationOdds(boost)
			line(`  без мутации: {pct(odds[0])}`)
			for i, m in Config.WeaponMutations do
				line(`  {m.nameFem} (урон ×{m.mult}): {pct(odds[i])}`, Palette.Mutation[i])
			end
		end
		line("Мутация проверяется от редкой к частой; гарантии поднимают итог минимум до Заряженной. Сфера с первого мутанта — минимум Заряженная.", Theme.Color.TextDim, 14)
	end
	oddsWin.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if oddsWin.isOpen() then
			fill()
		end
	end)
end

local function clearViewport()
	for _, c in viewport:GetChildren() do
		if not c:IsA("Camera") then
			c:Destroy()
		end
	end
	sphereModel, core = nil, nil
end

local function showSphere(zone: number)
	clearViewport()
	local m = Models.sphere(zone, CFrame.new())
	m.Parent = viewport
	sphereModel = m
	local c = m:FindFirstChild("Core")
	core = if c and c:IsA("BasePart") then c else nil
end

local function addCrack()
	local m = sphereModel
	local shell = m and m:FindFirstChild("Shell")
	if not m or not shell or not shell:IsA("BasePart") then
		return
	end
	-- Свет сквозь трещины: тёплый, а с 4-го удара — цвет редкости, дольше на редких.
	local color = Color3.fromRGB(255, 190, 80)
	if hits >= Config.Spheres.TeaseFromHit then
		local roll = math.random()
		local rarity = if roll < 0.3 then 1 elseif roll < 0.55 then 2 elseif roll < 0.75 then 3 elseif roll < 0.9 then 4 else 5
		color = Palette.Rarity[rarity]
		if rarity >= 4 then
			CreepFx.playSound(SOUND_DING, 0.4, 0.8 + rarity * 0.1, nil)
		end
	end
	for k = 1, 2 do
		local crack = Instance.new("Part")
		crack.Name = "CrackFx"
		crack.Anchored = true
		crack.Material = Enum.Material.Neon
		crack.Color = color
		crack.Size = Vector3.new(0.12, 0.9 + hits / need, 0.12)
		crack.CFrame = CFrame.Angles(0, math.rad(hits * 53 + k * 140), math.rad(hits * 29 + k * 60)) * CFrame.new(0, 0, -1.48)
		crack.Parent = m
	end
	for _, c in m:GetChildren() do
		if c.Name == "CrackFx" and c:IsA("BasePart") and hits >= Config.Spheres.TeaseFromHit then
			c.Color = color
		end
	end
	if core then
		core.Color = color
	end
	shakeUntil = os.clock() + 0.12
	CreepFx.playSound(SOUND_CRACK, 0.3, 0.6 + hits * 0.05, nil)
	counter.Text = `{hits}/{need}`
end

local function showCard(w: Formulas.Weapon, gain: number, left: number)
	card.Visible = true
	local color = if w.mutation > 0 then Palette.Mutation[w.mutation] else Palette.Rarity[w.rarity]
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end
	local name = card:FindFirstChild("Name") :: TextLabel
	name.Text = Formulas.weaponName(w)
	name.TextColor3 = color
	local rarity = card:FindFirstChild("Rarity") :: TextLabel
	rarity.Text = `{Config.Rarities[w.rarity].name} · зона {w.zone}`
	rarity.TextColor3 = Palette.Rarity[w.rarity]
	local dmg = card:FindFirstChild("Damage") :: TextLabel
	dmg.Text = "Урон " .. Formulas.short(Formulas.weaponDamage(w))
	local result = card:FindFirstChild("Result") :: TextLabel
	if gain > 0 then
		result.Text = `+{Formulas.short(gain)} к арсеналу — вставь на базе!`
		result.TextColor3 = Theme.Color.Good
	else
		result.Text = "В инвентарь"
		result.TextColor3 = Theme.Color.TextDim
	end
	local nextLabel = card:FindFirstChild("Next") :: TextLabel
	nextLabel.Text = if left > 0 then `Следующая Сфера… (ещё {left})` else ""
	local scale = card:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.6
	Theme.tween(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
end

-- Раскол: половинки разлетаются в окошке, внутри — друза цвета выпавшего.
local function split(w: Formulas.Weapon)
	clearViewport()
	local inner = if w.mutation > 0 then Palette.Mutation[w.mutation] else Palette.Rarity[w.rarity]
	for side = -1, 1, 2 do
		local half = Instance.new("Part")
		half.Anchored = true
		half.Material = Enum.Material.Sandstone
		half.Color = Color3.fromRGB(196, 140, 92)
		half.Size = Vector3.new(1.5, 3, 3)
		half.CFrame = CFrame.new(side * 0.75, 0, 0)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = half
		half.Parent = viewport
		local cut = Instance.new("Part")
		cut.Anchored = true
		cut.Material = Enum.Material.Neon
		cut.Color = inner
		cut.Size = Vector3.new(0.2, 2.4, 2.4)
		local cutMesh = Instance.new("SpecialMesh")
		cutMesh.MeshType = Enum.MeshType.Sphere
		cutMesh.Parent = cut
		cut.CFrame = half.CFrame * CFrame.new(-side * 0.7, 0, 0)
		cut.Parent = viewport
		local out = CFrame.new(side * 1.7, -0.9, 0) * CFrame.Angles(0, 0, math.rad(side * 35))
		TweenService:Create(half, TweenInfo.new(0.35, Enum.EasingStyle.Back), { CFrame = out }):Play()
		TweenService:Create(cut, TweenInfo.new(0.35, Enum.EasingStyle.Back), { CFrame = out * CFrame.new(-side * 0.7, 0, 0) }):Play()
	end
	-- В ViewportFrame нет физики: детали не следуют за сварками, поэтому крутим модель целиком.
	local handle = Models.weaponHandle(w.zone, w.rarity, w.mutation)
	local model = Instance.new("Model")
	model.Name = "Weapon"
	for _, p in handle:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.Parent = model
		end
	end
	handle.Anchored = true
	handle.Parent = model
	model.PrimaryPart = handle
	-- Насколько центр всей модели выше центра рукояти (по ней крутим).
	local box = model:GetBoundingBox()
	model:SetAttribute("CenterY", handle.CFrame:PointToObjectSpace(box.Position).Y)
	model.Parent = viewport
	CreepFx.playSound(SOUND_DING, 0.8, 1, nil)
end

local function close()
	showing = false
	active = false
	root.Visible = false
	Input.release("reveal")
end

function RevealScreen.open()
	if #Store.data.spheres == 0 and not pending then
		return
	end
	openRemote:FireServer()
end

local function onReveal(kind: string, data: any)
	if kind == "start" then
		active = true
		pending = true
		showing = true
		hits, need = data.hits, data.need
		card.Visible = false
		root.Visible = true
		showSphere(data.zone)
		counter.Text = `{hits}/{need}`
		hintText.Text = "Кликай по Сфере!"
	elseif kind == "crack" then
		hits = data.hits
		addCrack()
	elseif kind == "done" then
		active = false
		pending = false
		hits = need
		counter.Text = ""
		hintText.Text = ""
		local w = data.weapon :: Formulas.Weapon
		split(w)
		showCard(w, data.gain, data.left)
		if w.mutation > 0 or w.rarity >= 4 then
			CreepFx.playSound(SOUND_DING, 1, 0.6, nil)
		end
		task.delay(if data.left > 0 then 1.8 else 2.6, function()
			if not showing or active then
				return
			end
			if data.left > 0 then
				openRemote:FireServer()
			else
				close()
			end
		end)
	end
end

function RevealScreen.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Reveal"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	root = Theme.frame("Root", gui, {
		Size = UDim2.fromOffset(340, 460),
		Position = UDim2.fromScale(0.5, 0.58),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(340, 460)
	limit.Parent = root
	-- На низком экране (телефон боком) уменьшаем весь экран вскрытия, чтобы не налезал на HUD.
	local fit = Instance.new("UIScale")
	fit.Parent = root
	local function refit()
		local h = gui.AbsoluteSize.Y
		fit.Scale = math.clamp((h - 150) / 460, 0.5, 1)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	task.defer(refit)

	viewport = Instance.new("ViewportFrame")
	viewport.Name = "Sphere"
	viewport.Size = UDim2.fromOffset(300, 300)
	viewport.Position = UDim2.fromScale(0.5, 0)
	viewport.AnchorPoint = Vector2.new(0.5, 0)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(170, 160, 150)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.LightDirection = Vector3.new(-1, -1, -0.6)
	viewport.Parent = root
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.2, 8), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- Нажатие на Сферу (зажатие тоже работает).
	local hitArea = Instance.new("TextButton")
	hitArea.Name = "HitArea"
	hitArea.Size = UDim2.fromScale(1, 1)
	hitArea.BackgroundTransparency = 1
	hitArea.Text = ""
	hitArea.Parent = viewport
	hitArea.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Input.press("reveal")
		end
	end)
	hitArea.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Input.release("reveal")
		end
	end)

	counter = Theme.text("Counter", root, "", 30, {
		Size = UDim2.new(1, 0, 0, 34),
		Position = UDim2.fromOffset(0, 290),
		Font = Theme.Display,
		TextStrokeTransparency = 0.2,
	})
	hintText = Theme.text("Hint", root, "", 20, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 322),
		Font = Theme.Display,
		TextColor3 = Theme.Color.Accent,
		TextStrokeTransparency = 0.3,
	})

	card = Theme.frame("Card", root, {
		Size = UDim2.fromOffset(320, 150),
		Position = UDim2.new(0.5, 0, 0, 300),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.05,
		Visible = false,
	})
	Theme.corner(card, UDim.new(0, 14))
	Theme.stroke(card, Color3.new(1, 1, 1), 3)
	Instance.new("UIScale").Parent = card
	Theme.text("Name", card, "", 26, { Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 8), Font = Theme.Display })
	Theme.text("Rarity", card, "", 16, { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 40), Font = Theme.Display })
	Theme.text("Damage", card, "", 22, { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 62), Font = Theme.Display })
	Theme.text("Result", card, "", 18, { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 92), Font = Theme.Display })
	Theme.text("Next", card, "", 14, {
		Size = UDim2.new(1, -16, 0, 20),
		Position = UDim2.fromOffset(8, 122),
		TextColor3 = Theme.Color.TextDim,
	})

	local oddsButton = Theme.button("Odds", root, "Шансы", "secondary", {
		Size = UDim2.fromOffset(100, 36),
		Position = UDim2.fromOffset(0, 10),
		Font = Theme.Display,
	})
	local closeButton = Theme.button("Close", root, "X", "secondary", {
		Size = UDim2.fromOffset(40, 36),
		Position = UDim2.new(1, 0, 0, 10),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.Display,
	})
	closeButton.Activated:Connect(close)
	buildOdds()
	oddsButton.Activated:Connect(function()
		oddsWin.open()
	end)
	RevealScreen.openOdds = function()
		oddsWin.open()
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	revealFx.OnClientEvent:Connect(onReveal)

	Input.revealing = RevealScreen.isActive
	Input.onRevealHit = function()
		-- Сразу отклик на клик, не дожидаясь сервера.
		if sphereModel then
			local s = sphereModel:FindFirstChild("Shell")
			if s and s:IsA("BasePart") then
				shakeUntil = os.clock() + 0.08
			end
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		if not showing then
			return
		end
		spin += dt
		local cam = viewport.CurrentCamera
		if cam then
			local shake = if os.clock() < shakeUntil then Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * 0.25 else Vector3.zero
			cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(spin * 0.6) * 1.2, 1.2, 8) + shake, Vector3.zero)
		end
		local weapon = viewport:FindFirstChild("Weapon")
		if weapon and weapon:IsA("Model") then
			-- Оружие лежит по диагонали и крутится; сдвиг к середине клинка, чтобы влезало целиком.
			local centerY = (weapon:GetAttribute("CenterY") :: number?) or 0
			weapon:PivotTo(CFrame.new(0, math.sin(spin * 2) * 0.15, 0) * CFrame.Angles(0, spin * 1.5, math.rad(50)) * CFrame.new(0, -centerY, 0))
		end
	end)
end

RevealScreen.openOdds = function() end

return RevealScreen

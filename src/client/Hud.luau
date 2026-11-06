--!strict
-- Постоянный экран. Центр свободен для боя:
--   сверху — осколки, серия убийств, уровень Монолита и сколько до следующего;
--   слева — Сферы со счётчиком и кнопкой «Открыть», урон арсенала;
--   справа — круглые кнопки «Оружие» и «Улучшения» (пульсирует, когда хватает на уровень);
--   снизу справа на телефоне — большая кнопка «Удар».

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local World = require(script.Parent.World)
local Input = require(script.Parent.Input)

local Hud = {}
local player = Players.LocalPlayer

local actions: { [string]: () -> () } = {}
function Hud.on(name: string, fn: () -> ())
	actions[name] = fn
end
local function run(name: string)
	local fn = actions[name]
	if fn then
		fn()
	end
end
local affordable: () -> boolean = function()
	return false
end
function Hud.setAffordable(fn: () -> boolean)
	affordable = fn
end

local function glowStroke(parent: GuiObject, a: Color3, b: Color3, thickness: number)
	local s = Theme.stroke(parent, Color3.new(1, 1, 1), thickness)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Parent = s
	return s
end

-- Значок осколка: повёрнутый ромб с переливом.
function Hud.gem(parent: Instance, px: number, position: UDim2): Frame
	local gem = Theme.frame("Gem", parent, {
		Size = UDim2.fromOffset(px * 0.62, px * 0.62),
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
	})
	Theme.corner(gem, UDim.new(0, 3))
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 250, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 210, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 130, 255)),
	})
	g.Rotation = 45
	g.Parent = gem
	Theme.stroke(gem, Color3.fromRGB(40, 90, 160), 1.5)
	return gem
end

local function roundButton(name: string, parent: Instance, icon: string, caption: string, px: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(px, px)
	b.BackgroundColor3 = Theme.Color.Panel
	b.BackgroundTransparency = 0.1
	b.AutoButtonColor = false
	b.Text = ""
	b.Parent = parent
	Theme.corner(b, UDim.new(0.5, 0))
	glowStroke(b, Color3.fromRGB(90, 220, 255), Color3.fromRGB(180, 110, 255), 3)
	Theme.text("Icon", b, icon, px * 0.4, {
		Size = UDim2.fromScale(1, 0.62),
		Position = UDim2.fromScale(0, 0.08),
		Font = Theme.Display,
	})
	Theme.text("Caption", b, caption, math.max(11, px * 0.15), {
		Size = UDim2.fromScale(1, 0.24),
		Position = UDim2.fromScale(0, 0.66),
		Font = Theme.Display,
		TextColor3 = Theme.Color.TextDim,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		Theme.tween(scale, TweenInfo.new(0.06), { Scale = 0.92 })
	end)
	b.MouseButton1Up:Connect(function()
		Theme.tween(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 })
	end)
	b.MouseLeave:Connect(function()
		scale.Scale = 1
	end)
	return b
end

local shardsBounce: UIScale? = nil
-- Подпрыгивание счётчика осколков (зовут эффекты при добыче).
function Hud.bounceShards()
	if shardsBounce then
		shardsBounce.Scale = 1.18
		Theme.tween(shardsBounce, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 })
	end
end

local streakSteps, streakUntil = 0, 0
function Hud.setStreak(steps: number, mult: number)
	streakSteps = steps
	streakUntil = os.clock() + Config.Streak.Window
	local _ = mult
end

local spheresIcon: Frame? = nil
function Hud.spheresIconPosition(): Vector2?
	if spheresIcon then
		return spheresIcon.AbsolutePosition + spheresIcon.AbsoluteSize / 2
	end
	return nil
end

function Hud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Сверху: осколки, серия, Монолит ------------------------------------------
	local top = Theme.frame("Top", gui, {
		Size = UDim2.fromOffset(280, 110),
		Position = UDim2.new(0.5, 0, 0, 4),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	})
	local pill = Theme.frame("Shards", top, {
		Size = UDim2.fromOffset(210, 46),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0.08,
	})
	Theme.corner(pill, UDim.new(0.5, 0))
	glowStroke(pill, Color3.fromRGB(90, 220, 255), Color3.fromRGB(180, 110, 255), 2.5)
	Hud.gem(pill, 34, UDim2.fromOffset(26, 23))
	local shardsText = Theme.text("Amount", pill, "0", 32, {
		Size = UDim2.new(1, -54, 1, 0),
		Position = UDim2.fromOffset(48, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
	})
	local bounce = Instance.new("UIScale")
	bounce.Parent = pill
	shardsBounce = bounce

	local streakText = Theme.text("Streak", top, "", 20, {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 48),
		Font = Theme.Display,
		TextColor3 = Theme.Color.Crit,
		TextStrokeTransparency = 0.2,
		Visible = false,
	})
	local streakScale = Instance.new("UIScale")
	streakScale.Parent = streakText

	local barBack = Theme.frame("MonolithBar", top, {
		Size = UDim2.fromOffset(240, 12),
		Position = UDim2.new(0.5, 0, 0, 74),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(16, 14, 26),
		BackgroundTransparency = 0.2,
	})
	Theme.corner(barBack, UDim.new(0.5, 0))
	Theme.stroke(barBack, Color3.fromRGB(0, 0, 0), 1)
	local barFill = Theme.frame("Fill", barBack, {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
	})
	Theme.corner(barFill, UDim.new(0.5, 0))
	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new(Color3.fromRGB(80, 220, 255), Color3.fromRGB(190, 110, 255))
	fillGrad.Parent = barFill
	local monoText = Theme.text("Monolith", top, "", 14, {
		Size = UDim2.new(1, 40, 0, 16),
		Position = UDim2.new(0.5, 0, 0, 88),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Display,
		TextColor3 = Theme.Color.TextDim,
		TextStrokeTransparency = 0.5,
	})

	-- Слева: Сферы и урон арсенала ---------------------------------------------
	local left = Theme.frame("Spheres", gui, {
		Size = UDim2.fromOffset(150, 58),
		Position = UDim2.new(0, 8, 0.38, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 0.1,
	})
	Theme.corner(left, UDim.new(0.5, 0))
	glowStroke(left, Color3.fromRGB(255, 170, 80), Color3.fromRGB(180, 110, 255), 2.5)
	local orb = Theme.frame("Orb", left, {
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(7, 7),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
	})
	spheresIcon = orb
	Theme.corner(orb, UDim.new(0.5, 0))
	local orbGrad = Instance.new("UIGradient")
	orbGrad.Color = ColorSequence.new(Color3.fromRGB(225, 165, 105), Color3.fromRGB(120, 76, 50))
	orbGrad.Rotation = 60
	orbGrad.Parent = orb
	local orbScale = Instance.new("UIScale")
	orbScale.Parent = orb
	local countText = Theme.text("Count", left, "x0", 28, {
		Size = UDim2.new(1, -60, 1, 0),
		Position = UDim2.fromOffset(58, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
	})
	local openButton = Theme.button("Open", gui, "Открыть", "primary", {
		Size = UDim2.fromOffset(150, 40),
		Position = UDim2.new(0, 8, 0.38, 36),
		Font = Theme.Display,
		TextSize = 20,
	})
	Theme.corner(openButton, UDim.new(0.5, 0))
	openButton.Activated:Connect(function()
		run("open")
	end)
	local arsenalText = Theme.text("Arsenal", gui, "", 18, {
		Size = UDim2.fromOffset(220, 22),
		Position = UDim2.new(0, 12, 0.38, 82),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
		TextStrokeTransparency = 0.3,
	})

	-- Справа: круглые кнопки ------------------------------------------------
	local right = Theme.frame("Buttons", gui, {
		Size = UDim2.fromOffset(74, 170),
		Position = UDim2.new(1, -8, 0.4, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
	})
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = right
	local invButton = roundButton("Inventory", right, "⚔", "Оружие", 70)
	invButton.LayoutOrder = 1
	invButton.Activated:Connect(function()
		run("inventory")
	end)
	local upButton = roundButton("Upgrades", right, "⬆", "Улучшения", 70)
	upButton.LayoutOrder = 2
	upButton.Activated:Connect(function()
		run("upgrades")
	end)
	local upScale = upButton:FindFirstChildOfClass("UIScale") :: UIScale
	local upStroke = upButton:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- Стрелка к Золотому и более редкому мутанту.
	local pointer = Theme.frame("MutantPointer", gui, {
		Size = UDim2.fromOffset(280, 30),
		Position = UDim2.new(0.5, 0, 0, 116),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Visible = false,
	})
	local arrow = Theme.text("Arrow", pointer, "▲", 26, {
		Size = UDim2.fromOffset(30, 30),
		TextColor3 = Palette.Mutation[2],
	})
	local pointerText = Theme.text("Text", pointer, "", 18, {
		Size = UDim2.new(1, -34, 1, 0),
		Position = UDim2.fromOffset(34, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
		TextStrokeTransparency = 0.3,
	})

	-- Большая кнопка «Удар» на телефоне, левее прыжка.
	local attack = roundButton("Attack", gui, "⚔", "Удар", 104)
	attack.AnchorPoint = Vector2.new(1, 1)
	attack.Position = UDim2.new(1, -150, 1, -26)
	attack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.press("button")
		end
	end)
	attack.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.release("button")
		end
	end)
	local function refreshAttack()
		attack.Visible = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end
	UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshAttack)
	refreshAttack()

	-- Обновление по данным ----------------------------------------------------
	local lastSpheres = 0
	local function refresh(section: string)
		local d = Store.data
		if section == "wallet" then
			shardsText.Text = Formulas.short(d.shards)
		end
		if section == "monolith" or section == "wallet" then
			local cost = Formulas.monolithCost(d.monolithLevel)
			Theme.tween(barFill, TweenInfo.new(0.25), { Size = UDim2.fromScale(math.clamp(d.monolithProgress / cost, 0, 1), 1) })
			local need = math.max(0, cost - d.monolithProgress)
			monoText.Text = if d.shards >= need
				then `Монолит ур. {d.monolithLevel} · хватает на уровень — влей на базе!`
				else `Монолит ур. {d.monolithLevel} · до следующего {Formulas.short(need)}`
			monoText.TextColor3 = if d.shards >= need then Theme.Color.Good else Theme.Color.TextDim
		end
		if section == "spheres" then
			countText.Text = "x" .. #d.spheres
			openButton.Visible = #d.spheres > 0
			if #d.spheres > lastSpheres then
				orbScale.Scale = 1.35
				Theme.tween(orbScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 })
			end
			lastSpheres = #d.spheres
		end
		if section == "arsenal" or section == "monolith" then
			arsenalText.Text = `⚔ Урон удара {Formulas.short(Store.hitDamage())}`
		end
	end
	Store.onChanged(refresh)
	for _, s in { "wallet", "monolith", "spheres", "arsenal" } do
		refresh(s)
	end

	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		-- Серия убийств.
		local streakOn = streakSteps > 0 and t < streakUntil
		streakText.Visible = streakOn
		if streakOn then
			streakText.Text = `Серия {streakSteps} · осколки ×{(string.gsub(string.format("%.2f", Formulas.streakMult(streakSteps)), "%.", ","))}`
			streakText.TextTransparency = math.clamp(1 - (streakUntil - t) / Config.Streak.Window, 0, 0.7)
		end
		-- Пульс «Улучшений», когда хватает на уровень.
		if affordable() then
			upScale.Scale = 1 + math.sin(t * 6) * 0.06
			upStroke.Thickness = 4
		else
			upScale.Scale = 1
			upStroke.Thickness = 3
		end

		local root = World.root()
		local folder = Workspace:FindFirstChild("Creeps")
		local camera = Workspace.CurrentCamera
		if not root or not folder or not camera then
			pointer.Visible = false
			return
		end
		local myZone = Formulas.zoneAt(root.Position)
		local best: Model? = nil
		local bestD = math.huge
		for _, m in folder:GetChildren() do
			local mutation = m:GetAttribute("Mutation")
			if m:IsA("Model") and m.PrimaryPart and type(mutation) == "number" and mutation >= 2 and m:GetAttribute("Zone") == myZone then
				local dist = (m.PrimaryPart.Position - root.Position).Magnitude
				if dist < bestD then
					best, bestD = m, dist
				end
			end
		end
		pointer.Visible = best ~= nil
		if best and best.PrimaryPart then
			local mutation = best:GetAttribute("Mutation") :: number
			pointerText.Text = `{Config.CreepMutations[mutation].name} крип · {math.floor(bestD)} ст.`
			pointerText.TextColor3 = Palette.Mutation[mutation]
			arrow.TextColor3 = Palette.Mutation[mutation]
			local look = camera.CFrame:VectorToObjectSpace(best.PrimaryPart.Position - root.Position)
			arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Hud

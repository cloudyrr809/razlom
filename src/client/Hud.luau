--!strict
-- Постоянный экран. Центр свободен для боя:
--   сверху — осколки и полоска до ближайшей покупки;
--   слева — Сферы на складе и три гнезда;
--   справа — круглые кнопки; снизу справа на телефоне — большая кнопка «Удар».

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

local openInventory: () -> () = function() end
function Hud.onInventory(fn: () -> ())
	openInventory = fn
end

local function glowStroke(parent: GuiObject, a: Color3, b: Color3, thickness: number)
	local s = Theme.stroke(parent, Color3.new(1, 1, 1), thickness)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Parent = s
	return s
end
Hud.glowStroke = glowStroke

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
	Theme.text("Icon", b, icon, px * 0.42, {
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

-- Ближайшая покупка: то улучшение, до которого меньше всего осталось.
local function nextPurchase(): (string, number, boolean)
	local d = Store.data
	local best: string? = nil
	local bestFrac = -1
	local upgradeIds: { Formulas.UpgradeId } = { "Ring", "Aura" }
	for _, id in upgradeIds do
		local owned = ({ Ring = d.ring, Aura = d.aura } :: { [string]: number })[id]
		local uid = id :: any
		if owned < Formulas.upgradeCap(uid, d.openZones) then
			local price = Formulas.upgradeCost(uid, owned)
			local frac = math.min(1, d.shards / price)
			if frac > bestFrac then
				bestFrac = frac
				best = `{Config.Upgrades[id].name} ур. {owned + 1}`
			end
		end
	end
	if not best then
		return "Потолок: открой следующую зону", 1, true
	end
	return best, bestFrac, false
end

function Hud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	-- Сверху: осколки ------------------------------------------------------
	local top = Theme.frame("Top", gui, {
		Size = UDim2.fromOffset(260, 84),
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

	local barBack = Theme.frame("NextBar", top, {
		Size = UDim2.fromOffset(240, 12),
		Position = UDim2.new(0.5, 0, 0, 54),
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
	local nextText = Theme.text("NextPurchase", top, "", 14, {
		Size = UDim2.new(1, 40, 0, 16),
		Position = UDim2.new(0.5, 0, 0, 68),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.Display,
		TextColor3 = Theme.Color.TextDim,
		TextStrokeTransparency = 0.5,
	})

	-- Слева: Сферы и гнёзда --------------------------------------------------
	local left = Theme.frame("Spheres", gui, {
		Size = UDim2.fromOffset(150, 58),
		Position = UDim2.new(0, 8, 0.4, 0),
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
	Theme.corner(orb, UDim.new(0.5, 0))
	local orbGrad = Instance.new("UIGradient")
	orbGrad.Color = ColorSequence.new(Color3.fromRGB(225, 165, 105), Color3.fromRGB(120, 76, 50))
	orbGrad.Rotation = 60
	orbGrad.Parent = orb
	Theme.text("Crack", orb, "✦", 22, {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = Color3.fromRGB(255, 200, 90),
		Font = Theme.Display,
	})
	local storageText = Theme.text("Count", left, "0/10", 26, {
		Size = UDim2.new(1, -60, 0, 30),
		Position = UDim2.fromOffset(58, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
	})
	local dots: { Frame } = {}
	for k = 1, 3 do
		local dot = Theme.frame("Nest" .. k, left, {
			Size = UDim2.fromOffset(12, 12),
			Position = UDim2.fromOffset(60 + (k - 1) * 18, 36),
			BackgroundColor3 = Theme.Color.Secondary,
			BackgroundTransparency = 0,
		})
		Theme.corner(dot, UDim.new(0.5, 0))
		dots[k] = dot
	end
	local full = Theme.text("Full", gui, "Склад полон", 16, {
		Size = UDim2.fromOffset(220, 20),
		Position = UDim2.new(0, 14, 0.4, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
		TextColor3 = Theme.Color.Bad,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})

	-- Справа: круглые кнопки ------------------------------------------------
	local right = Theme.frame("Buttons", gui, {
		Size = UDim2.fromOffset(74, 160),
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
	invButton.Activated:Connect(function()
		openInventory()
	end)

	-- Стрелка к Золотому и более редкому мутанту.
	local pointer = Theme.frame("MutantPointer", gui, {
		Size = UDim2.fromOffset(280, 30),
		Position = UDim2.new(0.5, 0, 0, 92),
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
	local lastShards = 0
	local function refresh(section: string)
		local d = Store.data
		if section == "wallet" or section == "levels" then
			shardsText.Text = Formulas.short(d.shards)
			local label, frac, capped = nextPurchase()
			if capped then
				nextText.Text = label
			elseif frac >= 1 then
				nextText.Text = label .. " — можно купить!"
			else
				nextText.Text = `{label} — {math.floor(frac * 100)}%`
			end
			nextText.TextColor3 = if frac >= 1 and not capped then Theme.Color.Good else Theme.Color.TextDim
			Theme.tween(barFill, TweenInfo.new(0.25), { Size = UDim2.fromScale(frac, 1) })
			if d.shards > lastShards then
				bounce.Scale = 1.14
				Theme.tween(bounce, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 })
			end
			lastShards = d.shards
		end
		if section == "spheres" then
			storageText.Text = `{#d.storage}/{Config.Spheres.StorageSize}`
			full.Visible = d.overflow > 0 or #d.storage >= Config.Spheres.StorageSize
			full.Text = if d.overflow > 0 then `Склад полон · +{d.overflow} у базы` else "Склад полон"
		end
		if section == "reveals" then
			for k, dot in dots do
				dot.BackgroundColor3 = if Store.reveals[k] then Theme.Color.Accent else Theme.Color.Secondary
			end
		end
	end
	Store.onChanged(refresh)
	for _, s in { "wallet", "spheres", "reveals" } do
		refresh(s)
	end

	RunService.RenderStepped:Connect(function()
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

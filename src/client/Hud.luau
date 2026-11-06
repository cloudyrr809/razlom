--!strict
-- Постоянный экран: осколки и ближайшая покупка сверху, склад и гнёзда слева,
-- кнопки справа, стрелка к редкому мутанту, кнопка «Удар» на телефоне.

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

Hud.gui = nil :: ScreenGui?
local openInventory: () -> () = function() end

function Hud.onInventory(fn: () -> ())
	openInventory = fn
end

-- Ближайшая покупка: то улучшение, до которого меньше всего осталось.
local function nextPurchase(): string
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
				best = `{Config.Upgrades[id].name} ур. {owned + 1} — {math.floor(frac * 100)}%`
			end
		end
	end
	return best or "Потолок улучшений: открой следующую зону"
end

function Hud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	Hud.gui = gui

	-- Сверху по центру: осколки.
	local top = Theme.frame("Top", gui, {
		Size = UDim2.fromOffset(240, 74),
		Position = UDim2.new(0.5, 0, 0, 6),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	})
	local shardsBox = Theme.frame("Shards", top, {
		Size = UDim2.fromOffset(190, 44),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
	})
	Theme.corner(shardsBox, UDim.new(0, 22))
	Theme.stroke(shardsBox, Theme.Color.Shards, 1.5)
	local icon = Theme.frame("Icon", shardsBox, {
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromOffset(20, 22),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = Theme.Color.Shards,
		BackgroundTransparency = 0,
	})
	local _ = icon
	local shardsText = Theme.text("Amount", shardsBox, "0", 28, {
		Size = UDim2.new(1, -44, 1, 0),
		Position = UDim2.fromOffset(38, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Color.Shards,
	})
	local bounce = Instance.new("UIScale")
	bounce.Parent = shardsBox
	local nextText = Theme.text("NextPurchase", top, "", 16, {
		Size = UDim2.new(1, 60, 0, 22),
		Position = UDim2.new(0.5, 0, 0, 48),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Theme.Color.TextDim,
		TextStrokeTransparency = 0.6,
	})

	-- Слева: склад и три гнезда.
	local left = Theme.frame("Spheres", gui, {
		Size = UDim2.fromOffset(120, 96),
		Position = UDim2.new(0, 10, 0.42, 0),
		AnchorPoint = Vector2.new(0, 0.5),
	})
	Theme.corner(left)
	Theme.padding(left, 8)
	Theme.text("Label", left, "Сферы", 15, {
		Size = UDim2.new(1, 0, 0, 18),
		TextColor3 = Theme.Color.TextDim,
	})
	local storageText = Theme.text("Count", left, "0/10", 26, {
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.fromOffset(0, 18),
	})
	local dots: { Frame } = {}
	for k = 1, 3 do
		local dot = Theme.frame("Nest" .. k, left, {
			Size = UDim2.fromOffset(16, 16),
			Position = UDim2.new(0.5, (k - 2) * 26, 0, 56),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Theme.Color.Secondary,
			BackgroundTransparency = 0,
		})
		Theme.corner(dot, UDim.new(0.5, 0))
		dots[k] = dot
	end
	local full = Theme.text("Full", gui, "Склад полон", 18, {
		Size = UDim2.fromOffset(140, 24),
		Position = UDim2.new(0, 10, 0.42, 54),
		TextColor3 = Theme.Color.Bad,
		TextStrokeTransparency = 0.5,
		Visible = false,
	})

	-- Справа: кнопки.
	local right = Theme.frame("Buttons", gui, {
		Size = UDim2.fromOffset(110, 60),
		Position = UDim2.new(1, -10, 0.42, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
	})
	local invButton = Theme.button("Inventory", right, "Оружие", "secondary", {
		Size = UDim2.fromOffset(110, 52),
		TextSize = 20,
	})
	invButton.Activated:Connect(function()
		openInventory()
	end)

	-- Стрелка к Золотому и более редкому мутанту.
	local pointer = Theme.frame("MutantPointer", gui, {
		Size = UDim2.fromOffset(260, 30),
		Position = UDim2.new(0.5, 0, 0, 84),
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
		TextStrokeTransparency = 0.4,
	})

	-- Кнопка «Удар» на телефоне, слева от кнопки прыжка.
	local attack = Theme.button("Attack", gui, "Удар", "primary", {
		Size = UDim2.fromOffset(96, 96),
		Position = UDim2.new(1, -178, 1, -40),
		AnchorPoint = Vector2.new(1, 1),
		TextSize = 24,
		BackgroundTransparency = 0.2,
	})
	Theme.corner(attack, UDim.new(0.5, 0))
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

	-- Обновление по данным.
	local lastShards = 0
	local function refresh(section: string)
		local d = Store.data
		if section == "wallet" or section == "levels" then
			shardsText.Text = Formulas.short(d.shards)
			nextText.Text = nextPurchase()
			if d.shards > lastShards then
				bounce.Scale = 1.12
				Theme.tween(bounce, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 })
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
				local r = Store.reveals[k]
				dot.BackgroundColor3 = if r then Theme.Color.Accent else Theme.Color.Secondary
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
			local m = Config.CreepMutations[mutation]
			pointerText.Text = `{m.name} крип · {math.floor(bestD)} ст.`
			pointerText.TextColor3 = Palette.Mutation[mutation]
			arrow.TextColor3 = Palette.Mutation[mutation]
			-- Направление относительно камеры: вверх — вперёд.
			local look = camera.CFrame:VectorToObjectSpace(best.PrimaryPart.Position - root.Position)
			arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
end

return Hud

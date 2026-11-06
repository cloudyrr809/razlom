--!strict
-- Улучшения: Кольцо и Аура. Открываются где угодно из кнопки «Улучшения». Покупку решает сервер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)

local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteEvent

local UpgradesWindow = {}
local win: Window.Win

local function fmt(x: number): string
	return (string.gsub(string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", ""), "%.", ","))
end

local function ownedOf(id: string): number
	return if id == "Ring" then Store.data.ring else Store.data.aura
end

-- Хватает ли осколков хотя бы на один уровень (кнопка в HUD пульсирует).
function UpgradesWindow.affordable(): boolean
	for _, id in { "Ring", "Aura" } do
		local uid = id :: any
		local owned = ownedOf(id)
		if owned < Formulas.upgradeCap(uid, Store.data.openZones) and Store.data.shards >= Formulas.upgradeCost(uid, owned) then
			return true
		end
	end
	return false
end

function UpgradesWindow.toggle()
	if win.isOpen() then
		win.close()
	else
		win.open()
	end
end

function UpgradesWindow.start()
	win = Window.new("Upgrades", "Улучшения", 340, 380, "side")
	local column = Theme.frame("Cards", win.content, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.Parent = column

	type Card = { level: TextLabel, info: TextLabel, one: TextButton, max: TextButton }
	local cards: { [string]: Card } = {}
	for i, id in { "Ring", "Aura" } do
		local u = (Config.Upgrades :: any)[id]
		local accent = if id == "Ring" then Color3.fromRGB(255, 200, 80) else Color3.fromRGB(90, 200, 255)
		local card = Theme.frame(id, column, {
			Size = UDim2.new(1, 0, 0.5, -6),
			BackgroundColor3 = Theme.Color.PanelSoft,
			LayoutOrder = i,
		})
		Theme.corner(card)
		Theme.padding(card, 10)
		Theme.stroke(card, accent, 2)
		Theme.text("Name", card, u.name, 22, {
			Size = UDim2.new(0.5, 0, 0, 24),
			Font = Theme.Display,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = accent,
		})
		Theme.text("What", card, if id == "Ring" then "скорость атаки" else "скорость бега", 14, {
			Size = UDim2.new(0.5, 0, 0, 24),
			Position = UDim2.fromScale(0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Color.TextDim,
		})
		local level = Theme.text("Level", card, "", 17, {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Display,
		})
		local info = Theme.text("Info", card, "", 14, {
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 50),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Color.TextDim,
		})
		local one = Theme.button("BuyOne", card, "+1", "primary", {
			Size = UDim2.new(0.5, -4, 0, 42),
			Position = UDim2.new(0, 0, 1, -42),
			Font = Theme.Display,
			TextSize = 18,
		})
		local max = Theme.button("BuyMax", card, "Макс", "secondary", {
			Size = UDim2.new(0.5, -4, 0, 42),
			Position = UDim2.new(1, 0, 1, -42),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.Display,
			TextSize = 16,
		})
		one.Activated:Connect(function()
			if one.Active then
				buyRemote:FireServer(id, false)
			end
		end)
		max.Activated:Connect(function()
			if max.Active then
				buyRemote:FireServer(id, true)
			end
		end)
		cards[id] = { level = level, info = info, one = one, max = max }
	end

	local function render()
		local d = Store.data
		for id, c in cards do
			local uid = id :: any
			local owned = ownedOf(id)
			local cap = Formulas.upgradeCap(uid, d.openZones)
			local function value(l: number): number
				return if id == "Ring" then Formulas.hitsPerSecond(l) else Formulas.walkSpeed(l)
			end
			local unit = if id == "Ring" then " уд/с" else ""
			if owned >= cap then
				c.level.Text = `Ур. {owned}/{cap} · {fmt(value(owned))}{unit}`
				c.info.Text = "Потолок: открой следующую зону"
				c.one.Text = "+1"
				c.max.Text = "Макс"
				Theme.setEnabled(c.one, false)
				Theme.setEnabled(c.max, false)
			else
				local price = Formulas.upgradeCost(uid, owned)
				c.level.Text = `Ур. {owned}/{cap} · {fmt(value(owned))} → {fmt(value(owned + 1))}{unit}`
				c.info.Text = `Потолок растёт с каждой открытой зоной`
				c.one.Text = "+1 · " .. Formulas.short(price)
				Theme.setEnabled(c.one, d.shards >= price)
				local n, total = Formulas.upgradeMax(uid, owned, d.shards, d.openZones)
				Theme.setEnabled(c.max, n > 0)
				c.max.Text = if n > 0 then `Макс +{n} · {Formulas.short(total)}` else "Макс"
			end
		end
	end
	Store.onChanged(function(section)
		if (section == "wallet" or section == "levels") and win.isOpen() then
			render()
		end
	end)
	win.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if win.isOpen() then
			render()
		end
	end)
end

return UpgradesWindow

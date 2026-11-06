--!strict
-- Станция улучшений: две карточки (Аура, Кольцо) — уровень, что даст следующий, цена, «+1» и «Макс».
-- Открывается сама у своей станции. Покупку решает сервер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)

local buyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade") :: RemoteEvent

local StationWindow = {}
local win: Window.Win

local function fmt(x: number): string
	return (string.gsub(string.format("%.2f", x):gsub("0+$", ""):gsub("%.$", ""), "%.", ","))
end

function StationWindow.get(): Window.Win
	return win
end

function StationWindow.start()
	win = Window.new("Station", "Станция: Аура и Кольцо", 640, 330)
	local row = Theme.frame("Cards", win.content, {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 12)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row

	type Card = { level: TextLabel, effect: TextLabel, price: TextLabel, one: TextButton, max: TextButton }
	local cards: { [string]: Card } = {}

	local upgradeIds: { Formulas.UpgradeId } = { "Ring", "Aura" }
	for i, id in upgradeIds do
		local u = Config.Upgrades[id]
		local card = Theme.frame(id, row, {
			Size = UDim2.new(0.5, -6, 1, 0),
			BackgroundColor3 = Theme.Color.PanelSoft,
			LayoutOrder = i,
		})
		Theme.corner(card)
		Theme.padding(card, 12)
		Theme.text("Name", card, u.name, 24, {
			Size = UDim2.new(1, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		Theme.text("What", card, if id == "Ring" then "скорость атаки" else "скорость бега", 15, {
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Color.TextDim,
		})
		local level = Theme.text("Level", card, "", 18, {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 54),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local effect = Theme.text("Effect", card, "", 18, {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 80),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Color.Good,
		})
		local price = Theme.text("Price", card, "", 18, {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 106),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Color.Shards,
		})
		local one = Theme.button("BuyOne", card, "+1", "primary", {
			Size = UDim2.new(0.5, -4, 0, 48),
			Position = UDim2.new(0, 0, 1, -48),
			TextSize = 22,
		})
		local max = Theme.button("BuyMax", card, "Макс", "secondary", {
			Size = UDim2.new(0.5, -4, 0, 48),
			Position = UDim2.new(1, 0, 1, -48),
			AnchorPoint = Vector2.new(1, 0),
			TextSize = 18,
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
		cards[id] = { level = level, effect = effect, price = price, one = one, max = max }
	end

	local function render()
		local d = Store.data
		for id, c in cards do
			local uid: Formulas.UpgradeId = if id == "Ring" then "Ring" else "Aura"
			local owned = if uid == "Ring" then d.ring else d.aura
			local cap = Formulas.upgradeCap(uid, d.openZones)
			local function value(level: number): number
				return if uid == "Ring" then Formulas.hitsPerSecond(level) else Formulas.walkSpeed(level)
			end
			local unit = if uid == "Ring" then " уд/с" else ""
			c.level.Text = `Уровень {owned} / {cap}`
			if owned >= cap then
				c.effect.Text = `{fmt(value(owned))}{unit} — потолок зоны`
				c.price.Text = "Открой следующую зону"
				Theme.setEnabled(c.one, false)
				Theme.setEnabled(c.max, false)
				c.max.Text = "Макс"
			else
				local price = Formulas.upgradeCost(uid, owned)
				c.effect.Text = `{fmt(value(owned))} → {fmt(value(owned + 1))}{unit}`
				c.price.Text = "Цена: " .. Formulas.short(price)
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

return StationWindow

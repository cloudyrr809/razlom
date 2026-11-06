--!strict
-- Гнездо: Сферы со склада, цена вскрытия, «Вскрыть», «Шансы» со счётчиком гарантии.
-- Открывается само у своего гнезда. Пока идёт вскрытие — подсказка «бей по Сфере».

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local World = require(script.Parent.World)

local openRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OpenSphere") :: RemoteEvent

local NestWindow = {}
NestWindow.switching = false -- true, пока окно гнезда уступает место окну «Шансы»
local win: Window.Win
local oddsWin: Window.Win
local nestIndex = 1
local render: () -> () = function() end

local function pct(p: number): string
	local v = p * 100
	local text = if v >= 1 then string.format("%.1f", v) elseif v >= 0.01 then string.format("%.2f", v) else string.format("%.4f", v)
	return (string.gsub(text, "%.", ",")) .. "%"
end

function NestWindow.get(): Window.Win
	return win
end

function NestWindow.openAt(k: number)
	nestIndex = k
	win.title.Text = "Гнездо " .. k
	win.open()
	render()
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
		line("Редкость оружия (одинакова для всех Сфер):", Theme.Color.TextDim)
		local total = 0
		for _, r in Config.Rarities do
			total += r.weight
		end
		for i, r in Config.Rarities do
			line(`  {r.weapon} · {r.name}: {pct(r.weight / total)}`, Palette.Rarity[i])
		end
		if Store.data.freeOpen then
			line(`Первое вскрытие бесплатное и даёт минимум {Config.Rarities[Config.Spheres.FirstOpenMinRarity].weapon}.`, Theme.Color.Good)
		end
		-- Мутации для каждого вида усиления, которое бывает у Сфер.
		local boosts: { number } = { 1 }
		for _, m in Config.CreepMutations do
			if m.weaponMutationBoost > 1 and not table.find(boosts, m.weaponMutationBoost) then
				table.insert(boosts, m.weaponMutationBoost)
			end
		end
		for _, boost in boosts do
			local title = if boost == 1 then "Мутация оружия (обычная Сфера):" else `Мутация в Сфере с шансом ×{boost}:`
			line(title, Theme.Color.TextDim)
			local odds = Formulas.weaponMutationOdds(boost)
			line(`  без мутации: {pct(odds[0])}`)
			for i, m in Config.WeaponMutations do
				line(`  {m.nameFem} (урон ×{m.mult}): {pct(odds[i])}`, Palette.Mutation[i])
			end
		end
		line("Мутация проверяется от редкой к частой; гарантии поднимают итог минимум до Заряженной.", Theme.Color.TextDim, 14)
	end
	oddsWin.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if oddsWin.isOpen() then
			fill()
		end
	end)
end

function NestWindow.start()
	win = Window.new("Nest", "Гнездо", 560, 480)
	buildOdds()

	local header = Theme.text("Header", win.content, "", 16, {
		Size = UDim2.new(1, -130, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Color.TextDim,
	})
	local oddsButton = Theme.button("Odds", win.content, "Шансы", "secondary", {
		Size = UDim2.fromOffset(120, 40),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
	})
	oddsButton.Activated:Connect(function()
		NestWindow.switching = true
		oddsWin.open()
		NestWindow.switching = false
	end)
	-- Закрыли «Шансы» — возвращаемся в гнездо.
	oddsWin.onClose(function()
		if not Window.current() and World.nearNest(Config.Base.NestRange) == nestIndex then
			NestWindow.openAt(nestIndex)
		end
	end)

	local hint = Theme.text("RevealHint", win.content, "", 26, {
		Size = UDim2.new(1, 0, 0, 80),
		Position = UDim2.fromOffset(0, 60),
		TextColor3 = Theme.Color.Accent,
		Visible = false,
	})

	local list = Instance.new("ScrollingFrame")
	list.Name = "Spheres"
	list.Size = UDim2.new(1, 0, 1, -50)
	list.Position = UDim2.fromOffset(0, 50)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = win.content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	render = function()
		if not win.isOpen() then
			return
		end
		for _, c in list:GetChildren() do
			if c:IsA("Frame") or c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local d = Store.data
		local reveal = Store.reveals[nestIndex]
		header.Text = `Склад {#d.storage}/{Config.Spheres.StorageSize}` .. (if d.overflow > 0 then ` · у базы ещё {d.overflow}` else "") .. ` · {pityText()}`
		hint.Visible = reveal ~= nil
		list.Visible = reveal == nil
		if reveal then
			hint.Text = `Бей по Сфере! {reveal.hits}/{reveal.need}`
			return
		end
		if #d.storage == 0 then
			Theme.text("Empty", list, "Сфер нет. Бей крипов на дороге — Сферы сами прилетят сюда.", 18, {
				Size = UDim2.new(1, 0, 0, 60),
				TextColor3 = Theme.Color.TextDim,
			})
			return
		end
		-- Сортируем: дальняя зона и сильное усиление выше.
		local spheres = table.clone(d.storage)
		table.sort(spheres, function(a, b)
			if a.zone ~= b.zone then
				return a.zone > b.zone
			end
			return a.boost > b.boost
		end)
		for i, s in spheres do
			local row = Theme.frame("Sphere_" .. s.id, list, {
				Size = UDim2.new(1, -8, 0, 56),
				BackgroundColor3 = Theme.Color.PanelSoft,
				LayoutOrder = i,
			})
			Theme.corner(row)
			local zoneColor = (Palette.Zones[s.zone] or Palette.Zones[1]).glow
			local dot = Theme.frame("Dot", row, {
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.fromOffset(14, 15),
				BackgroundColor3 = zoneColor,
				BackgroundTransparency = 0,
			})
			Theme.corner(dot, UDim.new(0.5, 0))
			local label = `Сфера зоны {s.zone}`
			local m = Config.CreepMutations[s.fromMutation]
			if m then
				label ..= ` · с крипа «{m.name}»`
			end
			if s.boost > 1 then
				label ..= ` · мутация ×{s.boost}`
			end
			if s.minMutation > 0 then
				label ..= " · мутация гарантирована"
			end
			Theme.text("Label", row, label, 16, {
				Size = UDim2.new(1, -200, 1, 0),
				Position = UDim2.fromOffset(50, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = if m then Palette.Mutation[s.fromMutation] else Theme.Color.Text,
			})
			local price = Formulas.openPrice(s.zone)
			local free = d.freeOpen
			local button = Theme.button("Open", row, if free then "Вскрыть · бесплатно" else "Вскрыть · " .. Formulas.short(price), "primary", {
				Size = UDim2.fromOffset(140, 40),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 15,
			})
			Theme.setEnabled(button, free or d.shards >= price)
			button.Activated:Connect(function()
				if button.Active then
					openRemote:FireServer(s.id, nestIndex)
				end
			end)
		end
	end

	Store.onChanged(function(section)
		if section == "spheres" or section == "wallet" or section == "reveals" then
			render()
		end
	end)
end

return NestWindow

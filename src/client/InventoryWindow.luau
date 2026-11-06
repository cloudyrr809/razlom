--!strict
-- Инвентарь оружия: сетка с рамкой редкости и значком мутации, сортировка по урону,
-- пометка «в постаменте», выбор оружия в руку (из вставленных), «Скормить» и «Скормить все обычные».

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local equipRemote = Remotes:WaitForChild("Equip") :: RemoteEvent
local feedRemote = Remotes:WaitForChild("Feed") :: RemoteEvent

local InventoryWindow = {}
local win: Window.Win

function InventoryWindow.toggle()
	if win.isOpen() then
		win.close()
	else
		win.open()
	end
end

function InventoryWindow.start()
	win = Window.new("Inventory", "Оружие", 720, 540)
	local content = win.content

	local summary = Theme.text("Summary", content, "", 16, {
		Size = UDim2.new(1, -220, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Display,
		TextColor3 = Theme.Color.TextDim,
	})
	local feedCommons = Theme.button("FeedCommons", content, "Скормить все обычные", "secondary", {
		Size = UDim2.fromOffset(210, 40),
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.Display,
		TextSize = 16,
	})
	feedCommons.Activated:Connect(function()
		feedRemote:FireServer("commons")
	end)
	local hint = Theme.text("Hint", content, "Урон удара = сумма оружия в постаментах. Вставлять — у Монолита на базе.", 14, {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.fromOffset(0, 42),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Color.TextDim,
	})
	local _ = hint

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 1, -66)
	grid.Position = UDim2.fromOffset(0, 66)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.CanvasSize = UDim2.fromOffset(0, 0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(160, 118)
	layout.CellPadding = UDim2.fromOffset(Theme.Gap, Theme.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local function render()
		if not win.isOpen() then
			return
		end
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local d = Store.data
		local list = table.clone(d.weapons)
		table.sort(list, function(a, b)
			return Formulas.weaponDamage(a) > Formulas.weaponDamage(b)
		end)
		summary.Text = `Оружие {#list}/{Config.Weapons.MaxInventory} · арсенал {Formulas.short(Store.arsenal())}`
		for i, w in list do
			local placed = Store.inPedestal(w.id)
			local inHand = w.id == d.hand
			local color = if w.mutation > 0 then Palette.Mutation[w.mutation] else Palette.Rarity[w.rarity]
			local cell = Theme.frame("Weapon_" .. w.id, grid, { BackgroundColor3 = Theme.Color.PanelSoft, LayoutOrder = i })
			Theme.corner(cell)
			Theme.stroke(cell, color, if placed then 3 else 1.5)
			Theme.text("Name", cell, Formulas.weaponName(w), 15, {
				Size = UDim2.new(1, -12, 0, 36),
				Position = UDim2.fromOffset(6, 2),
				Font = Theme.Display,
				TextColor3 = color,
			})
			Theme.text("Damage", cell, "урон " .. Formulas.short(Formulas.weaponDamage(w)), 17, {
				Size = UDim2.new(1, -12, 0, 20),
				Position = UDim2.fromOffset(6, 38),
				Font = Theme.Display,
			})
			Theme.text("Sub", cell, if inHand then "в руке" elseif placed then "в постаменте" else Config.Rarities[w.rarity].name, 13, {
				Size = UDim2.new(1, -12, 0, 16),
				Position = UDim2.fromOffset(6, 58),
				TextColor3 = if placed then Theme.Color.Good else Theme.Color.TextDim,
			})
			if w.mutation > 0 then
				Theme.frame("Mutation", cell, {
					Size = UDim2.fromOffset(12, 12),
					Position = UDim2.new(1, -8, 0, 8),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundColor3 = Palette.Mutation[w.mutation],
					BackgroundTransparency = 0,
					Rotation = 45,
				})
			end
			-- Действие: вставленное — «В руку», остальное — «Скормить» (+прогресс Монолиту).
			if placed then
				if not inHand then
					local hand = Theme.button("Hand", cell, "В руку", "secondary", {
						Size = UDim2.new(1, -12, 0, 30),
						Position = UDim2.new(0, 6, 1, -36),
						TextSize = 14,
					})
					hand.Activated:Connect(function()
						equipRemote:FireServer(w.id)
					end)
				end
			elseif w.id ~= "starter" then
				local feed = Theme.button("Feed", cell, "Скормить +" .. Formulas.short(Formulas.feedValue(w)), "secondary", {
					Size = UDim2.new(1, -12, 0, 30),
					Position = UDim2.new(0, 6, 1, -36),
					TextSize = 13,
				})
				feed.Activated:Connect(function()
					feedRemote:FireServer("one", w.id)
				end)
			end
		end
	end

	Store.onChanged(function(section)
		if section == "arsenal" then
			render()
		end
	end)
	win.root:GetPropertyChangedSignal("Visible"):Connect(render)
end

return InventoryWindow

--!strict
-- Инвентарь: сетка оружия с рамкой цвета редкости и значком мутации, сортировка по урону,
-- «Надеть лучшее». Клик по карточке — надеть.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)

local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Equip") :: RemoteEvent

local InventoryWindow = {}
local win: Window.Win

function InventoryWindow.open()
	win.open()
end

function InventoryWindow.toggle()
	if win.isOpen() then
		win.close()
	else
		win.open()
	end
end

function InventoryWindow.start()
	win = Window.new("Inventory", "Оружие", 720, 520)
	local content = win.content

	local bestButton = Theme.button("EquipBest", content, "Надеть лучшее", "primary", {
		Size = UDim2.fromOffset(180, 40),
	})
	bestButton.Activated:Connect(function()
		equipRemote:FireServer("best")
	end)
	local summary = Theme.text("Summary", content, "", 16, {
		Size = UDim2.new(1, -196, 0, 40),
		Position = UDim2.fromOffset(196, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Color.TextDim,
	})

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, 0, 1, -50)
	grid.Position = UDim2.fromOffset(0, 50)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.CanvasSize = UDim2.fromOffset(0, 0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = content
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(150, 96)
	layout.CellPadding = UDim2.fromOffset(Theme.Gap, Theme.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local function render()
		for _, c in grid:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
		local list = table.clone(Store.data.weapons)
		table.sort(list, function(a, b)
			return Formulas.weaponDamage(a) > Formulas.weaponDamage(b)
		end)
		summary.Text = `Всего: {#list} · в руке: {Formulas.weaponName(Store.equippedWeapon())}`
		for i, w in list do
			local equipped = w.id == Store.data.equipped
			local cell = Theme.button("Weapon_" .. w.id, grid, "", "secondary", { LayoutOrder = i })
			Theme.stroke(cell, Palette.Rarity[w.rarity], if equipped then 3 else 1.5)
			Theme.text("Name", cell, Formulas.weaponName(w), 16, {
				Size = UDim2.new(1, -12, 0, 40),
				Position = UDim2.fromOffset(6, 4),
				TextColor3 = Palette.Rarity[w.rarity],
			})
			Theme.text("Damage", cell, "урон " .. Formulas.short(Formulas.weaponDamage(w)), 18, {
				Size = UDim2.new(1, -12, 0, 22),
				Position = UDim2.fromOffset(6, 44),
			})
			local sub = Config.Rarities[w.rarity].name .. " · зона " .. w.zone
			if equipped then
				sub = "в руке"
			end
			Theme.text("Sub", cell, sub, 13, {
				Size = UDim2.new(1, -12, 0, 18),
				Position = UDim2.fromOffset(6, 70),
				TextColor3 = if equipped then Theme.Color.Good else Theme.Color.TextDim,
			})
			if w.mutation > 0 then
				local badge = Theme.frame("Mutation", cell, {
					Size = UDim2.fromOffset(14, 14),
					Position = UDim2.new(1, -8, 0, 8),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundColor3 = Palette.Mutation[w.mutation],
					BackgroundTransparency = 0,
					Rotation = 45,
				})
				local _ = badge
			end
			cell.Activated:Connect(function()
				equipRemote:FireServer(w.id)
			end)
		end
	end

	Store.onChanged(function(section)
		if section == "inventory" and win.isOpen() then
			render()
		end
	end)
	win.root:GetPropertyChangedSignal("Visible"):Connect(function()
		if win.isOpen() then
			render()
		end
	end)
end

return InventoryWindow

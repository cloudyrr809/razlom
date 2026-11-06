--!strict
-- Окно базы (открывается само у своего Монолита): Монолит — уровень, прогресс, «Влить всё»;
-- постаменты — что вставлено, урон арсенала, «Экипировать лучшее», ручная вставка и снятие.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local pedestalRemote = Remotes:WaitForChild("Pedestal") :: RemoteEvent
local monolithRemote = Remotes:WaitForChild("Monolith") :: RemoteEvent

local BaseWindow = {}
local win: Window.Win

function BaseWindow.get(): Window.Win
	return win
end

local function colorOf(w: Formulas.Weapon): Color3
	return if w.mutation > 0 then Palette.Mutation[w.mutation] else Palette.Rarity[w.rarity]
end

-- Куда вставлять: в пустой постамент, иначе вместо самого слабого.
local function targetSlot(): number
	local d = Store.data
	local worst, worstD = 1, math.huge
	for k, id in d.pedestals do
		if id == "" then
			return k
		end
		local w = Store.weapon(id)
		local dmg = if w then Formulas.weaponDamage(w) else 0
		if dmg < worstD then
			worst, worstD = k, dmg
		end
	end
	return worst
end

function BaseWindow.start()
	win = Window.new("Base", "База", 380, 520, "side")
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Size = UDim2.fromScale(1, 1)
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

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function label(text: string, size: number, color: Color3?)
		return Theme.text("Label", list, text, size, {
			Size = UDim2.new(1, -8, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Display,
			TextColor3 = color or Theme.Color.Text,
			LayoutOrder = nextOrder(),
		})
	end
	local function row(height: number): Frame
		local f = Theme.frame("Row", list, {
			Size = UDim2.new(1, -8, 0, height),
			BackgroundColor3 = Theme.Color.PanelSoft,
			LayoutOrder = nextOrder(),
		})
		Theme.corner(f)
		return f
	end

	local function render()
		if not win.isOpen() then
			return
		end
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		order = 0
		local d = Store.data

		-- Монолит.
		local cost = Formulas.monolithCost(d.monolithLevel)
		label(`Монолит · уровень {d.monolithLevel}  (+{d.monolithLevel * 2}% урона)`, 20, Color3.fromRGB(170, 225, 255))
		local barRow = row(16)
		barRow.BackgroundColor3 = Color3.fromRGB(16, 14, 26)
		Theme.frame("Fill", barRow, {
			Size = UDim2.fromScale(math.clamp(d.monolithProgress / cost, 0, 1), 1),
			BackgroundColor3 = Color3.fromRGB(120, 210, 255),
			BackgroundTransparency = 0,
		})
		local nextTier = (math.floor(d.monolithLevel / Config.Monolith.LevelsPerTier) + 1) * Config.Monolith.LevelsPerTier
		local tierText = if Formulas.pedestalCount(nextTier) > Formulas.pedestalCount(d.monolithLevel)
			then `ур. {nextTier}: новый ярус и +1 постамент`
			else `ур. {nextTier}: новый ярус`
		label(`До уровня {d.monolithLevel + 1}: {Formulas.short(math.max(0, cost - d.monolithProgress))} осколков · {tierText}`, 14, Theme.Color.TextDim)
		local pour = Theme.button("Pour", list, `Влить всё · {Formulas.short(d.shards)}`, "primary", {
			Size = UDim2.new(1, -8, 0, 44),
			LayoutOrder = nextOrder(),
			Font = Theme.Display,
			TextSize = 20,
		})
		Theme.setEnabled(pour, d.shards > 0)
		pour.Activated:Connect(function()
			if pour.Active then
				monolithRemote:FireServer("pour")
			end
		end)

		-- Постаменты.
		local arsenal = Store.arsenal()
		label(`Постаменты {#d.pedestals}/{Config.Monolith.MaxPedestals} · арсенал {Formulas.short(arsenal)} · удар {Formulas.short(Store.hitDamage())}`, 18)
		local best = Theme.button("EquipBest", list, "Экипировать лучшее", "primary", {
			Size = UDim2.new(1, -8, 0, 40),
			LayoutOrder = nextOrder(),
			Font = Theme.Display,
		})
		best.Activated:Connect(function()
			pedestalRemote:FireServer("best")
		end)
		for k, id in d.pedestals do
			local r = row(40)
			local w = if id ~= "" then Store.weapon(id) else nil
			Theme.text("Slot", r, `{k}`, 18, { Size = UDim2.fromOffset(28, 40), Font = Theme.Display, TextColor3 = Theme.Color.TextDim })
			Theme.text("Name", r, if w then `{Formulas.weaponName(w)} · {Formulas.short(Formulas.weaponDamage(w))}` else "пусто", 16, {
				Size = UDim2.new(1, -120, 1, 0),
				Position = UDim2.fromOffset(30, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.Display,
				TextColor3 = if w then colorOf(w) else Theme.Color.TextDim,
			})
			if w then
				local remove = Theme.button("Remove", r, "Снять", "secondary", {
					Size = UDim2.fromOffset(80, 30),
					Position = UDim2.new(1, -6, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					TextSize = 14,
				})
				remove.Activated:Connect(function()
					pedestalRemote:FireServer("remove", k)
				end)
			end
		end

		-- Оружие вне постаментов.
		local free = {}
		for _, w in d.weapons do
			if not Store.inPedestal(w.id) then
				table.insert(free, w)
			end
		end
		table.sort(free, function(a, b)
			return Formulas.weaponDamage(a) > Formulas.weaponDamage(b)
		end)
		if #free > 0 then
			label("В инвентаре:", 16, Theme.Color.TextDim)
		end
		local weakest = Store.weakest()
		for i, w in free do
			if i > 12 then
				label(`…и ещё {#free - 12} — все в окне «Оружие»`, 14, Theme.Color.TextDim)
				break
			end
			local r = row(40)
			local better = Formulas.weaponDamage(w) > weakest
			Theme.text("Name", r, `{Formulas.weaponName(w)} · {Formulas.short(Formulas.weaponDamage(w))}`, 16, {
				Size = UDim2.new(1, -110, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.Display,
				TextColor3 = colorOf(w),
			})
			local put = Theme.button("Insert", r, if better then "Вставить ↑" else "Вставить", if better then "primary" else "secondary", {
				Size = UDim2.fromOffset(96, 30),
				Position = UDim2.new(1, -6, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				TextSize = 14,
			})
			put.Activated:Connect(function()
				pedestalRemote:FireServer("insert", targetSlot(), w.id)
			end)
		end
	end

	Store.onChanged(function(section)
		if section == "arsenal" or section == "monolith" or section == "wallet" then
			render()
		end
	end)
	win.root:GetPropertyChangedSignal("Visible"):Connect(render)
end

return BaseWindow

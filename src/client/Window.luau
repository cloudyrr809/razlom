--!strict
-- Общая рамка окна: заголовок, кнопка закрытия, содержимое. Одновременно открыто одно окно.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local Window = {}

export type Win = {
	name: string,
	root: Frame,
	content: Frame,
	title: TextLabel,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onClose: (fn: () -> ()) -> (),
}

local gui: ScreenGui? = nil
local current: Win? = nil

local function screen(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Windows"
	g.ResetOnSpawn = false
	g.DisplayOrder = 10
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	return g
end

function Window.current(): Win?
	return current
end

-- width/height — желаемый размер; на узком экране окно сжимается до экрана.
-- dock = "side": панель справа, мир остаётся виден (станция, гнездо).
function Window.new(name: string, titleText: string, width: number, height: number, dock: string?): Win
	local side = dock == "side"
	local root = Theme.frame(name, screen(), {
		Size = if side then UDim2.fromScale(0.4, 0.56) else UDim2.fromScale(0.94, 0.8),
		Position = if side then UDim2.new(1, -90, 0.52, 0) else UDim2.fromScale(0.5, 0.53),
		AnchorPoint = if side then Vector2.new(1, 0.5) else Vector2.new(0.5, 0.5),
		Visible = false,
		BackgroundTransparency = 0.05,
	})
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, height)
	limit.Parent = root
	Theme.corner(root, UDim.new(0, 14))
	Theme.stroke(root)
	Theme.padding(root, 12)

	local title = Theme.text("Title", root, titleText, 24, {
		Font = Theme.Display,
		Size = UDim2.new(1, -50, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local closeButton = Theme.button("Close", root, "X", "secondary", {
		Font = Theme.Display,
		Size = UDim2.fromOffset(40, 36),
		Position = UDim2.new(1, 0, 0, -2),
		AnchorPoint = Vector2.new(1, 0),
		TextSize = 20,
	})
	local content = Theme.frame("Content", root, {
		Size = UDim2.new(1, 0, 1, -42),
		Position = UDim2.fromOffset(0, 42),
		BackgroundTransparency = 1,
	})

	local closeHandlers: { () -> () } = {}
	local win: Win
	win = {
		name = name,
		root = root,
		content = content,
		title = title,
		open = function()
			if current and current ~= win then
				current.close()
			end
			current = win
			root.Visible = true
		end,
		close = function()
			if not root.Visible then
				return
			end
			root.Visible = false
			if current == win then
				current = nil
			end
			if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
				GuiService.SelectedObject = nil
			end
			for _, fn in closeHandlers do
				fn()
			end
		end,
		isOpen = function()
			return root.Visible
		end,
		onClose = function(fn)
			table.insert(closeHandlers, fn)
		end,
	}
	closeButton.Activated:Connect(win.close)
	return win
end

return Window

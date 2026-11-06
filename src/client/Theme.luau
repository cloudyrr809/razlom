--!strict
-- Оформление интерфейса: цвета, шрифты, размеры и маленькие строительные функции.
-- Каждый элемент получает понятное имя, чтобы его было видно в Explorer.

local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme = {}

Theme.Color = {
	Panel = Color3.fromRGB(22, 26, 36),
	PanelSoft = Color3.fromRGB(34, 40, 54),
	Stroke = Color3.fromRGB(80, 110, 140),
	Text = Color3.fromRGB(240, 244, 250),
	TextDim = Color3.fromRGB(160, 172, 190),
	Accent = Color3.fromRGB(110, 200, 255),
	Shards = Color3.fromRGB(150, 225, 255),
	Good = Color3.fromRGB(110, 220, 130),
	Bad = Color3.fromRGB(255, 110, 100),
	Crit = Color3.fromRGB(255, 220, 60),
	Primary = Color3.fromRGB(60, 150, 230),
	PrimaryPressed = Color3.fromRGB(40, 110, 180),
	Secondary = Color3.fromRGB(56, 64, 84),
	Disabled = Color3.fromRGB(50, 54, 62),
}

Theme.Font = Enum.Font.BuilderSansBold
Theme.FontRegular = Enum.Font.BuilderSans
Theme.Radius = UDim.new(0, 10)
Theme.Gap = 8
Theme.Fade = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Theme.corner(parent: GuiObject, radius: UDim?)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius or Theme.Radius
	c.Parent = parent
end

function Theme.stroke(parent: GuiObject, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Theme.Color.Stroke
	s.Thickness = thickness or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Theme.padding(parent: GuiObject, px: number)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, px)
	p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = u, u, u, u
	p.Parent = parent
end

function Theme.frame(name: string, parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = Theme.Color.Panel
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

function Theme.text(name: string, parent: Instance, text: string, size: number, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = Theme.Font
	t.Text = text
	t.TextSize = size
	t.TextColor3 = Theme.Color.Text
	t.TextWrapped = true
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

export type ButtonKind = "primary" | "secondary"

-- Кнопка с состояниями: наведение, нажатие, недоступна.
function Theme.button(name: string, parent: Instance, text: string, kind: ButtonKind, props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.AutoButtonColor = false
	b.Font = Theme.Font
	b.Text = text
	b.TextSize = 18
	b.TextColor3 = Theme.Color.Text
	b.BorderSizePixel = 0
	local base = if kind == "primary" then Theme.Color.Primary else Theme.Color.Secondary
	b.BackgroundColor3 = base
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	Theme.corner(b, UDim.new(0, 8))
	b.Parent = parent

	local hovered, pressed = false, false
	local function refresh()
		if not b.Active then
			b.BackgroundColor3 = Theme.Color.Disabled
			b.TextColor3 = Theme.Color.TextDim
			return
		end
		b.TextColor3 = Theme.Color.Text
		if pressed then
			b.BackgroundColor3 = if kind == "primary" then Theme.Color.PrimaryPressed else base:Lerp(Color3.new(0, 0, 0), 0.25)
		elseif hovered then
			b.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12)
		else
			b.BackgroundColor3 = base
		end
	end
	b.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end)
	b.MouseLeave:Connect(function()
		hovered, pressed = false, false
		refresh()
	end)
	b.MouseButton1Down:Connect(function()
		pressed = true
		refresh()
	end)
	b.MouseButton1Up:Connect(function()
		pressed = false
		refresh()
	end)
	b:GetPropertyChangedSignal("Active"):Connect(refresh)
	refresh()
	return b
end

function Theme.setEnabled(b: GuiButton, enabled: boolean)
	b.Active = enabled
	b.AutoButtonColor = false
end

function Theme.tween(obj: Instance, info: TweenInfo, goal: { [string]: any })
	if GuiService.ReducedMotionEnabled then
		for k, v in goal do
			(obj :: any)[k] = v
		end
		return
	end
	TweenService:Create(obj, info, goal):Play()
end

return Theme

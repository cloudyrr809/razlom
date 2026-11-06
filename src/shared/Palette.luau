--!strict
-- Цвета мира и интерфейса (это оформление, а не баланс). Финальный арт заменит заглушки.

local Palette = {}

Palette.Zones = {
	{
		sand = Color3.fromRGB(226, 205, 168),
		sandDark = Color3.fromRGB(196, 172, 134),
		glow = Color3.fromRGB(110, 200, 255),
		crystal = Color3.fromRGB(170, 225, 255),
	},
	{
		sand = Color3.fromRGB(190, 110, 72),
		sandDark = Color3.fromRGB(150, 82, 54),
		glow = Color3.fromRGB(255, 140, 50),
		crystal = Color3.fromRGB(255, 190, 120),
	},
}

-- Редкости: Обычное, Необычное, Редкое, Эпическое, Легендарное.
Palette.Rarity = {
	Color3.fromRGB(190, 196, 204),
	Color3.fromRGB(110, 220, 120),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(190, 100, 255),
	Color3.fromRGB(255, 175, 40),
}

-- Мутации: Заряженная, Золотая, Призматическая, Пустотная.
Palette.Mutation = {
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(255, 205, 60),
	Color3.fromRGB(255, 120, 220),
	Color3.fromRGB(140, 60, 255),
}

Palette.Rainbow = {
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(120, 255, 140),
	Color3.fromRGB(90, 200, 255),
	Color3.fromRGB(190, 120, 255),
}

Palette.VoidBody = Color3.fromRGB(24, 18, 34)
Palette.Gold = Color3.fromRGB(240, 190, 60)
Palette.Stone = Color3.fromRGB(120, 112, 104)
Palette.Base = Color3.fromRGB(214, 196, 160)

return Palette

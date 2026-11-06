--!strict
-- Точка входа клиента «Разломов».

local StarterGui = game:GetService("StarterGui")

local Store = require(script.Store)
local World = require(script.World)
local Input = require(script.Input)
local CreepFx = require(script.CreepFx)
local Hud = require(script.Hud)
local Effects = require(script.Effects)
local Window = require(script.Window)
local InventoryWindow = require(script.InventoryWindow)
local UpgradesWindow = require(script.UpgradesWindow)
local BaseWindow = require(script.BaseWindow)
local RevealScreen = require(script.RevealScreen)
local Cosmetics = require(script.Cosmetics)
local Guide = require(script.Guide)
local Ambient = require(script.Ambient)

-- Оружие в руке выбирается в инвентаре: стандартный рюкзак не нужен.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

Store.start()
Input.start()
CreepFx.start()
Hud.start()
Effects.start()
InventoryWindow.start()
UpgradesWindow.start()
BaseWindow.start()
RevealScreen.start()
Cosmetics.start()
Guide.start()
Ambient.start()

Hud.on("inventory", InventoryWindow.toggle)
Hud.on("upgrades", UpgradesWindow.toggle)
Hud.on("open", RevealScreen.open)
Hud.setAffordable(UpgradesWindow.affordable)

-- Окно базы открывается само у своего Монолита и закрывается при уходе.
-- Если игрок закрыл его сам, оно не откроется снова, пока он не отойдёт.
local baseWin = BaseWindow.get()
local dismissed = false
local auto = false
local suppress = false
baseWin.onClose(function()
	if auto and not suppress then
		dismissed = true
	end
	auto = false
end)

task.spawn(function()
	while true do
		task.wait(0.2)
		local near = World.nearMonolith()
		if not near then
			dismissed = false
			if auto then
				suppress = true
				baseWin.close()
				suppress = false
			end
		elseif not dismissed and not baseWin.isOpen() and Window.current() == nil then
			baseWin.open()
			auto = true
		end
	end
end)

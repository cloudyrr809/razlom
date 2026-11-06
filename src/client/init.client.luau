--!strict
-- Точка входа клиента «Разломов».

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Store = require(script.Store)
local World = require(script.World)
local Input = require(script.Input)
local CreepFx = require(script.CreepFx)
local Effects = require(script.Effects)
local Hud = require(script.Hud)
local Window = require(script.Window)
local InventoryWindow = require(script.InventoryWindow)
local StationWindow = require(script.StationWindow)
local NestWindow = require(script.NestWindow)
local Cosmetics = require(script.Cosmetics)

-- Оружие одно и всегда в руке: стандартный рюкзак не нужен.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

Store.start()
Input.start()
CreepFx.start()
Effects.start()
Hud.start()
InventoryWindow.start()
StationWindow.start()
NestWindow.start()
Cosmetics.start()
Hud.onInventory(InventoryWindow.toggle)

-- Окна станции и гнезда открываются сами при подходе и закрываются при уходе.
-- Если игрок закрыл окно сам, оно не откроется снова, пока он не отойдёт.
local dismissed: string? = nil
local autoOpened: string? = nil
local suppress = false

local function target(): (string?, number?)
	local k = World.nearNest(Config.Base.NestRange)
	if k then
		return "nest" .. k, k
	end
	if World.nearStation(Config.Base.StationRange) then
		return "station", nil
	end
	return nil, nil
end

for _, win in { NestWindow.get(), StationWindow.get() } do
	win.onClose(function()
		if not suppress and not NestWindow.switching and autoOpened then
			dismissed = autoOpened
		end
		if not NestWindow.switching then
			autoOpened = nil
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(0.2)
		local key, nest = target()
		if key ~= dismissed then
			dismissed = nil
		end
		local current = Window.current()
		if autoOpened and autoOpened ~= key then
			suppress = true
			if current then
				current.close()
			end
			suppress = false
			autoOpened = nil
			current = Window.current()
		end
		if key and key ~= dismissed and not current then
			if nest then
				NestWindow.openAt(nest)
			else
				StationWindow.get().open()
			end
			autoOpened = key
		end
	end
end)

--!strict
-- Точка входа сервера «Разломов». Порядок важен: сначала подписки, потом данные игрока.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Группы столкновений: крипы стоят на земле, но не толкают игроков и друг друга.
Workspace:RegisterCollisionGroup("Creeps")
Workspace:RegisterCollisionGroup("Players")
Workspace:CollisionGroupSetCollidable("Creeps", "Creeps", false)
Workspace:CollisionGroupSetCollidable("Creeps", "Players", false)

local function setGroup(d: Instance)
	if d:IsA("BasePart") then
		d.CollisionGroup = "Players"
	end
end
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		for _, d in character:GetDescendants() do
			setGroup(d)
		end
		character.DescendantAdded:Connect(setGroup)
	end)
end)

local PlayerState = require(script.PlayerState)
local Bases = require(script.Bases)
local Creeps = require(script.Creeps)
local Zones = require(script.Zones)
local Monolith = require(script.Monolith)
local Arsenal = require(script.Arsenal)
local Spheres = require(script.Spheres)
local Combat = require(script.Combat)
local Upgrades = require(script.Upgrades)
local Fall = require(script.Fall)

-- Подписки «игрок вошёл» регистрируются до PlayerState.start(), чтобы никого не пропустить.
Bases.start()
Monolith.start()
Arsenal.start()
Upgrades.start()
Spheres.start()
Combat.start()
Creeps.start()
Zones.start()
Fall.start()
PlayerState.start()

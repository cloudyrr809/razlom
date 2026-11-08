--!strict
-- Упал в пропасть — погиб. Возрождение обычное: Bases ставит персонажа на его базу.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Fall = {}

function Fall.start()
	local fallY = Config.World.Chasm.FallY
	task.spawn(function()
		while true do
			task.wait(Config.World.ZoneTrackInterval)
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and root.Position.Y < fallY then
					humanoid.Health = 0
				end
			end
		end
	end)
end

return Fall

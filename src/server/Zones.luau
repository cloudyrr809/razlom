--!strict
-- Где находится каждый игрок: для плотности крипов и надписи при первом входе в зону.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local PlayerState = require(script.Parent.PlayerState)
local Creeps = require(script.Parent.Creeps)

local notice = ReplicatedStorage.Remotes.Notice :: RemoteEvent

local Zones = {}

function Zones.start()
	task.spawn(function()
		while true do
			task.wait(Config.World.ZoneTrackInterval)
			local counts = table.create(#Config.Zones, 0)
			for player, session in PlayerState.all() do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local zone = if root and root:IsA("BasePart") then Formulas.zoneAt(root.Position) else 0
				session.zone = zone
				if zone > 0 then
					counts[zone] += 1
					if not session.seenZones[zone] then
						session.seenZones[zone] = true
						notice:FireClient(player, "zone", zone)
					end
				end
			end
			for i, n in counts do
				Creeps.setPlayers(i, n)
			end
		end
	end)
end

return Zones

--!strict
-- Где что лежит на карте с точки зрения клиента: своя база, гнёзда, станция, свой персонаж.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Store = require(script.Parent.Store)

local World = {}
local player = Players.LocalPlayer

function World.root(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function World.base(index: number?): Model?
	if not index then
		return nil
	end
	for _, b in CollectionService:GetTagged("Base") do
		if b:IsA("Model") and b:GetAttribute("Index") == index then
			return b
		end
	end
	return nil
end

function World.nest(baseIndex: number?, k: number): BasePart?
	for _, n in CollectionService:GetTagged("Nest") do
		if n:IsA("BasePart") and n:GetAttribute("Base") == baseIndex and n:GetAttribute("Index") == k then
			return n
		end
	end
	return nil
end

function World.station(baseIndex: number?): Model?
	for _, s in CollectionService:GetTagged("Station") do
		if s:IsA("Model") and s:GetAttribute("Base") == baseIndex then
			return s
		end
	end
	return nil
end

-- Расстояние по горизонтали от своего персонажа до точки (или бесконечность).
function World.distanceTo(p: Vector3): number
	local root = World.root()
	if not root then
		return math.huge
	end
	local d = root.Position - p
	if math.abs(d.Y) > 10 then
		return math.huge
	end
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Ближайшее своё гнездо в радиусе, или nil.
function World.nearNest(range: number): number?
	local best, bestD = nil, range
	for k = 1, 3 do
		local n = World.nest(Store.data.baseIndex, k)
		if n then
			local d = World.distanceTo(n.Position)
			if d <= bestD then
				best, bestD = k, d
			end
		end
	end
	return best
end

function World.nearStation(range: number): boolean
	local s = World.station(Store.data.baseIndex)
	return s ~= nil and World.distanceTo(s:GetPivot().Position) <= range
end

return World

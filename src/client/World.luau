--!strict
-- Где что лежит на карте с точки зрения клиента: своя база, Монолит, постаменты, свой персонаж.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
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

-- Центр Монолита базы (своей, если индекс не указан).
function World.monolith(index: number?): Vector3?
	local base = World.base(index or Store.data.baseIndex)
	local mono = base and base:FindFirstChild("Monolith")
	if mono and mono:IsA("Model") then
		return mono:GetPivot().Position
	end
	return nil
end

function World.pedestal(baseIndex: number?, k: number): BasePart?
	for _, p in CollectionService:GetTagged("Pedestal") do
		if p:IsA("BasePart") and p:GetAttribute("Base") == baseIndex and p:GetAttribute("Index") == k then
			return p
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
	if math.abs(d.Y) > 15 then
		return math.huge
	end
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Стоит ли игрок у своего Монолита (там окно базы: постаменты и вливание).
function World.nearMonolith(): boolean
	local p = World.monolith(nil)
	return p ~= nil and World.distanceTo(p) <= Config.Monolith.Range - 1
end

return World

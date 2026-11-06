--!strict
-- Внешний вид прокачки у всех игроков: Кольцо крутится под ногами (быстрее с уровнем),
-- Аура — шлейф за спиной (длиннее с уровнем). Каждые 10 уровней — новый цвет.
-- Только для глаз: уровни берутся из атрибутов игрока, которые ставит сервер.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local Cosmetics = {}

local TIER_COLORS = {
	Color3.fromRGB(150, 200, 230),
	Color3.fromRGB(110, 200, 255),
	Color3.fromRGB(120, 255, 170),
	Color3.fromRGB(255, 200, 80),
	Color3.fromRGB(255, 110, 200),
	Color3.fromRGB(170, 110, 255),
}
local SEGMENTS = 10

type Look = { segments: { BasePart }, trail: Trail?, angle: number }
local looks: { [Player]: Look } = {}
local folder: Folder

local function tierColor(level: number, every: number): Color3
	local tier = math.floor(level / every) + 1
	return TIER_COLORS[math.min(tier, #TIER_COLORS)]
end

local function clear(p: Player)
	local look = looks[p]
	if look then
		for _, s in look.segments do
			s:Destroy()
		end
		if look.trail then
			look.trail:Destroy()
		end
		looks[p] = nil
	end
end

local function build(p: Player, character: Model)
	clear(p)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or p.Character ~= character then
		return
	end
	local segments: { BasePart } = {}
	for _ = 1, SEGMENTS do
		local s = Instance.new("Part")
		s.Anchored = true
		s.CanCollide = false
		s.CanQuery = false
		s.CanTouch = false
		s.CastShadow = false
		s.Material = Enum.Material.Neon
		s.Size = Vector3.new(0.9, 0.12, 0.3)
		s.Parent = folder
		table.insert(segments, s)
	end
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, 0.9, 0.6)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -0.9, 0.6)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "AuraTrail"
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.LightEmission = 1
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.FaceCamera = true
	trail.Parent = root
	looks[p] = { segments = segments, trail = trail, angle = 0 }
end

local function bindPlayer(p: Player)
	p.CharacterAdded:Connect(function(c)
		build(p, c)
	end)
	if p.Character then
		task.spawn(build, p, p.Character)
	end
end

function Cosmetics.start()
	folder = Instance.new("Folder")
	folder.Name = "Cosmetics"
	folder.Parent = Workspace
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(clear)
	for _, p in Players:GetPlayers() do
		bindPlayer(p)
	end

	RunService.RenderStepped:Connect(function(dt: number)
		for p, look in looks do
			local character = p.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not root:IsA("BasePart") or not humanoid then
				continue
			end
			local ring = p:GetAttribute("RingLevel")
			local aura = p:GetAttribute("AuraLevel")
			local ringLevel = if type(ring) == "number" then ring else 0
			local auraLevel = if type(aura) == "number" then aura else 0

			look.angle += dt * (0.8 + ringLevel * 0.25)
			local color = tierColor(ringLevel, Config.Upgrades.Ring.lookEvery)
			local footY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2 + 0.15
			local center = Vector3.new(root.Position.X, footY, root.Position.Z)
			local radius = 2.2
			for i, s in look.segments do
				local a = look.angle + (i / SEGMENTS) * math.pi * 2
				s.CFrame = CFrame.new(center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius) * CFrame.Angles(0, -a, 0)
				s.Color = color
				s.Transparency = if ringLevel == 0 then 0.6 else 0.1
			end
			if look.trail then
				look.trail.Enabled = auraLevel > 0
				look.trail.Lifetime = 0.15 + auraLevel * 0.04
				look.trail.Color = ColorSequence.new(tierColor(auraLevel, Config.Upgrades.Aura.lookEvery))
				look.trail.WidthScale = NumberSequence.new(1 + auraLevel * 0.03, 0)
			end
		end
	end)
end

return Cosmetics

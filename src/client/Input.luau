--!strict
-- Удар: клик мышью, зажатие (мышь, палец на кнопке «Удар», курок геймпада).
-- Клиент бьёт в темпе Кольца, чтобы не тратить удары впустую, но решает сервер.
-- Если идёт своё вскрытие и игрок у гнезда — удары идут по Сфере.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Store = require(script.Parent.Store)
local World = require(script.Parent.World)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local hitRemote = Remotes:WaitForChild("Hit") :: RemoteEvent
local revealRemote = Remotes:WaitForChild("RevealHit") :: RemoteEvent

local Input = {}
local player = Players.LocalPlayer

local holdSources: { [string]: boolean } = {}
local queued = false -- одиночный клик раньше срока ждёт ближайшего разрешённого момента
local nextAt = 0

local function holding(): boolean
	return next(holdSources) ~= nil
end

Input.onRevealHit = function() end

-- Пока на экране Сфера, все удары идут по ней (это задаёт RevealScreen).
Input.revealing = function(): boolean
	return false
end

-- Есть ли крип в радиусе удара (по позициям, которые видит клиент, с запасом).
local function creepInRange(): boolean
	local root = World.root()
	local folder = Workspace:FindFirstChild("Creeps")
	if not root or not folder then
		return false
	end
	for _, model in folder:GetChildren() do
		local r = model:IsA("Model") and model.PrimaryPart
		local size = model:GetAttribute("Size")
		if r and type(size) == "number" then
			local d = (r.Position - root.Position) * Vector3.new(1, 0, 1)
			if d.Magnitude - Config.Creeps.Sizes[size].radius <= Config.Combat.HitRadius + 1 then
				return true
			end
		end
	end
	return false
end

local function swing()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool then
		-- Стандартный скрипт Animate проигрывает взмах, когда в Tool появляется toolanim.
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = "Slash"
		anim.Parent = tool
	end
end

local function tryFire(): boolean
	local t = os.clock()
	if t < nextAt then
		return false
	end
	if Input.revealing() then
		nextAt = t + 1 / Config.Spheres.RevealRate * 1.05
		revealRemote:FireServer()
		Input.onRevealHit()
		return true
	end
	if not creepInRange() then
		return false
	end
	nextAt = t + 1 / Formulas.hitsPerSecond(Store.data.ring) * 1.02
	hitRemote:FireServer()
	swing()
	return true
end

function Input.press(source: string)
	holdSources[source] = true
	if not tryFire() then
		queued = true
	end
end

function Input.release(source: string)
	holdSources[source] = nil
end

function Input.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.press("mouse")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			Input.press("gamepad")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.release("mouse")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			Input.release("gamepad")
		end
	end)
	RunService.RenderStepped:Connect(function()
		if holding() or queued then
			-- Одиночный клик ждёт ближайшего разрешённого момента; нет цели — пропадает.
			local fired = tryFire()
			if fired or os.clock() >= nextAt then
				queued = false
			end
		end
	end)
end

return Input

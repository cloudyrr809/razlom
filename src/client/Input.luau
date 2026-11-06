--!strict
-- Удар: игрок кликает (тапает) прямо по крипу. Зажатие бьёт того, кто под курсором.
-- Геймпад целится центром экрана. Клиент бьёт в темпе Кольца, но решает сервер.
-- Если идёт своё вскрытие — удары идут по Сфере.

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

-- Прицел источника: луч из камеры туда, куда указывает игрок.
type Aim = () -> Ray?
local function noAim(): Ray? -- источник без прицела (вскрытие Сферы)
	return nil
end
local holdSources: { [string]: Aim } = {}
local queuedAim: Aim? = nil -- клик чуть раньше срока ждёт ближайшего разрешённого момента
local nextAt = 0

Input.onRevealHit = function() end
-- Своя реакция крипа на удар — сразу, не дожидаясь ответа сервера (это задаёт init).
Input.onCreepHit = function(_id: number) end

-- Пока на экране Сфера, все удары идут по ней (это задаёт RevealScreen).
Input.revealing = function(): boolean
	return false
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

-- Крип под прицелом, если до него можно достать.
local function creepUnder(aim: Aim): (Model?, number?)
	local root = World.root()
	local folder = Workspace:FindFirstChild("Creeps")
	local ray = aim()
	if not root or not folder or not ray then
		return nil, nil
	end
	rayParams.FilterDescendantsInstances = { folder }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	local hit = result and result.Instance.Parent
	local model = if hit and hit:IsA("Model") and hit.Parent == folder then hit else nil
	local r = model and model.PrimaryPart
	local size = model and model:GetAttribute("Size")
	local id = model and model:GetAttribute("CreepId")
	if not model or not r or type(size) ~= "number" or type(id) ~= "number" then
		return nil, nil
	end
	local gap = ((r.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude - Config.Creeps.Sizes[size].radius
	if gap > Config.Combat.HitRadius + 1 then
		return nil, nil
	end
	return model, id
end

-- Игрок разворачивается к крипу, по которому кликнул (только по горизонтали).
local function face(model: Model)
	local root = World.root()
	local target = model.PrimaryPart
	if not root or not target then
		return
	end
	local p = root.Position
	local look = Vector3.new(target.Position.X, p.Y, target.Position.Z)
	if (look - p).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(p, look)
	end
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

local function tryFire(aim: Aim): boolean
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
	local model, id = creepUnder(aim)
	if not model or not id then
		return false
	end
	nextAt = t + 1 / Formulas.hitsPerSecond(Store.data.ring) * 1.02
	Input.onCreepHit(id) -- сначала звук и реакция, потом сеть
	face(model)
	hitRemote:FireServer(id)
	swing()
	return true
end

function Input.press(source: string, aim: Aim?)
	local a = aim or noAim
	holdSources[source] = a
	if not tryFire(a) and nextAt - os.clock() <= Config.Combat.ClickQueueWindow then
		queuedAim = a
	end
end

function Input.release(source: string)
	holdSources[source] = nil
end

local function camera(): Camera?
	return Workspace.CurrentCamera
end

local function mouseAim(): Ray?
	local cam = camera()
	local p = UserInputService:GetMouseLocation()
	return cam and cam:ViewportPointToRay(p.X, p.Y)
end

local function centerAim(): Ray?
	local cam = camera()
	return cam and cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
end

function Input.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.press("mouse", mouseAim)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			-- Палец можно вести по экрану: прицел идёт за ним.
			Input.press("touch", function(): Ray?
				local cam = camera()
				return cam and cam:ScreenPointToRay(input.Position.X, input.Position.Y)
			end)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			Input.press("gamepad", centerAim)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.release("mouse")
		elseif input.UserInputType == Enum.UserInputType.Touch then
			Input.release("touch")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			Input.release("gamepad")
		end
	end)
	RunService.RenderStepped:Connect(function()
		if queuedAim ~= nil then
			local fired = tryFire(queuedAim)
			if fired or os.clock() >= nextAt then
				queuedAim = nil
			end
			return
		end
		for _, aim in holdSources do
			if tryFire(aim) then
				break
			end
		end
	end)
end

return Input

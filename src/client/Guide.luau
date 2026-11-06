--!strict
-- Обучение первых минут без текста-учебника: подсказка внизу экрана,
-- бегущие стрелки на земле от игрока к цели и маяк над целью.
-- Шаги: дорога → удар → Крупный ради Сферы → «Открой» → «Вставь на базе!» → «Влей в Монолит».
-- «Вставь на базе!» со стрелкой домой работает и после обучения — каждый раз, когда
-- выпало оружие сильнее самого слабого в постаментах.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local World = require(script.Parent.World)

local Guide = {}
local player = Players.LocalPlayer

local CHEVRONS = 9
local GAP = 3.2
local COLOR = Color3.fromRGB(120, 230, 255)

local kills = 0
local reachedRoad = false
local finished = false

type Step = { text: string, target: Vector3? }

local function nearestCreep(size: number?): Vector3?
	local root = World.root()
	local folder = Workspace:FindFirstChild("Creeps")
	if not root or not folder then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m.PrimaryPart and m:GetAttribute("Zone") == 1 and (size == nil or m:GetAttribute("Size") == size) then
			local d = (m.PrimaryPart.Position - root.Position).Magnitude
			if d < bestD then
				best, bestD = m.PrimaryPart.Position, d
			end
		end
	end
	return best
end

local function hitWord(): string
	return if UserInputService.PreferredInput == Enum.PreferredInput.Touch then "Тапай" else "Кликай"
end

local function current(): Step?
	local d = Store.data
	-- Новое оружие сильнее вставленного — домой, всегда.
	if Store.betterWaiting() then
		return { text = "Вставь на базе! Новое оружие сильнее", target = World.monolith(nil) }
	end
	if finished then
		return nil
	end
	if not reachedRoad then
		return { text = "Беги на тропу — там лагеря крипов", target = Config.World.RoadStart + Vector3.new(4, 0, 0) }
	end
	if kills == 0 then
		return { text = `{hitWord()} прямо по крипу — бей!`, target = nearestCreep(nil) }
	end
	if d.opened == 0 then
		if #d.spheres > 0 then
			return { text = "Сфера у тебя! Жми «Открыть» слева", target = nil }
		end
		return { text = "Бей Крупных крипов — из них падают Сферы с оружием", target = nearestCreep(3) }
	end
	if d.monolithLevel == 0 then
		if d.shards >= Formulas.monolithCost(0) then
			return { text = "Влей осколки в Монолит — урон вырастет", target = World.monolith(nil) }
		end
		return { text = `Собери {Formulas.short(Formulas.monolithCost(0))} осколков и влей их в Монолит`, target = nil }
	end
	finished = true
	return nil
end

function Guide.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Guide"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Подсказка справа, под круглыми кнопками: центр экрана свободен для игры.
	local hint = Theme.frame("Hint", gui, {
		Size = UDim2.fromOffset(240, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(1, -8, 0.4, 100),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0.15,
		Visible = false,
	})
	Theme.corner(hint, UDim.new(0, 14))
	Theme.stroke(hint, COLOR, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = hint
	local text = Theme.text("Text", hint, "", 17, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Display,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Стрелки на земле и маяк живут только у этого игрока.
	local folder = Instance.new("Folder")
	folder.Name = "GuideFx"
	folder.Parent = Workspace
	local chevrons: { { BasePart } } = {}
	for i = 1, CHEVRONS do
		local pair: { BasePart } = {}
		for side = -1, 1, 2 do
			local p = Instance.new("Part")
			p.Name = "Chevron"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.Neon
			p.Color = COLOR
			p.Size = Vector3.new(0.35, 0.08, 1.5)
			p:SetAttribute("Side", side)
			p.Parent = folder
			table.insert(pair, p)
		end
		chevrons[i] = pair
	end
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.CastShadow = false
	beacon.Material = Enum.Material.Neon
	beacon.Color = COLOR
	beacon.Transparency = 0.75
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Size = Vector3.new(30, 2.2, 2.2)
	beacon.Parent = folder
	local diamond = Instance.new("Part")
	diamond.Name = "Diamond"
	diamond.Anchored = true
	diamond.CanCollide = false
	diamond.CanQuery = false
	diamond.CanTouch = false
	diamond.Material = Enum.Material.Neon
	diamond.Color = COLOR
	diamond.Size = Vector3.new(1.4, 1.4, 1.4)
	diamond.Parent = folder

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	;(remotes:WaitForChild("KillFx") :: RemoteEvent).OnClientEvent:Connect(function(info: any)
		if info.killer == player.UserId then
			kills += 1
		end
	end)

	local step: Step? = nil
	task.spawn(function()
		while true do
			local root = World.root()
			if root and Formulas.zoneAt(root.Position) > 0 then
				reachedRoad = true
			end
			step = current()
			-- Пока на экране Сфера — подсказку не показываем.
			local reveal = player.PlayerGui:FindFirstChild("Reveal")
			local revealRoot = reveal and reveal:FindFirstChild("Root")
			local busy = revealRoot ~= nil and revealRoot:IsA("GuiObject") and revealRoot.Visible
			hint.Visible = step ~= nil and not busy
			if step then
				text.Text = step.text
			end
			task.wait(0.25)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local root = World.root()
		local target = step and step.target
		local show = root ~= nil and target ~= nil
		beacon.Transparency = if show then 0.75 else 1
		diamond.Transparency = if show then 0 else 1
		if not root or not target then
			for _, pair in chevrons do
				for _, p in pair do
					p.Transparency = 1
				end
			end
			return
		end
		local t = os.clock()
		local feet = root.Position - Vector3.new(0, 2.9, 0)
		local flat = Vector3.new(target.X - feet.X, 0, target.Z - feet.Z)
		local dist = flat.Magnitude
		local dir = if dist > 0.1 then flat.Unit else Vector3.zAxis
		local shift = (t * 6) % GAP
		for i, pair in chevrons do
			local along = 3 + (i - 1) * GAP + shift
			local visible = along < dist - 2
			local pos = feet + dir * along
			-- Ромбик «>» из двух полосок, смотрящий на цель.
			local base = CFrame.lookAt(pos, pos + dir)
			for _, p in pair do
				local side = p:GetAttribute("Side") :: number
				p.CFrame = base * CFrame.new(side * 0.45, 0, 0) * CFrame.Angles(0, math.rad(-side * 40), 0)
				p.Transparency = if visible then 0.15 + (i / CHEVRONS) * 0.6 else 1
			end
		end
		beacon.CFrame = CFrame.new(target + Vector3.new(0, 15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		diamond.CFrame = CFrame.new(target + Vector3.new(0, 6 + math.sin(t * 3) * 0.6, 0)) * CFrame.Angles(t * 1.5, t * 2, math.rad(45))
	end)
end

return Guide

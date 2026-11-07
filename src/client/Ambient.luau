--!strict
-- Жизнь мира без влияния на игру: светящиеся детали карты (тег Glow) мягко «дышат»,
-- модели с тегом Spin вращаются.
-- Только у этого игрока, раз в два кадра, чтобы не тратить лишнего.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Ambient = {}

type Item = { part: BasePart, base: number, phase: number }
local items: { Item } = {}

local function add(inst: Instance)
	if inst:IsA("BasePart") then
		table.insert(items, { part = inst, base = inst.Transparency, phase = math.random() * 10 })
	end
end

-- Модели с тегом Spin медленно вращаются вокруг своей опорной точки (атрибут Speed, рад/с).
type Spinner = { model: Model, start: CFrame, speed: number }
local spinners: { Spinner } = {}

local function addSpin(inst: Instance)
	if inst:IsA("Model") then
		local speed = inst:GetAttribute("Speed")
		table.insert(spinners, { model = inst, start = inst:GetPivot(), speed = if typeof(speed) == "number" then speed else 0 })
	end
end

function Ambient.start()
	for _, p in CollectionService:GetTagged("Glow") do
		add(p)
	end
	CollectionService:GetInstanceAddedSignal("Glow"):Connect(add)
	for _, m in CollectionService:GetTagged("Spin") do
		addSpin(m)
	end
	CollectionService:GetInstanceAddedSignal("Spin"):Connect(addSpin)
	local frame = 0
	RunService.RenderStepped:Connect(function()
		frame += 1
		if frame % 2 == 1 then
			return
		end
		local t = os.clock()
		for _, it in items do
			local k = 0.5 + math.sin(t * 1.6 + it.phase) * 0.5
			it.part.Transparency = math.clamp(it.base + k * (1 - it.base) * 0.35, 0, 1)
		end
		for _, s in spinners do
			if s.model.Parent then
				s.model:PivotTo(s.start * CFrame.Angles(0, t * s.speed, 0))
			end
		end
	end)
end

return Ambient

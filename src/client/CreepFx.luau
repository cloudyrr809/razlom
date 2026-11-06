--!strict
-- Всё, что видно над крипом и при ударе: полоска HP с регеном, замок «до пробоя»,
-- цифры урона, сплющивание, крит, рассыпание песком и фонтан осколков убийце.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local World = require(script.Parent.World)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local hitFx = Remotes:WaitForChild("HitFx") :: UnreliableRemoteEvent
local killFx = Remotes:WaitForChild("KillFx") :: RemoteEvent

local CreepFx = {}
local player = Players.LocalPlayer

type View = {
	model: Model,
	root: BasePart,
	gui: BillboardGui,
	fill: Frame,
	regen: Frame,
	lock: TextLabel,
	lockBar: Frame,
	lastHit: number,
	cracks: { BasePart },
}
local views: { [number]: View } = {}

local SOUND_HIT = "rbxasset://sounds/swordslash.wav"
local SOUND_CRIT = "rbxasset://sounds/electronicpingshort.wav"

local function playSound(id: string, volume: number, pitch: number, at: BasePart?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.Parent = at or SoundService
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(4, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end
CreepFx.playSound = playSound

local function num(model: Instance, name: string): number
	local v = model:GetAttribute(name)
	return if type(v) == "number" then v else 0
end

local function bind(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model.PrimaryPart or model:WaitForChild("Root", 5)
	if not root or not root:IsA("BasePart") or not model.Parent then
		return
	end
	local id = num(model, "CreepId")
	local size = math.max(1, num(model, "Size"))
	local mutation = num(model, "Mutation")
	local s = Config.Creeps.Sizes[size]

	local gui = Instance.new("BillboardGui")
	gui.Name = "CreepGui"
	gui.Size = UDim2.fromScale(math.max(3.2, s.radius * 2.2), 1.6)
	gui.StudsOffset = Vector3.new(0, s.height / 2 + 1.4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = root

	local bar = Theme.frame("Bar", gui, {
		Size = UDim2.fromScale(1, 0.32),
		Position = UDim2.fromScale(0, 0.68),
		BackgroundColor3 = Color3.fromRGB(20, 20, 24),
		BackgroundTransparency = 0.2,
	})
	Theme.corner(bar, UDim.new(0.5, 0))
	local regen = Theme.frame("Regen", bar, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Good,
		BackgroundTransparency = 0,
	})
	Theme.corner(regen, UDim.new(0.5, 0))
	local fill = Theme.frame("Fill", bar, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(235, 70, 70),
		BackgroundTransparency = 0,
	})
	Theme.corner(fill, UDim.new(0.5, 0))

	local m = Config.CreepMutations[mutation]
	local title = if m then m.name .. " · " .. s.name else s.name
	Theme.text("Title", gui, title, 14, {
		Size = UDim2.fromScale(1, 0.34),
		Position = UDim2.fromScale(0, 0.32),
		TextScaled = true,
		TextColor3 = if m then Palette.Mutation[mutation] else Theme.Color.Text,
		TextStrokeTransparency = 0.5,
	})
	local lock = Theme.text("Lock", gui, "", 14, {
		Size = UDim2.fromScale(1, 0.32),
		Position = UDim2.fromScale(0, 0),
		TextScaled = true,
		TextColor3 = Theme.Color.Crit,
		TextStrokeTransparency = 0.4,
		Visible = false,
	})
	local lockBar = Theme.frame("LockBar", lock, {
		Size = UDim2.fromOffset(0, 3),
		Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Color.Crit,
		BackgroundTransparency = 0,
	})
	gui.Parent = root

	local cracks = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d.Name == "Crack" then
			table.insert(cracks, d)
		end
	end

	views[id] = {
		model = model,
		root = root,
		gui = gui,
		fill = fill,
		regen = regen,
		lock = lock,
		lockBar = lockBar,
		lastHit = 0,
		cracks = cracks,
	}

	-- Звук и подсказка для Золотого и реже, если игрок в той же зоне.
	if m and m.pointer then
		local myRoot = World.root()
		if myRoot and Formulas.zoneAt(myRoot.Position) == num(model, "Zone") then
			playSound(SOUND_CRIT, 0.6, 0.7, nil)
		end
	end

	model.Destroying:Once(function()
		views[id] = nil
	end)
end

local function updateView(v: View, t: number)
	local hp, maxHp = num(v.model, "Hp"), math.max(num(v.model, "MaxHp"), 0.001)
	local frac = math.clamp(hp / maxHp, 0, 1)
	v.fill.Size = UDim2.fromScale(frac, 1)
	-- Зелёная полоска показывает, сколько крип откатит за ближайшую секунду.
	local regenFrac = math.clamp(frac + Config.Creeps.RegenPerSecond, 0, 1)
	v.regen.Size = UDim2.fromScale(regenFrac, 1)
	v.regen.Visible = frac < 1

	local regen = Formulas.regenPerSecond(maxHp)
	local dps = Store.dps()
	local locked = dps <= regen
	v.lock.Visible = locked
	if locked then
		local pct = math.floor(dps / regen * 100)
		v.lock.Text = `🔒 до пробоя: {pct}%`
		v.lockBar.Size = UDim2.new(pct / 100, 0, 0, 3)
	end
	local inCombat = t - v.lastHit < Config.Creeps.InCombatTime
	v.gui.Enabled = frac < 1 or locked or inCombat or World.distanceTo(v.root.Position) < 30

	-- Призматический переливается.
	if num(v.model, "Mutation") == 3 then
		local c = Color3.fromHSV((t * 0.3) % 1, 0.6, 1)
		for _, crack in v.cracks do
			crack.Color = c
		end
	end
end

local function floatText(at: Vector3, text: string, color: Color3, big: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = at + Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
	anchor.Parent = Workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if big then 160 else 110, if big then 64 else 42)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Theme.text("Number", gui, text, if big then 42 else 28, {
		Size = UDim2.fromScale(1, 1),
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
	})
	gui.Parent = anchor
	local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { Position = anchor.Position + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.85, function()
		anchor:Destroy()
	end)
end
CreepFx.floatText = floatText

local function squash(v: View)
	local body = v.model:FindFirstChild("Body")
	if body and body:IsA("BasePart") and not body:GetAttribute("Squashing") then
		body:SetAttribute("Squashing", true)
		local size = body.Size
		local info = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
		local tw = TweenService:Create(body, info, { Size = Vector3.new(size.X * 0.7, size.Y * 1.15, size.Z * 1.15) })
		tw:Play()
		tw.Completed:Once(function()
			body.Size = size
			body:SetAttribute("Squashing", nil)
		end)
	end
end

-- Короткие светящиеся «осколки», летящие из крипа (Крупный при ударе и все при смерти).
local function chips(from: Vector3, to: Vector3?, count: number, color: Color3, duration: number)
	for _ = 1, count do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Size = Vector3.one * 0.45
		p.CFrame = CFrame.new(from) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		p.Parent = Workspace
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.6, math.random() - 0.5) * 6
		local mid = from + spread
		local goal = to or (mid + Vector3.new(0, -3, 0))
		TweenService:Create(p, TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = mid }):Play()
		task.delay(duration * 0.4, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = goal,
					Size = Vector3.one * 0.15,
				}):Play()
			end
		end)
		task.delay(duration + 0.05, function()
			p:Destroy()
		end)
	end
end
CreepFx.chips = chips

local function sandBurst(pos: Vector3, zone: number, size: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	local colors = Palette.Zones[zone] or Palette.Zones[1]
	e.Color = ColorSequence.new(colors.sand, colors.sandDark)
	e.Size = NumberSequence.new(0.6 + size * 0.3, 0)
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(6, 14)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Rate = 0
	e.Parent = p
	e:Emit(14 + size * 10)
	task.delay(1.2, function()
		p:Destroy()
	end)
end

local function onHit(creepId: number, damage: number, crit: boolean, attacker: number)
	local v = views[creepId]
	if not v then
		return
	end
	v.lastHit = os.clock()
	local top = v.root.Position + Vector3.new(0, v.root.Size.Y / 2 + 0.5, 0)
	local mine = attacker == player.UserId
	if crit then
		floatText(top, Formulas.short(damage) .. "!", Theme.Color.Crit, true)
	else
		floatText(top, Formulas.short(damage), if mine then Theme.Color.Text else Theme.Color.TextDim, false)
	end
	squash(v)
	if mine then
		playSound(if crit then SOUND_CRIT else SOUND_HIT, if crit then 0.5 else 0.25, if crit then 1.4 else 1 + math.random() * 0.2, v.root)
	end
	if num(v.model, "Size") == 3 then
		local zone = math.max(1, num(v.model, "Zone"))
		chips(top, nil, 3, Palette.Zones[zone].glow, 0.6)
	end
end

local function onKill(info: any)
	local zone, size = info.zone :: number, info.size :: number
	sandBurst(info.pos, zone, size)
	if info.killer == player.UserId then
		local root = World.root()
		if root then
			chips(info.pos + Vector3.new(0, 1, 0), root.Position, math.clamp(3 + size * 2, 3, 12), Palette.Zones[zone].glow, 0.7)
		end
		floatText(info.pos + Vector3.new(0, 3, 0), "+" .. Formulas.short(info.shards), Theme.Color.Shards, true)
	end
end

function CreepFx.start()
	local folder = Workspace:WaitForChild("Creeps")
	folder.ChildAdded:Connect(function(m)
		task.defer(bind, m)
	end)
	for _, m in folder:GetChildren() do
		task.spawn(bind, m)
	end
	hitFx.OnClientEvent:Connect(onHit)
	killFx.OnClientEvent:Connect(onKill)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, v in views do
			updateView(v, t)
		end
	end)
end

return CreepFx

--!strict
-- Всё, что видно над крипом и при ударе: полоска HP с регеном, замок «до пробоя»,
-- цифры урона, сплющивание, вспышка, крит с тряской камеры, «дыхание» крипа,
-- рассыпание песком и фонтан осколков убийце.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
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
	title: TextLabel,
	lastHit: number,
	glowing: { BasePart },
	body: SpecialMesh?,
	cap: SpecialMesh?,
	phase: number,
	squashUntil: number,
	mutation: number,
}
local views: { [number]: View } = {}

local SOUND_HIT = "rbxasset://sounds/swordslash.wav"
local SOUND_CRIT = "rbxasset://sounds/electronicpingshort.wav"
local SQUASH_TIME = 0.16

local function playSound(id: string, volume: number, pitch: number, at: BasePart?)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.RollOffMaxDistance = 80
	s.Parent = at or SoundService
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end
CreepFx.playSound = playSound

local function num(model: Instance, name: string): number
	local v = model:GetAttribute(name)
	return if type(v) == "number" then v else 0
end

local function meshOf(model: Model, name: string): SpecialMesh?
	local p = model:FindFirstChild(name)
	local m = p and p:FindFirstChildOfClass("SpecialMesh")
	return m
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
	gui.Size = UDim2.fromScale(math.max(3, s.radius * 1.8), 1.3)
	gui.StudsOffset = Vector3.new(0, s.height / 2 + 1, 0)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = root
	gui.Enabled = false

	local m = Config.CreepMutations[mutation]
	local title = Theme.text("Title", gui, if m then m.name else "", 14, {
		Size = UDim2.fromScale(1, 0.38),
		TextScaled = true,
		Font = Theme.Display,
		TextColor3 = if m then Palette.Mutation[mutation] else Theme.Color.Text,
		TextStrokeTransparency = 0.3,
		Visible = m ~= nil,
	})
	local lock = Theme.text("Lock", gui, "", 14, {
		Size = UDim2.fromScale(1, 0.38),
		TextScaled = true,
		Font = Theme.Display,
		TextColor3 = Theme.Color.Crit,
		TextStrokeTransparency = 0.3,
		Visible = false,
	})
	local bar = Theme.frame("Bar", gui, {
		Size = UDim2.fromScale(1, 0.3),
		Position = UDim2.fromScale(0, 0.55),
		BackgroundColor3 = Color3.fromRGB(16, 14, 22),
		BackgroundTransparency = 0.15,
	})
	Theme.corner(bar, UDim.new(0.5, 0))
	Theme.stroke(bar, Color3.fromRGB(0, 0, 0), 1)
	local regen = Theme.frame("Regen", bar, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Good,
		BackgroundTransparency = 0,
	})
	Theme.corner(regen, UDim.new(0.5, 0))
	local fill = Theme.frame("Fill", bar, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 80, 70),
		BackgroundTransparency = 0,
	})
	Theme.corner(fill, UDim.new(0.5, 0))
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 120, 90), Color3.fromRGB(230, 50, 60))
	grad.Rotation = 90
	grad.Parent = fill
	gui.Parent = root

	local glowing = {}
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and (d.Name == "Crack" or d.Name == "Eye") then
			table.insert(glowing, d)
		end
	end

	views[id] = {
		model = model,
		root = root,
		gui = gui,
		fill = fill,
		regen = regen,
		lock = lock,
		title = title,
		lastHit = 0,
		glowing = glowing,
		body = meshOf(model, "Body"),
		cap = meshOf(model, "Cap"),
		phase = math.random() * 10,
		squashUntil = 0,
		mutation = mutation,
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
	-- Зелёная полоска — сколько крип откатит за ближайшую секунду.
	v.regen.Size = UDim2.fromScale(math.clamp(frac + Config.Creeps.RegenPerSecond, 0, 1), 1)
	v.regen.Visible = frac < 1

	local dist = World.distanceTo(v.root.Position)
	local regen = Formulas.regenPerSecond(maxHp)
	local dps = Store.dps()
	local locked = dps <= regen
	v.lock.Visible = locked
	v.title.Visible = not locked and v.mutation > 0
	if locked then
		v.lock.Text = `🔒 до пробоя {math.floor(dps / regen * 100)}%`
	end
	local inCombat = t - v.lastHit < 3
	v.gui.Enabled = inCombat or frac < 0.999 or (locked and dist < 28) or (v.mutation > 0 and dist < 45)

	-- «Дыхание» и сплющивание от удара — через масштаб мешей.
	local breathe = math.sin(t * 2.2 + v.phase) * 0.035
	local squash = 0
	if t < v.squashUntil then
		local k = 1 - (v.squashUntil - t) / SQUASH_TIME
		squash = if k > 0 then math.sin(k * math.pi) * 0.28 else 0 -- до этого — хит-стоп
	end
	if v.body then
		v.body.Scale = Vector3.new(1 + squash * 0.6, 1 + breathe - squash, 1 + squash * 0.6)
	end
	if v.cap then
		v.cap.Scale = Vector3.new(1 + squash * 0.5 - breathe * 0.5, 1 - squash * 0.7, 1 + squash * 0.5 - breathe * 0.5)
	end
	-- Трещины и глаза мерцают; Призматический переливается.
	local pulse = 0.5 + math.sin(t * 3 + v.phase) * 0.5
	for _, g in v.glowing do
		g.Transparency = 0.25 * pulse
		if v.mutation == 3 then
			g.Color = Color3.fromHSV((t * 0.3 + v.phase) % 1, 0.6, 1)
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
	anchor.Position = at + Vector3.new((math.random() - 0.5) * 2.5, 0, (math.random() - 0.5) * 2.5)
	anchor.Parent = Workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if big then 170 else 110, if big then 70 else 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	local label = Theme.text("Number", gui, text, if big then 46 else 30, {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Display,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(30, 20, 10),
	})
	local scale = Instance.new("UIScale")
	scale.Scale = if big then 1.6 else 1.25
	scale.Parent = label
	gui.Parent = anchor
	TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { Position = anchor.Position + Vector3.new(0, 4.5, 0) }):Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(0.95, function()
		anchor:Destroy()
	end)
end
CreepFx.floatText = floatText

local function flash(model: Model, color: Color3)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.FillTransparency = 0.35
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	TweenService:Create(h, TweenInfo.new(0.18), { FillTransparency = 1 }):Play()
	task.delay(0.2, function()
		h:Destroy()
	end)
end

local shakeUntil, shakePower = 0, 0
local function shake(power: number, seconds: number)
	if GuiService.ReducedMotionEnabled then
		return
	end
	shakeUntil = os.clock() + seconds
	shakePower = power
end

-- Осколки-кристаллы: вылетают фонтаном и, если задана цель, летят в неё.
local function chips(from: Vector3, to: Vector3?, count: number, color: Color3, duration: number)
	for _ = 1, count do
		local p = Models.shard(CFrame.new(from) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), color, 0.6 + math.random() * 0.5)
		p.Parent = Workspace
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.7, math.random() - 0.5) * 7
		local mid = from + spread
		TweenService:Create(p, TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(mid) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
		}):Play()
		task.delay(duration * 0.4, function()
			if p.Parent then
				local goal = to or (mid + Vector3.new(0, -3, 0))
				TweenService:Create(p, TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(goal),
					Size = p.Size * 0.3,
				}):Play()
			end
		end)
		task.delay(duration + 0.05, function()
			p:Destroy()
		end)
	end
end
CreepFx.chips = chips

local function burst(pos: Vector3, colors: { Color3 }, count: number, sizeFrom: number, speed: number)
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
	e.Color = ColorSequence.new(colors[1], colors[2] or colors[1])
	e.Size = NumberSequence.new(sizeFrom, 0)
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Drag = 2
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	task.delay(1.4, function()
		p:Destroy()
	end)
end
CreepFx.burst = burst

-- Хит-стоп: анимации своего персонажа на миг замирают — удар ощущается «весомым».
local function hitStop()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	local tracks = animator:GetPlayingAnimationTracks()
	for _, tr in tracks do
		tr:AdjustSpeed(0)
	end
	task.delay(Config.Juice.HitStop, function()
		for _, tr in tracks do
			tr:AdjustSpeed(1)
		end
	end)
end

local function onHit(creepId: number, damage: number, crit: boolean, attacker: number)
	local v = views[creepId]
	if not v then
		return
	end
	v.lastHit = os.clock()
	v.squashUntil = os.clock() + Config.Juice.HitStop + SQUASH_TIME
	local top = v.root.Position + Vector3.new(0, v.root.Size.Y / 2 + 0.5, 0)
	local mine = attacker == player.UserId
	local zone = math.max(1, num(v.model, "Zone"))
	if crit then
		floatText(top, Formulas.short(damage) .. "!", Theme.Color.Crit, true)
	else
		floatText(top, Formulas.short(damage), if mine then Color3.fromRGB(255, 255, 255) else Theme.Color.TextDim, false)
	end
	if mine then
		hitStop()
		flash(v.model, if crit then Theme.Color.Crit else Color3.new(1, 1, 1))
		playSound(if crit then SOUND_CRIT else SOUND_HIT, if crit then 0.5 else 0.22, if crit then 1.4 else 0.9 + math.random() * 0.25, v.root)
		burst(top - Vector3.new(0, 1, 0), { Palette.Zones[zone].sand, Palette.Zones[zone].glow }, if crit then 14 else 5, 0.5, 14)
		if crit then
			shake(0.25, 0.15)
		end
	end
	if num(v.model, "Size") == 3 then
		chips(top, nil, 3, Palette.Zones[zone].glow, 0.6)
	end
end

local function onKill(info: any)
	local zone, size = info.zone :: number, info.size :: number
	local colors = Palette.Zones[zone] or Palette.Zones[1]
	burst(info.pos, { colors.sand, colors.sandDark }, 16 + size * 12, 0.8 + size * 0.3, 18)
	local mutation = info.mutation :: number
	if mutation > 0 then
		-- Мутант умирает взрывом осколков своего цвета.
		burst(info.pos, { Palette.Mutation[mutation], Color3.new(1, 1, 1) }, 40 + mutation * 20, 1.2, 30)
		chips(info.pos + Vector3.new(0, 2, 0), nil, 8 + mutation * 4, Palette.Mutation[mutation], 1)
	end
	if info.killer == player.UserId then
		local root = World.root()
		if root then
			chips(info.pos + Vector3.new(0, 1, 0), root.Position, math.clamp(3 + size * 3, 3, 14), Theme.Color.Shards, Config.Juice.MagnetTime)
		end
		floatText(info.pos + Vector3.new(0, 3.5, 0), "+" .. Formulas.short(info.shards), Theme.Color.Shards, true)
		if size == 3 then
			shake(0.35, 0.2)
		end
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
		if t < shakeUntil then
			local camera = Workspace.CurrentCamera
			if camera then
				local p = shakePower * (shakeUntil - t) * 5
				camera.CFrame *= CFrame.new((math.random() - 0.5) * p, (math.random() - 0.5) * p, 0)
			end
		end
	end)
end

return CreepFx

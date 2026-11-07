--!strict
-- Всё, что видно над крипом и при ударе: полоска HP с регеном, замок «до пробоя»,
-- цифры урона, сплющивание, вспышка, крит с тряской камеры, «дыхание» крипа,
-- рассыпание песком и фонтан осколков убийце.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
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

type Scaled = { mesh: SpecialMesh, base: Vector3 }
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
	-- Меши, которые сплющиваются вместе с ножкой / шляпкой; base — их исходный масштаб.
	bodyMeshes: { Scaled },
	capMeshes: { Scaled },
	sheens: { BasePart },
	sheenColor: Color3,
	-- Глаза: зрачок и блик двигаются мешем (Offset), глаз моргает масштабом.
	pupils: { { part: BasePart, mesh: SpecialMesh } },
	eyeMeshes: { Scaled },
	gaze: Vector2, -- текущее положение зрачков, −1..1
	gazeJitter: Vector2, -- мелкий «бег» глаз, меняется рывками
	nextJitter: number,
	nextBlink: number,
	blinkAt: number,
	lastT: number,
	dist: number,
	live: boolean, -- анимируется сейчас (один из ближайших)
	pupilRange: Vector2, -- насколько далеко зрачок уходит от центра, стады
	phase: number,
	squashUntil: number,
	mutation: number,
	height: number,
	basePivot: CFrame,
	recoilStart: number,
	recoilAxis: Vector3,
	recoilAngle: number,
	predictedAt: number,
}
local views: { [number]: View } = {}
local L = Config.CreepLife

local SOUND_HIT = "rbxasset://sounds/swordslash.wav"
local SOUND_CRIT = "rbxasset://sounds/electronicpingshort.wav"
local SQUASH_TIME = 0.16

-- Пул готовых звуков: новый Sound сначала грузится и звучит с задержкой,
-- а загруженный из пула играет в тот же кадр.
local pools: { [string]: { list: { Sound }, next: number } } = {}
-- Все звуки игры — в одной группе: общая громкость в одном месте.
local sfx = Instance.new("SoundGroup")
sfx.Name = "Sfx"
sfx.Volume = Config.Juice.SfxVolume
sfx.Parent = SoundService

local function pool(id: string): { list: { Sound }, next: number }
	local existing = pools[id]
	if existing then
		return existing
	end
	local list = {}
	for i = 1, Config.Juice.SoundPool do
		local s = Instance.new("Sound")
		s.Name = "Pooled" .. i
		s.SoundId = id
		s.SoundGroup = sfx
		s.Parent = SoundService
		table.insert(list, s)
	end
	local created = { list = list, next = 1 }
	pools[id] = created
	task.spawn(function()
		ContentProvider:PreloadAsync(list)
	end)
	return created
end

-- Загрузить звуки заранее, до первого удара.
function CreepFx.preload(ids: { string })
	for _, id in ids do
		pool(id)
	end
end

local function playSound(id: string, volume: number, pitch: number, _at: BasePart?)
	local p = pool(id)
	local s = p.list[p.next]
	p.next = p.next % #p.list + 1
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.TimePosition = 0
	s:Play()
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
	-- Крипы стоят на месте и живут долго: дальние приходят по стримингу позже — ждём Root без срока.
	local root = model:FindFirstChild("Root")
	if not root then
		local conn: RBXScriptConnection
		conn = model.ChildAdded:Connect(function(child)
			if child.Name == "Root" then
				conn:Disconnect()
				task.defer(bind, model)
			end
		end)
		model.Destroying:Once(function()
			conn:Disconnect()
		end)
		return
	end
	if not root:IsA("BasePart") or not model.Parent then
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
	local bodyMeshes: { Scaled }, capMeshes: { Scaled }, eyeMeshes: { Scaled } = {}, {}, {}
	local sheens: { BasePart } = {}
	local pupils: { { part: BasePart, mesh: SpecialMesh } } = {}
	local sheenColor = Color3.new(1, 1, 1)
	for _, d in model:GetChildren() do
		if not d:IsA("BasePart") then
			continue
		end
		if d.Name == "Crack" or d.Name == "Eye" then
			table.insert(glowing, d)
		end
		if d.Name == "Sheen" or d.Name == "SheenBody" then
			table.insert(sheens, d)
			sheenColor = d.Color
		end
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		if not mesh then
			continue
		end
		local entry = { mesh = mesh, base = mesh.Scale }
		if d.Name == "Cap" or d.Name == "Sheen" or d.Name == "CapPart" then
			table.insert(capMeshes, entry)
		elseif d.Name == "Body" or d.Name == "SheenBody" or d.Name == "BodyPart" then
			table.insert(bodyMeshes, entry)
		elseif d.Name == "Pupil" or d.Name == "Glint" then
			table.insert(pupils, { part = d, mesh = mesh })
			table.insert(eyeMeshes, entry)
		elseif d.Name == "Eye" then
			table.insert(eyeMeshes, entry)
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
		bodyMeshes = bodyMeshes,
		capMeshes = capMeshes,
		sheens = sheens,
		sheenColor = sheenColor,
		pupils = pupils,
		eyeMeshes = eyeMeshes,
		gaze = Vector2.zero,
		gazeJitter = Vector2.zero,
		nextJitter = 0,
		nextBlink = os.clock() + math.random() * Config.CreepLife.BlinkMax,
		blinkAt = -math.huge,
		lastT = os.clock(),
		dist = math.huge,
		live = false,
		pupilRange = Vector2.new(s.radius * Config.CreepLife.PupilRangeX, s.radius * Config.CreepLife.PupilRangeY),
		phase = math.random() * 10,
		squashUntil = 0,
		mutation = mutation,
		height = s.height,
		basePivot = model:GetPivot(),
		recoilStart = -math.huge,
		recoilAxis = Vector3.xAxis,
		recoilAngle = math.rad(Config.Juice.RecoilAngle / math.sqrt(s.radius)),
		predictedAt = -math.huge,
	}

	-- Звук и подсказка для Золотого и реже, если игрок в той же зоне.
	if m and m.pointer then
		local myRoot = World.root()
		if myRoot and Formulas.zoneAt(myRoot.Position) == num(model, "Zone") then
			playSound(SOUND_CRIT, 0.6, 0.7, nil)
		end
	end

	local view = views[id]
	local function drop()
		if views[id] == view then
			views[id] = nil
		end
	end
	model.Destroying:Once(drop)
	-- Ушёл по стримингу — забываем; вернётся — ChildAdded папки привяжет заново.
	root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(Workspace) then
			drop()
		end
	end)
end

local function setScale(list: { Scaled }, k: Vector3)
	for _, e in list do
		e.mesh.Scale = e.base * k
	end
end

-- Полоска и надписи: пишем в интерфейс, только когда он виден.
local function updateGui(v: View, t: number)
	local hp, maxHp = num(v.model, "Hp"), math.max(num(v.model, "MaxHp"), 0.001)
	local frac = math.clamp(hp / maxHp, 0, 1)
	local regen = Formulas.regenPerSecond(maxHp)
	local dps = Store.dps()
	local locked = dps <= regen
	local inCombat = t - v.lastHit < 3
	local show = inCombat or frac < 0.999 or (locked and v.dist < 28) or (v.mutation > 0 and v.dist < 45)
	v.gui.Enabled = show
	if not show then
		return
	end
	v.fill.Size = UDim2.fromScale(frac, 1)
	-- Зелёная полоска — сколько крип откатит за ближайшую секунду.
	v.regen.Size = UDim2.fromScale(math.clamp(frac + Config.Creeps.RegenPerSecond, 0, 1), 1)
	v.regen.Visible = frac < 1
	v.lock.Visible = locked
	v.title.Visible = not locked and v.mutation > 0
	if locked then
		v.lock.Text = `🔒 до пробоя {math.floor(dps / regen * 100)}%`
	end
end

-- Возвращает крипа в покой, когда он перестал быть «живым» (ушёл из ближайших).
local function rest(v: View)
	setScale(v.bodyMeshes, Vector3.one)
	setScale(v.capMeshes, Vector3.one)
	setScale(v.eyeMeshes, Vector3.one)
	for _, p in v.pupils do
		p.mesh.Offset = Vector3.zero
	end
	for _, g in v.glowing do
		g.Transparency = 0
	end
	for _, p in v.sheens do
		p.Color = v.sheenColor
	end
end

-- Жизнь ближнего крипа: дыхание, сплющивание от удара, взгляд, моргание, мерцание.
local function animate(v: View, t: number, me: BasePart?)
	local dt = math.min(t - v.lastT, 0.1)
	v.lastT = t
	local breathe = math.sin(t * 2.2 + v.phase) * 0.035
	local squash = 0
	if t < v.squashUntil then
		local k = 1 - (v.squashUntil - t) / SQUASH_TIME
		squash = if k > 0 then math.sin(k * math.pi) * 0.28 else 0 -- до этого — хит-стоп
	end
	setScale(v.bodyMeshes, Vector3.new(1 + squash * 0.6, 1 + breathe - squash, 1 + squash * 0.6))
	setScale(v.capMeshes, Vector3.new(1 + squash * 0.5 - breathe * 0.5, 1 - squash * 0.7, 1 + squash * 0.5 - breathe * 0.5))

	-- Плёнка переливается: оттенок плавно гуляет, у Призматического — по всей радуге.
	if #v.sheens > 0 then
		local hue, sat, val = v.sheenColor:ToHSV()
		local shifted = if v.mutation == 3
			then Color3.fromHSV((t * 0.15 + v.phase) % 1, 0.55, 1)
			else Color3.fromHSV((hue + math.sin(t * 0.9 + v.phase) * Config.CreepLooks.SheenHueShift) % 1, sat, val)
		for _, p in v.sheens do
			p.Color = shifted
		end
	end

	-- Зрачки: на игрока, а без игрока — бродят. Поверх — мелкие рывки, как у живых глаз.
	local target = if me and v.dist < L.LookRange then me.Position + Vector3.new(0, 1.5, 0) else nil
	if t >= v.nextJitter then
		v.nextJitter = t + L.JitterMin + math.random() * (L.JitterMax - L.JitterMin)
		local spread = if target then L.Jitter else 0.9
		v.gazeJitter = Vector2.new((math.random() * 2 - 1) * spread, (math.random() * 2 - 1) * spread * 0.6)
	end
	local aim = Vector2.zero
	local first = v.pupils[1]
	if target and first then
		local d = first.part.CFrame:VectorToObjectSpace(target - first.part.Position)
		local flat = math.max(-d.Z, 0.001)
		aim = Vector2.new(math.clamp(d.X / flat, -1, 1), math.clamp(d.Y / flat, -1, 1))
	end
	local goal = aim + v.gazeJitter
	goal = Vector2.new(math.clamp(goal.X, -1, 1), math.clamp(goal.Y, -1, 1))
	v.gaze = v.gaze:Lerp(goal, math.min(1, dt * L.GazeSpeed))
	local offset = Vector3.new(v.gaze.X * v.pupilRange.X, v.gaze.Y * v.pupilRange.Y, 0)
	for _, p in v.pupils do
		p.mesh.Offset = offset
	end

	-- Моргание: глаз сжимается по высоте и раскрывается.
	if t >= v.nextBlink then
		v.blinkAt = t
		v.nextBlink = t + L.BlinkMin + math.random() * (L.BlinkMax - L.BlinkMin)
	end
	local bk = (t - v.blinkAt) / L.BlinkTime
	setScale(v.eyeMeshes, Vector3.new(1, if bk < 1 then 1 - math.sin(bk * math.pi) * 0.9 else 1, 1))

	-- Трещины и глаза мерцают; Призматический переливается.
	local pulse = 0.5 + math.sin(t * 3 + v.phase) * 0.5
	for _, g in v.glowing do
		g.Transparency = 0.25 * pulse
		if v.mutation == 3 then
			g.Color = Color3.fromHSV((t * 0.3 + v.phase) % 1, 0.6, 1)
		end
	end
end

-- Отшатывается от удара, качнувшись от земли: крипы стоят на месте, сервер их не двигает.
local function recoil(v: View, t: number)
	if v.recoilStart == -math.huge then
		return
	end
	local rk = (t - v.recoilStart) / Config.Juice.RecoilTime
	if rk < 1 then
		local ang = v.recoilAngle * math.sin(rk * math.pi) * (1 - rk) * 2
		local foot = v.basePivot.Position - Vector3.new(0, v.height / 2, 0)
		v.model:PivotTo(CFrame.new(foot) * CFrame.fromAxisAngle(v.recoilAxis, ang) * CFrame.new(-foot) * v.basePivot)
	else
		v.recoilStart = -math.huge
		v.model:PivotTo(v.basePivot)
	end
end

-- Каждый кадр: полоски — у всех, «жизнь» — только у нескольких ближайших,
-- остальные стоят неподвижно и ничего не тратят.
local liveList: { View } = {}
local function updateAll(t: number)
	local me = World.root()
	table.clear(liveList)
	for _, v in views do
		v.dist = World.distanceTo(v.root.Position)
		updateGui(v, t)
		recoil(v, t)
		if v.dist < L.LiveRange then
			table.insert(liveList, v)
		end
	end
	table.sort(liveList, function(a, b)
		return a.dist < b.dist
	end)
	for i = L.LiveCount + 1, #liveList do
		liveList[i] = nil
	end
	for _, v in views do
		local live = table.find(liveList, v) ~= nil
		if live then
			if not v.live then
				v.lastT = t
			end
			animate(v, t, me)
		elseif v.live then
			rest(v)
		end
		v.live = live
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

local function topOf(v: View): Vector3
	return v.basePivot.Position + Vector3.new(0, v.height / 2 + 0.5, 0)
end

-- Сплющивание и отшатывание прочь от того, кто ударил.
local function react(v: View, from: Vector3?)
	local t = os.clock()
	v.lastHit = t
	v.squashUntil = t + Config.Juice.HitStop + SQUASH_TIME
	local away = if from then (v.basePivot.Position - from) * Vector3.new(1, 0, 1) else Vector3.zero
	if away.Magnitude < 0.1 then
		away = v.basePivot.LookVector * -1
	end
	-- Ось наклона — вверх × «прочь»: верх крипа уходит от удара.
	local u = away.Unit
	v.recoilAxis = Vector3.new(u.Z, 0, -u.X)
	v.recoilStart = t
	v.blinkAt = t -- от удара жмурится
end

-- Свой удар: крип реагирует сразу (звук, вспышка, отшатывание), урон придёт с сервера.
function CreepFx.predictHit(creepId: number)
	local v = views[creepId]
	if not v then
		return
	end
	local root = World.root()
	react(v, root and root.Position)
	v.predictedAt = os.clock()
	hitStop()
	flash(v.model, Color3.new(1, 1, 1))
	playSound(SOUND_HIT, 0.25, 0.9 + math.random() * 0.25, v.root)
	local zone = math.max(1, num(v.model, "Zone"))
	burst(topOf(v) - Vector3.new(0, 1, 0), { Palette.Zones[zone].sand, Palette.Zones[zone].glow }, 5, 0.5, 14)
end

local function onHit(creepId: number, damage: number, crit: boolean, attacker: number)
	local v = views[creepId]
	if not v then
		return
	end
	local top = topOf(v)
	local mine = attacker == player.UserId
	local zone = math.max(1, num(v.model, "Zone"))
	if crit then
		floatText(top, Formulas.short(damage) .. "!", Theme.Color.Crit, true)
	else
		floatText(top, Formulas.short(damage), if mine then Color3.fromRGB(255, 255, 255) else Theme.Color.TextDim, false)
	end
	-- Реакцию на свой удар уже показали сразу; если предсказания не было — показываем сейчас.
	local predicted = mine and os.clock() - v.predictedAt < Config.Juice.PredictWindow
	if not predicted then
		local attackerPlayer = Players:GetPlayerByUserId(attacker)
		local character = attackerPlayer and attackerPlayer.Character
		local attackerRoot = character and character:FindFirstChild("HumanoidRootPart")
		react(v, if attackerRoot and attackerRoot:IsA("BasePart") then attackerRoot.Position else nil)
	end
	if mine then
		if not predicted then
			hitStop()
			playSound(SOUND_HIT, 0.25, 0.9 + math.random() * 0.25, v.root)
		end
		if crit then
			flash(v.model, Theme.Color.Crit)
			playSound(SOUND_CRIT, 0.5, 1.4, v.root)
			burst(top - Vector3.new(0, 1, 0), { Palette.Zones[zone].sand, Palette.Zones[zone].glow }, 14, 0.5, 14)
			shake(0.25, 0.15)
		elseif not predicted then
			flash(v.model, Color3.new(1, 1, 1))
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
	CreepFx.preload({ SOUND_HIT, SOUND_CRIT })
	hitFx.OnClientEvent:Connect(onHit)
	killFx.OnClientEvent:Connect(onKill)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		updateAll(t)
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

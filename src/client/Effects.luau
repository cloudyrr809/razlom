--!strict
-- События и показуха: надпись зоны со вспышкой, всплывающие сообщения, Сфера улетает в иконку,
-- звук серии убийств, луч от постамента к Монолиту и «Урон +N%», река осколков в Монолит.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Theme = require(script.Parent.Theme)
local World = require(script.Parent.World)
local CreepFx = require(script.Parent.CreepFx)
local Hud = require(script.Parent.Hud)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local notice = Remotes:WaitForChild("Notice") :: RemoteEvent
local killFx = Remotes:WaitForChild("KillFx") :: RemoteEvent
local baseFx = Remotes:WaitForChild("BaseFx") :: RemoteEvent

local Effects = {}
local player = Players.LocalPlayer
local SOUND_DING = "rbxasset://sounds/electronicpingshort.wav"
local SOUND_KILL = "rbxasset://sounds/swordslash.wav"
local SOUND_BOOM = "rbxasset://sounds/collide.wav"

local gui: ScreenGui
local toastList: Frame

-- Всплывающие сообщения -------------------------------------------------------

function Effects.toast(text: string, color: Color3?, seconds: number?)
	local item = Theme.frame("Toast", toastList, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	Theme.corner(item)
	Theme.padding(item, 10)
	if color then
		Theme.stroke(item, color, 2)
	end
	Theme.text("Text", item, text, 20, {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Theme.Display,
		TextColor3 = color or Theme.Color.Text,
	})
	task.delay(seconds or 3.5, function()
		item:Destroy()
	end)
end

local function banner(title: string, subtitle: string, color: Color3)
	-- Лёгкая вспышка по экрану и надпись справа сверху: центр не закрываем.
	local flash = Theme.frame("Flash", gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.75,
		ZIndex = 5,
	})
	Theme.tween(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 })
	local holder = Theme.frame("Banner", gui, {
		Size = UDim2.fromOffset(320, 70),
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	local t = Theme.text("Title", holder, title, 34, {
		Size = UDim2.new(1, 0, 0, 40),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Display,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = color,
		ZIndex = 6,
	})
	local s = Theme.text("Subtitle", holder, subtitle, 20, {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 42),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Display,
		TextColor3 = color,
		TextStrokeTransparency = 0.5,
		ZIndex = 6,
	})
	task.delay(2.6, function()
		Theme.tween(t, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		Theme.tween(s, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		task.wait(0.6)
		holder:Destroy()
		flash:Destroy()
	end)
end

-- Крупная надпись над Монолитом базы (видят все рядом).
local function monolithText(baseIndex: number?, text: string, color: Color3, size: number)
	local pos = World.monolith(baseIndex)
	if not pos then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = pos + Vector3.new(0, 12, 0)
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(360, 80)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Adornee = anchor
	local label = Theme.text("Text", bb, text, size, {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Display,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = Color3.fromRGB(20, 20, 40),
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	bb.Parent = anchor
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(anchor, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = anchor.Position + Vector3.new(0, 5, 0) }):Play()
	task.delay(1.3, function()
		TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(1.9, function()
		anchor:Destroy()
	end)
end

-- Луч энергии от постамента к Монолиту и вспышка Монолита.
local function beam(baseIndex: number?, slot: number?)
	local mono = World.monolith(baseIndex)
	if not mono then
		return
	end
	local from = mono + Vector3.new(8, 0, 0)
	if slot then
		local ped = World.pedestal(baseIndex, slot)
		if ped then
			from = ped.Position + Vector3.new(0, 3, 0)
		end
	end
	local to = mono + Vector3.new(0, 7, 0)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(140, 230, 255)
	p.Size = Vector3.new(0.6, 0.6, (to - from).Magnitude)
	p.CFrame = CFrame.lookAt((from + to) / 2, to)
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(0.7), { Transparency = 1, Size = Vector3.new(0.1, 0.1, p.Size.Z) }):Play()
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(180, 240, 255)
	flash.Transparency = 0.2
	flash.Size = Vector3.one * 3
	flash.Position = to
	flash.Parent = Workspace
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 14, Transparency = 1 }):Play()
	CreepFx.burst(to, { Color3.fromRGB(150, 230, 255), Color3.new(1, 1, 1) }, 30, 0.6, 18)
	task.delay(0.8, function()
		p:Destroy()
		flash:Destroy()
	end)
end

-- Река осколков от игрока в Монолит.
local function river(amount: number, baseIndex: number?)
	local root = World.root()
	local mono = World.monolith(baseIndex)
	if not root or not mono then
		return
	end
	local count = math.clamp(math.floor(math.log10(amount + 1) * 10), 6, 40)
	task.spawn(function()
		for i = 1, count do
			local from = root.Position + Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
			CreepFx.chips(from, mono + Vector3.new(0, 6, 0), 1, Theme.Color.Shards, 0.6)
			if i % 4 == 0 then
				CreepFx.playSound(SOUND_DING, 0.15, 1 + i / count, nil)
			end
			task.wait(0.03)
		end
	end)
end

-- Сфера звенит над крипом и улетает в иконку на экране.
local function sphereToIcon(from: Vector3, zone: number)
	local camera = Workspace.CurrentCamera
	local m = Models.sphere(zone, CFrame.new(from + Vector3.new(0, 2, 0)))
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanCollide = false
			p.CanQuery = false
		end
	end
	m.Parent = Workspace
	CreepFx.playSound(SOUND_DING, 0.6, 1.2, nil)
	task.spawn(function()
		local t0 = os.clock()
		local start = from + Vector3.new(0, 2, 0)
		while os.clock() - t0 < 1.1 and camera do
			local k = (os.clock() - t0) / 1.1
			local p: Vector3
			if k < 0.45 then
				p = start + Vector3.new(0, k / 0.45 * 3, 0) -- взлёт и зависание
			else
				-- Летим к иконке: точка на луче камеры через позицию иконки на экране.
				local icon = Hud.spheresIconPosition() or Vector2.new(60, 300)
				local ray = camera:ViewportPointToRay(icon.X, icon.Y + 36)
				local target = ray.Origin + ray.Direction * 6
				local f = (k - 0.45) / 0.55
				p = (start + Vector3.new(0, 3, 0)):Lerp(target, f * f)
			end
			m:PivotTo(CFrame.new(p) * CFrame.Angles(0, os.clock() * 4, 0))
			task.wait()
		end
		m:Destroy()
	end)
end

-- Сообщения сервера ------------------------------------------------------------

local function onNotice(kind: string, arg: any)
	if kind == "zone" then
		local zone = Config.Zones[arg]
		if zone then
			banner(`Зона {arg}`, zone.name, (Palette.Zones[arg] or Palette.Zones[1]).glow)
		end
	elseif kind == "zoneOpen" then
		Effects.toast(`Зона «{Config.Zones[arg].name}» открыта: потолок Кольца и Ауры вырос`, Theme.Color.Good, 5)
	elseif kind == "spheresFull" then
		Effects.toast(`Сфер {Config.Spheres.MaxStored}/{Config.Spheres.MaxStored} — открой их!`, Theme.Color.Bad)
	elseif kind == "weaponsFull" then
		Effects.toast("Инвентарь оружия полон — скорми обычные", Theme.Color.Bad)
	elseif kind == "fed" then
		Effects.toast(`Монолит получил {Formulas.short(arg)} осколков силы`, Color3.fromRGB(150, 220, 255))
	elseif kind == "newPedestal" then
		Effects.toast(`Новый ярус Монолита: постаментов теперь {arg}!`, Theme.Color.Crit, 5)
	elseif kind == "insertAtBase" then
		Effects.toast(`{arg} сильнее — вставь на базе!`, Theme.Color.Good, 4)
	elseif kind == "announce" then
		Effects.toast(tostring(arg), Palette.Mutation[4], 6)
	end
end

local function onBaseFx(kind: string, baseIndex: number?, data: any)
	local mine = data.owner == player.UserId
	if kind == "insert" then
		beam(baseIndex, nil)
		monolithText(baseIndex, `Урон +{data.percent}%`, Theme.Color.Crit, 54)
		if mine then
			CreepFx.playSound(SOUND_DING, 0.9, 0.8, nil)
		end
	elseif kind == "level" then
		monolithText(baseIndex, if data.gained > 1 then `Ур. {data.level}!  (+{data.gained})` else `Ур. {data.level}!`, Color3.fromRGB(170, 230, 255), 44)
		beam(baseIndex, nil)
		if mine then
			CreepFx.playSound(SOUND_DING, 0.8, 1.3, nil)
		end
	elseif kind == "pour" and mine then
		river(data.amount, baseIndex)
	end
end

function Effects.start()
	CreepFx.preload({ SOUND_DING, SOUND_KILL, SOUND_BOOM })
	gui = Instance.new("ScreenGui")
	gui.Name = "Effects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Сообщения — слева под Сферами, чтобы не закрывать центр и экран вскрытия.
	toastList = Theme.frame("Toasts", gui, {
		Size = UDim2.new(0, 300, 0.4, 0),
		Position = UDim2.new(0, 10, 0.3, 210),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = toastList
	gui.Parent = player:WaitForChild("PlayerGui")

	notice.OnClientEvent:Connect(onNotice)
	baseFx.OnClientEvent:Connect(onBaseFx)
	killFx.OnClientEvent:Connect(function(info: any)
		if info.killer ~= player.UserId then
			return
		end
		-- Серия: звук убийства с каждым шагом выше.
		Hud.setStreak(info.streak, info.streakMult)
		CreepFx.playSound(SOUND_KILL, 0.35, 0.9 + info.streak * 0.04, nil)
		task.delay(Config.Juice.MagnetTime, Hud.bounceShards)
		if info.mutation > 0 then
			CreepFx.playSound(SOUND_BOOM, 0.7, 0.7, nil)
			CreepFx.playSound(SOUND_DING, 0.9, 0.6 + info.mutation * 0.1, nil)
		end
		if info.sphere then
			sphereToIcon(info.pos, info.zone)
		end
	end)
end

return Effects

--!strict
-- События и показуха: надпись зоны со вспышкой, всплывающие сообщения, полёт Сферы на базу,
-- трещины и перебор цветов при вскрытии, оружие над гнездом.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
local Palette = require(ReplicatedStorage.Shared.Palette)
local Store = require(script.Parent.Store)
local Theme = require(script.Parent.Theme)
local World = require(script.Parent.World)
local CreepFx = require(script.Parent.CreepFx)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local notice = Remotes:WaitForChild("Notice") :: RemoteEvent
local killFx = Remotes:WaitForChild("KillFx") :: RemoteEvent
local revealFx = Remotes:WaitForChild("RevealFx") :: RemoteEvent

local Effects = {}
local player = Players.LocalPlayer
local SOUND_DING = "rbxasset://sounds/electronicpingshort.wav"

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
		TextColor3 = color or Theme.Color.Text,
	})
	task.delay(seconds or 3.5, function()
		item:Destroy()
	end)
end

local function banner(title: string, subtitle: string, color: Color3)
	local flash = Theme.frame("Flash", gui, {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		ZIndex = 5,
	})
	Theme.tween(flash, TweenInfo.new(0.9), { BackgroundTransparency = 1 })
	local holder = Theme.frame("Banner", gui, {
		Size = UDim2.new(0.8, 0, 0, 110),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
	})
	local t = Theme.text("Title", holder, title, 54, {
		Font = Theme.Display,
		Size = UDim2.new(1, 0, 0, 64),
		TextColor3 = Theme.Color.Text,
		TextStrokeTransparency = 0.3,
		TextStrokeColor3 = color,
		ZIndex = 6,
	})
	local s = Theme.text("Subtitle", holder, subtitle, 24, {
		Font = Theme.Display,
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 66),
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

-- Полёт Сферы ----------------------------------------------------------------

local function flySphere(from: Vector3, zone: number, baseIndex: number?)
	local base = World.base(baseIndex)
	local target = if base then base:GetPivot().Position + Vector3.new(0, 6, 0) else from + Vector3.new(0, 40, 0)
	local model = Models.sphere(zone, CFrame.new(from + Vector3.new(0, 2, 0)))
	local shell = model.PrimaryPart :: BasePart
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
		end
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.8, 0)
	a0.Parent = shell
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.8, 0)
	a1.Parent = shell
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new((Palette.Zones[zone] or Palette.Zones[1]).glow)
	trail.LightEmission = 1
	trail.Lifetime = 0.5
	trail.Parent = shell
	model.Parent = Workspace

	local up = from + Vector3.new(0, 5, 0)
	local function move(to: Vector3, seconds: number, style: Enum.EasingStyle)
		local value = Instance.new("CFrameValue")
		value.Value = model:GetPivot()
		value.Changed:Connect(function(cf)
			model:PivotTo(cf)
		end)
		local tw = TweenService:Create(value, TweenInfo.new(seconds, style, Enum.EasingDirection.InOut), { Value = CFrame.new(to) })
		tw:Play()
		tw.Completed:Wait()
		value:Destroy()
	end
	task.spawn(function()
		move(up, 0.35, Enum.EasingStyle.Quad)
		CreepFx.playSound(SOUND_DING, 0.5, 1.2, shell)
		task.wait(0.65) -- зависает над крипом
		local dist = (target - up).Magnitude
		move(target, math.clamp(dist / 120, 0.5, 2), Enum.EasingStyle.Sine)
		model:Destroy()
	end)
end

-- Вскрытие ---------------------------------------------------------------------

local function sphereAt(baseIndex: number, nestIndex: number): Model?
	local base = World.base(baseIndex)
	local nest = World.nest(baseIndex, nestIndex)
	if not base or not nest then
		return nil
	end
	local best, bestD = nil, 6
	for _, m in base:GetChildren() do
		if m:IsA("Model") and m.Name == "Sphere" then
			local d = (m:GetPivot().Position - nest.Position).Magnitude
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

-- Свет сквозь трещины перебирает цвета редкости и задерживается на редких.
local function tease(core: BasePart, hits: number, need: number)
	if hits < Config.Spheres.TeaseFromHit then
		return
	end
	local roll = math.random()
	local rarity = if roll < 0.35 then 1 elseif roll < 0.6 then 2 elseif roll < 0.8 then 3 elseif roll < 0.93 then 4 else 5
	core.Color = Palette.Rarity[rarity]
	core.Transparency = 0.2
	local light = core:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = core.Color
		light.Brightness = 0.6 + rarity * 0.5 + hits / need
	end
	if rarity >= 4 then
		CreepFx.playSound(SOUND_DING, 0.3, 0.8 + rarity * 0.1, core)
	end
end

local function addCrack(model: Model, hits: number, need: number)
	local shell = model:FindFirstChild("Shell")
	local core = model:FindFirstChild("Core")
	if not shell or not shell:IsA("BasePart") or not core or not core:IsA("BasePart") then
		return
	end
	local angle = math.rad(hits * 47)
	local crack = Instance.new("Part")
	crack.Name = "CrackFx"
	crack.Anchored = true
	crack.CanCollide = false
	crack.CanQuery = false
	crack.Material = Enum.Material.Neon
	local warm = Color3.fromRGB(255, 190, 80)
	crack.Color = if hits < Config.Spheres.TeaseFromHit then warm else core.Color
	crack.Size = Vector3.new(0.16, 1.3 + hits / need, 0.16)
	crack.CFrame = shell.CFrame * CFrame.Angles(0, angle, math.rad(hits * 23)) * CFrame.new(0, 0, -1.45)
	crack.Parent = model
	-- Толчок от удара.
	local base = shell.CFrame
	shell.CFrame = base * CFrame.new((math.random() - 0.5) * 0.3, 0, (math.random() - 0.5) * 0.3)
	task.delay(0.06, function()
		if shell.Parent then
			shell.CFrame = base
		end
	end)
	tease(core, hits, need)
	for _, c in model:GetChildren() do
		if c.Name == "CrackFx" and c:IsA("BasePart") and hits >= Config.Spheres.TeaseFromHit then
			c.Color = core.Color
		end
	end
end

local function showWeapon(baseIndex: number, nestIndex: number, weapon: Formulas.Weapon)
	local nest = World.nest(baseIndex, nestIndex)
	if not nest then
		return
	end
	local handle = Models.weaponHandle(weapon.zone, weapon.rarity, weapon.mutation)
	local parts: { BasePart } = { handle }
	for _, d in handle:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local holder = Instance.new("Model")
	holder.Name = "RevealedWeapon"
	handle.Parent = holder
	for _, p in parts do
		p.Anchored = false
		p.CanCollide = false
	end
	handle.Anchored = true
	local start = nest.Position + Vector3.new(0, 2.5, 0)
	handle.CFrame = CFrame.new(start)
	holder.Parent = Workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 60)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	local color = if weapon.mutation > 0 then Palette.Mutation[weapon.mutation] else Palette.Rarity[weapon.rarity]
	Theme.text("Name", bb, Formulas.weaponName(weapon), 28, {
		Size = UDim2.fromScale(1, 0.6),
		TextColor3 = color,
		TextStrokeTransparency = 0.2,
	})
	Theme.text("Rarity", bb, Config.Rarities[weapon.rarity].name .. " · урон " .. Formulas.short(Formulas.weaponDamage(weapon)), 18, {
		Size = UDim2.fromScale(1, 0.4),
		Position = UDim2.fromScale(0, 0.6),
		TextColor3 = Palette.Rarity[weapon.rarity],
		TextStrokeTransparency = 0.3,
	})
	bb.Parent = handle

	CreepFx.chips(start, nil, 10, color, 0.8)
	CreepFx.playSound(SOUND_DING, 0.7, 0.9, handle)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 3 and handle.Parent do
			local t = os.clock() - t0
			handle.CFrame = CFrame.new(start + Vector3.new(0, math.min(t * 3, 3), 0)) * CFrame.Angles(0, t * 3, 0)
			task.wait()
		end
		holder:Destroy()
	end)
end

-- Сфера раскалывается на две половинки, внутри — друза кристаллов цвета выпавшего.
local function splitSphere(baseIndex: number, nestIndex: number, weapon: Formulas.Weapon)
	local nest = World.nest(baseIndex, nestIndex)
	if not nest then
		return
	end
	local center = nest.Position + Vector3.new(0, 2.4, 0)
	local inner = if weapon.mutation > 0 then Palette.Mutation[weapon.mutation] else Palette.Rarity[weapon.rarity]
	local stone = Color3.fromRGB(196, 140, 92)
	local parts: { BasePart } = {}
	for side = -1, 1, 2 do
		local half = Instance.new("Part")
		half.Name = "SphereHalf"
		half.Anchored = true
		half.CanCollide = false
		half.CanQuery = false
		half.Material = Enum.Material.Sandstone
		half.Color = stone
		half.Size = Vector3.new(1.5, 3, 3)
		half.CFrame = CFrame.new(center + Vector3.new(side * 0.75, 0, 0))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = half
		half.Parent = Workspace
		-- Внутренняя «друза»: светящийся срез.
		local cut = Instance.new("Part")
		cut.Anchored = true
		cut.CanCollide = false
		cut.CanQuery = false
		cut.Material = Enum.Material.Neon
		cut.Color = inner
		cut.Size = Vector3.new(0.2, 2.4, 2.4)
		cut.CFrame = half.CFrame * CFrame.new(-side * 0.7, 0, 0)
		local cutMesh = Instance.new("SpecialMesh")
		cutMesh.MeshType = Enum.MeshType.Sphere
		cutMesh.Parent = cut
		cut.Parent = Workspace
		table.insert(parts, half)
		table.insert(parts, cut)
		local out = CFrame.new(center + Vector3.new(side * 2.4, -0.8, 0)) * CFrame.Angles(0, 0, math.rad(side * 35))
		TweenService:Create(half, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = out }):Play()
		TweenService:Create(cut, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			CFrame = out * CFrame.new(-side * 0.7, 0, 0),
		}):Play()
	end
	CreepFx.burst(center, { inner, Color3.new(1, 1, 1) }, 40, 0.7, 20)
	task.delay(3, function()
		for _, p in parts do
			TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
		task.wait(0.7)
		for _, p in parts do
			p:Destroy()
		end
	end)
end

local function onReveal(kind: string, baseIndex: number, nestIndex: number, data: any)
	local mine = data.owner == player.UserId or (kind == "crack" and baseIndex == Store.data.baseIndex)
	if kind == "start" then
		if mine then
			Store.reveals[nestIndex] = { hits = 0, need = data.need }
			Store.emit("reveals")
		end
	elseif kind == "crack" then
		if mine and Store.reveals[nestIndex] then
			Store.reveals[nestIndex].hits = data.hits
			Store.emit("reveals")
		end
		local model = sphereAt(baseIndex, nestIndex)
		if model then
			addCrack(model, data.hits, data.need)
		end
	elseif kind == "done" then
		if mine then
			Store.reveals[nestIndex] = nil
			Store.emit("reveals")
			local w = data.weapon :: Formulas.Weapon
			local r = Config.Rarities[w.rarity]
			Effects.toast(`Выпало: {Formulas.weaponName(w)} · {r.name}`, if w.mutation > 0 then Palette.Mutation[w.mutation] else Palette.Rarity[w.rarity], 4)
		end
		splitSphere(baseIndex, nestIndex, data.weapon)
		showWeapon(baseIndex, nestIndex, data.weapon)
	end
end

-- Сообщения сервера ------------------------------------------------------------

local function onNotice(kind: string, arg: any)
	if kind == "zone" then
		local zone = Config.Zones[arg]
		if zone then
			banner(`Зона {arg}`, zone.name, (Palette.Zones[arg] or Palette.Zones[1]).glow)
		end
	elseif kind == "zoneOpen" then
		local zone = Config.Zones[arg]
		Effects.toast(`Зона «{zone.name}» открыта: потолок Кольца и Ауры вырос`, Theme.Color.Good, 5)
	elseif kind == "storageFull" then
		Effects.toast("Склад полон — Сфера ждёт на земле у базы", Theme.Color.Bad)
	elseif kind == "announce" then
		Effects.toast(tostring(arg), Palette.Mutation[4], 6)
	end
end

function Effects.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Effects"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	toastList = Theme.frame("Toasts", gui, {
		Size = UDim2.new(0, 340, 0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 120),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
	})
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = toastList
	gui.Parent = player:WaitForChild("PlayerGui")

	notice.OnClientEvent:Connect(onNotice)
	revealFx.OnClientEvent:Connect(onReveal)
	killFx.OnClientEvent:Connect(function(info: any)
		if info.sphere then
			flySphere(info.pos, info.zone, info.base)
		end
	end)
end

return Effects

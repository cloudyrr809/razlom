--!strict
-- Монолит: уровень (+2% урона за уровень), ярусы каждые 10 уровней (+1 постамент).
-- Прогресс идёт в осколках: вливание, скармливание оружия, а в Шаге 2 — ковка в АФК.
-- Все источники прогресса зовут одну функцию Monolith.addProgress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Shared.Formulas)
local PlayerState = require(script.Parent.PlayerState)
local Bases = require(script.Parent.Bases)
local RateLimit = require(script.Parent.RateLimit)

local Remotes = ReplicatedStorage.Remotes
local monolithRemote = Remotes.Monolith :: RemoteEvent
local baseFx = Remotes.BaseFx :: RemoteEvent

local Monolith = {}
local limiter = RateLimit.new()
local levelListeners: { (PlayerState.Session, number) -> () } = {}

-- Подписка «у игрока вырос уровень Монолита» (постаменты добавляются тут).
function Monolith.onLevel(fn: (PlayerState.Session, number) -> ())
	table.insert(levelListeners, fn)
end

-- Ярусы и табличка над Монолитом — видно всем.
local function redraw(session: PlayerState.Session)
	local info = Bases.of(session)
	if not info then
		return
	end
	local mono = info.monolith
	local center = mono:GetPivot().Position
	local old = info.model:FindFirstChild("MonolithTiers")
	if old then
		old:Destroy()
	end
	local tiers = Instance.new("Folder")
	tiers.Name = "MonolithTiers"
	local tier = Formulas.tier(session.monolithLevel)
	for t = 2, tier do
		-- Каждый ярус — кольцо из кристаллов чуть выше и шире предыдущего.
		for k = 0, 3 do
			local a = math.rad(k * 90 + t * 22)
			local p = Instance.new("Part")
			p.Name = "TierCrystal"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.Material = Enum.Material.Glass
			p.Color = Color3.fromRGB(170, 225, 255)
			p.Transparency = 0.15
			p.Size = Vector3.new(1, 2.5 + t * 0.4, 1)
			p.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * (2.6 + t * 0.25), 0.8 + t * 1.6, math.sin(a) * (2.6 + t * 0.25)))
				* CFrame.Angles(math.sin(a) * 0.35, 0, -math.cos(a) * 0.35)
			p.Parent = tiers
		end
	end
	tiers.Parent = info.model

	local gui = mono:FindFirstChild("LevelGui")
	if not gui then
		local bb = Instance.new("BillboardGui")
		bb.Name = "LevelGui"
		bb.Size = UDim2.fromOffset(200, 50)
		bb.StudsOffset = Vector3.new(0, 16, 0)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Name = "Label"
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.TextColor3 = Color3.fromRGB(190, 235, 255)
		t.TextStrokeTransparency = 0.3
		t.Parent = bb
		bb.Parent = mono
		gui = bb
	end
	local label = (gui :: Instance):FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = `Монолит · ур. {session.monolithLevel}`
	end
end

-- Добавляет прогресс (в осколках) и поднимает уровни, пока хватает. Возвращает число новых уровней.
function Monolith.addProgress(session: PlayerState.Session, amount: number): number
	if amount <= 0 or amount ~= amount then
		return 0
	end
	session.monolithProgress += amount
	local gained = 0
	while session.monolithProgress >= Formulas.monolithCost(session.monolithLevel) do
		session.monolithProgress -= Formulas.monolithCost(session.monolithLevel)
		session.monolithLevel += 1
		gained += 1
	end
	PlayerState.markDirty(session, "monolith")
	if gained > 0 then
		redraw(session)
		for _, fn in levelListeners do
			fn(session, gained)
		end
		baseFx:FireAllClients("level", session.baseIndex, { level = session.monolithLevel, gained = gained, owner = session.player.UserId })
	end
	return gained
end

-- «Влить всё»: все осколки уходят в Монолит. Только у своего Монолита.
local function onRemote(player: Player, action: unknown)
	local session = PlayerState.get(player)
	if not session or action ~= "pour" or not limiter.consume(player, 2, 2) then
		return
	end
	if not Bases.nearMonolith(session) then
		return
	end
	local amount = session.wallet.shards
	if amount <= 0 then
		return
	end
	session.wallet.shards = 0
	PlayerState.markDirty(session, "wallet")
	baseFx:FireAllClients("pour", session.baseIndex, { amount = amount, owner = player.UserId })
	Monolith.addProgress(session, amount)
end

function Monolith.start()
	monolithRemote.OnServerEvent:Connect(onRemote)
	PlayerState.onAdded(function(session)
		task.defer(redraw, session)
	end)
	PlayerState.onRemoving(function(session)
		limiter.forget(session.player)
		local info = Bases.of(session)
		if info then
			local old = info.model:FindFirstChild("MonolithTiers")
			if old then
				old:Destroy()
			end
			local gui = info.monolith:FindFirstChild("LevelGui")
			if gui then
				gui:Destroy()
			end
		end
	end)
end

return Monolith

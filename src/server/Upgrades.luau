--!strict
-- Станция улучшений: Кольцо (скорость атаки) и Аура (скорость бега).
-- Клиент шлёт только «купить Кольцо» / «купить Ауру» и «+1» или «Макс». Цену считает сервер.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EconomyMath = require(ReplicatedStorage.Shared.EconomyMath)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local PlayerState = require(script.Parent.PlayerState)
local Bases = require(script.Parent.Bases)
local RateLimit = require(script.Parent.RateLimit)

local buyRemote = ReplicatedStorage.Remotes.BuyUpgrade :: RemoteEvent

local Upgrades = {}
local limiter = RateLimit.new()

local function applyStats(session: PlayerState.Session)
	local player = session.player
	player:SetAttribute("RingLevel", session.ring)
	player:SetAttribute("AuraLevel", session.aura)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Formulas.walkSpeed(session.aura)
	end
end

local function nearStation(session: PlayerState.Session): boolean
	local info = Bases.of(session)
	local character = session.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not info or not root or not root:IsA("BasePart") then
		return false
	end
	local p = info.station:GetPivot().Position
	local d = root.Position - p
	return Vector3.new(d.X, 0, d.Z).Magnitude <= Config.Base.StationRange and math.abs(d.Y) <= 10
end

local function onBuy(player: Player, id: unknown, buyMax: unknown)
	local session = PlayerState.get(player)
	if not session or (id ~= "Ring" and id ~= "Aura") or type(buyMax) ~= "boolean" then
		return
	end
	if not limiter.consume(player, 8, 8) or not nearStation(session) then
		return
	end
	local upgradeId: Formulas.UpgradeId = if id == "Ring" then "Ring" else "Aura"
	local owned = if upgradeId == "Ring" then session.ring else session.aura
	local cap = Formulas.upgradeCap(upgradeId, session.openZones)
	if owned >= cap then
		return
	end

	local count, price
	if buyMax then
		count, price = Formulas.upgradeMax(upgradeId, owned, session.wallet.shards, session.openZones)
	else
		count, price = 1, Formulas.upgradeCost(upgradeId, owned)
	end
	if count < 1 or not EconomyMath.trySpend(session.wallet, { shards = price }) then
		return
	end
	if upgradeId == "Ring" then
		session.ring += count
	else
		session.aura += count
	end
	PlayerState.markDirty(session, "wallet")
	PlayerState.markDirty(session, "levels")
	applyStats(session)
end

function Upgrades.start()
	buyRemote.OnServerEvent:Connect(onBuy)
	PlayerState.onAdded(function(session)
		applyStats(session)
		session.player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			applyStats(session)
		end)
	end)
	PlayerState.onRemoving(function(session)
		limiter.forget(session.player)
	end)
end

return Upgrades

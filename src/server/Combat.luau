--!strict
-- Удар. Клиент шлёт только «хочу ударить». Сервер сам выбирает цель,
-- проверяет расстояние и лимит ударов Кольца, считает урон, криты, серию и награды.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local PlayerState = require(script.Parent.PlayerState)
local Creeps = require(script.Parent.Creeps)
local Spheres = require(script.Parent.Spheres)
local Arsenal = require(script.Parent.Arsenal)
local RateLimit = require(script.Parent.RateLimit)

local Remotes = ReplicatedStorage.Remotes
local hitRemote = Remotes.Hit :: RemoteEvent
local hitFx = Remotes.HitFx :: UnreliableRemoteEvent
local killFx = Remotes.KillFx :: RemoteEvent
local notice = Remotes.Notice :: RemoteEvent

local Combat = {}
local rng = Random.new()
local limiter = RateLimit.new()

-- Урон одного удара игрока без крита.
function Combat.hitDamage(session: PlayerState.Session): number
	return Formulas.hitDamage(Arsenal.damage(session), session.monolithLevel, 0)
end

local function reward(session: PlayerState.Session, creep: Creeps.Creep, pos: Vector3)
	-- Серия: убийство быстрее окна после прошлого — +1 ступень, иначе с нуля.
	local now = os.clock()
	if now - session.lastKill < Config.Streak.Window then
		session.streak = math.min(session.streak + 1, Config.Streak.MaxSteps)
	else
		session.streak = 0
	end
	session.lastKill = now
	local mult = Formulas.streakMult(session.streak)
	local shards = math.floor(Formulas.creepShards(creep.zone, creep.size, creep.mutation) * mult + 0.5)
	session.wallet.shards += shards
	PlayerState.markDirty(session, "wallet")

	if PlayerState.addZoneKill(session, creep.zone) then
		notice:FireClient(session.player, "zoneOpen", creep.zone)
	end

	local guaranteed = creep.size == 3 and session.firstLargeSphere
	local dropped = (guaranteed or rng:NextNumber() < Formulas.sphereChance(creep.zone, creep.size, creep.mutation))
		and Spheres.give(session, creep.zone, creep.mutation)
	if dropped and creep.size == 3 then
		session.firstLargeSphere = false
	end

	killFx:FireAllClients({
		id = creep.id,
		pos = pos,
		zone = creep.zone,
		size = creep.size,
		mutation = creep.mutation,
		killer = session.player.UserId,
		shards = shards,
		sphere = dropped,
		streak = session.streak,
		streakMult = mult,
	})
end

local function onHit(player: Player)
	local session = PlayerState.get(player)
	if not session then
		return
	end
	-- Лимит Кольца: не больше N ударов в секунду, лишние отбрасываются.
	if not limiter.consume(player, Formulas.hitsPerSecond(session.ring), Config.Combat.HitBurst) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return
	end
	local pos = root.Position
	local creep = Creeps.nearest(pos, Config.Combat.HitRadius)
	if not creep then
		return
	end

	local crit = rng:NextNumber() < Config.Combat.CritChance
	local damage = Combat.hitDamage(session) * (if crit then Config.Combat.CritMult else 1)
	local creepPos = creep.root.Position
	local killed = Creeps.damage(creep, damage, pos)
	hitFx:FireAllClients(creep.id, damage, crit, player.UserId)
	if killed then
		reward(session, creep, creepPos)
	end
end

function Combat.start()
	hitRemote.OnServerEvent:Connect(onHit)
	PlayerState.onRemoving(function(session)
		limiter.forget(session.player)
	end)
end

return Combat

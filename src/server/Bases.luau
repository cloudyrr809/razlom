--!strict
-- 8 баз. Выдаёт свободную при входе, освобождает при выходе, ставит игрока на базу.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerState = require(script.Parent.PlayerState)

export type BaseInfo = {
	index: number,
	model: Model,
	spawn: BasePart,
	monolith: Model,
	pedestals: { BasePart }, -- все 10 мест; работают первые pedestalCount
	owner: Player?,
}

local Bases = {}
local list: { BaseInfo } = {}

function Bases.get(index: number?): BaseInfo?
	if not index then
		return nil
	end
	return list[index]
end

function Bases.of(session: PlayerState.Session): BaseInfo?
	return Bases.get(session.baseIndex)
end

-- Стоит ли игрок у своего Монолита (вставлять оружие и вливать осколки можно только тут).
function Bases.nearMonolith(session: PlayerState.Session): boolean
	local info = Bases.of(session)
	local character = session.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not info or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local d = root.Position - info.monolith:GetPivot().Position
	return Vector3.new(d.X, 0, d.Z).Magnitude <= Config.Monolith.Range and math.abs(d.Y) <= 15
end

local function setSign(info: BaseInfo)
	local sign = info.model:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("OwnerGui")
	local label = gui and gui:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = if info.owner then "База " .. info.owner.DisplayName else "Свободная база"
	end
	info.model:SetAttribute("OwnerId", if info.owner then info.owner.UserId else nil)
end

local function placeOnBase(player: Player, character: Model)
	local session = PlayerState.get(player)
	local info = session and Bases.of(session)
	if not info then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or player.Character ~= character then
		return
	end
	character:PivotTo(info.spawn.CFrame)
end

function Bases.start()
	for _, model in CollectionService:GetTagged("Base") do
		local index = model:GetAttribute("Index")
		if not model:IsA("Model") or type(index) ~= "number" then
			warn("Base без Index:", model:GetFullName())
			continue
		end
		local pedestals: { BasePart } = {}
		for _, p in CollectionService:GetTagged("Pedestal") do
			if p:IsA("BasePart") and p:GetAttribute("Base") == index then
				local k = p:GetAttribute("Index")
				if type(k) == "number" then
					pedestals[k] = p
				end
			end
		end
		local spawn = model:FindFirstChild("SpawnPoint")
		local monolith = model:FindFirstChild("Monolith")
		if not (spawn and spawn:IsA("BasePart") and monolith and monolith:IsA("Model")) or #pedestals ~= Config.Monolith.MaxPedestals then
			warn("База собрана не полностью:", model:GetFullName())
			continue
		end
		list[index] = { index = index, model = model, spawn = spawn, monolith = monolith, pedestals = pedestals, owner = nil }
	end
	if #list ~= Config.Base.Count then
		warn(`Найдено баз: {#list} из {Config.Base.Count}. Запусти tools/build_map.luau.`)
	end

	PlayerState.onAdded(function(session)
		for _, info in list do
			if not info.owner then
				info.owner = session.player
				session.baseIndex = info.index
				PlayerState.markDirty(session, "base")
				setSign(info)
				break
			end
		end
		if not session.baseIndex then
			warn("Нет свободной базы для", session.player.Name)
		end
		local player = session.player
		player.CharacterAdded:Connect(function(character)
			placeOnBase(player, character)
		end)
		if player.Character then
			task.spawn(placeOnBase, player, player.Character)
		end
	end)

	PlayerState.onRemoving(function(session)
		local info = Bases.of(session)
		if info and info.owner == session.player then
			info.owner = nil
			setSign(info)
		end
	end)
end

return Bases

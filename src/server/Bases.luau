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
	overflow: BasePart,
	nests: { BasePart },
	station: Model,
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
		local nests: { BasePart } = {}
		for _, nest in CollectionService:GetTagged("Nest") do
			if nest:IsA("BasePart") and nest:GetAttribute("Base") == index then
				local k = nest:GetAttribute("Index")
				if type(k) == "number" then
					nests[k] = nest
				end
			end
		end
		local station: Model? = nil
		for _, s in CollectionService:GetTagged("Station") do
			if s:IsA("Model") and s:GetAttribute("Base") == index then
				station = s
			end
		end
		local spawn = model:FindFirstChild("SpawnPoint")
		local overflow = model:FindFirstChild("Overflow")
		if not (station and spawn and spawn:IsA("BasePart") and overflow and overflow:IsA("BasePart")) or #nests ~= 3 then
			warn("База собрана не полностью:", model:GetFullName())
			continue
		end
		list[index] = {
			index = index,
			model = model,
			spawn = spawn,
			overflow = overflow,
			nests = nests,
			station = station,
			owner = nil,
		}
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

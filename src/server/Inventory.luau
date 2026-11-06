--!strict
-- Оружие игрока: список, «Надеть», «Надеть лучшее», заглушка в руке.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
local PlayerState = require(script.Parent.PlayerState)
local RateLimit = require(script.Parent.RateLimit)

local equipRemote = ReplicatedStorage.Remotes.Equip :: RemoteEvent

local Inventory = {}
local limiter = RateLimit.new()

local function giveTool(session: PlayerState.Session)
	local character = session.player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local holders: { Instance? } = { character, session.player:FindFirstChildOfClass("Backpack") }
	for _, holder in holders do
		if holder then
			for _, child in holder:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("IsWeapon") then
					child:Destroy()
				end
			end
		end
	end
	local w = PlayerState.equippedWeapon(session)
	local tool = Instance.new("Tool")
	tool.Name = Formulas.weaponName(w)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsWeapon", true)
	local handle = Models.weaponHandle(w.zone, w.rarity, w.mutation)
	handle.Parent = tool
	-- Держим за низ рукояти.
	tool.GripPos = Vector3.new(0, -(handle.Size.Y / 2 - 0.5), 0)
	tool.Parent = character
end

function Inventory.equip(session: PlayerState.Session, id: string)
	for _, w in session.weapons do
		if w.id == id then
			session.equipped = id
			PlayerState.markDirty(session, "inventory")
			giveTool(session)
			return
		end
	end
end

function Inventory.best(session: PlayerState.Session): Formulas.Weapon
	local best = session.weapons[1]
	for _, w in session.weapons do
		if Formulas.weaponDamage(w) > Formulas.weaponDamage(best) then
			best = w
		end
	end
	return best
end

-- Добавляет оружие. Если оно сильнее того, что в руке, — сразу надевает.
function Inventory.add(session: PlayerState.Session, w: Formulas.Weapon)
	if #session.weapons >= Config.Spheres.MaxWeapons then
		-- Предохранитель: выбрасываем самое слабое немутированное, кроме того, что в руке.
		local weakest: number? = nil
		for i, x in session.weapons do
			if x.id ~= session.equipped and x.mutation == 0 then
				if not weakest or Formulas.weaponDamage(x) < Formulas.weaponDamage(session.weapons[weakest]) then
					weakest = i
				end
			end
		end
		if weakest then
			table.remove(session.weapons, weakest)
		end
	end
	table.insert(session.weapons, w)
	PlayerState.markDirty(session, "inventory")
	if Formulas.weaponDamage(w) > Formulas.weaponDamage(PlayerState.equippedWeapon(session)) then
		Inventory.equip(session, w.id)
	end
end

function Inventory.start()
	PlayerState.onAdded(function(session)
		session.player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			if session.player.Character == character then
				giveTool(session)
			end
		end)
		if session.player.Character then
			task.spawn(giveTool, session)
		end
	end)
	PlayerState.onRemoving(function(session)
		limiter.forget(session.player)
	end)

	equipRemote.OnServerEvent:Connect(function(player: Player, id: unknown)
		local session = PlayerState.get(player)
		if not session or type(id) ~= "string" or #id > 24 then
			return
		end
		if not limiter.consume(player, 4, 4) then
			return
		end
		if id == "best" then
			Inventory.equip(session, Inventory.best(session).id)
		else
			Inventory.equip(session, id)
		end
	end)
end

return Inventory

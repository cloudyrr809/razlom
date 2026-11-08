--!strict
-- Арсенал: всё оружие игрока, постаменты на базе, оружие в руке, скармливание Монолиту.
-- Урон удара = сумма урона оружия в постаментах (дальше бонусы Монолита — см. Formulas.hitDamage).
-- Вставлять и менять оружие в постаментах можно только у своего Монолита.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Formulas = require(ReplicatedStorage.Shared.Formulas)
local Models = require(ReplicatedStorage.Shared.Models)
local Palette = require(ReplicatedStorage.Shared.Palette)
local PlayerState = require(script.Parent.PlayerState)
local Bases = require(script.Parent.Bases)
local Monolith = require(script.Parent.Monolith)
local RateLimit = require(script.Parent.RateLimit)

local Remotes = ReplicatedStorage.Remotes
local pedestalRemote = Remotes.Pedestal :: RemoteEvent
local equipRemote = Remotes.Equip :: RemoteEvent
local feedRemote = Remotes.Feed :: RemoteEvent
local baseFx = Remotes.BaseFx :: RemoteEvent
local notice = Remotes.Notice :: RemoteEvent

local Arsenal = {}
local limiter = RateLimit.new()

local function dmgOf(session: PlayerState.Session, id: string): number
	if id == "" then
		return 0
	end
	local w = PlayerState.weapon(session, id)
	return if w then Formulas.weaponDamage(w) else 0
end

-- Сумма урона оружия в постаментах.
function Arsenal.damage(session: PlayerState.Session): number
	local sum = 0
	for _, id in session.pedestals do
		sum += dmgOf(session, id)
	end
	return sum
end

-- Урон самого слабого в постаментах; 0, если есть пустой постамент.
function Arsenal.weakest(session: PlayerState.Session): number
	local weakest = math.huge
	for _, id in session.pedestals do
		if id == "" then
			return 0
		end
		weakest = math.min(weakest, dmgOf(session, id))
	end
	return if weakest == math.huge then 0 else weakest
end

local function inPedestal(session: PlayerState.Session, id: string): number?
	return table.find(session.pedestals, id)
end

-- Насколько вырос бы арсенал, если вставить это оружие вместо самого слабого.
function Arsenal.gainOf(session: PlayerState.Session, w: Formulas.Weapon): number
	return math.max(0, Formulas.weaponDamage(w) - Arsenal.weakest(session))
end

function Arsenal.isFull(session: PlayerState.Session): boolean
	return #session.weapons >= Config.Weapons.MaxInventory
end

-- Оружие в руке: только вид удара. Ставим инструмент-заглушку.
local function giveTool(session: PlayerState.Session)
	local character = session.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
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
	local w = PlayerState.weapon(session, session.hand) or session.weapons[1]
	local tool = Instance.new("Tool")
	tool.Name = Formulas.weaponName(w)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("IsWeapon", true)
	local handle = Models.weaponHandle(w.zone, w.rarity, w.mutation)
	handle.Parent = tool
	tool.GripPos = Vector3.new(0, -(handle.Size.Y / 2 - 0.5), 0)
	tool.Parent = character
end

-- Если оружия в руке нет в постаментах — берём сильнейшее из вставленных.
local function fixHand(session: PlayerState.Session)
	if inPedestal(session, session.hand) then
		return
	end
	local best, bestD = session.hand, -1
	for _, id in session.pedestals do
		local d = dmgOf(session, id)
		if id ~= "" and d > bestD then
			best, bestD = id, d
		end
	end
	if best ~= session.hand then
		session.hand = best
		giveTool(session)
	end
end

-- Клинки, парящие над постаментами (видно всем).
local function redraw(session: PlayerState.Session)
	local info = Bases.of(session)
	if not info then
		return
	end
	local old = info.model:FindFirstChild("PedestalWeapons")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PedestalWeapons"
	local count = #session.pedestals
	for k, part in info.pedestals do
		local active = k <= count
		part.Transparency = if active then 0 else 0.7
		local top = part:FindFirstChild("Top")
		local w = if active then PlayerState.weapon(session, session.pedestals[k] or "") else nil
		if top and top:IsA("BasePart") then
			top.Transparency = if active then 0.2 else 0.85
			top.Color = if w then (if w.mutation > 0 then Palette.Mutation[w.mutation] else Palette.Rarity[w.rarity]) else Color3.fromRGB(110, 140, 170)
		end
		if w then
			local handle = Models.weaponHandle(w.zone, w.rarity, w.mutation)
			handle.Anchored = true
			handle.CFrame = CFrame.new(part.Position + Vector3.new(0, part.Size.Y / 2 + 2.6, 0)) * CFrame.Angles(0, math.rad(k * 36), math.rad(12))
			handle.Name = "Weapon" .. k
			handle.Parent = folder
		end
	end
	folder.Parent = info.model
end

local function changed(session: PlayerState.Session, before: number)
	fixHand(session)
	redraw(session)
	PlayerState.markDirty(session, "arsenal")
	local after = Arsenal.damage(session)
	if after > before then
		local percent = if before > 0 then math.floor((after - before) / before * 100 + 0.5) else 100
		baseFx:FireAllClients("insert", session.baseIndex, { percent = percent, owner = session.player.UserId, arsenal = after })
	end
end

-- Добавляет оружие в инвентарь (не в постамент — вставлять надо на базе).
function Arsenal.add(session: PlayerState.Session, w: Formulas.Weapon)
	table.insert(session.weapons, w)
	PlayerState.markDirty(session, "arsenal")
	if Arsenal.gainOf(session, w) > 0 then
		notice:FireClient(session.player, "insertAtBase", Formulas.weaponName(w))
	end
end

-- «Экипировать лучшее»: сильнейшее оружие во все постаменты.
local function equipBest(session: PlayerState.Session)
	local before = Arsenal.damage(session)
	local sorted = table.clone(session.weapons)
	table.sort(sorted, function(a, b)
		return Formulas.weaponDamage(a) > Formulas.weaponDamage(b)
	end)
	for k = 1, #session.pedestals do
		session.pedestals[k] = if sorted[k] then sorted[k].id else ""
	end
	changed(session, before)
end

local function insert(session: PlayerState.Session, slot: number, id: string)
	if not PlayerState.weapon(session, id) then
		return
	end
	local before = Arsenal.damage(session)
	local from = inPedestal(session, id)
	if from then
		session.pedestals[from] = session.pedestals[slot] -- поменять местами
	end
	session.pedestals[slot] = id
	changed(session, before)
end

local function feed(session: PlayerState.Session, ids: { string }): number
	local total = 0
	for _, id in ids do
		if id ~= "starter" and not inPedestal(session, id) then
			for i, w in session.weapons do
				if w.id == id then
					total += Formulas.feedValue(w)
					table.remove(session.weapons, i)
					break
				end
			end
		end
	end
	if total > 0 then
		PlayerState.markDirty(session, "arsenal")
		Monolith.addProgress(session, total)
	end
	return total
end

local function validSlot(session: PlayerState.Session, v: unknown): number?
	if type(v) == "number" and v == math.floor(v) and v >= 1 and v <= #session.pedestals then
		return v
	end
	return nil
end

function Arsenal.start()
	-- Ярус Монолита — новые пустые постаменты.
	Monolith.onLevel(function(session)
		local want = Formulas.pedestalCount(session.monolithLevel)
		if #session.pedestals < want then
			while #session.pedestals < want do
				table.insert(session.pedestals, "")
			end
			redraw(session)
			PlayerState.markDirty(session, "arsenal")
			notice:FireClient(session.player, "newPedestal", want)
		end
	end)

	PlayerState.onAdded(function(session)
		local player = session.player
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			if player.Character == character then
				giveTool(session)
			end
		end)
		if player.Character then
			task.spawn(giveTool, session)
		end
		task.defer(redraw, session)
	end)
	PlayerState.onRemoving(function(session)
		limiter.forget(session.player)
		local info = Bases.of(session)
		if info then
			local old = info.model:FindFirstChild("PedestalWeapons")
			if old then
				old:Destroy()
			end
			-- Свободная база — все постаменты погашены, чтобы не путать с чужими.
			for _, part in info.pedestals do
				part.Transparency = 0.7
				local top = part:FindFirstChild("Top")
				if top and top:IsA("BasePart") then
					top.Transparency = 0.85
					top.Color = Color3.fromRGB(110, 140, 170)
				end
			end
		end
	end)

	pedestalRemote.OnServerEvent:Connect(function(player: Player, action: unknown, a: unknown, b: unknown)
		local session = PlayerState.get(player)
		if not session or type(action) ~= "string" or not limiter.consume(player, 6, 6) then
			return
		end
		if not Bases.nearMonolith(session) then
			return
		end
		if action == "best" then
			equipBest(session)
		elseif action == "insert" then
			local slot = validSlot(session, a)
			if slot and type(b) == "string" and #b <= 24 then
				insert(session, slot, b)
			end
		elseif action == "remove" then
			local slot = validSlot(session, a)
			if slot and session.pedestals[slot] ~= "" then
				local before = Arsenal.damage(session)
				session.pedestals[slot] = ""
				changed(session, before)
			end
		end
	end)

	equipRemote.OnServerEvent:Connect(function(player: Player, id: unknown)
		local session = PlayerState.get(player)
		if not session or type(id) ~= "string" or #id > 24 or not limiter.consume(player, 6, 6) then
			return
		end
		if inPedestal(session, id) and id ~= session.hand then
			session.hand = id
			PlayerState.markDirty(session, "arsenal")
			giveTool(session)
		end
	end)

	feedRemote.OnServerEvent:Connect(function(player: Player, action: unknown, id: unknown)
		local session = PlayerState.get(player)
		if not session or not limiter.consume(player, 6, 6) then
			return
		end
		local total = 0
		if action == "one" and type(id) == "string" and #id <= 24 then
			total = feed(session, { id })
		elseif action == "commons" then
			-- Все обычные (немутированные) вне постаментов.
			local ids = {}
			for _, w in session.weapons do
				if w.mutation == 0 and w.rarity == 1 and not inPedestal(session, w.id) then
					table.insert(ids, w.id)
				end
			end
			total = feed(session, ids)
		end
		if total > 0 then
			notice:FireClient(player, "fed", total)
		end
	end)
end

return Arsenal

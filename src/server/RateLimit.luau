--!strict
-- «Ведро жетонов»: жетоны копятся со скоростью rate в секунду, не больше capacity.
-- Каждое действие тратит жетон. Нет жетона — действие отбрасывается.

local RateLimit = {}

type Bucket = { tokens: number, updatedAt: number }

export type Limiter = {
	consume: (player: Player, rate: number, capacity: number) -> boolean,
	forget: (player: Player) -> (),
}

function RateLimit.new(): Limiter
	local buckets: { [Player]: Bucket } = {}

	local function consume(player: Player, rate: number, capacity: number): boolean
		local now = os.clock()
		local bucket = buckets[player]
		if not bucket then
			bucket = { tokens = capacity, updatedAt = now }
			buckets[player] = bucket
		end
		bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.updatedAt) * rate)
		bucket.updatedAt = now
		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	local function forget(player: Player)
		buckets[player] = nil
	end

	return { consume = consume, forget = forget }
end

return RateLimit

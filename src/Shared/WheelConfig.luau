--[[
	WheelConfig (ModuleScript -> ReplicatedStorage)
	==================================================
	Pure data + a shared weighted-roll helper for the Fortune Wheel: a
	free daily spin, plus extra spins earned by playing (see
	WheelService.server.luau), landing on one of 8 weighted rewards.

	Both server (WheelService, which is authoritative and does the actual
	rolling/granting) and client (WheelPanel, which only draws the wheel
	and its segments) require this file, so what a player SEES on the
	wheel can never drift from what they can actually win -- unlike the
	promo codes in ProgressionService, there's nothing here worth hiding:
	seeing the odds is part of the point of a wheel.

	WHY A SEPARATE MECHANIC FROM THE DAILY STREAK
	--------------------------------------------------
	The daily streak's reward is KNOWN in advance and its appeal is
	commitment (don't break the chain). The wheel's reward is UNKNOWN
	until it stops spinning and its appeal is suspense -- a different
	psychological hook reinforcing a different kind of return visit,
	layered on top rather than replacing anything. Tickets earned from
	actual play (not just logging in) also tie it back into the core
	click/collect loop the way the daily streak or quests don't.
]]

local WheelConfig = {}

-- =========================================================================
-- TICKETS
-- =========================================================================

-- One free spin, always available once the cooldown clears -- a rolling
-- 24h timer from the player's OWN last spin (see WheelService), not a
-- shared UTC day boundary like the daily streak. Deliberately a
-- different rhythm from the streak so the two don't just feel like the
-- same "log in for a reward" beat twice.
WheelConfig.FreeSpinCooldownSeconds = 24 * 60 * 60

-- Extra spins earned by playing. Deterministic (not another random roll
-- on top of crit/golden/gravity-well) so it reads as steady progress
-- toward a spin, not more randomness fatigue.
WheelConfig.CollectionsPerTicket = 60
WheelConfig.MaxBankedTickets = 5

-- =========================================================================
-- SEGMENTS
-- =========================================================================
-- Exactly 8 -- WheelPanel.client.luau lays these out as 8 fixed physical
-- slots around the wheel, one each, so "which slot lit up" and "what you
-- actually won" are always the same thing (the server rolls an INDEX
-- into this list, never a reward that then has to go find a slot).
-- Weights sum to 100 for a readable "X% chance" if that's ever surfaced.
--
-- Essence is scaled by rebirths the same way every other reward in the
-- game is (ProgressionConfig.ScaleReward) -- WheelService applies that;
-- this table only holds the base numbers.
WheelConfig.Segments = {
	{ Id = "spark",   Label = "Spark",         Icon = "✨", Color = Color3.fromRGB(120, 200, 255), Weight = 30, Essence = 400 },
	{ Id = "glimmer", Label = "Glimmer",       Icon = "💫", Color = Color3.fromRGB(120, 240, 160), Weight = 25, Essence = 800 },
	{ Id = "shard",   Label = "Shard",         Icon = "🔮", Color = Color3.fromRGB(170, 130, 255), Weight = 18, Essence = 1800 },
	{ Id = "surge",   Label = "Surge",         Icon = "🌊", Color = Color3.fromRGB(90, 160, 230),  Weight = 12, Essence = 3500 },
	{
		Id = "boost", Label = "Boost", Icon = "🚀", Color = Color3.fromRGB(255, 165, 60), Weight = 8,
		Essence = 6000,
		Potion = { Effect = "EssenceX15", Duration = 10 * 60 },
		PotionLabel = "+ 1.5x Essence (10 min)",
	},
	{ Id = "cache", Label = "Radiant Cache", Icon = "📦", Color = Color3.fromRGB(255, 205, 80), Weight = 4, Essence = 12000 },
	{
		Id = "prestige", Label = "Prestige Spark", Icon = "🔥", Color = Color3.fromRGB(230, 80, 90), Weight = 2,
		Essence = 3000,
		Shards = 2,
	},
	{
		Id = "jackpot", Label = "JACKPOT", Icon = "👑", Color = Color3.fromRGB(255, 221, 84), Weight = 1,
		Essence = 30000,
		Potion = { Effect = "EssenceX15", Duration = 20 * 60 },
		PotionLabel = "+ 1.5x Essence (20 min)",
	},
}

WheelConfig.SegmentCount = #WheelConfig.Segments

function WheelConfig.TotalWeight(): number
	local total = 0
	for _, segment in ipairs(WheelConfig.Segments) do
		total += segment.Weight
	end
	return total
end

-- Rolls a weighted-random segment INDEX (1..SegmentCount). Pure/stateless
-- -- callers get their randomness implicitly via math.random, same as
-- every other roll in this codebase (RollCrit, golden storm chance,
-- Gravity Well, ...). math.random() is documented to return a float in
-- [0, 1), strictly less than 1, so `roll` is always strictly less than
-- `total` and the loop below is guaranteed to return before the
-- fallback -- kept anyway as the same never-error-on-an-edge-case
-- guarantee every roll in this game has.
function WheelConfig.RollSegmentIndex(): number
	local total = WheelConfig.TotalWeight()
	local roll = math.random() * total
	local cumulative = 0
	for index, segment in ipairs(WheelConfig.Segments) do
		cumulative += segment.Weight
		if roll < cumulative then
			return index
		end
	end
	return WheelConfig.SegmentCount
end

return WheelConfig

--[[
	ProgressionConfig (ModuleScript -> ReplicatedStorage)
	=====================================================
	Shared, pure-data definitions for the three retention systems:

		1. Daily login rewards (a 7 day streak cycle)
		2. Daily quests (3 rotating goals, same for everyone each day)
		3. Playtime chests (rewards for staying in a single session)

	Both the server (ProgressionService, which is authoritative and does
	all the actual granting) and the client (ProgressionHud, which only
	draws things) require this file, so the numbers a player is shown can
	never drift out of sync with the numbers they actually receive.

	NOTHING in here touches Players, DataStores or Remotes -- it's safe to
	require from either side.

	WHY THESE THREE SYSTEMS
	-----------------------
	The game's problem was never a lack of content, it was a lack of
	*goals*. A player would join, click, and have nothing telling them
	what to aim for or any reason to come back tomorrow. Quests give a
	session a purpose, playtime chests give a reason to stay past the
	first few minutes, and the daily streak gives a reason to return.

	All rewards here are ordinary in-game essence (plus, on day 7, a
	short boost that uses the existing potion system). Deliberately
	nothing here costs Robux or pressures a purchase -- these systems
	exist to make the game worth playing, not to sell anything.
]]

local ProgressionConfig = {}

-- =========================================================================
-- NUMBER FORMATTING
-- =========================================================================
-- Matches the abbreviation style used by the rest of the game's UI so
-- reward numbers read identically wherever they appear.

local ABBREVIATIONS = {
	"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No"
}

function ProgressionConfig.FormatNumber(value: number): string
	value = math.floor(tonumber(value) or 0)

	local absValue = math.abs(value)
	if absValue < 1000 then
		return tostring(value)
	end

	local index = math.floor(math.log10(absValue) / 3)
	if index >= #ABBREVIATIONS then
		index = #ABBREVIATIONS - 1
	end

	local shortValue = value / (10 ^ (index * 3))
	local formatted = string.format("%.2f", shortValue)
	formatted = string.gsub(formatted, "%.?0+$", "")

	return formatted .. ABBREVIATIONS[index + 1]
end

-- Whole-day number in UTC. Used for "is this a new day?" checks -- every
-- player in the world rolls over to a new day at the same instant, which
-- keeps daily quests genuinely shared instead of per-timezone.
function ProgressionConfig.GetDayNumber(timestamp: number?): number
	return math.floor((timestamp or os.time()) / 86400)
end

-- Seconds until the next UTC day boundary (for "resets in 4h 12m" text).
function ProgressionConfig.GetSecondsUntilNextDay(timestamp: number?): number
	local now = timestamp or os.time()
	return 86400 - (now % 86400)
end

function ProgressionConfig.FormatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60

	if hours > 0 then
		return ("%dh %dm"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%dm %ds"):format(minutes, secs)
	end
	return ("%ds"):format(secs)
end

-- =========================================================================
-- REWARD SCALING
-- =========================================================================
-- A flat 500 essence is a fortune on day one and worthless after ten
-- rebirths. Rewards are therefore quoted as a base value and scaled by
-- how far the player has actually progressed, so a daily reward stays
-- meaningful for a returning veteran without being absurd for a newcomer.

function ProgressionConfig.GetRewardScale(rebirths: number?): number
	return 1 + (math.max(0, rebirths or 0) * 0.85)
end

function ProgressionConfig.ScaleReward(baseAmount: number, rebirths: number?): number
	return math.max(1, math.floor(baseAmount * ProgressionConfig.GetRewardScale(rebirths)))
end

-- =========================================================================
-- 1. DAILY LOGIN REWARDS
-- =========================================================================
-- A 7 day cycle. Day 7 is deliberately the standout reward (a big essence
-- payout plus a timed boost) so there's a clear thing to aim for across a
-- week. After day 7 the cycle repeats, keeping the day 7 payout as the
-- recurring "you kept your streak" reward.
--
-- Missing a day resets the streak back to day 1. That's the standard
-- genre convention, and it's kept deliberately gentle: nothing is ever
-- permanently lost, there's no way to pay to restore a streak, and the
-- UI never uses countdown pressure about losing it.

ProgressionConfig.DailyRewards = {
	{ Day = 1, Essence = 250,    Icon = "✨", Title = "Day 1" },
	{ Day = 2, Essence = 600,    Icon = "✨", Title = "Day 2" },
	{ Day = 3, Essence = 1400,   Icon = "💫", Title = "Day 3" },
	{ Day = 4, Essence = 3000,   Icon = "💫", Title = "Day 4" },
	{ Day = 5, Essence = 6500,   Icon = "🌟", Title = "Day 5" },
	{ Day = 6, Essence = 14000,  Icon = "🌟", Title = "Day 6" },
	{
		Day = 7,
		Essence = 40000,
		Icon = "👑",
		Title = "Day 7",
		-- Uses the existing PotionTimerService effect, so this needs no
		-- new boost plumbing of its own.
		Potion = { Effect = "EssenceX15", Duration = 30 * 60 },
		PotionLabel = "+ 1.5x Essence (30 min)",
	},
}

ProgressionConfig.DailyCycleLength = #ProgressionConfig.DailyRewards

-- Which entry of the cycle a given streak length maps to (1-indexed,
-- wrapping so streak 8 lands back on day 1, streak 14 on day 7, etc).
function ProgressionConfig.GetDailyRewardForStreak(streak: number)
	local cycleLength = ProgressionConfig.DailyCycleLength
	local index = ((math.max(1, streak) - 1) % cycleLength) + 1
	return ProgressionConfig.DailyRewards[index], index
end

-- =========================================================================
-- STREAK FREEZES
-- =========================================================================
-- Missing a day still resets the streak by default -- that stays exactly
-- as gentle as the note above describes (no pay-to-restore, no countdown-
-- pressure UI). A freeze is the same gentleness pointed the other
-- direction: earned for free by keeping a streak going, it forgives
-- exactly one missed day instead of the whole thing resetting, so one bad
-- week doesn't erase a genuinely-earned streak. Never purchasable, never
-- advertised as "at risk" -- it either quietly saves a streak or it
-- doesn't (see ProgressionService's claim handler and ProgressionHud's
-- status line).
ProgressionConfig.StreakFreezeEveryNDays = 7 -- one freeze per full week of streak
ProgressionConfig.MaxStreakFreezes = 3 -- bankable cap -- a safety net, not unlimited insurance

-- =========================================================================
-- 2. DAILY QUESTS
-- =========================================================================
-- Trackable stat keys. ProgressionService increments these; quests just
-- reference them. Keep these strings stable -- they're persisted inside
-- player data as quest progress keys.

ProgressionConfig.Stats = {
	OrbsCollected = "OrbsCollected",
	Clicks = "Clicks",
	EssenceEarned = "EssenceEarned",
	CriticalOrbs = "CriticalOrbs",
	UpgradesBought = "UpgradesBought",
	Rebirths = "Rebirths",
}

-- The pool the day's quests are drawn from. Each entry is a template; the
-- actual target/reward is scaled per player by their rebirth count at the
-- time the quest is generated.
--
-- Targets are tuned to be completable inside a single normal session --
-- the point is to give a session a shape ("three things to finish"), not
-- to create a grind that spans days.
ProgressionConfig.QuestPool = {
	{
		Id = "collect_orbs_small",
		Stat = ProgressionConfig.Stats.OrbsCollected,
		Target = 75,
		BaseReward = 900,
		Icon = "🔮",
		Title = "Essence Gatherer",
		Describe = function(target) return ("Collect %d orbs"):format(target) end,
	},
	{
		Id = "collect_orbs_large",
		Stat = ProgressionConfig.Stats.OrbsCollected,
		Target = 250,
		BaseReward = 2600,
		Icon = "🔮",
		Title = "Orb Hoarder",
		Describe = function(target) return ("Collect %d orbs"):format(target) end,
	},
	{
		Id = "clicks_small",
		Stat = ProgressionConfig.Stats.Clicks,
		Target = 100,
		BaseReward = 800,
		Icon = "👆",
		Title = "Orb Breaker",
		Describe = function(target) return ("Click the great orb %d times"):format(target) end,
	},
	{
		Id = "clicks_large",
		Stat = ProgressionConfig.Stats.Clicks,
		Target = 350,
		BaseReward = 2400,
		Icon = "👆",
		Title = "Relentless",
		Describe = function(target) return ("Click the great orb %d times"):format(target) end,
	},
	{
		Id = "criticals",
		Stat = ProgressionConfig.Stats.CriticalOrbs,
		Target = 15,
		BaseReward = 1800,
		Icon = "⚡",
		Title = "Critical Spark",
		Describe = function(target) return ("Collect %d critical orbs"):format(target) end,
	},
	{
		Id = "criticals_many",
		Stat = ProgressionConfig.Stats.CriticalOrbs,
		Target = 40,
		BaseReward = 3600,
		Icon = "⚡",
		Title = "Storm of Sparks",
		Describe = function(target) return ("Collect %d critical orbs"):format(target) end,
	},
	{
		Id = "upgrades",
		Stat = ProgressionConfig.Stats.UpgradesBought,
		Target = 3,
		BaseReward = 1500,
		Icon = "🌳",
		Title = "Growing Stronger",
		Describe = function(target) return ("Purchase %d upgrades"):format(target) end,
	},
	{
		Id = "upgrades_many",
		Stat = ProgressionConfig.Stats.UpgradesBought,
		Target = 8,
		BaseReward = 3200,
		Icon = "🌳",
		Title = "Deep Roots",
		Describe = function(target) return ("Purchase %d upgrades"):format(target) end,
	},
	{
		Id = "essence_earned",
		Stat = ProgressionConfig.Stats.EssenceEarned,
		Target = 4000,
		BaseReward = 2000,
		Icon = "🌿",
		Title = "Essence Flow",
		-- Scales with rebirths like the reward does, since a veteran earns
		-- vastly more per minute than a new player.
		ScaleTarget = true,
		Describe = function(target)
			return ("Earn %s essence"):format(ProgressionConfig.FormatNumber(target))
		end,
	},
	{
		Id = "rebirth",
		Stat = ProgressionConfig.Stats.Rebirths,
		Target = 1,
		BaseReward = 5000,
		Icon = "🔥",
		Title = "Begin Again",
		Describe = function(target) return ("Rebirth %d time(s)"):format(target) end,
	},
}

ProgressionConfig.QuestsPerDay = 3

-- Deterministic shuffle so every player online on a given day gets the
-- SAME set of quests without the server having to store the selection.
-- (A small LCG rather than math.random, because math.random's global
-- state is shared and reseeding it would disturb other systems.)
local function deterministicPick(dayNumber: number, poolSize: number, count: number)
	local picked = {}
	local used = {}

	-- Well-known LCG constants (Numerical Recipes); any decent mixing
	-- function works here, this only needs to look arbitrary and be stable.
	local seed = (dayNumber * 1664525 + 1013904223) % 2147483647

	local attempts = 0
	while #picked < count and attempts < poolSize * 8 do
		attempts += 1
		seed = (seed * 1664525 + 1013904223) % 2147483647
		local index = (seed % poolSize) + 1
		if not used[index] then
			used[index] = true
			table.insert(picked, index)
		end
	end

	-- Fallback: if the pool is smaller than `count` or we somehow failed
	-- to fill, top up in order so callers always get a usable list.
	for index = 1, poolSize do
		if #picked >= count then
			break
		end
		if not used[index] then
			used[index] = true
			table.insert(picked, index)
		end
	end

	return picked
end

-- Returns the concrete quest list for a day: ids, scaled targets, scaled
-- rewards and display strings. Pure -- same inputs always give the same
-- output, on client and server alike.
function ProgressionConfig.GetQuestsForDay(dayNumber: number, rebirths: number?)
	local pool = ProgressionConfig.QuestPool
	local indices = deterministicPick(dayNumber, #pool, ProgressionConfig.QuestsPerDay)

	local quests = {}
	for _, poolIndex in ipairs(indices) do
		local template = pool[poolIndex]
		if template then
			local target = template.Target
			if template.ScaleTarget then
				target = ProgressionConfig.ScaleReward(target, rebirths)
			end

			table.insert(quests, {
				Id = template.Id,
				Stat = template.Stat,
				Target = target,
				Reward = ProgressionConfig.ScaleReward(template.BaseReward, rebirths),
				Icon = template.Icon,
				Title = template.Title,
				Description = template.Describe(target),
			})
		end
	end

	return quests
end

-- =========================================================================
-- 3. PLAYTIME CHESTS
-- =========================================================================
-- Claimable rewards for time spent in a single session. This is the
-- system aimed squarely at session length: the first chest lands early
-- enough that a brand-new player reaches it before they'd otherwise get
-- bored, and each subsequent one is worth noticeably more than the last.
--
-- Progress is per-session and resets on rejoin ON PURPOSE. Because the
-- rewards escalate, staying in one long session is always strictly
-- better than leaving and rejoining -- so there's no incentive to
-- server-hop, and the mechanic can't be farmed.

ProgressionConfig.PlaytimeChests = {
	{ Seconds = 2 * 60,  Essence = 400,   Icon = "🎁", Title = "First Find" },
	{ Seconds = 5 * 60,  Essence = 1000,  Icon = "🎁", Title = "Bronze Cache" },
	{ Seconds = 10 * 60, Essence = 2500,  Icon = "📦", Title = "Silver Cache" },
	{ Seconds = 18 * 60, Essence = 6000,  Icon = "📦", Title = "Golden Cache" },
	{ Seconds = 30 * 60, Essence = 15000, Icon = "💎", Title = "Ancient Vault" },
	{
		Seconds = 45 * 60,
		Essence = 32000,
		Icon = "👑",
		Title = "Keeper's Hoard",
		Potion = { Effect = "EssenceX15", Duration = 20 * 60 },
		PotionLabel = "+ 1.5x Essence (20 min)",
	},
}

-- Once every listed chest is claimed, a repeating chest keeps the reward
-- loop alive for very long sessions instead of going silent.
ProgressionConfig.RepeatingChest = {
	IntervalSeconds = 15 * 60,
	Essence = 20000,
	Icon = "💎",
	Title = "Deep Cache",
}

-- The chest at a given index (1-based). Past the defined list this rolls
-- into the repeating chest, with its unlock time extending accordingly.
function ProgressionConfig.GetChest(index: number)
	local defined = ProgressionConfig.PlaytimeChests
	if index <= #defined then
		return defined[index], false
	end

	local repeating = ProgressionConfig.RepeatingChest
	local lastDefined = defined[#defined]
	local extraSteps = index - #defined

	return {
		Seconds = lastDefined.Seconds + (repeating.IntervalSeconds * extraSteps),
		Essence = repeating.Essence,
		Icon = repeating.Icon,
		Title = repeating.Title,
	}, true
end

return ProgressionConfig

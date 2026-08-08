--[[
	AchievementsConfig (ModuleScript -> ReplicatedStorage)
	=======================================================
	Pure data for the Achievements panel: the 13 existing Roblox badges
	(already awarded server-side via BadgeService, but with ZERO in-game
	visibility beyond a one-off toast -- a player has no way to see what
	badges exist, which they have, or what's left) plus a new set of
	in-game Milestones with real claimable rewards.

	WHY MILESTONES ARE SEPARATE FROM BADGES
	------------------------------------------
	Badges are Roblox platform achievements -- they can't pay out in-game
	currency, so completing one is pure bragging rights. Milestones are
	this game's own goals, each with a concrete essence/Prestige Shard
	payout on claim, giving achievement-hunting an actual gameplay loop
	(spot a goal -> chase it -> claim -> spend the reward -> repeat)
	instead of just a checklist.

	Every Milestone's Stat key reads a field that's already tracked,
	server-owned, and MONOTONIC (never decreases -- TotalEssenceGathered,
	CriticalEssence, Rebirths, ManualStormsSummoned, UniqueEssences) so a
	milestone can never un-complete itself later (e.g. spending currency
	would NOT be safe to gate a milestone on, which is why none of these
	use RebirthCurrency's current balance).

	Pure data + math. No Players, DataStores or Remotes -- safe to require
	from either side, same contract as every other *Config/*Upgrades module
	in this codebase.
]]

local AchievementsConfig = {}

-- =========================================================================
-- BADGES (Roblox BadgeService achievements -- ids match DefaultPlayerData's
-- Badges table exactly; this module only adds display text on top)
-- =========================================================================
-- Secret = true hides Name/Description until earned, replaced with "???" --
-- reserved for the Hollowed ARG badges, which are meant to stay a surprise.

AchievementsConfig.Badges = {
	{ Id = "3032854636359044", Name = "First Steps", Icon = "✨",
		Description = "Collect your very first essence." },
	{ Id = "4008378896042305", Name = "Welcome to the Grind", Icon = "🌱",
		Description = "Reach 500 Earth Essence." },
	{ Id = "1189564550645111", Name = "Essence Hoarder", Icon = "💰",
		Description = "Reach 100,000 Earth Essence." },
	{ Id = "4077164450257078", Name = "Essence Baron", Icon = "👑",
		Description = "Reach 1,000,000 Earth Essence." },
	{ Id = "2522508290427820", Name = "First Rebirth", Icon = "🔥",
		Description = "Rebirth for the first time." },
	{ Id = "2435657570989542", Name = "Reborn Again and Again", Icon = "♻️",
		Description = "Reach 10 rebirths." },
	{ Id = "2662901027091325", Name = "Critical Hit", Icon = "⚡",
		Description = "Collect your first critical essence." },
	{ Id = "4281764202448916", Name = "Storm Caller", Icon = "🌩️",
		Description = "Manually summon your first essence storm." },
	{ Id = "2767213148031403", Name = "Storm Chaser", Icon = "🌪️",
		Description = "Manually summon 35 essence storms." },
	{ Id = "3091905792121753", Name = "Storm Watcher", Icon = "☁️",
		Description = "Witness your first automatic essence storm." },
	{ Id = "1472053267504184", Name = "It Has Noticed You", Icon = "👁️",
		Secret = true },
	{ Id = "3749419964014047", Name = "Nothing Left Hidden", Icon = "🌑",
		Secret = true },
	{ Id = "1219109424164715", Name = "Playtester", Icon = "🎮",
		Description = "Play EssenceBound. That's it, that's the badge." },
}

-- =========================================================================
-- MILESTONES (in-game only, real rewards)
-- =========================================================================
-- Reward.Type: "Essence" (added to Earth Essence, the same leaderstat path
-- every other essence grant in the game uses) or "Shards" (Prestige Shop
-- currency, same attribute path the Prestige Shop / Shard Rain use).
--
-- Amounts are deliberately modest relative to the tree's own costs (see
-- TreeUpgrades' pass notes) -- these are a nice bonus for hitting a goal
-- you were already chasing, not a way to skip the economy.

AchievementsConfig.Milestones = {
	{
		Id = "milestone_two_essences", Name = "Two Sides of Essence", Icon = "🌗",
		Description = "Discover both Earth Essence and Shadow Essence.",
		Stat = "UniqueEssences", Target = 2,
		Reward = { Type = "Essence", Amount = 150 },
	},
	{
		Id = "milestone_first_harvest", Name = "First Harvest", Icon = "🌿",
		Description = "Gather 1,000 essence in total (lifetime).",
		Stat = "TotalEssenceGathered", Target = 1000,
		Reward = { Type = "Essence", Amount = 200 },
	},
	{
		Id = "milestone_storm_apprentice", Name = "Storm Chaser's Apprentice", Icon = "🌤️",
		Description = "Manually summon 5 essence storms.",
		Stat = "ManualStormsSummoned", Target = 5,
		Reward = { Type = "Essence", Amount = 300 },
	},
	{
		Id = "milestone_essence_adept", Name = "Essence Adept", Icon = "🍀",
		Description = "Gather 50,000 essence in total (lifetime).",
		Stat = "TotalEssenceGathered", Target = 50000,
		Reward = { Type = "Essence", Amount = 2000 },
	},
	{
		Id = "milestone_spark_of_fortune", Name = "Spark of Fortune", Icon = "💫",
		Description = "Gather 1,000 essence from critical hits.",
		Stat = "CriticalEssence", Target = 1000,
		Reward = { Type = "Essence", Amount = 500 },
	},
	{
		Id = "milestone_cycle_of_rebirth", Name = "Cycle of Rebirth", Icon = "🔁",
		Description = "Reach 3 rebirths.",
		Stat = "Rebirths", Target = 3,
		Reward = { Type = "Shards", Amount = 1 },
	},
	{
		Id = "milestone_essence_master", Name = "Essence Master", Icon = "🏵️",
		Description = "Gather 1,000,000 essence in total (lifetime).",
		Stat = "TotalEssenceGathered", Target = 1000000,
		Reward = { Type = "Essence", Amount = 25000 },
	},
	{
		Id = "milestone_ascended_soul", Name = "Ascended Soul", Icon = "🕊️",
		Description = "Reach 15 rebirths.",
		Stat = "Rebirths", Target = 15,
		Reward = { Type = "Shards", Amount = 3 },
	},
	{
		Id = "milestone_essence_legend", Name = "Essence Legend", Icon = "🌟",
		Description = "Gather 100,000,000 essence in total (lifetime).",
		Stat = "TotalEssenceGathered", Target = 100000000,
		Reward = { Type = "Shards", Amount = 1 },
	},
}

local MilestonesById = {}
for _, def in ipairs(AchievementsConfig.Milestones) do
	MilestonesById[def.Id] = def
end
AchievementsConfig.MilestonesById = MilestonesById

function AchievementsConfig.GetMilestone(id: string)
	return MilestonesById[id]
end

-- Reads whatever stat a milestone cares about straight off a playerData
-- table (works with the real PlayerData module server-side). Coerced to a
-- number and floored so a milestone can never be tripped up by a stray
-- nil/float on a field it doesn't own the writing of.
function AchievementsConfig.GetStatValue(data, statKey: string): number
	return math.floor(tonumber(data and data[statKey]) or 0)
end

-- Progress toward a single milestone as a 0-1 fraction, for progress bars.
function AchievementsConfig.GetProgress(data, id: string): number
	local def = MilestonesById[id]
	if not def or def.Target <= 0 then
		return 0
	end
	return math.clamp(AchievementsConfig.GetStatValue(data, def.Stat) / def.Target, 0, 1)
end

function AchievementsConfig.IsComplete(data, id: string): boolean
	local def = MilestonesById[id]
	if not def then
		return false
	end
	return AchievementsConfig.GetStatValue(data, def.Stat) >= def.Target
end

return AchievementsConfig

--[[
	RebirthShopUpgrades (ModuleScript -> ReplicatedStorage)
	========================================================
	Definitions for the Prestige Shop: what Rebirth Currency (display name
	"Prestige Shards") actually buys.

	WHERE THE CURRENCY COMES FROM
	-------------------------------
	Every rebirth grants RebirthModule.BASE_REBIRTH_CURRENCY_GRANT (1) Prestige
	Shard, plus a bonus from the "Ascension Insight" Earth-tree upgrade
	(EffectType = "BonusRebirthCurrency", up to +6 at max level). That part
	already existed before this shop did -- see RebirthHandler.luau's
	PerformRebirth. This file is the spend side that was missing.

	WHY THESE FIVE AND NOT MORE STAT LINES
	-----------------------------------------
	The Earth tree and the Shadow Sanctum both already do "flat number goes
	up" upgrades extremely well. A currency this scarce (1-7 per rebirth --
	rebirths themselves take a real session to earn) is wasted if it just
	buys a fourth copy of "+essence %". Every upgrade below changes HOW a
	system behaves, not just its magnitude, and each is driven by a
	DIFFERENT trigger so they never compete for the same moment:

		Momentum Core     -- continuous: sustained click cadence
		Gravity Well      -- periodic: a timed field pulse
		Twin Ascension    -- the rebirth action itself
		Second Wind       -- reactive: orb energy hitting 0
		Shard Rain        -- random: any collection

	Costs are deliberately tiny (single/low-double digits) relative to
	TreeUpgrades/SanctumUpgrades -- Prestige Shards accrue at ~1-7 per
	REBIRTH (which itself takes a real session), not per second like
	Earth/Shadow Essence. A cost curve copied from either of those would be
	effectively unreachable.

	Pure data + math, same contract as SanctumUpgrades: no Players,
	DataStores or Remotes, safe to require from either side. The server is
	still the only thing that can grant a level or spend a Shard.
]]

local RebirthShopUpgrades = {}

-- Source of truth is the plain player Attribute "RebirthCurrency" (already
-- written by RebirthHandler.luau's PerformRebirth) -- NOT a leaderstat
-- Quantity sub-attribute like Earth/Shadow Essence use. Simpler: every
-- call site (rebirth grant, shop purchase, Shard Rain drop, Twin Ascension
-- double) reads/writes exactly one number, and PlayerDataHandler mirrors a
-- leaderstat FROM it automatically for display.
RebirthShopUpgrades.CURRENCY_ATTRIBUTE = "RebirthCurrency"
RebirthShopUpgrades.CURRENCY_NAME = "Prestige Shards"
RebirthShopUpgrades.CURRENCY_ICON = "🔷"

-- Momentum's window/cap don't scale per level (only the per-stack % does),
-- so they live here once rather than being repeated in every level entry.
RebirthShopUpgrades.MOMENTUM_WINDOW_SECONDS = 1.2
RebirthShopUpgrades.MOMENTUM_MAX_STACKS = 20

-- =========================================================================
-- DEFINITIONS
-- =========================================================================
-- Cost for the next level = BaseCost * (CostGrowth ^ levelsAlreadyOwned),
-- identical formula to TreeUpgrades/SanctumUpgrades.
--
-- None of these fit a single EffectPerLevel number, so -- like SanctumUpgrades'
-- relics -- every level is its own small table under Levels[level], read by
-- GetLevelData. What's IN that table differs upgrade to upgrade (chance,
-- cooldown, radius...) since each upgrade is its own mechanic; DescribeEffect
-- below special-cases each Id rather than trying to force one generic format.

local UPGRADES = {
	{
		Id = "rebirthshop_momentum",
		Name = "Momentum Core",
		Description = "Sustained clicking builds Momentum, raising your essence gain -- pausing resets it.",
		Icon = "⚡",
		MaxLevel = 5,
		BaseCost = 3,
		CostGrowth = 1.9,
		-- Read by EssenceMultiplier (bonus) and OrbClickManager (stacking).
		Levels = {
			[1] = { PercentPerStack = 0.006 },
			[2] = { PercentPerStack = 0.009 },
			[3] = { PercentPerStack = 0.012 },
			[4] = { PercentPerStack = 0.016 },
			[5] = { PercentPerStack = 0.020 },
		},
	},
	{
		Id = "rebirthshop_gravitywell",
		Name = "Gravity Well",
		Description = "Periodically fuses nearby orbs into fewer, bigger ones worth more than their sum.",
		Icon = "🌀",
		MaxLevel = 4,
		BaseCost = 5,
		CostGrowth = 2.0,
		-- Read by CursorCollection's merge pulse.
		Levels = {
			[1] = { Interval = 40, MergeRadius = 140, BonusPercent = 0.08 },
			[2] = { Interval = 32, MergeRadius = 160, BonusPercent = 0.11 },
			[3] = { Interval = 25, MergeRadius = 180, BonusPercent = 0.15 },
			[4] = { Interval = 18, MergeRadius = 200, BonusPercent = 0.20 },
		},
	},
	{
		Id = "rebirthshop_twinascension",
		Name = "Twin Ascension",
		Description = "Every rebirth has a chance to grant DOUBLE Prestige Shards in one flash.",
		Icon = "♊",
		MaxLevel = 5,
		BaseCost = 4,
		CostGrowth = 1.9,
		-- Read by RebirthHandler.luau's PerformRebirth.
		Levels = {
			[1] = { ChancePercent = 0.05 },
			[2] = { ChancePercent = 0.09 },
			[3] = { ChancePercent = 0.14 },
			[4] = { ChancePercent = 0.20 },
			[5] = { ChancePercent = 0.28 },
		},
	},
	{
		Id = "rebirthshop_secondwind",
		Name = "Second Wind",
		Description = "When your energy hits zero, catch a Second Wind instead: instant refill + a burst of bonus essence.",
		Icon = "🌅",
		MaxLevel = 3,
		BaseCost = 6,
		CostGrowth = 2.2,
		-- Read by EssenceOrbController.Fire / OrbClickManager.
		Levels = {
			[1] = { Cooldown = 120, RefillPercent = 0.40, BoostSeconds = 8 },
			[2] = { Cooldown = 90, RefillPercent = 0.55, BoostSeconds = 12 },
			[3] = { Cooldown = 60, RefillPercent = 0.75, BoostSeconds = 18 },
		},
	},
	{
		Id = "rebirthshop_shardrain",
		Name = "Shard Rain",
		Description = "A rare chance for any collected orb to also drop a bonus Prestige Shard.",
		Icon = "💎",
		MaxLevel = 5,
		BaseCost = 8,
		CostGrowth = 2.1,
		-- Read by OrbClickManager's collection handler.
		Levels = {
			[1] = { ChancePercent = 0.004, ShardAmount = 1 },
			[2] = { ChancePercent = 0.007, ShardAmount = 1 },
			[3] = { ChancePercent = 0.010, ShardAmount = 1 },
			[4] = { ChancePercent = 0.014, ShardAmount = 2 },
			[5] = { ChancePercent = 0.020, ShardAmount = 2 },
		},
	},
}

RebirthShopUpgrades.List = UPGRADES

local ById = {}
for _, def in ipairs(UPGRADES) do
	ById[def.Id] = def
end
RebirthShopUpgrades.ById = ById

-- =========================================================================
-- MATH
-- =========================================================================

function RebirthShopUpgrades.GetUpgrade(id: string)
	return ById[id]
end

-- Cost of going from `currentLevel` to `currentLevel + 1`, or nil if the
-- upgrade is already maxed. Identical formula to SanctumUpgrades.
function RebirthShopUpgrades.GetCostForNextLevel(id: string, currentLevel: number): number?
	local def = ById[id]
	if not def then
		return nil
	end

	currentLevel = math.max(0, math.floor(tonumber(currentLevel) or 0))
	if currentLevel >= def.MaxLevel then
		return nil
	end

	return math.floor(def.BaseCost * (def.CostGrowth ^ currentLevel))
end

-- The {..level-specific fields..} table for a given level, or nil if `id`
-- isn't a real upgrade or `level` is 0 (not yet purchased).
function RebirthShopUpgrades.GetLevelData(id: string, level: number)
	local def = ById[id]
	if not def or not def.Levels then
		return nil
	end

	level = math.floor(tonumber(level) or 0)
	return def.Levels[level]
end

-- Reads the level straight off the player attribute the server mirrors, so
-- the systems that consume these effects never need player data access.
-- Clamped defensively, same reasoning as SanctumUpgrades.GetPlayerLevel.
function RebirthShopUpgrades.GetPlayerLevel(player, id: string): number
	local def = ById[id]
	if not def or not player then
		return 0
	end

	local level = tonumber(player:GetAttribute(id)) or 0
	return math.clamp(math.floor(level), 0, def.MaxLevel)
end

-- Convenience wrapper used by every consumer (EssenceMultiplier,
-- EssenceOrbController, OrbClickManager, RebirthHandler, CursorCollection).
function RebirthShopUpgrades.GetPlayerLevelData(player, id: string)
	return RebirthShopUpgrades.GetLevelData(id, RebirthShopUpgrades.GetPlayerLevel(player, id))
end

-- Human-readable effect string for the shop panel. Each Id gets its own
-- phrasing rather than a generic formatter -- unlike SanctumUpgrades' stat
-- lines (which are all "+N thing") or relics (all "activates every Ns"),
-- these five don't share a common shape.
function RebirthShopUpgrades.DescribeEffect(id: string, level: number): string
	local data = RebirthShopUpgrades.GetLevelData(id, level)
	if not data then
		return ""
	end

	if id == "rebirthshop_momentum" then
		return ("+%s%% essence per combo stack, up to %dx stacks"):format(
			tostring(data.PercentPerStack * 100), RebirthShopUpgrades.MOMENTUM_MAX_STACKS)
	elseif id == "rebirthshop_gravitywell" then
		return ("Fuses nearby orbs every %ds (+%d%% bonus value)"):format(
			data.Interval, math.floor(data.BonusPercent * 100 + 0.5))
	elseif id == "rebirthshop_twinascension" then
		return ("%d%% chance per rebirth for DOUBLE Prestige Shards"):format(
			math.floor(data.ChancePercent * 100 + 0.5))
	elseif id == "rebirthshop_secondwind" then
		return ("At 0 energy: refill %d%% + 1.5x essence for %ds (%ds cooldown)"):format(
			math.floor(data.RefillPercent * 100 + 0.5), data.BoostSeconds, data.Cooldown)
	elseif id == "rebirthshop_shardrain" then
		return ("%s%% chance per collection for +%d bonus Shard(s)"):format(
			tostring(data.ChancePercent * 100), data.ShardAmount)
	end

	return ""
end

return RebirthShopUpgrades

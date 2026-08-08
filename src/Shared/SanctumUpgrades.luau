--[[
	SanctumUpgrades (ModuleScript -> ReplicatedStorage)
	===================================================
	Definitions for the Shadow Sanctum: the first and only place Shadow
	Essence can actually be spent.

	THE PROBLEM THIS SOLVES
	------------------------
	Shadow Essence was a dead-end currency. Orbs of it spawn at the same
	rate as Earth Essence, it has its own leaderstat and counter, and it
	feeds a passive multiplier -- but every single upgrade in TreeUpgrades
	costs EarthEssence, so there was nothing to do with it. Players
	accumulated a number that only ever went up and never mattered.

	WHY SPENDING IT DOESN'T MAKE YOU WEAKER
	----------------------------------------
	EssenceMultiplier grants a bonus based on Shadow Essence held. If that
	read the current balance, spending would directly reduce your own
	multiplier -- a trap where using the shop is a downgrade. So the
	multiplier now reads LIFETIME Shadow Essence earned (tracked in
	PlayerDataHandler), which only ever increases. Spending costs you the
	balance, never the power you already earned.

	EFFECTS
	--------
	Each upgrade mirrors its level onto a player attribute named after its
	Id (e.g. "sanctum_deep_well" = 3). The systems those effects belong to
	read that attribute directly, exactly as they already do for the
	TreeUpgrades ids. That keeps each hook to a couple of lines in the
	module that actually owns the stat, rather than this file reaching into
	anything.

	Pure data + math. No Players, DataStores or Remotes -- safe to require
	from either side, and the server is still the only thing that can
	actually grant a level.
]]

local SanctumUpgrades = {}

-- Currency key. Must match the key in PlayerData.Essences, which for
-- Shadow Essence includes the space.
SanctumUpgrades.CURRENCY = "Shadow Essence"

-- =========================================================================
-- DEFINITIONS
-- =========================================================================
-- Cost for the next level = BaseCost * (CostGrowth ^ levelsAlreadyOwned)
--
-- Costs are tuned against Shadow Essence accruing at roughly the same rate
-- as Earth Essence (both orb types spawn on equal weight), so these sit in
-- a similar band to the early TreeUpgrades tiers rather than being a
-- separate, much slower economy.

local UPGRADES = {
	{
		Id = "sanctum_umbral_focus",
		Name = "Umbral Focus",
		Description = "Draw raw power from the dark. Increases ALL essence you earn.",
		Icon = "🌑",
		MaxLevel = 10,
		BaseCost = 25,
		CostGrowth = 1.55,
		-- Read by EssenceMultiplier.
		EffectPerLevel = 0.05,
		EffectSuffix = "% essence",
		EffectIsPercent = true,
	},
	{
		Id = "sanctum_deep_well",
		Name = "Deep Well",
		Description = "Widen the orb's reservoir so it holds far more energy before running dry.",
		Icon = "🔋",
		MaxLevel = 10,
		BaseCost = 20,
		CostGrowth = 1.5,
		-- Read by EssenceOrbController.
		EffectPerLevel = 40,
		EffectSuffix = " max energy",
	},
	{
		Id = "sanctum_swift_shadows",
		Name = "Swift Shadows",
		Description = "The orb drinks from the dark to refill itself faster.",
		Icon = "⏳",
		MaxLevel = 8,
		BaseCost = 30,
		CostGrowth = 1.6,
		-- Read by EssenceOrbController.
		EffectPerLevel = 0.6,
		EffectSuffix = " energy/sec",
	},
	{
		Id = "sanctum_wider_reach",
		Name = "Wider Reach",
		Description = "Extend your collection ring so orbs are gathered from further out.",
		Icon = "🎯",
		MaxLevel = 8,
		BaseCost = 35,
		CostGrowth = 1.6,
		-- Read by CollectionUpgrades.
		EffectPerLevel = 4,
		EffectSuffix = " collect radius",
	},

	{
		Id = "sanctum_dark_fortune",
		Name = "Dark Fortune",
		Description = "The dark favours you. Raises the chance any orb lands as a critical.",
		Icon = "🎲",
		MaxLevel = 10,
		BaseCost = 40,
		CostGrowth = 1.62,
		-- Read by CriticalsController.
		EffectPerLevel = 0.02,
		EffectSuffix = "% crit chance",
		EffectIsPercent = true,
	},
	{
		Id = "sanctum_fracture",
		Name = "Umbral Fracture",
		Description = "Shadow bleeds into every strike, so each click drains less of the orb's energy.",
		Icon = "💠",
		MaxLevel = 8,
		BaseCost = 45,
		CostGrowth = 1.65,
		-- Read by EssenceOrbController. Stacks with fracture_efficiency;
		-- both are clamped together against MIN_SHOT_HP_COST there, so this
		-- can never make clicking free.
		EffectPerLevel = 0.04,
		EffectSuffix = "% cheaper clicks",
		EffectIsPercent = true,
	},
	{
		Id = "sanctum_magnetism",
		Name = "Void Magnetism",
		Description = "Loose orbs are pulled toward your cursor instead of drifting where they land.",
		Icon = "🧲",
		MaxLevel = 8,
		BaseCost = 55,
		CostGrowth = 1.6,
		-- Read by CollectionUpgrades.
		EffectPerLevel = 0.12,
		EffectSuffix = " magnet pull",
	},
	{
		Id = "sanctum_overflow",
		Name = "Shadow Overflow",
		Description = "Hold more orbs on screen at once, so big bursts aren't cut short by the cap.",
		Icon = "♾️",
		MaxLevel = 8,
		BaseCost = 60,
		CostGrowth = 1.58,
		-- Read by CollectionUpgrades.
		EffectPerLevel = 3,
		EffectSuffix = " max active orbs",
	},

	-- ===================== RELICS =====================
	-- Unlike the four stat upgrades above, these don't grant a linear
	-- per-level number -- they grant a periodic, automatic EVENT: a big,
	-- unmissable visual moment that fires on its own timer without the
	-- player having to do anything. That's deliberate: the stat upgrades
	-- make the existing loop a bit better every purchase; a relic is
	-- supposed to feel like a completely different kind of reward, and be
	-- something a player watches the clock for.
	--
	-- Kind = "Relic" upgrades read Levels[level] = {Interval, BurstCount?}
	-- instead of EffectPerLevel -- see GetRelicLevelData below. Priced well
	-- above the stat upgrades (500+ vs 20-35 base) since a relic is a much
	-- bigger, rarer purchase, not a routine incremental one.
	{
		Id = "sanctum_hammer",
		Name = "Shadow Hammer",
		Description = "Summons a spectral hammer that periodically slams down on your orb for a burst of bonus essence orbs.",
		Icon = "🔨",
		Kind = "Relic",
		MaxLevel = 2,
		BaseCost = 500,
		CostGrowth = 6, -- level 2 costs 3000
		Levels = {
			[1] = { Interval = 45, BurstCount = 4 },
			[2] = { Interval = 28, BurstCount = 7 },
		},
	},
	{
		Id = "sanctum_laser",
		Name = "Void Laser",
		Description = "Sweeps a beam of void energy across your collection field, instantly gathering everything currently active.",
		Icon = "🌌",
		Kind = "Relic",
		MaxLevel = 2,
		BaseCost = 700,
		CostGrowth = 6, -- level 2 costs 4200
		Levels = {
			[1] = { Interval = 55 },
			[2] = { Interval = 32 },
		},
	},
	{
		Id = "sanctum_chrono_rift",
		Name = "Chrono Rift",
		Description = "Tears open a rift where time thins -- for a few seconds, orbs are gathered the instant they touch your ring.",
		Icon = "⌛",
		Kind = "Relic",
		MaxLevel = 2,
		BaseCost = 900,
		CostGrowth = 6, -- level 2 costs 5400
		-- WindowSeconds instead of BurstCount: this relic grants a timed
		-- state rather than spawning or collecting a fixed amount.
		Levels = {
			[1] = { Interval = 70, WindowSeconds = 6 },
			[2] = { Interval = 45, WindowSeconds = 10 },
		},
	},
	{
		Id = "sanctum_eclipse",
		Name = "Shadow Eclipse",
		Description = "Periodically veils the sky in shadow, surging your essence power while the eclipse lasts.",
		Icon = "🌘",
		Kind = "Relic",
		MaxLevel = 2,
		BaseCost = 1100,
		CostGrowth = 6, -- level 2 costs 6600
		-- BoostSeconds instead of BurstCount/WindowSeconds: this relic
		-- grants a temporary ESSENCE MULTIPLIER rather than orbs, a
		-- collection burst, or a collection-speed state -- see
		-- SanctumService.server.luau for why that makes this the only
		-- relic whose timing is server-owned rather than client-owned.
		Levels = {
			[1] = { Interval = 90, BoostSeconds = 25 },
			[2] = { Interval = 60, BoostSeconds = 40 },
		},
	},
}

SanctumUpgrades.List = UPGRADES

local ById = {}
for _, def in ipairs(UPGRADES) do
	ById[def.Id] = def
end
SanctumUpgrades.ById = ById

-- =========================================================================
-- MATH
-- =========================================================================

function SanctumUpgrades.GetUpgrade(id: string)
	return ById[id]
end

-- Cost of going from `currentLevel` to `currentLevel + 1`, or nil if the
-- upgrade is already maxed.
function SanctumUpgrades.GetCostForNextLevel(id: string, currentLevel: number): number?
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

-- Total effect granted at a given level. Relics have no linear per-level
-- number (see GetRelicLevelData instead), so this returns 0 for them
-- rather than erroring on a nil EffectPerLevel -- defensive in case
-- something calls this generically without checking Kind first.
function SanctumUpgrades.GetEffect(id: string, level: number): number
	local def = ById[id]
	if not def or def.Kind == "Relic" then
		return 0
	end

	level = math.clamp(math.floor(tonumber(level) or 0), 0, def.MaxLevel)
	return def.EffectPerLevel * level
end

-- Relic-only: the {Interval, BurstCount?} table for a given level, or nil
-- if `id` isn't a relic or `level` is 0 (not yet purchased). BurstCount is
-- absent for relics whose activation isn't "spawn N orbs" (e.g. the Void
-- Laser collects everything active instead of spawning a fixed amount).
function SanctumUpgrades.GetRelicLevelData(id: string, level: number)
	local def = ById[id]
	if not def or def.Kind ~= "Relic" or not def.Levels then
		return nil
	end

	level = math.floor(tonumber(level) or 0)
	return def.Levels[level]
end

-- Convenience wrapper matching GetPlayerEffect's naming, for the client
-- scripts that actually run each relic's periodic loop.
function SanctumUpgrades.GetPlayerRelicLevelData(player, id: string)
	return SanctumUpgrades.GetRelicLevelData(id, SanctumUpgrades.GetPlayerLevel(player, id))
end

-- Reads the level straight off the player attribute the server mirrors, so
-- the systems that consume these effects never need player data access.
-- Clamped defensively: an attribute is the one part of this that something
-- else could in principle set to a silly value.
function SanctumUpgrades.GetPlayerLevel(player, id: string): number
	local def = ById[id]
	if not def or not player then
		return 0
	end

	local level = tonumber(player:GetAttribute(id)) or 0
	return math.clamp(math.floor(level), 0, def.MaxLevel)
end

-- Convenience used by the hooks in EssenceMultiplier / EssenceOrbController
-- / CollectionUpgrades.
function SanctumUpgrades.GetPlayerEffect(player, id: string): number
	return SanctumUpgrades.GetEffect(id, SanctumUpgrades.GetPlayerLevel(player, id))
end

-- Human-readable effect string for the UI, e.g. "+15% essence", "+120 max
-- energy", or (for a relic) "Slams every 45s (+4 bonus orbs)".
function SanctumUpgrades.DescribeEffect(id: string, level: number): string
	local def = ById[id]
	if not def then
		return ""
	end

	if def.Kind == "Relic" then
		local data = SanctumUpgrades.GetRelicLevelData(id, level)
		if not data then
			return ""
		end
		if data.BurstCount then
			return ("Activates every %ds (+%d bonus orbs)"):format(data.Interval, data.BurstCount)
		end
		if data.WindowSeconds then
			return ("Activates every %ds (%ds of instant collection)"):format(data.Interval, data.WindowSeconds)
		end
		if data.BoostSeconds then
			return ("Activates every %ds (%ds of 1.5x essence)"):format(data.Interval, data.BoostSeconds)
		end
		return ("Activates every %ds (collects everything active)"):format(data.Interval)
	end

	local total = SanctumUpgrades.GetEffect(id, level)
	if def.EffectIsPercent then
		-- Rounded because floating point turns 3 * 0.05 into 0.15000000000002
		return ("+%s%s"):format(tostring(math.floor(total * 100 + 0.5)), def.EffectSuffix)
	end

	-- Trim a trailing ".0" so whole numbers read cleanly.
	local formatted = string.format("%.1f", total)
	formatted = formatted:gsub("%.0$", "")
	return ("+%s%s"):format(formatted, def.EffectSuffix)
end

return SanctumUpgrades

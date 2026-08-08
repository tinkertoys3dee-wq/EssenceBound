--[[
	EssenceUpgrades ModuleScript
	----------------------------
	Shared upgrade-tree data + purchase logic for EssenceBound.
	Require this from both client and server.

	REBALANCE NOTES:
		Pass 1: base rate assumption ~1 Earth Essence per 2-3 seconds at game start
		(~0.4/sec). Old tier-1 costs (20-150) took 50-375s each - way too slow.
		BaseCost was cut to roughly 1/8th of the original values, and EffectPerLevel
		was raised (roughly 1.5x-4x depending on the stat) so upgrades feel impactful
		right away.

		Pass 2: the growth curves in pass 1 were too flat - it was cheap to buy ONE
		level of anything and never look back. Every leveled upgrade's CostGrowth
		had its per-level percentage increase multiplied by ~1.35 (a 1.15 growth,
		+15%/level, became roughly 1.20, +20%/level).

		Pass 3 (this one): still too easy to snowball a single node, so growth was
		pushed further - another ~1.4x multiplier on top of pass 2's per-level
		percentage increase (e.g. 1.20 -> 1.28, 1.30 -> 1.42, the steep Shatter
		Force line went from 2.35/3.36 up to 2.89/4.30). Combined with pass 2 this
		roughly doubles the original per-level percentage increase - level 10 of a
		typical 10-rank node now costs dramatically more than level 1, so players
		have to actively spread purchases across the tree instead of dumping
		everything into whichever node they found first. Base costs (level 1 price)
		are still untouched from pass 1, so getting started stays fast.

		One-off upgrades (MaxLevel = 1, CostGrowth = 1) are unaffected since growth
		never applies to them.

		Pass 4 (this one) fixed two real problems pass 3 didn't:
		1) Tier-1 growth had gotten too steep across the board (pass 2 x pass 3
		   compounded to nearly 2x the original per-level rate), so even the FIRST
		   node you level up felt expensive within a few levels, before you have any
		   passive income to lean on. Tier-1 CostGrowth was dialed back down to
		   roughly pass-2 levels so early leveling is cheap and fast again.
		2) Idle Drips and Essence Affinity (the flat passive-income and global-
		   multiplier nodes) were the actual source of "nothing costs enough later" -
		   once maxed they generate so much essence per second that every other
		   node's cost becomes trivial, no matter how steep its own growth is. Their
		   EffectPerLevel was cut hard (idle_drips ~65% weaker, global multiplier
		   ~30-25% weaker) and their own CostGrowth was pushed much steeper
		   (idle_drips_2 to 1.50, global_multiplier_2 to 1.55) so they can't be
		   maxed early and used to trivialize the rest of the tree.
		Everything at Tier 2 and above also got both a base-cost increase (roughly
		1.6x at tier 2, 2x at tier 3, on top of pass 1's numbers) and steeper growth,
		so late-tree purchases stay meaningful even once your income has scaled up.

		Pass 5 (this one): pass 4's tier-1 base costs (2-19) ended up too cheap once
		everything else was in place - a first purchase should feel like a real
		decision, not a rounding error. Tier-1 BaseCost was raised so every level-1
		price falls between 15 (cheap utility nodes) and 70 (the two economy-
		defining nodes, Rebirth Bonus I and Essence Affinity I), spread roughly by
		how impactful each node is relative to its siblings. Tier-2+ costs and every
		CostGrowth value are untouched - tier 2's cheapest node (90) still comfortably
		outprices the new tier-1 ceiling, so progression order is unaffected.

		Pass 6 (this one): pass 5's request was "cheap to start" but a flat growth
		rate applied to a lower base just means the whole curve is uniformly
		cheaper forever - level 10 of a 15-cost/1.20-growth node only reaches ~93.
		To start lower AND still climb past where it used to be, tier-1 BaseCost was
		cut ~35% (10-46 now, down from 15-70) while CostGrowth was steepened
		substantially (e.g. 1.20 -> 1.36, 1.32 -> 1.58). Net effect: level 1 is
		cheaper than before, but by level ~8-10 the same node costs noticeably MORE
		than it did under pass 5's flatter curve - the early game is faster to get
		into, but grinding one node to max is still a real investment.

		Pass 7 (this one): still not steep enough, so growth was pushed hard across
		THE WHOLE TREE this time (not just tier 1) - every leveled upgrade's
		CostGrowth had its per-level percentage increase multiplied by another
		~1.45x (e.g. 1.36 -> 1.52, 1.58 -> 1.84, 4.30 -> 5.78 for Shatter Force II).
		Base costs are untouched everywhere. A 10-rank node that cost ~93 essence at
		level 10 back in pass 4 (15 base, 1.20 growth) now costs orders of magnitude
		more at level 10 off the same-tier base - each additional level of a single
		node is a much bigger ask than buying a new node, which is the intent:
		breadth across the tree should beat depth into one branch.

		Pass 8 (this one): a full cost-to-max audit across every node (summing
		BaseCost * CostGrowth^level for every level) turned up two nodes whose
		total cost was wildly out of line with same-tier siblings, not because
		anyone decided they should be premium sinks (unlike global_multiplier_1/2,
		which pass 4 explicitly called out as intentional late-game control
		valves) but because collection_radius_1/2 happen to carry an unusually
		high MaxLevel (20 and 25, vs the usual 8-10) that pass 7's blanket
		per-level growth multiplier was never re-checked against. More levels at
		the same per-level growth rate compounds a LOT harder: collection_radius_1
		was costing 42,079 total against a tier-1 sibling band of roughly
		900-5,500, and collection_radius_2 was costing 2,259,831 against a tier-2
		band of roughly 3,500-172,000 (excluding the two nodes meant to be
		outliers). Nothing else in the tree was this far outside its own tier's
		band without a documented reason. BaseCost, MaxLevel and EffectPerLevel
		are all untouched (still the same +1.5/+2.4 studs per level, still 20/25
		small steps for a smooth radius curve) - only CostGrowth was brought back
		down (1.46 -> 1.272 and 1.45 -> 1.185) so their totals (~4,483 and
		~34,883) land back inside their tier's normal spread instead of
		outcosting nodes that are strictly more powerful.

	PLAYER DATA SHAPE (you supply/store this however you like - DataStore, profile service, etc):

		playerData = {
			Currencies = {
				Essence = 0,        -- primary essence
				-- [FutureEssenceName] = 0,  <- just add new keys here later, no code changes needed
			},
			RebirthLevel = 0,
			Upgrades = {
				-- [upgradeId] = currentLevel (integer, 0 = not purchased)
			},
		}

	MULTI-ESSENCE COST SUPPORT:
		Every upgrade's BaseCost is a table like {Essence = 50}. When you add new essence
		types later, you can give ANY upgrade (new or existing) a cost table like
		{Essence = 50, Radiance = 10} and everything below (GetCostForNextLevel, CanAfford,
		PurchaseUpgrade) will just work, because they loop over whatever keys exist in the
		cost table instead of hardcoding "Essence". Nothing in this module assumes there is
		only one currency.
]]

local EssenceUpgrades = {}

-- =========================================================================
-- UPGRADE DEFINITIONS
-- =========================================================================
-- Fields:
--   Id               unique string key
--   Name             display name
--   Description      display description
--   Branch           which branch of the tree this sits in (for UI grouping/lines)
--   Tier             depth in the tree (0 = root)
--   Prerequisites    list of upgrade Ids that must be at level >= 1 first
--   RebirthRequired  minimum RebirthLevel needed to unlock this node at all
--   MaxLevel         1 = one-off purchase, >1 = leveled upgrade with that many ranks
--   BaseCost         cost table {CurrencyName = amount} for level 1 (see note above)
--   CostGrowth       multiplier applied to BaseCost per level already owned
--   EffectType       string tag your game code reads to know what this upgrade affects
--   EffectPerLevel   magnitude added per level; total effect = EffectPerLevel * currentLevel
--                    (for one-offs, this is just the flat value granted on purchase)

local Upgrades = {

	-- ===================== ROOT =====================
	{
		Id = "root_awakening", Name = "Essence Awakening",
		Description = "Awaken your bond with essence and unlock the path of ascension. Doubles base essence reward for each level!",
		Branch = "Core", Tier = 0, Prerequisites = {}, RebirthRequired = 0,
		MaxLevel = 5, BaseCost = {EarthEssence = 15}, CostGrowth = 13,
		EffectType = "UnlockTree", EffectPerLevel = 2,
	},

	-- ===================== ORB CORE BRANCH =====================
	{
		Id = "orb_vitality_1", Name = "Orb Vitality I",
		Description = "Increases the Essence Orb's maximum HP, letting it fire more shots before depleting.",
		Branch = "OrbCore", Tier = 1, Prerequisites = {"shatter_force_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 10}, CostGrowth = 1.52,
		EffectType = "OrbMaxHP", EffectPerLevel = 75,
	},
	{
		Id = "orb_vitality_2", Name = "Orb Vitality II",
		Description = "Further reinforces the orb's core, dramatically raising its max HP.",
		Branch = "OrbCore", Tier = 2, Prerequisites = {"orb_vitality_1"}, RebirthRequired = 1,
		MaxLevel = 10, BaseCost = {EarthEssence = 90}, CostGrowth = 1.46,
		EffectType = "OrbMaxHP", EffectPerLevel = 220,
	},
	{
		Id = "orb_vitality_3", Name = "Orb Vitality III",
		Description = "The orb's core becomes near-unbreakable, granting a massive max HP surge.",
		Branch = "OrbCore", Tier = 3, Prerequisites = {"orb_vitality_2"}, RebirthRequired = 3,
		MaxLevel = 10, BaseCost = {EarthEssence = 1880}, CostGrowth = 1.52,
		EffectType = "OrbMaxHP", EffectPerLevel = 700,
	},
	{
		Id = "orb_regen_1", Name = "Orb Regeneration I",
		Description = "Speeds up how quickly the depleted orb recovers HP over time.",
		Branch = "OrbCore", Tier = 1, Prerequisites = {"shatter_force_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 10}, CostGrowth = 1.49,
		EffectType = "OrbRegenRate", EffectPerLevel = 1.2, -- HP/sec
	},
	{
		Id = "orb_regen_2", Name = "Orb Regeneration II",
		Description = "Channels extra essence into the orb's recovery, further boosting regen speed.",
		Branch = "OrbCore", Tier = 2, Prerequisites = {"fracture_efficiency"}, RebirthRequired = 2,
		MaxLevel = 10, BaseCost = {EarthEssence = 120}, CostGrowth = 1.45,
		EffectType = "OrbRegenRate", EffectPerLevel = 3.2,
	},
	{
		Id = "shatter_force_1", Name = "Shatter Force I",
		Description = "Each click shatters off an extra essence orb fragment for collection.",
		Branch = "OrbCore", Tier = 1, Prerequisites = {"root_awakening"}, RebirthRequired = 0,
		MaxLevel = 4, BaseCost = {EarthEssence = 23}, CostGrowth = 2.96,
		EffectType = "OrbsPerClick", EffectPerLevel = 2,
	},
	{
		Id = "shatter_force_2", Name = "Shatter Force II",
		Description = "Splits the orb's shots into wider fragment bursts on every click.",
		Branch = "OrbCore", Tier = 2, Prerequisites = {"shatter_force_1"}, RebirthRequired = 1,
		MaxLevel = 4, BaseCost = {EarthEssence = 350}, CostGrowth = 5.78,
		EffectType = "OrbsPerClick", EffectPerLevel = 3,
	},
	{
		Id = "overload_shots", Name = "Overload Shots",
		Description = "One-off: clicking has a chance to trigger a bonus overload wave of extra orbs.",
		Branch = "OrbCore", Tier = 3, Prerequisites = {"shatter_force_2"}, RebirthRequired = 2,
		MaxLevel = 1, BaseCost = {EarthEssence = 1625}, CostGrowth = 1,
		EffectType = "OverloadWaveChance", EffectPerLevel = 0.15, -- 15% chance
	},
	{
		Id = "fracture_efficiency", Name = "Fracture Efficiency",
		Description = "Reduces the HP cost of each shot, letting the orb fire more times before running dry.",
		Branch = "OrbCore", Tier = 2, Prerequisites = {"orb_regen_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 80}, CostGrowth = 1.46,
		EffectType = "ShotHPCostReduction", EffectPerLevel = 0.05, -- 5% less HP per shot, per level
	},
	{
		Id = "core_resilience", Name = "Core Resilience",
		Description = "One-off: the orb's core never truly fails, always trickling out a slow shot even at 0 HP.",
		Branch = "OrbCore", Tier = 3, Prerequisites = {"orb_regen_2"}, RebirthRequired = 3,
		MaxLevel = 1, BaseCost = {EarthEssence = 1463}, CostGrowth = 1,
		EffectType = "NeverFullyDepleted", EffectPerLevel = 1,
	},

	-- ===================== COLLECTION BRANCH =====================
	{
		Id = "collection_radius_1", Name = "Collection Radius I",
		Description = "Expands the collection circle around your cursor.",
		Branch = "Collection", Tier = 1, Prerequisites = {"root_awakening"}, RebirthRequired = 0,
		-- Pass 8: was CostGrowth 1.46 (42,079 total to max) - wildly above the
		-- rest of tier 1 (~900-5,500) purely because 20 levels compounds much
		-- harder than the usual 8-10. See the pass 8 note up top.
		MaxLevel = 20, BaseCost = {EarthEssence = 10}, CostGrowth = 1.272,
		EffectType = "CollectionRadius", EffectPerLevel = 1.5, -- studs
	},
	{
		Id = "collection_radius_2", Name = "Collection Radius II",
		Description = "Further widens the collection circle for effortless gathering.",
		Branch = "Collection", Tier = 2, Prerequisites = {"collection_radius_1"}, RebirthRequired = 1,
		-- Pass 8: was CostGrowth 1.45 (2,259,831 total to max) for the same
		-- reason as collection_radius_1 above (25 levels, never re-checked).
		MaxLevel = 25, BaseCost = {EarthEssence = 94}, CostGrowth = 1.185,
		EffectType = "CollectionRadius", EffectPerLevel = 2.4,
	},
	{
		Id = "magnetic_pull_1", Name = "Magnetic Pull I",
		Description = "Nearby essence orbs gently drift toward your collection circle.",
		Branch = "Collection", Tier = 1, Prerequisites = {"collection_radius_1"}, RebirthRequired = 0,
		MaxLevel = 8, BaseCost = {EarthEssence = 29}, CostGrowth = 1.62,
		EffectType = "MagnetStrength", EffectPerLevel = 1.0,
	},
	{
		Id = "magnetic_pull_2", Name = "Magnetic Pull II",
		Description = "Strengthens the magnetic pull, drawing essence in from further away.",
		Branch = "Collection", Tier = 2, Prerequisites = {"magnetic_pull_1"}, RebirthRequired = 2,
		MaxLevel = 8, BaseCost = {EarthEssence = 421}, CostGrowth = 1.55,
		EffectType = "MagnetStrength", EffectPerLevel = 2.2,
	},
	{
		Id = "swift_collection_1", Name = "Swift Collection I",
		Description = "Reduces the time an orb needs to sit in your collection circle before it's gathered.",
		Branch = "Collection", Tier = 1, Prerequisites = {"collection_radius_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 10}, CostGrowth = 1.49,
		EffectType = "CollectionSpeed", EffectPerLevel = 0.09, -- seconds shaved off
	},
	{
		Id = "swift_collection_2", Name = "Swift Collection II",
		Description = "Nearly instant collection the moment an orb touches your circle.",
		Branch = "Collection", Tier = 2, Prerequisites = {"swift_collection_1"}, RebirthRequired = 1,
		MaxLevel = 10, BaseCost = {EarthEssence = 101}, CostGrowth = 1.46,
		EffectType = "CollectionSpeed", EffectPerLevel = 0.14,
	},
	{
		Id = "essence_magnet_field", Name = "Essence Magnet Field",
		Description = "One-off: essence within your collection radius is gathered automatically, no hover required.",
		Branch = "Collection", Tier = 3, Prerequisites = {"magnetic_pull_2"}, RebirthRequired = 3,
		MaxLevel = 1, BaseCost = {EarthEssence = 1788}, CostGrowth = 1,
		EffectType = "AutoCollectInRadius", EffectPerLevel = 1,
	},
	{
		Id = "overflow_capacity", Name = "Overflow Capacity",
		Description = "Increases how many essence orbs can exist on screen at once before older ones fade.",
		Branch = "Collection", Tier = 2, Prerequisites = {"collection_radius_2"}, RebirthRequired = 1,
		MaxLevel = 6, BaseCost = {EarthEssence = 150}, CostGrowth = 1.55,
		EffectType = "MaxActiveOrbs", EffectPerLevel = 10,
	},

	-- ===================== CRITICAL ESSENCE BRANCH =====================
	{
		Id = "critical_chance_1", Name = "Critical Chance I",
		Description = "Grants a chance for collected essence to land as a critical, multiplied hit.",
		Branch = "Critical", Tier = 1, Prerequisites = {"root_awakening"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 13}, CostGrowth = 1.58,
		EffectType = "CritChance", EffectPerLevel = 0.02, -- 2% per level
	},
	{
		Id = "critical_chance_2", Name = "Critical Chance II",
		Description = "Sharpens your essence sense, further raising the odds of a critical collect.",
		Branch = "Critical", Tier = 2, Prerequisites = {"critical_chance_1"}, RebirthRequired = 1,
		MaxLevel = 10, BaseCost = {EarthEssence = 160}, CostGrowth = 1.49,
		EffectType = "CritChance", EffectPerLevel = 0.025,
	},
	{
		Id = "critical_chance_3", Name = "Critical Chance III",
		Description = "Attunes you deeply to critical essence, making crits a frequent occurrence.",
		Branch = "Critical", Tier = 3, Prerequisites = {"critical_chance_2"}, RebirthRequired = 3,
		MaxLevel = 10, BaseCost = {EarthEssence = 3126}, CostGrowth = 1.55,
		EffectType = "CritChance", EffectPerLevel = 0.03,
	},
	{
		Id = "critical_multiplier_1", Name = "Critical Multiplier I",
		Description = "Increases how much bonus essence a critical collect grants.",
		Branch = "Critical", Tier = 1, Prerequisites = {"critical_chance_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 16}, CostGrowth = 1.59,
		EffectType = "CritMultiplierBonus", EffectPerLevel = 0.2, -- +0.2x per level
	},
	{
		Id = "critical_multiplier_2", Name = "Critical Multiplier II",
		Description = "Further intensifies critical hits for far larger essence payouts.",
		Branch = "Critical", Tier = 2, Prerequisites = {"critical_multiplier_1"}, RebirthRequired = 2,
		MaxLevel = 10, BaseCost = {EarthEssence = 261}, CostGrowth = 1.52,
		EffectType = "CritMultiplierBonus", EffectPerLevel = 0.4,
	},
	{
		Id = "double_crit", Name = "Double Crit",
		Description = "One-off: a critical hit has a chance to immediately trigger a second critical.",
		Branch = "Critical", Tier = 3, Prerequisites = {"guaranteed_crit_streak"}, RebirthRequired = 3,
		MaxLevel = 1, BaseCost = {EarthEssence = 2438}, CostGrowth = 1,
		EffectType = "DoubleCritChance", EffectPerLevel = 0.25, -- 25% chance to double-proc
	},
	{
		Id = "guaranteed_crit_streak", Name = "Guaranteed Crit Streak",
		Description = "Every so many clicks is guaranteed to critical, and the streak needed shrinks per level.",
		Branch = "Critical", Tier = 3, Prerequisites = {"critical_chance_3"}, RebirthRequired = 4,
		MaxLevel = 5, BaseCost = {EarthEssence = 5000}, CostGrowth = 1.7,
		EffectType = "GuaranteedCritEveryNClicksReduction", EffectPerLevel = 3, -- reduces N by 3 per level
	},

	-- ===================== ESSENCE STORM BRANCH =====================
	{
		Id = "storm_frequency_1", Name = "Storm Frequency I",
		Description = "Shortens the wait between essence storms.",
		Branch = "Storm", Tier = 1, Prerequisites = {"root_awakening"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 13}, CostGrowth = 1.52,
		EffectType = "StormCooldownReduction", EffectPerLevel = 5, -- seconds
	},
	{
		Id = "storm_frequency_2", Name = "Storm Frequency II",
		Description = "Calls essence storms far more often.",
		Branch = "Storm", Tier = 2, Prerequisites = {"storm_frequency_1"}, RebirthRequired = 1,
		MaxLevel = 10, BaseCost = {EarthEssence = 200}, CostGrowth = 1.49,
		EffectType = "StormCooldownReduction", EffectPerLevel = 9,
	},
	{
		Id = "storm_duration_1", Name = "Storm Duration I",
		Description = "Makes essence storms rain for longer.",
		Branch = "Storm", Tier = 1, Prerequisites = {"storm_frequency_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 13}, CostGrowth = 1.52,
		EffectType = "StormDuration", EffectPerLevel = 2.5, -- seconds
	},
	{
		Id = "storm_duration_2", Name = "Storm Duration II",
		Description = "Extends essence storms even further, flooding the skies with essence.",
		Branch = "Storm", Tier = 2, Prerequisites = {"storm_intensity_1"}, RebirthRequired = 2,
		MaxLevel = 10, BaseCost = {EarthEssence = 240}, CostGrowth = 1.52,
		EffectType = "StormDuration", EffectPerLevel = 5,
	},
	{
		Id = "storm_intensity_1", Name = "Storm Intensity I",
		Description = "Increases how much essence falls during a storm.",
		Branch = "Storm", Tier = 1, Prerequisites = {"storm_duration_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 16}, CostGrowth = 1.58,
		EffectType = "StormIntensity", EffectPerLevel = 0.12, -- +12% orb density per level
	},
	{
		Id = "storm_intensity_2", Name = "Storm Intensity II",
		Description = "Thickens the essence rainfall dramatically during storms.",
		Branch = "Storm", Tier = 2, Prerequisites = {"storm_duration_2"}, RebirthRequired = 3,
		MaxLevel = 10, BaseCost = {EarthEssence = 320}, CostGrowth = 1.55,
		EffectType = "StormIntensity", EffectPerLevel = 0.22,
	},
	{
		Id = "manual_storm_summon", Name = "Manual Storm Summon",
		Description = "One-off: unlocks a button to summon an essence storm on demand (its own cooldown).",
		Branch = "Storm", Tier = 3, Prerequisites = {"storm_mastery"}, RebirthRequired = 2,
		MaxLevel = 1, BaseCost = {EarthEssence = 1300}, CostGrowth = 1,
		EffectType = "UnlockManualStorm", EffectPerLevel = 1,
	},
	{
		Id = "storm_mastery", Name = "Storm Mastery",
		Description = "Storms gain a chance to turn golden, showering down massively multiplied essence.",
		Branch = "Storm", Tier = 3, Prerequisites = {"storm_intensity_2"}, RebirthRequired = 4,
		MaxLevel = 8, BaseCost = {EarthEssence = 4376}, CostGrowth = 1.61,
		EffectType = "GoldenStormChance", EffectPerLevel = 0.05,
	},

	-- ===================== REBIRTH BRANCH =====================
	{
		Id = "rebirth_insight_1", Name = "Rebirth Insight I",
		Description = "Lowers the amount of essence needed to reach your next rebirth.",
		Branch = "Rebirth", Tier = 1, Prerequisites = {"root_awakening"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 23}, CostGrowth = 1.59,
		EffectType = "RebirthRequirementReduction", EffectPerLevel = 0.02, -- 2% cheaper per level
	},
	{
		Id = "rebirth_insight_2", Name = "Rebirth Insight II",
		Description = "Grants deeper insight into rebirth, cutting the requirement further still.",
		Branch = "Rebirth", Tier = 2, Prerequisites = {"rebirth_insight_1"}, RebirthRequired = 2,
		MaxLevel = 10, BaseCost = {EarthEssence = 501}, CostGrowth = 1.55,
		EffectType = "RebirthRequirementReduction", EffectPerLevel = 0.03,
	},
	{
		Id = "rebirth_bonus_1", Name = "Rebirth Bonus I",
		Description = "Increases the permanent essence gain boost granted by each rebirth.",
		Branch = "Rebirth", Tier = 1, Prerequisites = {"rebirth_insight_1"}, RebirthRequired = 1,
		MaxLevel = 10, BaseCost = {EarthEssence = 46}, CostGrowth = 1.62,
		EffectType = "RebirthBoostBonus", EffectPerLevel = 0.08, -- +8% extra per rebirth, per level
	},
	{
		Id = "rebirth_bonus_2", Name = "Rebirth Bonus II",
		Description = "Amplifies rebirth boosts even more, making every rebirth far more rewarding.",
		Branch = "Rebirth", Tier = 2, Prerequisites = {"rebirth_insight_1"}, RebirthRequired = 4,
		MaxLevel = 10, BaseCost = {EarthEssence = 1200}, CostGrowth = 1.55,
		EffectType = "RebirthBoostBonus", EffectPerLevel = 0.15,
	},
	{
		Id = "rebirth_echo", Name = "Rebirth Echo",
		Description = "One-off: retain a portion of your essence when you rebirth instead of losing them.",
		Branch = "Rebirth", Tier = 3, Prerequisites = {"rebirth_insight_2"}, RebirthRequired = 3,
		MaxLevel = 1, BaseCost = {EarthEssence = 2275}, CostGrowth = 1,
		EffectType = "RebirthRetainPercent", EffectPerLevel = 0.15, -- keep 15% of essence
	},
	{
		Id = "ascension_insight", Name = "Ascension Insight",
		Description = "Each rebirth grants a bonus amount of Prestige Shards (the currency spent in the Prestige Shop) alongside the usual boost.",
		Branch = "Rebirth", Tier = 3, Prerequisites = {"rebirth_bonus_2","rebirth_bonus_1"}, RebirthRequired = 5,
		MaxLevel = 6, BaseCost = {EarthEssence = 5626}, CostGrowth = 1.61,
		EffectType = "BonusRebirthCurrency", EffectPerLevel = 1,
	},

	-- ===================== PASSIVE / IDLE BRANCH =====================
	{
		Id = "idle_drips_1", Name = "Idle Drips I",
		Description = "Essence slowly seeps in passively, even without clicking.",
		Branch = "Passive", Tier = 1, Prerequisites = {"root_awakening"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 20}, CostGrowth = 1.68,
		EffectType = "PassiveEssencePerSecond", EffectPerLevel = 0.35,
	},
	{
		Id = "idle_drips_2", Name = "Idle Drips II",
		Description = "Widens the passive essence trickle into a steady stream.",
		Branch = "Passive", Tier = 2, Prerequisites = {"idle_drips_1"}, RebirthRequired = 1,
		MaxLevel = 10, BaseCost = {EarthEssence = 200}, CostGrowth = 1.73,
		EffectType = "PassiveEssencePerSecond", EffectPerLevel = 0.7,
	},
	{
		Id = "offline_harvest_1", Name = "Offline Harvest I",
		Description = "Earn a percentage of your passive essence gain while offline.",
		Branch = "Passive", Tier = 1, Prerequisites = {"idle_drips_1"}, RebirthRequired = 0,
		MaxLevel = 10, BaseCost = {EarthEssence = 26}, CostGrowth = 1.59,
		EffectType = "OfflineEarningsPercent", EffectPerLevel = 0.05,
	},
	{
		Id = "offline_harvest_2", Name = "Offline Harvest II",
		Description = "Substantially raises how much essence you earn while away.",
		Branch = "Passive", Tier = 2, Prerequisites = {"offline_harvest_1"}, RebirthRequired = 2,
		MaxLevel = 10, BaseCost = {EarthEssence = 360}, CostGrowth = 1.55,
		EffectType = "OfflineEarningsPercent", EffectPerLevel = 0.08,
	},
	{
		Id = "automation_core", Name = "Automation Core",
		Description = "One-off: the orb periodically fires on its own, without needing a click.",
		Branch = "Passive", Tier = 3, Prerequisites = {"offline_harvest_2","idle_drips_2"}, RebirthRequired = 2,
		MaxLevel = 1, BaseCost = {EarthEssence = 1544}, CostGrowth = 1,
		EffectType = "UnlockAutoClick", EffectPerLevel = 1,
	},
	{
		Id = "global_multiplier_1", Name = "Essence Affinity I",
		Description = "A flat multiplier applied to all essence gained from any source.",
		Branch = "Passive", Tier = 1, Prerequisites = {"idle_drips_1"}, RebirthRequired = 0,
		MaxLevel = 20, BaseCost = {EarthEssence = 46}, CostGrowth = 1.84,
		EffectType = "GlobalEssenceMultiplier", EffectPerLevel = 0.09,
	},
	{
		Id = "global_multiplier_2", Name = "Essence Affinity II",
		Description = "Deepens your affinity for essence, multiplying all gains further still.",
		Branch = "Passive", Tier = 2, Prerequisites = {"global_multiplier_1"}, RebirthRequired = 3,
		MaxLevel = 25, BaseCost = {EarthEssence = 850}, CostGrowth = 1.8,
		EffectType = "GlobalEssenceMultiplier", EffectPerLevel = 0.16,
	},

	-- ===================== CAPSTONES (cross-branch) =====================
	{
		Id = "essence_convergence", Name = "Essence Convergence",
		Description = "One-off: the mastery of orb, crit, storm, and rebirth converges into a colossal essence surge.",
		Branch = "Capstone", Tier = 4,
		Prerequisites = {"twin_orb_manifestation","automation_core","orb_vitality_3", "double_crit", "storm_mastery", "rebirth_bonus_2","essence_magnet_field","orb_regen_2","overload_shots"},
		RebirthRequired = 5,
		MaxLevel = 1, BaseCost = {EarthEssence = 8125}, CostGrowth = 1,
		EffectType = "GlobalEssenceMultiplier", EffectPerLevel = 1.5, -- +150%
	},
	{
		Id = "twin_orb_manifestation", Name = "Twin Orb Manifestation",
		Description = "One-off: manifests a second Essence Orb alongside the first, doubling click yield sources.",
		Branch = "Capstone", Tier = 4, Prerequisites = {"overload_shots","orb_vitality_3"}, RebirthRequired = 5,
		MaxLevel = 1, BaseCost = {EarthEssence = 9750}, CostGrowth = 1,
		EffectType = "UnlockSecondOrb", EffectPerLevel = 1,
	},
	{
		Id = "storm_caller_ascension", Name = "Storm Caller Ascension",
		Description = "Passive essence storms begin summoning themselves automatically, no cooldown consumed.",
		Branch = "Capstone", Tier = 4, Prerequisites = {"manual_storm_summon","storm_frequency_2"}, RebirthRequired = 4,
		MaxLevel = 5, BaseCost = {EarthEssence = 4875}, CostGrowth = 1.61,
		EffectType = "AutoStormChancePerMinute", EffectPerLevel = 0.15,
	},
}

-- =========================================================================
-- INTERNAL LOOKUP
-- =========================================================================

local UpgradesById = {}
for _, def in ipairs(Upgrades) do
	UpgradesById[def.Id] = def
end

EssenceUpgrades.List = Upgrades
EssenceUpgrades.ById = UpgradesById

-- =========================================================================
-- ACCESSORS
-- =========================================================================

function EssenceUpgrades.GetUpgrade(id)
	return UpgradesById[id]
end

function EssenceUpgrades.GetUpgradesByBranch(branch)
	local results = {}
	for _, def in ipairs(Upgrades) do
		if def.Branch == branch then
			table.insert(results, def)
		end
	end
	return results
end

function EssenceUpgrades.GetCurrentLevel(playerData, id)
	return (playerData.Upgrades and playerData.Upgrades[id]) or 0
end

-- Effect value granted at a given level (or the player's current level if omitted)
function EssenceUpgrades.GetUpgradeEffectValue(id, level)
	local def = UpgradesById[id]
	if not def then return 0 end
	return def.EffectPerLevel * level
end

function EssenceUpgrades.GetTotalEffect(playerData, id)
	local level = EssenceUpgrades.GetCurrentLevel(playerData, id)
	return EssenceUpgrades.GetUpgradeEffectValue(id, level)
end

-- Add this to TreeUpgrades.lua, near GetSummedEffect

-- Same as GetSummedEffect, but reads levels off a Player's Attributes
-- instead of a playerData table - for code that only has the Player
-- instance handy (client UI, or server systems that don't want to
-- require() PlayerData just to check a level).
function EssenceUpgrades.GetSummedEffectFromAttributes(player, effectType)
	local total = 0
	for _, def in ipairs(Upgrades) do
		if def.EffectType == effectType then
			local level = player:GetAttribute(def.Id) or 0
			total += def.EffectPerLevel * level
		end
	end
	return total
end
-- =========================================================================
-- COST + UNLOCK LOGIC
-- =========================================================================

-- Returns a cost table {CurrencyName = amount, ...} for purchasing the NEXT level.
-- Works for any currencies present in BaseCost - add new essence types later and
-- this needs no changes.
function EssenceUpgrades.GetCostForNextLevel(id, currentLevel)
	local def = UpgradesById[id]
	if not def then return nil end

	local cost = {}
	local growth = def.CostGrowth ^ currentLevel
	for currency, amount in pairs(def.BaseCost) do
		cost[currency] = math.floor(amount * growth + 0.5)
	end
	return cost
end

function EssenceUpgrades.CanAfford(playerData, cost)
	local currencies = playerData.Essences or {}
	for currency, amount in pairs(cost) do
		if (currencies[currency].Quantity or 0) < amount then
			return false, currency
		end
	end
	return true
end

-- Checks prerequisites (all must be owned at level >= 1) and rebirth gate.
function EssenceUpgrades.IsUnlocked(playerData, id)
	local def = UpgradesById[id]
	if not def then return false, "UnknownUpgrade" end

	if (playerData.Rebirths or 0) < def.RebirthRequired then
		return false, "RebirthLocked"
	end

	for _, prereqId in ipairs(def.Prerequisites) do
		if EssenceUpgrades.GetCurrentLevel(playerData, prereqId) < 1 then
			return false, "PrerequisiteLocked"
		end
	end

	return true
end

function EssenceUpgrades.IsMaxed(playerData, id)
	local def = UpgradesById[id]
	if not def then return true end
	return EssenceUpgrades.GetCurrentLevel(playerData, id) >= def.MaxLevel
end

-- =========================================================================
-- PURCHASE
-- =========================================================================

-- Attempts to buy the next level of `id` for `playerData`.
-- Deducts currency and increments the level in-place on success.
-- Returns: success (bool), reason (string) - reason is nil on success.
-- Reasons: "UnknownUpgrade" | "RebirthLocked" | "PrerequisiteLocked" | "MaxLevel" | "CannotAfford"
function EssenceUpgrades.PurchaseUpgrade(player, playerData, id)
	local def = UpgradesById[id]
	if not def then
		return false, "UnknownUpgrade"
	end

	local unlocked, unlockReason = EssenceUpgrades.IsUnlocked(playerData, id)
	if not unlocked then
		return false, unlockReason
	end

	local currentLevel = EssenceUpgrades.GetCurrentLevel(playerData, id)
	if currentLevel >= def.MaxLevel then
		return false, "MaxLevel"
	end

	local cost = EssenceUpgrades.GetCostForNextLevel(id, currentLevel)
	local affordable, missingCurrency = EssenceUpgrades.CanAfford(playerData, cost)
	if not affordable then
		return false, "CannotAfford", missingCurrency
	end

	-- Deduct cost
	playerData.Essences = playerData.Essences or {}
	for currency, amount in pairs(cost) do
		local stat = player:FindFirstChild("leaderstats"):FindFirstChild(playerData.Essences[currency].DisplayName)
		stat:SetAttribute("Quantity", stat:GetAttribute("Quantity") - amount)
	end

	-- Apply new level
	playerData.Upgrades = playerData.Upgrades or {}
	playerData.Upgrades[id] = currentLevel + 1

	return true, nil
end

-- =========================================================================
-- TREE-WIDE HELPERS
-- =========================================================================

-- Returns every upgrade currently purchasable: unlocked, not maxed, affordable.
function EssenceUpgrades.GetPurchasableUpgrades(playerData)
	local results = {}
	for _, def in ipairs(Upgrades) do
		local unlocked = EssenceUpgrades.IsUnlocked(playerData, def.Id)
		if unlocked and not EssenceUpgrades.IsMaxed(playerData, def.Id) then
			local currentLevel = EssenceUpgrades.GetCurrentLevel(playerData, def.Id)
			local cost = EssenceUpgrades.GetCostForNextLevel(def.Id, currentLevel)
			if EssenceUpgrades.CanAfford(playerData, cost) then
				table.insert(results, def.Id)
			end
		end
	end
	return results
end

-- Returns every upgrade the player has unlocked (whether or not they've bought it yet),
-- useful for drawing the tree UI (locked nodes still show, but greyed out).
function EssenceUpgrades.GetVisibleTree(playerData)
	local results = {}
	for _, def in ipairs(Upgrades) do
		local unlocked = EssenceUpgrades.IsUnlocked(playerData, def.Id)
		table.insert(results, {
			Id = def.Id,
			Name = def.Name,
			Branch = def.Branch,
			Tier = def.Tier,
			Prerequisites = def.Prerequisites,
			Unlocked = unlocked,
			CurrentLevel = EssenceUpgrades.GetCurrentLevel(playerData, def.Id),
			MaxLevel = def.MaxLevel,
		})
	end
	return results
end

-- Sums a given EffectType across all owned upgrades - e.g. add up every
-- source of "GlobalEssenceMultiplier" into one final multiplier.
function EssenceUpgrades.GetSummedEffect(playerData, effectType)
	local total = 0
	for _, def in ipairs(Upgrades) do
		if def.EffectType == effectType then
			total += EssenceUpgrades.GetTotalEffect(playerData, def.Id)
		end
	end
	return total
end

return EssenceUpgrades
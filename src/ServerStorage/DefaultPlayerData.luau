--[[
	DefaultPlayerData.lua (ModuleScript)
	Place in: ServerStorage

	This is the template for a fresh player's data. It gets CLONED per
	player by PlayerDataHandler and parented under them — never required
	directly for live data, only used as the clone source and as a
	structural reference for merging saved values.

	To add a new stat later: just add a field here. Returning players
	will automatically get it (see PlayerDataHandler's merge logic) —
	no migration script needed.
]]

local DefaultPlayerData = {
	PlayTime = 0,                 -- seconds
	TotalEssenceGathered = 0,
	CriticalEssence = 0,
	RarestEssence = "None",
	RebirthCurrency = 0,
	Rebirths = 0,
	-- Weekly leaderboard baseline (see LeaderboardService's "This Week"
	-- board) -- WeeklyBaselineValue is the player's TotalEssenceGathered
	-- reading the moment their tracking for WeeklyBaselineWeekNumber
	-- started; "gained this week" = TotalEssenceGathered - that baseline.
	-- Reset automatically whenever the current UTC week number moves past
	-- WeeklyBaselineWeekNumber, so nobody needs to touch this by hand.
	WeeklyBaselineWeekNumber = 0,
	WeeklyBaselineValue = 0,
	RobuxSpent = 0,
	UniqueEssences = 0,
	LastLeaveTime = 0,
	ManualStormsSummoned = 0,
	-- Unix timestamp of this player's first-ever join, stamped ONCE by
	-- PlayerDataHandler.server.luau the moment a genuinely brand-new save
	-- is created (never for a returning player, even one whose old save
	-- predates this field -- see that file's loadPlayerData for exactly
	-- how those two cases are told apart). 0 means "not eligible", not
	-- "just joined" -- drives NewPlayerLuckConfig's first-24-hours crit
	-- boost and nothing else.
	FirstJoinAt = 0,
	SeenTutorial = false,
	-- Forces the very first orb a player ever spawns to land as a
	-- guaranteed critical (see OrbClicker.client.luau). A new player's
	-- first click otherwise had a real chance of landing on the single
	-- least exciting outcome available -- this guarantees their first
	-- taste of the game's biggest visual payoff instead of leaving it to
	-- a 0% base crit chance and a 20-click guaranteed-streak wait.
	SeenFirstCrit = false,
	-- Gates the one-time 50-essence starter gift TutorialStarterGiftService
	-- grants when the tutorial's Upgrades step begins, so a brand-new
	-- player can actually afford to buy something during the tutorial
	-- instead of just being shown a menu they can't use yet.
	SeenTutorialStarterGift = false,
	-- Gates PromptFav.client.luau's one-time favorite prompt. Was previously
	-- an unconditional loop re-prompting every 5 minutes forever with no
	-- persisted memory at all -- this flag is what makes "one time" actually
	-- mean once, across rejoins too, not just within a single session.
	SeenFavoritePrompt = false,
	-- Gates the "What's New" popup (WhatsNewConfig.CurrentVersion). Starts
	-- at 0 so every existing save is behind version 1 and sees it once;
	-- bumping CurrentVersion later re-triggers the popup for everyone,
	-- same mechanism as a streak or tutorial flag, just numeric instead
	-- of boolean so it can track which version was last acknowledged.
	SeenWhatsNewVersion = 0,
	Badges = {
		[3032854636359044] = false, --- First Steps
		[4008378896042305] = false, -- Welcome to the grind
		[1189564550645111] = false, -- Essence Hoarder
		[4077164450257078] = false, --Essence Baron
		[2522508290427820] = false, -- First Rebirth
		[2435657570989542] = false, -- reborn again and again
		[2662901027091325] = false, -- critical hit
		[4281764202448916] = false, -- storm caller
		[2767213148031403] = false, -- Storm Chaser
		[3091905792121753] = false, -- Storm Watcher
		[1472053267504184] = false, -- It Has Noticed You
		[3749419964014047] = false, -- Nothing Left Hidden
		[1219109424164715] = false, -- Playtester
	},
	Gamepasses = {
		--Dedicated Essence
		[1907077899] = {
			Owned = false,
		},
		--Material Alchemist (Offline Collection)
		[1907863864] = {
			Owned = false,
		},
		--Auto Absorbtion
		[1907677938] = {
			Owned = false,
		},
		--Ultra Luck (+300%)
		[1906063939] = {
			Owned = false,
		},
		--Lucky Finder (+50% Luck)
		[1907239833] = {
			Owned = false,
		},
		--VIP Rank
		[1909291891] = {
			Owned = false,
		},
		--2x Essence Multiplier
		[1907605899] = {
			Owned = false,
		},
	},
	HollowedMilestones = {
		["HollowMilestone1"] = false,
		["HollowMilestone2"] = false,
		["HollowMilestone3"] = false,
		["HollowMilestone4"] = false,
		["HollowMilestone5"] = false,
		["HollowMilestone6"] = false
	},
	Essences = {
		EarthEssence = {
			Quantity = 0,
			Discovered = false,
			Rarity = 0,
			DisplayName = "Earth Essence",
			savedEPM = 0
		},
		["Shadow Essence"] = {
			Quantity = 0,
			Discovered = false,
			Rarity = 1,
			DisplayName = "Shadow Essence",
			savedEPM = 0
		},
		-- Add more essence types here later, e.g.:
		-- FireEssence = { Quantity = 0 },
	},
	
	Upgrades = {},

	-- Total Shadow Essence ever EARNED, which only ever increases.
	--
	-- EssenceMultiplier grants a bonus from Shadow Essence. If that read the
	-- current balance, then spending it in the Shadow Sanctum would directly
	-- reduce the player's own multiplier -- a trap where using the shop is a
	-- downgrade. Basing the bonus on lifetime earnings instead means
	-- spending costs the balance but never the power already earned.
	--
	-- Existing saves are migrated on load (see PlayerDataHandler): a player
	-- whose lifetime total is behind their current balance has it raised to
	-- match, so nobody loses multiplier when this field first appears.
	LifetimeShadowEssence = 0,

	-- [upgradeId] = level, for the Shadow Sanctum (see SanctumUpgrades).
	-- Kept separate from Upgrades so a rebirth, which wipes the Earth
	-- Essence tree, never touches what Shadow Essence bought.
	SanctumUpgrades = {},

	-- [upgradeId] = level, for the Prestige Shop (see RebirthShopUpgrades).
	-- Kept separate from Upgrades for the same reason as SanctumUpgrades --
	-- RebirthCurrency itself is the one currency that ONLY ever accumulates
	-- across rebirths, so what it buys has to survive the Earth tree wipe
	-- a rebirth performs, or the whole currency would be pointless.
	RebirthShopUpgrades = {},

	-- [milestoneId] = true, for AchievementsService. Kept independent of
	-- the Badges table (Roblox platform badges) since Milestones are this
	-- game's own goals with real claimable rewards -- once claimed, a
	-- milestone must never pay out twice, and must survive a rebirth (the
	-- goals it tracks, like TotalEssenceGathered, are lifetime stats that
	-- a rebirth doesn't reset either).
	ClaimedMilestones = {},

	-- Daily streak / daily quest state, driven by ProgressionService.
	-- Quest progress is stored by SLOT INDEX (1..QuestsPerDay) rather than
	-- by quest id on purpose: the save merge in PlayerDataHandler only
	-- overwrites keys present in the new data, so fixed slots that are
	-- rewritten every day can't leave stale per-quest-id progress sitting
	-- in the DataStore to be picked up later when a quest rotates back in.
	Progression = {
		LastClaimDay = 0,        -- UTC day number of the last daily claim
		Streak = 0,
		BestStreak = 0,
		QuestDay = 0,            -- UTC day number the current quests are for
		QuestRebirths = 0,       -- rebirth count when those quests were rolled
		QuestProgress = { 0, 0, 0 },
		QuestClaimed = { false, false, false },
		TotalQuestsCompleted = 0,
		TotalDailiesClaimed = 0,
		-- Bankable, earned automatically at every 7-day streak milestone --
		-- see ProgressionConfig's "STREAK FREEZES" note. (Was previously
		-- only normalized at runtime in ProgressionService.getProgression,
		-- never listed here -- harmless, since that normalization already
		-- guarantees 0 for every save either way, but every sibling field
		-- above has a template default too, so this belongs here for the
		-- same self-documenting reason they do.)
		StreakFreezes = 0,
		-- [CODE] = true for each promo code already redeemed. Keyed by
		-- code string on purpose -- these entries should persist forever
		-- so a code can never be redeemed twice.
		RedeemedCodes = {},
	},

	-- Fortune Wheel state, driven by WheelService. Tickets are earned by
	-- collecting orbs (WheelConfig.CollectionsPerTicket) and spent on
	-- spins; LastSpinAt is a timestamp, not a day number like the daily
	-- streak's LastClaimDay -- the free spin runs on its own rolling 24h
	-- cooldown from your last spin, not a shared UTC day boundary.
	Wheel = {
		Tickets = 0,
		CollectionsSinceLastTicket = 0,
		LastSpinAt = 0,
	},

	-- Zones state, driven by ZoneService (see ZonesConfig for what a zone
	-- actually changes -- essentially just the Earth/Shadow essence roll
	-- weighting). earth_zone is the only zone ever unlocked by default --
	-- everything else has to be bought with essence, once, permanently.
	-- Switching between already-unlocked zones is free and unlimited.
	Zones = {
		Current = "earth_zone",
		Unlocked = { earth_zone = true },
	},

	Settings = {
		["Music"] = true,
		["SFX"] = true,
	},
}

return DefaultPlayerData
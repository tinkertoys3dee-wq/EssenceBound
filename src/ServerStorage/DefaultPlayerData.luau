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
	RobuxSpent = 0,
	UniqueEssences = 0,
	LastLeaveTime = 0,
	ManualStormsSummoned = 0,
	SeenTutorial = false,
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
	
	Settings = {
		["Music"] = true,
		["SFX"] = true,
	},
}

return DefaultPlayerData
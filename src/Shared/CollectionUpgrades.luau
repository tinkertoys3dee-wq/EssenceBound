--[[
	CollectionUpgrades ModuleScript
	-------------------------------
	Place in: ReplicatedStorage (alongside RebirthHandler, Remotes, etc.)

	Centralizes all "Collection" branch upgrade math so scripts that care
	about collection behavior (the ring, orb movement, orb spawning) don't
	each re-implement the same level -> effect lookups.

	UPGRADE LEVEL SOURCE:
		Upgrade levels are NOT read from EssenceUpgrades/PlayerData here.
		Per your setup, each upgrade's current level is stored directly as
		a NumberValue-style attribute on the Player instance, e.g.:

			player:GetAttribute("collection_radius_1") == 3

		If an attribute hasn't been set yet, it's treated as level 0.

	These EffectPerLevel / MaxLevel numbers are mirrored from the
	"Collection" branch of EssenceUpgrades - keep them in sync if that
	module's values ever change.
]]

local CollectionUpgrades = {}

-- =========================================================================
-- UPGRADE DEFINITIONS (Collection branch only)
-- =========================================================================
local treeUpgrades = require(script.Parent.TreeUpgrades)
-- Timed lookup rather than a bare WaitForChild: a missing SanctumUpgrades
-- must cost the Sanctum bonus only, not hang collection entirely.
local SanctumUpgrades
do
	local module = script.Parent:FindFirstChild("SanctumUpgrades")
		or script.Parent:WaitForChild("SanctumUpgrades", 10)

	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			SanctumUpgrades = result
		end
	end
end
local RADIUS_UPGRADES = {
	{ Id = "collection_radius_1", 
		EffectPerLevel = treeUpgrades.GetUpgrade("collection_radius_1").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("collection_radius_1").MaxLevel},
	{ Id = "collection_radius_2", 
		EffectPerLevel = treeUpgrades.GetUpgrade("collection_radius_2").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("collection_radius_2").MaxLevel},
}

local MAGNET_UPGRADES = {
	{ Id = "magnetic_pull_1", 
		EffectPerLevel = treeUpgrades.GetUpgrade("magnetic_pull_1").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("magnetic_pull_1").MaxLevel},
	{ Id = "magnetic_pull_2", 
		EffectPerLevel = treeUpgrades.GetUpgrade("magnetic_pull_2").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("magnetic_pull_2").MaxLevel},
}

local SPEED_UPGRADES = {
	{ Id = "swift_collection_1", 
		EffectPerLevel = treeUpgrades.GetUpgrade("swift_collection_1").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("swift_collection_1").MaxLevel},
	{ Id = "swift_collection_2", 
		EffectPerLevel = treeUpgrades.GetUpgrade("swift_collection_2").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("swift_collection_2").MaxLevel},
}

local MAX_ACTIVE_ORB_UPGRADES = {
	{ Id = "overflow_capacity", 
		EffectPerLevel = treeUpgrades.GetUpgrade("overflow_capacity").EffectPerLevel, 
		MaxLevel = treeUpgrades.GetUpgrade("overflow_capacity").MaxLevel},
}

local AUTO_COLLECT_UPGRADE_ID = "essence_magnet_field" -- one-off unlock

-- All attribute ids this module cares about, flattened - handy for scripts
-- that want to hook GetAttributeChangedSignal for every relevant upgrade.
local ALL_UPGRADE_IDS = {}
do
	local function collect(list)
		for _, def in ipairs(list) do
			table.insert(ALL_UPGRADE_IDS, def.Id)
		end
	end
	collect(RADIUS_UPGRADES)
	collect(MAGNET_UPGRADES)
	collect(SPEED_UPGRADES)
	collect(MAX_ACTIVE_ORB_UPGRADES)
	table.insert(ALL_UPGRADE_IDS, AUTO_COLLECT_UPGRADE_ID)
	-- Included so WatchAll fires when a Sanctum purchase changes the ring
	-- size -- without this the ring would keep its old radius until
	-- something else happened to trigger a recalculation.
	table.insert(ALL_UPGRADE_IDS, "sanctum_wider_reach")
end
CollectionUpgrades.AllUpgradeIds = ALL_UPGRADE_IDS

-- =========================================================================
-- INTERNAL HELPERS
-- =========================================================================

local function getLevel(player, upgradeId)
	return player:GetAttribute(upgradeId) or 0
end

local function sumEffect(player, upgradeList)
	local total = 0
	for _, def in ipairs(upgradeList) do
		local level = getLevel(player, def.Id)
		if level > def.MaxLevel then
			level = def.MaxLevel
		end
		total += def.EffectPerLevel * level
	end
	return total
end

-- =========================================================================
-- PUBLIC ACCESSORS
-- =========================================================================

-- Extra radius (added on top of a base size) from collection_radius_1/2,
-- plus the Shadow Sanctum's Wider Reach. The two stack additively so the
-- Shadow economy complements the Earth Essence tree rather than replacing
-- it.
function CollectionUpgrades.GetCollectionRadiusBonus(player)
	local sanctumReach = 0
	if SanctumUpgrades then
		sanctumReach = tonumber(SanctumUpgrades.GetPlayerEffect(player, "sanctum_wider_reach")) or 0
	end
	return sumEffect(player, RADIUS_UPGRADES) + sanctumReach
end

-- Combined pull strength from magnetic_pull_1/2 (for whatever script moves
-- orbs toward the player - this module just does the level math).
function CollectionUpgrades.GetMagnetStrength(player)
	return sumEffect(player, MAGNET_UPGRADES)
end

-- Seconds shaved off however long an orb needs to dwell before collecting.
function CollectionUpgrades.GetCollectionSpeedBonus(player)
	return sumEffect(player, SPEED_UPGRADES)
end

-- Extra concurrent active orbs allowed on screen (for the orb spawner).
function CollectionUpgrades.GetMaxActiveOrbsBonus(player)
	return sumEffect(player, MAX_ACTIVE_ORB_UPGRADES)
end

-- Whether the player has purchased essence_magnet_field (auto-collect
-- anything inside the radius, no dwell/hover required).
function CollectionUpgrades.HasAutoCollect(player)
	return getLevel(player, AUTO_COLLECT_UPGRADE_ID) >= 1
end

-- Convenience: final ring diameter given a base size, in the same units
-- (UI pixels) the ring Frame's Size already uses.
function CollectionUpgrades.GetRingSize(player, baseSize)
	return baseSize + (CollectionUpgrades.GetCollectionRadiusBonus(player) * 2)
end

-- Subscribes `callback` to fire whenever any Collection-branch upgrade
-- attribute changes on `player`. Returns a table of the RBXScriptConnections
-- so the caller can disconnect them later if needed.
function CollectionUpgrades.WatchAll(player, callback)
	local connections = {}
	for _, id in ipairs(ALL_UPGRADE_IDS) do
		table.insert(connections, player:GetAttributeChangedSignal(id):Connect(callback))
	end
	return connections
end

return CollectionUpgrades
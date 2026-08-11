--[[
	ZonesConfig (ModuleScript -> ReplicatedStorage)
	===================================================
	Data + shared helpers for Zones: a player picks which "zone" they're
	collecting in, and each zone weights the complete essence catalog.
	Earthen Grove favors Earth, Shadowfen favors Shadow, and the Rebirth-4
	Sunforge heavily favors Solar. Every zone still has a non-zero chance
	for all three, so a mythic Solar discovery is possible before its
	dedicated destination without making that destination irrelevant.

	There's still only ONE orb to click (EssenceOrbController's HP/Fire
	mechanics are completely untouched by any of this) -- "zones" are a
	reskin of the same click loop with a different essence-type roll under
	it, not a second physical map to build and maintain. ZoneAmbience.
	client.luau is what makes it actually look and feel like somewhere
	different.

	Wires up the "Dedicated Essence" Game Pass (id 1907077899), previously
	a pure stub -- see NEW_SYSTEMS.md's "THREE PAID GAMEPASSES DO NOTHING"
	section -- with a meaning that actually matches its name: owning it
	sharpens whichever zone you're standing in toward its specialty
	further. Pure upside for anyone who already bought it; it simply did
	nothing before.

	Also applies LuckGamepassConfig's Lucky Finder / Ultra Luck multiplier
	to every non-common weight. Their real store text says "rarer essences,"
	so both rare Shadow and mythic Solar benefit while common Earth remains
	the baseline. Multiplying weights (rather than forcing exact target
	percentages) keeps the bonuses composable across all three zones.

	GetEssence.luau (the actual roll) and ZoneService.server.luau (unlock/
	switch + attribute mirroring) both read this; ZonePanel.client.luau
	(the picker UI) and ZoneAmbience.client.luau (the persistent per-zone
	orb reskin) do too, so every surface always agrees on names, costs,
	and odds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LuckGamepassConfig = require(ReplicatedStorage:WaitForChild("LuckGamepassConfig"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local ZonesConfig = {}

ZonesConfig.DedicatedEssenceGamepassId = 1907077899

-- The actual collectible-orb art used by OrbClicker.client.luau. Zone cards
-- and the travel reveal read this mapping so the preview a player sees is
-- the same essence orb that falls after arrival, not a lookalike emoji.
-- Earthen Grove still leaves LargeOrb.Image itself Studio-authored (see its
-- zone entry below); this table is specifically the explicit menu/transition
-- preview for each zone's specialty essence.
ZonesConfig.EssenceOrbImages = {
	["Earth Essence"] = EssenceConfig.GetIconImage("Earth Essence"),
	["Shadow Essence"] = EssenceConfig.GetIconImage("Shadow Essence"),
	["Solar Essence"] = EssenceConfig.GetIconImage("Solar Essence"),
}

-- Ordered: index 1 is the default/fallback zone for any player who
-- somehow has no valid CurrentZoneId (never happens in practice, but
-- keeps every reader below safe without a special nil case).
ZonesConfig.Zones = {
	{
		Id = "earth_zone",
		Name = "Earthen Grove",
		Icon = "🌍",
		Description = "The living grove. Earth dominates, with rare Shadow and mythic Solar traces.",
		Color = Color3.fromRGB(120, 200, 110),
		SpecialtyEssence = "Earth Essence",
		EssenceOrbImage = ZonesConfig.EssenceOrbImages["Earth Essence"],
		UnlockCost = 0, -- always unlocked
		UnlockCosts = {},
		RebirthRequired = 0,
		BaseWeights = { ["Earth Essence"] = 81, ["Shadow Essence"] = 18, ["Solar Essence"] = 1 },
		AmplifiedWeights = { ["Earth Essence"] = 92, ["Shadow Essence"] = 7, ["Solar Essence"] = 1 },
		-- No OrbImage -- ZoneAmbience.client.luau keeps whatever LargeOrb's
		-- own Image already is for this zone, captured once at load rather
		-- than a second hardcoded asset id here that could drift out of
		-- sync with whatever the real default actually is in Studio.
	},
	{
		Id = "shadow_zone",
		Name = "The Shadowfen",
		Icon = "🌑",
		Description = "A fog-choked hollow. Shadow dominates, with Earth and mythic Solar traces.",
		Color = Color3.fromRGB(150, 90, 220),
		SpecialtyEssence = "Shadow Essence",
		EssenceOrbImage = ZonesConfig.EssenceOrbImages["Shadow Essence"],
		UnlockCost = 300,
		UnlockCosts = { EarthEssence = 300 },
		RebirthRequired = 0,
		BaseWeights = { ["Earth Essence"] = 17, ["Shadow Essence"] = 82, ["Solar Essence"] = 1 },
		AmplifiedWeights = { ["Earth Essence"] = 7, ["Shadow Essence"] = 92, ["Solar Essence"] = 1 },
		-- ZoneAmbience applies this to the giant center orb on every switch
		-- (including initial spawn into an already-selected Shadow zone).
		OrbImage = ZonesConfig.EssenceOrbImages["Shadow Essence"],
	},
	{
		Id = "solar_zone",
		Name = "The Sunforge",
		Icon = "☀️",
		Description = "A stellar foundry above the clouds, overflowing with mythic Solar Essence.",
		Color = Color3.fromRGB(255, 176, 54),
		SpecialtyEssence = "Solar Essence",
		EssenceOrbImage = ZonesConfig.EssenceOrbImages["Solar Essence"],
		-- Multi-currency, server-authoritative unlock. Solar itself is not
		-- required, avoiding a catch-22 for players who have not hit the 1%
		-- global discovery yet.
		UnlockCost = 500000, -- legacy/primary-cost compatibility
		UnlockCosts = { EarthEssence = 500000, ["Shadow Essence"] = 25000 },
		RebirthRequired = 4,
		BaseWeights = { ["Earth Essence"] = 15, ["Shadow Essence"] = 15, ["Solar Essence"] = 70 },
		AmplifiedWeights = { ["Earth Essence"] = 6, ["Shadow Essence"] = 6, ["Solar Essence"] = 88 },
		-- ZoneAmbience and ZonePanel both resolve the uploaded Solar art
		-- through EssenceVisuals, which retains a native fallback if the
		-- catalog asset id is ever intentionally cleared.
	},
}

local zonesById = {}
for _, zone in ipairs(ZonesConfig.Zones) do
	zonesById[zone.Id] = zone
end

function ZonesConfig.GetZoneById(zoneId)
	if type(zoneId) ~= "string" then
		return nil
	end
	return zonesById[zoneId]
end

function ZonesConfig.UnlockedAttributeName(zoneId)
	return "Zone_" .. zoneId .. "_Unlocked"
end

-- The very first zone never needs a purchase, so it never needs its own
-- attribute check either -- true unconditionally, same as the game
-- treating it as unlocked in DefaultPlayerData.luau's Zones.Unlocked
-- table without anything ever having to buy it.
function ZonesConfig.IsZoneUnlocked(player, zoneId)
	local zone = ZonesConfig.GetZoneById(zoneId)
	if not zone then
		return false
	end
	if not next(zone.UnlockCosts or {}) then
		return true
	end
	if not player then
		return false
	end
	return player:GetAttribute(ZonesConfig.UnlockedAttributeName(zoneId)) == true
end

function ZonesConfig.GetUnlockCosts(zoneOrId)
	local zone = type(zoneOrId) == "table" and zoneOrId or ZonesConfig.GetZoneById(zoneOrId)
	if not zone then
		return {}
	end
	local costs = {}
	for currency, amount in pairs(zone.UnlockCosts or {}) do
		costs[currency] = amount
	end
	return costs
end

-- Falls back to the default zone for a missing/invalid/not-yet-replicated
-- attribute -- never nil, since every caller below treats this as always
-- resolving to a real zone.
function ZonesConfig.GetCurrentZoneId(player)
	if player then
		local id = player:GetAttribute("CurrentZoneId")
		if ZonesConfig.GetZoneById(id) then
			return id
		end
	end
	return ZonesConfig.Zones[1].Id
end

function ZonesConfig.GetCurrentZone(player)
	return ZonesConfig.GetZoneById(ZonesConfig.GetCurrentZoneId(player)) or ZonesConfig.Zones[1]
end

-- The actual roll table GetEssence.luau spins against: the current zone's
-- weights, sharpened if the player owns Dedicated Essence, then further
-- sharpened toward every non-common essence if they own Lucky Finder
-- and/or Ultra Luck. Safe to call with a nil player (returns the default
-- zone's base weights, unmultiplied) so GetEssence never has to
-- special-case a missing player itself.
function ZonesConfig.GetEssenceWeightsForZone(zoneOrId, player)
	local zone = type(zoneOrId) == "table" and zoneOrId or ZonesConfig.GetZoneById(zoneOrId)
	zone = zone or ZonesConfig.Zones[1]
	local owned = player
		and player:GetAttribute(MonetizationConfig.GetOwnershipAttribute(ZonesConfig.DedicatedEssenceGamepassId)) == true
	local weights = (owned and zone.AmplifiedWeights) or zone.BaseWeights

	-- Copied rather than returned directly -- callers are free to treat
	-- this as scratch data without ever risking a mutation reaching back
	-- into this module's own zone config.
	local copy = {}
	for essenceName, weight in pairs(weights) do
		copy[essenceName] = weight
	end

	if player then
		local rareMultiplier = LuckGamepassConfig.GetRareEssenceMultiplier(player)
		for essenceName, weight in pairs(copy) do
			if EssenceConfig.IsRare(essenceName) then
				copy[essenceName] = weight * rareMultiplier
			end
		end
	end

	return copy
end

function ZonesConfig.GetEssenceWeights(player)
	return ZonesConfig.GetEssenceWeightsForZone(ZonesConfig.GetCurrentZone(player), player)
end

return ZonesConfig

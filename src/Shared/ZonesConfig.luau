--[[
	ZonesConfig (ModuleScript -> ReplicatedStorage)
	===================================================
	Data + shared helpers for Zones: a player picks which "zone" they're
	collecting in, and each zone weights the Earth/Shadow essence roll
	differently -- Zone 1 (Earthen Grove, always unlocked) favors Earth
	Essence, Zone 2 (The Shadowfen, costs essence to unlock) favors Shadow
	Essence. Both zones still drop BOTH essence types on purpose -- picking
	a zone is about leaning into a currency, never locking the other one
	out, so nobody's stuck unable to discover Shadow Essence at all just
	because they haven't unlocked Zone 2 yet.

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

	GetEssence.luau (the actual roll) and ZoneService.server.luau (unlock/
	switch + attribute mirroring) both read this; ZonePanel.client.luau
	(the picker UI) and ZoneAmbience.client.luau (the persistent per-zone
	orb reskin) do too, so every surface always agrees on names, costs,
	and odds.
]]

local ZonesConfig = {}

ZonesConfig.DedicatedEssenceGamepassId = 1907077899

-- Ordered: index 1 is the default/fallback zone for any player who
-- somehow has no valid CurrentZoneId (never happens in practice, but
-- keeps every reader below safe without a special nil case).
ZonesConfig.Zones = {
	{
		Id = "earth_zone",
		Name = "Earthen Grove",
		Icon = "🌍",
		Description = "The grove you started in. Leans Earth Essence, but Shadow still turns up.",
		Color = Color3.fromRGB(120, 200, 110),
		UnlockCost = 0, -- always unlocked
		BaseWeights = { ["Earth Essence"] = 82, ["Shadow Essence"] = 18 },
		AmplifiedWeights = { ["Earth Essence"] = 92, ["Shadow Essence"] = 8 }, -- w/ Dedicated Essence
	},
	{
		Id = "shadow_zone",
		Name = "The Shadowfen",
		Icon = "🌑",
		Description = "A fog-choked hollow. Leans Shadow Essence, but Earth still turns up.",
		Color = Color3.fromRGB(150, 90, 220),
		UnlockCost = 300,
		BaseWeights = { ["Earth Essence"] = 18, ["Shadow Essence"] = 82 },
		AmplifiedWeights = { ["Earth Essence"] = 8, ["Shadow Essence"] = 92 },
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
	if zone.UnlockCost <= 0 then
		return true
	end
	if not player then
		return false
	end
	return player:GetAttribute(ZonesConfig.UnlockedAttributeName(zoneId)) == true
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
-- weights, sharpened if the player owns Dedicated Essence. Safe to call
-- with a nil player (returns the default zone's base weights) so
-- GetEssence never has to special-case a missing player itself.
function ZonesConfig.GetEssenceWeights(player)
	local zone = ZonesConfig.GetCurrentZone(player)
	local owned = player and player:GetAttribute(ZonesConfig.DedicatedEssenceGamepassId) == true
	local weights = (owned and zone.AmplifiedWeights) or zone.BaseWeights

	-- Copied rather than returned directly -- callers are free to treat
	-- this as scratch data without ever risking a mutation reaching back
	-- into this module's own zone config.
	local copy = {}
	for essenceName, weight in pairs(weights) do
		copy[essenceName] = weight
	end
	return copy
end

return ZonesConfig

--[[
	LuckGamepassConfig (ModuleScript -> ReplicatedStorage)
	==========================================================
	Wires up "Lucky Finder" and "Ultra Luck" -- two of the three Game
	Passes flagged in NEW_SYSTEMS.md's "THREE PAID GAMEPASSES DO NOTHING"
	section as pure stubs: real Robux, a flag set, nothing in the entire
	codebase ever read it. The third, "Dedicated Essence", is wired
	separately in ZonesConfig.luau.

	REAL STORE DESCRIPTIONS (an earlier pass guessed crit chance --
	wrong; this replaces it)
	--------------------------------------------------------------------
	Lucky Finder: "Increases the base chance of finding rarer essences
	by 50%."
	Ultra Luck: "Stacks with regular luck to give a massive boost
	(x3 luck)."

	"Rarer essences" means Shadow Essence specifically -- the only two
	essence types in the game are EarthEssence (Rarity 0) and Shadow
	Essence (Rarity 1), see DefaultPlayerData.luau. Hardcoded to Shadow
	Essence by name rather than built as a generic "find the highest-
	Rarity type" lookup, since there are only ever two types right now --
	the same "don't build generality nothing needs yet" call ZonesConfig
	already makes for its own two zones.

	THE MATH BEHIND x1.5 / x2 / x3
	------------------------------------
	Lucky Finder's own "+50%" is unambiguous: x1.5 alone. Ultra Luck's
	text describes the STACKED total with Lucky Finder as "x3 luck", not
	its own standalone value -- so Ultra Luck's own multiplier is set to
	x2, chosen specifically so 1.5 (Lucky Finder) * 2 (Ultra Luck) = 3,
	matching that "x3 luck" headline exactly when both are owned. Someone
	who buys ONLY Ultra Luck (skipping "regular luck") still gets a real,
	standalone x2 -- there's no reasonable default that makes an
	Ultra-Luck-only purchase do nothing just because the marketing copy
	assumes it's bought alongside Lucky Finder.

	WHERE THIS APPLIES
	--------------------
	Multiplies the Shadow Essence WEIGHT ZonesConfig.GetEssenceWeights
	returns, whichever zone the player is currently in -- not a fixed
	target probability. Both the real roll (GetEssence.luau) and the
	odds preview (ZonePanel.client.luau) read that one function, so
	wiring it there once means neither can ever show a number the other
	doesn't actually roll against.
]]

local LuckGamepassConfig = {}

LuckGamepassConfig.LuckyFinderGamepassId = 1907239833
LuckGamepassConfig.UltraLuckGamepassId = 1906063939

LuckGamepassConfig.LuckyFinderMultiplier = 1.5 -- "+50%", alone
LuckGamepassConfig.UltraLuckMultiplier = 2.0    -- combines with Lucky Finder's 1.5x to make exactly x3

-- 1 (no-op) for a player who owns neither; multiplicative, not additive,
-- since the store description explicitly frames this as one multiplier
-- STACKING with another, not two separate bonuses summing into one pool.
function LuckGamepassConfig.GetRareEssenceMultiplier(player: Instance): number
	local multiplier = 1
	if player:GetAttribute(LuckGamepassConfig.LuckyFinderGamepassId) then
		multiplier *= LuckGamepassConfig.LuckyFinderMultiplier
	end
	if player:GetAttribute(LuckGamepassConfig.UltraLuckGamepassId) then
		multiplier *= LuckGamepassConfig.UltraLuckMultiplier
	end

	-- ProphecyService supplies a temporary server-owned luck multiplier.
	-- It stacks with paid luck (rather than replacing something a player
	-- bought) and is clamped to the strongest catalogued 2x omen.
	multiplier *= math.clamp(
		tonumber(player:GetAttribute("ProphecyRareWeightMultiplier")) or 1,
		1,
		2
	)
	return multiplier
end

return LuckGamepassConfig

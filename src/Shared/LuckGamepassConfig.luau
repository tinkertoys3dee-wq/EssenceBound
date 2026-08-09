--[[
	LuckGamepassConfig (ModuleScript -> ReplicatedStorage)
	==========================================================
	Wires up "Lucky Finder (+50% Luck)" and "Ultra Luck (+300%)" -- two of
	the three Game Passes flagged in NEW_SYSTEMS.md's "THREE PAID GAMEPASSES
	DO NOTHING" section as pure stubs: real Robux, a flag set, nothing in
	the entire codebase ever read it. The third, "Dedicated Essence", is
	wired separately in ZonesConfig.luau (it amplifies zone odds, not crit
	luck -- a different, better-fitting mechanic for what that name means).

	WHY CRIT CHANCE
	-----------------
	"Luck" is this game's own word for it already, and crits are the one
	mechanic in the whole game explicitly built around a random roll with
	a big, exciting payoff -- see CriticalsController.luau's own docs.
	Reusing that existing, already-balanced, already-capped system is a
	much smaller and safer change than inventing a new roll (a golden-storm
	chance mod, an essence-rarity mod, ...) from scratch to hang two paid
	features off of.

	WHY ADDITIVE, NOT MULTIPLICATIVE, WHEN BOTH ARE OWNED
	-----------------------------------------------------------
	+50% and +300% read as percentages of the player's OWN base luck, not
	as multipliers that compound with each other -- owning both should
	feel generous (this is two separate real purchases), not turn into an
	uncontrolled x6 from naively chaining 1.5 * 4.0. Both bonuses add into
	one shared multiplier instead: 1 + 0.5 (Lucky Finder) + 3.0 (Ultra
	Luck) = 4.5x with both owned, 1.5x or 4x with just one. Still bounded
	by CriticalsController's own MAX_CRIT_CHANCE either way, same as every
	other source that feeds into it.

	Also shortens the guaranteed-crit-streak wait (see CriticalsController's
	BASE_GUARANTEED_CRIT_STREAK) -- a flat click-count reduction, since
	"percentage of a streak length" doesn't mean much the way a chance
	percentage does. This one genuinely does stack by simple addition (no
	compounding risk with a flat subtraction), same as every other source
	feeding into that number.
]]

local LuckGamepassConfig = {}

LuckGamepassConfig.LuckyFinderGamepassId = 1907239833
LuckGamepassConfig.UltraLuckGamepassId = 1906063939

LuckGamepassConfig.LuckyFinderCritChanceBonus = 0.5 -- "+50% Luck"
LuckGamepassConfig.UltraLuckCritChanceBonus = 3.0   -- "+300%"

LuckGamepassConfig.LuckyFinderStreakReduction = 4
LuckGamepassConfig.UltraLuckStreakReduction = 10

-- Multiplies whatever crit chance the player already has from every
-- other source (tree, Sanctum, New Adventurer's Luck) -- 1 if neither
-- pass is owned, i.e. a total no-op for anyone who hasn't bought either.
function LuckGamepassConfig.GetCritChanceMultiplier(player: Instance): number
	local multiplier = 1
	if player:GetAttribute(LuckGamepassConfig.LuckyFinderGamepassId) then
		multiplier += LuckGamepassConfig.LuckyFinderCritChanceBonus
	end
	if player:GetAttribute(LuckGamepassConfig.UltraLuckGamepassId) then
		multiplier += LuckGamepassConfig.UltraLuckCritChanceBonus
	end
	return multiplier
end

function LuckGamepassConfig.GetStreakReduction(player: Instance): number
	local reduction = 0
	if player:GetAttribute(LuckGamepassConfig.LuckyFinderGamepassId) then
		reduction += LuckGamepassConfig.LuckyFinderStreakReduction
	end
	if player:GetAttribute(LuckGamepassConfig.UltraLuckGamepassId) then
		reduction += LuckGamepassConfig.UltraLuckStreakReduction
	end
	return reduction
end

return LuckGamepassConfig

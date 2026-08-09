--[[
	NewPlayerLuckConfig (ModuleScript -> ReplicatedStorage)
	==========================================================
	A flat, transparent crit-luck boost for a player's first 24 hours
	since their very first join -- not first SESSION, first CALENDAR DAY,
	so it's still active if they quit after ten minutes and come back
	later today, covering the single highest-leverage retention moment
	there is: the trip back for day one.

	WHY CRITS SPECIFICALLY
	------------------------
	Crits are already this game's single biggest "wow" moment (bigger
	tint/glow/pop per OrbClicker.client.luau, a badge, and the Crit
	Streak Combo callout for back-to-back ones) -- a totally fresh
	player only sees one via the guaranteed first-click crit
	(SeenFirstCrit) and then nothing else until click ~16, since base
	CritChance from the upgrade tree starts at 0. This closes that gap:
	more frequent big payoffs during the exact window that decides
	whether someone becomes a second-session player at all.

	WHY THIS IS NOT THE MANIPULATIVE KIND OF "ADDICTIVE"
	--------------------------------------------------------
	Purely additive generosity with a real, disclosed, benefit-only
	deadline -- nothing is taken away when it expires (the permanent
	crit economy underneath is completely untouched), nothing here is
	hidden (NewPlayerLuckIndicator.client.luau shows it plainly, with an
	honest countdown), and it never scales as a paid product. The
	timer is real and worth telling the truth about -- that's what makes
	it a legitimate reason to come back today, not a fake one.

	Both CriticalsController (the real bonus) and the client indicator
	(what it displays) read this off the same NewPlayerLuckExpiresAt
	attribute, mirrored once at load by PlayerDataHandler.server.luau
	from data.FirstJoinAt -- see that file for how a save is told apart
	from a genuinely brand-new player.
]]

local NewPlayerLuckConfig = {}

NewPlayerLuckConfig.WindowSeconds = 24 * 60 * 60

-- Flat additive bonus to CriticalsController.GetCritChance while active,
-- still subject to that module's own MAX_CRIT_CHANCE clamp same as every
-- other source feeding into it.
NewPlayerLuckConfig.CritChanceBonus = 0.15

-- Shortens the guaranteed_crit_streak wait (see CriticalsController's
-- BASE_GUARANTEED_CRIT_STREAK) by this many clicks while active, still
-- floored by that module's own MIN_GUARANTEED_CRIT_STREAK.
NewPlayerLuckConfig.GuaranteedStreakReduction = 6

-- data.FirstJoinAt is 0 for a save that either predates this field or was
-- never eligible in the first place -- 0 always reads as "not eligible",
-- never as "just joined", which is exactly why this can't be inferred
-- from FirstJoinAt still being 0 at load time (see PlayerDataHandler).
function NewPlayerLuckConfig.GetExpiresAt(firstJoinAt: number?): number?
	local stamp = tonumber(firstJoinAt) or 0
	if stamp <= 0 then
		return nil
	end
	return stamp + NewPlayerLuckConfig.WindowSeconds
end

-- Safe to call from the client or the server: both just read the mirrored
-- attribute, never PlayerData directly, so this behaves identically on
-- either side (same contract as CriticalsController's own functions).
function NewPlayerLuckConfig.IsActive(player: Instance): boolean
	local expiresAt = player:GetAttribute("NewPlayerLuckExpiresAt")
	return type(expiresAt) == "number" and os.time() < expiresAt
end

return NewPlayerLuckConfig

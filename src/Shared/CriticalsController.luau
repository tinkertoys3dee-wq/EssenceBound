--[[
	CriticalsController.lua (ModuleScript)
	---------------------------------------
	Shared crit-roll + crit-multiplier math for the Critical Essence
	upgrade branch in TreeUpgrades:
		critical_chance_1/2/3          -> EffectType "CritChance"
		critical_multiplier_1/2        -> EffectType "CritMultiplierBonus"
		guaranteed_crit_streak         -> EffectType "GuaranteedCritEveryNClicksReduction"
		double_crit                    -> EffectType "DoubleCritChance"

	Crits don't deal extra damage or affect the orb's HP at all -- they
	purely amplify the essence PROFIT from whichever orb landed the crit.
	This module has nothing to do with EssenceOrbController's HP/shots.

	Reads every upgrade level straight off player Attributes via
	TreeUpgrades.GetSummedEffectFromAttributes -- same pattern already used
	elsewhere (CollectionUpgrades, IdleUpgrades) -- so this module behaves
	identically whether required from the client or the server.

	DESIGN NOTE ON TRUST: RollCrit/RollDoubleCrit are meant to be called
	CLIENT-SIDE, once per orb, purely to decide whether that orb gets crit
	visuals (tint/glow/bigger pop) and to flag it for the "collected"
	RemoteEvent. GetCritMultiplier reads CritMultiplierBonus live off the
	player's own Attributes, so the EXTRA amount a crit is worth beyond
	its flat base 2x can't exceed what real upgrades justify. The base 2x
	itself is NOT gated by anything, though: a client that always claims
	crit = true gets an unconditional 2x on every collection regardless
	of upgrades owned -- a real, currently-unmitigated gap, not the closed
	trust boundary this note used to describe. See OrbClickManager.
	server.luau's "collected" handler for the full writeup of that gap
	and why it's flagged rather than fixed there. (`quantity` from the
	client has the same "purely client-owned, no independent server
	record" root cause, elsewhere in this codebase.)

	USAGE
	------
		local Criticals = require(path.to.CriticalsController)

		-- client, once per spawned orb:
		local isCrit = Criticals.RollCrit(player)
		orbInstance:SetAttribute("IsCrit", isCrit)
		-- (tint/glow the orb however you like based on isCrit)

		-- wherever collection actually fires the "collected" RemoteEvent:
		collectedEvent:FireServer(orbName, quantity, orbInstance:GetAttribute("IsCrit"), isGolden)

		-- server, inside the "collected" handler (see EssenceMultiplier.lua,
		-- which already wraps this for you):
		local isDoubleCrit = Criticals.RollDoubleCrit(plr, crit)
		local multiplier = Criticals.GetCritMultiplier(plr, crit, isDoubleCrit)

		-- optional, read-only, for UI (doesn't touch streak state):
		local chance = Criticals.GetCritChance(player)          -- 0-1
		local bonus = Criticals.GetCritMultiplierBonus(player)  -- e.g. 0.35
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))
local NewPlayerLuckConfig = require(ReplicatedStorage:WaitForChild("NewPlayerLuckConfig"))

-- Timed lookup rather than a bare WaitForChild: crit rolling runs on every
-- orb spawn, so a missing SanctumUpgrades must cost the Sanctum crit bonus
-- only, never hang this module.
local SanctumUpgrades
do
	local module = ReplicatedStorage:FindFirstChild("SanctumUpgrades")
		or ReplicatedStorage:WaitForChild("SanctumUpgrades", 10)

	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			SanctumUpgrades = result
		end
	end
end

local CriticalsController = {}

-- =========================================================================
-- TUNABLES (design choices TreeUpgrades doesn't specify a number for)
-- =========================================================================

-- guaranteed_crit_streak reduces this by EffectPerLevel(=2) per level,
-- MaxLevel 5 -> up to -10 total. Floor keeps it from ever hitting 0 or
-- going negative regardless of how the tree gets tuned later.
--
-- Was 20: lowered so the wait between guaranteed crits is shorter across
-- the whole game, not just via the first-click guarantee added in
-- OrbClicker.client.luau (which only ever covers the very first one).
-- Deliberately NOT lowered further than this: at 16, a maxed
-- guaranteed_crit_streak (-10) still lands on 6, comfortably above the
-- floor of 4, so every level of that upgrade stays meaningful. Dropping
-- much further would push the upgrade's own top level(s) below the floor
-- and make them do nothing -- the same kind of dead-upgrade problem
-- root_awakening's levels 2-5 already have elsewhere in TreeUpgrades
-- (its "UnlockTree" effect is defined but never read anywhere -- flagged,
-- not fixed here, since it's a balance call outside this change's scope).
local BASE_GUARANTEED_CRIT_STREAK = 16
local MIN_GUARANTEED_CRIT_STREAK = 4

-- Belt-and-suspenders cap so stacking every CritChance upgrade can't push
-- past a near-guaranteed crit on every single click.
local MAX_CRIT_CHANCE = 0.9

-- =========================================================================
-- PER-PLAYER STREAK STATE
-- =========================================================================
-- [player] = number of non-crit clicks in a row since the last crit
local streakCounts = {}

local function getGuaranteedStreakLength(player)
	local reduction = TreeUpgrades.GetSummedEffectFromAttributes(player, "GuaranteedCritEveryNClicksReduction")

	-- First-24-hours boost (see NewPlayerLuckConfig) shortens the wait on
	-- top of whatever the player has actually upgraded -- stacks with,
	-- doesn't replace, their real progress.
	if NewPlayerLuckConfig.IsActive(player) then
		reduction += NewPlayerLuckConfig.GuaranteedStreakReduction
	end

	return math.max(MIN_GUARANTEED_CRIT_STREAK, BASE_GUARANTEED_CRIT_STREAK - reduction)
end

-- =========================================================================
-- READ-ONLY DISPLAY HELPERS (safe to call from UI, never touch streak state)
-- =========================================================================

function CriticalsController.GetCritChance(player)
	-- Shadow Sanctum's Dark Fortune stacks additively with the Earth tree's
	-- CritChance line, then the whole total is clamped by MAX_CRIT_CHANCE
	-- exactly as before -- so the two economies complement each other and
	-- neither can push crit chance past the existing cap.
	local sanctumCrit = 0
	if SanctumUpgrades then
		sanctumCrit = tonumber(SanctumUpgrades.GetPlayerEffect(player, "sanctum_dark_fortune")) or 0
	end

	-- First-24-hours boost (see NewPlayerLuckConfig): a flat add on top,
	-- clamped by the same MAX_CRIT_CHANCE as everything else below, so it
	-- can never push a player past the existing ceiling either.
	local luckBonus = NewPlayerLuckConfig.IsActive(player) and NewPlayerLuckConfig.CritChanceBonus or 0

	local total = TreeUpgrades.GetSummedEffectFromAttributes(player, "CritChance") + sanctumCrit + luckBonus
	return math.min(MAX_CRIT_CHANCE, total)
end

function CriticalsController.GetCritMultiplierBonus(player)
	return TreeUpgrades.GetSummedEffectFromAttributes(player, "CritMultiplierBonus")
end

-- =========================================================================
-- ROLLING
-- =========================================================================

-- Returns true/false for whether this single orb/collection should be
-- treated as a critical. Combines a base random roll off CritChance with
-- a guaranteed crit once enough non-crit clicks have piled up
-- (guaranteed_crit_streak). Advances/resets the player's streak counter as
-- a side effect, so call this AT MOST ONCE PER ORB.
function CriticalsController.RollCrit(player)
	local critChance = CriticalsController.GetCritChance(player)
	local streakLength = getGuaranteedStreakLength(player)
	local clicksSinceLastCrit = (streakCounts[player] or 0) + 1

	local isCrit = math.random() < critChance
	if not isCrit and clicksSinceLastCrit >= streakLength then
		isCrit = true
	end

	streakCounts[player] = isCrit and 0 or clicksSinceLastCrit

	return isCrit
end

-- Rolls double_crit's "chance to immediately trigger a second critical" on
-- top of an already-landed crit. Returns false immediately if isCrit is
-- false (no double-crit without crit-ing first) or if the player doesn't
-- own double_crit at all.
function CriticalsController.RollDoubleCrit(player, isCrit)
	if not isCrit then
		return false
	end

	local doubleCritChance = TreeUpgrades.GetSummedEffectFromAttributes(player, "DoubleCritChance")
	if doubleCritChance <= 0 then
		return false
	end

	return math.random() < doubleCritChance
end

-- =========================================================================
-- MULTIPLIER
-- =========================================================================

-- Returns the essence multiplier a single collection is worth given
-- whether it crit (and optionally double-crit). 1 = no bonus, i.e. safe to
-- multiply straight into an existing essence calculation unconditionally.
-- This is the piece meant to be trusted server-side: the bonus is derived
-- from CritMultiplierBonus on the player's own Attributes, not from
-- anything the client sent, so it can't be inflated beyond what their
-- upgrades actually justify.
function CriticalsController.GetCritMultiplier(player, isCrit, isDoubleCrit)
	if not isCrit then
		return 1
	end

	local critBonus = CriticalsController.GetCritMultiplierBonus(player)
	local multiplier = 2 + critBonus

	if isDoubleCrit then
		multiplier += critBonus -- second proc stacks another full crit bonus
	end

	return multiplier
end

-- =========================================================================
-- CLEANUP
-- =========================================================================

Players.PlayerRemoving:Connect(function(player)
	streakCounts[player] = nil
end)

return CriticalsController
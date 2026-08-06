--[[
	IdleUpgrades ModuleScript
	-------------------------
	Getters for the "Passive" branch of TreeUpgrades:
		idle_drips_1 / idle_drips_2         -> PassiveEssencePerSecond
		offline_harvest_1 / offline_harvest_2 -> OfflineEarningsPercent
		automation_core                     -> UnlockAutoClick (one-off)
		global_multiplier_1 / global_multiplier_2 ("Essence Affinity I/II")
			-> GlobalEssenceMultiplier
		(essence_convergence capstone also grants GlobalEssenceMultiplier -
		 it's included automatically since GetSummedEffectFromAttributes
		 sums by EffectType across the whole tree, not just one branch)

	Reads upgrade levels from Player Attributes (assumed to be the live,
	server-mirrored source of truth - same assumption your orb clicker
	script and CollectionUpgrades already make). Safe to require from
	both client and server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))

local IdleUpgrades = {}

-- Essence/sec from idle_drips_1 + idle_drips_2, BEFORE any global
-- multiplier is applied. Whatever system deposits this (see IdleService)
-- should run it through your normal multiplier stack (CalculateMultiplier),
-- not use this raw number directly as currency.
function IdleUpgrades.GetPassiveEssencePerSecond(player)
	return TreeUpgrades.GetSummedEffectFromAttributes(player, "PassiveEssencePerSecond")
end

-- 0-1 fraction of the passive rate banked while offline, from
-- offline_harvest_1 + offline_harvest_2. Clamped defensively in case future
-- upgrades push the sum past 100%.
function IdleUpgrades.GetOfflineEarningsPercent(player)
	local pct = TreeUpgrades.GetSummedEffectFromAttributes(player, "OfflineEarningsPercent")
	return math.clamp(pct, 0, 1)
end

-- automation_core has MaxLevel = 1, so this is just "owned or not."
function IdleUpgrades.HasAutomationCore(player)
	return (player:GetAttribute("automation_core") or 0) >= 1
end

-- 1 + (every GlobalEssenceMultiplier source: Essence Affinity I/II AND
-- essence_convergence, since they share this EffectType by design).
-- Multiply this into your existing multiplier stack (see the
-- CalculateMultiplier patch).
function IdleUpgrades.GetGlobalEssenceMultiplier(player)
	return 1 + TreeUpgrades.GetSummedEffectFromAttributes(player, "GlobalEssenceMultiplier")
end

return IdleUpgrades
--!strict
--[[
	RebirthModule.lua
	----------------------------------------------------------------
	Pure-logic ModuleScript for a "Rebirth" / prestige system.

	It does NOT touch DataStores, RemoteEvents, or Player instances.
	You feed it plain data (numbers / tables) and it hands back plain
	data. That makes it safe to require from a LocalScript (for UI
	previews, e.g. "what will my next rebirth give me?") AND from a
	server Script (for the real rebirth transaction) without
	duplicating your formulas in two places.

	Recommended usage pattern:
		- Client: require this module to PREVIEW numbers in the UI.
		- Server: require this module to VALIDATE and APPLY the
		  actual rebirth, since the client can never be trusted to
		  award itself essence/multipliers.
--]]

local RebirthModule = {}

--============================================================
-- CONFIG - tune these to balance your game
--============================================================

-- Base essence cost for the FIRST rebirth (rebirth 0 -> 1).
local BASE_ESSENCE_COST = 350

-- How steeply the essence cost scales per rebirth already owned.
-- cost = BASE_ESSENCE_COST * (COST_GROWTH ^ rebirthCount)
local COST_GROWTH = 1.85

-- Multiplier granted per rebirth (before milestone bonuses).
-- multiplier = 1 + (rebirthCount * MULTIPLIER_PER_REBIRTH)
local MULTIPLIER_PER_REBIRTH = 0.5

-- Soft cap so the multiplier doesn't scale forever at full rate.
-- After SOFT_CAP_REBIRTH rebirths, each extra rebirth grants less.
-- Set SOFT_CAP_REBIRTH = math.huge to disable the cap entirely.
local SOFT_CAP_REBIRTH = 25
local SOFT_CAP_MULTIPLIER_PER_REBIRTH = 0.15
-- Base RebirthCurrency granted per rebirth, before ascension_insight bonus.
RebirthModule.BASE_REBIRTH_CURRENCY_GRANT = 1
--============================================================
-- MILESTONES - special unlocks tied to specific rebirth counts
--============================================================
-- Each key is the rebirth count a player must REACH (i.e. the
-- number they have right after performing that rebirth) to get
-- the listed rewards. essenceMultiplierBonus values are additive
-- flat bonuses stacked on top of the normal per-rebirth multiplier.

export type MilestoneData = {
	essenceMultiplierBonus: number?,
	upgradesUnlocked: { string }?,
	title: string?,
	description: string,
}

local MILESTONES: { [number]: MilestoneData } = {
	[1] = {
		essenceMultiplierBonus = 0.25,
		upgradesUnlocked = { "New Upgrades" },
		title = "Reborn",
		description = "Unlocks new upgrade tree routes and a permanent +25% essence bonus.",
	},
	[5] = {
		essenceMultiplierBonus = 0.5,
		upgradesUnlocked = { "New Upgrades" },
		title = "Veteran",
		description = "Unlocks new upgrade tree routes and a permanent +50% essence bonus.",
	},
	[10] = {
		essenceMultiplierBonus = 1,
		upgradesUnlocked = { "New Upgrades" },
		title = "Ascended",
		description = "Unlocks the Prestige Shop and a permanent +100% essence bonus.",
	},
	[25] = {
		essenceMultiplierBonus = 2,
		upgradesUnlocked = { "PrestigeShop" },
		title = "Mythic",
		description = "Unlocks new upgrade tree routes and a permanent +200% essence bonus.",
	},
	[50] = {
		essenceMultiplierBonus = 5,
		upgradesUnlocked = { "InfinityCore" },
		title = "Eternal",
		description = "Unlocks the Infinity Core and a permanent +500% essence bonus.",
	},
}

--============================================================
-- CORE MATH
--============================================================

function RebirthModule.CalculateMultiplier(rebirthCount: number, boostBonusPercent: number?): number
	boostBonusPercent = boostBonusPercent or 0
	local perRebirth = MULTIPLIER_PER_REBIRTH * (1 + boostBonusPercent)
	local softCapPerRebirth = SOFT_CAP_MULTIPLIER_PER_REBIRTH * (1 + boostBonusPercent)

	if rebirthCount <= 0 then
		return 1
	end

	if rebirthCount <= SOFT_CAP_REBIRTH then
		return 1 + (rebirthCount * perRebirth)
	end

	local baseGain = SOFT_CAP_REBIRTH * perRebirth
	local extraRebirths = rebirthCount - SOFT_CAP_REBIRTH
	local extraGain = extraRebirths * softCapPerRebirth

	return 1 + baseGain + extraGain
end

function RebirthModule.CalculateMilestoneBonus(rebirthCount: number): number
	local bonus = 0
	for count, data in pairs(MILESTONES) do
		if count <= rebirthCount and data.essenceMultiplierBonus then
			bonus += data.essenceMultiplierBonus
		end
	end
	return bonus
end

function RebirthModule.CalculateTotalMultiplier(rebirthCount: number, boostBonusPercent: number?): number
	return RebirthModule.CalculateMultiplier(rebirthCount, boostBonusPercent)
		+ RebirthModule.CalculateMilestoneBonus(rebirthCount)
end

-- requirementReductionPercent comes from rebirth_insight_1/2, clamped so
-- rebirth can never become free.
function RebirthModule.CalculateEssenceNeeded(rebirthCount: number, requirementReductionPercent: number?): number
	requirementReductionPercent = math.clamp(requirementReductionPercent or 0, 0, 0.9)
	local cost = BASE_ESSENCE_COST * (COST_GROWTH ^ rebirthCount)
	cost *= (1 - requirementReductionPercent)
	return math.floor(cost)
end

-- Base RebirthCurrency granted per rebirth, before ascension_insight bonus.
RebirthModule.BASE_REBIRTH_CURRENCY_GRANT = 1


--============================================================
-- MILESTONE LOOKUPS
--============================================================

-- Raw milestone data for an exact rebirth count, if any.
function RebirthModule.GetMilestone(rebirthCount: number): MilestoneData?
	return MILESTONES[rebirthCount]
end

-- Unlocks (if any) tied specifically to the player's NEXT rebirth.
function RebirthModule.GetUnlocksForNextRebirth(currentRebirthCount: number): MilestoneData?
	return MILESTONES[currentRebirthCount + 1]
end

-- The closest future milestone beyond the current rebirth count.
-- Useful for "3 rebirths until Veteran" style UI.
function RebirthModule.GetNextMilestone(currentRebirthCount: number): (number?, MilestoneData?)
	local closestCount: number? = nil
	local closestData: MilestoneData? = nil

	for count, data in pairs(MILESTONES) do
		if count > currentRebirthCount and (closestCount == nil or count < closestCount) then
			closestCount = count
			closestData = data
		end
	end

	return closestCount, closestData
end

-- Every milestone reached up to and including rebirthCount, sorted ascending.
function RebirthModule.GetReachedMilestones(rebirthCount: number): { [number]: MilestoneData }
	local reached: { [number]: MilestoneData } = {}
	for count, data in pairs(MILESTONES) do
		if count <= rebirthCount then
			reached[count] = data
		end
	end
	return reached
end


--============================================================
-- HIGH-LEVEL HELPERS
--============================================================

function RebirthModule.GetRebirthInfo(playerData: { rebirthCount: number?, essence: number? }, player: Player?): RebirthInfo
	local rebirthCount = playerData.rebirthCount or 0
	local essence = playerData.essence or 0

	local requirementReduction = 0
	local boostBonus = 0
	if player then
		local EssenceUpgrades = require(game:GetService("ReplicatedStorage"):WaitForChild("TreeUpgrades"))
		requirementReduction = EssenceUpgrades.GetSummedEffectFromAttributes(player, "RebirthRequirementReduction")
		boostBonus = EssenceUpgrades.GetSummedEffectFromAttributes(player, "RebirthBoostBonus")
	end
	local currentMultiplier = RebirthModule.CalculateTotalMultiplier(rebirthCount, boostBonus)
	local nextMultiplier = RebirthModule.CalculateTotalMultiplier(rebirthCount + 1, boostBonus)
	local essenceNeeded = RebirthModule.CalculateEssenceNeeded(rebirthCount, requirementReduction)
	local nextMilestoneCount, nextMilestoneData = RebirthModule.GetNextMilestone(rebirthCount)

	return {
		rebirthCount = rebirthCount,
		currentMultiplier = currentMultiplier,
		nextMultiplier = nextMultiplier,
		multiplierGain = nextMultiplier - currentMultiplier,
		essenceNeeded = essenceNeeded,
		essenceCurrent = essence,
		canRebirth = essence >= essenceNeeded,
		nextRebirthUnlocks = RebirthModule.GetUnlocksForNextRebirth(rebirthCount),
		nextMilestoneCount = nextMilestoneCount,
		nextMilestoneData = nextMilestoneData,
	}
end

function RebirthModule.CanRebirth(currentEssence: number, rebirthCount: number, requirementReductionPercent: number?): boolean
	return currentEssence >= RebirthModule.CalculateEssenceNeeded(rebirthCount, requirementReductionPercent)
end

function RebirthModule.PerformRebirth(playerData, player)
	local EssenceUpgrades = require(game:GetService("ReplicatedStorage"):WaitForChild("TreeUpgrades"))

	local rebirthCount = playerData.Rebirths or 0
	local essence = playerData.Essences["EarthEssence"].Quantity or 0

	local requirementReduction = EssenceUpgrades.GetSummedEffectFromAttributes(player, "RebirthRequirementReduction")
	local essenceNeeded = RebirthModule.CalculateEssenceNeeded(rebirthCount, requirementReduction)

	if essence < essenceNeeded then
		return false
	end

	local newRebirthCount = rebirthCount + 1
	local unlocks = RebirthModule.GetMilestone(newRebirthCount)

	-- rebirth_echo: retain a % of current essence instead of zeroing it out
	local retainPercent = math.clamp(EssenceUpgrades.GetSummedEffectFromAttributes(player, "RebirthRetainPercent"), 0, 1)
	local retainedEssence = math.floor(essence * retainPercent)
	local bonusCurrency = EssenceUpgrades.GetSummedEffectFromAttributes(player, "BonusRebirthCurrency")
	
	for upgrade, tier in pairs(playerData.Upgrades) do
		player:SetAttribute(upgrade,0)
	end
	playerData.Upgrades = {}
	
	playerData.Rebirths = newRebirthCount
	player:SetAttribute("Rebirths", newRebirthCount)
	player:WaitForChild("leaderstats"):WaitForChild("Earth Essence"):SetAttribute("Quantity", retainedEssence)
	playerData.Essences["EarthEssence"].Quantity = retainedEssence
	playerData.Essences["EarthEssence"].savedEPM = 0
	
	-- ascension_insight: bonus RebirthCurrency on top of the base grant
	
	local grantedCurrency = RebirthModule.BASE_REBIRTH_CURRENCY_GRANT + bonusCurrency

	playerData.RebirthCurrency = (playerData.RebirthCurrency or 0) + grantedCurrency
	player:SetAttribute("RebirthCurrency", playerData.RebirthCurrency)
	
	return true
end

return RebirthModule
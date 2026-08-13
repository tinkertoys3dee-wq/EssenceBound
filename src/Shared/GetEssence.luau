local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ZonesConfig = require(ReplicatedStorage:WaitForChild("ZonesConfig"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))

local module = {}

-- Catalog-derived fallback only -- used if a weight table ever comes back
-- empty/malformed (never in normal play; ZonesConfig.GetEssenceWeights
-- always returns a real zone's weights). Not read directly by either
-- function below anymore now that zones exist; kept as the safety net
-- resolveWeights falls back to.
module.Essences = {}
for _, definition in ipairs(EssenceConfig.Ordered) do
	module.Essences[definition.Name] = definition.Rarity == 0 and 98 or 1
end

-- Shared by GetOddsText and GetRandomEssence so the two can never roll
-- against a different table than the one the odds text describes.
local function resolveWeights(weights)
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	if total <= 0 then
		weights = module.Essences
		total = 100
	end
	return weights, total
end

-- Builds a human-readable "1 in N" odds string for the discovery popup,
-- against the SAME per-player, per-zone weight table GetRandomEssence
-- rolls -- pass the player so this can never show odds that don't match
-- what they're actually zoned into (a zone-blind global number would be
-- misleading now that zones bias this per player). plr is optional only
-- for backwards compatibility with any stray caller that predates zones;
-- every call site in this codebase passes it.
module.GetOddsText = function(essenceName, plr)
	local weights, total = resolveWeights(ZonesConfig.GetEssenceWeights(plr))
	local weight = weights[essenceName]
	if not weight or weight <= 0 then
		return "1 in ?"
	end

	local n = total / weight
	if n == math.floor(n) then
		return "1 in " .. math.floor(n)
	end
	return string.format("1 in %.1f", n)
end

module.GetRandomEssence = function(plr)
	local weights, total = resolveWeights(ZonesConfig.GetEssenceWeights(plr))

	local roll = math.random() * total

	local cumulative = 0
	local lastEssence = nil
	for essence, weight in pairs(weights) do
		cumulative += weight
		lastEssence = essence
		if roll <= cumulative then
			return essence
		end
	end

	-- Floating point can leave `roll` a hair above the final cumulative
	-- total, which would otherwise fall out of the loop and return nil --
	-- callers treat this as an orb type, so it must always return one.
	return lastEssence
end

return module

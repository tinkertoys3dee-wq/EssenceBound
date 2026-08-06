local module = {}
module.Essences = {
	["Earth Essence"] = 50,
	["Shadow Essence"] = 50
}


-- Builds a human-readable "1 in N" odds string for the discovery popup from
-- the same weight table GetRandomEssence rolls against, so the displayed
-- odds can never drift out of sync with the actual roll.
module.GetOddsText = function(essenceName)
	local weight = module.Essences[essenceName]
	if not weight or weight <= 0 then
		return "1 in ?"
	end

	local total = 0
	for _, w in pairs(module.Essences) do
		total += w
	end

	local n = total / weight
	if n == math.floor(n) then
		return "1 in " .. math.floor(n)
	end
	return string.format("1 in %.1f", n)
end

module.GetRandomEssence = function(plr)
	local total = 0
	for _, weight in pairs(module.Essences) do
		total += weight
	end

	local roll = math.random() * total

	local cumulative = 0
	local lastEssence = nil
	for essence, weight in pairs(module.Essences) do
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
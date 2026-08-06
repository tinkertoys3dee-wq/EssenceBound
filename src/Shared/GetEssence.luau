local module = {}
module.Essences = {
	["Earth Essence"] = 50,
	["Shadow Essence"] = 50
}


module.GetRandomEssence = function(plr)
	local total = 0
	for _, weight in pairs(module.Essences) do
		total += weight
	end

	local roll = math.random() * total

	local cumulative = 0
	for essence, weight in pairs(module.Essences) do
		cumulative += weight
		if roll <= cumulative then
			return essence
		end
	end
end

return module
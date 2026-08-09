--[[
	ProphecyConfig (ModuleScript -> ReplicatedStorage)
	===================================================
	Shared catalog and balance rules for the Prophecy Crystal. The server
	is the only caller that rolls an outcome; the client reads this same
	catalog so every name, duration, rarity and advertised benefit is the
	exact one that gameplay applies.

	A reading is free every ten minutes. Most prophecies last five minutes
	(six for Radiant Harvest, three for the especially strong Chosen Hour),
	so the crystal adds a focused burst to the collect loop without becoming
	a permanent baseline multiplier. Eight readings without a Rare-or-better
	omen trigger Fate: the eighth roll is restricted to Rare+ entries.
]]

local ProphecyConfig = {}

ProphecyConfig.RollCooldownSeconds = 10 * 60
ProphecyConfig.PityRolls = 8
ProphecyConfig.RareRank = 3

ProphecyConfig.Rarities = {
	Common = {
		Rank = 1,
		Color = Color3.fromRGB(155, 205, 190),
		Glow = Color3.fromRGB(86, 184, 157),
	},
	Uncommon = {
		Rank = 2,
		Color = Color3.fromRGB(104, 222, 255),
		Glow = Color3.fromRGB(70, 150, 255),
	},
	Rare = {
		Rank = 3,
		Color = Color3.fromRGB(255, 206, 89),
		Glow = Color3.fromRGB(255, 143, 63),
	},
	Epic = {
		Rank = 4,
		Color = Color3.fromRGB(215, 118, 255),
		Glow = Color3.fromRGB(139, 74, 255),
	},
	Mythic = {
		Rank = 5,
		Color = Color3.fromRGB(255, 116, 181),
		Glow = Color3.fromRGB(255, 195, 87),
	},
}

-- Weights deliberately sum to 100. Effect fields use neutral defaults
-- when absent: 1x multiplicative bonuses and +0 additive crit chance.
ProphecyConfig.Prophecies = {
	{
		Id = "verdant_whisper",
		Name = "The Verdant Whisper",
		Icon = "🌿",
		Rarity = "Common",
		Weight = 26,
		Duration = 5 * 60,
		EssenceMultiplier = 1.25,
		Benefit = "1.25x all Essence",
		Lore = "Every root remembers your name. For a little while, the grove gives more freely.",
		RevealQuote = "THE ROOTS SPEAK",
	},
	{
		Id = "keen_omen",
		Name = "The Keen Omen",
		Icon = "✦",
		Rarity = "Common",
		Weight = 24,
		Duration = 5 * 60,
		CritChanceBonus = 0.08,
		Benefit = "+8% Critical Chance",
		Lore = "A bright fracture crosses the future. Your next moments sharpen around it.",
		RevealQuote = "A CLEAR PATH FORMS",
	},
	{
		Id = "shadow_murmur",
		Name = "Shadow's Murmur",
		Icon = "🌑",
		Rarity = "Uncommon",
		Weight = 18,
		Duration = 5 * 60,
		RareWeightMultiplier = 1.5,
		Benefit = "1.5x rare-Essence luck",
		Lore = "Something beneath the veil points toward rarer things. It asks only that you listen.",
		RevealQuote = "THE VEIL WHISPERS",
	},
	{
		Id = "twin_comet",
		Name = "The Twin Comet",
		Icon = "☄",
		Rarity = "Uncommon",
		Weight = 14,
		Duration = 5 * 60,
		EssenceMultiplier = 1.25,
		CritChanceBonus = 0.06,
		Benefit = "1.25x Essence  •  +6% Crit",
		Lore = "Two lights share one horizon: abundance follows precision, and precision follows motion.",
		RevealQuote = "TWO FATES ALIGN",
	},
	{
		Id = "radiant_harvest",
		Name = "The Radiant Harvest",
		Icon = "☀",
		Rarity = "Rare",
		Weight = 9,
		Duration = 6 * 60,
		EssenceMultiplier = 1.5,
		Benefit = "1.5x all Essence",
		Lore = "The crystal fills with a golden field where every gathered spark returns brighter.",
		RevealQuote = "ABUNDANCE IS FORETOLD",
	},
	{
		Id = "astral_precision",
		Name = "Astral Precision",
		Icon = "✧",
		Rarity = "Rare",
		Weight = 6,
		Duration = 5 * 60,
		CritChanceBonus = 0.15,
		Benefit = "+15% Critical Chance",
		Lore = "For one perfect interval, the stars stop wandering and mark exactly where fortune will land.",
		RevealQuote = "THE STARS TAKE AIM",
	},
	{
		Id = "convergent_future",
		Name = "The Convergent Future",
		Icon = "◈",
		Rarity = "Epic",
		Weight = 2.5,
		Duration = 5 * 60,
		EssenceMultiplier = 1.5,
		CritChanceBonus = 0.10,
		RareWeightMultiplier = 1.5,
		Benefit = "1.5x Essence  •  +10% Crit  •  1.5x Luck",
		Lore = "A thousand possible worlds collapse into the one where every current runs in your favor.",
		RevealQuote = "ALL PATHS BECOME ONE",
	},
	{
		Id = "chosen_hour",
		Name = "The Chosen Hour",
		Icon = "👑",
		Rarity = "Mythic",
		Weight = 0.5,
		Duration = 3 * 60,
		EssenceMultiplier = 2,
		CritChanceBonus = 0.20,
		RareWeightMultiplier = 2,
		Benefit = "2x Essence  •  +20% Crit  •  2x Luck",
		Lore = "The crystal does not show a future. It bows, and the future waits for you to choose it.",
		RevealQuote = "THIS HOUR IS YOURS",
	},
}

local byId = {}
for _, prophecy in ipairs(ProphecyConfig.Prophecies) do
	byId[prophecy.Id] = prophecy
end

function ProphecyConfig.GetById(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

function ProphecyConfig.GetRarity(rarityName: string?)
	if type(rarityName) ~= "string" then
		return nil
	end
	return ProphecyConfig.Rarities[rarityName]
end

function ProphecyConfig.GetRank(prophecy): number
	local rarity = prophecy and ProphecyConfig.GetRarity(prophecy.Rarity)
	return rarity and rarity.Rank or 0
end

function ProphecyConfig.TotalWeight(minimumRank: number?): number
	local minRank = tonumber(minimumRank) or 0
	local total = 0
	for _, prophecy in ipairs(ProphecyConfig.Prophecies) do
		if ProphecyConfig.GetRank(prophecy) >= minRank then
			total += prophecy.Weight
		end
	end
	return total
end

-- Server-only by convention. minimumRank is used by the Fate guarantee;
-- clients receive only the already-chosen Id from ProphecyService.
function ProphecyConfig.RollProphecyId(minimumRank: number?): string
	local minRank = tonumber(minimumRank) or 0
	local total = ProphecyConfig.TotalWeight(minRank)
	if total <= 0 then
		return ProphecyConfig.Prophecies[1].Id
	end

	local roll = math.random() * total
	local cumulative = 0
	local fallback = ProphecyConfig.Prophecies[1]
	for _, prophecy in ipairs(ProphecyConfig.Prophecies) do
		if ProphecyConfig.GetRank(prophecy) >= minRank then
			fallback = prophecy
			cumulative += prophecy.Weight
			if roll < cumulative then
				return prophecy.Id
			end
		end
	end

	return fallback.Id
end

return ProphecyConfig

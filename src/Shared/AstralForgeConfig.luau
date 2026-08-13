--[[
	AstralForgeConfig (ModuleScript -> ReplicatedStorage)
	=====================================================
	Shared recipe catalog and progression rules for the Astral Forge.

	Unlike the free, random Prophecy Crystal, the forge is a deliberate
	currency sink: players choose an infusion, pay a mixed Essence cost, and
	receive one reconnect-safe temporary boon. Only one forge infusion can be
	active at a time, so the choice remains meaningful instead of turning into
	a checklist of four buffs to keep permanently running.

	A globally featured recipe rotates at midnight UTC. Featured recipes cost
	20% less and last 25% longer. Every successful craft also advances permanent
	Forge Mastery, which adds a modest duration bonus without inflating rewards
	or making early recipes free. Higher ranks also require forging the Umbral,
	Solar, then Trinity recipes at least once; cheap Verdant spam cannot skip
	the game's Shadow/Solar progression and instantly max the forge.
]]

local AstralForgeConfig = {}

AstralForgeConfig.RotationSeconds = 24 * 60 * 60
AstralForgeConfig.FeaturedCostMultiplier = 0.8
AstralForgeConfig.FeaturedDurationMultiplier = 1.25

AstralForgeConfig.Recipes = {
	{
		Id = "verdant_flux",
		Name = "Verdant Flux",
		Icon = "🌿",
		Rune = "ᚠ",
		Color = Color3.fromRGB(84, 232, 144),
		GlowColor = Color3.fromRGB(45, 174, 112),
		RebirthRequired = 0,
		Duration = 8 * 60,
		Costs = { EarthEssence = 750 },
		EssenceMultiplier = 1.3,
		Benefit = "1.30x all Essence",
		Description = "Temper living Earth Essence into a current of accelerated growth.",
		Flavor = "ROOTS BEND TOWARD THE FLAME",
	},
	{
		Id = "umbral_edge",
		Name = "Umbral Edge",
		Icon = "🌘",
		Rune = "ᚦ",
		Color = Color3.fromRGB(193, 112, 255),
		GlowColor = Color3.fromRGB(112, 58, 207),
		RebirthRequired = 1,
		Duration = 8 * 60,
		Costs = { EarthEssence = 15000, ["Shadow Essence"] = 250 },
		CritChanceBonus = 0.1,
		Benefit = "+10% Critical Chance",
		Description = "Hone Shadow Essence into an edge thin enough to split fortune itself.",
		Flavor = "THE DARKNESS LEARNS PRECISION",
	},
	{
		Id = "solar_lens",
		Name = "Solar Lens",
		Icon = "☀",
		Rune = "ᛋ",
		Color = Color3.fromRGB(255, 193, 65),
		GlowColor = Color3.fromRGB(255, 106, 48),
		RebirthRequired = 3,
		Duration = 10 * 60,
		Costs = { EarthEssence = 75000, SolarEssence = 100 },
		RareWeightMultiplier = 1.8,
		Benefit = "1.80x rare-Essence luck",
		Description = "Focus stellar fire until rare Essence shines through every possible path.",
		Flavor = "A SECOND SUN OPENS ITS EYE",
	},
	{
		Id = "trinity_crown",
		Name = "Trinity Crown",
		Icon = "✦",
		Rune = "ᛟ",
		Color = Color3.fromRGB(104, 225, 255),
		GlowColor = Color3.fromRGB(255, 112, 210),
		RebirthRequired = 8,
		Duration = 12 * 60,
		Costs = {
			EarthEssence = 750000,
			["Shadow Essence"] = 10000,
			SolarEssence = 1000,
		},
		EssenceMultiplier = 1.65,
		CritChanceBonus = 0.12,
		RareWeightMultiplier = 2.25,
		Benefit = "1.65x Essence  •  +12% Crit  •  2.25x Luck",
		Description = "Converge all three Essences into a crown of impossible, unstable power.",
		Flavor = "THREE CURRENTS BECOME ONE",
	},
}

AstralForgeConfig.MasteryTiers = {
	{ Tier = 0, Name = "Spark Initiate", CraftsRequired = 0, DurationMultiplier = 1 },
	{ Tier = 1, Name = "Emberkeeper", CraftsRequired = 3, DurationMultiplier = 1.05 },
	{ Tier = 2, Name = "Runebinder", CraftsRequired = 10, DurationMultiplier = 1.1, RequiredRecipeId = "umbral_edge" },
	{ Tier = 3, Name = "Starforged", CraftsRequired = 25, DurationMultiplier = 1.15, RequiredRecipeId = "solar_lens" },
	{ Tier = 4, Name = "Astral Smith", CraftsRequired = 60, DurationMultiplier = 1.25, RequiredRecipeId = "trinity_crown" },
}

local recipesById = {}
for _, recipe in ipairs(AstralForgeConfig.Recipes) do
	recipesById[recipe.Id] = recipe
end

function AstralForgeConfig.GetRecipe(recipeId: string?)
	if type(recipeId) ~= "string" then
		return nil
	end
	return recipesById[recipeId]
end

function AstralForgeConfig.GetRotationIndex(unixTimestamp: number?): number
	local timestamp = math.max(0, math.floor(tonumber(unixTimestamp) or os.time()))
	return math.floor(timestamp / AstralForgeConfig.RotationSeconds)
end

function AstralForgeConfig.GetFeaturedRecipe(unixTimestamp: number?)
	local day = AstralForgeConfig.GetRotationIndex(unixTimestamp)
	local index = (day % #AstralForgeConfig.Recipes) + 1
	return AstralForgeConfig.Recipes[index]
end

function AstralForgeConfig.GetSecondsUntilRotation(unixTimestamp: number?): number
	local timestamp = math.max(0, math.floor(tonumber(unixTimestamp) or os.time()))
	local nextRotation = (AstralForgeConfig.GetRotationIndex(timestamp) + 1) * AstralForgeConfig.RotationSeconds
	return math.max(0, nextRotation - timestamp)
end

function AstralForgeConfig.IsFeatured(recipeId: string?, unixTimestamp: number?): boolean
	local featured = AstralForgeConfig.GetFeaturedRecipe(unixTimestamp)
	return featured ~= nil and featured.Id == recipeId
end

function AstralForgeConfig.GetMastery(crafts: number?, recipeCrafts)
	local count = math.max(0, math.floor(tonumber(crafts) or 0))
	local crafted = type(recipeCrafts) == "table" and recipeCrafts or {}
	local current = AstralForgeConfig.MasteryTiers[1]
	local nextTier = nil

	for _, tier in ipairs(AstralForgeConfig.MasteryTiers) do
		local hasRequiredRecipe = not tier.RequiredRecipeId
			or (tonumber(crafted[tier.RequiredRecipeId]) or 0) > 0
		if count >= tier.CraftsRequired and hasRequiredRecipe then
			current = tier
		else
			nextTier = tier
			break
		end
	end

	return current, nextTier
end

function AstralForgeConfig.GetCosts(recipeOrId, unixTimestamp: number?)
	local recipe = type(recipeOrId) == "table" and recipeOrId or AstralForgeConfig.GetRecipe(recipeOrId)
	if not recipe then
		return {}
	end

	local multiplier = AstralForgeConfig.IsFeatured(recipe.Id, unixTimestamp)
		and AstralForgeConfig.FeaturedCostMultiplier
		or 1
	local costs = {}
	for currency, amount in pairs(recipe.Costs or {}) do
		costs[currency] = math.max(1, math.floor(amount * multiplier + 0.5))
	end
	return costs
end

function AstralForgeConfig.GetDuration(recipeOrId, crafts: number?, unixTimestamp: number?, recipeCrafts): number
	local recipe = type(recipeOrId) == "table" and recipeOrId or AstralForgeConfig.GetRecipe(recipeOrId)
	if not recipe then
		return 0
	end

	local mastery = AstralForgeConfig.GetMastery(crafts, recipeCrafts)
	local featuredMultiplier = AstralForgeConfig.IsFeatured(recipe.Id, unixTimestamp)
		and AstralForgeConfig.FeaturedDurationMultiplier
		or 1
	return math.max(1, math.floor(recipe.Duration * mastery.DurationMultiplier * featuredMultiplier + 0.5))
end

return AstralForgeConfig

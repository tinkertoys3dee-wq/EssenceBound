--[[
	EssenceConfig
	===============================================================
	One authoritative catalog for every collectible essence. Systems that
	used to maintain separate Earth/Shadow allowlists now resolve through
	this module, so adding Solar Essence cannot leave collection validation,
	persistence, discovery, zones, HUD colors or reward presentation out of
	sync.

	DataKey is the key used inside PlayerData.Essences. Name is the player-
	facing leaderstat/orb name. They are deliberately separate because the
	original data model already used EarthEssence but "Shadow Essence".
]]

local EssenceConfig = {}

EssenceConfig.Ordered = {
	{
		Id = "EarthEssence",
		DataKey = "EarthEssence",
		Name = "Earth Essence",
		ShortName = "Earth",
		Rarity = 0,
		RarityName = "Common",
		Color = Color3.fromRGB(112, 232, 156),
		DeepColor = Color3.fromRGB(32, 116, 73),
		Glyph = "🌍",
		IconAssetId = 79479049281587,
		Description = "Living essence drawn from roots, stone, and the world below.",
	},
	{
		Id = "ShadowEssence",
		DataKey = "Shadow Essence",
		Name = "Shadow Essence",
		ShortName = "Shadow",
		Rarity = 1,
		RarityName = "Rare",
		Color = Color3.fromRGB(184, 108, 255),
		DeepColor = Color3.fromRGB(72, 30, 126),
		Glyph = "🌑",
		IconAssetId = 106130917603943,
		Description = "Unstable essence condensed from the dark between worlds.",
		LifetimeField = "LifetimeShadowEssence",
		LifetimeAttribute = "ShadowEssenceLifetime",
	},
	{
		Id = "SolarEssence",
		DataKey = "SolarEssence",
		Name = "Solar Essence",
		ShortName = "Solar",
		Rarity = 2,
		RarityName = "Mythic",
		Color = Color3.fromRGB(255, 196, 64),
		DeepColor = Color3.fromRGB(193, 68, 24),
		Glyph = "☀️",
		-- The matching source art ships as assets/solar-essence-orb.svg.
		-- Its transparent raster export is now uploaded to Roblox; every UI
		-- surface derives the image URI from this one catalog entry.
		IconAssetId = 97084886370150,
		Description = "Mythic stellar essence carrying the heat and memory of a newborn sun.",
		LifetimeField = "LifetimeSolarEssence",
		LifetimeAttribute = "SolarEssenceLifetime",
	},
}

local byName = {}
local byId = {}
local byDataKey = {}

for _, definition in ipairs(EssenceConfig.Ordered) do
	definition.AttributeName = definition.Id
	definition.DiscoveryAttribute = definition.Id .. "Discovered"
	definition.IconImage = definition.IconAssetId and ("rbxassetid://" .. definition.IconAssetId) or ""
	byName[definition.Name] = definition
	byId[definition.Id] = definition
	byDataKey[definition.DataKey] = definition
end

EssenceConfig.ByName = byName
EssenceConfig.ById = byId
EssenceConfig.ByDataKey = byDataKey

function EssenceConfig.Get(value)
	if type(value) ~= "string" then
		return nil
	end
	return byName[value] or byId[value] or byDataKey[value]
end

function EssenceConfig.IsValidName(name)
	return byName[name] ~= nil
end

function EssenceConfig.GetDataKey(value)
	local definition = EssenceConfig.Get(value)
	return definition and definition.DataKey or nil
end

function EssenceConfig.GetDisplayName(value)
	local definition = EssenceConfig.Get(value)
	return definition and definition.Name or tostring(value or "Essence")
end

function EssenceConfig.GetColor(value, fallback)
	local definition = EssenceConfig.Get(value)
	return definition and definition.Color or fallback or Color3.fromRGB(255, 255, 255)
end

function EssenceConfig.GetIconImage(value)
	local definition = EssenceConfig.Get(value)
	return definition and definition.IconImage or ""
end

function EssenceConfig.GetDiscoveryAttribute(value)
	local definition = EssenceConfig.Get(value)
	return definition and definition.DiscoveryAttribute or nil
end

function EssenceConfig.IsRare(value)
	local definition = EssenceConfig.Get(value)
	return definition ~= nil and definition.Rarity > 0
end

return EssenceConfig

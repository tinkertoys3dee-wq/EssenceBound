--[[
	MonetizationConfig (ModuleScript -> ReplicatedStorage)
	========================================================
	One honest catalog for every Robux offer in EssenceBound. The storefront
	and its optional spotlight cards read this data, while Roblox remains the
	owner of prices and purchase confirmation.

	No price is stored here. MonetizationStore retrieves each player's live
	price from MarketplaceService so regional/managed pricing and Roblox Plus
	discounts are shown correctly instead of being hard-coded into UI text.
]]

local MonetizationConfig = {}

MonetizationConfig.StoreTitle = "ESSENCE MARKET"
MonetizationConfig.StoreSubtitle = "Permanent power and instant boosts"

-- Interest cards never open Roblox's checkout by themselves. They offer a
-- route into the store after the player has had time to understand the game.
MonetizationConfig.Spotlights = {
	MaximumPerSession = 2,
	FirstDelayMin = 150,
	FirstDelayMax = 240,
	RepeatDelayMin = 330,
	RepeatDelayMax = 480,
	VisibleSeconds = 14,
}

MonetizationConfig.Offers = {
	-- =====================================================================
	-- PERMANENT PASSES
	-- =====================================================================
	{
		Id = 1907605899,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 1,
		Title = "2× Essence",
		Headline = "DOUBLE EVERY DROP",
		Benefit = "Permanently doubles every essence reward.",
		Detail = "Stacks with VIP, boosts, rebirths, upgrades, and community bonuses.",
		Tag = "PERMANENT",
		Symbol = "×2",
		Accent = Color3.fromRGB(82, 230, 143),
		Featured = true,
		FeaturedOrder = 2,
		FirstPurchaseFriendly = false,
		SpotlightWeight = 7,
	},
	{
		Id = 1907677938,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 2,
		Title = "Auto Absorption",
		Headline = "ORBS COLLECT THEMSELVES",
		Benefit = "Automatically absorbs spawned essence orbs.",
		Detail = "Skip hover collection and keep your click loop moving on every device.",
		Tag = "PERMANENT AUTO",
		Symbol = "◎",
		Accent = Color3.fromRGB(86, 202, 255),
		Featured = true,
		FeaturedOrder = 3,
		FirstPurchaseFriendly = false,
		SpotlightWeight = 6,
	},
	{
		Id = 1909291891,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 3,
		Title = "VIP Rank",
		Headline = "POWER WITH A GOLDEN MARK",
		Benefit = "Permanent 1.5× essence multiplier.",
		Detail = "Also adds a gold outline to your name and player portrait.",
		Tag = "POWER + STYLE",
		Symbol = "VIP",
		Accent = Color3.fromRGB(255, 205, 77),
		Featured = true,
		FeaturedOrder = 7,
		FirstPurchaseFriendly = false,
		SpotlightWeight = 4,
	},
	{
		Id = 1907863864,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 4,
		Title = "Material Alchemist",
		Headline = "COME BACK TO MORE",
		Benefit = "Raises base offline harvesting from 10% to 50%.",
		Detail = "Earn a much larger share of your saved EPM while away from the game.",
		Tag = "OFFLINE POWER",
		Symbol = "Zz",
		Accent = Color3.fromRGB(132, 157, 255),
		Featured = true,
		FeaturedOrder = 6,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 5,
	},
	{
		Id = 1907239833,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 5,
		Title = "Lucky Finder",
		Headline = "FIND MORE SHADOW ESSENCE",
		Benefit = "+50% weight toward rarer essence drops.",
		Detail = "Works in every zone and stacks with Ultra Luck.",
		Tag = "RARE LUCK",
		Symbol = "+50",
		Accent = Color3.fromRGB(194, 125, 255),
		Featured = false,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 5,
	},
	{
		Id = 1906063939,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 6,
		Title = "Ultra Luck",
		Headline = "AMPLIFY RARE DROPS",
		Benefit = "2× rare-essence weight on its own.",
		Detail = "Stacks with Lucky Finder for a combined 3× rare-essence weight.",
		Tag = "ULTRA RARE LUCK",
		Symbol = "✦",
		Accent = Color3.fromRGB(232, 108, 255),
		Featured = false,
		FirstPurchaseFriendly = false,
		SpotlightWeight = 3,
	},
	{
		Id = 1907077899,
		Kind = "GamePass",
		Category = "Passes",
		SortOrder = 7,
		Title = "Dedicated Essence",
		Headline = "MASTER EACH ZONE",
		Benefit = "Sharpens each zone toward its specialty essence.",
		Detail = "Changes the zone split from 82/18 to a stronger 92/8 focus.",
		Tag = "ZONE POWER",
		Symbol = "◇",
		Accent = Color3.fromRGB(104, 224, 180),
		Featured = false,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 4,
	},

	-- =====================================================================
	-- REPEATABLE BOOSTS / EVENTS
	-- =====================================================================
	{
		Id = 3609555390,
		Kind = "Product",
		Category = "Boosts",
		SortOrder = 1,
		Title = "Mini Essence Potion",
		Headline = "A QUICK BURST OF POWER",
		Benefit = "1.5× all essence for 3 minutes.",
		Detail = "The shortest, simplest way to try an essence boost.",
		Tag = "STARTER BOOST",
		Symbol = "1.5×",
		Accent = Color3.fromRGB(76, 226, 144),
		Featured = true,
		FeaturedOrder = 1,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 8,
	},
	{
		Id = 3609555456,
		Kind = "Product",
		Category = "Boosts",
		SortOrder = 2,
		Title = "Moderate Essence Potion",
		Headline = "POWER AN ENTIRE RUN",
		Benefit = "1.5× all essence for 15 minutes.",
		Detail = "A longer boost for quests, upgrades, and rebirth progress.",
		Tag = "15 MIN BOOST",
		Symbol = "1.5×",
		Accent = Color3.fromRGB(66, 209, 160),
		Featured = false,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 6,
	},
	{
		Id = 3609555497,
		Kind = "Product",
		Category = "Boosts",
		SortOrder = 3,
		Title = "Massive Essence Potion",
		Headline = "NINETY MINUTES OF POWER",
		Benefit = "1.5× all essence for 90 minutes.",
		Detail = "The longest essence potion for a full progression session.",
		Tag = "90 MIN BOOST",
		Symbol = "1.5×",
		Accent = Color3.fromRGB(50, 191, 132),
		Featured = true,
		FeaturedOrder = 8,
		FirstPurchaseFriendly = false,
		SpotlightWeight = 4,
	},
	{
		Id = 3609555580,
		Kind = "Product",
		Category = "Boosts",
		SortOrder = 4,
		Title = "Essence Rain",
		Headline = "SUMMON A STORM NOW",
		Benefit = "Immediately begins an Essence Storm.",
		Detail = "Fill the screen with falling essence without waiting for the next natural storm.",
		Tag = "INSTANT EVENT",
		Symbol = "☄",
		Accent = Color3.fromRGB(255, 172, 66),
		Featured = true,
		FeaturedOrder = 4,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 6,
	},
	{
		Id = 3609555620,
		Kind = "Product",
		Category = "Boosts",
		SortOrder = 5,
		Title = "5 Minute Time Warp",
		Headline = "SKIP FIVE MINUTES AHEAD",
		Benefit = "Instantly grants 5 minutes of current EPM.",
		Detail = "Uses the production rate you have already built in this session.",
		Tag = "INSTANT ESSENCE",
		Symbol = "+5m",
		Accent = Color3.fromRGB(116, 187, 255),
		Featured = true,
		FeaturedOrder = 5,
		FirstPurchaseFriendly = true,
		SpotlightWeight = 7,
	},
	{
		Id = 3609555653,
		Kind = "Product",
		Category = "Boosts",
		SortOrder = 6,
		Title = "30 Minute Time Warp",
		Headline = "LEAP THIRTY MINUTES AHEAD",
		Benefit = "Instantly grants 30 minutes of current EPM.",
		Detail = "A larger instant payout that scales with your current production.",
		Tag = "BIG INSTANT PAYOUT",
		Symbol = "+30m",
		Accent = Color3.fromRGB(96, 154, 255),
		Featured = false,
		FirstPurchaseFriendly = false,
		SpotlightWeight = 4,
	},
}

local offersById = {}
for _, offer in ipairs(MonetizationConfig.Offers) do
	offersById[offer.Id] = offer
end

function MonetizationConfig.GetOffer(offerId)
	return offersById[tonumber(offerId)]
end

function MonetizationConfig.GetInfoType(offer)
	return offer.Kind == "GamePass" and Enum.InfoType.GamePass or Enum.InfoType.Product
end

function MonetizationConfig.IsOwned(player, offer)
	return offer.Kind == "GamePass" and player:GetAttribute(offer.Id) == true
end

function MonetizationConfig.GetOffers(category)
	local results = {}
	for _, offer in ipairs(MonetizationConfig.Offers) do
		if category == "Featured" then
			if offer.Featured then
				table.insert(results, offer)
			end
		elseif offer.Category == category then
			table.insert(results, offer)
		end
	end

	table.sort(results, function(a, b)
		if category == "Featured" then
			return (a.FeaturedOrder or 999) < (b.FeaturedOrder or 999)
		end
		return a.SortOrder < b.SortOrder
	end)
	return results
end

return MonetizationConfig

--[[
	MonetizationStore (LocalScript -> StarterPlayerScripts)
	========================================================
	Builds the Robux storefront entirely in code so it cannot disappear when
	Studio UI instances fail to sync. It binds to the existing Shop button
	when present and creates a matching fallback only when that button is
	actually missing.

	Conversion principles used here:
	  * explain the exact, working benefit before asking for Robux;
	  * retrieve live player-specific prices from MarketplaceService;
	  * distinguish permanent passes from repeatable boosts clearly;
	  * never open Roblox's checkout without a deliberate BUY click;
	  * show one contextual newcomer card only after six minutes of understood
	    play (returning players may see two), and stop once the store is used.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local FirstJourneyConfig = require(ReplicatedStorage:WaitForChild("FirstJourneyConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestPurchase
local analyticsRemote
local queuedAnalyticsEvents = {}

local function trackStoreAction(action, offerId, source)
	if analyticsRemote then
		analyticsRemote:FireServer(action, offerId, source)
		return
	end

	-- The store is intentionally available before its remotes finish
	-- replicating. Preserve the first few funnel events during that window
	-- rather than making slow clients invisible in conversion analytics.
	if #queuedAnalyticsEvents < 12 then
		table.insert(queuedAnalyticsEvents, { action, offerId, source })
	end
end

-- Store presentation must not disappear just because the server-side remote
-- is a few replication frames late. Resolve it independently; BUY gives a
-- clear retry message until the allowlisted purchase route is ready.
task.spawn(function()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		or ReplicatedStorage:WaitForChild("Remotes", 20)
	requestPurchase = remotes and (remotes:FindFirstChild("RequestPurchase")
		or remotes:WaitForChild("RequestPurchase", 20))
	if not requestPurchase then
		warn("MonetizationStore: RequestPurchase remote unavailable -- market remains visible but checkout is disabled.")
	end

	analyticsRemote = remotes and (remotes:FindFirstChild("MonetizationAnalytics")
		or remotes:WaitForChild("MonetizationAnalytics", 20))
	if analyticsRemote then
		for _, event in ipairs(queuedAnalyticsEvents) do
			analyticsRemote:FireServer(event[1], event[2], event[3])
		end
		table.clear(queuedAnalyticsEvents)
	else
		warn("MonetizationStore: analytics remote unavailable -- checkout remains enabled.")
	end
end)

-- =========================================================================
-- THEME + HELPERS
-- =========================================================================

local THEME = {
	Void = Color3.fromRGB(9, 6, 17),
	Background = Color3.fromRGB(22, 14, 35),
	Panel = Color3.fromRGB(34, 21, 51),
	Raised = Color3.fromRGB(48, 29, 67),
	Accent = Color3.fromRGB(255, 171, 65),
	AccentLight = Color3.fromRGB(255, 222, 146),
	Green = Color3.fromRGB(67, 220, 133),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(185, 174, 201),
	Dim = Color3.fromRGB(126, 113, 144),
	Danger = Color3.fromRGB(245, 101, 113),
}

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 12) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or THEME.Accent,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	}, parent)
end

local function constrainText(label, minSize, maxSize)
	return new("UITextSizeConstraint", {
		MinTextSize = minSize or 7,
		MaxTextSize = maxSize or 18,
	}, label)
end

local function tween(instance, info, props)
	return TweenService:Create(instance, info, props)
end

local function addButtonFeel(button, hoverScale)
	local existingScale = button:FindFirstChildOfClass("UIScale")
	if button:GetAttribute("JuiceFeelApplied") then
		return existingScale
	end
	button:SetAttribute("JuiceFeelApplied", true)
	local scale = existingScale or new("UIScale", { Scale = 1 }, button)
	hoverScale = hoverScale or 1.025

	button.MouseEnter:Connect(function()
		tween(scale, TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = hoverScale,
		}):Play()
	end)
	button.MouseLeave:Connect(function()
		tween(scale, TweenInfo.new(0.13, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, TweenInfo.new(0.06), { Scale = 0.965 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = hoverScale,
		}):Play()
	end)
	return scale
end

local function priceText(info)
	local price = info and tonumber(info.PriceInRobux)
	if price then
		return "R$ " .. tostring(math.floor(price + 0.5))
	end
	return "VIEW OFFER"
end

local function imageForInfo(info)
	local assetId = info and tonumber(info.IconImageAssetId)
	if assetId and assetId > 0 then
		return ("rbxthumb://type=Asset&id=%d&w=420&h=420"):format(assetId)
	end
	return ""
end

-- =========================================================================
-- ROOT + MODAL SHELL
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "MonetizationStore",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 78,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Void,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 200,
}, screenGui)
backdrop:SetAttribute("PresentationModal", true)

local panelShadow = new("Frame", {
	Name = "PanelShadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 10, 0.5, 14),
	Size = UDim2.fromScale(0.74, 0.79),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.32,
	Visible = false,
	ZIndex = 201,
}, screenGui)
new("UISizeConstraint", { MinSize = Vector2.new(280, 300), MaxSize = Vector2.new(980, 720) }, panelShadow)
corner(panelShadow, UDim.new(0, 24))
local shadowScale = new("UIScale", { Scale = 0.84 }, panelShadow)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.74, 0.79),
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Visible = false,
	ZIndex = 202,
}, screenGui)
new("UISizeConstraint", { MinSize = Vector2.new(280, 300), MaxSize = Vector2.new(980, 720) }, panel)
corner(panel, UDim.new(0, 24))
local panelStroke = stroke(panel, THEME.Accent, 2.5, 0.06)
local panelScale = new("UIScale", { Scale = 0.84 }, panel)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(47, 27, 66)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(28, 17, 43)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 10, 26)),
	}),
	Rotation = 115,
}, panel)

local topAccent = new("Frame", {
	Name = "TopAccent",
	Size = UDim2.fromScale(1, 0.012),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 204,
}, panel)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.Green),
		ColorSequenceKeypoint.new(0.5, THEME.AccentLight),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(184, 114, 255)),
	}),
}, topAccent)

local header = new("Frame", {
	Name = "Header",
	Size = UDim2.fromScale(1, 0.19),
	BackgroundColor3 = THEME.Panel,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	ZIndex = 203,
}, panel)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(66, 37, 88), THEME.Panel),
	Rotation = 15,
}, header)

local marketMark = new("Frame", {
	Name = "MarketMark",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.038, 0.5),
	Size = UDim2.fromScale(0.085, 0.57),
	BackgroundColor3 = THEME.Accent,
	ZIndex = 205,
}, header)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, marketMark)
corner(marketMark, UDim.new(0.28, 0))
stroke(marketMark, THEME.AccentLight, 1.8, 0.08)
new("UIGradient", {
	Color = ColorSequence.new(THEME.AccentLight, Color3.fromRGB(218, 113, 66)),
	Rotation = 45,
}, marketMark)
local markText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "R$",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 206,
}, marketMark)
constrainText(markText, 12, 25)

local titleLabel = new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.145, 0.18),
	Size = UDim2.fromScale(0.56, 0.31),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = MonetizationConfig.StoreTitle,
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 205,
}, header)
constrainText(titleLabel, 15, 29)

local subtitleLabel = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.145, 0.5),
	Size = UDim2.fromScale(0.59, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = MonetizationConfig.StoreSubtitle,
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 205,
}, header)
constrainText(subtitleLabel, 8, 15)

local trustPill = new("Frame", {
	Name = "TrustPill",
	Position = UDim2.fromScale(0.145, 0.73),
	Size = UDim2.fromScale(0.39, 0.18),
	BackgroundColor3 = Color3.fromRGB(29, 84, 61),
	ZIndex = 205,
}, header)
corner(trustPill, UDim.new(1, 0))
stroke(trustPill, THEME.Green, 1, 0.35)
local trustText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "✓ LIVE PRICES  •  ROBLOX CHECKOUT",
	TextColor3 = THEME.Green,
	TextScaled = true,
	ZIndex = 206,
}, trustPill)
constrainText(trustText, 7, 11)

local supporterPill = new("Frame", {
	Name = "SupporterBlessing",
	Position = UDim2.fromScale(0.55, 0.73),
	Size = UDim2.fromScale(0.35, 0.18),
	BackgroundColor3 = Color3.fromRGB(92, 60, 27),
	ZIndex = 205,
}, header)
corner(supporterPill, UDim.new(1, 0))
local supporterStroke = stroke(supporterPill, THEME.AccentLight, 1, 0.2)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 7),
	PaddingRight = UDim.new(0, 7),
}, supporterPill)
local supporterText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = THEME.AccentLight,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 206,
}, supporterPill)
constrainText(supporterText, 5, 10)

local closeButton = new("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.968, 0.19),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = THEME.Raised,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextColor3 = THEME.Muted,
	TextSize = 25,
	ZIndex = 207,
}, header)
corner(closeButton, UDim.new(1, 0))
stroke(closeButton, THEME.Dim, 1, 0.48)
addButtonFeel(closeButton, 1.08)

-- =========================================================================
-- TABS + CATALOG GRID
-- =========================================================================

local tabsHolder = new("Frame", {
	Name = "Tabs",
	Position = UDim2.fromScale(0.035, 0.212),
	Size = UDim2.fromScale(0.93, 0.075),
	BackgroundTransparency = 1,
	ZIndex = 204,
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0.018, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tabsHolder)

local catalog = new("ScrollingFrame", {
	Name = "Catalog",
	Position = UDim2.fromScale(0.035, 0.305),
	Size = UDim2.fromScale(0.93, 0.64),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = THEME.Accent,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 204,
}, panel)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 16),
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 18),
}, catalog)

local grid = new("UIGridLayout", {
	CellSize = UDim2.fromOffset(240, 225),
	CellPadding = UDim2.fromOffset(14, 14),
	FillDirection = Enum.FillDirection.Horizontal,
	FillDirectionMaxCells = 3,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, catalog)

local footerText = new("TextLabel", {
	Name = "Footer",
	Position = UDim2.fromScale(0.04, 0.958),
	Size = UDim2.fromScale(0.92, 0.025),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Optional purchases only • Every benefit shown here is wired into gameplay",
	TextColor3 = THEME.Dim,
	TextScaled = true,
	ZIndex = 204,
}, panel)
constrainText(footerText, 7, 11)

local DEFAULT_FOOTER_TEXT = footerText.Text
local footerMessageToken = 0
local function showFooterMessage(message, color, duration)
	footerMessageToken += 1
	local token = footerMessageToken
	footerText.Text = message
	footerText.TextColor3 = color or THEME.Muted
	task.delay(duration or 3, function()
		if footerMessageToken == token and footerText.Parent then
			footerText.Text = DEFAULT_FOOTER_TEXT
			footerText.TextColor3 = THEME.Dim
		end
	end)
end

local tabButtons = {}
local currentCategory = "Featured"
local cardsById = {}
local productInfoById = {}
local locallyOwnedPasses = {}
local personalizedRankById = {}
local bestValueById = {}
local pendingOfferId = nil
local storeOpen = false
local storeOpenedThisSession = false
local selectedOfferId = nil
local currentOpenSource = "Unknown"
local viewedOfferIds = {}
local firstPurchaseClaimed = player:GetAttribute("FirstPurchaseBonusClaimed") == true
local storeBadgeLabels = {}

local function featuredDisplayOrder(offer)
	local rank = personalizedRankById[offer.Id]
	if rank then
		return rank
	end
	return 1000 + (offer.FeaturedOrder or 999)
end

local function recalculateBestValues()
	table.clear(bestValueById)
	local bestByGroup = {}
	for _, offer in ipairs(MonetizationConfig.Offers) do
		local info = productInfoById[offer.Id]
		local price = info and tonumber(info.PriceInRobux)
		local amount = tonumber(offer.ValueAmount)
		if offer.ValueGroup and price and price > 0 and amount and amount > 0 then
			local score = amount / price
			local previous = bestByGroup[offer.ValueGroup]
			if not previous or score > previous.Score then
				bestByGroup[offer.ValueGroup] = { Id = offer.Id, Score = score }
			end
		end
	end
	for _, result in pairs(bestByGroup) do
		bestValueById[result.Id] = true
	end
end

local function updateMerchandisingBadge(offer)
	local refs = cardsById[offer.Id]
	if not refs or not refs.ValueBadge then
		return
	end

	local text
	local color
	if not firstPurchaseClaimed then
		text = "FIRST BONUS"
		color = THEME.Accent
	elseif bestValueById[offer.Id] then
		text = "BEST VALUE"
		color = THEME.Green
	elseif personalizedRankById[offer.Id] and personalizedRankById[offer.Id] <= 3 then
		text = "FOR YOU"
		color = Color3.fromRGB(184, 114, 255)
	end

	refs.ValueBadge.Visible = text ~= nil
	if text then
		refs.ValueBadge.BackgroundColor3 = color
		refs.ValueBadgeText.Text = text
		refs.ValueBadgeText.TextColor3 = color
		refs.ValueBadgeStroke.Color = color
	end
end

local function updateSupporterBonusUI()
	if firstPurchaseClaimed then
		supporterPill.BackgroundColor3 = Color3.fromRGB(29, 84, 61)
		supporterStroke.Color = THEME.Green
		supporterText.TextColor3 = THEME.Green
		supporterText.Text = "✓ " .. MonetizationConfig.FirstPurchaseBonus.ClaimedText
	else
		supporterPill.BackgroundColor3 = Color3.fromRGB(92, 60, 27)
		supporterStroke.Color = THEME.AccentLight
		supporterText.TextColor3 = THEME.AccentLight
		supporterText.Text = "1ST BUY  •  " .. MonetizationConfig.FirstPurchaseBonus.OfferText
	end
	for _, offer in ipairs(MonetizationConfig.Offers) do
		updateMerchandisingBadge(offer)
	end
	for _, label in ipairs(storeBadgeLabels) do
		if label.Parent then
			label.Text = firstPurchaseClaimed and "R$" or "+10%"
		end
	end
end

local function trackOfferView(offer)
	if not storeOpen or viewedOfferIds[offer.Id] then
		return
	end
	viewedOfferIds[offer.Id] = true
	trackStoreAction("OfferViewed", offer.Id, currentOpenSource)
end

local function isOwned(offer)
	return locallyOwnedPasses[offer.Id] == true or MonetizationConfig.IsOwned(player, offer)
end

local function updateGridSize()
	local width = catalog.AbsoluteSize.X
	if width <= 0 then
		return
	end

	-- Reserve room for the catalog's UIPadding and scrollbar, then derive an
	-- exact pixel width. The previous scale-based cells consumed virtually
	-- 100% of the row and could press strokes/text into neighboring cards.
	local contentWidth = math.max(1, width - 12 - 16 - catalog.ScrollBarThickness)
	local columns
	local horizontalGap
	local cardHeight
	if width < 560 then
		columns = 1
		horizontalGap = 0
		cardHeight = 240
	elseif width < 760 then
		columns = 2
		horizontalGap = 12
		cardHeight = 232
	else
		columns = 3
		horizontalGap = 14
		cardHeight = 225
	end

	local cellWidth = math.floor((contentWidth - horizontalGap * (columns - 1)) / columns)
	grid.FillDirectionMaxCells = columns
	grid.CellSize = UDim2.fromOffset(cellWidth, cardHeight)
	grid.CellPadding = UDim2.fromOffset(horizontalGap, 14)
end

catalog:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateGridSize)

local function updateCard(offer)
	local refs = cardsById[offer.Id]
	if not refs then
		return
	end

	local info = productInfoById[offer.Id]
	local image = imageForInfo(info)
	refs.IconImage.Visible = image ~= ""
	refs.IconImage.Image = image
	refs.Symbol.Visible = image == ""

	if isOwned(offer) then
		refs.Buy.Active = false
		refs.Buy.BackgroundColor3 = Color3.fromRGB(38, 98, 67)
		refs.Buy.Text = "✓ OWNED"
		refs.Buy.TextColor3 = THEME.Green
	elseif info and info.IsForSale == false then
		refs.Buy.Active = false
		refs.Buy.BackgroundColor3 = THEME.Raised
		refs.Buy.Text = "UNAVAILABLE"
		refs.Buy.TextColor3 = THEME.Dim
	else
		refs.Buy.Active = true
		refs.Buy.BackgroundColor3 = offer.Accent
		refs.Buy.Text = priceText(info) .. "   •   BUY"
		refs.Buy.TextColor3 = THEME.Void
	end
	updateMerchandisingBadge(offer)
end

local function requestOfferPurchase(offer)
	if isOwned(offer) then
		NotificationService.Info("You already own this permanent perk.", {
			Title = "Perk Already Owned",
			Icon = "✓",
			Key = "store-owned:" .. offer.Id,
		})
		return
	end
	if not requestPurchase then
		showFooterMessage("Store connection is still loading • Please try again in a moment", THEME.Danger, 3)
		NotificationService.Error("The store connection is still loading. Try again in a moment.", {
			Title = "Store Not Ready",
			Key = "store-connection",
		})
		return
	end
	trackOfferView(offer)
	pendingOfferId = offer.Id
	if not analyticsRemote then
		-- LogPrompt on the server will create the authoritative session. Do
		-- not replay an older queued StoreOpened after checkout has started.
		table.clear(queuedAnalyticsEvents)
	end
	requestPurchase:FireServer(
		offer.Kind == "GamePass" and "gamepass" or "product",
		offer.Id,
		currentOpenSource
	)
end

local function createOfferCard(offer, displayOrder)
	local card = new("Frame", {
		Name = "Offer_" .. tostring(offer.Id),
		BackgroundColor3 = THEME.Panel,
		BorderSizePixel = 0,
		LayoutOrder = displayOrder,
		ZIndex = 205,
	}, catalog)
	corner(card, UDim.new(0, 15))
	local cardStroke = stroke(card, offer.Accent, 1.5, 0.42)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
	}, card)
	new("UIGradient", {
		Color = ColorSequence.new(THEME.Raised, THEME.Panel),
		Rotation = 115,
	}, card)

	local tag = new("Frame", {
		Name = "Tag",
		Position = UDim2.fromScale(0.045, 0.04),
		Size = UDim2.fromScale(0.62, 0.095),
		BackgroundColor3 = offer.Accent,
		BackgroundTransparency = 0.82,
		ZIndex = 206,
	}, card)
	corner(tag, UDim.new(1, 0))
	stroke(tag, offer.Accent, 1, 0.35)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
	}, tag)
	local tagText = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = offer.Tag,
		TextColor3 = offer.Accent,
		TextScaled = true,
		ZIndex = 207,
	}, tag)
	constrainText(tagText, 7, 11)

	local valueBadge = new("Frame", {
		Name = "ValueBadge",
		Position = UDim2.fromScale(0.69, 0.04),
		Size = UDim2.fromScale(0.265, 0.095),
		BackgroundColor3 = THEME.Accent,
		BackgroundTransparency = 0.83,
		Visible = false,
		ZIndex = 206,
	}, card)
	corner(valueBadge, UDim.new(1, 0))
	local valueBadgeStroke = stroke(valueBadge, THEME.Accent, 1, 0.25)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 5),
	}, valueBadge)
	local valueBadgeText = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = THEME.Accent,
		TextScaled = true,
		ZIndex = 207,
	}, valueBadge)
	constrainText(valueBadgeText, 6, 10)

	local iconHolder = new("Frame", {
		Name = "IconHolder",
		Position = UDim2.fromScale(0.045, 0.17),
		Size = UDim2.fromScale(0.28, 0.25),
		BackgroundColor3 = offer.Accent,
		BackgroundTransparency = 0.82,
		ZIndex = 206,
	}, card)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, iconHolder)
	corner(iconHolder, UDim.new(0.28, 0))
	stroke(iconHolder, offer.Accent, 1.5, 0.24)

	local iconImage = new("ImageLabel", {
		Name = "ProductIcon",
		Position = UDim2.fromScale(0.08, 0.08),
		Size = UDim2.fromScale(0.84, 0.84),
		BackgroundTransparency = 1,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		Visible = false,
		ZIndex = 207,
	}, iconHolder)
	corner(iconImage, UDim.new(0.2, 0))

	local symbol = new("TextLabel", {
		Name = "Symbol",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = offer.Symbol,
		TextColor3 = offer.Accent,
		TextScaled = true,
		ZIndex = 207,
	}, iconHolder)
	constrainText(symbol, 11, 23)

	local kindLabel = new("TextLabel", {
		Name = "Kind",
		Position = UDim2.fromScale(0.365, 0.17),
		Size = UDim2.fromScale(0.59, 0.075),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = offer.Kind == "GamePass" and "PERMANENT PASS" or "REPEATABLE BOOST",
		TextColor3 = THEME.Dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 206,
	}, card)
	constrainText(kindLabel, 6, 10)

	local offerTitle = new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromScale(0.365, 0.245),
		Size = UDim2.fromScale(0.59, 0.17),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = offer.Title,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 206,
	}, card)
	constrainText(offerTitle, 9, 16)

	local benefit = new("TextLabel", {
		Name = "Benefit",
		Position = UDim2.fromScale(0.045, 0.455),
		Size = UDim2.fromScale(0.91, 0.14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = offer.Benefit,
		TextColor3 = offer.Accent,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 206,
	}, card)
	constrainText(benefit, 7, 13)

	local detail = new("TextLabel", {
		Name = "Detail",
		Position = UDim2.fromScale(0.045, 0.605),
		Size = UDim2.fromScale(0.91, 0.14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = offer.Detail,
		TextColor3 = THEME.Muted,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 206,
	}, card)
	constrainText(detail, 6, 11)

	local buy = new("TextButton", {
		Name = "BuyButton",
		Position = UDim2.fromScale(0.045, 0.79),
		Size = UDim2.fromScale(0.91, 0.15),
		BackgroundColor3 = offer.Accent,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "VIEW OFFER",
		TextColor3 = THEME.Void,
		TextScaled = true,
		ZIndex = 207,
	}, card)
	corner(buy, UDim.new(0, 10))
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, buy)
	constrainText(buy, 8, 14)
	addButtonFeel(buy, 1.018)

	buy.Activated:Connect(function()
		requestOfferPurchase(offer)
	end)
	card.MouseEnter:Connect(function()
		trackOfferView(offer)
		tween(cardStroke, TweenInfo.new(0.14), { Transparency = 0.08 }):Play()
	end)
	card.MouseLeave:Connect(function()
		tween(cardStroke, TweenInfo.new(0.14), { Transparency = 0.42 }):Play()
	end)

	cardsById[offer.Id] = {
		Card = card,
		Stroke = cardStroke,
		Buy = buy,
		IconImage = iconImage,
		Symbol = symbol,
		ValueBadge = valueBadge,
		ValueBadgeText = valueBadgeText,
		ValueBadgeStroke = valueBadgeStroke,
	}
	updateCard(offer)
	updateMerchandisingBadge(offer)
end

local function clearCatalog()
	for _, child in ipairs(catalog:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	cardsById = {}
end

local function refreshTabs()
	for category, button in pairs(tabButtons) do
		local active = category == currentCategory
		button.BackgroundColor3 = active and THEME.Accent or THEME.Raised
		button.TextColor3 = active and THEME.Void or THEME.Muted
	end
end

local function renderCategory(category)
	currentCategory = category
	selectedOfferId = nil
	clearCatalog()
	for _, offer in ipairs(MonetizationConfig.GetOffers(category)) do
		local displayOrder = category == "Featured" and featuredDisplayOrder(offer) or offer.SortOrder
		createOfferCard(offer, displayOrder)
	end
	catalog.CanvasPosition = Vector2.new(0, 0)
	refreshTabs()
	task.defer(updateGridSize)
end

for order, category in ipairs({ "Featured", "Passes", "Boosts" }) do
	local button = new("TextButton", {
		Name = category .. "Tab",
		Size = UDim2.fromScale(0.22, 0.75),
		BackgroundColor3 = THEME.Raised,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = string.upper(category),
		TextColor3 = THEME.Muted,
		TextScaled = true,
		LayoutOrder = order,
		ZIndex = 205,
	}, tabsHolder)
	corner(button, UDim.new(1, 0))
	stroke(button, category == "Featured" and THEME.Accent or THEME.Dim, 1, 0.45)
	constrainText(button, 8, 13)
	addButtonFeel(button, 1.025)
	button.Activated:Connect(function()
		renderCategory(category)
	end)
	tabButtons[category] = button
end

renderCategory("Featured")
updateSupporterBonusUI()

player:GetAttributeChangedSignal("FirstPurchaseBonusClaimed"):Connect(function()
	local claimed = player:GetAttribute("FirstPurchaseBonusClaimed") == true
	local newlyClaimed = claimed and not firstPurchaseClaimed
	firstPurchaseClaimed = claimed
	updateSupporterBonusUI()

	if newlyClaimed then
		showFooterMessage("✓ Supporter Blessing unlocked • Permanent +10% essence is active", THEME.Green, 5)
		Juice.Punch(Juice.GetScale(supporterPill), 0.2, 0.45)
		Juice.PulseBackground(supporterPill, THEME.Green, 0.8)
	end
end)

-- Join-time ownership checks finish asynchronously on the server. Keep any
-- card that is already on-screen honest when one of those attributes arrives,
-- not only after a locally initiated purchase prompt finishes.
for _, offer in ipairs(MonetizationConfig.Offers) do
	if offer.Kind == "GamePass" then
		local watchedOffer = offer
		player:GetAttributeChangedSignal(MonetizationConfig.GetOwnershipAttribute(watchedOffer)):Connect(function()
			updateCard(watchedOffer)
		end)
	end
end

-- =========================================================================
-- OPEN / CLOSE + OFFER FOCUS
-- =========================================================================

local animationId = 0

local function closeStore()
	if not storeOpen then
		return
	end
	trackStoreAction("StoreClosed", selectedOfferId, currentOpenSource)
	storeOpen = false
	animationId += 1
	local thisAnimation = animationId
	tween(backdrop, TweenInfo.new(0.17), { BackgroundTransparency = 1 }):Play()
	tween(panelScale, TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	tween(shadowScale, TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()

	task.delay(0.18, function()
		if animationId == thisAnimation then
			backdrop.Visible = false
			panel.Visible = false
			panelShadow.Visible = false
		end
	end)
end

local function focusOffer(offerId)
	local refs = cardsById[offerId]
	if not refs then
		return
	end
	local offer = MonetizationConfig.GetOffer(offerId)
	if offer then
		trackOfferView(offer)
	end

	local maxScroll = math.max(0, catalog.AbsoluteCanvasSize.Y - catalog.AbsoluteWindowSize.Y)
	local relativeY = refs.Card.AbsolutePosition.Y - catalog.AbsolutePosition.Y
	local targetY = math.clamp(catalog.CanvasPosition.Y + relativeY - 12, 0, maxScroll)
	tween(catalog, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CanvasPosition = Vector2.new(0, targetY),
	}):Play()
	local scale = refs.Card:FindFirstChildOfClass("UIScale") or new("UIScale", { Scale = 1 }, refs.Card)
	Juice.Punch(scale, 0.08, 0.35)
	tween(refs.Stroke, TweenInfo.new(0.15), { Transparency = 0 }):Play()
	task.delay(1.4, function()
		if refs.Stroke.Parent then
			tween(refs.Stroke, TweenInfo.new(0.25), { Transparency = 0.42 }):Play()
		end
	end)
end

local function leadingOfferId(category)
	local leadingId
	local leadingOrder = math.huge
	for _, offer in ipairs(MonetizationConfig.GetOffers(category)) do
		local order = category == "Featured" and featuredDisplayOrder(offer) or offer.SortOrder
		if order < leadingOrder then
			leadingOrder = order
			leadingId = offer.Id
		end
	end
	return leadingId
end

local function openStore(offerId, source)
	storeOpenedThisSession = true
	local activeSpotlight = screenGui:FindFirstChild("OfferSpotlight")
	if activeSpotlight and activeSpotlight:IsA("GuiObject") then
		activeSpotlight.Visible = false
	end
	local wasOpen = storeOpen
	if not wasOpen then
		currentOpenSource = tostring(source or (offerId and "Featured" or "Unknown"))
		viewedOfferIds = {}
	end
	selectedOfferId = tonumber(offerId)
	local offer = selectedOfferId and MonetizationConfig.GetOffer(selectedOfferId) or nil
	if offer then
		-- Non-featured items must switch to their full category before focus.
		local category = offer.Featured and "Featured" or offer.Category
		renderCategory(category)
	elseif currentCategory ~= "Featured" then
		renderCategory("Featured")
	end
	-- renderCategory clears stale focus state for tab clicks; restore the
	-- explicit deep-link target after that rebuild.
	selectedOfferId = offer and offer.Id or nil

	if not wasOpen then
		local visibleOfferId = selectedOfferId or leadingOfferId(currentCategory)
		trackStoreAction("StoreOpened", visibleOfferId, currentOpenSource)
		if visibleOfferId then
			-- BeginStoreSession records the first visible offer as step two.
			viewedOfferIds[visibleOfferId] = true
		end
	end

	if storeOpen then
		if selectedOfferId then
			task.defer(function()
				focusOffer(selectedOfferId)
			end)
		end
		return
	end

	storeOpen = true
	animationId += 1
	backdrop.Visible = true
	panelShadow.Visible = true
	panel.Visible = true
	backdrop.BackgroundTransparency = 1
	panelScale.Scale = 0.84
	shadowScale.Scale = 0.84
	panelStroke.Transparency = 0.55

	tween(backdrop, TweenInfo.new(0.22), { BackgroundTransparency = 0.17 }):Play()
	tween(panelScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	tween(shadowScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	tween(panelStroke, TweenInfo.new(0.3), { Transparency = 0.06 }):Play()

	if selectedOfferId then
		task.delay(0.34, function()
			if storeOpen then
				focusOffer(selectedOfferId)
			end
		end)
	end
end

backdrop.Activated:Connect(closeStore)
closeButton.Activated:Connect(closeStore)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and storeOpen and input.KeyCode == Enum.KeyCode.Escape then
		closeStore()
	end
end)

-- Exposed at click time rather than relying on LocalScript execution order.
_G.EssenceboundStore = {
	Open = openStore,
	Close = closeStore,
	IsOpen = function()
		return storeOpen
	end,
}

-- =========================================================================
-- LIVE PRODUCT DATA + PURCHASE COMPLETION
-- =========================================================================

local function fetchProductInfo(offer)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(offer.Id, MonetizationConfig.GetInfoType(offer))
	end)

	-- Compatibility fallback for places running an engine build where only
	-- GetProductInfo is exposed. Both calls are client-side so personalized
	-- and regional prices remain eligible when supported.
	if not ok then
		ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(offer.Id, MonetizationConfig.GetInfoType(offer))
		end)
	end

	if ok and type(info) == "table" then
		productInfoById[offer.Id] = info
		recalculateBestValues()
		updateCard(offer)
		for _, catalogOffer in ipairs(MonetizationConfig.Offers) do
			updateMerchandisingBadge(catalogOffer)
		end
	end
end

local function refreshPersonalizedCatalog()
	for _, offer in ipairs(MonetizationConfig.Offers) do
		local refs = cardsById[offer.Id]
		if refs then
			if currentCategory == "Featured" then
				refs.Card.LayoutOrder = featuredDisplayOrder(offer)
			end
			updateCard(offer)
		end
	end
end

-- Roblox ranks this exact catalog for the current player. If the service is
-- unavailable (including older Studio builds), the authored FeaturedOrder
-- remains intact and checkout behaves exactly as before.
task.spawn(function()
	local identifiers = {}
	for _, offer in ipairs(MonetizationConfig.Offers) do
		table.insert(identifiers, {
			InfoType = MonetizationConfig.GetInfoType(offer),
			Id = offer.Id,
		})
	end

	local ok, rankedItems = pcall(function()
		return MarketplaceService:RankProductsAsync(identifiers)
	end)
	if not ok or type(rankedItems) ~= "table" then
		return
	end

	local nextRanks = {}
	for rank, rankedItem in ipairs(rankedItems) do
		local identifier = rankedItem.ProductIdentifier
		local id = identifier and tonumber(identifier.Id)
		if id and MonetizationConfig.GetOffer(id) then
			nextRanks[id] = rank
			if type(rankedItem.ProductInfo) == "table" then
				productInfoById[id] = rankedItem.ProductInfo
			end
		end
	end
	personalizedRankById = nextRanks
	recalculateBestValues()
	refreshPersonalizedCatalog()
end)

-- Three workers avoid firing thirteen yield-heavy marketplace requests on
-- one frame while still filling the catalog quickly.
do
	local nextOffer = 1
	for _ = 1, 3 do
		task.spawn(function()
			while true do
				local index = nextOffer
				nextOffer += 1
				local offer = MonetizationConfig.Offers[index]
				if not offer then
					break
				end
				fetchProductInfo(offer)
				task.wait(0.05)
			end
		end)
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasedPlayer, gamePassId, purchased)
	if purchasedPlayer ~= player then
		return
	end
	if not purchased then
		trackStoreAction("CheckoutCancelled", gamePassId, currentOpenSource)
		pendingOfferId = nil
		return
	end
	locallyOwnedPasses[gamePassId] = true
	local offer = MonetizationConfig.GetOffer(gamePassId)
	if offer then
		updateCard(offer)
	end
	showFooterMessage("✓ Permanent perk unlocked • Thank you!", THEME.Green, 4)
	NotificationService.Success("Your permanent perk is active now. Thank you for supporting EssenceBound!", {
		Title = "Permanent Perk Unlocked",
		Icon = "★",
		Duration = 4,
		Key = "store-gamepass-success:" .. gamePassId,
	})
	pendingOfferId = nil
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
	if userId == player.UserId and purchased and pendingOfferId == productId then
		showFooterMessage("✓ Purchase confirmed • Applying your reward", THEME.Green, 4)
		NotificationService.Success("Purchase confirmed — your reward is being applied now.", {
			Title = "Reward Incoming",
			Icon = "◆",
			Duration = 4,
			Key = "store-product-success:" .. productId,
		})
		pendingOfferId = nil
	elseif userId == player.UserId then
		trackStoreAction("CheckoutCancelled", productId, currentOpenSource)
		pendingOfferId = nil
	end
end)

-- =========================================================================
-- SHOP BUTTON BINDING + FALLBACK
-- =========================================================================

local function normalizedName(value)
	return string.lower(tostring(value)):gsub("button", ""):gsub("%s+", "")
end

local function findShopTrigger()
	local mainGui = playerGui:FindFirstChild("MainGui")
	local right = mainGui and mainGui:FindFirstChild("Right")
	local holder = right and right:FindFirstChild("Holder")
	if not holder then
		return nil, nil
	end

	for _, child in ipairs(holder:GetChildren()) do
		local isShop = normalizedName(child.Name) == "shop"
		if not isShop and child:IsA("TextButton") then
			isShop = string.find(string.lower(child.Text), "shop", 1, true) ~= nil
		end
		if not isShop then
			for _, descendant in ipairs(child:GetDescendants()) do
				if (descendant:IsA("TextLabel") or descendant:IsA("TextButton"))
					and string.find(string.lower(descendant.Text), "shop", 1, true)
				then
					isShop = true
					break
				end
			end
		end

		if isShop then
			local trigger = child:IsA("GuiButton") and child
				or child:FindFirstChildWhichIsA("TextButton", true)
				or child:FindFirstChildWhichIsA("ImageButton", true)
			if trigger then
				return trigger, child
			end
		end
	end
	return nil, holder
end

local function addStoreBadge(parent)
	if not parent:IsA("GuiObject") or parent:FindFirstChild("EssenceMarketBadge") then
		return
	end
	local badge = new("Frame", {
		Name = "EssenceMarketBadge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1.03, -0.05),
		Size = UDim2.fromScale(0.22, 0.3),
		BackgroundColor3 = THEME.Accent,
		ZIndex = math.max(50, parent.ZIndex + 3),
	}, parent)
	corner(badge, UDim.new(1, 0))
	stroke(badge, THEME.AccentLight, 1, 0.15)
	local label = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = firstPurchaseClaimed and "R$" or "+10%",
		TextColor3 = THEME.Void,
		TextScaled = true,
		ZIndex = badge.ZIndex + 1,
	}, badge)
	constrainText(label, 6, 10)
	table.insert(storeBadgeLabels, label)
end

local function createFallbackStoreButton()
	local holder = new("Frame", {
		Name = "FallbackStoreButtonHolder",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.84, 0.685),
		Size = UDim2.fromScale(0.13, 0.066),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, screenGui)
	local button = new("TextButton", {
		Name = "FallbackStoreButton",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Panel,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "R$  STORE",
		TextColor3 = THEME.White,
		TextScaled = true,
		ZIndex = 61,
	}, holder)
	corner(button, UDim.new(0.32, 0))
	stroke(button, THEME.Accent, 2, 0.08)
	new("UIGradient", {
		Color = ColorSequence.new(THEME.Raised, THEME.Panel),
		Rotation = 90,
	}, button)
	constrainText(button, 9, 15)
	addButtonFeel(button, 1.05)
	button.Activated:Connect(function()
		openStore(nil, "FallbackButton")
	end)
	addStoreBadge(holder)
end

task.spawn(function()
	local trigger, visualParent
	-- MainGui can arrive one replication step before its authored children.
	-- Give Shop a short grace window before deciding it is truly absent, or a
	-- healthy slow client could briefly get both the real and fallback entry.
	for _ = 1, 24 do
		trigger, visualParent = findShopTrigger()
		if trigger then
			break
		end
		task.wait(0.5)
	end

	if trigger then
		if not trigger:GetAttribute("EssenceMarketBound") then
			trigger:SetAttribute("EssenceMarketBound", true)
			trigger.Activated:Connect(function()
				openStore(nil, "ShopButton")
			end)
		end
		addStoreBadge(visualParent or trigger)
	else
		warn("MonetizationStore: Shop navigation button missing -- using code-created fallback.")
		createFallbackStoreButton()
	end
end)

-- =========================================================================
-- OPTIONAL, LIMITED INTEREST SPOTLIGHTS
-- =========================================================================

local spotlight = new("Frame", {
	Name = "OfferSpotlight",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.fromScale(0.72, 1.08),
	Size = UDim2.fromScale(0.31, 0.185),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 120,
}, screenGui)
new("UISizeConstraint", { MinSize = Vector2.new(280, 118), MaxSize = Vector2.new(410, 165) }, spotlight)
corner(spotlight, UDim.new(0, 17))
local spotlightStroke = stroke(spotlight, THEME.Accent, 2, 0.08)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(61, 35, 80), THEME.Panel),
	Rotation = 120,
}, spotlight)
local spotlightScale = new("UIScale", { Scale = 0.88 }, spotlight)

local spotlightAccent = new("Frame", {
	Name = "Accent",
	Size = UDim2.fromScale(0.018, 1),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 121,
}, spotlight)

local spotlightEyebrow = new("TextLabel", {
	Position = UDim2.fromScale(0.055, 0.08),
	Size = UDim2.fromScale(0.66, 0.14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "OPTIONAL POWER-UP",
	TextColor3 = THEME.AccentLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 121,
}, spotlight)
constrainText(spotlightEyebrow, 7, 11)

local spotlightTitle = new("TextLabel", {
	Position = UDim2.fromScale(0.055, 0.23),
	Size = UDim2.fromScale(0.82, 0.19),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "FEATURED OFFER",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 121,
}, spotlight)
constrainText(spotlightTitle, 10, 18)

local spotlightBenefit = new("TextLabel", {
	Position = UDim2.fromScale(0.055, 0.43),
	Size = UDim2.fromScale(0.89, 0.2),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 121,
}, spotlight)
constrainText(spotlightBenefit, 7, 12)

local spotlightView = new("TextButton", {
	Name = "ViewButton",
	Position = UDim2.fromScale(0.055, 0.69),
	Size = UDim2.fromScale(0.62, 0.22),
	BackgroundColor3 = THEME.Accent,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "VIEW IN STORE",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 122,
}, spotlight)
corner(spotlightView, UDim.new(0, 9))
constrainText(spotlightView, 8, 13)
addButtonFeel(spotlightView, 1.02)

local spotlightPrice = new("TextLabel", {
	Position = UDim2.fromScale(0.7, 0.69),
	Size = UDim2.fromScale(0.24, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = THEME.AccentLight,
	TextScaled = true,
	ZIndex = 121,
}, spotlight)
constrainText(spotlightPrice, 8, 14)

local spotlightClose = new("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.965, 0.065),
	Size = UDim2.fromOffset(28, 28),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextColor3 = THEME.Muted,
	TextSize = 20,
	ZIndex = 123,
}, spotlight)

local spotlightOffer = nil
local spotlightAnimationId = 0

local function hideSpotlight()
	if not spotlight.Visible then
		return
	end
	spotlightAnimationId += 1
	local thisAnimation = spotlightAnimationId
	tween(spotlight, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.72, 1.08),
	}):Play()
	tween(spotlightScale, TweenInfo.new(0.2), { Scale = 0.9 }):Play()
	task.delay(0.21, function()
		if spotlightAnimationId == thisAnimation then
			spotlight.Visible = false
			spotlightOffer = nil
		end
	end)
end

local function showSpotlight(offer)
	spotlightOffer = offer
	spotlightAnimationId += 1
	local thisAnimation = spotlightAnimationId
	local journeyOngoing = player:GetAttribute("FirstJourneyEligible") == true
		and player:GetAttribute("FirstJourneyCompleted") ~= true
	if journeyOngoing then
		spotlightEyebrow.Text = "OPTIONAL  •  EXTEND YOUR MOMENTUM"
	else
		spotlightEyebrow.Text = firstPurchaseClaimed
			and "OPTIONAL POWER-UP"
			or "FIRST PURCHASE BONUS INCLUDED"
	end
	spotlightAccent.BackgroundColor3 = offer.Accent
	spotlightStroke.Color = offer.Accent
	spotlightTitle.Text = offer.Headline
	if firstPurchaseClaimed then
		spotlightBenefit.Text = offer.Benefit
	else
		local bonus = MonetizationConfig.FirstPurchaseBonus
		spotlightBenefit.Text = ("%s  Plus +%d%% essence forever and a %dm 1.5× boost.")
			:format(offer.Benefit, bonus.PermanentPercent, math.floor(bonus.BoostSeconds / 60))
	end
	spotlightView.BackgroundColor3 = offer.Accent
	spotlightPrice.TextColor3 = offer.Accent
	spotlightPrice.Text = priceText(productInfoById[offer.Id])
	spotlight.Position = UDim2.fromScale(0.72, 1.08)
	spotlightScale.Scale = 0.88
	spotlight.Visible = true
	tween(spotlight, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.72, 0.9),
	}):Play()
	tween(spotlightScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	trackStoreAction("SpotlightShown", offer.Id, "Spotlight")

	task.delay(MonetizationConfig.Spotlights.VisibleSeconds, function()
		if spotlightAnimationId == thisAnimation and spotlight.Visible then
			hideSpotlight()
		end
	end)
end

spotlightClose.Activated:Connect(hideSpotlight)
spotlightView.Activated:Connect(function()
	local offer = spotlightOffer
	hideSpotlight()
	if offer then
		trackStoreAction("SpotlightClicked", offer.Id, "Spotlight")
		openStore(offer.Id, "Spotlight")
	end
end)

local shownSpotlights = {}
local journeyCompletedAtClock = nil

local function noteJourneyCompletion()
	if player:GetAttribute("FirstJourneyEligible") == true
		and player:GetAttribute("FirstJourneyCompleted") == true
		and not journeyCompletedAtClock
	then
		journeyCompletedAtClock = os.clock()
	end
end

player:GetAttributeChangedSignal("FirstJourneyEligible"):Connect(noteJourneyCompletion)
player:GetAttributeChangedSignal("FirstJourneyCompleted"):Connect(noteJourneyCompletion)
noteJourneyCompletion()

local function newcomerJourneyBlocksSpotlight()
	if player:GetAttribute("FirstJourneyEligible") ~= true then
		return false
	end
	if player:GetAttribute("FirstJourneyCompleted") ~= true then
		local activeSeconds = tonumber(player:GetAttribute("FirstJourneyActiveSeconds")) or 0
		return activeSeconds < FirstJourneyConfig.MonetizationUnlockAt
	end
	-- The attribute flips just before the finale RemoteEvent arrives. This
	-- grace closes the tiny race where a ten-second polling check could pass
	-- in that gap and show a spotlight milliseconds before the modal exists.
	return journeyCompletedAtClock ~= nil and os.clock() - journeyCompletedAtClock < 12
end

local function modalIsBusy()
	local presentationOwner = PresentationCoordinator.GetOwner()
	if presentationOwner and presentationOwner ~= "StoreSpotlight" then
		return true
	end
	if not presentationOwner and PresentationCoordinator.GetQueueDepth() > 0 then
		return true
	end
	if storeOpen or spotlight.Visible then
		return true
	end
	local menuOpen = false
	pcall(function()
		menuOpen = GuiService.MenuIsOpen
	end)
	if menuOpen then
		return true
	end

	-- Essence Awakening's twelve-minute convergence is intentionally modal
	-- but is not named "Backdrop" like the regular panels below. Treat it
	-- explicitly as busy so a Robux interest card can never slide over the
	-- most important new-player payoff in the session.
	local journeyGui = playerGui:FindFirstChild("FirstJourneyHud")
	if journeyGui and journeyGui:FindFirstChild("AwakeningFinale", true) then
		return true
	end

	for _, gui in ipairs(playerGui:GetChildren()) do
		if gui:IsA("ScreenGui") and gui ~= screenGui and gui.Enabled then
			for _, descendant in ipairs(gui:GetDescendants()) do
				if descendant.Name == "Backdrop"
					and descendant:IsA("GuiObject")
					and descendant.Active
					and descendant.Visible
				then
					local effectivelyVisible = true
					local ancestor = descendant.Parent
					while ancestor and ancestor ~= gui do
						if ancestor:IsA("GuiObject") and not ancestor.Visible then
							effectivelyVisible = false
							break
						end
						ancestor = ancestor.Parent
					end
					if effectivelyVisible then
						return true
					end
				end
			end
		end
	end
	return false
end

local function chooseSpotlight(promptNumber)
	local candidates = {}
	local totalWeight = 0

	for _, offer in ipairs(MonetizationConfig.Offers) do
		local info = productInfoById[offer.Id]
		local isAvailable = not info or info.IsForSale ~= false
		if isAvailable and not shownSpotlights[offer.Id] and not isOwned(offer) then
			if promptNumber > 1 or offer.FirstPurchaseFriendly then
				local weight = tonumber(offer.SpotlightWeight) or 1
				local price = info and tonumber(info.PriceInRobux)
				local rank = personalizedRankById[offer.Id]
				if rank then
					local catalogSize = math.max(1, #MonetizationConfig.Offers)
					weight *= 1 + math.max(0, catalogSize - rank + 1) / catalogSize
				end
				if not firstPurchaseClaimed and offer.FirstPurchaseFriendly then
					weight *= 1.35
				end
				-- During the first journey, favor a low-commitment boost that
				-- directly extends the loop the player is currently enjoying.
				local journeyOngoing = player:GetAttribute("FirstJourneyEligible") == true
					and player:GetAttribute("FirstJourneyCompleted") ~= true
				if journeyOngoing and offer.Title == "Mini Essence Potion" then
					weight *= 2.5
				end
				-- The first interest card leans toward approachable live prices,
				-- but still uses weighted randomness so one item isn't repeated.
				if promptNumber == 1 and price and price > 0 then
					weight *= 1 + math.min(4, 40 / price)
				end
				totalWeight += weight
				table.insert(candidates, { Offer = offer, Ceiling = totalWeight })
			end
		end
	end

	if totalWeight <= 0 then
		return nil
	end
	local roll = math.random() * totalWeight
	for _, candidate in ipairs(candidates) do
		if roll <= candidate.Ceiling then
			return candidate.Offer
		end
	end
	return candidates[#candidates] and candidates[#candidates].Offer or nil
end

local function waitForClearMoment()
	-- The first attempt begins around minute 2. A newcomer remains protected
	-- until minute 6, then may see one contextual interest card during a truly
	-- quiet moment. Returning players usually pass on the first iteration.
	for _ = 1, 72 do
		if storeOpenedThisSession then
			return false
		end
		if player:GetAttribute("SeenTutorial") == true
			and not newcomerJourneyBlocksSpotlight()
			and not modalIsBusy()
		then
			return true
		end
		task.wait(10)
	end
	return false
end

task.spawn(function()
	local rules = MonetizationConfig.Spotlights
	task.wait(math.random(rules.FirstDelayMin, rules.FirstDelayMax))
	local newcomerJourneyOngoing = player:GetAttribute("FirstJourneyEligible") == true
		and player:GetAttribute("FirstJourneyCompleted") ~= true
	local maximumPrompts = newcomerJourneyOngoing and 1 or rules.MaximumPerSession

	for promptNumber = 1, maximumPrompts do
		if storeOpenedThisSession or not waitForClearMoment() then
			break
		end

		local spotlightLease = PresentationCoordinator.Acquire("StoreSpotlight", {
			Priority = 32,
			QuietAfter = 0.8,
		})
		if not spotlightLease then
			break
		end

		-- A manual action may have happened while this low-priority request was
		-- queued. Re-check every eligibility condition before showing anything.
		if storeOpenedThisSession or newcomerJourneyBlocksSpotlight() or modalIsBusy() then
			PresentationCoordinator.Release(spotlightLease, 0.4)
			break
		end

		local offer = chooseSpotlight(promptNumber)
		if not offer then
			PresentationCoordinator.Release(spotlightLease, 0.4)
			break
		end
		shownSpotlights[offer.Id] = true
		local presentationOk, presentationError = xpcall(function()
			showSpotlight(offer)
			-- Viewing a spotlight transitions directly into the store. Retain the
			-- same foreground lease until that store closes so another automatic
			-- frame cannot appear over the purchase decision.
			while screenGui.Parent and (spotlight.Visible or storeOpen) do
				task.wait(0.1)
			end
		end, debug.traceback)
		if not presentationOk then
			hideSpotlight()
			if storeOpen then
				closeStore()
			end
			warn("[MonetizationStore] Spotlight presentation failed: " .. tostring(presentationError))
		end
		PresentationCoordinator.Release(spotlightLease, 0.8)

		if promptNumber < maximumPrompts then
			task.wait(math.random(rules.RepeatDelayMin, rules.RepeatDelayMax))
		end
	end
end)

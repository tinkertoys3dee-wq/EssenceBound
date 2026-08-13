--[[
	MonetizationAnalytics (ModuleScript -> ServerScriptService)
	===========================================================
	Server-authoritative measurement for the Essence Market conversion funnel.
	The client may report that UI was shown or clicked, but this module validates
	every offer/action, rate-limits the remote, creates funnel session ids on the
	server, and logs actual purchase completion only from ProcessReceipt or the
	game-pass completion handler.

	Creator Hub's Funnel dashboard will expose the useful question directly:
	Store Opened -> Offer Viewed -> Checkout Prompted -> Purchase Completed.
	Spotlight impressions/clicks are separate custom events so their click-through
	rate can be measured without pretending an interest card is a checkout step.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local MonetizationAnalytics = {}

local FUNNEL_NAME = "EssenceMarketCheckoutV1"
local MAX_REMOTE_EVENTS_PER_MINUTE = 24

local sessions = {}
local spotlightActivity = {}
local remoteBudgets = {}

local allowedSources = {
	ShopButton = true,
	FallbackButton = true,
	Spotlight = true,
	Featured = true,
	DirectPrompt = true,
	Unknown = true,
}

local customFieldKeys = { "CustomField01", "CustomField02", "CustomField03" }
pcall(function()
	customFieldKeys = {
		Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
	}
end)

local function getOffer(offerId)
	return MonetizationConfig.GetOffer(tonumber(offerId))
end

local function cleanSource(source)
	source = tostring(source or "Unknown")
	return allowedSources[source] and source or "Unknown"
end

local function fieldsFor(offer, source)
	return {
		[customFieldKeys[1]] = offer and offer.Kind or "Unknown",
		[customFieldKeys[2]] = offer and tostring(offer.Id) or "None",
		[customFieldKeys[3]] = cleanSource(source),
	}
end

local function safeFunnelLog(player, session, step, stepName, offer)
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			FUNNEL_NAME,
			session.Id,
			step,
			stepName,
			fieldsFor(offer, session.Source)
		)
	end)
	if not ok then
		warn(("MonetizationAnalytics: funnel step %d failed for %s: %s")
			:format(step, player.Name, tostring(err)))
	end
end

local function safeCustomLog(player, eventName, value, offer, source)
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(
			player,
			eventName,
			tonumber(value) or 1,
			fieldsFor(offer, source)
		)
	end)
	if not ok then
		warn(("MonetizationAnalytics: custom event %s failed for %s: %s")
			:format(eventName, player.Name, tostring(err)))
	end
end

local function newSessionId(player)
	local ok, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok and type(guid) == "string" then
		return guid
	end
	return ("%d-%d-%d"):format(player.UserId, os.time(), math.floor(os.clock() * 1000))
end

function MonetizationAnalytics.BeginStoreSession(player, offerId, source)
	if not player or not player:IsA("Player") then
		return
	end

	local offer = getOffer(offerId)
	local session = {
		Id = newSessionId(player),
		Source = cleanSource(source),
		OfferId = offer and offer.Id or nil,
		ViewedOffers = {},
		HighestStep = 1,
	}
	sessions[player] = session
	safeFunnelLog(player, session, 1, "Store Opened", offer)

	if offer then
		MonetizationAnalytics.ViewOffer(player, offer.Id, source)
	end
end

function MonetizationAnalytics.ViewOffer(player, offerId, source)
	local offer = getOffer(offerId)
	if not offer then
		return
	end

	local session = sessions[player]
	if not session then
		MonetizationAnalytics.BeginStoreSession(player, offer.Id, source or "Featured")
		return
	end
	if session.ViewedOffers[offer.Id] then
		return
	end

	session.ViewedOffers[offer.Id] = true
	session.OfferId = offer.Id
	if session.HighestStep < 2 then
		session.HighestStep = 2
		safeFunnelLog(player, session, 2, "Offer Viewed", offer)
	end
end

function MonetizationAnalytics.LogPrompt(player, offerId, source)
	local offer = getOffer(offerId)
	if not offer then
		return
	end

	if not sessions[player] then
		MonetizationAnalytics.BeginStoreSession(player, offer.Id, source or "DirectPrompt")
	else
		MonetizationAnalytics.ViewOffer(player, offer.Id, source)
	end

	local session = sessions[player]
	if not session then
		return
	end
	session.OfferId = offer.Id
	if session.HighestStep < 3 then
		session.HighestStep = 3
		safeFunnelLog(player, session, 3, "Checkout Prompted", offer)
	end
end

function MonetizationAnalytics.LogPurchase(player, offerId, robuxSpent)
	local offer = getOffer(offerId)
	if not offer then
		return
	end

	local session = sessions[player]
	local source = session and session.Source or "Unknown"
	safeCustomLog(player, "MonetizationPurchaseCompleted", math.max(0, tonumber(robuxSpent) or 0), offer, source)

	if session and (session.OfferId == nil or session.OfferId == offer.Id) then
		session.OfferId = offer.Id
		session.HighestStep = 4
		safeFunnelLog(player, session, 4, "Purchase Completed", offer)
		sessions[player] = nil
	end
end

function MonetizationAnalytics.LogSpotlight(player, action, offerId)
	local offer = getOffer(offerId)
	if not offer or (action ~= "Shown" and action ~= "Clicked") then
		return
	end

	local state = spotlightActivity[player]
	if not state then
		state = { Shown = {}, Clicked = {} }
		spotlightActivity[player] = state
	end
	if state[action][offer.Id] then
		return
	end
	state[action][offer.Id] = true

	safeCustomLog(player, "MonetizationSpotlight" .. action, 1, offer, "Spotlight")
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local analyticsRemote = remotes:FindFirstChild("MonetizationAnalytics")
if analyticsRemote and not analyticsRemote:IsA("RemoteEvent") then
	analyticsRemote:Destroy()
	analyticsRemote = nil
end
if not analyticsRemote then
	analyticsRemote = Instance.new("RemoteEvent")
	analyticsRemote.Name = "MonetizationAnalytics"
	analyticsRemote.Parent = remotes
end

local function hasRemoteBudget(player)
	local now = os.clock()
	local budget = remoteBudgets[player]
	if not budget or now - budget.WindowStartedAt >= 60 then
		budget = { WindowStartedAt = now, Count = 0 }
		remoteBudgets[player] = budget
	end
	if budget.Count >= MAX_REMOTE_EVENTS_PER_MINUTE then
		return false
	end
	budget.Count += 1
	return true
end

analyticsRemote.OnServerEvent:Connect(function(player, action, offerId, source)
	if not hasRemoteBudget(player) then
		return
	end

	if action == "StoreOpened" then
		MonetizationAnalytics.BeginStoreSession(player, offerId, source)
	elseif action == "OfferViewed" then
		MonetizationAnalytics.ViewOffer(player, offerId, source)
	elseif action == "SpotlightShown" then
		MonetizationAnalytics.LogSpotlight(player, "Shown", offerId)
	elseif action == "SpotlightClicked" then
		MonetizationAnalytics.LogSpotlight(player, "Clicked", offerId)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	spotlightActivity[player] = nil
	remoteBudgets[player] = nil
end)

return MonetizationAnalytics

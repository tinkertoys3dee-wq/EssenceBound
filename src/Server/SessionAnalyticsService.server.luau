--[[
	SessionAnalyticsService (Script -> ServerScriptService)
	======================================================
	Server-authoritative retention diagnostics for the opening session.

	The depth funnel answers WHEN players leave. The first-journey funnel and
	exit summaries answer WHY: no accepted action, a specific journey stage,
	a missed reward, or a particular storefront outcome. High-frequency gameplay
	is aggregated in memory and emitted only at exit, keeping the event stream
	useful without logging every click or collection.

	Analytics is observational only. It never participates in rewards, saves,
	progression, or purchase decisions, so an analytics outage cannot affect play.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameplaySignals = require(ServerScriptService:WaitForChild("GameplaySignals"))
local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))

local SESSION_FUNNEL_NAME = "SessionDepthV2"
local JOURNEY_FUNNEL_NAME = "FirstJourneyV2"

local DEPTH_STEPS = {
	{ Seconds = 0, Step = 1, Name = "Session Started" },
	{ Seconds = 60, Step = 2, Name = "Reached 1 Minute" },
	{ Seconds = 180, Step = 3, Name = "Reached 3 Minutes" },
	{ Seconds = 300, Step = 4, Name = "Reached 5 Minutes" },
	{ Seconds = 480, Step = 5, Name = "Reached 8 Minutes" },
	{ Seconds = 600, Step = 6, Name = "Reached 10 Minutes" },
	{ Seconds = 720, Step = 7, Name = "Reached 12 Minutes" },
	{ Seconds = 900, Step = 8, Name = "Reached 15 Minutes" },
}

-- Ten ordered checkpoints keep the funnel compact enough to read while still
-- exposing the major first-session failure points. Stage thresholds refer to
-- the NEXT active stage, so MinStage 2 means stage 1 was completed.
local JOURNEY_STEPS = {
	{ Step = 1, Name = "Journey Session Started", MinStage = 1 },
	{ Step = 2, Name = "First Spark Complete", MinStage = 2 },
	{ Step = 3, Name = "Click Rhythm Complete", MinStage = 3 },
	{ Step = 4, Name = "First Upgrade Complete", MinStage = 4 },
	{ Step = 5, Name = "Veil Goal Complete", MinStage = 5 },
	{ Step = 6, Name = "Prophecy Goal Complete", MinStage = 6 },
	{ Step = 7, Name = "Rush Goal Complete", MinStage = 7 },
	{ Step = 8, Name = "Six Minute Charge Complete", MinStage = 9 },
	{ Step = 9, Name = "Eight Minute Growth Complete", MinStage = 10 },
	{ Step = 10, Name = "Journey Completed", RequiresCompletion = true },
}

local MILESTONE_ORDER = {
	"FirstClick",
	"FirstCollection",
	"TutorialComplete",
	"FirstUpgrade",
	"FirstProphecy",
	"FirstPlaytimeReward",
	"FirstSpotlightShow",
	"FirstSpotlightClick",
	"FirstStoreOpen",
	"FirstCheckoutPrompt",
	"FirstPurchase",
}

local MILESTONE_LABELS = {
	FirstClick = "FirstClick",
	FirstCollection = "FirstCollection",
	TutorialComplete = "TutorialComplete",
	FirstUpgrade = "FirstUpgrade",
	FirstProphecy = "FirstProphecy",
	FirstPlaytimeReward = "FirstPlaytimeReward",
	FirstSpotlightShow = "FirstSpotlightShow",
	FirstSpotlightClick = "FirstSpotlightClick",
	FirstStoreOpen = "FirstStoreOpen",
	FirstCheckoutPrompt = "FirstCheckoutPrompt",
	FirstPurchase = "FirstPurchase",
}

local ENGAGEMENT_METRICS = {
	{ Label = "ManualClicks", Field = "ManualClicks" },
	{ Label = "Collections", Field = "Collections" },
	{ Label = "CriticalCollections", Field = "CriticalCollections" },
	{ Label = "GoldenCollections", Field = "GoldenCollections" },
	{ Label = "Upgrades", Field = "Upgrades" },
	{ Label = "PlaytimeRewards", Attribute = "SessionPlaytimeChestsClaimed" },
	{ Label = "Prophecies", Attribute = "SessionProphecyRolls" },
}

local CONVERSION_METRICS = {
	{ Label = "StoreOpens", Attribute = "SessionStoreOpens" },
	{ Label = "OfferViews", Attribute = "SessionOfferViews" },
	{ Label = "SpotlightShows", Attribute = "SessionSpotlightShows" },
	{ Label = "SpotlightClicks", Attribute = "SessionSpotlightClicks" },
	{ Label = "CheckoutPrompts", Attribute = "SessionCheckoutPrompts" },
	{ Label = "CheckoutCancels", Attribute = "SessionCheckoutCancels" },
	{ Label = "Purchases", Attribute = "SessionPurchaseCount" },
	{ Label = "RobuxSpent", Attribute = "SessionRobuxSpent" },
}

local sessions = {}

local customFieldKeys = { "CustomField01", "CustomField02", "CustomField03" }
pcall(function()
	customFieldKeys = {
		Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
	}
end)

local function metricValue(player: Player, attribute: string): number
	return math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
end

local function elapsedSeconds(session): number
	return math.max(0, math.floor(os.clock() - session.JoinedAt))
end

local function newSessionId(player: Player, suffix: string): string
	local ok, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok and type(guid) == "string" then
		return guid
	end
	return ("%d-%d-%d-%s"):format(
		player.UserId,
		os.time(),
		math.floor(os.clock() * 1000),
		suffix
	)
end

local function stageLabel(player: Player): string
	if player:GetAttribute("FirstJourneyCompleted") == true then
		return "JourneyComplete"
	end
	if player:GetAttribute("FirstJourneyEligible") ~= true then
		return "NoJourney"
	end
	return ("Stage%02d"):format(math.max(
		1,
		math.floor(tonumber(player:GetAttribute("FirstJourneyStage")) or 1)
	))
end

local function lifetimePayerLabel(player: Player): string
	return metricValue(player, "PurchaseCount") > 0 and "LifetimePayer" or "NonPayer"
end

local function determineSegment(player: Player): string
	if player:GetAttribute("PlayerDataLoadStatus") == "FallbackAfterError" then
		return "DataFallback"
	end
	if player:GetAttribute("IsBrandNewPlayer") == true then
		return "FreshJourney"
	end
	if player:GetAttribute("FirstJourneyEligible") == true
		and player:GetAttribute("FirstJourneyCompleted") ~= true
	then
		return "ResumedJourney"
	end
	if player:GetAttribute("FirstJourneyCompleted") == true then
		return "JourneyGraduate"
	end
	return "LegacyReturning"
end

local function depthBucket(seconds: number): string
	if seconds < 30 then
		return "Under30s"
	elseif seconds < 90 then
		return "30to89s"
	elseif seconds < 180 then
		return "90to179s"
	elseif seconds < 300 then
		return "3to4m"
	elseif seconds < 480 then
		return "5to7m"
	elseif seconds < 720 then
		return "8to11m"
	elseif seconds < 900 then
		return "12to14m"
	end
	return "15mPlus"
end

local function conversionState(player: Player): string
	if metricValue(player, "SessionPurchaseCount") > 0 then
		return "Purchased"
	elseif metricValue(player, "SessionCheckoutCancels") > 0 then
		return "CheckoutCancelled"
	elseif metricValue(player, "SessionCheckoutPrompts") > 0 then
		return "PromptedNoPurchase"
	elseif metricValue(player, "SessionOfferViews") > 0 then
		return "ViewedNoPrompt"
	elseif metricValue(player, "SessionStoreOpens") > 0 then
		return "OpenedNoView"
	elseif metricValue(player, "SessionSpotlightClicks") > 0 then
		return "SpotlightClicked"
	elseif metricValue(player, "SessionSpotlightShows") > 0 then
		return "SpotlightOnly"
	end
	return "NoStoreExposure"
end

local function depthFields(player: Player, session)
	return {
		[customFieldKeys[1]] = session.Segment or "Loading",
		-- Funnel filters are easiest to trust when their dimensions do not
		-- mutate between steps. Current stage is emitted separately below.
		[customFieldKeys[2]] = session.EntryStageLabel
			or ("EntryStage%02d"):format(session.EntryStage or 1),
		-- Keep the payer cohort fixed at entry. A first purchase mid-session
		-- should not move one person between field values halfway down a funnel.
		[customFieldKeys[3]] = session.EntryPayerLabel or lifetimePayerLabel(player),
	}
end

local function checkpointFields(session, checkpoint: string)
	return {
		[customFieldKeys[1]] = session.Segment or "Loading",
		[customFieldKeys[2]] = session.EntryPayerLabel or "NonPayer",
		[customFieldKeys[3]] = checkpoint,
	}
end

local function journeyStageValue(player: Player): number
	if player:GetAttribute("FirstJourneyEligible") ~= true then
		return 0
	end
	return math.max(1, math.floor(tonumber(player:GetAttribute("FirstJourneyStage")) or 1))
end

local function journeyFields(player: Player, session)
	return {
		[customFieldKeys[1]] = session.Segment or "Loading",
		[customFieldKeys[2]] = ("EntryStage%02d"):format(session.EntryStage or 1),
		[customFieldKeys[3]] = session.EntryPayerLabel or lifetimePayerLabel(player),
	}
end

local function milestoneFields(player: Player, session, milestone: string)
	return {
		[customFieldKeys[1]] = session.Segment or "Loading",
		[customFieldKeys[2]] = stageLabel(player),
		[customFieldKeys[3]] = milestone,
	}
end

local function summaryFields(player: Player, session)
	return {
		[customFieldKeys[1]] = session.Segment or "Loading",
		[customFieldKeys[2]] = stageLabel(player),
		[customFieldKeys[3]] = conversionState(player),
	}
end

local function metricFields(session, seconds: number, metric: string)
	return {
		[customFieldKeys[1]] = session.Segment or "Loading",
		[customFieldKeys[2]] = depthBucket(seconds),
		[customFieldKeys[3]] = metric,
	}
end

local function safeFunnelLog(player: Player, funnelName: string, sessionId: string, definition, fields)
	if RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			funnelName,
			sessionId,
			definition.Step,
			definition.Name,
			fields
		)
	end)
	if not ok then
		warn(("SessionAnalyticsService: %s step %d failed for %s: %s")
			:format(funnelName, definition.Step, player.Name, tostring(err)))
	end
end

local function safeCustomLog(player: Player, eventName: string, value: number, fields)
	if RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, tonumber(value) or 0, fields or {})
	end)
	if not ok then
		warn(("SessionAnalyticsService: event %s failed for %s: %s")
			:format(eventName, player.Name, tostring(err)))
	end
end

local function logMilestone(player: Player, key: string)
	local session = sessions[player]
	if not session or session.Milestones[key] ~= nil then
		return
	end

	local seconds = elapsedSeconds(session)
	session.Milestones[key] = seconds
	if session.Ready then
		safeCustomLog(
			player,
			"SessionMilestoneSecondsV2",
			seconds,
			milestoneFields(player, session, MILESTONE_LABELS[key] or key)
		)
		session.LoggedMilestones[key] = true
	end
end

local function flushMilestones(player: Player, session)
	for _, key in ipairs(MILESTONE_ORDER) do
		local seconds = session.Milestones[key]
		if seconds ~= nil and not session.LoggedMilestones[key] then
			safeCustomLog(
				player,
				"SessionMilestoneSecondsV2",
				seconds,
				milestoneFields(player, session, MILESTONE_LABELS[key] or key)
			)
			session.LoggedMilestones[key] = true
		end
	end
end

local function journeyStepReached(player: Player, definition): boolean
	if definition.RequiresCompletion then
		return player:GetAttribute("FirstJourneyCompleted") == true
	end
	local stage = math.max(1, math.floor(tonumber(player:GetAttribute("FirstJourneyStage")) or 1))
	return stage >= (definition.MinStage or 1)
end

local function updateJourneyFunnel(player: Player, session)
	if not session.Ready or not session.JourneyActiveAtEntry then
		return
	end

	while session.NextJourneyIndex <= #JOURNEY_STEPS do
		local definition = JOURNEY_STEPS[session.NextJourneyIndex]
		if not journeyStepReached(player, definition) then
			break
		end
		safeFunnelLog(
			player,
			JOURNEY_FUNNEL_NAME,
			session.JourneyId,
			definition,
			journeyFields(player, session)
		)
		session.NextJourneyIndex += 1
	end
end

local function updateDepthFunnel(player: Player, session)
	if not session.Ready then
		return
	end
	local elapsed = elapsedSeconds(session)
	while session.NextDepthIndex <= #DEPTH_STEPS do
		local definition = DEPTH_STEPS[session.NextDepthIndex]
		if elapsed < definition.Seconds then
			break
		end
		safeFunnelLog(
			player,
			SESSION_FUNNEL_NAME,
			session.Id,
			definition,
			depthFields(player, session)
		)
		safeCustomLog(
			player,
			"SessionCheckpointStageV2",
			journeyStageValue(player),
			checkpointFields(session, ("Step%02d"):format(definition.Step))
		)
		session.NextDepthIndex += 1
	end
end

local function updateAttributeMetrics(player: Player, session, attribute: string)
	if attribute == "SeenTutorial"
		and player:GetAttribute("SeenTutorial") == true
		and not session.TutorialCompleteAtEntry
	then
		logMilestone(player, "TutorialComplete")
	elseif attribute == "SessionPlaytimeChestsClaimed" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstPlaytimeReward")
		end
	elseif attribute == "SessionProphecyRolls" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstProphecy")
		end
	elseif attribute == "SessionSpotlightShows" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstSpotlightShow")
		end
	elseif attribute == "SessionSpotlightClicks" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstSpotlightClick")
		end
	elseif attribute == "SessionStoreOpens" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstStoreOpen")
		end
	elseif attribute == "SessionCheckoutPrompts" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstCheckoutPrompt")
		end
	elseif attribute == "SessionPurchaseCount" then
		if metricValue(player, attribute) > 0 then
			logMilestone(player, "FirstPurchase")
		end
	elseif attribute == "FirstJourneyStage" or attribute == "FirstJourneyCompleted" then
		updateJourneyFunnel(player, session)
	end

	local definition = TreeUpgrades.ById and TreeUpgrades.ById[attribute]
	if not definition then
		return
	end
	local current = math.max(0, math.floor(tonumber(player:GetAttribute(attribute)) or 0))
	local previous = session.UpgradeLevels[attribute] or current
	session.UpgradeLevels[attribute] = current
	if current > previous then
		session.Upgrades += current - previous
		logMilestone(player, "FirstUpgrade")
	end
end

GameplaySignals.OnClickAccepted(function(player: Player, payload)
	if type(payload) == "table" and payload.WasTrickle == true then
		return
	end
	local session = sessions[player]
	if not session then
		return
	end
	session.ManualClicks += 1
	logMilestone(player, "FirstClick")
end)

GameplaySignals.OnCollectionAccepted(function(player: Player, payload)
	local session = sessions[player]
	if not session then
		return
	end
	session.Collections += 1
	if type(payload) == "table" and payload.IsCritical == true then
		session.CriticalCollections += 1
	end
	if type(payload) == "table" and payload.IsGolden == true then
		session.GoldenCollections += 1
	end
	logMilestone(player, "FirstCollection")
end)

local function finishInitialization(player: Player, session)
	-- FirstJourneyService mirrors its detailed stage just after data loading.
	-- Wait briefly so a returning graduate is never mislabelled as Stage01.
	local stageDeadline = os.clock() + 3
	while player.Parent
		and player:GetAttribute("FirstJourneyEligible") == true
		and player:GetAttribute("FirstJourneyStage") == nil
		and os.clock() < stageDeadline
	do
		task.wait(0.05)
	end
	if not player.Parent or sessions[player] ~= session then
		return
	end

	session.Segment = determineSegment(player)
	session.EntryStage = math.max(
		1,
		math.floor(tonumber(player:GetAttribute("FirstJourneyStage")) or 1)
	)
	session.EntryStageLabel = stageLabel(player)
	session.EntryPayerLabel = lifetimePayerLabel(player)
	session.JourneyActiveAtEntry = player:GetAttribute("FirstJourneyEligible") == true
		and player:GetAttribute("FirstJourneyCompleted") ~= true
	-- Returning players who completed the tutorial in an earlier session must
	-- not appear as a zero-second completion in this session's milestone chart.
	-- A fresh save can only become SeenTutorial=true during this very join.
	session.TutorialCompleteAtEntry = player:GetAttribute("SeenTutorial") == true
		and session.Segment ~= "FreshJourney"

	for _, definition in ipairs(TreeUpgrades.List or {}) do
		session.UpgradeLevels[definition.Id] = math.max(
			0,
			math.floor(tonumber(player:GetAttribute(definition.Id)) or 0)
		)
	end

	session.AttributeConnection = player.AttributeChanged:Connect(function(attribute)
		updateAttributeMetrics(player, session, attribute)
	end)
	session.Ready = true

	-- Reconcile events that may have happened in the narrow gap between data
	-- becoming available and this observer connecting.
	for _, attribute in ipairs({
		"SeenTutorial",
		"SessionPlaytimeChestsClaimed",
		"SessionProphecyRolls",
		"SessionSpotlightShows",
		"SessionSpotlightClicks",
		"SessionStoreOpens",
		"SessionCheckoutPrompts",
		"SessionPurchaseCount",
	}) do
		updateAttributeMetrics(player, session, attribute)
	end
	flushMilestones(player, session)
	updateJourneyFunnel(player, session)
	-- Log the denominator immediately; sub-second exits after data readiness
	-- must still appear in SessionDepthV2 instead of vanishing from the funnel.
	updateDepthFunnel(player, session)
end

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end

	local session = {
		Id = newSessionId(player, "depth"),
		JourneyId = newSessionId(player, "journey"),
		JoinedAt = os.clock(),
		NextDepthIndex = 1,
		NextJourneyIndex = 1,
		Ready = false,
		LoadTimeoutLogged = false,
		Segment = "Loading",
		Milestones = {},
		LoggedMilestones = {},
		UpgradeLevels = {},
		ManualClicks = 0,
		Collections = 0,
		CriticalCollections = 0,
		GoldenCollections = 0,
		Upgrades = 0,
	}
	sessions[player] = session

	task.spawn(function()
		while player.Parent and player:GetAttribute("PlayerDataLoaded") ~= true do
			if not session.LoadTimeoutLogged and elapsedSeconds(session) >= 35 then
				session.LoadTimeoutLogged = true
				safeCustomLog(player, "SessionLoadTimeoutV2", elapsedSeconds(session), {
					[customFieldKeys[1]] = "Loading",
					[customFieldKeys[2]] = "DataNotReady",
					[customFieldKeys[3]] = "StillConnected",
				})
			end
			task.wait(0.1)
		end
		if not player.Parent or sessions[player] ~= session then
			return
		end
		finishInitialization(player, session)
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		for player, session in pairs(sessions) do
			if not player.Parent or not session.Ready then
				continue
			end
			updateDepthFunnel(player, session)
		end
	end
end)

local function logExitMetrics(player: Player, session)
	local seconds = elapsedSeconds(session)
	if not session.Ready then
		safeCustomLog(player, "SessionLoadExitV2", seconds, {
			[customFieldKeys[1]] = "Loading",
			[customFieldKeys[2]] = session.LoadTimeoutLogged and "LoadTimedOut" or "LoadPending",
			[customFieldKeys[3]] = depthBucket(seconds),
		})
		return
	end

	safeCustomLog(player, "SessionExitSummaryV2", seconds, summaryFields(player, session))

	for _, metric in ipairs(ENGAGEMENT_METRICS) do
		local value = metric.Attribute and metricValue(player, metric.Attribute)
			or math.max(0, math.floor(tonumber(session[metric.Field]) or 0))
		safeCustomLog(
			player,
			"SessionEngagementCountV2",
			value,
			metricFields(session, seconds, metric.Label)
		)
	end

	for _, metric in ipairs(CONVERSION_METRICS) do
		safeCustomLog(
			player,
			"SessionConversionCountV2",
			metricValue(player, metric.Attribute),
			metricFields(session, seconds, metric.Label)
		)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player: Player)
	local session = sessions[player]
	if session then
		logExitMetrics(player, session)
		if session.AttributeConnection then
			session.AttributeConnection:Disconnect()
		end
	end
	sessions[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

--[[
	FirstJourneyService (Script -> ServerScriptService)
	==================================================
	Server-authoritative twelve-minute new-player journey. The client can
	display progress but cannot claim, skip, choose reward amounts or advance
	a stage. Progress comes from accepted server gameplay signals and
	server-written attributes; rewards are paid here exactly once.

	Only saves proven brand-new by PlayerDataHandler are eligible. Active time
	pauses offline, persists across rejoins and caps at twelve minutes. If a
	player still needs an objective at that point, their personal 2x rush stays
	active until they finish instead of punishing them for learning slowly.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local FirstJourneyConfig = require(ReplicatedStorage:WaitForChild("FirstJourneyConfig"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))
local GameplaySignals = require(ServerScriptService:WaitForChild("GameplaySignals"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local function ensureRemote(parent: Instance, className: string, name: string)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		warn(("FirstJourneyService: replacing %s (%s, expected %s)")
			:format(name, existing.ClassName, className))
		existing:Destroy()
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("FirstJourneyRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "FirstJourneyRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local SyncRemote = ensureRemote(remotesFolder, "RemoteEvent", "JourneySync")
local EventRemote = ensureRemote(remotesFolder, "RemoteEvent", "JourneyEvent")
local GetStateFunction = ensureRemote(remotesFolder, "RemoteFunction", "GetJourneyState")

-- =========================================================================
-- STATE
-- =========================================================================

local sessions = {}
local initializing = {}
local pendingPush = {}

local MAX_ACTIVE_SECONDS = FirstJourneyConfig.DurationSeconds
local MAX_COUNTER = 1000000

local function getData(player: Player)
	local module = player:FindFirstChild("PlayerData")
	if not module then
		return nil
	end
	local ok, data = pcall(require, module)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return data
end

local function normalizeCounter(value)
	return math.clamp(math.floor(tonumber(value) or 0), 0, MAX_COUNTER)
end

local function getJourney(player: Player)
	local data = getData(player)
	if not data then
		return nil, nil
	end

	if type(data.FirstJourney) ~= "table" then
		data.FirstJourney = {}
	end

	local state = data.FirstJourney
	state.Eligible = state.Eligible == true
	state.Completed = state.Completed == true
	state.ActiveSeconds = math.clamp(tonumber(state.ActiveSeconds) or 0, 0, MAX_ACTIVE_SECONDS)
	state.StageIndex = math.clamp(
		math.floor(tonumber(state.StageIndex) or 1),
		1,
		FirstJourneyConfig.GetStageCount() + 1
	)
	state.TotalCollections = normalizeCounter(state.TotalCollections)
	state.TotalClicks = normalizeCounter(state.TotalClicks)
	state.TotalUpgrades = normalizeCounter(state.TotalUpgrades)
	state.RushCollections = normalizeCounter(state.RushCollections)
	if type(state.StageBaselines) ~= "table" then
		state.StageBaselines = {}
	end

	-- Version 1 used lifetime counters for every stage, which allowed one
	-- early burst to pre-complete several later beats. Preserve progress on
	-- the player's current stage once, then use fresh per-stage baselines.
	local savedVersion = math.floor(tonumber(state.Version) or 1)
	if savedVersion < FirstJourneyConfig.Version then
		local currentStage = FirstJourneyConfig.GetStage(state.StageIndex)
		if currentStage and type(state.StageBaselines[currentStage.Id]) ~= "table" then
			state.StageBaselines[currentStage.Id] = {
				TotalCollections = 0,
				TotalClicks = 0,
				TotalUpgrades = 0,
				RushCollections = 0,
			}
		end
	end
	state.Version = FirstJourneyConfig.Version
	state.ShadowDiscovered = state.ShadowDiscovered == true
	state.ProphecyRead = state.ProphecyRead == true
	state.RushAnnounced = state.RushAnnounced == true
	state.StartedLogged = state.StartedLogged == true
	state.LastMinuteLogged = math.clamp(
		math.floor(tonumber(state.LastMinuteLogged) or 0),
		0,
		math.floor(MAX_ACTIVE_SECONDS / 60)
	)

	if state.Completed then
		state.StageIndex = FirstJourneyConfig.GetStageCount() + 1
		state.ActiveSeconds = MAX_ACTIVE_SECONDS
	end

	return state, data
end

local function ensureStageBaseline(state, stage)
	if not stage then
		return nil
	end
	-- A locked stage is not active yet. Capturing its baseline early would let
	-- actions during the waiting window pre-complete it before it appears.
	if (stage.UnlockAt or 0) > state.ActiveSeconds then
		return nil
	end
	local baseline = state.StageBaselines[stage.Id]
	if type(baseline) ~= "table" then
		baseline = {
			TotalCollections = state.TotalCollections,
			TotalClicks = state.TotalClicks,
			TotalUpgrades = state.TotalUpgrades,
			RushCollections = state.RushCollections,
		}
		state.StageBaselines[stage.Id] = baseline
	end
	return baseline
end

local function sinceBaseline(state, baseline, field)
	return math.max(0, normalizeCounter(state[field]) - normalizeCounter(baseline[field]))
end

local function getStageProgress(state, stage)
	if not stage then
		return 0, 1
	end
	if (stage.UnlockAt or 0) > state.ActiveSeconds then
		if stage.GoalType == "UpgradesOrCollections" then
			return 0, stage.Target, ("↑ 0/%d  •  ✦ 0/%d"):format(
				math.max(1, tonumber(stage.UpgradeTarget) or 1),
				math.max(1, tonumber(stage.CollectionTarget) or 1)
			)
		end
		return 0, stage.Target
	end

	local baseline = ensureStageBaseline(state, stage)
	local progress = 0
	if stage.GoalType == "Collections" then
		progress = sinceBaseline(state, baseline, "TotalCollections")
	elseif stage.GoalType == "Clicks" then
		progress = sinceBaseline(state, baseline, "TotalClicks")
	elseif stage.GoalType == "Upgrades" then
		progress = sinceBaseline(state, baseline, "TotalUpgrades")
	elseif stage.GoalType == "ShadowOrCollections" then
		progress = state.ShadowDiscovered
			and stage.Target
			or sinceBaseline(state, baseline, "TotalCollections")
	elseif stage.GoalType == "ProphecyOrCollections" then
		progress = state.ProphecyRead
			and stage.Target
			or sinceBaseline(state, baseline, "TotalCollections")
	elseif stage.GoalType == "RushCollections" then
		progress = sinceBaseline(state, baseline, "RushCollections")
	elseif stage.GoalType == "UpgradesOrCollections" then
		local upgrades = sinceBaseline(state, baseline, "TotalUpgrades")
		local collections = sinceBaseline(state, baseline, "TotalCollections")
		local upgradeTarget = math.max(1, tonumber(stage.UpgradeTarget) or 1)
		local collectionTarget = math.max(1, tonumber(stage.CollectionTarget) or 1)
		progress = math.floor(math.max(
			upgrades / upgradeTarget,
			collections / collectionTarget
		) * stage.Target)
		local progressText = ("↑ %d/%d  •  ✦ %d/%d"):format(
			math.min(upgrades, upgradeTarget),
			upgradeTarget,
			math.min(collections, collectionTarget),
			collectionTarget
		)
		return math.min(stage.Target, progress), stage.Target, progressText
	end

	return math.min(stage.Target, math.max(0, progress)), stage.Target
end

local function isRushActive(state)
	return state.Eligible
		and not state.Completed
		and state.ActiveSeconds >= FirstJourneyConfig.RushStartsAt
end

local function buildClientState(player: Player)
	local state = getJourney(player)
	if not state then
		return nil
	end

	local stage = FirstJourneyConfig.GetStage(state.StageIndex)
	local progress, target, progressText = getStageProgress(state, stage)
	local activeSeconds = math.floor(state.ActiveSeconds)
	local stagePayload

	if stage then
		stagePayload = {
			Id = stage.Id,
			Name = stage.Name,
			Icon = stage.Icon,
			Objective = stage.Objective,
			Hint = stage.Hint,
			RewardText = stage.RewardText,
			Progress = progress,
			Target = target,
			ProgressText = progressText,
			UnlockAt = stage.UnlockAt or 0,
			Locked = (stage.UnlockAt or 0) > state.ActiveSeconds,
			Action = stage.Action,
			ActionLabel = stage.ActionLabel,
		}
	else
		local waiting = math.max(0, MAX_ACTIVE_SECONDS - activeSeconds)
		stagePayload = {
			Id = "final_resonance",
			Name = "Final Resonance",
			Icon = "✧",
			Objective = waiting > 0
				and ("Keep the resonance alive until %s"):format(FirstJourneyConfig.FormatTime(MAX_ACTIVE_SECONDS))
				or "Your awakening is ready",
			Hint = "Keep collecting—your personal 2x rush remains active.",
			RewardText = FirstJourneyConfig.FinalRewardText,
			Progress = math.min(activeSeconds, MAX_ACTIVE_SECONDS),
			Target = MAX_ACTIVE_SECONDS,
			UnlockAt = 0,
			Locked = false,
			Action = "Orb",
			ActionLabel = "KEEP GATHERING",
		}
	end

	return {
		Eligible = state.Eligible,
		Completed = state.Completed,
		ActiveSeconds = activeSeconds,
		Duration = MAX_ACTIVE_SECONDS,
		StageIndex = state.StageIndex,
		StageCount = FirstJourneyConfig.GetStageCount(),
		Stage = stagePayload,
		RushActive = isRushActive(state),
		RushStartsAt = FirstJourneyConfig.RushStartsAt,
		RushMultiplier = FirstJourneyConfig.RushMultiplier,
		FinalRewardText = FirstJourneyConfig.FinalRewardText,
	}
end

local function requestPush(player: Player)
	pendingPush[player] = true
end

local function pushState(player: Player)
	local payload = buildClientState(player)
	if payload and player.Parent then
		SyncRemote:FireClient(player, payload)
	end
end

task.spawn(function()
	while true do
		task.wait(0.35)
		for player in pairs(pendingPush) do
			pendingPush[player] = nil
			if player.Parent then
				local ok, err = pcall(pushState, player)
				if not ok then
					warn("FirstJourneyService: state push failed: " .. tostring(err))
				end
			end
		end
	end
end)

-- =========================================================================
-- REWARDS + ANALYTICS
-- =========================================================================

local function grantCurrency(player: Player, currencyId: string, amount: number)
	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount <= 0 then
		return false
	end

	local essence = EssenceConfig.Get(currencyId)
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and essence and leaderstats:FindFirstChild(essence.Name)
	if not stat then
		warn(("FirstJourneyService: cannot grant %s to %s; leaderstat missing")
			:format(tostring(currencyId), player.Name))
		return false
	end

	local current = tonumber(stat:GetAttribute("Quantity")) or 0
	stat:SetAttribute("Quantity", current + amount)

	local data = getData(player)
	if data then
		data.TotalEssenceGathered = (tonumber(data.TotalEssenceGathered) or 0) + amount
	end
	return true
end

local function grantReward(player: Player, reward)
	if type(reward) ~= "table" then
		return
	end

	-- Catalog order makes the attribute/discovery reactions deterministic:
	-- Earth, then Shadow, then Solar.
	for _, essence in ipairs(EssenceConfig.Ordered) do
		grantCurrency(player, essence.Id, reward[essence.Id])
	end
end

local function applyPostJourneyPotion(player: Player)
	local potion = FirstJourneyConfig.PostJourneyPotion
	local moduleScript = ServerScriptService:FindFirstChild("PotionTimerService")
	if not moduleScript then
		warn("FirstJourneyService: PotionTimerService missing; finale currency granted without handoff boost")
		return
	end

	local ok, err = pcall(function()
		local PotionTimerService = require(moduleScript)
		PotionTimerService.ApplyPotion(player, potion.Effect, potion.Duration, "Extend")
	end)
	if not ok then
		warn("FirstJourneyService: post-journey potion failed: " .. tostring(err))
	end
end

local function logEvent(player: Player, eventName: string, activeSeconds: number)
	-- Analytics is observational only. A Creator Hub outage or API change can
	-- never block rewards or progression. Studio skips the network call so
	-- normal local QA stays free of expected analytics warnings.
	if RunService:IsStudio() then
		return
	end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, math.max(0, math.floor(activeSeconds)), {})
	end)
	if not ok then
		warn(("FirstJourneyService: analytics event %s failed: %s"):format(eventName, tostring(err)))
	end
end

local function logMinuteMilestones(player: Player, state, announce: boolean?)
	local reachedMinute = math.clamp(
		math.floor(state.ActiveSeconds / 60),
		0,
		math.floor(MAX_ACTIVE_SECONDS / 60)
	)
	while state.LastMinuteLogged < reachedMinute do
		state.LastMinuteLogged += 1
		logEvent(player, ("FirstJourney_Minute%02d"):format(state.LastMinuteLogged), state.ActiveSeconds)
		-- The rush arrival and finale have larger presentations. Other minute
		-- marks get a restrained pulse so the twelve-minute arc stays alive.
		if announce
			and state.LastMinuteLogged ~= math.floor(FirstJourneyConfig.RushStartsAt / 60)
			and state.LastMinuteLogged ~= math.floor(MAX_ACTIVE_SECONDS / 60)
		then
			EventRemote:FireClient(player, {
				Type = "MinuteReached",
				Minute = state.LastMinuteLogged,
			})
		end
	end
end

local function mirrorAttributes(player: Player, state)
	local rushActive = isRushActive(state)
	player:SetAttribute("FirstJourneyEligible", state.Eligible)
	player:SetAttribute("FirstJourneyCompleted", state.Completed)
	player:SetAttribute("FirstJourneyActiveSeconds", math.floor(state.ActiveSeconds))
	player:SetAttribute("FirstJourneyStage", state.StageIndex)
	player:SetAttribute("FirstJourneyRushActive", rushActive)
	player:SetAttribute(
		"FirstJourneyEssenceMultiplier",
		rushActive and FirstJourneyConfig.RushMultiplier or 1
	)
end

-- =========================================================================
-- ADVANCEMENT
-- =========================================================================

local evaluatePlayer

local function completeJourney(player: Player, state)
	if state.Completed then
		return
	end

	state.Completed = true
	state.ActiveSeconds = MAX_ACTIVE_SECONDS
	state.StageIndex = FirstJourneyConfig.GetStageCount() + 1
	mirrorAttributes(player, state)

	grantReward(player, FirstJourneyConfig.FinalReward)
	applyPostJourneyPotion(player)

	NotificationService.Send(player, {
		Kind = "Success",
		Title = "Essence Awakened!",
		Message = FirstJourneyConfig.FinalRewardText .. "  •  " .. FirstJourneyConfig.PostJourneyPotion.Label,
		Icon = "✧",
		Duration = 7,
		Priority = 5,
		Key = "first-journey-complete",
	}, { Cooldown = 0 })

	EventRemote:FireClient(player, {
		Type = "JourneyCompleted",
		RewardText = FirstJourneyConfig.FinalRewardText,
		PotionText = FirstJourneyConfig.PostJourneyPotion.Label,
		Snapshot = buildClientState(player),
	})
	logEvent(player, "FirstJourney_Completed", state.ActiveSeconds)
	requestPush(player)
end

local function completeStage(player: Player, state, stage, stageIndex: number)
	-- Increment before emitting any attribute/discovery signal from rewards;
	-- the evaluation lock below prevents re-entrancy, and the advanced index
	-- guarantees an observer can never pay this same stage again.
	state.StageIndex = stageIndex + 1
	ensureStageBaseline(state, FirstJourneyConfig.GetStage(state.StageIndex))
	grantReward(player, stage.Reward)
	mirrorAttributes(player, state)

	NotificationService.Send(player, {
		Kind = "Success",
		Title = stage.Name .. " Complete",
		Message = stage.RewardText,
		Icon = stage.Icon,
		Duration = 3.2,
		Priority = 2,
		Key = "first-journey-stage:" .. stage.Id,
	}, { Cooldown = 0 })

	EventRemote:FireClient(player, {
		Type = "StageCompleted",
		StageIndex = stageIndex,
		StageName = stage.Name,
		Icon = stage.Icon,
		RewardText = stage.RewardText,
		Snapshot = buildClientState(player),
	})
	logEvent(player, ("FirstJourney_Stage%02d"):format(stageIndex), state.ActiveSeconds)
end

evaluatePlayer = function(player: Player, suppressRoutinePush: boolean?)
	local session = sessions[player]
	if not session then
		return
	end

	if session.Evaluating then
		session.EvaluateAgain = true
		return
	end
	session.Evaluating = true

	repeat
		session.EvaluateAgain = false
		local state = getJourney(player)
		if not state or not state.Eligible or state.Completed then
			if state then
				mirrorAttributes(player, state)
			end
			break
		end

		-- Server-written mirrors are authoritative alternatives to the raw
		-- counters. Once true, persist the fact so a rejoin keeps the credit.
		state.ShadowDiscovered = state.ShadowDiscovered
			or player:GetAttribute("ShadowEssenceDiscovered") == true
		local prophecyId = player:GetAttribute("ActiveProphecyId")
		state.ProphecyRead = state.ProphecyRead
			or (type(prophecyId) == "string" and prophecyId ~= "")

		mirrorAttributes(player, state)

		while not state.Completed do
			local stageIndex = state.StageIndex
			local stage = FirstJourneyConfig.GetStage(stageIndex)
			if not stage then
				if state.ActiveSeconds >= MAX_ACTIVE_SECONDS then
					completeJourney(player, state)
				end
				break
			end

			if (stage.UnlockAt or 0) > state.ActiveSeconds then
				break
			end

			local progress, target = getStageProgress(state, stage)
			if progress < target then
				break
			end

			completeStage(player, state, stage, stageIndex)
		end

		if not suppressRoutinePush then
			requestPush(player)
		end
	until not session.EvaluateAgain

	session.Evaluating = false
end

local function beginRushIfReady(player: Player, state)
	if not isRushActive(state) then
		return
	end

	mirrorAttributes(player, state)
	if state.RushAnnounced then
		return
	end

	state.RushAnnounced = true
	EventRemote:FireClient(player, {
		Type = "RushStarted",
		Multiplier = FirstJourneyConfig.RushMultiplier,
		Remaining = math.max(0, MAX_ACTIVE_SECONDS - state.ActiveSeconds),
		Snapshot = buildClientState(player),
	})
	NotificationService.Send(player, {
		Kind = "Success",
		Title = "Awakening Rush!",
		Message = ("Your essence gains are doubled through the %s finale.")
			:format(FirstJourneyConfig.FormatTime(MAX_ACTIVE_SECONDS)),
		Icon = "☀",
		Duration = 4.5,
		Priority = 4,
		Key = "first-journey-rush",
	}, { Cooldown = 0 })
	logEvent(player, "FirstJourney_RushStarted", state.ActiveSeconds)
end

-- =========================================================================
-- GAMEPLAY OBSERVERS
-- =========================================================================

local function addCounter(player: Player, field: string, amount: number)
	if not sessions[player] or player:GetAttribute("PlayerDataLoaded") ~= true then
		return
	end
	local state = getJourney(player)
	if not state or not state.Eligible or state.Completed then
		return
	end
	state[field] = math.min(MAX_COUNTER, normalizeCounter(state[field]) + amount)
	evaluatePlayer(player)
end

GameplaySignals.OnClickAccepted(function(player, payload)
	-- Automatic trickle clicks are useful progression, but an onboarding
	-- objective that completes itself teaches nothing and feels unearned.
	if type(payload) == "table" and payload.WasTrickle == true then
		return
	end
	addCounter(player, "TotalClicks", 1)
end)

GameplaySignals.OnCollectionAccepted(function(player)
	local state = getJourney(player)
	if not sessions[player] or not state or not state.Eligible or state.Completed then
		return
	end
	state.TotalCollections = math.min(MAX_COUNTER, state.TotalCollections + 1)
	if state.ActiveSeconds >= FirstJourneyConfig.RushStartsAt then
		state.RushCollections = math.min(MAX_COUNTER, state.RushCollections + 1)
	end
	evaluatePlayer(player)
end)

local function watchAttributes(player: Player, session)
	session.UpgradeLevels = {}
	for _, definition in ipairs(TreeUpgrades.List or {}) do
		session.UpgradeLevels[definition.Id] = tonumber(player:GetAttribute(definition.Id)) or 0
	end

	session.AttributeConnection = player.AttributeChanged:Connect(function(attribute)
		if attribute == "ShadowEssenceDiscovered" or attribute == "ActiveProphecyId" then
			evaluatePlayer(player)
			return
		end

		local definition = TreeUpgrades.ById and TreeUpgrades.ById[attribute]
		if not definition then
			return
		end

		local current = tonumber(player:GetAttribute(attribute)) or 0
		local previous = session.UpgradeLevels[attribute] or 0
		session.UpgradeLevels[attribute] = current
		if current > previous then
			addCounter(player, "TotalUpgrades", current - previous)
		end
	end)
end

-- =========================================================================
-- CLOCK + LIFECYCLE
-- =========================================================================

GetStateFunction.OnServerInvoke = function(player: Player)
	if not player:GetAttribute("PlayerDataLoaded") then
		return nil
	end
	return buildClientState(player)
end

task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, session in pairs(sessions) do
			if not player.Parent then
				continue
			end

			local state = getJourney(player)
			if state and state.Eligible and not state.Completed then
				local delta = math.clamp(now - session.LastClock, 0, 2.5)
				state.ActiveSeconds = math.min(MAX_ACTIVE_SECONDS, state.ActiveSeconds + delta)
				session.LastClock = now

				logMinuteMilestones(player, state, true)
				beginRushIfReady(player, state)
				evaluatePlayer(player, true)
				if math.floor(state.ActiveSeconds) % 5 == 0 then
					requestPush(player)
				end
			else
				session.LastClock = now
			end
		end
	end
end)

local function waitForDataLoaded(player: Player)
	local waited = 0
	while player.Parent and not player:GetAttribute("PlayerDataLoaded") and waited < 35 do
		task.wait(0.1)
		waited += 0.1
	end
	return player.Parent ~= nil and player:GetAttribute("PlayerDataLoaded") == true
end

local function onPlayerAdded(player: Player)
	if sessions[player] or initializing[player] then
		return
	end
	initializing[player] = true

	task.spawn(function()
		if not waitForDataLoaded(player) then
			initializing[player] = nil
			if player.Parent then
				warn("FirstJourneyService: timed out waiting for data for " .. player.Name)
			end
			return
		end

		local state = getJourney(player)
		if not state then
			initializing[player] = nil
			return
		end

		local session = {
			LastClock = os.clock(),
			Evaluating = false,
			EvaluateAgain = false,
		}
		sessions[player] = session
		initializing[player] = nil
		ensureStageBaseline(state, FirstJourneyConfig.GetStage(state.StageIndex))
		watchAttributes(player, session)
		if state.Eligible and not state.StartedLogged then
			state.StartedLogged = true
			logEvent(player, "FirstJourney_Started", 0)
		end
		mirrorAttributes(player, state)
		if state.Eligible then
			logMinuteMilestones(player, state, false)
		end
		beginRushIfReady(player, state)
		evaluatePlayer(player)

		-- StarterPlayerScripts may still be connecting. GetJourneyState is the
		-- reliable path; this delayed push makes hot reloads feel immediate too.
		task.wait(1)
		if player.Parent then
			pushState(player)
		end
	end)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		local state = getJourney(player)
		if state and state.Eligible and not state.Completed then
			local delta = math.clamp(os.clock() - session.LastClock, 0, 2.5)
			state.ActiveSeconds = math.min(MAX_ACTIVE_SECONDS, state.ActiveSeconds + delta)
			mirrorAttributes(player, state)
			logEvent(player, "FirstJourney_SessionExit", state.ActiveSeconds)
		end
		if session.AttributeConnection then
			session.AttributeConnection:Disconnect()
		end
	end
	sessions[player] = nil
	initializing[player] = nil
	pendingPush[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

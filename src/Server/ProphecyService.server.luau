--[[
	ProphecyService (Script -> ServerScriptService)
	================================================
	Server-authoritative Prophecy Crystal readings. A client can ask for a
	reading, but only this script checks the cooldown, performs the weighted
	roll, advances Fate pity, persists the active omen and applies its timed
	attributes. Rejoining resumes the same countdown instead of rerolling or
	extending it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProphecyConfig = require(ReplicatedStorage:WaitForChild("ProphecyConfig"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local function ensureRemote(parent: Instance, className: string, name: string)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		warn(("ProphecyService: %s exists as %s, expected %s"):format(name, existing.ClassName, className))
		existing:Destroy()
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("ProphecyRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "ProphecyRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local SyncRemote = ensureRemote(remotesFolder, "RemoteEvent", "ProphecySync")
local RollFunction = ensureRemote(remotesFolder, "RemoteFunction", "RollProphecy")
local GetStateFunction = ensureRemote(remotesFolder, "RemoteFunction", "GetProphecyState")

-- =========================================================================
-- PERSISTENT STATE
-- =========================================================================

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

-- Normalizes old or malformed saves into the current shape. Default data
-- already has these fields for new players; this also makes the service
-- safe during a hot reload before a save migration has happened.
local function getProphecyState(player: Player)
	local data = getData(player)
	if not data then
		return nil, nil
	end

	if type(data.Prophecy) ~= "table" then
		data.Prophecy = {}
	end

	local state = data.Prophecy
	state.NextRollAt = math.max(0, math.floor(tonumber(state.NextRollAt) or 0))
	state.ActiveId = type(state.ActiveId) == "string" and state.ActiveId or ""
	state.ExpiresAt = math.max(0, math.floor(tonumber(state.ExpiresAt) or 0))
	state.TotalRolls = math.max(0, math.floor(tonumber(state.TotalRolls) or 0))
	state.RollsSinceRare = math.clamp(
		math.floor(tonumber(state.RollsSinceRare) or 0),
		0,
		ProphecyConfig.PityRolls - 1
	)

	if state.ActiveId ~= "" and not ProphecyConfig.GetById(state.ActiveId) then
		state.ActiveId = ""
		state.ExpiresAt = 0
	end

	return state, data
end

-- =========================================================================
-- ACTIVE EFFECT
-- =========================================================================

local expiryGenerations = {}
local scheduledExpiryKeys = {}

local function setNeutralAttributes(player: Player)
	player:SetAttribute("ActiveProphecyId", "")
	player:SetAttribute("ProphecyExpiresAt", 0)
	player:SetAttribute("ProphecyEssenceMultiplier", 1)
	player:SetAttribute("ProphecyCritChanceBonus", 0)
	player:SetAttribute("ProphecyRareWeightMultiplier", 1)
end

local function applyAttributes(player: Player, prophecy, expiresAt: number)
	player:SetAttribute("ActiveProphecyId", prophecy.Id)
	player:SetAttribute("ProphecyExpiresAt", expiresAt)
	player:SetAttribute("ProphecyEssenceMultiplier", tonumber(prophecy.EssenceMultiplier) or 1)
	player:SetAttribute("ProphecyCritChanceBonus", tonumber(prophecy.CritChanceBonus) or 0)
	player:SetAttribute("ProphecyRareWeightMultiplier", tonumber(prophecy.RareWeightMultiplier) or 1)
end

local function buildClientState(player: Player, state)
	local now = os.time()
	local activeId = state.ActiveId
	local active = activeId ~= "" and ProphecyConfig.GetById(activeId) or nil
	if not active or state.ExpiresAt <= now then
		activeId = ""
	end

	return {
		ServerNow = now,
		NextRollAt = state.NextRollAt,
		SecondsUntilRoll = math.max(0, state.NextRollAt - now),
		RollReady = now >= state.NextRollAt,
		ActiveId = activeId,
		ExpiresAt = activeId ~= "" and state.ExpiresAt or 0,
		TotalRolls = state.TotalRolls,
		RollsSinceRare = state.RollsSinceRare,
		PityRolls = ProphecyConfig.PityRolls,
	}
end

local function pushState(player: Player, stateOverride)
	local state = stateOverride or getProphecyState(player)
	if state and player.Parent then
		SyncRemote:FireClient(player, buildClientState(player, state))
	end
end

local function clearExpired(player: Player, expectedId: string?, expectedExpiresAt: number?)
	local state = getProphecyState(player)
	if not state then
		return
	end

	if expectedId and state.ActiveId ~= expectedId then
		return
	end
	if expectedExpiresAt and state.ExpiresAt ~= expectedExpiresAt then
		return
	end
	if state.ExpiresAt > os.time() then
		return
	end

	state.ActiveId = ""
	state.ExpiresAt = 0
	setNeutralAttributes(player)
	pushState(player, state)
end

local function scheduleExpiry(player: Player, prophecyId: string, expiresAt: number)
	local expiryKey = prophecyId .. ":" .. tostring(expiresAt)
	if scheduledExpiryKeys[player] == expiryKey then
		return
	end
	scheduledExpiryKeys[player] = expiryKey
	expiryGenerations[player] = (expiryGenerations[player] or 0) + 1
	local generation = expiryGenerations[player]
	local delaySeconds = math.max(0, expiresAt - os.time())

	task.delay(delaySeconds + 0.1, function()
		if not player.Parent or expiryGenerations[player] ~= generation then
			return
		end
		scheduledExpiryKeys[player] = nil
		clearExpired(player, prophecyId, expiresAt)
	end)
end

local function reconcileActiveEffect(player: Player, state)
	local now = os.time()
	local prophecy = ProphecyConfig.GetById(state.ActiveId)
	if not prophecy or state.ExpiresAt <= now then
		state.ActiveId = ""
		state.ExpiresAt = 0
		setNeutralAttributes(player)
		return
	end

	applyAttributes(player, prophecy, state.ExpiresAt)
	scheduleExpiry(player, prophecy.Id, state.ExpiresAt)
end

-- =========================================================================
-- READINGS
-- =========================================================================

local rollDebounce = {}
local ROLL_DEBOUNCE_SECONDS = 1

GetStateFunction.OnServerInvoke = function(player: Player)
	local state = getProphecyState(player)
	if not state then
		return nil
	end

	-- Also reconciles attributes here, closing the tiny startup race where
	-- a client asks for state after PlayerData loads but before onPlayerAdded's
	-- spawned initialization task reaches the same data.
	reconcileActiveEffect(player, state)
	return buildClientState(player, state)
end

RollFunction.OnServerInvoke = function(player: Player)
	local clockNow = os.clock()
	local previous = rollDebounce[player]
	if previous and clockNow - previous < ROLL_DEBOUNCE_SECONDS then
		return false, "The crystal is still settling..."
	end
	rollDebounce[player] = clockNow

	local state = getProphecyState(player)
	if not state then
		return false, "Your fate is still loading -- try again in a moment."
	end

	local now = os.time()
	if now < state.NextRollAt then
		return false, "The crystal has not reawakened yet.", {
			State = buildClientState(player, state),
		}
	end

	local pityTriggered = state.RollsSinceRare >= ProphecyConfig.PityRolls - 1
	local minimumRank = pityTriggered and ProphecyConfig.RareRank or nil
	local prophecyId = ProphecyConfig.RollProphecyId(minimumRank)
	local prophecy = ProphecyConfig.GetById(prophecyId)
	if not prophecy then
		return false, "The veil went quiet -- try again."
	end

	state.TotalRolls += 1
	if ProphecyConfig.GetRank(prophecy) >= ProphecyConfig.RareRank then
		state.RollsSinceRare = 0
	else
		state.RollsSinceRare = math.min(ProphecyConfig.PityRolls - 1, state.RollsSinceRare + 1)
	end
	state.NextRollAt = now + ProphecyConfig.RollCooldownSeconds
	state.ActiveId = prophecy.Id
	state.ExpiresAt = now + prophecy.Duration

	applyAttributes(player, prophecy, state.ExpiresAt)
	scheduleExpiry(player, prophecy.Id, state.ExpiresAt)
	local clientState = buildClientState(player, state)
	SyncRemote:FireClient(player, clientState)
	-- Session-only analytics mirror. The roll itself was validated, consumed its
	-- cooldown and persisted above, so this cannot be forged by a client.
	player:SetAttribute(
		"SessionProphecyRolls",
		math.max(0, math.floor(tonumber(player:GetAttribute("SessionProphecyRolls")) or 0)) + 1
	)

	return true, nil, {
		ProphecyId = prophecy.Id,
		PityTriggered = pityTriggered,
		State = clientState,
	}
end

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function onPlayerAdded(player: Player)
	player:SetAttribute("SessionProphecyRolls", 0)
	task.spawn(function()
		local dataModule = player:WaitForChild("PlayerData", 30)
		if not dataModule or not player.Parent then
			return
		end

		local state = getProphecyState(player)
		if not state then
			return
		end

		reconcileActiveEffect(player, state)
		-- Give StarterPlayerScripts time to connect ProphecySync. The client
		-- also invokes GetProphecyState, so this is helpful rather than relied on.
		task.wait(1)
		pushState(player, state)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player: Player)
	rollDebounce[player] = nil
	expiryGenerations[player] = nil
	scheduledExpiryKeys[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

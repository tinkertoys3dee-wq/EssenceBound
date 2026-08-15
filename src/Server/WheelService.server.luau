--[[
	WheelService (Script -> ServerScriptService)
	===============================================
	Server-authoritative Fortune Wheel: tracks tickets earned from actual
	play and the free-spin cooldown, and rolls + grants the reward for
	every spin. The client can only ever ASK to spin -- this rolls the
	segment, deducts whichever resource (the free spin or a ticket) paid
	for it, and is the only thing that grants anything.

	TICKETS
	--------
	Counted from GameplaySignals only after OrbClickManager validates and
	credits a collection. A forged or rejected Collection remote can never
	advance a ticket. MaxBankedTickets bounds how much can be stored.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WheelConfig = require(ReplicatedStorage:WaitForChild("WheelConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local GameplaySignals = require(ServerScriptService:WaitForChild("GameplaySignals"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local function ensureRemote(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		warn(("WheelService: %s exists as %s, expected %s"):format(name, existing.ClassName, className))
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("WheelRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "WheelRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local SyncRemote = ensureRemote(remotesFolder, "RemoteEvent", "WheelSync")
local SpinFunction = ensureRemote(remotesFolder, "RemoteFunction", "SpinWheel")
local GetStateFunction = ensureRemote(remotesFolder, "RemoteFunction", "GetWheelState")

-- =========================================================================
-- HELPERS
-- =========================================================================

local function getData(player)
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

local function isDataReady(player)
	return player:GetAttribute("PlayerDataLoaded") == true
end

-- Guarantees the Wheel sub-table exists and is shaped correctly, even for
-- a save written before this system existed.
local function getWheel(player)
	local data = getData(player)
	if not data then
		return nil, nil
	end

	local wheel = data.Wheel
	if type(wheel) ~= "table" then
		wheel = {}
		data.Wheel = wheel
	end

	wheel.Tickets = tonumber(wheel.Tickets) or 0
	wheel.CollectionsSinceLastTicket = tonumber(wheel.CollectionsSinceLastTicket) or 0
	wheel.LastSpinAt = tonumber(wheel.LastSpinAt) or 0

	return wheel, data
end

local function getRebirths(player)
	return tonumber(player:GetAttribute("Rebirths")) or 0
end

local function freeSpinReadyAt(wheel)
	return wheel.LastSpinAt + WheelConfig.FreeSpinCooldownSeconds
end

local function buildClientState(wheel)
	local readyAt = freeSpinReadyAt(wheel)
	local now = os.time()
	return {
		ServerNow = now,
		Tickets = wheel.Tickets,
		CollectionsSinceLastTicket = wheel.CollectionsSinceLastTicket,
		FreeSpinReady = now >= readyAt,
		FreeSpinSecondsRemaining = math.max(0, readyAt - now),
		FreeSpinReadyAt = readyAt,
	}
end

local function pushState(player)
	if not isDataReady(player) then
		return
	end
	local wheel = getWheel(player)
	if not wheel then
		return
	end

	SyncRemote:FireClient(player, buildClientState(wheel))
end

-- Race-proof initial read for the rebuilt WheelPanel. The delayed push on
-- join remains useful, but the client no longer depends on receiving one
-- particular RemoteEvent during startup in order to leave LOADING state.
GetStateFunction.OnServerInvoke = function(player)
	if not isDataReady(player) then
		return nil
	end
	local wheel = getWheel(player)
	if not wheel then
		return nil
	end
	return buildClientState(wheel)
end

-- =========================================================================
-- TICKET EARNING
-- =========================================================================

GameplaySignals.OnCollectionAccepted(function(player)
	if not isDataReady(player) then
		return
	end

	local wheel = getWheel(player)
	if not wheel then
		return
	end

	-- Paused (not reset) once already at the cap -- collecting while
	-- holding the max banked tickets shouldn't waste progress toward
	-- the next one; it resumes after a spin frees room.
	if wheel.Tickets >= WheelConfig.MaxBankedTickets then
		return
	end

	wheel.CollectionsSinceLastTicket += 1
	if wheel.CollectionsSinceLastTicket >= WheelConfig.CollectionsPerTicket then
		wheel.CollectionsSinceLastTicket -= WheelConfig.CollectionsPerTicket
		wheel.Tickets += 1
		pushState(player)
	end
end)

-- =========================================================================
-- SPINNING
-- =========================================================================

local function getPotionTimerService()
	local ok, service = pcall(function()
		local moduleScript = ServerScriptService:FindFirstChild("PotionTimerService")
		if not moduleScript then
			return nil
		end
		return require(moduleScript)
	end)
	if ok then
		return service
	end
	return nil
end

-- Same crediting path every other reward system in this file's
-- neighborhood uses (ProgressionService.grantEssence, AchievementsService):
-- write the leaderstat's Quantity attribute, PlayerDataHandler mirrors it
-- back into PlayerData for free.
local function grantEssence(player, essenceName, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(essenceName)
	if not stat then
		return
	end

	local current = tonumber(stat:GetAttribute("Quantity")) or 0
	stat:SetAttribute("Quantity", current + amount)

	local data = getData(player)
	if data then
		data.TotalEssenceGathered = (tonumber(data.TotalEssenceGathered) or 0) + amount
	end
end

local spinDebounce = {}
local SPIN_DEBOUNCE_SECONDS = 1

-- Returns (success: boolean, message: string?, result: table?). message is
-- set only on failure (told to the player, e.g. "no spins available yet");
-- result is set only on success (SegmentIndex is what WheelPanel.client.
-- luau spins the wheel to land on -- the client never chooses this, it
-- only ever finds out).
SpinFunction.OnServerInvoke = function(player)
	if not isDataReady(player) then
		return false, "Still loading -- try again in a moment."
	end

	local now = os.clock()
	local last = spinDebounce[player]
	if last and (now - last) < SPIN_DEBOUNCE_SECONDS then
		return false, "Slow down a moment..."
	end
	spinDebounce[player] = now

	local wheel = getWheel(player)
	if not wheel then
		return false, "Still loading -- try again in a moment."
	end

	local realNow = os.time()
	local usingFreeSpin = realNow >= freeSpinReadyAt(wheel)

	-- Free spin always wins over spending a ticket when both are
	-- available -- the player-favorable order, and the obviously
	-- expected one.
	if usingFreeSpin then
		wheel.LastSpinAt = realNow
	else
		if wheel.Tickets <= 0 then
			return false, "No spins available yet."
		end
		wheel.Tickets -= 1
	end

	local segmentIndex = WheelConfig.RollSegmentIndex()
	local segment = WheelConfig.Segments[segmentIndex]

	local essence = ProgressionConfig.ScaleReward(segment.Essence or 0, getRebirths(player))
	local solarEssence = math.max(0, math.floor(tonumber(segment.SolarEssence) or 0))
	grantEssence(player, "Earth Essence", essence)
	grantEssence(player, "Solar Essence", solarEssence)

	if segment.Potion then
		local PotionTimerService = getPotionTimerService()
		if PotionTimerService then
			PotionTimerService.ApplyPotion(player, segment.Potion.Effect, segment.Potion.Duration)
		end
	end

	if segment.Shards then
		local currentShards = tonumber(player:GetAttribute("RebirthCurrency")) or 0
		player:SetAttribute("RebirthCurrency", currentShards + segment.Shards)
	end

	pushState(player)

	return true, nil, {
		SegmentIndex = segmentIndex,
		Essence = essence,
		SolarEssence = solarEssence,
		Shards = segment.Shards,
		PotionLabel = segment.PotionLabel,
	}
end

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function onPlayerAdded(player)
	task.spawn(function()
		local deadline = os.clock() + 35
		while player.Parent and not isDataReady(player) and os.clock() < deadline do
			task.wait(0.1)
		end
		if not player.Parent or not isDataReady(player) then
			return
		end

		-- Small delay so the client's UI script has loaded and is
		-- listening before the first state arrives.
		task.wait(1)
		if player.Parent then
			pushState(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	spinDebounce[player] = nil
end)

for _, existing in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existing)
end

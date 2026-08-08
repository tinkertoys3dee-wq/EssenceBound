--[[
	LeaderboardService (Script -> ServerScriptService)
	===================================================
	Global, cross-server leaderboards: Total Essence Gathered (lifetime,
	both essence types combined -- see OrbClickManager's
	TotalEssenceGathered increment) and Rebirths. Backed by
	OrderedDataStore, refreshed on a timer and broadcast to every online
	client -- nobody polls the DataStore directly, so this stays well
	inside Roblox's request budget no matter how many players are online.

	WHY THIS EXISTS
	----------------
	Nothing in this game let a player compare themselves to anyone else.
	Social competition/comparison is one of the strongest retention levers
	an incremental game can have and this one had none of it.

	SCOPE
	------
	Read-only and purely cosmetic/social: nothing here grants currency,
	changes economy state, or is trusted for anything. It only ever writes
	a player's own already-server-derived stat (TotalEssenceGathered,
	Rebirths -- both already fully server-owned, never client-writable) to
	an ordered store, and reads back the top of each store to show
	everyone. If DataStoreService is unavailable (API Services off in
	Studio, a DataStore outage) this fails soft -- empty leaderboards,
	never an error that could touch anything else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- =========================================================================
-- CONFIG
-- =========================================================================

local TOP_N = 50
local REFRESH_INTERVAL = 180 -- seconds between full leaderboard refreshes
local WRITE_THROTTLE = 60 -- minimum seconds between one player's own writes
local PER_PLAYER_WRITE_LOOP = 20 -- how often to CHECK whether a write is due

local BOARDS = {
	{
		Id = "Essence",
		Name = "Total Essence",
		Icon = "🌿",
		DataStoreName = "EssenceLeaderboard",
		GetValue = function(data)
			return math.floor(tonumber(data.TotalEssenceGathered) or 0)
		end,
	},
	{
		Id = "Rebirths",
		Name = "Rebirths",
		Icon = "🔥",
		DataStoreName = "RebirthsLeaderboard",
		GetValue = function(data)
			return math.floor(tonumber(data.Rebirths) or 0)
		end,
	},
}

-- =========================================================================
-- REMOTES
-- =========================================================================

local remotesFolder = ReplicatedStorage:FindFirstChild("LeaderboardRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "LeaderboardRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemote(className, name)
	local existing = remotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local SyncRemote = ensureRemote("RemoteEvent", "LeaderboardSync")

-- =========================================================================
-- DATASTORE SETUP
-- =========================================================================

for _, board in ipairs(BOARDS) do
	local ok, storeOrErr = pcall(function()
		return DataStoreService:GetOrderedDataStore(board.DataStoreName)
	end)
	if ok then
		board.Store = storeOrErr
	else
		board.Store = nil
		warn("[LeaderboardService] Could not open OrderedDataStore for " .. board.Id .. ": " .. tostring(storeOrErr))
	end
end

-- =========================================================================
-- STATE
-- =========================================================================

-- [board.Id] = { {Rank, UserId, Name, Value}, ... }, top N descending.
local cachedSnapshots = {}
for _, board in ipairs(BOARDS) do
	cachedSnapshots[board.Id] = {}
end

-- [player] = { LastWriteAt: number, LastWrittenValue: {[board.Id]: number} }
local playerWriteState = {}

-- [userId] = name. Small cache so repeat refreshes don't re-resolve a name
-- for a player who's still sitting in the top N.
local nameCache = {}

local function getName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		nameCache[userId] = name
		return name
	end
	return "Player" .. tostring(userId)
end

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

-- =========================================================================
-- WRITING (one player's own score onto each board)
-- =========================================================================

local function writePlayerScores(player, force)
	local data = getData(player)
	if not data then
		return
	end

	local writeState = playerWriteState[player]
	if not writeState then
		writeState = { LastWriteAt = 0, LastWrittenValue = {} }
		playerWriteState[player] = writeState
	end

	local now = os.clock()
	if not force and (now - writeState.LastWriteAt) < WRITE_THROTTLE then
		return
	end
	writeState.LastWriteAt = now

	for _, board in ipairs(BOARDS) do
		if board.Store then
			local value = board.GetValue(data)
			-- Skip zero-progress players entirely -- no point cluttering the
			-- store with rows nobody will ever page down to, and skip
			-- unchanged values so a player sitting idle doesn't re-write the
			-- same number every throttle window for no reason.
			if value > 0 and value ~= writeState.LastWrittenValue[board.Id] then
				local ok, err = pcall(function()
					board.Store:SetAsync(tostring(player.UserId), value)
				end)
				if ok then
					writeState.LastWrittenValue[board.Id] = value
				else
					warn("[LeaderboardService] Write failed for " .. board.Id .. " (" .. player.Name .. "): " .. tostring(err))
				end
			end
		end
	end
end

-- =========================================================================
-- REFRESHING (reading the top of each board back)
-- =========================================================================

local function refreshBoard(board)
	if not board.Store then
		return
	end

	local ok, pagesOrErr = pcall(function()
		return board.Store:GetSortedAsync(false, TOP_N) -- false = descending, highest first
	end)
	if not ok then
		warn("[LeaderboardService] Refresh failed for " .. board.Id .. ": " .. tostring(pagesOrErr))
		return
	end

	local ok2, page = pcall(function()
		return pagesOrErr:GetCurrentPage()
	end)
	if not ok2 then
		return
	end

	local snapshot = {}
	for rank, entry in ipairs(page) do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(snapshot, {
				Rank = rank,
				UserId = userId,
				Name = getName(userId),
				Value = entry.value,
			})
		end
	end

	cachedSnapshots[board.Id] = snapshot
end

local function buildPayload()
	local payload = {}
	for _, board in ipairs(BOARDS) do
		payload[board.Id] = cachedSnapshots[board.Id]
	end
	return payload
end

local function broadcastSnapshots()
	local payload = buildPayload()
	for _, plr in ipairs(Players:GetPlayers()) do
		SyncRemote:FireClient(plr, payload)
	end
end

-- =========================================================================
-- LOOPS
-- =========================================================================

task.spawn(function()
	while true do
		for _, board in ipairs(BOARDS) do
			refreshBoard(board)
		end
		broadcastSnapshots()
		task.wait(REFRESH_INTERVAL)
	end
end)

task.spawn(function()
	while true do
		task.wait(PER_PLAYER_WRITE_LOOP)
		for _, plr in ipairs(Players:GetPlayers()) do
			writePlayerScores(plr)
		end
	end
end)

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function onPlayerAdded(plr)
	-- Give them whatever's cached right away rather than waiting up to
	-- REFRESH_INTERVAL for the first push.
	task.defer(function()
		if plr.Parent then
			SyncRemote:FireClient(plr, buildPayload())
		end
	end)

	-- A short delay so PlayerData has actually finished loading before the
	-- first write attempt (mirrors the join-order defensiveness already
	-- used elsewhere in this codebase, e.g. RebirthShopService).
	task.delay(15, function()
		if plr.Parent then
			writePlayerScores(plr, true)
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end
Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(plr)
	writePlayerScores(plr, true)
	playerWriteState[plr] = nil
end)

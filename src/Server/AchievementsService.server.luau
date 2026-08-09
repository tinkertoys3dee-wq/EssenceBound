--[[
	AchievementsService (Script -> ServerScriptService)
	===================================================
	Server-authoritative state + claiming for the Achievements panel.

	Badges themselves are granted elsewhere -- see AchievementsConfig's own
	comment block for the full map of which system owns which badge. This
	file only reads that already-earned state back out to build a sync
	payload, and owns claiming for the new in-game Milestones (real
	essence/Prestige Shard rewards -- see AchievementsConfig.Milestones).

	AUTHORITY
	----------
	The client can only ever ASK to claim a milestone. This re-derives
	completion straight from the same server-owned stats every other
	system already trusts (TotalEssenceGathered, Rebirths, etc.) and is
	the only thing that grants a reward or marks a milestone claimed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local remotesFolder = ReplicatedStorage:FindFirstChild("AchievementsRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "AchievementsRemotes"
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

local SyncRemote = ensureRemote("RemoteEvent", "AchievementsSync")
local ClaimRemote = ensureRemote("RemoteEvent", "ClaimMilestone")
local RequestSyncRemote = ensureRemote("RemoteEvent", "RequestAchievementsSync")

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
	if type(data.ClaimedMilestones) ~= "table" then
		data.ClaimedMilestones = {}
	end
	if type(data.Badges) ~= "table" then
		data.Badges = {}
	end
	return data
end

local function buildState(data)
	local badges = {}
	for _, def in ipairs(AchievementsConfig.Badges) do
		table.insert(badges, {
			Id = def.Id,
			Earned = data.Badges[tonumber(def.Id)] == true,
		})
	end

	local milestones = {}
	for _, def in ipairs(AchievementsConfig.Milestones) do
		table.insert(milestones, {
			Id = def.Id,
			Progress = AchievementsConfig.GetProgress(data, def.Id),
			Complete = AchievementsConfig.IsComplete(data, def.Id),
			Claimed = data.ClaimedMilestones[def.Id] == true,
		})
	end

	return { Badges = badges, Milestones = milestones }
end

local function pushSync(player)
	local data = getData(player)
	if not data then
		return
	end
	SyncRemote:FireClient(player, buildState(data))
end

-- =========================================================================
-- CLAIMING
-- =========================================================================

local claimDebounce = {}
local CLAIM_DEBOUNCE = 0.3

ClaimRemote.OnServerEvent:Connect(function(player, milestoneId)
	if type(milestoneId) ~= "string" then
		return
	end

	local now = os.clock()
	if claimDebounce[player] and (now - claimDebounce[player]) < CLAIM_DEBOUNCE then
		return
	end
	claimDebounce[player] = now

	local def = AchievementsConfig.GetMilestone(milestoneId)
	if not def then
		return
	end

	local data = getData(player)
	if not data then
		return
	end

	-- Already claimed, or not actually earned yet -- the client UI
	-- shouldn't even offer a claim in either case, but never trust it;
	-- re-derive both from server-owned state, same as every purchase flow
	-- in this codebase.
	if data.ClaimedMilestones[milestoneId] then
		return
	end
	if not AchievementsConfig.IsComplete(data, milestoneId) then
		return
	end

	data.ClaimedMilestones[milestoneId] = true

	local reward = def.Reward
	if reward.Type == "Essence" then
		-- Same path every other essence grant in the game uses: write the
		-- leaderstat's Quantity attribute, PlayerDataHandler mirrors it
		-- back into PlayerData and the display Value for free.
		local leaderstats = player:FindFirstChild("leaderstats")
		local earthStat = leaderstats and leaderstats:FindFirstChild("Earth Essence")
		if earthStat then
			local current = tonumber(earthStat:GetAttribute("Quantity")) or 0
			earthStat:SetAttribute("Quantity", current + reward.Amount)
		end
	elseif reward.Type == "Shards" then
		-- Same path the Prestige Shop / Shard Rain use.
		local current = tonumber(player:GetAttribute("RebirthCurrency")) or 0
		player:SetAttribute("RebirthCurrency", current + reward.Amount)
	end

	pushSync(player)
end)

RequestSyncRemote.OnServerEvent:Connect(function(player)
	pushSync(player)
end)

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function initialPush(player)
	-- Short delay so PlayerData has finished loading first (same
	-- defensiveness already used by RebirthShopService/LeaderboardService).
	task.delay(5, function()
		if player.Parent then
			pushSync(player)
		end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	initialPush(plr)
end
Players.PlayerAdded:Connect(initialPush)

-- Periodic push so progress bars creep forward live while a player has the
-- panel open and is actively earning toward something, without the client
-- needing to poll. Cheap: pure in-memory reads, no DataStore calls.
task.spawn(function()
	while true do
		task.wait(5)
		for _, plr in ipairs(Players:GetPlayers()) do
			pushSync(plr)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	claimDebounce[player] = nil
end)

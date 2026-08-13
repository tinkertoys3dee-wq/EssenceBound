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
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local function formatReward(reward)
	local amount = ProgressionConfig.FormatNumber(tonumber(reward and reward.Amount) or 0)
	if reward and reward.Type == "Shards" then
		return amount .. " Prestige Shards"
	elseif reward and reward.Type == "SolarEssence" then
		return amount .. " Solar Essence"
	end
	return amount .. " Earth Essence"
end

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
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Milestones Still Loading",
			Message = "Your milestone data is still loading. Try again in a moment.",
			Key = "milestone-loading",
		})
		return
	end

	-- Already claimed, or not actually earned yet -- the client UI
	-- shouldn't even offer a claim in either case, but never trust it;
	-- re-derive both from server-owned state, same as every purchase flow
	-- in this codebase.
	if data.ClaimedMilestones[milestoneId] then
		NotificationService.Send(player, {
			Kind = "Info",
			Title = "Reward Already Claimed",
			Message = def.Name .. " has already been claimed.",
			Icon = "✓",
			Key = "milestone-claimed:" .. milestoneId,
		})
		return
	end
	if not AchievementsConfig.IsComplete(data, milestoneId) then
		local current = AchievementsConfig.GetStatValue(data, def.Stat)
		NotificationService.Send(player, {
			Kind = "Info",
			Title = def.Name .. " In Progress",
			Message = ("%s / %s complete — %s"):format(
				ProgressionConfig.FormatNumber(math.min(current, def.Target)),
				ProgressionConfig.FormatNumber(def.Target),
				def.Description
			),
			Icon = def.Icon,
			Key = "milestone-incomplete:" .. milestoneId,
		})
		return
	end

	local reward = def.Reward
	local rewardAmount = type(reward) == "table" and tonumber(reward.Amount) or nil
	if type(reward) ~= "table" or type(reward.Type) ~= "string" or not rewardAmount or rewardAmount <= 0 then
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Reward Unavailable",
			Message = "That milestone's reward is not configured correctly.",
			Key = "milestone-reward-invalid:" .. milestoneId,
		})
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local rewardStat
	if reward.Type == "Essence" then
		rewardStat = leaderstats and leaderstats:FindFirstChild("Earth Essence")
	elseif reward.Type == "SolarEssence" then
		rewardStat = leaderstats and leaderstats:FindFirstChild("Solar Essence")
	end

	-- Validate the destination before marking the milestone claimed. The old
	-- order could permanently consume a claim during a leaderstats load race
	-- and then grant nothing.
	if (reward.Type == "Essence" or reward.Type == "SolarEssence") and not rewardStat then
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Reward Delivery Delayed",
			Message = "Your currency balance is still loading. Try claiming again in a moment.",
			Key = "milestone-reward-loading:" .. milestoneId,
		})
		return
	elseif reward.Type ~= "Essence" and reward.Type ~= "SolarEssence" and reward.Type ~= "Shards" then
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Reward Unavailable",
			Message = "That milestone's reward type is not configured correctly.",
			Key = "milestone-reward-invalid:" .. milestoneId,
		})
		return
	end

	data.ClaimedMilestones[milestoneId] = true

	if rewardStat then
		local current = tonumber(rewardStat:GetAttribute("Quantity")) or 0
		rewardStat:SetAttribute("Quantity", current + rewardAmount)
		data.TotalEssenceGathered = (tonumber(data.TotalEssenceGathered) or 0) + rewardAmount
	else
		-- Same path the Prestige Shop / Shard Rain use.
		local current = tonumber(player:GetAttribute("RebirthCurrency")) or 0
		player:SetAttribute("RebirthCurrency", current + rewardAmount)
	end

	pushSync(player)
	NotificationService.Send(player, {
		Kind = "Success",
		Title = "Milestone Reward Claimed",
		Message = ("%s complete — +%s."):format(def.Name, formatReward(reward)),
		Icon = def.Icon,
		Duration = 4,
		Key = "milestone-success:" .. milestoneId,
	}, { Cooldown = 0 })
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

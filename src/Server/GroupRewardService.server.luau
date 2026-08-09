--[[
	GroupRewardService (Script -> ServerScriptService)
	===================================================
	Checks Roblox group membership on join and mirrors the result
	onto a `GroupMember` player attribute, which EssenceMultiplier reads
	like every other multiplicative bonus in the game.

	A complete no-op until GroupRewardConfig.GroupId is set to a real
	group id -- see that file for why this is safe to ship unconfigured.

	WHY AN ATTRIBUTE INSTEAD OF CALLING IsInGroup LIVE
	------------------------------------------------------
	EssenceMultiplier.CalculateMultiplier runs on every single essence
	collection -- a live IsInGroup call in there would hammer Roblox's
	group API far past any reasonable budget. Checked once at join and
	cached on the player instead, same pattern this codebase already uses
	for gamepass ownership.

	The client can request one rate-limited recheck after the player visits
	the group page. The server still performs the authoritative IsInGroup
	call, so the request can never grant the bonus by itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("GroupRewardConfig"))

if not GroupRewardConfig.IsEnabled() then
	return
end

local checkMembership = ReplicatedStorage:FindFirstChild("CheckGroupMembership")
if not checkMembership then
	checkMembership = Instance.new("RemoteFunction")
	checkMembership.Name = "CheckGroupMembership"
	checkMembership.Parent = ReplicatedStorage
end

assert(checkMembership:IsA("RemoteFunction"), "CheckGroupMembership must be a RemoteFunction")

local lastCheckAt = {}
local RECHECK_COOLDOWN = 5

local function updateMembership(player)
	-- IsInGroup hits Roblox's backend and can fail like any other API
	-- call -- must never take the whole join sequence down with it.
	local ok, isMember = pcall(function()
		return player:IsInGroup(GroupRewardConfig.GroupId)
	end)

	-- Always set once checked (true OR false), never left nil on a
	-- successful check. GroupRewardPrompt.client.luau needs to tell "not
	-- checked yet" (nil) apart from "checked, not a member" (false) to
	-- know when it's safe to decide whether to show its join button --
	-- a nil that only ever flips to true on success would leave it
	-- waiting forever for the (far more common) non-member case. A
	-- failed pcall leaves it nil on purpose, so a transient API hiccup
	-- is retried next join rather than being cached as a false negative.
	if ok then
		player:SetAttribute("GroupMember", isMember)
	end

	return ok and isMember == true
end

local function onPlayerAdded(player)
	updateMembership(player)
end

checkMembership.OnServerInvoke = function(player)
	local now = os.clock()
	if now - (lastCheckAt[player] or -math.huge) < RECHECK_COOLDOWN then
		return player:GetAttribute("GroupMember") == true
	end

	lastCheckAt[player] = now
	return updateMembership(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	lastCheckAt[player] = nil
end)

-- Covers a Studio script reload with players already in the world.
for _, existing in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existing)
end

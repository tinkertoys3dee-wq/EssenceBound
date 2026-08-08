--[[
	GroupRewardService (Script -> ServerScriptService)
	===================================================
	Checks Roblox group membership once per join and mirrors the result
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

	Membership is intentionally NOT re-checked mid-session: a player who
	joins the group while already in-game gets the bonus next time they
	join, not instantly. That matches how virtually every other Roblox
	group-reward system behaves and avoids a live-polling loop for a
	one-time, low-frequency event.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("GroupRewardConfig"))

if not GroupRewardConfig.IsEnabled() then
	return
end

local function onPlayerAdded(player)
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
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Covers a Studio script reload with players already in the world.
for _, existing in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existing)
end

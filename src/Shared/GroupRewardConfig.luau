--[[
	GroupRewardConfig (ModuleScript -> ReplicatedStorage)
	======================================================
	Pure data + one placeholder for a standard Roblox mechanic: a modest,
	permanent essence bonus for players who've joined the game's Roblox
	group. Free, social, and (unlike a gamepass) actively helps the game
	itself -- group members see the game's shouts and wall posts, which is
	real, ongoing marketing reach the game doesn't currently have any way
	to earn.

	SAFE TO SHIP UNCONFIGURED
	----------------------------
	GroupId starts at 0, which every piece of this feature (the server
	membership check, the client's join-prompt button) treats as "feature
	disabled" -- no GroupService calls are made, no attribute is set, no
	button is shown, nothing in CalculateMultiplier changes. This is
	deliberately NOT the same situation as the paid gamepasses documented
	at the top of this file: those needed an actual product DESIGN
	decision I can't make on the developer's behalf (what should "Lucky
	Finder" even do?). This mechanic's design is just the genre standard
	(flat % bonus for group membership) -- the only missing piece is a
	literal numeric id, a copy-paste from the group's own URL, not a
	judgment call.

	TO ACTUALLY ENABLE THIS
	--------------------------
	Set GroupId below to your group's real id (visible in its URL:
	roblox.com/groups/123456/Your-Group-Name -- 123456 is the id). That's
	the entire setup step.
]]

local GroupRewardConfig = {}

-- 0 = feature disabled. Set to your real Roblox Group ID to enable.
GroupRewardConfig.GroupId = 0

-- Permanent and free, so deliberately more modest than the paid 2x Essence
-- Multiplier gamepass (EssenceMultiplier.luau) -- this must never make
-- that gamepass a worse deal than a free group join.
GroupRewardConfig.BonusMultiplier = 1.1

GroupRewardConfig.GroupUrl = "https://www.roblox.com/groups/%d"

function GroupRewardConfig.IsEnabled(): boolean
	return GroupRewardConfig.GroupId > 0
end

return GroupRewardConfig

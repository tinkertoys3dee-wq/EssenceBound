--[[
	GroupRewardConfig (ModuleScript -> ReplicatedStorage)
	======================================================
	Pure data for a standard Roblox mechanic: a permanent essence bonus
	for players who've joined the game's Roblox
	group. Free, social, and (unlike a gamepass) actively helps the game
	itself -- group members see the game's shouts and wall posts, which is
	real, ongoing marketing reach the game doesn't currently have any way
	to earn.

	Configured for Mundane Studios. Membership is always verified by the
	server; the client UI can advertise the reward, but cannot grant it.
]]

local GroupRewardConfig = {}

GroupRewardConfig.GroupId = 15575113
GroupRewardConfig.GroupName = "Mundane Studios"

-- Permanent and free, so deliberately more modest than the paid 2x Essence
-- Multiplier gamepass (EssenceMultiplier.luau) -- this must never make
-- that gamepass a worse deal than a free group join.
GroupRewardConfig.BonusMultiplier = 1.35

GroupRewardConfig.GroupUrl = "https://www.roblox.com/communities/%d/Mundane-Studios#!/about"

function GroupRewardConfig.IsEnabled(): boolean
	return GroupRewardConfig.GroupId > 0
end

return GroupRewardConfig

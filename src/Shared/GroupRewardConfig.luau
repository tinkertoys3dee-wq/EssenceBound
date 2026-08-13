--[[
	GroupRewardConfig (ModuleScript -> ReplicatedStorage)
	======================================================
	Pure data for a standard Roblox mechanic: permanent gameplay benefits
	for players who've joined the game's Roblox group. Free, social, and
	(unlike a gamepass) actively helps the game itself -- group members see
	the game's shouts and wall posts, which gives the game ongoing community
	reach it otherwise has no way to earn.

	Configured for Mundane Studios. Membership is always verified by the
	server; the client UI can advertise the reward, but cannot grant it.
]]

local GroupRewardConfig = {}

GroupRewardConfig.GroupId = 15575113
GroupRewardConfig.GroupName = "Mundane Studios"

-- Permanent and free, so every benefit is deliberately modest and stacks
-- with the player's paid/permanent upgrades instead of replacing them.
-- Keep these values in this shared config so the real gameplay hooks and
-- the client benefit cards can never advertise different numbers.
GroupRewardConfig.BonusMultiplier = 1.35
GroupRewardConfig.CritChanceBonus = 0.05
GroupRewardConfig.OfflineEarningsMultiplier = 1.15

GroupRewardConfig.GroupUrl = "https://www.roblox.com/communities/%d/Mundane-Studios#!/about"

function GroupRewardConfig.IsEnabled(): boolean
	return GroupRewardConfig.GroupId > 0
end

return GroupRewardConfig

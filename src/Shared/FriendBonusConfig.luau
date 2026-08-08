--[[
	FriendBonusConfig (ModuleScript -> ReplicatedStorage)
	========================================================
	Pure data for a small, free essence bonus for playing alongside real
	Roblox friends in the same server -- a proven social/viral mechanic
	(bring a friend, both of you benefit) that needs zero setup, unlike
	GroupRewardConfig (which needs a real GroupId before it does anything).

	FriendBonusService.server.luau computes each player's live "friends
	currently in this server" count via Player:IsFriendsWith and mirrors it
	onto a FriendsInServer attribute; EssenceMultiplier reads that attribute
	like every other multiplicative bonus. This module only holds the
	formula, kept here (not duplicated in EssenceMultiplier and the client
	indicator) so both sides always agree on what a given friend count is
	worth.
]]

local FriendBonusConfig = {}

-- +5% per friend present, capped at 4 friends (+20% max). Deliberately
-- more modest per-friend than the free Group bonus's flat 1.1x -- this one
-- can stack up with the group size, so the cap keeps a full-party server
-- from turning into a dominant strategy over just playing well.
FriendBonusConfig.PerFriendBonus = 0.05
FriendBonusConfig.MaxFriends = 4

-- Shared by EssenceMultiplier (the real bonus) and the client indicator
-- (what it displays) so the two can never drift out of sync.
function FriendBonusConfig.GetMultiplierFor(friendCount: number): number
	local capped = math.clamp(friendCount or 0, 0, FriendBonusConfig.MaxFriends)
	return 1 + (FriendBonusConfig.PerFriendBonus * capped)
end

return FriendBonusConfig

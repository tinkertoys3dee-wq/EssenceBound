--[[
	FriendBonusService (Script -> ServerScriptService)
	=====================================================
	Checks, for every player currently in the server, how many of the
	OTHER players present are real Roblox friends of theirs, and mirrors
	the count onto a `FriendsInServer` attribute -- which EssenceMultiplier
	reads like every other multiplicative bonus (see FriendBonusConfig for
	the formula both sides share).

	Unlike GroupRewardService, there's no "unconfigured, ships as a no-op"
	state here: IsFriendsWith needs no setup, so this is live for every
	player immediately.

	WHY RECOMPUTE THE WHOLE SERVER ON EVERY JOIN/LEAVE
	------------------------------------------------------
	A single player joining or leaving changes the correct answer for
	EVERY other player currently in the server, not just their own -- so,
	unlike group membership (which only ever depends on the player being
	checked), this can't be a "compute once at join" cache. Recomputing
	every player's count on each PlayerAdded/PlayerRemoving is O(players^2)
	IsFriendsWith calls per event, which is trivial at the server sizes
	this game runs (an idle/incremental game, not a 100-player shooter) and
	only runs on join/leave -- never on a poll or a per-frame loop.

	WHY THE LEAVING PLAYER IS PASSED IN EXPLICITLY
	--------------------------------------------------
	Relying on Players:GetPlayers() to have already dropped the leaving
	player by the time PlayerRemoving fires would make this correct or
	wrong depending on an ordering guarantee this script shouldn't need to
	assume. Passing `excluding` through and skipping it explicitly is
	correct regardless of that timing.

	WHY refreshAll IS TOKEN-GUARDED
	------------------------------------
	Each IsFriendsWith call yields (it's a real network call), so two
	joins/leaves within the same second or two produce two overlapping
	refreshAll calls. Without a guard, the slower one can finish last and
	overwrite a newer, more complete recompute with stale data -- same
	problem Juice.CountUp solves for concurrent count-up animations, same
	fix: a call that's been superseded stops writing instead of racing.
]]

local Players = game:GetService("Players")

local function computeFriendsInServer(player, excluding)
	local count = 0
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other ~= excluding then
			-- IsFriendsWith hits Roblox's backend and can fail like any
			-- other API call -- a single failed check must cost that one
			-- pairing, never the whole recompute (and never take the
			-- join/leave sequence down with it).
			local ok, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if ok and isFriend then
				count += 1
			end
		end
	end
	return count
end

local refreshToken = 0

local function refreshAll(excluding)
	refreshToken += 1
	local myToken = refreshToken

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= excluding then
			local count = computeFriendsInServer(player, excluding)

			-- A newer join/leave started (and will itself recompute every
			-- current player from scratch) while this call was still
			-- resolving IsFriendsWith calls -- stop writing rather than
			-- racing it with a now-stale snapshot.
			if refreshToken ~= myToken then
				return
			end

			player:SetAttribute("FriendsInServer", count)
		end
	end
end

Players.PlayerAdded:Connect(function()
	refreshAll(nil)
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	refreshAll(leavingPlayer)
end)

-- Covers a Studio script reload with players already in the world.
refreshAll(nil)

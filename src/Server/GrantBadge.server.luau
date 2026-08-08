local BS = game:GetService("BadgeService")
local badgefunc = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("GrantBadge")

-- This remote had NO validation on ID at all -- any client could FireServer
-- with any badge id string and get BS:AwardBadgeAsync called for it, no
-- matter which of the 13 badges it was or whether they'd done anything to
-- earn it. The only real caller (TheHollowGlitch.client.luau) only ever
-- asks for these two exact ids -- the secret Hollowed One badges, fired
-- when its own client-side lore event reaches Tier 1 / Tier 6. Restricting
-- to that allowlist closes the "claim literally any badge instantly" hole;
-- a forged call can now, at worst, claim early access to one of these two
-- specific badges rather than every badge in the game.
local ALLOWED_BADGE_IDS = {
	["1472053267504184"] = true, -- It Has Noticed You (Hollowed One, Tier 1)
	["3749419964014047"] = true, -- Nothing Left Hidden (Hollowed One, Tier 6)
}

badgefunc.OnServerEvent:Connect(function(plr, ID)
	if type(ID) ~= "string" or not ALLOWED_BADGE_IDS[ID] then
		warn(("GrantBadge: rejected request for badge id %s from %s"):format(tostring(ID), plr.Name))
		return
	end

	if not plr:GetAttribute(ID) then
		plr:SetAttribute(ID, true)

		-- Every other AwardBadgeAsync call in this codebase (StormController,
		-- RebirthHandler) uses the badge id as a NUMBER, both for the
		-- Badges[id] table write and the API call itself -- matching
		-- DefaultPlayerData.Badges' own numeric keys. This handler's `ID`
		-- arrives as the STRING the client sent, which would silently create
		-- a SEPARATE string-keyed entry alongside the real numeric-keyed
		-- default instead of updating it. tonumber() here can only make this
		-- more consistent with every other badge grant, never less --
		-- SetAttribute above intentionally keeps the string, since Roblox
		-- attribute names must be strings regardless.
		local numericId = tonumber(ID) or ID
		require(plr:WaitForChild("PlayerData")).Badges[numericId] = true
		BS:AwardBadgeAsync(plr.UserId, numericId)
	end
end)
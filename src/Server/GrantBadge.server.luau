local BS = game:GetService("BadgeService")
local badgefunc = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("GrantBadge")

badgefunc.OnServerEvent:Connect(function(plr,ID)
	if not plr:GetAttribute(ID) then
		plr:SetAttribute(ID, true)
		require(plr:WaitForChild("PlayerData")).Badges[ID] = true
		BS:AwardBadgeAsync(plr.UserId,ID)
	end
end)
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
local func = remotes:WaitForChild("Rebirth")
local BS = game:GetService("BadgeService")

local rebirthmodule = require(game:GetService("ReplicatedStorage"):WaitForChild("RebirthHandler"))
func.OnServerEvent:Connect(function(plr)
	local data = require(plr:WaitForChild("PlayerData"))
	local response = rebirthmodule.PerformRebirth(data,plr)
	if response == true then
		
		if not plr:GetAttribute("2522508290427820") then
			plr:SetAttribute("2522508290427820",true)
			data.Badges[2522508290427820] = true
			BS:AwardBadgeAsync(plr.UserId,2522508290427820)
		end
		
		if not plr:GetAttribute("2435657570989542") and data.Rebirths >= 10 then
			plr:SetAttribute("2435657570989542",true)
			data.Badges[2435657570989542] = true
			BS:AwardBadgeAsync(plr.UserId,2435657570989542)
		end
		
		func:FireClient(plr,response)
	end
end)
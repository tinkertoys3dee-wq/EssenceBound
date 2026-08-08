local RP = game:GetService("ReplicatedStorage")
local remotes = RP:WaitForChild("Remotes")
local func = remotes:WaitForChild("Rebirth")
local BS = game:GetService("BadgeService")

-- Owned/created by RebirthShopService.server.luau -- waited on rather than
-- created here so there's exactly one owner for the whole RebirthShop
-- remote set, regardless of which of the two scripts happens to run first.
local rebirthShopRemotes = RP:WaitForChild("RebirthShopRemotes", 10)
local TwinAscensionRemote = rebirthShopRemotes and rebirthShopRemotes:WaitForChild("TwinAscensionProc", 10)

local rebirthmodule = require(RP:WaitForChild("RebirthHandler"))
func.OnServerEvent:Connect(function(plr)
	local data = require(plr:WaitForChild("PlayerData"))
	local response, wasTwinAscension = rebirthmodule.PerformRebirth(data,plr)
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

		if wasTwinAscension and TwinAscensionRemote then
			TwinAscensionRemote:FireClient(plr)
		end
	end
end)
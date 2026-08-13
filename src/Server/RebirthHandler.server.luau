local RP = game:GetService("ReplicatedStorage")
local remotes = RP:WaitForChild("Remotes")
local func = remotes:WaitForChild("Rebirth")
local BS = game:GetService("BadgeService")
local NotificationService = require(RP:WaitForChild("NotificationService"))
local ProgressionConfig = require(RP:WaitForChild("ProgressionConfig"))

-- Owned/created by RebirthShopService.server.luau -- waited on rather than
-- created here so there's exactly one owner for the whole RebirthShop
-- remote set, regardless of which of the two scripts happens to run first.
local rebirthShopRemotes = RP:WaitForChild("RebirthShopRemotes", 10)
local TwinAscensionRemote = rebirthShopRemotes and rebirthShopRemotes:WaitForChild("TwinAscensionProc", 10)

local rebirthmodule = require(RP:WaitForChild("RebirthHandler"))
func.OnServerEvent:Connect(function(plr)
	local data = require(plr:WaitForChild("PlayerData"))
	local response, wasTwinAscension, essenceNeeded = rebirthmodule.PerformRebirth(data,plr)
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
	else
		local earthData = data.Essences and data.Essences["EarthEssence"]
		local current = earthData and (tonumber(earthData.Quantity) or 0) or 0
		local shortfall = math.max(0, (tonumber(essenceNeeded) or 0) - current)
		NotificationService.Send(plr, {
			Kind = "Warning",
			Title = "Not Enough Earth Essence",
			Message = ("You need %s more Earth Essence to rebirth."):format(ProgressionConfig.FormatNumber(shortfall)),
			Icon = "↻",
			Key = "rebirth-not-enough",
		})
	end
end)

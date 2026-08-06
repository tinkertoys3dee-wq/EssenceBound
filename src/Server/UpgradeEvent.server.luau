local RP = game:GetService("ReplicatedStorage")

local BuyRemote = RP:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")
local TreeModule = require(RP:WaitForChild("TreeUpgrades"))

BuyRemote.OnServerEvent:Connect(function(plr, name)
	local data = require(plr:FindFirstChild("PlayerData"))
	local canAfford = 	TreeModule.CanAfford(data,TreeModule.GetCostForNextLevel(name,TreeModule.GetCurrentLevel(data,name)))
	local prereq = TreeModule.IsUnlocked(data,name)
	if canAfford and prereq then
		TreeModule.PurchaseUpgrade(plr,data,name)
		local level = TreeModule.GetCurrentLevel(data,name)
		plr:SetAttribute(name,level)
		BuyRemote:FireClient(plr,name,level, data)
	end
end)
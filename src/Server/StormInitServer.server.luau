--[[
	StormServerInit (Script, place in ServerScriptService)
	--------------------------------------------------------
	Minimal wiring example for StormController. Swap GetPlayerData for
	however you actually load/save playerData (ProfileService, etc) -
	this stub is just here so the module has something driving it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StormController = require(script.Parent:WaitForChild("StormController")) -- adjust path
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EssenceStormEvent = Remotes:WaitForChild("EssenceStorm")

-- Add this RemoteEvent alongside your existing ones (ClickOrb, Return, etc)
local ManualStormSummon = Remotes:FindFirstChild("ManualStormSummon")
if not ManualStormSummon then
	ManualStormSummon = Instance.new("RemoteEvent")
	ManualStormSummon.Name = "ManualStormSummon"
	ManualStormSummon.Parent = Remotes
end

-- STUB: replace with your real data source (e.g. ProfileService profile.Data)
local datas = {
	
}
local function GetPlayerData(player)
	local data = require(player:WaitForChild("PlayerData"))
	return data
end

Players.PlayerAdded:Connect(function(player)
	local controller = StormController.new(player, GetPlayerData, EssenceStormEvent)
	controller:Start()
end)

Players.PlayerRemoving:Connect(function(player)
	local controller = StormController.Get(player)
	if controller then
		controller:Stop()
	end
end)

ManualStormSummon.OnServerEvent:Connect(function(player)
	local controller = StormController.Get(player)
	if controller then
		controller:TryManualSummon()
	end
end)
local RP = game:GetService("ReplicatedStorage")
local remotes = RP:WaitForChild("Remotes")

local GetData = remotes:WaitForChild("GetData")

GetData.OnServerInvoke = function(player)
	local data = {}
	for name, value in pairs(require(player:WaitForChild("PlayerData"))) do
		data[name] = value
	end
	print(data)
	return data
end
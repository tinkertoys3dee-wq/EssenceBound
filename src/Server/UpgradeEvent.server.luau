local RP = game:GetService("ReplicatedStorage")

local BuyRemote = RP:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")
local TreeModule = require(RP:WaitForChild("TreeUpgrades"))

-- Was calling TreeModule.CanAfford(data, TreeModule.GetCostForNextLevel(name, ...))
-- as a pre-check BEFORE PurchaseUpgrade -- but GetCostForNextLevel only
-- returns nil for a genuinely unknown upgrade id (it does NOT check
-- MaxLevel), and CanAfford does `for currency, amount in pairs(cost)`
-- with no nil-guard on `cost` itself. Any malformed/invalid `name` from
-- the client (a typo'd exploit call, or just a stale/renamed upgrade id)
-- crashed this handler with "bad argument #1 to 'pairs' (table expected,
-- got nil)" before ever reaching PurchaseUpgrade, which already does
-- every one of these checks correctly and returns false/reason instead
-- of erroring. PurchaseUpgrade is the real gatekeeper -- this now just
-- trusts it, rather than duplicating (and getting wrong) its own checks.
BuyRemote.OnServerEvent:Connect(function(plr, name)
	if type(name) ~= "string" then
		return
	end

	local playerDataModule = plr:FindFirstChild("PlayerData")
	if not playerDataModule then
		return
	end

	local ok, data = pcall(require, playerDataModule)
	if not ok or type(data) ~= "table" then
		return
	end

	local success = TreeModule.PurchaseUpgrade(plr, data, name)
	if success then
		local level = TreeModule.GetCurrentLevel(data, name)
		plr:SetAttribute(name, level)
		BuyRemote:FireClient(plr, name, level, data)
	end
end)

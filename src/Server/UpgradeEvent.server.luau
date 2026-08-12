local RP = game:GetService("ReplicatedStorage")

local BuyRemote = RP:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")
local TreeModule = require(RP:WaitForChild("TreeUpgrades"))
local NotificationService = require(RP:WaitForChild("NotificationService"))
local ProgressionConfig = require(RP:WaitForChild("ProgressionConfig"))

local function notifyPurchaseFailure(player, data, upgradeId, reason, missingCurrency)
	local definition = TreeModule.GetUpgrade(upgradeId)
	if not definition then
		return
	end

	if reason == "CannotAfford" then
		local costs = TreeModule.GetCostForNextLevel(upgradeId, TreeModule.GetCurrentLevel(data, upgradeId)) or {}
		local required = tonumber(costs[missingCurrency]) or 0
		local currencyData = data.Essences and data.Essences[missingCurrency]
		local balance = currencyData and (tonumber(currencyData.Quantity) or 0) or 0
		local shortfall = math.max(0, required - balance)
		local displayName = TreeModule.GetCurrencyDisplayName(missingCurrency) or "Essence"
		NotificationService.Send(player, {
			Kind = "Warning",
			Title = "Not Enough " .. displayName,
			Message = ("You need %s more %s for %s."):format(
				ProgressionConfig.FormatNumber(shortfall),
				displayName,
				definition.Name
			),
			Icon = "!",
			Key = "upgrade-currency:" .. tostring(missingCurrency),
		})
	elseif reason == "RebirthLocked" then
		NotificationService.Send(player, {
			Kind = "Warning",
			Title = "Rebirth Locked",
			Message = ("Reach Rebirth %d to unlock %s."):format(definition.RebirthRequired or 0, definition.Name),
			Icon = "↻",
			Key = "upgrade-rebirth:" .. upgradeId,
		})
	elseif reason == "PrerequisiteLocked" then
		local prerequisiteName = "the connected upgrade"
		for _, prerequisiteId in ipairs(definition.Prerequisites or {}) do
			if TreeModule.GetCurrentLevel(data, prerequisiteId) < 1 then
				local prerequisite = TreeModule.GetUpgrade(prerequisiteId)
				prerequisiteName = prerequisite and prerequisite.Name or prerequisiteName
				break
			end
		end
		NotificationService.Send(player, {
			Kind = "Info",
			Title = "Path Still Locked",
			Message = ("Buy %s first to reach %s."):format(prerequisiteName, definition.Name),
			Icon = "◇",
			Key = "upgrade-path:" .. upgradeId,
		})
	elseif reason == "MaxLevel" then
		NotificationService.Send(player, {
			Kind = "Info",
			Title = "Upgrade Maxed",
			Message = definition.Name .. " is already at its final level.",
			Icon = "★",
			Key = "upgrade-maxed:" .. upgradeId,
		})
	end
end

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
		NotificationService.Send(plr, {
			Kind = "Error",
			Title = "Upgrades Still Loading",
			Message = "Your upgrade data is still loading. Try again in a moment.",
			Key = "upgrade-data-loading",
		})
		return
	end

	local ok, data = pcall(require, playerDataModule)
	if not ok or type(data) ~= "table" then
		NotificationService.Send(plr, {
			Kind = "Error",
			Title = "Upgrades Unavailable",
			Message = "Your upgrade data could not be read. Try again in a moment.",
			Key = "upgrade-data-error",
		})
		return
	end

	local success, reason, missingCurrency = TreeModule.PurchaseUpgrade(plr, data, name)
	if success then
		local level = TreeModule.GetCurrentLevel(data, name)
		plr:SetAttribute(name, level)
		BuyRemote:FireClient(plr, name, level, data)

		local definition = TreeModule.GetUpgrade(name)
		if definition then
			NotificationService.Send(plr, {
				Kind = "Success",
				Title = "Upgrade Installed",
				Message = ("%s reached level %d."):format(definition.Name, level),
				Icon = "↑",
				Duration = 2.4,
				Key = "upgrade-success:" .. name,
			}, { Cooldown = 0 })
		end
	else
		notifyPurchaseFailure(plr, data, name, reason, missingCurrency)
	end
end)

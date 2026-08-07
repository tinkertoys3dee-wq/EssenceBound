--[[
    PRODUCT PURCHASE HANDLER
    ========================
    Server-side handler for Game Pass and Developer Product purchases.

    HOW TO USE
    ----------
    1. Replace the placeholder IDs in GAMEPASS_HANDLERS / PRODUCT_HANDLERS
       below with your real IDs from the Creator Dashboard.
    2. Fill in each handler function with what should actually happen
       (give currency, unlock a pet, apply a boost, etc). Use your own
       data/currency system in place of the print() placeholders.
    3. Place this Script in ServerScriptService.

    IMPORTANT
    ---------
    Only ONE script in your whole game should assign to
    MarketplaceService.ProcessReceipt (this one). If you have purchase
    logic elsewhere, route it through PRODUCT_HANDLERS here instead of
    setting ProcessReceipt a second time — the second assignment would
    silently overwrite the first and you'd stop getting paid for products
    handled by the one that got replaced.

    Game Passes are permanent, one-time purchases: ownership is re-checked
    and re-granted on every join (see grantOwnedGamePassesOnJoin) since a
    player could own a pass from before this handler even existed.

    Developer Products are consumable: they are only ever granted through
    ProcessReceipt, which Roblox guarantees will keep retrying until your
    handler returns PurchaseGranted — even across server crashes/restarts.

    HOOKING UP YOUR SHOP UI
    ------------------------
    This script also exposes a RemoteEvent at
    ReplicatedStorage.PurchaseRemotes.RequestPurchase so client UI (like
    the Shop popup) can trigger a purchase prompt without needing direct
    MarketplaceService access. From a LocalScript:

        local remotes = game:GetService("ReplicatedStorage"):WaitForChild("PurchaseRemotes")
        remotes.RequestPurchase:FireServer("gamepass", 123456789)
        remotes.RequestPurchase:FireServer("product", 345678901)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EPMService = require(game:GetService("ServerScriptService"):WaitForChild("EPMService"))
-------------------------------------------------------------------
-- 1) REGISTER YOUR HANDLERS HERE
-------------------------------------------------------------------

-- Game Pass purchases: [gamePassId] = function(player) ... end
-- Called once right after a successful purchase, AND again on every future
-- join (so the benefit is always re-applied, e.g. after a data reset).
local GAMEPASS_HANDLERS = {
	-- 2x Essence Multiplier
	[1907605899] = function(player) -- VIP Pass
		print(player.Name .. " now owns  2x Essence Multiplier")
		require(player:WaitForChild("PlayerData")).Gamepasses[1907605899] = {["Owned"] = true}
		player:SetAttribute(1907605899, true)
	end,
	--VIP Rank
	[1909291891] = function(player) -- Auto-Collect Pass
		print(player.Name .. " now owns VIP Rank")
		-- e.g. player:SetAttribute("AutoCollect", true)
		require(player:WaitForChild("PlayerData")).Gamepasses[1909291891] = {["Owned"] = true}
		player:SetAttribute(1909291891, true)
	end,
	--Lucky Finder (+50% Luck)
	[1907239833] = function(player) -- Auto-Collect Pass
		print(player.Name .. " now owns Lucky Finder (+50% Luck)")
		-- e.g. player:SetAttribute("AutoCollect", true)
		require(player:WaitForChild("PlayerData")).Gamepasses[1907239833] = {["Owned"] = true}
		player:SetAttribute(1907239833, true)
	end,
	--Ultra Luck (+300%)
	[1906063939] = function(player) -- Auto-Collect Pass
		print(player.Name .. " now owns Ultra Luck (+300%)")
		-- e.g. player:SetAttribute("AutoCollect", true)
		require(player:WaitForChild("PlayerData")).Gamepasses[1906063939] = {["Owned"] = true}
		player:SetAttribute(1906063939, true)
	end,
	--Auto Absorption
	[1907677938] = function(player) -- Auto-Collect Pass
		print(player.Name .. " now owns Auto Absorption")
		-- e.g. player:SetAttribute("AutoCollect", true)
		require(player:WaitForChild("PlayerData")).Gamepasses[1907677938] = {["Owned"] = true}
		player:SetAttribute(1907677938, true)
	end,
	--Material Alchemist (Offline Collection)
	[1907863864] = function(player) -- Auto-Collect Pass
		print(player.Name .. " now owns Material Alchemist (Offline Collection)")
		-- e.g. player:SetAttribute("AutoCollect", true)
		require(player:WaitForChild("PlayerData")).Gamepasses[1907863864] = {["Owned"] = true}
		player:SetAttribute(1907863864, true)
	end,
	--Dedicated Essence
	[1907077899] = function(player) -- Auto-Collect Pass
		print(player.Name .. " now owns Dedicated Essence")
		-- e.g. player:SetAttribute("AutoCollect", true)
		require(player:WaitForChild("PlayerData")).Gamepasses[1907077899] = {["Owned"] = true}
		player:SetAttribute(1907077899, true)
	end,
}

-- Developer Product purchases: [productId] = function(player) ... end
-- MUST return true on success, or false/nil on failure. Returning
-- anything other than true tells Roblox to retry the purchase later
-- instead of silently losing it.
local PotionTimerService = require(game.ServerScriptService:WaitForChild("PotionTimerService"))
local StormController = require(game.ServerScriptService:WaitForChild("StormController"))
local PRODUCT_HANDLERS = {
	[3609555390] = function(player) -- Mini Essence Potion (e.g. +250 Essence)
		print(player.Name .. " bought the Small Gem Pack")
		PotionTimerService.ApplyPotion(player, "EssenceX15", 60 * 3)
		
		return true
	end,

	[3609555456] = function(player) -- Moderate Essence Potion (e.g. +2000 Essence)
		print(player.Name .. " bought the Mega Gem Pack")
		PotionTimerService.ApplyPotion(player, "EssenceX15", 60 * 15)

		return true
	end,

	[3609555497] = function(player) -- Massive Essence Potion (24h)
		print(player.Name .. " bought the 2x Essence Boost")
		-- e.g. BoostService:Apply(player, "EssenceX2", 24 * 60 * 60)
		PotionTimerService.ApplyPotion(player, "EssenceX15", 60 * 90)

		return true
	end,
	
	[3609555580] = function(player) -- Essence Rain
		-- Storms are driven server-side: the controller owns the timer,
		-- the golden roll and the spawn interval, and tells the client
		-- what to draw. Firing the EssenceStorm remote from here directly
		-- (as this used to) sent the client a bare event with no action
		-- string or payload, which its handler simply ignored -- so the
		-- purchase took the player's Robux and produced nothing at all.
		local started, reason = StormController.ForceStormFor(player)

		if not started then
			warn(("Essence Rain purchase could not start a storm for %s: %s")
				:format(player.Name, tostring(reason)))
			-- Returning false leaves the receipt unprocessed so Roblox
			-- retries it, rather than charging for a storm that never ran.
			return false
		end

		return true
	end,

	[3609555620] = function(player) -- 5 Minute Time Warp (e.g. +2000 Essence)
		print(player.Name .. " bought the Mega Gem Pack")
		local EPMS = EPMService.getEPM(player)
		local data = require(player:WaitForChild("PlayerData"))
		local leaderstats = player:WaitForChild("leaderstats")
		for name, Quantity in pairs(EPMS) do
			if data.Essences[name].Discovered == true then
				leaderstats:WaitForChild(data.Essences[name].DisplayName or name):SetAttribute("Quantity",leaderstats:WaitForChild(data.Essences[name].DisplayName or name):GetAttribute("Quantity") + Quantity * 5)
				data.TotalEssenceGathered += Quantity * 5
			end
		end
		return true
	end,

	[3609555653] = function(player) -- 30 Minute Time Warp (24h)
		print(player.Name .. " bought the 2x Essence Boost")
		-- e.g. BoostService:Apply(player, "EssenceX2", 24 * 60 * 60)
		local EPMS = EPMService.getEPM(player)
		local data = require(player:WaitForChild("PlayerData"))
		local leaderstats = player:WaitForChild("leaderstats")
		for name, Quantity in pairs(EPMS) do
			if data.Essences[name].Discovered == true then
				leaderstats:WaitForChild(data.Essences[name].DisplayName or name):SetAttribute("Quantity",leaderstats:WaitForChild(data.Essences[name].DisplayName or name):GetAttribute("Quantity") + Quantity * 30)
				data.TotalEssenceGathered += Quantity * 30
			end
		end
		return true
	end,
}

local sound = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("UI"):WaitForChild("RobuxPurchase")
-------------------------------------------------------------------
-- 2) GAME PASS PURCHASE HANDLING
-------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then
		return
	end
	sound:Play()
	require(player:WaitForChild("PlayerData")).RobuxSpent += MarketplaceService:GetProductInfoAsync(gamePassId).PriceInRobux
	local handler = GAMEPASS_HANDLERS[gamePassId]
	if not handler then
		warn(("No handler registered for GamePass id %d"):format(gamePassId))
		return
	end

	local ok, err = pcall(handler, player)
	if not ok then
		warn(("GamePass handler for id %d errored: %s"):format(gamePassId, tostring(err)))
	end
end)

-- Re-grants any owned game pass whenever a player joins, in case they
-- already owned it before a handler existed for it, or the benefit needs
-- to be re-applied every session (e.g. a flag that isn't saved in data).
local function grantOwnedGamePassesOnJoin(player)
	for gamePassId, handler in pairs(GAMEPASS_HANDLERS) do
		task.spawn(function()
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
			end)

			if not ok then
				warn(("UserOwnsGamePassAsync failed for id %d: %s"):format(gamePassId, tostring(owns)))
				return
			end

			if owns then
				local success, err = pcall(handler, player)
				if not success then
					warn(("GamePass re-grant for id %d errored: %s"):format(gamePassId, tostring(err)))
				end
			end
		end)
	end
end

Players.PlayerAdded:Connect(grantOwnedGamePassesOnJoin)

-- catch anyone already in the game when this script starts (e.g. a Studio script reload)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	grantOwnedGamePassesOnJoin(existingPlayer)
end

-------------------------------------------------------------------
-- 3) DEVELOPER PRODUCT PURCHASE HANDLING
-------------------------------------------------------------------
local purchaseHistoryStore = DataStoreService:GetDataStore("PurchaseHistoryStore")

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	-- player isn't in the game anymore (e.g. they left mid-purchase) — ask
	-- Roblox to hold onto the receipt and try again later
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- guard against double-granting if this exact receipt was already
	-- handled (e.g. the server crashed after granting but before we could
	-- return PurchaseGranted, so Roblox sent it again)
	local receiptKey = "Receipt_" .. receiptInfo.PurchaseId
	local alreadyGranted
	local historyOk = pcall(function()
		alreadyGranted = purchaseHistoryStore:GetAsync(receiptKey)
	end)

	if historyOk and alreadyGranted then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	
	sound:Play()
	local handler = PRODUCT_HANDLERS[receiptInfo.ProductId]
	require(player:WaitForChild("PlayerData")).RobuxSpent += receiptInfo.CurrencySpent

	if not handler then
		warn(("No handler registered for Developer Product id %d"):format(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	
	local success, result = pcall(handler, player)
	if not success then
		warn(("Product handler for id %d errored: %s"):format(receiptInfo.ProductId, tostring(result)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if result ~= true then
		-- handler reported it couldn't complete the grant — let Roblox retry
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- record that this receipt has been granted so a retry never double-grants
	pcall(function()
		purchaseHistoryStore:SetAsync(receiptKey, true)
	end)
	

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-------------------------------------------------------------------
-- 4) CLIENT-FACING REMOTE (lets your Shop UI trigger purchase prompts)
-------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")

local requestPurchaseRemote = remotesFolder:FindFirstChild("RequestPurchase")

requestPurchaseRemote.OnServerEvent:Connect(function(player, purchaseType, id)
	id = tonumber(id)
	if typeof(id) ~= "number" then
		return
	end
	if purchaseType == "gamepass" then
		if GAMEPASS_HANDLERS[id] then
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			warn(("%s requested an unregistered GamePass id: %d"):format(player.Name, id))
		end
	elseif purchaseType == "product" then
		if PRODUCT_HANDLERS[id] then
			MarketplaceService:PromptProductPurchase(player, id)
		else
			warn(("%s requested an unregistered Product id: %d"):format(player.Name, id))
		end
	else
		warn(("%s sent an unknown purchase type: %s"):format(player.Name, tostring(purchaseType)))
	end
end)
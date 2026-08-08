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
		if not EPMS then
			-- getEPM returns bare nil if EPMService.ActiveSessions has no
			-- entry for this player yet (e.g. a receipt processed before
			-- PlayerDataHandler finished its join sequence) -- pairs(nil)
			-- would otherwise throw here and take a paid purchase down
			-- with it. Same "return false, let Roblox retry" contract as
			-- the Essence Rain handler above; nothing charged is lost.
			warn(("ProductPurchaseHandler: no EPM session yet for %s, deferring Time Warp purchase"):format(player.Name))
			return false
		end
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
		if not EPMS then
			-- See the 5 Minute Time Warp handler above -- same missing-
			-- session guard, same safe retry contract.
			warn(("ProductPurchaseHandler: no EPM session yet for %s, deferring Time Warp purchase"):format(player.Name))
			return false
		end
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

-- Was a bare WaitForChild chain with no timeout, and -- critically --
-- this runs BEFORE ProcessReceipt gets assigned further down. If
-- SFX/UI/RobuxPurchase were ever missing or renamed in Studio, this
-- would hang here forever and NONE of the purchase-granting logic
-- below it (ProcessReceipt, PromptGamePassPurchaseFinished, the
-- join-time gamepass re-grant) would ever get wired up -- silently
-- disabling every gamepass and developer product in the game, not
-- just this one sound effect. Timed lookup + a safePlay guard at both
-- call sites (this codebase's established pattern) means a missing
-- sound now costs only its own sound effect, never the game's ability
-- to process a single purchase.
local sfxFolder = game:GetService("SoundService"):FindFirstChild("SFX")
	or game:GetService("SoundService"):WaitForChild("SFX", 5)
local uiFolder = sfxFolder and (sfxFolder:FindFirstChild("UI") or sfxFolder:WaitForChild("UI", 5))
local sound = uiFolder and (uiFolder:FindFirstChild("RobuxPurchase") or uiFolder:WaitForChild("RobuxPurchase", 5))

local function safePlaySound()
	if sound then
		sound:Play()
	end
end

-------------------------------------------------------------------
-- 2) GAME PASS PURCHASE HANDLING
-------------------------------------------------------------------
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then
		return
	end
	safePlaySound()

	-- GetProductInfoAsync is a real network call to Roblox and can fail
	-- (rate limit, transient outage) -- was unguarded and ran BEFORE the
	-- handler lookup/call below, so a failure here used to skip the
	-- actual grant entirely for this event. Unlike ProcessReceipt (which
	-- Roblox itself keeps retrying until PurchaseGranted),
	-- PromptGamePassPurchaseFinished fires exactly once with no retry --
	-- the only safety net is grantOwnedGamePassesOnJoin re-checking
	-- ownership on this player's NEXT join, which means a transient
	-- failure here would have delayed a paying player's purchase rather
	-- than applying it immediately. Wrapped so a failure here costs only
	-- the RobuxSpent stat, never the grant.
	local ok, err = pcall(function()
		local info = MarketplaceService:GetProductInfoAsync(gamePassId)
		require(player:WaitForChild("PlayerData")).RobuxSpent += info.PriceInRobux
	end)
	if not ok then
		warn(("Could not record RobuxSpent for GamePass id %d: %s"):format(gamePassId, tostring(err)))
	end

	local handler = GAMEPASS_HANDLERS[gamePassId]
	if not handler then
		warn(("No handler registered for GamePass id %d"):format(gamePassId))
		return
	end

	local grantOk, grantErr = pcall(handler, player)
	if not grantOk then
		warn(("GamePass handler for id %d errored: %s"):format(gamePassId, tostring(grantErr)))
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

	safePlaySound()
	local handler = PRODUCT_HANDLERS[receiptInfo.ProductId]

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

	-- RobuxSpent used to be credited BEFORE the handler-exists/succeeds
	-- checks above, which meant every automatic Roblox retry of an
	-- unregistered product id (or a handler that legitimately keeps
	-- returning false, like Essence Rain waiting for a valid storm slot)
	-- re-credited it again -- unbounded over enough retries. Moved here,
	-- right alongside the "receipt fully granted" store write below, so
	-- it only ever counts once per receipt, same guarantee that write
	-- already has.
	pcall(function()
		require(player:WaitForChild("PlayerData")).RobuxSpent += receiptInfo.CurrencySpent
	end)

	-- record that this receipt has been granted so a retry never double-grants
	pcall(function()
		purchaseHistoryStore:SetAsync(receiptKey, true)
	end)


	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-------------------------------------------------------------------
-- 4) CLIENT-FACING REMOTE (lets your Shop UI trigger purchase prompts)
-------------------------------------------------------------------
-- Was two bare FindFirstChild calls with no creation fallback, then
-- indexing straight into requestPurchaseRemote.OnServerEvent below --
-- if "Remotes" or "RequestPurchase" didn't already exist, this would
-- crash the whole script right here. Everything ABOVE this point
-- (ProcessReceipt, PromptGamePassPurchaseFinished, the join-time
-- gamepass re-grant) is already wired up by the time execution reaches
-- this line, so a crash here wouldn't have broken real purchase
-- granting -- but it would silently break the Shop UI's ability to
-- ever prompt a purchase in the first place. ensureRemote-style
-- fallback, same pattern used everywhere else in this codebase.
local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "Remotes"
	remotesFolder.Parent = ReplicatedStorage
end

local requestPurchaseRemote = remotesFolder:FindFirstChild("RequestPurchase")
if not requestPurchaseRemote then
	requestPurchaseRemote = Instance.new("RemoteEvent")
	requestPurchaseRemote.Name = "RequestPurchase"
	requestPurchaseRemote.Parent = remotesFolder
end

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
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
    ReplicatedStorage.Remotes.RequestPurchase so client UI (like
    the Shop popup) can trigger a purchase prompt without needing direct
    MarketplaceService access. From a LocalScript:

        local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
        remotes.RequestPurchase:FireServer("gamepass", 123456789)
        remotes.RequestPurchase:FireServer("product", 345678901)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EPMService = require(game:GetService("ServerScriptService"):WaitForChild("EPMService"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

-- Analytics must never be able to block a paid grant. The real module is
-- server-authoritative and normally always present; the no-op fallback keeps
-- checkout operational even if an incomplete Studio sync omitted it.
local MonetizationAnalytics = {
	LogPrompt = function() end,
	LogPurchase = function() end,
}
do
	local module = game:GetService("ServerScriptService"):FindFirstChild("MonetizationAnalytics")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			MonetizationAnalytics = result
		else
			warn("ProductPurchaseHandler: MonetizationAnalytics unavailable; checkout remains enabled.")
		end
	end
end
-------------------------------------------------------------------
-- 1) REGISTER YOUR HANDLERS HERE
-------------------------------------------------------------------

local function markGamePassOwned(player, gamePassId)
	local data = require(player:WaitForChild("PlayerData"))
	if type(data.Gamepasses) ~= "table" then
		data.Gamepasses = {}
	end
	local attribute = MonetizationConfig.GetOwnershipAttribute(gamePassId)
	data.Gamepasses[gamePassId] = nil -- remove the legacy numeric-key form
	data.Gamepasses[attribute] = { Owned = true }
	player:SetAttribute(attribute, true)
end

-- Game Pass purchases: [gamePassId] = function(player) ... end
-- Called once right after a successful purchase, AND again on every future
-- join (so the benefit is always re-applied, e.g. after a data reset).
local GAMEPASS_HANDLERS = {
	-- 2x Essence Multiplier
	[1907605899] = function(player)
		print(player.Name .. " now owns  2x Essence Multiplier")
		markGamePassOwned(player, 1907605899)
	end,
	--VIP Rank
	[1909291891] = function(player)
		print(player.Name .. " now owns VIP Rank")
		-- e.g. player:SetAttribute("AutoCollect", true)
		markGamePassOwned(player, 1909291891)
	end,
	--Lucky Finder (+50% Luck)
	[1907239833] = function(player)
		print(player.Name .. " now owns Lucky Finder (+50% Luck)")
		-- e.g. player:SetAttribute("AutoCollect", true)
		markGamePassOwned(player, 1907239833)
	end,
	--Ultra Luck (2x rare weight alone, 3x total with Lucky Finder)
	[1906063939] = function(player)
		print(player.Name .. " now owns Ultra Luck")
		-- e.g. player:SetAttribute("AutoCollect", true)
		markGamePassOwned(player, 1906063939)
	end,
	--Auto Absorption
	[1907677938] = function(player)
		print(player.Name .. " now owns Auto Absorption")
		-- e.g. player:SetAttribute("AutoCollect", true)
		markGamePassOwned(player, 1907677938)
	end,
	--Material Alchemist (Offline Collection)
	[1907863864] = function(player)
		print(player.Name .. " now owns Material Alchemist (Offline Collection)")
		-- e.g. player:SetAttribute("AutoCollect", true)
		markGamePassOwned(player, 1907863864)
	end,
	--Dedicated Essence
	[1907077899] = function(player)
		print(player.Name .. " now owns Dedicated Essence")
		-- e.g. player:SetAttribute("AutoCollect", true)
		markGamePassOwned(player, 1907077899)
	end,
}

-- Developer Product purchases: [productId] = function(player) ... end
-- MUST return true on success, or false/nil on failure. Returning
-- anything other than true tells Roblox to retry the purchase later
-- instead of silently losing it.
local PotionTimerService = require(game.ServerScriptService:WaitForChild("PotionTimerService"))
local StormController = require(game.ServerScriptService:WaitForChild("StormController"))

local function applyPaidPotion(player, duration)
	local before = PotionTimerService.GetRemainingTime(player, "EssenceX15")
	PotionTimerService.ApplyPotion(player, "EssenceX15", duration)
	local after = PotionTimerService.GetRemainingTime(player, "EssenceX15")
	if after < before + duration - 5 then
		warn(("ProductPurchaseHandler: potion state not ready for %s; deferring receipt"):format(player.Name))
		return false
	end
	return true
end

local PRODUCT_HANDLERS = {
	[3609555390] = function(player) -- Mini Essence Potion (3 minutes)
		print(player.Name .. " bought the Mini Essence Potion")
		return applyPaidPotion(player, 60 * 3)
	end,

	[3609555456] = function(player) -- Moderate Essence Potion (15 minutes)
		print(player.Name .. " bought the Moderate Essence Potion")
		return applyPaidPotion(player, 60 * 15)
	end,

	[3609555497] = function(player) -- Massive Essence Potion (90 minutes)
		print(player.Name .. " bought the Massive Essence Potion")
		return applyPaidPotion(player, 60 * 90)
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

	[3609555620] = function(player) -- 5 Minute Time Warp
		print(player.Name .. " bought the 5 Minute Time Warp")
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

	[3609555653] = function(player) -- 30 Minute Time Warp
		print(player.Name .. " bought the 30 Minute Time Warp")
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

-- =====================================================================
-- FIRST-PURCHASE SUPPORTER BLESSING
-- =====================================================================
-- The first successfully granted purchase of ANY catalog item receives a
-- permanent +10% multiplier and an immediate 15-minute 1.5x boost. The
-- pending flag makes the timed portion retryable if potion state happened
-- to be loading when a receipt arrived, without ever replaying the paid
-- product's own handler.

local function getPlayerData(player)
	local module = player:FindFirstChild("PlayerData")
	if not module then
		return nil
	end
	local ok, data = pcall(require, module)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

local function syncPurchaseAttributes(player, data)
	player:SetAttribute("RobuxSpent", math.max(0, tonumber(data.RobuxSpent) or 0))
	player:SetAttribute("PurchaseCount", math.max(0, math.floor(tonumber(data.PurchaseCount) or 0)))
	player:SetAttribute("FirstPurchaseBonusClaimed", data.FirstPurchaseBonusClaimed == true)
end

local bonusGrantInProgress = setmetatable({}, { __mode = "k" })

local function tryGrantFirstPurchaseBonus(player)
	local data = getPlayerData(player)
	if not data or data.FirstPurchaseBonusClaimed == true then
		return data ~= nil
	end
	if data.FirstPurchaseBonusPending ~= true then
		return false
	end
	if bonusGrantInProgress[player] then
		return false
	end
	bonusGrantInProgress[player] = true

	local bonus = MonetizationConfig.FirstPurchaseBonus
	local ok, before, after = pcall(function()
		local priorTime = PotionTimerService.GetRemainingTime(player, bonus.BoostEffect)
		PotionTimerService.ApplyPotion(player, bonus.BoostEffect, bonus.BoostSeconds)
		return priorTime, PotionTimerService.GetRemainingTime(player, bonus.BoostEffect)
	end)

	-- ApplyPotion intentionally returns nil, so an increased persisted timer
	-- is the concrete success signal. Leave Pending true on failure so the
	-- join/retry worker below can finish the promise later.
	if not ok or after < before + bonus.BoostSeconds - 5 then
		bonusGrantInProgress[player] = nil
		if not ok then
			warn(("ProductPurchaseHandler: Supporter Blessing boost failed for %s: %s")
				:format(player.Name, tostring(before)))
		end
		return false
	end

	data.FirstPurchaseBonusPending = false
	data.FirstPurchaseBonusClaimed = true
	player:SetAttribute("FirstPurchaseBonusClaimed", true)
	bonusGrantInProgress[player] = nil
	return true
end

local function recordSuccessfulPurchase(player, robuxAmount)
	local data = getPlayerData(player)
	if not data then
		warn("ProductPurchaseHandler: PlayerData missing while recording a successful purchase for " .. player.Name)
		return false
	end

	local amount = math.max(0, math.floor(tonumber(robuxAmount) or 0))
	data.RobuxSpent = math.max(0, tonumber(data.RobuxSpent) or 0) + amount
	data.PurchaseCount = math.max(0, math.floor(tonumber(data.PurchaseCount) or 0)) + 1

	if data.FirstPurchaseBonusClaimed ~= true then
		data.FirstPurchaseBonusPending = true
	end
	syncPurchaseAttributes(player, data)
	tryGrantFirstPurchaseBonus(player)
	return true
end

local function resumeFirstPurchaseBonus(player)
	local module = player:FindFirstChild("PlayerData") or player:WaitForChild("PlayerData", 30)
	if not module then
		return
	end
	local data = getPlayerData(player)
	if not data then
		return
	end

	-- Returning payers whose saves predate this feature receive the same
	-- thank-you instead of being excluded merely because they bought early.
	if data.FirstPurchaseBonusClaimed ~= true
		and (data.FirstPurchaseBonusPending == true
			or (tonumber(data.PurchaseCount) or 0) > 0
			or (tonumber(data.RobuxSpent) or 0) > 0)
	then
		data.FirstPurchaseBonusPending = true
	end
	syncPurchaseAttributes(player, data)

	for _ = 1, 6 do
		if data.FirstPurchaseBonusClaimed == true or data.FirstPurchaseBonusPending ~= true then
			break
		end
		if tryGrantFirstPurchaseBonus(player) then
			break
		end
		task.wait(2)
	end
end

local function migrateLegacyGamePassOwner(player)
	local data = getPlayerData(player)
	if not data or data.FirstPurchaseBonusClaimed == true then
		return
	end

	-- Ownership is proof of an earlier Robux purchase even when that save
	-- predates RobuxSpent tracking. Do not invent a historical spend amount;
	-- record only the minimum purchase count needed to grant the thank-you.
	data.PurchaseCount = math.max(1, math.floor(tonumber(data.PurchaseCount) or 0))
	data.FirstPurchaseBonusPending = true
	syncPurchaseAttributes(player, data)
	task.spawn(resumeFirstPurchaseBonus, player)
end

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
	-- the historical spend display, never the game-pass grant.
	local priceInRobux = 0
	local priceOk, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(gamePassId, Enum.InfoType.GamePass)
	end)
	if not priceOk then
		priceOk, info = pcall(function()
			return MarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
		end)
	end
	if priceOk and type(info) == "table" then
		priceInRobux = math.max(0, tonumber(info.PriceInRobux) or 0)
	end

	local handler = GAMEPASS_HANDLERS[gamePassId]
	if not handler then
		warn(("No handler registered for GamePass id %d"):format(gamePassId))
		return
	end

	local grantOk, grantErr = pcall(handler, player)
	if not grantOk then
		warn(("GamePass handler for id %d errored: %s"):format(gamePassId, tostring(grantErr)))
		return
	end

	recordSuccessfulPurchase(player, priceInRobux)
	MonetizationAnalytics.LogPurchase(player, gamePassId, priceInRobux)
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
				else
					migrateLegacyGamePassOwner(player)
				end
			end
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	grantOwnedGamePassesOnJoin(player)
	task.spawn(resumeFirstPurchaseBonus, player)
end)

-- catch anyone already in the game when this script starts (e.g. a Studio script reload)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	grantOwnedGamePassesOnJoin(existingPlayer)
	task.spawn(resumeFirstPurchaseBonus, existingPlayer)
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
	recordSuccessfulPurchase(player, receiptInfo.CurrencySpent)
	MonetizationAnalytics.LogPurchase(player, receiptInfo.ProductId, receiptInfo.CurrencySpent)

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
if requestPurchaseRemote and not requestPurchaseRemote:IsA("RemoteEvent") then
	requestPurchaseRemote:Destroy()
	requestPurchaseRemote = nil
end
if not requestPurchaseRemote then
	requestPurchaseRemote = Instance.new("RemoteEvent")
	requestPurchaseRemote.Name = "RequestPurchase"
	requestPurchaseRemote.Parent = remotesFolder
end

local lastPromptAt = setmetatable({}, { __mode = "k" })

requestPurchaseRemote.OnServerEvent:Connect(function(player, purchaseType, id, source)
	id = tonumber(id)
	if typeof(id) ~= "number" then
		return
	end
	local now = os.clock()
	if now - (lastPromptAt[player] or 0) < 1.25 then
		return
	end
	if purchaseType == "gamepass" then
		if GAMEPASS_HANDLERS[id] then
			lastPromptAt[player] = now
			MonetizationAnalytics.LogPrompt(player, id, source)
			MarketplaceService:PromptGamePassPurchase(player, id)
		else
			warn(("%s requested an unregistered GamePass id: %d"):format(player.Name, id))
		end
	elseif purchaseType == "product" then
		if PRODUCT_HANDLERS[id] then
			lastPromptAt[player] = now
			MonetizationAnalytics.LogPrompt(player, id, source)
			MarketplaceService:PromptProductPurchase(player, id)
		else
			warn(("%s requested an unregistered Product id: %d"):format(player.Name, id))
		end
	else
		warn(("%s sent an unknown purchase type: %s"):format(player.Name, tostring(purchaseType)))
	end
end)

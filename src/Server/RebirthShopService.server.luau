--[[
	RebirthShopService (Script -> ServerScriptService)
	===================================================
	Server-authoritative purchasing for the Prestige Shop -- what Rebirth
	Currency ("Prestige Shards") actually buys (see
	ReplicatedStorage.RebirthShopUpgrades for the definitions).

	Same authority model as SanctumService: the client can only ever ASK to
	buy something. Level, cost and balance are all re-derived from server
	state here, never trusted from the client.

	Balance lives on the plain player Attribute "RebirthCurrency" (not a
	leaderstat Quantity sub-attribute like Earth/Shadow Essence use) --
	that's the attribute RebirthHandler.luau's PerformRebirth already reads
	and writes for the rebirth grant itself, so purchases just spend from
	the same single number. PlayerDataHandler mirrors a leaderstat from it
	automatically.

	This script is also the single owner of the three GAMEPLAY-EFFECT
	remotes the five upgrades need (Twin Ascension / Second Wind / Shard
	Rain) -- creating them here, up front, means every other server script
	that fires them (RebirthHandler.server.luau, OrbClickManager.server.luau)
	can just WaitForChild them without caring about script execution order.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RebirthShopUpgrades = require(ReplicatedStorage:WaitForChild("RebirthShopUpgrades"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local remotesFolder = ReplicatedStorage:FindFirstChild("RebirthShopRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "RebirthShopRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemote(className, name)
	local existing = remotesFolder:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = remotesFolder
	return remote
end

local PurchaseRemote = ensureRemote("RemoteEvent", "PurchaseRebirthUpgrade")
local SyncRemote = ensureRemote("RemoteEvent", "RebirthShopSync")
local RequestSyncRemote = ensureRemote("RemoteEvent", "RequestRebirthShopSync")

-- Gameplay-effect remotes, purely cosmetic triggers for the client-side
-- payoff of each upgrade -- none of them grant anything themselves, the
-- reward is always already-applied server-side before these fire. Not
-- consumed in this file (RebirthHandler.server.luau and
-- OrbClickManager.server.luau fire them) -- created here, up front, so
-- those scripts can WaitForChild them regardless of script execution
-- order, rather than each needing its own ensureRemote fallback.
ensureRemote("RemoteEvent", "TwinAscensionProc")
ensureRemote("RemoteEvent", "SecondWindProc")
ensureRemote("RemoteEvent", "ShardRainProc")

-- =========================================================================
-- HELPERS
-- =========================================================================

local purchaseDebounce = {}
local PURCHASE_DEBOUNCE = 0.2

local function getData(player)
	local module = player:FindFirstChild("PlayerData")
	if not module then
		return nil
	end

	local ok, data = pcall(require, module)
	if not ok or type(data) ~= "table" then
		return nil
	end

	if type(data.RebirthShopUpgrades) ~= "table" then
		data.RebirthShopUpgrades = {}
	end

	return data
end

local function getBalance(player)
	return tonumber(player:GetAttribute(RebirthShopUpgrades.CURRENCY_ATTRIBUTE)) or 0
end

-- Builds the full snapshot the panel renders from. Levels and costs are
-- computed here rather than client-side so the price a player is shown is
-- always the price the server will actually charge.
local function buildState(player)
	local data = getData(player)
	if not data then
		return nil
	end

	local entries = {}
	for index, def in ipairs(RebirthShopUpgrades.List) do
		local level = tonumber(data.RebirthShopUpgrades[def.Id]) or 0
		level = math.clamp(math.floor(level), 0, def.MaxLevel)

		entries[index] = {
			Id = def.Id,
			Name = def.Name,
			Description = def.Description,
			Icon = def.Icon,
			Level = level,
			MaxLevel = def.MaxLevel,
			Cost = RebirthShopUpgrades.GetCostForNextLevel(def.Id, level),
			CurrentEffect = level > 0 and RebirthShopUpgrades.DescribeEffect(def.Id, level) or nil,
			NextEffect = level < def.MaxLevel
				and RebirthShopUpgrades.DescribeEffect(def.Id, level + 1)
				or nil,
		}
	end

	return {
		Balance = getBalance(player),
		Rebirths = player:GetAttribute("Rebirths") or 0,
		Upgrades = entries,
	}
end

local function pushState(player)
	local state = buildState(player)
	if state then
		SyncRemote:FireClient(player, state)
	end
end

-- =========================================================================
-- PURCHASE
-- =========================================================================

PurchaseRemote.OnServerEvent:Connect(function(player, upgradeId)
	local now = os.clock()
	local last = purchaseDebounce[player]
	if last and (now - last) < PURCHASE_DEBOUNCE then
		return
	end
	purchaseDebounce[player] = now

	if type(upgradeId) ~= "string" then
		return
	end

	local def = RebirthShopUpgrades.GetUpgrade(upgradeId)
	if not def then
		-- Not a real upgrade id: a forged or stale request.
		return
	end

	local data = getData(player)
	if not data then
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Shop Still Loading",
			Message = "Your prestige upgrades are still loading. Try again in a moment.",
			Key = "rebirth-shop-loading",
		})
		return
	end

	-- Level is re-read from server data, never taken from the client.
	local level = tonumber(data.RebirthShopUpgrades[upgradeId]) or 0
	level = math.clamp(math.floor(level), 0, def.MaxLevel)

	if level >= def.MaxLevel then
		pushState(player)
		NotificationService.Send(player, {
			Kind = "Info",
			Title = "Relic Maxed",
			Message = def.Name .. " is already fully awakened.",
			Icon = "★",
			Key = "rebirth-shop-maxed:" .. upgradeId,
		})
		return
	end

	local cost = RebirthShopUpgrades.GetCostForNextLevel(upgradeId, level)
	if not cost then
		pushState(player)
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Price Unavailable",
			Message = "That relic's next price could not be loaded. Try again in a moment.",
			Key = "rebirth-shop-price:" .. upgradeId,
		})
		return
	end

	local balance = getBalance(player)
	if balance < cost then
		-- Re-sync so a client showing a stale price corrects itself.
		pushState(player)
		NotificationService.Send(player, {
			Kind = "Warning",
			Title = "Not Enough Prestige Shards",
			Message = ("You need %s more Prestige Shards for %s."):format(
				ProgressionConfig.FormatNumber(cost - balance),
				def.Name
			),
			Icon = RebirthShopUpgrades.CURRENCY_ICON,
			Key = "rebirth-shop-currency",
		})
		return
	end

	-- Deduct via the attribute -- PlayerDataHandler's changed-signal
	-- listener mirrors this into both the leaderstat and playerData, so
	-- writing both here would risk them drifting apart.
	player:SetAttribute(RebirthShopUpgrades.CURRENCY_ATTRIBUTE, balance - cost)

	local newLevel = level + 1
	data.RebirthShopUpgrades[upgradeId] = newLevel

	-- The systems this upgrade affects (EssenceMultiplier,
	-- EssenceOrbController, OrbClickManager, CursorCollection,
	-- RebirthHandler) all read this attribute directly.
	player:SetAttribute(upgradeId, newLevel)

	pushState(player)
	NotificationService.Send(player, {
		Kind = "Success",
		Title = "Prestige Relic Awakened",
		Message = ("%s reached level %d."):format(def.Name, newLevel),
		Icon = RebirthShopUpgrades.CURRENCY_ICON,
		Duration = 2.8,
		Key = "rebirth-shop-success:" .. upgradeId,
	}, { Cooldown = 0 })
end)

local requestSyncDebounce = {}
local REQUEST_SYNC_DEBOUNCE = 1

RequestSyncRemote.OnServerEvent:Connect(function(player)
	-- Read-only, but still debounced against a client stuck in a fast loop.
	local now = os.clock()
	local last = requestSyncDebounce[player]
	if last and (now - last) < REQUEST_SYNC_DEBOUNCE then
		return
	end
	requestSyncDebounce[player] = now

	pushState(player)
end)

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local pendingPush = {}

local function requestPush(player)
	pendingPush[player] = true
end

task.spawn(function()
	while true do
		task.wait(0.5)

		for player in pairs(pendingPush) do
			pendingPush[player] = nil
			if player.Parent then
				local ok, err = pcall(pushState, player)
				if not ok then
					warn("RebirthShopService: state push failed: " .. tostring(err))
				end
			end
		end
	end
end)

local function onPlayerAdded(player)
	task.spawn(function()
		-- Balance and Rebirths are both plain attributes PlayerDataHandler
		-- sets synchronously during its own join sequence -- wait for the
		-- attribute rather than a fixed delay, same fix as the Sanctum
		-- "stuck showing 0" bug: a guess that's usually long enough still
		-- fails for the player it fails for.
		if player:GetAttribute("RebirthCurrency") == nil then
			player:GetAttributeChangedSignal("RebirthCurrency"):Wait()
		end

		if not player.Parent then
			return
		end

		task.wait(0.5)
		if player.Parent then
			pushState(player)
		end

		player:GetAttributeChangedSignal("RebirthCurrency"):Connect(function()
			if player.Parent then
				requestPush(player)
			end
		end)
		player:GetAttributeChangedSignal("Rebirths"):Connect(function()
			if player.Parent then
				requestPush(player)
			end
		end)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	purchaseDebounce[player] = nil
	pendingPush[player] = nil
	requestSyncDebounce[player] = nil
end)

for _, existing in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existing)
end

--[[
	SanctumService (Script -> ServerScriptService)
	==============================================
	Server-authoritative purchasing for the Shadow Sanctum -- the first
	place Shadow Essence can actually be spent (see
	ReplicatedStorage.SanctumUpgrades for the definitions and the reasoning).

	AUTHORITY
	----------
	The client can only ever ASK to buy something. This script re-derives
	the level, the cost and the balance from server state, and is the only
	thing that deducts currency or grants a level. A forged request can
	claim to be buying anything at any level; none of that is trusted.

	Currency is deducted by writing the leaderstat's Quantity attribute,
	which is the same path the rest of the economy uses -- PlayerDataHandler
	is listening on that attribute and mirrors the value back into
	PlayerData, so there is exactly one place that owns the number.

	Levels are stored in PlayerData.SanctumUpgrades, deliberately separate
	from PlayerData.Upgrades: a rebirth wipes the Earth Essence tree, and
	what Shadow Essence bought must survive that.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SanctumUpgrades = require(ReplicatedStorage:WaitForChild("SanctumUpgrades"))

-- =========================================================================
-- REMOTES
-- =========================================================================

local remotesFolder = ReplicatedStorage:FindFirstChild("SanctumRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "SanctumRemotes"
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

local PurchaseRemote = ensureRemote("RemoteEvent", "PurchaseSanctumUpgrade")
local SyncRemote = ensureRemote("RemoteEvent", "SanctumSync")
-- Lets the panel ask for a fresh read whenever it's opened, rather than
-- depending solely on the one push at join. Defense in depth against any
-- future timing edge case producing the same "stuck showing 0" bug the
-- join-time race above just caused.
local RequestSyncRemote = ensureRemote("RemoteEvent", "RequestSanctumSync")

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

	if type(data.SanctumUpgrades) ~= "table" then
		data.SanctumUpgrades = {}
	end

	return data
end

local function getShadowStat(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end
	return leaderstats:FindFirstChild(SanctumUpgrades.CURRENCY)
end

local function getBalance(player)
	local stat = getShadowStat(player)
	if not stat then
		return 0
	end
	return tonumber(stat:GetAttribute("Quantity")) or 0
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
	for index, def in ipairs(SanctumUpgrades.List) do
		local level = tonumber(data.SanctumUpgrades[def.Id]) or 0
		level = math.clamp(math.floor(level), 0, def.MaxLevel)

		entries[index] = {
			Id = def.Id,
			Name = def.Name,
			Description = def.Description,
			Icon = def.Icon,
			Level = level,
			MaxLevel = def.MaxLevel,
			Cost = SanctumUpgrades.GetCostForNextLevel(def.Id, level),
			CurrentEffect = SanctumUpgrades.DescribeEffect(def.Id, level),
			NextEffect = level < def.MaxLevel
				and SanctumUpgrades.DescribeEffect(def.Id, level + 1)
				or nil,
		}
	end

	return {
		Balance = getBalance(player),
		Lifetime = tonumber(data.LifetimeShadowEssence) or 0,
		Upgrades = entries,
	}
end

local function pushState(player)
	local state = buildState(player)
	if state then
		SyncRemote:FireClient(player, state)
	end
end

-- Shadow Essence changes every time a Shadow orb is collected, which is
-- several times a second during normal play. Firing a full state snapshot
-- per change would mean a constant stream of remote traffic just to keep a
-- balance readout current, so routine updates mark the player dirty and a
-- single flush loop coalesces them. Purchases still push immediately,
-- because those need to feel instant.
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
					warn("SanctumService: state push failed: " .. tostring(err))
				end
			end
		end
	end
end)

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

	local def = SanctumUpgrades.GetUpgrade(upgradeId)
	if not def then
		-- Not a real upgrade id: a forged or stale request.
		return
	end

	local data = getData(player)
	if not data then
		return
	end

	-- Level is re-read from server data, never taken from the client.
	local level = tonumber(data.SanctumUpgrades[upgradeId]) or 0
	level = math.clamp(math.floor(level), 0, def.MaxLevel)

	if level >= def.MaxLevel then
		pushState(player)
		return
	end

	local cost = SanctumUpgrades.GetCostForNextLevel(upgradeId, level)
	if not cost then
		pushState(player)
		return
	end

	local stat = getShadowStat(player)
	if not stat then
		return
	end

	local balance = tonumber(stat:GetAttribute("Quantity")) or 0
	if balance < cost then
		-- Re-sync so a client showing a stale price corrects itself.
		pushState(player)
		return
	end

	-- Deduct through the leaderstat attribute, which PlayerDataHandler
	-- watches and mirrors into PlayerData. Writing both here would risk the
	-- two drifting apart.
	stat:SetAttribute("Quantity", balance - cost)

	local newLevel = level + 1
	data.SanctumUpgrades[upgradeId] = newLevel

	-- The systems this upgrade affects (EssenceOrbController,
	-- CollectionUpgrades, EssenceMultiplier) all read the attribute, and
	-- EssenceOrbController watches it for changes, so this single write is
	-- what actually applies the effect.
	player:SetAttribute(upgradeId, newLevel)

	pushState(player)
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

local function onPlayerAdded(player)
	task.spawn(function()
		local dataModule = player:WaitForChild("PlayerData", 30)
		if not dataModule or not player.Parent then
			return
		end

		-- Wait for the ACTUAL Shadow Essence leaderstat, not a fixed delay.
		-- PlayerDataHandler's initial load includes a DataStore GetAsync
		-- call (with retries on failure), which can easily take longer than
		-- a flat 1-second guess -- especially for a large save. When the
		-- leaderstat wasn't ready yet, the old code's getShadowStat()
		-- returned nil, the panel showed a balance of 0 no matter how large
		-- the real balance was, AND the live-update listener below never
		-- got attached -- so it stayed wrong for the rest of the session,
		-- not just a brief flash.
		local leaderstats = player:WaitForChild("leaderstats", 30)
		local stat = leaderstats and leaderstats:WaitForChild(SanctumUpgrades.CURRENCY, 30)

		if not stat or not player.Parent then
			warn(("SanctumService: %s never got a %q leaderstat -- Sanctum balance will not sync this session.")
				:format(player.Name, SanctumUpgrades.CURRENCY))
			return
		end

		-- Small extra beat so the client's UI script has finished building
		-- and is listening before the first state arrives.
		task.wait(0.5)
		if player.Parent then
			pushState(player)
		end

		-- Keep the panel's balance readout live as Shadow Essence is earned
		-- or spent, without the client having to poll for it.
		stat:GetAttributeChangedSignal("Quantity"):Connect(function()
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

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

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function onPlayerAdded(player)
	task.spawn(function()
		local dataModule = player:WaitForChild("PlayerData", 30)
		if not dataModule or not player.Parent then
			return
		end

		-- Let the client's UI script finish building before the first push.
		task.wait(1)
		if player.Parent then
			pushState(player)
		end

		-- Keep the panel's balance readout live as Shadow Essence is earned
		-- or spent, without the client having to poll for it.
		local stat = getShadowStat(player)
		if stat then
			stat:GetAttributeChangedSignal("Quantity"):Connect(function()
				if player.Parent then
					pushState(player)
				end
			end)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	purchaseDebounce[player] = nil
end)

for _, existing in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existing)
end

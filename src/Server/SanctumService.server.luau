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
local ServerScriptService = game:GetService("ServerScriptService")

local SanctumUpgrades = require(ReplicatedStorage:WaitForChild("SanctumUpgrades"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

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

-- Shadow Eclipse's two client-facing events (see the ECLIPSE section
-- below): CycleRemote (re)starts the client's own local countdown pill
-- display, TriggerRemote tells it to play the big screen effect right now.
-- Split into two events rather than one, so the client's purely-cosmetic
-- countdown logic can't be confused with "a real boost was just granted."
local EclipseCycleRemote = ensureRemote("RemoteEvent", "EclipseCycle")
local EclipseTriggerRemote = ensureRemote("RemoteEvent", "EclipseTrigger")

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
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Sanctum Still Loading",
			Message = "Your Shadow relics are still loading. Try again in a moment.",
			Key = "sanctum-loading",
		})
		return
	end

	-- Level is re-read from server data, never taken from the client.
	local level = tonumber(data.SanctumUpgrades[upgradeId]) or 0
	level = math.clamp(math.floor(level), 0, def.MaxLevel)

	if level >= def.MaxLevel then
		pushState(player)
		NotificationService.Send(player, {
			Kind = "Info",
			Title = "Relic Maxed",
			Message = def.Name .. " is already fully awakened.",
			Icon = "★",
			Key = "sanctum-maxed:" .. upgradeId,
		})
		return
	end

	local cost = SanctumUpgrades.GetCostForNextLevel(upgradeId, level)
	if not cost then
		pushState(player)
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Price Unavailable",
			Message = "That relic's next price could not be loaded. Try again in a moment.",
			Key = "sanctum-price:" .. upgradeId,
		})
		return
	end

	local stat = getShadowStat(player)
	if not stat then
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Shadow Essence Still Loading",
			Message = "Your Shadow Essence balance is still loading. Try again in a moment.",
			Key = "sanctum-balance-loading",
		})
		return
	end

	local balance = tonumber(stat:GetAttribute("Quantity")) or 0
	if balance < cost then
		-- Re-sync so a client showing a stale price corrects itself.
		pushState(player)
		NotificationService.Send(player, {
			Kind = "Warning",
			Title = "Not Enough Shadow Essence",
			Message = ("You need %s more Shadow Essence for %s."):format(
				ProgressionConfig.FormatNumber(cost - balance),
				def.Name
			),
			Icon = "☾",
			Key = "sanctum-currency",
		})
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
	NotificationService.Send(player, {
		Kind = "Success",
		Title = "Sanctum Relic Awakened",
		Message = ("%s reached level %d."):format(def.Name, newLevel),
		Icon = "☾",
		Duration = 2.8,
		Key = "sanctum-success:" .. upgradeId,
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
-- SHADOW ECLIPSE (Sanctum relic: sanctum_eclipse)
-- =========================================================================
-- Hammer/Laser/Rift all time themselves on the CLIENT -- safe, because
-- whatever they actually pay out (bonus orbs, a force-collect) still has
-- to go through the same server-validated remotes normal play uses. Eclipse
-- is different: it grants a real, stackable essence multiplier straight
-- through PotionTimerService. If the client owned that timer, a forged
-- "trigger now" request could spam PotionTimerService.ApplyPotion's
-- "Extend" stacking into an unbounded free boost. So this is the one relic
-- whose interval is tracked here, server-side; the client only ever gets
-- told "a cycle of N seconds just started" and "the boost is live for N
-- seconds" -- cosmetic countdown and screen effect, never a decision.

local function getPotionTimerService()
	local ok, service = pcall(function()
		local moduleScript = ServerScriptService:FindFirstChild("PotionTimerService")
		if not moduleScript then
			return nil
		end
		return require(moduleScript)
	end)
	if ok then
		return service
	end
	return nil
end

local function runEclipseLoop(player)
	-- Bounded polling rather than a bare GetAttributeChangedSignal():Wait().
	-- This thread is server-side, so unlike an equivalent client loop it is
	-- NOT torn down automatically when the player leaves -- a player who
	-- never buys this relic and then leaves would otherwise leak a
	-- coroutine parked forever on an event that will never fire again.
	-- Re-checking player.Parent every couple seconds bounds the leak to at
	-- most one more sleep cycle after they've actually gone.
	while player.Parent and (player:GetAttribute("sanctum_eclipse") or 0) <= 0 do
		task.wait(2)
	end

	while player.Parent do
		local level = player:GetAttribute("sanctum_eclipse") or 0
		local relicData = SanctumUpgrades.GetRelicLevelData("sanctum_eclipse", level)

		if not relicData then
			-- Shouldn't happen once level >= 1, but never busy-loop on a
			-- bad read.
			task.wait(5)
		else
			-- Tells the client's purely-decorative countdown pill to start
			-- a fresh cycle. Ticking in small steps (rather than one
			-- blocking wait) costs nothing here and keeps this loop
			-- responsive to the player leaving mid-cycle.
			EclipseCycleRemote:FireClient(player, relicData.Interval)

			local remaining = relicData.Interval
			while remaining > 0 and player.Parent do
				local step = math.min(2, remaining)
				task.wait(step)
				remaining -= step
			end

			if player.Parent then
				-- Re-read rather than trust the closed-over `level`: an
				-- upgrade purchased mid-wait sizes the NEXT eclipse
				-- correctly, matching how Hammer/Laser/Rift behave
				-- client-side.
				local currentLevel = player:GetAttribute("sanctum_eclipse") or 0
				local currentData = SanctumUpgrades.GetRelicLevelData("sanctum_eclipse", currentLevel)
				if currentData then
					local PotionTimerService = getPotionTimerService()
					if PotionTimerService then
						PotionTimerService.ApplyPotion(player, "EssenceX15", currentData.BoostSeconds)
					else
						warn("SanctumService: PotionTimerService unavailable, Eclipse boost not applied for " .. player.Name)
					end
					EclipseTriggerRemote:FireClient(player, currentData.BoostSeconds)
				end
			end
		end
	end
end

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

	-- Separate spawn from the state-sync one above: Eclipse's own
	-- "wait until owned" gate means this thread does nothing at all for
	-- the vast majority of players who never buy the relic, and it
	-- shouldn't be entangled with (or blocked by) the sync logic.
	task.spawn(runEclipseLoop, player)
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

--[[
    POTION TIMER SERVICE
    ====================
    A simple timed-effect ("potion") system. A player gets a boost for a
    set duration; while it's active, other scripts can check for it (via
    attributes or the API below). The remaining time survives server
    restarts and the player leaving/rejoining.

    HOW TIME PERSISTS
    ------------------
    Each active effect is stored as an EXPIRATION TIMESTAMP (os.time(),
    real-world UTC seconds) rather than "seconds remaining". That means a
    boost keeps counting down in real time even while the player is
    offline — a "24 Hour Boost" bought at 3 PM expires at 3 PM the next
    day, whether or not they were online the whole time. This matches how
    most timed boosts work (game passes, limited offers, etc).

    If you'd rather have the timer PAUSE while offline (only counts down
    during actual playtime), swap the os.time()-based math for a stored
    "secondsRemaining" value that's only decremented on a loop while the
    player is in-game, and save that instead of an expiration timestamp.

    HOW TO USE
    ----------
    1. Place this ModuleScript in ServerScriptService.
    2. Place the tiny PotionTimerBootstrap Script alongside it (also
       provided) so the system starts up even if nothing requires it yet.
    3. Add your own effects to POTION_EFFECTS below.
    4. From any server script:
           local PotionTimerService = require(game.ServerScriptService.PotionTimerService)
           PotionTimerService.ApplyPotion(player, "EssenceX2", 60 * 30) -- 30 minutes
    5. Other scripts can read the boost without touching this module at
       all, via attributes set in OnApply/OnExpire below, e.g.:
           local multiplier = player:GetAttribute("EssenceMultiplier") or 1

    HOOKING UP TO THE SHOP
    -----------------------
    In ProductPurchaseHandler's PRODUCT_HANDLERS, a boost product would call:
           local PotionTimerService = require(game.ServerScriptService.PotionTimerService)
           [567890123] = function(player) -- 2x Essence Boost (24h)
               PotionTimerService.ApplyPotion(player, "EssenceX2", 24 * 60 * 60)
               return true
           end,
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionTimerService = {}

-------------------------------------------------------------------
-- 1) REGISTER YOUR POTION EFFECTS HERE
-------------------------------------------------------------------
-- OnApply runs once when the effect first turns on (not on every extend).
-- OnExpire runs once when it finally runs out. Keep these reversible —
-- whatever OnApply changes, OnExpire should undo.
local POTION_EFFECTS = {
	["EssenceX15"] = {
		DisplayName = "1.5x Essence Boost",
		OnApply = function(player)
			player:SetAttribute("EssenceMultiplier", 1.5)
		end,
		OnExpire = function(player)
			player:SetAttribute("EssenceMultiplier", 1)
		end,
	},
}

-------------------------------------------------------------------
-- INTERNAL STATE
-------------------------------------------------------------------
local potionDataStore = DataStoreService:GetDataStore("PotionTimerStore")

local activeEffects = {}     -- [player] = { [effectName] = expirationTimestamp }
local expirationTasks = {}   -- [player] = { [effectName] = thread }

-------------------------------------------------------------------
-- REMOTES (for UI to show live countdowns)
-------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:FindFirstChild("PotionRemotes")

local potionUpdated = remotesFolder:FindFirstChild("PotionUpdated")
if not potionUpdated then
	potionUpdated = Instance.new("RemoteEvent")
	potionUpdated.Name = "PotionUpdated"
	potionUpdated.Parent = remotesFolder
end

-- Client calls this once on join to reliably sync current state
-- (avoids a race condition with PotionUpdated firing before the
-- client's listener is connected).
local getActivePotions = remotesFolder:FindFirstChild("GetActivePotions")

local function fireUpdate(player, effectName, remaining, active)
	potionUpdated:FireClient(player, effectName, remaining, active)
end

-------------------------------------------------------------------
-- SAVE / LOAD
-------------------------------------------------------------------
local function savePlayerEffects(player)
	local playerEffects = activeEffects[player]
	if not playerEffects then
		return
	end
	pcall(function()
		potionDataStore:SetAsync("PotionData_" .. player.UserId, playerEffects)
	end)
end

-------------------------------------------------------------------
-- CORE LOGIC
-------------------------------------------------------------------
local function expireEffect(player, effectName)
	local playerEffects = activeEffects[player]
	if not playerEffects or not playerEffects[effectName] then
		return
	end

	playerEffects[effectName] = nil

	local config = POTION_EFFECTS[effectName]
	if config and config.OnExpire then
		pcall(config.OnExpire, player)
	end

	fireUpdate(player, effectName, 0, false)
	savePlayerEffects(player)
end

local function scheduleExpiration(player, effectName, expiration)
	expirationTasks[player] = expirationTasks[player] or {}

	local existing = expirationTasks[player][effectName]
	if existing then
		task.cancel(existing)
	end

	expirationTasks[player][effectName] = task.spawn(function()
		local remaining = expiration - os.time()
		if remaining > 0 then
			task.wait(remaining)
		end
		expireEffect(player, effectName)
	end)
end

-- Applies (or extends) a potion effect.
-- stackMode: "Extend" (default, adds duration onto remaining time) or
--            "Refresh" (resets to exactly `duration` from now).
function PotionTimerService.ApplyPotion(player, effectName, duration, stackMode)
	local config = POTION_EFFECTS[effectName]
	if not config then
		warn(("PotionTimerService: no effect registered called '%s'"):format(tostring(effectName)))
		return
	end

	if not activeEffects[player] then
		-- player data hasn't loaded yet (or they've already left) — bail safely
		warn(("PotionTimerService: %s has no loaded potion data yet"):format(player.Name))
		return
	end

	stackMode = stackMode or "Extend"
	local now = os.time()
	local playerEffects = activeEffects[player]
	local currentExpiration = playerEffects[effectName]
	local wasActive = currentExpiration ~= nil and currentExpiration > now

	local newExpiration
	if stackMode == "Extend" then
		newExpiration = (wasActive and currentExpiration or now) + duration
	else
		newExpiration = now + duration
	end

	playerEffects[effectName] = newExpiration

	if not wasActive and config.OnApply then
		pcall(config.OnApply, player)
	end

	scheduleExpiration(player, effectName, newExpiration)
	fireUpdate(player, effectName, newExpiration - now, true)
	savePlayerEffects(player)
end

-- Seconds remaining on an effect (0 if not active).
function PotionTimerService.GetRemainingTime(player, effectName)
	local playerEffects = activeEffects[player]
	if not playerEffects then
		return 0
	end
	local expiration = playerEffects[effectName]
	if not expiration then
		return 0
	end
	return math.max(0, expiration - os.time())
end

function PotionTimerService.IsActive(player, effectName)
	return PotionTimerService.GetRemainingTime(player, effectName) > 0
end

-- Instantly clears an effect early (e.g. an admin command or a "cleanse" item).
function PotionTimerService.ClearPotion(player, effectName)
	if expirationTasks[player] and expirationTasks[player][effectName] then
		task.cancel(expirationTasks[player][effectName])
		expirationTasks[player][effectName] = nil
	end
	expireEffect(player, effectName)
end

-------------------------------------------------------------------
-- PLAYER JOIN / LEAVE
-------------------------------------------------------------------
local function onPlayerAdded(player)
	activeEffects[player] = {}
	expirationTasks[player] = {}

	local savedData
	local ok = pcall(function()
		savedData = potionDataStore:GetAsync("PotionData_" .. player.UserId)
	end)

	if ok and savedData then
		local now = os.time()
		for effectName, expiration in pairs(savedData) do
			local config = POTION_EFFECTS[effectName]
			if config and type(expiration) == "number" and expiration > now then
				activeEffects[player][effectName] = expiration

				if config.OnApply then
					pcall(config.OnApply, player)
				end

				scheduleExpiration(player, effectName, expiration)
				fireUpdate(player, effectName, expiration - now, true)
			end
			-- effects that expired while offline are simply dropped —
			-- OnApply was never called this session, so there's nothing to undo
		end
	end
end

local function onPlayerRemoving(player)
	savePlayerEffects(player)

	if expirationTasks[player] then
		for _, thread in pairs(expirationTasks[player]) do
			task.cancel(thread)
		end
	end

	activeEffects[player] = nil
	expirationTasks[player] = nil
end

getActivePotions.OnServerInvoke = function(player)
	local playerEffects = activeEffects[player]
	if not playerEffects then
		return {}
	end

	local now = os.time()
	local snapshot = {}
	for effectName, expiration in pairs(playerEffects) do
		local remaining = expiration - now
		if remaining > 0 then
			snapshot[effectName] = remaining
		end
	end
	return snapshot
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- catch anyone already in-game when this module first loads (e.g. a Studio script reload)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerEffects(player)
	end
end)

return PotionTimerService
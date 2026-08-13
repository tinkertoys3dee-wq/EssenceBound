--[[
	EssenceRushService (Script -> ServerScriptService)
	===================================================
	A server-wide timed event: periodically, EVERY online player gets a
	temporary essence boost at the same time, with an arrival announcement
	and a live countdown banner (see EssenceRushBanner.client.luau) -- a
	reason to be online at a given moment, not just whenever's convenient.
	The first "whole server" event in the game, distinct from the
	personal, individually-timed boosts already here (Second Wind, daily
	rewards, Shadow Eclipse).

	Reuses the SAME "EssenceX15" PotionTimerService effect every other
	temporary essence boost in the game already uses. That's a deliberate,
	previously-established decision (see Shadow Eclipse / Second Wind):
	two DIFFERENTLY-named effects both writing the shared EssenceMultiplier
	attribute could have one's OnExpire wipe the other's still-active
	boost, so anything that grants a temporary essence multiplier reuses
	this one name -- a same-name reapplication safely EXTENDS the shared
	timer instead of clobbering it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- =========================================================================
-- CONFIG
-- =========================================================================

local MIN_INTERVAL = 20 * 60 -- 20 minutes
local MAX_INTERVAL = 35 * 60 -- 35 minutes
local RUSH_DURATION = 4 * 60 -- 4 minutes
local POTION_EFFECT = "EssenceX15"

-- =========================================================================
-- REMOTES
-- =========================================================================

local remotesFolder = ReplicatedStorage:FindFirstChild("EssenceRushRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "EssenceRushRemotes"
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

local RushRemote = ensureRemote("RemoteEvent", "EssenceRushEvent")

-- =========================================================================
-- STATE
-- =========================================================================

local rushActive = false
local rushEndsAt = 0

-- Same defensive lookup used by OrbClickManager/SanctumService for the
-- exact same effect: a missing PotionTimerService must cost only the
-- boost itself, never anything else in the game.
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

local function applyToPlayer(player, duration)
	local PotionTimerService = getPotionTimerService()
	if PotionTimerService then
		-- PotionTimerService.ApplyPotion no-ops (with a warn) for a player
		-- whose potion data hasn't loaded yet -- safe to call unconditionally.
		PotionTimerService.ApplyPotion(player, POTION_EFFECT, duration)
	end
end

local function startRush()
	rushActive = true
	rushEndsAt = os.time() + RUSH_DURATION

	for _, plr in ipairs(Players:GetPlayers()) do
		applyToPlayer(plr, RUSH_DURATION)
		RushRemote:FireClient(plr, "Start", { Duration = RUSH_DURATION })
	end

	task.delay(RUSH_DURATION, function()
		rushActive = false
		for _, plr in ipairs(Players:GetPlayers()) do
			RushRemote:FireClient(plr, "End")
		end
	end)
end

-- =========================================================================
-- LOOP
-- =========================================================================

task.spawn(function()
	while true do
		local waitTime = math.random(MIN_INTERVAL, MAX_INTERVAL)
		task.wait(waitTime)
		startRush()
	end
end)

-- A player who joins mid-Rush still gets whatever time is left, rather
-- than missing out entirely just for bad timing.
Players.PlayerAdded:Connect(function(plr)
	task.delay(8, function()
		if plr.Parent and rushActive then
			local remaining = math.max(0, rushEndsAt - os.time())
			if remaining > 0 then
				applyToPlayer(plr, remaining)
				RushRemote:FireClient(plr, "Start", { Duration = remaining })
			end
		end
	end)
end)

--[[
	StormController ModuleScript
	-----------------------------
	Server-authoritative essence storm handling for EssenceBound.

	Mirrors state onto player Attributes so LocalScripts can react to it
	without needing to require this module client-side - this matches the
	same pattern OrbController uses for OrbCurrentHP / OrbMaxHP / etc, and
	for the same reason: Init/Start only ever runs in the server's Lua VM,
	so a client-side require would just see an empty module. Attributes are
	the bridge.

	Attributes mirrored per player:
		StormCooldownRemaining        (number) seconds until the next AUTOMATIC storm
		StormActive                   (bool)
		StormTimeRemaining            (number) seconds left in the active storm
		StormIsGolden                 (bool)   true if the active storm is golden
		ManualStormUnlocked           (bool)   true once the player owns manual_storm_summon
		ManualStormCooldownRemaining  (number) seconds until manual summon is available again

	Events fired to the client via the RemoteEvent you pass into .new()
	(e.g. ReplicatedStorage.Remotes.EssenceStorm):
		("StormStart", {Duration = number, IsGolden = bool, SpawnInterval = number})
		("StormEnd")

	NOT handled here (by design, keep this server-authoritative-but-narrow):
		- Applying the golden-storm reward multiplier to collected essence.
		  Do that where you actually credit currency for a collected orb
		  (wherever your Collect/Return remote handler lives), by checking
		  player:GetAttribute("StormIsGolden") at the moment of collection.
		- The manual-summon RemoteEvent's OnServerEvent connection - wire
		  that up in your init script and call
		  StormController.Get(player):TryManualSummon().

	Requires the EssenceUpgrades module - adjust the require path below to
	wherever you keep it (this assumes it's a sibling of this module).
]]

local StormController = {}
StormController.__index = StormController

local RP = game:GetService("ReplicatedStorage")
local EssenceUpgrades = require(RP:WaitForChild("TreeUpgrades"))

-- =========================================================================
-- TUNING
-- =========================================================================

local BASE_COOLDOWN = 300         -- seconds between automatic storms at 0 upgrades
local MIN_COOLDOWN = 30           -- floor so StormCooldownReduction can't stack to 0/negative
local BASE_DURATION = 60          -- seconds an automatic storm lasts at 0 upgrades
local BASE_SPAWN_INTERVAL = 0.4   -- seconds between orb spawns at 0 StormIntensity

local MANUAL_STORM_COOLDOWN = 180 -- separate cooldown for the manual-summon button
local MANUAL_STORM_DURATION = 30  -- manual storms are shorter than automatic ones by default

local TICK_RATE = 1 -- seconds between countdown ticks

-- =========================================================================
-- INTERNAL: per-player registry, so StormController.Get(player) works
-- from wherever your ManualStormSummon RemoteEvent handler lives
-- =========================================================================

local ActiveControllers = {}

-- =========================================================================
-- EFFECT LOOKUPS
-- All pulled straight from EssenceUpgrades.GetSummedEffect/GetCurrentLevel,
-- so new storm upgrades added later just work as long as they reuse these
-- EffectType strings - no changes needed here.
-- =========================================================================

local function getCooldownSeconds(playerData)
	local reduction = EssenceUpgrades.GetSummedEffect(playerData, "StormCooldownReduction")
	return math.max(BASE_COOLDOWN - reduction, MIN_COOLDOWN)
end

local function getDurationSeconds(playerData)
	local bonus = EssenceUpgrades.GetSummedEffect(playerData, "StormDuration")
	return BASE_DURATION + bonus
end

local function getSpawnInterval(playerData)
	-- StormIntensity is stored as "+X% orb density" - higher intensity means
	-- a SHORTER interval between spawns (more orbs per second), not a longer one.
	local intensity = EssenceUpgrades.GetSummedEffect(playerData, "StormIntensity")
	local density = 1 + intensity
	return BASE_SPAWN_INTERVAL / density
end

local function getGoldenChance(playerData)
	return EssenceUpgrades.GetSummedEffect(playerData, "GoldenStormChance")
end

local function hasManualSummon(playerData)
	return EssenceUpgrades.GetCurrentLevel(playerData, "manual_storm_summon") >= 1
end

local function getAutoStormChancePerMinute(playerData)
	return EssenceUpgrades.GetSummedEffect(playerData, "AutoStormChancePerMinute")
end

-- =========================================================================
-- CONSTRUCTOR
-- =========================================================================

-- playerDataProvider: function(player) -> playerData table (however you
-- fetch/store it - ProfileService, a DataStore wrapper, etc). Called fresh
-- every tick so an upgrade purchased mid-cooldown is picked up immediately.
function StormController.new(player, playerDataProvider, remoteEvent)
	local self = setmetatable({}, StormController)

	self.Player = player
	self.GetPlayerData = playerDataProvider
	self.RemoteEvent = remoteEvent

	self.CooldownRemaining = BASE_COOLDOWN
	self.ManualCooldownRemaining = 0
	self.Active = false
	self.TimeRemaining = 0
	self.IsGolden = false
	self._running = false

	ActiveControllers[player] = self

	self:_mirrorAttributes()

	return self
end

function StormController.Get(player)
	return ActiveControllers[player]
end

function StormController:_mirrorAttributes()
	local p = self.Player
	p:SetAttribute("StormCooldownRemaining", self.CooldownRemaining)
	p:SetAttribute("StormActive", self.Active)
	p:SetAttribute("StormTimeRemaining", self.TimeRemaining)
	p:SetAttribute("StormIsGolden", self.IsGolden)
	p:SetAttribute("ManualStormUnlocked", hasManualSummon(self.GetPlayerData(p)))
	p:SetAttribute("ManualStormCooldownRemaining", self.ManualCooldownRemaining)
end

-- =========================================================================
-- STORM LIFECYCLE
-- =========================================================================

function StormController:_startStorm(isManual)
	local playerData = self.GetPlayerData(self.Player)
	local duration = isManual and MANUAL_STORM_DURATION or getDurationSeconds(playerData)
	local spawnInterval = getSpawnInterval(playerData)
	-- Manual summons don't roll golden - that stays a reward tied to the
	-- automatic storm cadence upgrades (storm_mastery). Change this if you
	-- want manual storms golden-eligible too.
	local isGolden = (not isManual) and (math.random() < getGoldenChance(playerData)) or false

	self.Active = true
	self.TimeRemaining = duration
	self.IsGolden = isGolden

	self:_mirrorAttributes()

	if self.RemoteEvent then
		self.RemoteEvent:FireClient(self.Player, "StormStart", {
			Duration = duration,
			IsGolden = isGolden,
			SpawnInterval = spawnInterval,
		})
	end
end

function StormController:_endStorm()
	self.Active = false
	self.TimeRemaining = 0
	self.IsGolden = false

	self:_mirrorAttributes()

	if self.RemoteEvent then
		self.RemoteEvent:FireClient(self.Player, "StormEnd")
	end
end

-- Call from your ManualStormSummon RemoteEvent's OnServerEvent handler.
-- Returns success (bool), reason (string, nil on success).
-- Reasons: "NotUnlocked" | "StormAlreadyActive" | "OnCooldown"
local BS = game:GetService("BadgeService")
function StormController:TryManualSummon()
	local playerData = self.GetPlayerData(self.Player)

	if not hasManualSummon(playerData) then
		return false, "NotUnlocked"
	end
	if self.Active then
		return false, "StormAlreadyActive"
	end
	if self.ManualCooldownRemaining > 0 then
		return false, "OnCooldown"
	end

	self.ManualCooldownRemaining = MANUAL_STORM_COOLDOWN
	
	if not self.Player:GetAttribute("4281764202448916")  then
		self.Player:SetAttribute("4281764202448916", true)
		playerData.Badges[4281764202448916] = true
		BS:AwardBadgeAsync(self.Player.UserId,4281764202448916)
	end
	
	if not self.Player:GetAttribute("2767213148031403") and playerData.ManualStormsSummoned >= 35 then
		self.Player:SetAttribute("2767213148031403",true)
		playerData.Badges[2767213148031403] = true
		BS:AwardBadgeAsync(self.Player.UserId,2767213148031403)
	end
	
	playerData.ManualStormsSummoned += 1
	self:_startStorm(true)
	return true
end

-- Unconditionally starts a storm the player has PAID for (the Essence
-- Rain developer product).
--
-- Deliberately skips every check TryManualSummon applies: those gate a
-- FREE ability behind an upgrade unlock and a cooldown, and a purchase
-- must never be silently swallowed by them. Buying rain always rains.
--
-- Returns: success (bool), reason (string, nil on success)
function StormController:ForceStorm()
	-- Buying while it's already raining tops the timer back up rather than
	-- restarting it (or being discarded outright), so the purchase can't
	-- be wasted by unlucky timing.
	if self.Active then
		self.TimeRemaining = math.max(self.TimeRemaining, MANUAL_STORM_DURATION)
		self:_mirrorAttributes()

		if self.RemoteEvent then
			self.RemoteEvent:FireClient(self.Player, "StormStart", {
				Duration = self.TimeRemaining,
				IsGolden = self.IsGolden,
				SpawnInterval = getSpawnInterval(self.GetPlayerData(self.Player)),
			})
		end

		return true
	end

	self:_startStorm(true)
	return true
end

-- Module-level entry point: looks the controller up and calls ForceStorm
-- with the correct `self`.
--
-- This exists because the alternative -- every caller doing its own
-- StormController.Get(player) and then reaching for an internal method --
-- is exactly how the wrong `self` gets passed (a dot call, or calling on
-- the module itself). Every field then resolves to nil and it surfaces as
-- a bare "attempt to call a nil value" from deep inside this module, far
-- from the code that actually got it wrong.
--
-- Returns: success (bool), reason (string, nil on success)
-- Reasons: "NoPlayer" | "NoController"
function StormController.ForceStormFor(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "NoPlayer"
	end

	local controller = ActiveControllers[player]
	if not controller then
		-- Player left, or joined before this system started running. The
		-- caller decides whether that's worth retrying.
		return false, "NoController"
	end

	return controller:ForceStorm()
end

-- =========================================================================
-- MAIN LOOP
-- =========================================================================

function StormController:Start()
	if self._running then return end
	self._running = true

	task.spawn(function()
		while self._running and self.Player.Parent do
			task.wait(TICK_RATE)
			if not self._running then break end

			local playerData = self.GetPlayerData(self.Player)

			if self.Active then
				self.TimeRemaining = math.max(self.TimeRemaining - TICK_RATE, 0)
				if self.TimeRemaining <= 0 then
					self:_endStorm()
					self.CooldownRemaining = getCooldownSeconds(playerData)
				end
			else
				-- storm_caller_ascension: a per-tick chance to auto-trigger a
				-- storm entirely outside the main cooldown.
				local autoChancePerMinute = getAutoStormChancePerMinute(playerData)
				if autoChancePerMinute > 0 then
					local chanceThisTick = autoChancePerMinute * (TICK_RATE / 60)
					if math.random() < chanceThisTick then
						self:_startStorm(false)
					end
				end

				if not self.Active then
					self.CooldownRemaining = math.max(self.CooldownRemaining - TICK_RATE, 0)
					if self.CooldownRemaining <= 0 then
						
						if not self.Player:GetAttribute("3091905792121753") then
							self.Player:SetAttribute("3091905792121753",true)
							playerData.Badges[3091905792121753] = true
							BS:AwardBadgeAsync(self.Player.UserId,3091905792121753)
						end
						
						self:_startStorm(false)
					end
				end
			end

			if self.ManualCooldownRemaining > 0 then
				self.ManualCooldownRemaining = math.max(self.ManualCooldownRemaining - TICK_RATE, 0)
			end

			self:_mirrorAttributes()
			
		end
	end)
end

function StormController:Stop()
	self._running = false
	ActiveControllers[self.Player] = nil
end

return StormController
--[[
	EssenceOrbController.lua  (ModuleScript)
	------------------------------------------
	Owns the runtime state and math for a player's main Essence Orb: its
	max HP, current HP, regen rate, and per-shot HP cost.

	This module ONLY concerns itself with upgrades that change the orb's
	own durability/behavior. Upgrades that just grant more essence per
	click live in your click/reward code instead and are intentionally
	left out of here.

	UPGRADES THIS MODULE READS
	----------------------------
		orb_vitality_1 / orb_vitality_2 / orb_vitality_3
			EffectType = "OrbMaxHP"              -> raises MaxHP

		orb_regen_1 / orb_regen_2
			EffectType = "OrbRegenRate"           -> HP regenerated per second

		fracture_efficiency
			EffectType = "ShotHPCostReduction"    -> cheaper HP cost per shot

		core_resilience
			EffectType = "NeverFullyDepleted"     -> free "trickle" shot at 0 HP
			                                          (rate-limited by
			                                          TRICKLE_SHOT_COOLDOWN below)

	DELIBERATELY NOT HANDLED HERE
	-------------------------------
	shatter_force_1, shatter_force_2, overload_shots, and
	twin_orb_manifestation all increase essence gained per click rather
	than changing the orb's own health/behavior, so they're left for
	whatever module handles click rewards.
	(twin_orb_manifestation is a judgment call -- its description leans on
	"doubling click yield sources," but it does also spawn a literal
	second orb. If you'd rather it be treated as an orb-system upgrade,
	pull it in and give it its own handling; it isn't included by default.)

	PLAYER DATA
	------------
	Upgrade levels are read live from player:GetAttribute(upgradeId) -- 
	there's no separate playerData table here. Whatever sets those
	attributes (your purchase code, using EssenceUpgrades.PurchaseUpgrade)
	should keep them in sync; this module just reacts to them.

	This module is server-authoritative: HP is spent/regenerated here and
	mirrored onto attributes (OrbCurrentHP, OrbMaxHP, OrbRegenRate,
	OrbShotHPCost) purely so client UI can read them. Require and drive
	this from the server; the client can require it too, but should only
	ever call GetState/CanFire for display purposes, never Fire/Init/
	RecalculateStats/Heal/Cleanup.

	USAGE
	------
		local OrbController = require(path.to.EssenceOrbController)

		Players.PlayerAdded:Connect(function(player)
			-- once your upgrade-level attributes are loaded/set:
			OrbController.Init(player)
		end)

		-- after EssenceUpgrades.PurchaseUpgrade succeeds for an orb upgrade,
		-- and after you've updated the player's attribute for that upgrade,
		-- stats recalculate automatically (Init hooks attribute-changed
		-- signals for you) -- but you can also force it manually:
		OrbController.RecalculateStats(player)

		-- firing a shot (e.g. on click):
		local canFire, isTrickle = OrbController.CanFire(player)
		if canFire then
			local success, hpCostPaid, wasTrickle = OrbController.Fire(player)
			-- wasTrickle shots cost 0 HP and are on their own cooldown --
			-- treat them as a much weaker/slower shot in your combat code.
		end

		-- granting a bonus heal outside of passive regen (e.g. a reward for
		-- an orb completing its return-home animation, a consumable, etc.):
		OrbController.Heal(player, 5)

		-- regen ticks automatically in the background (see Heartbeat loop
		-- near the bottom of this file) -- no manual Update call needed.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local EssenceUpgrades = require(script.Parent:WaitForChild("TreeUpgrades"))
-- Timed lookup rather than a bare WaitForChild: a missing SanctumUpgrades
-- must cost the Sanctum bonus only, not hang the module that owns every
-- player's orb energy.
local SanctumUpgrades
do
	local module = script.Parent:FindFirstChild("SanctumUpgrades")
		or script.Parent:WaitForChild("SanctumUpgrades", 10)

	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			SanctumUpgrades = result
		end
	end
end

-- Returns 0 when the module is unavailable, so callers stay arithmetic-safe.
local function sanctumEffect(player, id)
	if not SanctumUpgrades then
		return 0
	end
	return tonumber(SanctumUpgrades.GetPlayerEffect(player, id)) or 0
end

local EssenceOrbController = {}

-- =========================================================================
-- ORB-RELEVANT UPGRADES
-- =========================================================================

local MAX_HP_UPGRADE_IDS = { "orb_vitality_1", "orb_vitality_2", "orb_vitality_3" }
local REGEN_UPGRADE_IDS = { "orb_regen_1", "orb_regen_2" }
local SHOT_COST_UPGRADE_ID = "fracture_efficiency"
local NEVER_DEPLETED_UPGRADE_ID = "core_resilience"

-- =========================================================================
-- BASE ORB STATS (level-0 values, before any upgrades) -- tune to taste
-- =========================================================================

-- Raised from 100/2 (was ~12 clicks then 1 click per 4s forever, with zero
-- in-game explanation of why -- new players were hitting a hard, unexplained
-- wall about 15-20 seconds into their first session). Still a real resource
-- players will want orb_vitality/orb_regen upgrades to grow, just a more
-- forgiving starting point while they're learning the game and not yet
-- invested. Paired with an in-tutorial explanation of the mechanic.
local BASE_MAX_HP = 150
local BASE_REGEN_RATE = 3.5 -- HP regenerated per second
local BASE_SHOT_HP_COST = 8 -- HP spent per normal shot
local MIN_SHOT_HP_COST = 1 -- fracture_efficiency can never reduce a shot below this
local TRICKLE_SHOT_COOLDOWN = 1.2 -- seconds between free "trickle" shots while depleted

-- =========================================================================
-- PER-PLAYER STATE
-- =========================================================================

-- [player] = {
--     CurrentHP, MaxHP, RegenRate, ShotHPCost, NeverFullyDepleted,
--     TrickleCooldownRemaining, Connections,
-- }
local orbStates = {}

local function getLevel(player, upgradeId)
	return player:GetAttribute(upgradeId) or 0
end

-- Sums EffectPerLevel * level across a list of upgrade ids, reusing
-- EssenceUpgrades' own per-upgrade math so the numbers never drift out of
-- sync with the upgrade definitions.
local function sumEffect(player, upgradeIds)
	local total = 0
	for _, id in ipairs(upgradeIds) do
		total += EssenceUpgrades.GetUpgradeEffectValue(id, getLevel(player, id))
	end
	return total
end

-- =========================================================================
-- STAT CALCULATION
-- =========================================================================

-- Recomputes MaxHP/RegenRate/ShotHPCost/NeverFullyDepleted from the
-- player's current upgrade-level attributes, clamps CurrentHP into the new
-- MaxHP, and mirrors everything onto attributes for UI binding. Call this
-- once on join (Init does it for you) -- after that it's wired to fire
-- automatically whenever a relevant upgrade attribute changes, so you only
-- need to call it manually if you're doing something unusual (e.g.
-- resetting a player's upgrades without changing attributes one at a time).
function EssenceOrbController.RecalculateStats(player)
	local state = orbStates[player]
	if not state then
		return
	end

	-- Shadow Sanctum upgrades stack additively on top of the Earth Essence
	-- tree rather than replacing it, so the two economies complement each
	-- other instead of one making the other pointless.
	-- Always numbers, even if the Sanctum module is missing, so a bad value
	-- can never turn MaxHP/RegenRate into a non-number and break regen.
	local sanctumMaxHP = sanctumEffect(player, "sanctum_deep_well")
	local sanctumRegen = sanctumEffect(player, "sanctum_swift_shadows")

	local maxHP = BASE_MAX_HP + sumEffect(player, MAX_HP_UPGRADE_IDS) + sanctumMaxHP
	local regenRate = BASE_REGEN_RATE + sumEffect(player, REGEN_UPGRADE_IDS) + sanctumRegen

	-- Sanctum's Umbral Fracture stacks additively with fracture_efficiency,
	-- then the combined total is clamped to 0..0.9 before being applied.
	-- Without that clamp, enough combined levels could drive the reduction
	-- past 1.0 and make BASE_SHOT_HP_COST * (1 - reduction) go NEGATIVE --
	-- a click that REFUNDS energy and makes the orb infinitely clickable.
	-- MIN_SHOT_HP_COST alone wouldn't catch that, since math.max would
	-- happily return the floor while the real intent was broken.
	local shotCostReduction = sumEffect(player, { SHOT_COST_UPGRADE_ID })
		+ sanctumEffect(player, "sanctum_fracture")
	shotCostReduction = math.clamp(shotCostReduction, 0, 0.9)

	local shotHPCost = math.max(MIN_SHOT_HP_COST, BASE_SHOT_HP_COST * (1 - shotCostReduction))

	local neverFullyDepleted = getLevel(player, NEVER_DEPLETED_UPGRADE_ID) >= 1

	state.MaxHP = maxHP
	state.RegenRate = regenRate
	state.ShotHPCost = shotHPCost
	state.NeverFullyDepleted = neverFullyDepleted
	state.CurrentHP = math.clamp(state.CurrentHP, 0, maxHP)

	player:SetAttribute("OrbMaxHP", maxHP)
	player:SetAttribute("OrbRegenRate", regenRate)
	player:SetAttribute("OrbShotHPCost", shotHPCost)
	player:SetAttribute("OrbCurrentHP", state.CurrentHP)
end

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

-- Sets up orb state for `player` and hooks attribute-changed signals on
-- every orb-relevant upgrade id, so purchasing one of them automatically
-- recalculates stats -- no need to manually call RecalculateStats after
-- every purchase. Safe to call more than once (no-ops if already inited).
function EssenceOrbController.Init(player)
	if orbStates[player] then
		return
	end

	orbStates[player] = {
		CurrentHP = BASE_MAX_HP,
		MaxHP = BASE_MAX_HP,
		RegenRate = BASE_REGEN_RATE,
		ShotHPCost = BASE_SHOT_HP_COST,
		NeverFullyDepleted = false,
		TrickleCooldownRemaining = 0,
		Connections = {},
	}

	EssenceOrbController.RecalculateStats(player)

	local watchedIds = {}
	for _, id in ipairs(MAX_HP_UPGRADE_IDS) do
		table.insert(watchedIds, id)
	end
	for _, id in ipairs(REGEN_UPGRADE_IDS) do
		table.insert(watchedIds, id)
	end
	table.insert(watchedIds, SHOT_COST_UPGRADE_ID)
	table.insert(watchedIds, NEVER_DEPLETED_UPGRADE_ID)
	-- Sanctum upgrades that change orb stats, so buying one takes effect
	-- immediately instead of waiting for some other recalculation.
	table.insert(watchedIds, "sanctum_deep_well")
	table.insert(watchedIds, "sanctum_swift_shadows")
	table.insert(watchedIds, "sanctum_fracture")

	local state = orbStates[player]
	for _, id in ipairs(watchedIds) do
		local conn = player:GetAttributeChangedSignal(id):Connect(function()
			EssenceOrbController.RecalculateStats(player)
		end)
		table.insert(state.Connections, conn)
	end
end

-- Tears down orb state + connections for `player`. Also auto-wired to
-- Players.PlayerRemoving below as a backstop, so calling this explicitly
-- is optional but fine (e.g. if you want to free memory earlier).
function EssenceOrbController.Cleanup(player)
	local state = orbStates[player]
	if not state then
		return
	end

	for _, conn in ipairs(state.Connections) do
		conn:Disconnect()
	end

	orbStates[player] = nil
end

Players.PlayerRemoving:Connect(EssenceOrbController.Cleanup)

-- =========================================================================
-- READING STATE
-- =========================================================================

-- Returns a snapshot table {CurrentHP, MaxHP, RegenRate, ShotHPCost,
-- NeverFullyDepleted}, or nil if Init hasn't been called for this player.
function EssenceOrbController.GetState(player)
	local state = orbStates[player]
	if not state then
		return nil
	end

	return {
		CurrentHP = state.CurrentHP,
		MaxHP = state.MaxHP,
		RegenRate = state.RegenRate,
		ShotHPCost = state.ShotHPCost,
		NeverFullyDepleted = state.NeverFullyDepleted,
	}
end

-- =========================================================================
-- FIRING
-- =========================================================================

-- Returns: canFire (bool), isTrickle (bool)
-- isTrickle = true means firing right now would consume no HP -- it's the
-- free, rate-limited "core_resilience" shot available once the orb is
-- fully depleted, not a normal shot.
function EssenceOrbController.CanFire(player)
	local state = orbStates[player]
	if not state then
		return false, false
	end

	if state.CurrentHP >= state.ShotHPCost then
		return true, false
	end

	if state.NeverFullyDepleted and state.TrickleCooldownRemaining <= 0 then
		return true, true
	end

	return false, false
end

-- Attempts to fire a shot. Deducts ShotHPCost from CurrentHP on a normal
-- shot, or -- if the orb is depleted and core_resilience is owned --
-- fires a free trickle shot and starts its cooldown instead.
-- Returns: success (bool), hpCostPaid (number), isTrickle (bool)
function EssenceOrbController.Fire(player)
	local state = orbStates[player]
	if not state then
		return false, 0, false
	end

	local canFire, isTrickle = EssenceOrbController.CanFire(player)
	if not canFire then
		return false, 0, false
	end

	if isTrickle then
		state.TrickleCooldownRemaining = TRICKLE_SHOT_COOLDOWN
		return true, 0, true
	end

	state.CurrentHP = math.max(0, state.CurrentHP - state.ShotHPCost)
	player:SetAttribute("OrbCurrentHP", state.CurrentHP)
	return true, state.ShotHPCost, false
end

-- =========================================================================
-- HEALING
-- =========================================================================

-- Restores `amount` HP outside of passive regen -- e.g. a reward for an
-- orb's return-home animation completing, a consumable, an ability, etc.
-- Clamped into [0, MaxHP] the same way RecalculateStats clamps CurrentHP.
-- No-ops (returns false, 0) if Init hasn't been called for this player, or
-- if amount isn't a positive number.
-- Returns: success (bool), actualAmountHealed (number) -- the second value
-- accounts for overheal getting clipped at MaxHP, e.g. healing 10 while
-- only 4 HP below MaxHP returns actualAmountHealed = 4.
function EssenceOrbController.Heal(player, amount)
	local state = orbStates[player]
	if not state then
		return false, 0
	end

	if type(amount) ~= "number" or amount <= 0 then
		return false, 0
	end

	local previousHP = state.CurrentHP
	state.CurrentHP = math.clamp(state.CurrentHP + amount, 0, state.MaxHP)
	player:SetAttribute("OrbCurrentHP", state.CurrentHP)

	return true, state.CurrentHP - previousHP
end

-- =========================================================================
-- REGEN LOOP
-- =========================================================================
-- Regenerates HP and ticks down the trickle cooldown for every inited
-- player automatically -- no manual Update() call needed. Attribute
-- writes are throttled to actual changes (skipped once a player is
-- already at full HP) to avoid needless replication traffic.

RunService.Heartbeat:Connect(function(dt)
	for player, state in pairs(orbStates) do
		if state.CurrentHP < state.MaxHP then
			state.CurrentHP = math.min(state.MaxHP, state.CurrentHP + state.RegenRate * dt)
			player:SetAttribute("OrbCurrentHP", state.CurrentHP)
		end

		if state.TrickleCooldownRemaining > 0 then
			state.TrickleCooldownRemaining = math.max(0, state.TrickleCooldownRemaining - dt)
		end
	end
end)

return EssenceOrbController
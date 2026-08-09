local RP = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Events = RP:WaitForChild("Remotes")
local OrbClick = Events:WaitForChild("ClickOrb")
local collected = Events:WaitForChild("Collection")
local PlayerDatas = {}

-- TODO: point this at wherever EssenceOrbController actually lives in your
-- tree (it requires "EssenceUpgrades" as a sibling via script.Parent, so
-- it's presumably sitting in a shared Modules folder somewhere).
local OrbController = require(RP:WaitForChild("EssenceOrbController"))

-- Timed lookup with a graceful fallback, same contract as every other
-- defensive RebirthShopUpgrades require in this codebase: Momentum/Second
-- Wind/Shard Rain are all bonuses on top of the click/collection flow, and
-- a missing module must cost only those bonuses, never the flow itself
-- (every essence reward in the game passes through this script).
local RebirthShopUpgrades
do
	local module = RP:FindFirstChild("RebirthShopUpgrades") or RP:WaitForChild("RebirthShopUpgrades", 10)
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			RebirthShopUpgrades = result
		end
	end
end

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

-- Owned/created by RebirthShopService.server.luau -- waited on rather than
-- created here, same reasoning as RebirthHandler.server.luau's own wait for
-- these (see its comment): exactly one owner for the whole remote set.
local rebirthShopRemotesFolder = RP:WaitForChild("RebirthShopRemotes", 10)
local SecondWindRemote = rebirthShopRemotesFolder and rebirthShopRemotesFolder:WaitForChild("SecondWindProc", 10)
local ShardRainRemote = rebirthShopRemotesFolder and rebirthShopRemotesFolder:WaitForChild("ShardRainProc", 10)

-- =========================================================================
-- MOMENTUM (Prestige Shop: rebirthshop_momentum)
-- =========================================================================
-- Sustained clicking builds a stacking combo -- EssenceMultiplier reads
-- MomentumStacks directly off the player attribute set below. Tracked
-- server-side (not just displayed client-side) because it feeds a real
-- essence-multiplier bonus: a client-reported stack count could otherwise
-- be forged to claim the max bonus on every single click.
--
-- [player] = { Stacks: number, DecayThread: thread? }
local comboState = {}

local function bumpMomentum(plr)
	if not RebirthShopUpgrades then
		return
	end

	local level = plr:GetAttribute("rebirthshop_momentum") or 0
	if level < 1 then
		return
	end

	local state = comboState[plr]
	if not state then
		state = { Stacks = 0, DecayThread = nil }
		comboState[plr] = state
	end

	if state.DecayThread then
		task.cancel(state.DecayThread)
		state.DecayThread = nil
	end

	state.Stacks = math.min(state.Stacks + 1, RebirthShopUpgrades.MOMENTUM_MAX_STACKS)
	plr:SetAttribute("MomentumStacks", state.Stacks)

	-- Combo resets if the player stops clicking for the window -- restarted
	-- from scratch on every click above, so only the LATEST click's timer
	-- ever actually fires.
	state.DecayThread = task.delay(RebirthShopUpgrades.MOMENTUM_WINDOW_SECONDS, function()
		state.DecayThread = nil
		state.Stacks = 0
		if plr.Parent then
			plr:SetAttribute("MomentumStacks", 0)
		end
	end)
end

local ABBREVIATIONS = {
	"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No"
}

local function formatNumber(value: number): string
	-- Handle negative numbers safely
	local absValue = math.abs(value)
	if absValue < 1000 then
		return tostring(value)
	end

	-- Calculate which abbreviation bucket the number falls into
	-- floor(log10(value) / 3) gives us the index (1 for thousands, 2 for millions, etc.)
	local index = math.floor(math.log10(absValue) / 3)

	-- Cap the index at our highest abbreviation (Nonillion) to prevent errors
	if index >= #ABBREVIATIONS then
		index = #ABBREVIATIONS - 1
	end

	-- Divide the number down to its abbreviated form
	local shortValue = value / (10 ^ (index * 3))

	-- Format to 2 decimal places (e.g., 1.25M)
	-- %.2f forces two decimals, but we can clean up trailing zeros if you prefer
	local formatted = string.format("%.2f", shortValue)

	-- Optional: Clean up trailing zeros (e.g., change "1.50K" to "1.5K" or "1.00K" to "1K")
	formatted = string.gsub(formatted, "%.?0+$", "")

	return formatted .. ABBREVIATIONS[index + 1]
end
local EssenceMulti = require(RP:WaitForChild("EssenceMultiplier"))
local ResonanceService = require(ServerScriptService:WaitForChild("ResonanceService"))

-- Only holds stuff OrbController doesn't already own for us (leaderstat +
-- save data refs). Health/MaxHealth used to be cached NumberValue refs here,
-- but OrbController now owns HP entirely internally.
local function getOrInitPlayerSession(plr)
	local userId = plr.UserId
	if not PlayerDatas[userId] then
		PlayerDatas[userId] = {
			["data"] = require(plr:WaitForChild("PlayerData")),
			["Earth Essence leaderstat"] = plr:WaitForChild("leaderstats"):WaitForChild("Earth Essence"),
			["Shadow Essence leaderstat"] = plr:WaitForChild("leaderstats"):WaitForChild("Shadow Essence")

		}
	end

	-- Defensive/idempotent: safe even if PlayerAdded already Init'd this
	-- player elsewhere (Init no-ops if already called). If your upgrade
	-- attributes load asynchronously, RecalculateStats will still fire
	-- correctly later since Init hooks the attribute-changed signals.
	OrbController.Init(plr)

	return PlayerDatas[userId]
end

-- 1. Handle the player clicking the orb
OrbClick.OnServerEvent:Connect(function(plr)
	getOrInitPlayerSession(plr)

	local canFire, isTrickle = OrbController.CanFire(plr)
	if not canFire then
		return
	end

	local success, hpCostPaid, wasTrickle, secondWindData = OrbController.Fire(plr)
	if not success then
		return
	end

	-- wasTrickle shots are core_resilience's free "orb isn't fully dead" hit.
	-- If you want trickle shots to grant reduced essence vs. a normal shot,
	-- this is the spot to branch on wasTrickle and scale down whatever
	-- reward your click flow grants (the client's SpawnOrb call happens
	-- regardless of this, so gate any reward difference here, not there).

	bumpMomentum(plr)

	-- rebirthshop_secondwind just triggered (HP already healed by Fire()
	-- above) -- grant the boost and tell the client to play its effect.
	if secondWindData then
		local PotionTimerService = getPotionTimerService()
		if PotionTimerService then
			PotionTimerService.ApplyPotion(plr, "EssenceX15", secondWindData.BoostSeconds)
		end
		if SecondWindRemote then
			SecondWindRemote:FireClient(plr, secondWindData.BoostSeconds)
		end
	end
end)


-- crit: true if the specific orb being collected rolled a crit client-side
-- (CriticalsController.RollCrit, at spawn time). EssenceMulti.
-- CalculateMultiplier derives the EXTRA bonus a crit is worth -- beyond
-- its flat base 2x -- from the player's own CritMultiplierBonus attribute
-- total, so that part can't exceed what real upgrades justify. The base
-- 2x is NOT gated by anything: a client that always claims crit = true
-- gets an unconditional 2x on every collection, upgrades or not.
--
-- Flagged rather than fixed: a real fix means the server rolling crits
-- itself instead of trusting this flag, which needs a way to tie a
-- specific "collected" event back to a specific earlier orb/click (an id
-- the client doesn't currently send -- orbs are purely client-side visual
-- objects, same root cause as quantity below). That's a real feature, not
-- a small patch, and the exposure is bounded in the meantime: crit only
-- ever multiplies an amount already capped by MAX_QUANTITY_PER_COLLECTION,
-- and MAX_CRIT_CHANCE already lets a fully-upgraded legitimate player
-- approach a near-100% real crit rate on their own, so this mostly just
-- lets a player skip actually buying that upgrade line -- not the
-- unbounded-currency class of bug quantity/gold were.
--
-- gold and quantity had a more direct version of this problem, with no
-- ceiling or re-derivation at all, and both were being trusted outright
-- until this pass:
--
--   - gold used to go straight into CalculateMultiplier's flat 3x with no
--     check at all, even though StormController.luau's own header comment
--     documents exactly the fix below ("checking player:GetAttribute(
--     'StormIsGolden') at the moment of collection") as the intended
--     design -- it just was never actually wired up here. Any client could
--     FireServer with gold=true for a permanent, unconditional 3x on every
--     collection with no storm ever active. Re-derived below instead of
--     trusted directly.
--   - quantity is an orb's base essence value, which is entirely client-
--     owned data (orbs are purely client-side visual objects -- OrbClicker.
--     client.luau sets EssenceValue locally, the server has no independent
--     record of what any given collection "should" be worth). Unlike
--     gold/crit, nothing bounds it: a direct FireServer call could claim
--     any quantity at all, permanently inflating real, saved currency and
--     poisoning the global leaderboard. MAX_QUANTITY_PER_COLLECTION is a
--     generous sanity ceiling, not a precise recompute of the legitimate
--     formula -- legitimate play (even a maxed root_awakening at 32x base,
--     fused through a maxed Gravity Well's +20%) stays far under it; it
--     exists purely to block the "claim an arbitrary huge number" exploit.
local MAX_QUANTITY_PER_COLLECTION = 5000

local BS = game:GetService("BadgeService")
collected.OnServerEvent:Connect(function(plr, orbName, quantity, crit, gold)
	-- Defensive validation: orbName/quantity come straight from the
	-- client's FireServer call, and everything below indexes off orbName
	-- directly (Essences[temp], the "<orbName> leaderstat" session key).
	-- An unrecognized orbName (nil, or anything that isn't one of the two
	-- real essence types -- seen in practice, cause not fully confirmed,
	-- but a direct/malformed FireServer call from an exploit would
	-- produce exactly this) used to reach the Essences[temp]["Quantity"]
	-- lookup below with temp == nil, which errors (indexing nil) and
	-- aborts the handler PARTWAY THROUGH -- after the crit-count/badge
	-- state above had already been applied, so a player could end up
	-- credited for a crit whose essence gain never actually landed.
	-- Reject up front instead, before any state changes. The client now
	-- also guards this at the source (see CollectEffect in
	-- CursorCollection.client.luau) so a legitimate client should never
	-- trigger this branch at all -- this exists for whatever still can.
	--
	-- The quantity checks below (NaN/non-positive/over-ceiling) close the
	-- forged-currency gap described above -- see MAX_QUANTITY_PER_
	-- COLLECTION's comment for why 5000 is safe headroom, not a tight fit.
	if (orbName ~= "Earth Essence" and orbName ~= "Shadow Essence")
		or type(quantity) ~= "number"
		or quantity ~= quantity -- NaN: the only number that's never equal to itself
		or quantity <= 0
		or quantity > MAX_QUANTITY_PER_COLLECTION
	then
		warn(("[OrbClickManager] Rejected malformed/out-of-range collection from %s (%d): orbName=%s quantity=%s")
			:format(plr.Name, plr.UserId, tostring(orbName), tostring(quantity)))
		return
	end

	-- Re-derived from the server's own storm state rather than trusting
	-- the client's gold flag directly -- see the comment above this
	-- handler for why. A real golden storm sets this attribute itself
	-- (StormController:_mirrorAttributes), so legitimate play is
	-- unaffected; a forged gold=true with no storm active now just does
	-- nothing instead of granting a free permanent 3x.
	local isGolden = gold and plr:GetAttribute("StormIsGolden") == true

	-- Validated collections feed the alternating-essence Resonance loop before
	-- the multiplier is calculated, so the newly earned Harmony stack applies
	-- to this collection immediately rather than one orb late.
	ResonanceService.ProcessCollection(plr, orbName, crit == true)

	local session = getOrInitPlayerSession(plr)
	local userId = plr.UserId
	if not plr:GetAttribute("3032854636359044") then
		plr:SetAttribute("3032854636359044", true)
		PlayerDatas[plr.UserId]["data"].Badges[3032854636359044] = true
		BS:AwardBadgeAsync(plr.UserId,3032854636359044)
	end
	
	if crit then
		PlayerDatas[plr.UserId]["data"].CriticalEssence += quantity
		
		if not plr:GetAttribute("2662901027091325") then
			plr:SetAttribute("2662901027091325", true)
			PlayerDatas[plr.UserId]["data"].Badges[2662901027091325] = true
			BS:AwardBadgeAsync(plr.UserId,2662901027091325)
		end
	end
	-- Computed ONCE and reused for both lines below -- CalculateMultiplier
	-- rolls double_crit internally when crit is true, so calling it twice
	-- here would roll that independently each time and could credit a crit
	-- to one number but not the other.
	local multiplier = EssenceMulti.CalculateMultiplier(plr, isGolden, crit)
	local essenceGained = math.floor(multiplier * quantity)
	local temp = orbName
	if orbName == "Earth Essence" then
		temp = "EarthEssence"
	end
	local newEssence = essenceGained + PlayerDatas[plr.UserId]["data"]["Essences"][temp]["Quantity"]
	PlayerDatas[plr.UserId]["data"]["TotalEssenceGathered"] += essenceGained
	PlayerDatas[plr.UserId][orbName.." leaderstat"]:SetAttribute("Quantity",newEssence)

	-- rebirthshop_shardrain: a rare chance for this SAME collection to also
	-- drop a bonus Prestige Shard -- a new earn path for Rebirth Currency
	-- outside of rebirthing itself. Independent roll from crit/gold; this
	-- pays in a completely different currency so there's no reason to tie
	-- the odds together.
	if RebirthShopUpgrades then
		local shardLevel = plr:GetAttribute("rebirthshop_shardrain") or 0
		if shardLevel >= 1 then
			local shardData = RebirthShopUpgrades.GetLevelData("rebirthshop_shardrain", shardLevel)
			if shardData and math.random() < shardData.ChancePercent then
				local currentShards = tonumber(plr:GetAttribute("RebirthCurrency")) or 0
				plr:SetAttribute("RebirthCurrency", currentShards + shardData.ShardAmount)
				if ShardRainRemote then
					ShardRainRemote:FireClient(plr, shardData.ShardAmount)
				end
			end
		end
	end
end)

local returnEvent = Events:WaitForChild("Return")

-- An orb finishing its return-home animation grants a small bonus heal on
-- top of whatever OrbController's passive regen has already ticked in.
returnEvent.OnServerEvent:Connect(function(plr, quantity)
	getOrInitPlayerSession(plr)

	if type(quantity) ~= "number" then
		return
	end

	OrbController.Heal(plr, quantity)
end)

-- Release every per-player cache from this script when a player leaves. This
-- is intentionally one shared handler so the cleanup remains compatible with
-- the retention branch's PlayerDatas fix and cannot leak across busy servers.
game:GetService("Players").PlayerRemoving:Connect(function(plr)
	PlayerDatas[plr.UserId] = nil
	local state = comboState[plr]
	if state and state.DecayThread then
		task.cancel(state.DecayThread)
	end
	comboState[plr] = nil
end)

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
-- (CriticalsController.RollCrit, at spawn time). gold: true for golden-storm
-- orbs. EssenceMulti.CalculateMultiplier is the ONLY thing that turns "crit"
-- into an actual bonus amount, and it derives that amount from the player's
-- own CritMultiplierBonus attribute total -- so the client flagging crit
-- can't grant more than their real upgrades justify.
local BS = game:GetService("BadgeService")
collected.OnServerEvent:Connect(function(plr, orbName, quantity, crit, gold)
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
	local multiplier = EssenceMulti.CalculateMultiplier(plr, gold, crit)
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

-- Only cleans up this script's OWN new comboState table -- PlayerDatas
-- above has no such cleanup and predates this change; not touching it.
game:GetService("Players").PlayerRemoving:Connect(function(plr)
	local state = comboState[plr]
	if state and state.DecayThread then
		task.cancel(state.DecayThread)
	end
	comboState[plr] = nil
end)
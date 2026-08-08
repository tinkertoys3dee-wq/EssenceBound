local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EssenceMultiplier = {}
local rebirthModule = require(ReplicatedStorage:WaitForChild("RebirthHandler"))
local IdleUpgrades = require(ReplicatedStorage:WaitForChild("IdleUpgrades"))
local Criticals = require(ReplicatedStorage:WaitForChild("CriticalsController"))
-- Timed lookup with a graceful fallback, NOT a bare WaitForChild.
--
-- Every essence reward in the game flows through CalculateMultiplier. If
-- SanctumUpgrades ever failed to reach ReplicatedStorage (a partial sync,
-- a script deleted in Studio), an infinite WaitForChild here would hang
-- this module forever and silently zero the entire economy -- which is
-- precisely the failure this file already caused once. Missing the Sanctum
-- module must cost the Sanctum bonus and nothing else.
local SanctumUpgrades
do
	local module = ReplicatedStorage:FindFirstChild("SanctumUpgrades")
		or ReplicatedStorage:WaitForChild("SanctumUpgrades", 10)

	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			SanctumUpgrades = result
		end
	end

	if not SanctumUpgrades then
		warn("EssenceMultiplier: SanctumUpgrades unavailable -- Sanctum bonuses disabled, economy otherwise unaffected.")
	end
end

-- Same defensive contract as SanctumUpgrades above, for the Prestige
-- Shop's Momentum Core upgrade.
local RebirthShopUpgrades
do
	local module = ReplicatedStorage:FindFirstChild("RebirthShopUpgrades")
		or ReplicatedStorage:WaitForChild("RebirthShopUpgrades", 10)

	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			RebirthShopUpgrades = result
		end
	end
end

-- Rolls the double-crit chain for a single collection and returns the
-- resulting crit multiplier contribution (1 = no crit bonus). Kept as its
-- own function so CalculateMultiplier only ever rolls double-crit ONCE per
-- call -- callers must not call CalculateMultiplier twice for the same
-- collection event, or they'll get two independent (and possibly
-- inconsistent) double-crit rolls for what should be one crit. See
-- OrbClickServerScript.lua's "collected" handler for the correct pattern:
-- compute the multiplier once, reuse it for every number that derives
-- from it.
local function RollCritMultiplier(plr, crit)
	local isDoubleCrit = Criticals.RollDoubleCrit(plr, crit)
	return Criticals.GetCritMultiplier(plr, crit, isDoubleCrit)
end

function EssenceMultiplier.CalculateMultiplier(plr, gold, crit)
	local multiplier = 1
	if plr:GetAttribute("EssenceMultiplier") then
		multiplier *= plr:GetAttribute("EssenceMultiplier")
	end
	if plr:GetAttribute(1907605899) then
		multiplier *= 2
	end
	if plr:GetAttribute(1909291891) then
		multiplier *= 1.5
	end
	if plr:GetAttribute("Rebirths") then
		multiplier *= rebirthModule.CalculateTotalMultiplier(plr:GetAttribute("Rebirths"))
	end
	multiplier *= IdleUpgrades.GetGlobalEssenceMultiplier(plr)

	if gold then
		multiplier *= 3
	end

	if crit then
		multiplier *= RollCritMultiplier(plr, crit)
	end
	
	if plr:GetAttribute("essence_convergence") then
		multiplier *= 1 + plr:GetAttribute("essence_convergence")
	end

	-- Prestige Shop: Momentum Core. MomentumStacks is maintained
	-- server-side in OrbClickManager (sustained clicking builds it, a
	-- pause decays it) -- read directly off the attribute rather than
	-- recomputed here, same trust boundary as everything else in this
	-- function reading a server-owned attribute.
	if RebirthShopUpgrades then
		local momentumLevel = RebirthShopUpgrades.GetPlayerLevel(plr, "rebirthshop_momentum")
		if momentumLevel >= 1 then
			local momentumData = RebirthShopUpgrades.GetLevelData("rebirthshop_momentum", momentumLevel)
			local stacks = tonumber(plr:GetAttribute("MomentumStacks")) or 0
			if momentumData then
				multiplier *= 1 + (stacks * momentumData.PercentPerStack)
			end
		end
	end

	-- Shadow Sanctum: Umbral Focus is a flat additive bonus to everything.
	-- Coerced so a missing effect can never turn the multiplier into a
	-- non-number and zero out every reward in the game (which is exactly
	-- the failure mode the ShadowEssence^.2 bug caused).
	local umbralFocus = 0
	if SanctumUpgrades then
		umbralFocus = tonumber(SanctumUpgrades.GetPlayerEffect(plr, "sanctum_umbral_focus")) or 0
	end
	multiplier *= 1 + umbralFocus

	-- Shadow Essence gives a synergy bonus that grows with the stockpile,
	-- but must never zero out the base multiplier for players who haven't
	-- collected any yet (0^.2 == 0, which was silently zeroing every single
	-- essence reward in the game for every new player). +1 keeps this a
	-- neutral 1x at zero and growing from there.
	--
	-- Reads LIFETIME earnings rather than the current balance: the balance
	-- is spendable in the Sanctum, and if this used it, buying anything
	-- would shrink the player's own multiplier. Falls back to the balance
	-- for the brief window on join before the lifetime attribute is set.
	local shadowEssence = plr:GetAttribute("ShadowEssenceLifetime")
		or plr:GetAttribute("ShadowEssence")
		or 0

	-- The +1 inside the bracket is the safety guard: it keeps this at a
	-- neutral 1x when the balance is 0 instead of annihilating the whole
	-- multiplier. Adding a second "1 +" in FRONT of this expression is not
	-- a guard -- it would be a flat ~2x baseline inflation of every reward
	-- in the game.
	multiplier *= (shadowEssence + 1)^.2
	return multiplier
end

return EssenceMultiplier

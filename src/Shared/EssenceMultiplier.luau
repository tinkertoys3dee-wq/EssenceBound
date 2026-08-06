local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EssenceMultiplier = {}
local rebirthModule = require(ReplicatedStorage:WaitForChild("RebirthHandler"))
local IdleUpgrades = require(ReplicatedStorage:WaitForChild("IdleUpgrades"))
local Criticals = require(ReplicatedStorage:WaitForChild("CriticalsController"))

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
		print(plr:GetAttribute("essence_convergence"))
		multiplier *= 1 + plr:GetAttribute("essence_convergence")
	end
	
	-- Shadow Essence holdings give a synergy bonus that grows with stockpile
	-- size, but must never zero out the base multiplier for players who
	-- haven't collected any Shadow Essence yet (0^.2 == 0, which was
	-- silently zeroing every single essence reward in the game for every
	-- new player). +1 keeps this a neutral 1x at zero and growing from there.
	local shadowEssence = plr:GetAttribute("ShadowEssence") or 0
	multiplier *= (shadowEssence + 1)^.2
	return multiplier
end

return EssenceMultiplier
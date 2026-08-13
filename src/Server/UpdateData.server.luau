local UpdateData = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("UpdateData")

-- Only these top-level PlayerData keys are safe for a client to write
-- directly (preferences/flags). Currency, rebirths, and anything else that
-- represents progression must ONLY ever be mutated by trusted server code
-- (TreeUpgrades, RebirthHandler, ProductPurchaseHandler, OrbClickManager,
-- ...) -- without this allowlist any client could FireServer its own path
-- into "Essences"/"Rebirths"/etc. and set its own currency to anything.
local ALLOWED_ROOTS = {
	Settings = true,
	SeenTutorial = true,
	SeenFirstCrit = true,
	SeenFavoritePrompt = true,
	SeenWhatsNewVersion = true,
	HollowedMilestones = true,
}

UpdateData.OnServerEvent:Connect(function(plr, Value, Operator, ...)
	local path = {...}
	if not path[1] or not ALLOWED_ROOTS[path[1]] then
		warn(("UpdateData: rejected write to disallowed path root %s from %s"):format(tostring(path[1]), plr.Name))
		return
	end

	local currentFolder = require(plr:WaitForChild("PlayerData"))

	for i = 1, #path do
		local key = path[i]

		-- The allowlist above only constrains path[1] -- everything past
		-- that just walks whatever shape ALLOWED_ROOTS' data actually has.
		-- Every real root today is either a scalar or one flat table
		-- (Settings, HollowedMilestones), so a legitimate path never
		-- descends past a table. A path with MORE segments than the real
		-- data supports would previously try to index a boolean (e.g.
		-- SeenTutorial, true/false) and throw "attempt to index a boolean
		-- value", aborting with an error instead of the same clean reject
		-- every other malformed-input case in this codebase gets.
		if type(currentFolder) ~= "table" then
			warn(("UpdateData: path under %s from %s goes deeper than the data shape allows (segment %d)"):format(tostring(path[1]), plr.Name, i))
			return
		end

		if currentFolder[key] ~= nil then
			-- If it's the last argument in your path, we found our target!
			if i == #path then
				-- Arithmetic on a non-number (Value from the client, or --
				-- in principle -- the field itself) throws the same class
				-- of error as above. "=" is unrestricted: every ALLOWED_
				-- ROOTS field is the player's own preference/flag data, so
				-- letting it become whatever type the client sends is the
				-- same trust already extended to every other Settings/Seen*
				-- write here, not a new gap.
				if (Operator == "+" or Operator == "-" or Operator == "*" or Operator == "/")
					and (type(Value) ~= "number" or type(currentFolder[key]) ~= "number")
				then
					warn(("UpdateData: rejected non-numeric %s on %s from %s"):format(tostring(Operator), tostring(key), plr.Name))
					return
				end

				if Operator == "+" then
					currentFolder[key] += Value
				elseif Operator == "-" then
					currentFolder[key] -= Value
				elseif Operator == "=" then
					currentFolder[key] = Value
				elseif Operator == "*" then
					currentFolder[key] *= Value
				elseif Operator == "/" then
					currentFolder[key] /= Value
				else
					warn("Invalid Operator: ".. tostring(Operator))
				end
				
				if path[1] == "Settings" then
					plr:SetAttribute(string.gsub(key, "%s", ""), Value)
				end
				if path[1] == "SeenTutorial" then
					plr:SetAttribute("SeenTutorial", Value)
				end
				if path[1] == "SeenFirstCrit" then
					plr:SetAttribute("SeenFirstCrit", Value)
				end
				if path[1] == "SeenFavoritePrompt" then
					plr:SetAttribute("SeenFavoritePrompt", Value)
				end
				if path[1] == "SeenWhatsNewVersion" then
					plr:SetAttribute("SeenWhatsNewVersion", Value)
				end
			else
				-- Otherwise, dig deeper into the hierarchy structure
				currentFolder = currentFolder[key]
			end
		else
			warn("Invalid hierarchy path specified at key: " .. tostring(key))
			break
		end
	end
end)

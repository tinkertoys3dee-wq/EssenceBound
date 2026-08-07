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
		
		if currentFolder[key] ~= nil then
			-- If it's the last argument in your path, we found our target!
			if i == #path then
				print("Reached target data:", currentFolder[key])
				-- Do your logic here (e.g., return it, modify it, etc.)
								
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

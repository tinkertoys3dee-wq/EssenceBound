local UpdateData = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("UpdateData")

UpdateData.OnServerEvent:Connect(function(plr, Value, Operator, ...)
	local path = {...}
	
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

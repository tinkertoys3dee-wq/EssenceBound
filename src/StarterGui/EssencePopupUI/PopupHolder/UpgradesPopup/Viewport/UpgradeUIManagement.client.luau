local RP = game:GetService("ReplicatedStorage")
local remotes = RP:WaitForChild("Remotes")
local TreeUpgrades = require(RP:WaitForChild("TreeUpgrades"))

local UserInputService = game:GetService("UserInputService")

local viewport = script.Parent
local canvas = viewport:WaitForChild("Canvas")
local revert = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Revert")
local loadingscreen = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LoadingDone")
loadingscreen.Event:Wait()
-- === ZOOM SETTINGS ===
local MIN_ZOOM = 0.5
local MAX_ZOOM = 3.0
local ZOOM_SPEED = 0.1

-- Set up UIScale for the canvas
local uiScale = canvas:FindFirstChildWhichIsA("UIScale")
if not uiScale then
	uiScale = Instance.new("UIScale")
	uiScale.Parent = canvas
end
uiScale.Scale = 1 -- Default scale

local isDragging = false
local lastInputPos = Vector2.new()

-- Track input starting on the viewport
viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = true
		lastInputPos = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

local isDragging = false
local lastInputPos = Vector2.new()

-- We track these "virtually" to avoid Roblox's render-delay stutter
local virtualAbsX = 0
local virtualAbsY = 0
local targetOffsetX = 0
local targetOffsetY = 0

-- Track input starting on the viewport
viewport.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = true
		lastInputPos = Vector2.new(input.Position.X, input.Position.Y)
		
		-- Sync our virtual trackers to the real UI positions the moment we click
		virtualAbsX = canvas.AbsolutePosition.X
		virtualAbsY = canvas.AbsolutePosition.Y
		targetOffsetX = canvas.Position.X.Offset
		targetOffsetY = canvas.Position.Y.Offset
	end
end)

-- Track movement
UserInputService.InputChanged:Connect(function(input)
	if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		
		-- FIX 1: The Ghost Click Failsafe. If the mouse button is no longer held down, cancel the drag immediately.
		if input.UserInputType == Enum.UserInputType.MouseMovement and not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			isDragging = false
			return
		end

		local currentInputPos = Vector2.new(input.Position.X, input.Position.Y)
		local delta = currentInputPos - lastInputPos
		lastInputPos = currentInputPos 

		local scale = uiScale.Scale
		local viewSize = viewport.AbsoluteSize
		local canvasSize = canvas.AbsoluteSize 

		-- FIX 2: Update our virtual trackers (Immune to Roblox's mid-frame render lag)
		virtualAbsX = virtualAbsX + delta.X
		virtualAbsY = virtualAbsY + delta.Y
		targetOffsetX = targetOffsetX + (delta.X / scale)
		targetOffsetY = targetOffsetY + (delta.Y / scale)

		-- FIX 3: Calculate coordinates strictly RELATIVE to the Viewport (Ignores screen position)
		local relX = virtualAbsX - viewport.AbsolutePosition.X
		local relY = virtualAbsY - viewport.AbsolutePosition.Y

		local strideX = viewSize.X + canvasSize.X 
		local strideY = viewSize.Y + canvasSize.Y 

		-- === PERFECT OUT-OF-VIEW WRAPPING ===

		-- Wrap X (Left / Right)
		if relX > viewSize.X then
			targetOffsetX = targetOffsetX - (strideX / scale)
			virtualAbsX = virtualAbsX - strideX -- Keep virtual tracker synced!
		elseif relX + canvasSize.X < 0 then
			targetOffsetX = targetOffsetX + (strideX / scale)
			virtualAbsX = virtualAbsX + strideX
		end

		-- Wrap Y (Up / Down)
		if relY > viewSize.Y then
			targetOffsetY = targetOffsetY - (strideY / scale)
			virtualAbsY = virtualAbsY - strideY
		elseif relY + canvasSize.Y < 0 then
			targetOffsetY = targetOffsetY + (strideY / scale)
			virtualAbsY = virtualAbsY + strideY
		end

		-- Apply the new position
		canvas.Position = UDim2.new(
			canvas.Position.X.Scale,
			targetOffsetX,
			canvas.Position.Y.Scale,
			targetOffsetY
		)
	end
end)

-- End drag when the button/finger is released
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isDragging = false
	end
end)

local player = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")

local frame = script.Parent:FindFirstChild("Canvas") -- Change if your Frame is elsewhere

local hoverSize = 1.05
local clickSize = 0.95
local normalSize = 1

local hoverTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local clickTweenInfo = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local CS = game:GetService("CollectionService")

local UpgradePurchaseEffct = require(RP:WaitForChild("UpgradePurchaseEffect"))
local BuyRemote = RP:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")

for _, child in ipairs(frame:GetChildren()) do
	if child:IsA("Frame") and child.Name ~= "Connections" then
		CS:AddTag(child, "UpgradeNode")
		
		local button = child:FindFirstChild("TextButton")

		if button and button:IsA("TextButton") then
			local uiScale = child:FindFirstChild("UIScale")

			if uiScale then
				local hovering = false

				button.MouseEnter:Connect(function()
					hovering = true
					TweenService:Create(uiScale, hoverTweenInfo, {
						Scale = hoverSize
					}):Play()
				end)

				button.MouseLeave:Connect(function()
					hovering = false
					TweenService:Create(uiScale, hoverTweenInfo, {
						Scale = normalSize
					}):Play()
				end)

				button.MouseButton1Down:Connect(function()
					TweenService:Create(uiScale, clickTweenInfo, {
						Scale = clickSize
					}):Play()
				end)

				button.MouseButton1Up:Connect(function()
					local targetScale = hovering and hoverSize or normalSize

					TweenService:Create(uiScale, hoverTweenInfo, {
						Scale = targetScale
					}):Play()
				end)
			end
			
			button.Activated:Connect(function()
				if TreeUpgrades.GetUpgrade(child.Name).MaxLevel > child:GetAttribute("Tier") and TreeUpgrades.GetUpgrade(child.Name).RebirthRequired <= player:GetAttribute("Rebirths") and TreeUpgrades.GetCostForNextLevel(child.Name,child:GetAttribute("Tier")) then
					BuyRemote:FireServer(child.Name)
				end
			end)
		end
	end
end


local connections = canvas:WaitForChild("Connections")

local EXTRA_CONNECTIONS = {
	{ "shatter_force_1", "critical_chance_1" },
	{ "critical_chance_1", "collection_radius_1" },
	{ "collection_radius_1", "rebirth_insight_1" },
	{ "rebirth_insight_1", "idle_drips_1" },
	{ "idle_drips_1", "storm_frequency_1" },
	{ "storm_frequency_1", "shatter_force_1" },
}

local function findExtraConnectionLine(nameA, nameB)
	return connections:FindFirstChild(nameA .. "-" .. nameB)
		or connections:FindFirstChild(nameB .. "-" .. nameA)
end

local function isNodeActive(nodeId)
	local nodeFrame = frame:FindFirstChild(nodeId)
	return nodeFrame ~= nil and (nodeFrame:GetAttribute("Tier") or 0) > 0
end

-- Checks every extra pair and fades in any connector whose both endpoints
-- are now active. Safe to call repeatedly — AlreadyFadedIn guards re-tweening.


local function GetNextUnlocks(upgradeId)
	local nextNodes = {}

	-- Iterate through the master list
	for _, def in ipairs(TreeUpgrades.List) do
		-- Check if the freshly bought upgrade is in this node's prerequisites
		if table.find(def.Prerequisites, upgradeId) then
			table.insert(nextNodes, def)
		end
	end

	return nextNodes
end

local function playUnlockSheen(Gradient)
	Gradient.Parent.Visible = true
	-- Make sure it starts fully hidden/locked
	--Gradient.Offset = Vector2.new(-.1, 0)

	-- Configure the tween to slide the offset across the X axis
	local tweenInfo = TweenInfo.new(
		1.6, -- Duration of the slide in seconds (adjust to change speed)
		Enum.EasingStyle.Cubic, -- Smooth acceleration/deceleration
		Enum.EasingDirection.Out
	)

	-- Target offset shifts it all the way to the other side
	local targetProperties = {
		Offset = Gradient:GetAttribute("Target")
	}

	local tween = TweenService:Create(Gradient, tweenInfo, targetProperties)
	tween:Play()
end

local activeTweens = {}

-- Helper function to play a fade tween smoothly
local function playFadeIn(uiObject, targetTransparency)
	if not uiObject then return end

	-- 1. CANCEL any running tween on this specific object so it stops overwriting!
	if activeTweens[uiObject] then
		activeTweens[uiObject]:Cancel()
		activeTweens[uiObject] = nil
	end

	-- Identify the correct transparency property
	local prop = (uiObject:IsA("ImageLabel") or uiObject:IsA("ImageButton")) and "ImageTransparency" or "BackgroundTransparency"

	uiObject.Visible = true

	-- Optional: Only set to 1 if you want it to jump to fully invisible before fading
	-- uiObject[prop] = 1 

	local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(uiObject, tweenInfo, { [prop] = targetTransparency })

	-- Save reference to running tween
	activeTweens[uiObject] = tween

	tween.Completed:Connect(function()
		if activeTweens[uiObject] == tween then
			activeTweens[uiObject] = nil
		end
	end)

	tween:Play()
end

-- Helper function to INSTANTLY set transparency (and stop active tweens)
local function setTransparencyInstant(uiObject, targetTransparency)
	if not uiObject then return end

	-- Stop active tween so it doesn't overwrite this instant change
	if activeTweens[uiObject] then
		activeTweens[uiObject]:Cancel()
		activeTweens[uiObject] = nil
	end

	if uiObject:IsA("ImageLabel") or uiObject:IsA("ImageButton") then
		uiObject.ImageTransparency = targetTransparency
	else
		uiObject.BackgroundTransparency = targetTransparency
	end
end

local function refreshExtraConnections()
	for _, pair in ipairs(EXTRA_CONNECTIONS) do
		local nameA, nameB = pair[1], pair[2]
		local connectionLine = findExtraConnectionLine(nameA, nameB)

		if not connectionLine then
			warn("Missing extra connection line for:", nameA, nameB)
		elseif not connectionLine:GetAttribute("AlreadyFadedIn") then
			if isNodeActive(nameA) and isNodeActive(nameB) then
				connectionLine:SetAttribute("AlreadyFadedIn", true)
				playFadeIn(connectionLine, 0)

				local gradient = connectionLine:FindFirstChild("UIGradient")
				if gradient then
					playUnlockSheen(gradient)
				end
			end
		end
	end
end

local UpgradeSound = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("UpgradeScreen"):WaitForChild("UpgradeNormal")
BuyRemote.OnClientEvent:Connect(function(upgradeName, tier, newdata)
	UpgradeSound:Play()
	-- 1. Safely find the main child and its ImageLabel
	local child = frame:FindFirstChild(upgradeName)
	if not child then
		warn("Could not find upgrade frame for:", upgradeName)
		return -- Exit early if the frame doesn't exist
	end
	child:SetAttribute("Unlocked", true)

	local imageLabel = child:FindFirstChild("ImageLabel")
	if imageLabel then
		imageLabel.ImageTransparency = 0
	end

	-- 2. Format Costs (Renamed loop variable to avoid shadowing)
	local costsText = ""
	for currencyName, cost in pairs(TreeUpgrades.GetCostForNextLevel(upgradeName, tier)) do
		costsText = costsText .. currencyName .. ": " .. cost .. "\n"
	end

	child:SetAttribute("Cost", costsText)
	child:SetAttribute("Tier", tier)
	
	-- 3. Handle Downstream Unlocks
	local downstreamNodes = GetNextUnlocks(upgradeName)
	for _, node in ipairs(downstreamNodes) do
		local isFullyUnlocked, lockReason = TreeUpgrades.IsUnlocked(newdata, node.Id)
		local NewNode = frame:FindFirstChild(node.Id)

		if not NewNode then
			warn("Missing downstream node frame:", node.Id)
			continue -- Skip to the next node in the loop
		end

		if isFullyUnlocked then
			print("NEW UNLOCK: " .. node.Name .. " is now available to purchase!")

			if NewNode:GetAttribute("Tier") == 0 then
				NewNode:SetAttribute("Unlocked",true)
				local newImage = NewNode:FindFirstChild("ImageLabel")
			
				-- Safely find the connection line without yielding forever
				local connectionName = child.Name .. "-" .. NewNode.Name
				local connectionLine = connections:FindFirstChild(connectionName)
				print(connectionLine)
				if connectionLine and not connectionLine:GetAttribute("AlreadyFadedIn") then
					connectionLine:SetAttribute("AlreadyFadedIn", true)
					playFadeIn(NewNode:FindFirstChild("ImageLabel"), .7)
					playFadeIn(connectionLine, 0)
				else
					warn("Missing connection line:", connectionName)
				end
				if TreeUpgrades.GetUpgrade(NewNode.Name).RebirthRequired <= player:GetAttribute("Rebirths") then
					NewNode:SetAttribute("Buyable", true)
				end
				NewNode.Visible = true
			end
		else
			print("REVEALED: " .. node.Name .. " is downstream, but still locked. Reason: " .. lockReason)
			
			if NewNode:GetAttribute("Tier") == 0 then
				local newImage = NewNode:FindFirstChild("ImageLabel")
				if newImage then
					newImage.ImageTransparency = 0.7
				end

				-- Safely find the connection line without yielding forever
				local connectionName = child.Name .. "-" .. NewNode.Name
				local connectionLine = connections:FindFirstChild(connectionName)
				if connectionLine  and not connectionLine:GetAttribute("AlreadyFadedIn") then
					connectionLine:SetAttribute("AlreadyFadedIn", true)
					playFadeIn(NewNode:FindFirstChild("ImageLabel"), .7)
					playFadeIn(connectionLine, 0)
				else
					warn("Missing connection line:", connectionName)
				end
				
				NewNode:SetAttribute("Buyable", false)
				NewNode.Visible = true
			end
		end
	end

	-- 4. Play Sheen on Prerequisites
	for _, old in pairs(TreeUpgrades.GetUpgrade(upgradeName).Prerequisites) do
		local connectionName = old .. "-" .. upgradeName
		local connectionLine = connections:FindFirstChild(connectionName)

		if connectionLine then
			local gradient = connectionLine:FindFirstChild("UIGradient")
			if gradient then
				playUnlockSheen(gradient)
			end
		end
	end
	
	-- 5. Play final purchase effect
	setTransparencyInstant(child:FindFirstChild("ImageLabel"), 0)
	
	UpgradePurchaseEffct.Play(child, child:GetAttribute("Category"), upgradeName)
	refreshExtraConnections()
end)

local dataremote = RP:WaitForChild("Remotes"):WaitForChild("GetData")

local function onRebirth(trueReset)
	local data = dataremote:InvokeServer()
	local tree = TreeUpgrades.GetVisibleTree(data)

	if trueReset then
		-- Wipe every connector to a clean, never-shown state up front
		-- (covers both prerequisite connectors AND the EXTRA_CONNECTIONS set)
		for _, conn in ipairs(connections:GetChildren()) do
			conn:SetAttribute("AlreadyFadedIn", false)
			conn.Visible = false
			conn.ImageTransparency = 1
			local gradient = conn:FindFirstChild("UIGradient")
			if gradient then
				gradient.Transparency = NumberSequence.new(1)
			end
		end
	end

	for index, IndexData in tree do
		local frame = canvas:WaitForChild(IndexData.Id)
		local imageLabel = frame:FindFirstChild("ImageLabel")

		if trueReset then
			frame:SetAttribute("Tier", 0)
			frame:SetAttribute("Unlocked", false)
			frame:SetAttribute("Buyable", false)
			frame:SetAttribute("Cost", "")
			frame:SetAttribute("Requires", "\n")

			if imageLabel then
				imageLabel.ImageTransparency = 0.7
			end

			frame.Visible = (#IndexData.Prerequisites == 0)
		else
			-- unchanged normal-refresh branch (same as before)
			imageLabel.ImageTransparency = 0
			for _, child in pairs(connections:GetChildren()) do
				child.ImageTransparency = 0
			end

			frame:SetAttribute("Tier", IndexData.CurrentLevel)
			frame:SetAttribute("Unlocked", IndexData.Unlocked)

			local Costs = ""
			local requires = "\n"
			for name, cost in pairs(TreeUpgrades.GetCostForNextLevel(IndexData.Id, IndexData.CurrentLevel)) do
				Costs = Costs .. name .. ": " .. cost .. "\n"
			end
			for indexx, prerequisite in pairs(IndexData.Prerequisites) do
				if indexx == #IndexData.Prerequisites - 1 then
					requires = requires .. prerequisite .. ", and "
				end
				requires = requires .. TreeUpgrades.GetUpgrade(prerequisite).Name .. ", "
			end
			local Further = TreeUpgrades.GetUpgrade(IndexData.Id)
			if Further and Further.RebirthRequired > 0 then
				requires = requires .. "\nRebirth " .. Further.RebirthRequired .. "+"
			end
			frame:SetAttribute("Cost", Costs)
			frame:SetAttribute("Requires", requires)

			if IndexData.CurrentLevel > 0 then
				frame.Visible = IndexData.Unlocked
			end

			if IndexData.Unlocked then
				if TreeUpgrades.GetUpgrade(frame.Name).RebirthRequired <= player:GetAttribute("Rebirths") then
					frame:SetAttribute("Buyable", true)
				end
				for _, prerequisite in pairs(IndexData.Prerequisites) do
					local connection = connections:FindFirstChild(prerequisite.."-"..IndexData.Id)
					if connection then
						local connTransparency = (IndexData.CurrentLevel > 0) and 0 or 0.7
						connection.ImageTransparency = connTransparency
						local gradient = connection:FindFirstChild("UIGradient")
						if gradient then
							gradient.Transparency = NumberSequence.new(connTransparency)
						end
						connection.Visible = true
					end
				end

				imageLabel.ImageTransparency = (IndexData.CurrentLevel > 0) and 0 or 0.7
				frame.Visible = true
			else
				frame:SetAttribute("Buyable", false)
			end
		end
	end
end

player.AttributeChanged:Connect(function(attr)
	if attr == "Rebirths" then
		onRebirth(true)
		onRebirth(false)
		refreshExtraConnections()
	end
end)
task.wait(1)
onRebirth(false)
refreshExtraConnections()
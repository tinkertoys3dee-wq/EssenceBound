

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------
-- THEME (matched to the dark purple / gold-orange / green look)
-------------------------------------------------------------------
local THEME = {
	Background      = Color3.fromRGB(24, 12, 40),
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),   -- gold/orange dividers
	Green           = Color3.fromRGB(58, 209, 118),   -- essence green
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(146, 136, 160),
	Locked          = Color3.fromRGB(58, 50, 76),
	Red             = Color3.fromRGB(230, 80, 90),
}

-------------------------------------------------------------------
-- SMALL HELPERS
-------------------------------------------------------------------

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

local function tween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

-- Generic hover-grow + press-shrink "button feel" animation.
local function applyButtonFeel(button, hoverScale, baseColor, hoverColor, parent, highlight, highlightColor)
	hoverScale = hoverScale or 1.05
	if button:GetAttribute("JuiceFeelApplied") then
		return
	end

	-- Marks this button as already having a bespoke hover animation, so
	-- the global Juice.ButtonFeel pass in UIManagement skips it instead of
	-- layering a second, competing scale animation on top.
	button:SetAttribute("JuiceFeelApplied", true)

	local tweener = parent or button
	local baseSize = tweener.Size

	local function scaled(mult)
		return UDim2.new(
			baseSize.X.Scale * mult, baseSize.X.Offset * mult,
			baseSize.Y.Scale * mult, baseSize.Y.Offset * mult
		)
	end

	-- set up the highlight stroke (hidden by default)
	local highlightStroke
	if highlight then
		highlightStroke = tweener:FindFirstChild("HoverHighlight")
		if not highlightStroke then
			highlightStroke = Instance.new("UIStroke")
			highlightStroke.Name = "HoverHighlight"
			highlightStroke.Thickness = 4
			highlightStroke.Color = highlightColor or THEME.Accent
			highlightStroke.Transparency = 1 -- invisible until hovered
			highlightStroke.Parent = tweener
		end
	end

	button.MouseEnter:Connect(function()
		tween(tweener, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Size = scaled(hoverScale)}):Play()
		if hoverColor then
			tween(tweener, TweenInfo.new(0.15), {BackgroundColor3 = hoverColor}):Play()
		end
		if highlightStroke then
			tween(highlightStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		tween(tweener, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Size = baseSize}):Play()
		if baseColor then
			tween(tweener, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
		end
		if highlightStroke then
			tween(highlightStroke, TweenInfo.new(0.15), {Transparency = 1}):Play()
		end
	end)

	button.MouseButton1Down:Connect(function()
		tween(tweener, TweenInfo.new(0.08), {Size = scaled(hoverScale * 0.9)}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		tween(tweener, TweenInfo.new(0.12), {Size = scaled(hoverScale)}):Play()
	end)
end

-------------------------------------------------------------------
-- OPEN / CLOSE STATE
------------------------------------------------------------------
local popups = {}       -- name -> CanvasGroup

local GUI = playerGui:WaitForChild("EssencePopupUI")

local PopupHolder = GUI:WaitForChild("PopupHolder")

local popupSizes = {}   -- name -> target UDim2 (scale-based)

for _,popup in pairs(PopupHolder:GetChildren()) do
	popups[popup.Name] = popup
	popupSizes[popup.Name] = UDim2.fromScale(popup.Size.X.Scale, popup.Size.Y.Scale)
end
local currentOpen = nil

local OPEN_INFO = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local openPopup, closePopup -- forward declared, bodies assigned further down

local backdrop = GUI:WaitForChild("Backdrop")
-------------------------------------------------------------------
-- OPEN / CLOSE IMPLEMENTATION
-------------------------------------------------------------------
local rbF = popups["RebirthPopup"]:WaitForChild("Content"):WaitForChild("Frame")
local rbD = rbF:FindFirstChild("LargeDisplay"):FindFirstChild("Display"):FindFirstChild("TextLabel")
local RebirthModule = require(game:GetService("ReplicatedStorage"):WaitForChild("RebirthHandler"))
local Earthessence = player:WaitForChild("leaderstats"):WaitForChild("Earth Essence")
local CS = rbF:WaitForChild("CurrentStats")
local RBar = rbF:WaitForChild("Progress")
local unlockTemplate = game:GetService("ReplicatedStorage"):WaitForChild("Cloneables"):WaitForChild("UnlockTemplate")
local milestones = rbF:WaitForChild("Milestones"):WaitForChild("Frame")
local function rebirthUpdates()
	print(player:GetAttribute("Rebirths"))
	local RebirthData = RebirthModule.GetRebirthInfo({rebirthCount = player:GetAttribute("Rebirths"),essence = Earthessence:GetAttribute("Quantity")},player)
	rbD.Text = "Rebirth "..player:GetAttribute("Rebirths")

	CS:FindFirstChild("CurrentMultiplier"):FindFirstChild("Value").Text = RebirthData.currentMultiplier
	CS:FindFirstChild("EssenceNeeded"):FindFirstChild("Value").Text = formatNumber(RebirthData.essenceNeeded)
	CS:FindFirstChild("NextMultiplier"):FindFirstChild("Value").Text = RebirthData.nextMultiplier

	RBar:FindFirstChild("Quantity").Text = formatNumber(RebirthData.essenceCurrent).. " / ".. formatNumber(RebirthData.essenceNeeded)
	RBar:FindFirstChild("Percent").Text = math.clamp(math.floor(RebirthData.essenceCurrent / RebirthData.essenceNeeded * 100),0,100).. "%"
	RBar:FindFirstChild("Frame"):FindFirstChild("Frame").Size = UDim2.new(math.clamp(RebirthData.essenceCurrent / RebirthData.essenceNeeded,0,1),0,1,0)
	
	local milestone = RebirthModule.GetReachedMilestones(player:GetAttribute("Rebirths")) 
	local keys = {}
	for key, _ in pairs(milestone) do
		table.insert(keys, key)
	end

	-- 2. Sort the keys (so they are in a predictable order, e.g., Level1, Level2, Level3)
	table.sort(keys)

	-- 3. Grab the last sorted key
	local lastKey = #keys
	for _, child in pairs(milestones:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "Frame" then
			if child.Name ~= tostring(lastKey) then
				child.BackgroundColor3 = Color3.fromRGB(58, 50, 78)
				child:FindFirstChild("UIStroke").Color = Color3.fromRGB(148,136,160)
			else
				child.BackgroundColor3 = Color3.fromRGB(58, 209, 118)
				child:FindFirstChild("UIStroke").Color = Color3.fromRGB(247,165,60)
			end
		end
	end
	if not RebirthData.nextRebirthUnlocks then
		RebirthData.nextRebirthUnlocks = {["NextRegular Bonus"] =  RebirthModule.CalculateMultiplier(player:GetAttribute("Rebirths") + 1)}
	end
	
	for _, child in rbF:FindFirstChild("Unlocks"):FindFirstChild("Frame"):GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for name,v in pairs(RebirthData.nextRebirthUnlocks)  do

		if name == "essenceMultiplierBonus"  then
			local clone = unlockTemplate:Clone()
			clone.Parent = rbF:FindFirstChild("Unlocks"):FindFirstChild("Frame")
			clone:FindFirstChild("TextLabel").Text = "+"..tostring(v * 100).. "% Boost Perm"
		end
		if name == "upgradesUnlocked" then
			local clone = unlockTemplate:Clone()
			clone.Parent = rbF:FindFirstChild("Unlocks"):FindFirstChild("Frame")
			clone:FindFirstChild("TextLabel").Text = v[1]
		end
		if name == "NextRegular Bonus" then
			local clone = unlockTemplate:Clone()
			clone.Parent = rbF:FindFirstChild("Unlocks"):FindFirstChild("Frame")
			clone:FindFirstChild("TextLabel").Text = v.."x Multiplier"
		end
	end
end

closePopup = function(name)
	local popup = popups[name]
	if not popup or not popup.Visible then return end

	local targetSize = popupSizes[name]
	local shrunk = UDim2.fromScale(targetSize.X.Scale * 0.85, targetSize.Y.Scale * 0.85)

	local sizeTween = tween(popup, CLOSE_INFO, {Size = shrunk, GroupTransparency = 1})
	sizeTween:Play()
	tween(backdrop, CLOSE_INFO, {BackgroundTransparency = 1}):Play()

	if currentOpen == name then
		currentOpen = nil
	end

	sizeTween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and popup.GroupTransparency >= 0.99 then
			popup.Visible = false
			if currentOpen == nil then
				backdrop.Visible = false
			end
		end
	end)
end

openPopup = function(name)
	local popup = popups[name]
	if not popup then return end
	if currentOpen == name then return end
	if currentOpen then
		closePopup(currentOpen)
	end
	currentOpen = name

	local targetSize = popupSizes[name]
	popup.Size = UDim2.fromScale(targetSize.X.Scale * 0.8, targetSize.Y.Scale * 0.8)
	popup.GroupTransparency = 1
	popup.Visible = true
	backdrop.Visible = true

	tween(popup, OPEN_INFO, {Size = targetSize, GroupTransparency = 0}):Play()
	tween(backdrop, TweenInfo.new(0.25), {BackgroundTransparency = 0.45}):Play()
	
	if name == "RebirthPopup" then
		rebirthUpdates()
	end
end

player.AttributeChanged:Connect(function(attribute)
	if attribute == "Rebirths" then
		rebirthUpdates()
	end
end)
	
backdrop.Activated:Connect(function()
	if currentOpen then
		closePopup(currentOpen)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Escape and currentOpen then
		closePopup(currentOpen)
	end
end)

_G.PopupUI = {
	Open = function(name) openPopup(name) end,
	Close = function(name) closePopup(name) end,
}

-------------------------------------------------------------------
-- MAIN NAVIGATION
--
-- The visual buttons live in Studio, but their exact wrapper shape is not
-- guaranteed by syncback: some are Frames containing a TextButton, while a
-- replacement may be a GuiButton directly. Resolve either shape and route by
-- a normalized name so a harmless "Button" suffix never breaks the menu.
-------------------------------------------------------------------

local OGUI = playerGui:WaitForChild("MainGui")
local right = OGUI:WaitForChild("Right"):WaitForChild('Holder')

local NAV_POPUPS = {
	upgrades = "UpgradesPopup",
	rebirth = "RebirthPopup",
	index = "IndexPopup",
	inventory = "InventoryPopup",
	settings = "SettingsPopup",
}

local function navKey(name)
	return string.lower(tostring(name)):gsub("button", ""):gsub("%s+", "")
end

local function resolveNavTrigger(container)
	if container:IsA("GuiButton") then
		return container
	end
	return container:FindFirstChildWhichIsA("TextButton", true)
		or container:FindFirstChildWhichIsA("ImageButton", true)
end

for _, container in pairs(right:GetChildren()) do
	if container.Name ~= "Divider" and container:IsA("GuiObject") then
		local trigger = resolveNavTrigger(container)
		local key = navKey(container.Name)
		if trigger then
			applyButtonFeel(trigger, 1.03, nil, nil, container, true)

			if key == "shop" then
				-- MonetizationStore uses this same tag. Whichever script starts
				-- first owns the single click connection, preventing the legacy
				-- ShopPopup and the new market from opening on top of each other.
				if not trigger:GetAttribute("EssenceMarketBound") then
					trigger:SetAttribute("EssenceMarketBound", true)
					trigger.Activated:Connect(function()
						local market = _G.EssenceboundStore
						if market and market.Open then
							market.Open()
						else
							openPopup("ShopPopup")
						end
					end)
				end
			elseif key ~= "zones" then
				-- ZonePanel owns the Zones trigger because its panel is built in
				-- code rather than living in PopupHolder.
				local popupName = NAV_POPUPS[key]
				if popupName then
					trigger.Activated:Connect(function()
						openPopup(popupName)
					end)
				end
			end
		end
	end
end

for _, btn in pairs(PopupHolder:GetChildren()) do
	local titleBar = btn:FindFirstChild("TitleBar")
	local btn2 = titleBar and titleBar:FindFirstChild("CloseButton")
	if btn2 and btn2:IsA("GuiButton") then
		applyButtonFeel(btn2, 1.03)
		btn2.Activated:Connect(function()
			closePopup(btn.Name)
		end)
	end
end

local Left = OGUI:WaitForChild("Left")
local PlayerInfo = Left:WaitForChild("Currencys"):WaitForChild("Player")

local name = PlayerInfo:WaitForChild("Name")
local Icon = PlayerInfo:WaitForChild("Icon")

-- VIP can be bought while this session is already running. Previously its
-- gold identity treatment was checked only once during script startup, so a
-- successful purchase appeared to do nothing until the next join.
local VIP_PASS_ID = 1909291891
local nameStroke = name:WaitForChild("UIStroke")
local iconStroke = Icon:WaitForChild("UIStroke")
local defaultNameStrokeColor = nameStroke.Color
local defaultIconStrokeColor = iconStroke.Color

local function refreshVipTreatment()
	local ownsVip = player:GetAttribute(MonetizationConfig.GetOwnershipAttribute(VIP_PASS_ID)) == true
	nameStroke.Color = ownsVip and Color3.fromRGB(255, 215, 0) or defaultNameStrokeColor
	iconStroke.Color = ownsVip and Color3.fromRGB(255, 215, 0) or defaultIconStrokeColor
end

player:GetAttributeChangedSignal(MonetizationConfig.GetOwnershipAttribute(VIP_PASS_ID)):Connect(refreshVipTreatment)
refreshVipTreatment()
Icon.Image = game:GetService("Players"):GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
name.Text = player.DisplayName

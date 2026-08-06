--[[
	OfflineEssenceReward.client.lua

	PURPOSE:
	Listens for a RemoteEvent fired by the server containing a dictionary of
	essence rewards earned while the player was offline, e.g:

		{
			["Earth Essence"] = 60,
			["Fire Essence"]  = 12,
			["Rare Essence"]  = 3,
		}

	...and displays a themed popup (matching the dark purple / gold UI style)
	listing each reward with an icon, name, and formatted amount, a running
	total, and a UI "pop" sound on open.

	INSTALL:
	- Place this LocalScript in StarterPlayerScripts (or StarterGui).
	- Create a RemoteEvent named "OfflineEssenceReward" inside ReplicatedStorage.
	- Make sure SoundService has this hierarchy: SoundService.SFX.UI.UIPop (a Sound instance).
	- Fire the remote from the server like:
		game.ReplicatedStorage.OfflineEssenceReward:FireClient(player, rewardTable)

	NOTE ON SCALING:
	Every UI element uses UDim2.fromScale (or the scale component of UDim2.new)
	— there is NO use of offsets anywhere, so this scales proportionally on
	any screen/device, matching how the rest of your interface is built.
]]

--// SERVICES
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local SoundService       = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

--// REMOTE EVENT
local OfflineEssenceRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OfflineEssenceReward")

--// SOUND (SoundService.SFX.UI.UIPop)
local uiPopSound do
	local ok, sfxFolder = pcall(function() return SoundService:WaitForChild("SFX", 5) end)
	if ok and sfxFolder then
		local uiFolder = sfxFolder:WaitForChild("UI", 5)
		if uiFolder then
			uiPopSound = uiFolder:WaitForChild("UIPop", 5)
		end
	end
end

local function playPopSound()
	if uiPopSound and uiPopSound:IsA("Sound") then
		-- Restart from the beginning in case it's already mid-playback
		uiPopSound.TimePosition = 0
		uiPopSound:Play()
	end
end

--=========================================================================
-- THEME CONSTANTS (pulled to match your screenshot's palette)
--=========================================================================
local THEME = {
	Backdrop         = Color3.fromRGB(5, 2, 12),
	PanelTop         = Color3.fromRGB(40, 19, 60),
	PanelMid         = Color3.fromRGB(26, 13, 44),
	PanelBottom      = Color3.fromRGB(16, 7, 28),
	Gold             = Color3.fromRGB(245, 166, 35),
	GoldBright       = Color3.fromRGB(255, 210, 120),
	GoldDim          = Color3.fromRGB(140, 95, 25),
	RowBackground    = Color3.fromRGB(50, 27, 75),
	RowBackgroundAlt = Color3.fromRGB(41, 21, 63),
	TotalRowBg       = Color3.fromRGB(28, 45, 35),
	Green            = Color3.fromRGB(65, 215, 125),
	GreenBright      = Color3.fromRGB(150, 255, 180),
	GreenDark        = Color3.fromRGB(28, 135, 78),
	White            = Color3.fromRGB(255, 255, 255),
	SoftWhite        = Color3.fromRGB(222, 210, 235),
	MutedLavender    = Color3.fromRGB(175, 155, 200),
	Black            = Color3.fromRGB(0, 0, 0),
	Red              = Color3.fromRGB(205, 60, 60),
	RedBright        = Color3.fromRGB(235, 90, 90),
}

-- Fallback color palette for essence icons keyed by keyword found in the name.
-- Add more keywords as your game grows (matches "Fire Essence", "Earth Essence" etc).
local ESSENCE_COLOR_KEYWORDS = {
	Fire   = Color3.fromRGB(255, 94, 58),
	Earth  = Color3.fromRGB(120, 200, 80),
	Water  = Color3.fromRGB(70, 160, 255),
	Ice    = Color3.fromRGB(150, 230, 255),
	Wind   = Color3.fromRGB(190, 240, 210),
	Storm  = Color3.fromRGB(255, 230, 90),
	Rare   = Color3.fromRGB(90, 160, 255),
	Void   = Color3.fromRGB(150, 70, 210),
	Light  = Color3.fromRGB(255, 250, 200),
	Dark   = Color3.fromRGB(90, 40, 120),
	Gold   = Color3.fromRGB(255, 200, 60),
}

local DEFAULT_ICON_COLOR = Color3.fromRGB(120, 220, 150) -- matches the green orb in your screenshot

--=========================================================================
-- HELPER: format large numbers the same way your HUD does (137.46K style)
--=========================================================================
local function formatAmount(n)
	n = tonumber(n) or 0
	local suffixes = {
		{1e12, "T"},
		{1e9,  "B"},
		{1e6,  "M"},
		{1e3,  "K"},
	}
	for _, data in ipairs(suffixes) do
		local threshold, suffix = data[1], data[2]
		if n >= threshold then
			return string.format("%.2f%s", n / threshold, suffix)
		end
	end
	if n == math.floor(n) then
		return tostring(n)
	end
	return string.format("%.2f", n)
end

-- Picks an icon color for a given essence name by scanning for known keywords
local function getIconColor(essenceName)
	local lowered = string.lower(essenceName)
	for keyword, color in pairs(ESSENCE_COLOR_KEYWORDS) do
		if string.find(lowered, string.lower(keyword)) then
			return color
		end
	end
	return DEFAULT_ICON_COLOR
end

--=========================================================================
-- HELPER: small UI builder utilities (keeps everything scale-based)
--=========================================================================
local function corner(instance, radiusScale)
	local uic = Instance.new("UICorner")
	uic.CornerRadius = UDim.new(radiusScale or 0.15, 0)
	uic.Parent = instance
	return uic
end

local function stroke(instance, color, thickness, transparency)
	local uis = Instance.new("UIStroke")
	uis.Color = color or THEME.Gold
	uis.Thickness = thickness or 2
	uis.Transparency = transparency or 0
	uis.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	uis.Parent = instance
	return uis
end

local function gradient(instance, colorSequence, rotation)
	local grad = Instance.new("UIGradient")
	grad.Color = colorSequence
	grad.Rotation = rotation or 90
	grad.Parent = instance
	return grad
end

local function textOutline(label, thicknessTransparency)
	label.TextStrokeTransparency = thicknessTransparency or 0
	label.TextStrokeColor3 = THEME.Black
end

local function padding(instance, top, bottom, left, right)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(top or 0, 0)
	pad.PaddingBottom = UDim.new(bottom or 0, 0)
	pad.PaddingLeft = UDim.new(left or 0, 0)
	pad.PaddingRight = UDim.new(right or 0, 0)
	pad.Parent = instance
	return pad
end

--=========================================================================
-- BUILD: ScreenGui + Backdrop
--=========================================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OfflineEssenceGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Enabled = false
screenGui.Parent = PlayerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Position = UDim2.fromScale(0, 0)
backdrop.BackgroundColor3 = THEME.Backdrop
backdrop.BackgroundTransparency = 1 -- fades in on open
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Active = true -- blocks click-through to the game world
backdrop.Parent = screenGui

--=========================================================================
-- BUILD: Main Popup Panel
--=========================================================================
-- Slightly larger than before, and internal content gets its own inset
-- padding so nothing (icons, text, rows) ever touches or clips the edges.
local POPUP_TARGET_SIZE = UDim2.fromScale(0.4, 0.62)

local popup = Instance.new("Frame")
popup.Name = "PopupPanel"
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.Position = UDim2.fromScale(0.5, 0.5)
popup.Size = UDim2.fromScale(0, 0) -- animated to full size on open
popup.BackgroundColor3 = THEME.PanelBottom
popup.BorderSizePixel = 0
popup.ClipsDescendants = true
popup.ZIndex = 2
popup.Parent = backdrop

corner(popup, 0.035)
stroke(popup, THEME.Gold, 3, 0)
gradient(popup, ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.PanelTop),
	ColorSequenceKeypoint.new(0.5, THEME.PanelMid),
	ColorSequenceKeypoint.new(1, THEME.PanelBottom),
}), 90)

-- Inner content wrapper — this is what actually holds every element below,
-- inset from the popup's edges so nothing can ever clip the rounded border.
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.fromScale(1, 1)
content.BackgroundTransparency = 1
content.ZIndex = 2
content.Parent = popup
padding(content, 0.07, 0.07, 0.07, 0.07)

--=========================================================================
-- BUILD: decorative corner accents (small gold marks, top-left / top-right)
--=========================================================================
local function cornerAccent(anchorX)
	local accent = Instance.new("Frame")
	accent.Name = "CornerAccent"
	accent.AnchorPoint = Vector2.new(anchorX, 0)
	accent.Position = UDim2.fromScale(anchorX == 0 and 0.02 or 0.98, 0.02)
	accent.Size = UDim2.fromScale(0.05, 0.008)
	accent.BackgroundColor3 = THEME.Gold
	accent.BorderSizePixel = 0
	accent.ZIndex = 3
	accent.Parent = popup
	corner(accent, 0.5)
	return accent
end
cornerAccent(0)
cornerAccent(1)

--=========================================================================
-- BUILD: Header (icon + title + subtitle)
--=========================================================================
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.fromScale(1, 0.24)
header.Position = UDim2.fromScale(0, 0)
header.BackgroundTransparency = 1
header.ZIndex = 3
header.Parent = content

local headerIconRing = Instance.new("Frame")
headerIconRing.Name = "IconRing"
headerIconRing.AnchorPoint = Vector2.new(0.5, 0)
headerIconRing.Position = UDim2.fromScale(0.5, 0.02)
headerIconRing.Size = UDim2.fromScale(0.2, 0.5)
headerIconRing.BackgroundColor3 = THEME.Green
headerIconRing.ZIndex = 3
headerIconRing.Parent = header
corner(headerIconRing, 0.5)
stroke(headerIconRing, THEME.Gold, 3, 0)
gradient(headerIconRing, ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.GreenBright),
	ColorSequenceKeypoint.new(1, THEME.GreenDark),
}), 90)

-- Soft outer glow ring behind the icon (subtle pulsing halo)
local glowRing = Instance.new("Frame")
glowRing.Name = "GlowRing"
glowRing.AnchorPoint = Vector2.new(0.5, 0.5)
glowRing.Position = UDim2.fromScale(0.5, 0.5)
glowRing.Size = UDim2.fromScale(1.35, 1.35)
glowRing.BackgroundColor3 = THEME.Green
glowRing.BackgroundTransparency = 0.75
glowRing.BorderSizePixel = 0
glowRing.ZIndex = 2
glowRing.Parent = headerIconRing
corner(glowRing, 0.5)

local headerIconGlyph = Instance.new("ImageLabel")
headerIconGlyph.Name = "Glyph"
headerIconGlyph.Size = UDim2.fromScale(1, 1)
headerIconGlyph.BackgroundTransparency = 1
headerIconGlyph.Image = "rbxassetid://72641569769631" -- ✧ placeholder glyph; swap for an ImageLabel + rbxassetid if you have icon art
headerIconGlyph.ScaleType = Enum.ScaleType.Fit
headerIconGlyph.Parent = headerIconRing
headerIconGlyph.ZIndex = 10

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.fromScale(1, 0.24)
title.Position = UDim2.fromScale(0, 0.56)
title.BackgroundTransparency = 1
title.Text = "WELCOME BACK!"
title.Font = Enum.Font.GothamBlack
title.TextColor3 = THEME.White
title.TextScaled = true
title.ZIndex = 3
title.Parent = header
textOutline(title)

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.fromScale(1, 0.16)
subtitle.Position = UDim2.fromScale(0, 0.82)
subtitle.BackgroundTransparency = 1
subtitle.Text = "Here's what you earned while away"
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextColor3 = THEME.SoftWhite
subtitle.TextScaled = true
subtitle.ZIndex = 3
subtitle.Parent = header

-- Divider line under header
local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.Size = UDim2.fromScale(1, 0.004)
divider.Position = UDim2.fromScale(0, 0.245)
divider.BackgroundColor3 = THEME.Gold
divider.BackgroundTransparency = 0.25
divider.BorderSizePixel = 0
divider.ZIndex = 3
divider.Parent = content
gradient(divider, ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.Gold),
	ColorSequenceKeypoint.new(0.1, THEME.Gold),
	ColorSequenceKeypoint.new(0.5, THEME.GoldBright),
	ColorSequenceKeypoint.new(0.9, THEME.Gold),
	ColorSequenceKeypoint.new(1, THEME.Gold),
}), 0)

--=========================================================================
-- BUILD: Close (X) Button — inset well away from the rounded corner
--=========================================================================
local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.fromScale(1, 0.01)
closeButton.Size = UDim2.fromScale(0.09, 0.065)
closeButton.BackgroundColor3 = THEME.Red
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.TextColor3 = THEME.White
closeButton.AutoButtonColor = false
closeButton.ZIndex = 5
closeButton.Parent = content
corner(closeButton, 0.3)
stroke(closeButton, THEME.Gold, 2, 0.2)
textOutline(closeButton)

--=========================================================================
-- BUILD: Scrolling reward list
--   Inset further from the sides than before (extra left/right padding)
--   so long essence names / large amount numbers never clip the panel edge.
--=========================================================================
local listContainer = Instance.new("Frame")
listContainer.Name = "ListContainer"
listContainer.Size = UDim2.fromScale(1, 0.5)
listContainer.Position = UDim2.fromScale(0, 0.27)
listContainer.BackgroundTransparency = 1
listContainer.ZIndex = 3
listContainer.Parent = content

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name = "RewardScroll"
scrollFrame.Size = UDim2.fromScale(1, 1)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.ScrollBarThickness = 6
scrollFrame.ScrollBarImageColor3 = THEME.Gold
scrollFrame.ScrollBarImageTransparency = 0.2
scrollFrame.CanvasSize = UDim2.fromScale(0, 0) -- auto-updated via AutomaticCanvasSize
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.ZIndex = 3
scrollFrame.Parent = listContainer
-- Extra right padding keeps rows clear of the scrollbar; extra top/bottom
-- stops the first/last row's stroke from touching the container edge.
padding(scrollFrame, 0.1, 0.1, 0.1, 0.1)


local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0.03, 0)
listLayout.Parent = scrollFrame

--=========================================================================
-- BUILD: Total summary row (sits below the scroll list, above the button)
--=========================================================================
local totalRow = Instance.new("Frame")
totalRow.Name = "TotalRow"
totalRow.Size = UDim2.fromScale(1, 0.09)
totalRow.Position = UDim2.fromScale(0, 0.725)
totalRow.BackgroundColor3 = THEME.TotalRowBg
totalRow.BorderSizePixel = 0
totalRow.ZIndex = 3
totalRow.Parent = content
corner(totalRow, 0.3)
stroke(totalRow, THEME.Green, 1.5, 0.4)
padding(totalRow, 0, 0, 0.06, 0.06)

local totalLabel = Instance.new("TextLabel")
totalLabel.Name = "TotalLabel"
totalLabel.Size = UDim2.fromScale(0.6, 1)
totalLabel.Position = UDim2.fromScale(0, 0)
totalLabel.BackgroundTransparency = 1
totalLabel.Text = "Total Essence"
totalLabel.Font = Enum.Font.GothamBold
totalLabel.TextColor3 = THEME.MutedLavender
totalLabel.TextScaled = true
totalLabel.TextXAlignment = Enum.TextXAlignment.Left
totalLabel.ZIndex = 4
totalLabel.Parent = totalRow
textOutline(totalLabel, 0.5)

local totalAmountLabel = Instance.new("TextLabel")
totalAmountLabel.Name = "TotalAmountLabel"
totalAmountLabel.AnchorPoint = Vector2.new(1, 0)
totalAmountLabel.Size = UDim2.fromScale(0.4, 1)
totalAmountLabel.Position = UDim2.fromScale(1, 0)
totalAmountLabel.BackgroundTransparency = 1
totalAmountLabel.Text = "+0"
totalAmountLabel.Font = Enum.Font.GothamBlack
totalAmountLabel.TextColor3 = THEME.Green
totalAmountLabel.TextScaled = true
totalAmountLabel.TextXAlignment = Enum.TextXAlignment.Right
totalAmountLabel.ZIndex = 4
totalAmountLabel.Parent = totalRow
textOutline(totalAmountLabel)

--=========================================================================
-- BUILD: Claim Button (bottom, safely inset from the bottom edge)
--=========================================================================
local claimButton = Instance.new("TextButton")
claimButton.Name = "ClaimButton"
claimButton.AnchorPoint = Vector2.new(0.5, 1)
claimButton.Position = UDim2.fromScale(0.5, 1)
claimButton.Size = UDim2.fromScale(0.62, 0.105)
claimButton.BackgroundColor3 = THEME.GreenDark
claimButton.Text = "CLAIM REWARDS"
claimButton.Font = Enum.Font.GothamBlack
claimButton.TextScaled = true
claimButton.TextColor3 = THEME.White
claimButton.AutoButtonColor = false
claimButton.ZIndex = 3
claimButton.Parent = content
corner(claimButton, 0.25)
stroke(claimButton, THEME.Gold, 3, 0)
gradient(claimButton, ColorSequence.new({
	ColorSequenceKeypoint.new(0, THEME.Green),
	ColorSequenceKeypoint.new(1, THEME.GreenDark),
}), 90)
textOutline(claimButton)

--=========================================================================
-- FUNCTION: Build a single reward row inside the scroll frame
--=========================================================================
local function createRewardRow(essenceName, amount, layoutOrder)
	local row = Instance.new("Frame")
	row.Name = essenceName .. "_Row"
	row.Size = UDim2.fromScale(1, 0.28)
	row.BackgroundColor3 = (layoutOrder % 2 == 0) and THEME.RowBackground or THEME.RowBackgroundAlt
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.ZIndex = 4
	row.BackgroundTransparency = 1 -- animated in
	row.Parent = scrollFrame
	corner(row, 0.28)
	stroke(row, THEME.GoldDim, 1, 0.4)
	-- Internal padding keeps the icon/name/amount clear of the row's own
	-- rounded edges and stroke, in addition to the outer list padding.
	padding(row, 0, 0, 0.03, 0.04)

	-- Icon circle
	local iconCircle = Instance.new("Frame")
	iconCircle.Name = "IconCircle"
	iconCircle.AnchorPoint = Vector2.new(0, 0.5)
	iconCircle.Position = UDim2.fromScale(0, 0.5)
	iconCircle.Size = UDim2.fromScale(0.16, 0.78)
	iconCircle.BackgroundColor3 = getIconColor(essenceName)
	iconCircle.ZIndex = 5
	iconCircle.Parent = row
	corner(iconCircle, 0.5)
	stroke(iconCircle, THEME.Gold, 2, 0.1)
	gradient(iconCircle, ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.18, getIconColor(essenceName)),
		ColorSequenceKeypoint.new(1, getIconColor(essenceName)),
	}), 45)

	local iconGlyph = Instance.new("ImageLabel")
	iconGlyph.Size = UDim2.fromScale(1, 1)
	iconGlyph.BackgroundTransparency = 1
	iconGlyph.Image = "rbxassetid://72641569769631"
	iconGlyph.ScaleType = Enum.ScaleType.Fit
	iconGlyph.ZIndex = 6
	iconGlyph.Parent = iconCircle

	-- Essence name label (given generous width + left offset from icon)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.fromScale(0.22, 0.5)
	nameLabel.Size = UDim2.fromScale(0.44, 0.65)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = essenceName
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = THEME.White
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 5
	nameLabel.Parent = row
	textOutline(nameLabel)

	-- Amount label ("+1.23K" style, green like your currency display),
	-- pulled inward from the right edge so big numbers don't clip.
	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.AnchorPoint = Vector2.new(1, 0.5)
	amountLabel.Position = UDim2.fromScale(1, 0.5)
	amountLabel.Size = UDim2.fromScale(0.32, 0.65)
	amountLabel.BackgroundTransparency = 1
	amountLabel.Text = "+" .. formatAmount(amount)
	amountLabel.Font = Enum.Font.GothamBlack
	amountLabel.TextColor3 = THEME.Green
	amountLabel.TextScaled = true
	amountLabel.TextXAlignment = Enum.TextXAlignment.Right
	amountLabel.ZIndex = 5
	amountLabel.Parent = row
	textOutline(amountLabel)

	return row
end

--=========================================================================
-- FUNCTION: Populate the popup with a reward dictionary
--=========================================================================
local function populateRewards(rewardTable)
	-- Clear any old rows first
	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Sort keys alphabetically for consistent, predictable ordering
	local sortedNames = {}
	for essenceName in pairs(rewardTable) do
		table.insert(sortedNames, essenceName)
	end
	table.sort(sortedNames)

	local rows = {}
	local runningTotal = 0
	local order = 1
	for _, essenceName in ipairs(sortedNames) do
		local amount = tonumber(rewardTable[essenceName]) or 0
		runningTotal += amount
		local row = createRewardRow(essenceName, amount, order)
		table.insert(rows, row)
		order += 1
	end

	-- Update the subtitle with a count of how many essence types were earned
	local typeCount = #sortedNames
	subtitle.Text = string.format(
		"You earned %d essence type%s while away",
		typeCount,
		typeCount == 1 and "" or "s"
	)

	-- Update the total summary row
	totalAmountLabel.Text = "+" .. formatAmount(runningTotal)

	return rows
end

--=========================================================================
-- FUNCTION: Open / Close animations
--=========================================================================
local isOpen = false
local glowTween

local function startGlowPulse()
	if glowTween then
		glowTween:Cancel()
	end
	glowRing.BackgroundTransparency = 0.75
	glowTween = TweenService:Create(
		glowRing,
		TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.35 }
	)
	glowTween:Play()
end

local function stopGlowPulse()
	if glowTween then
		glowTween:Cancel()
		glowTween = nil
	end
end

local function animateRowsIn(rows)
	for i, row in ipairs(rows) do
		row.BackgroundTransparency = 1
		task.delay((i - 1) * 0.06, function()
			if row and row.Parent then
				TweenService:Create(row, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0,
				}):Play()
			end
		end)
	end
end

local function openPopup(rewardTable)
	if isOpen then return end
	isOpen = true

	screenGui.Enabled = true
	local rows = populateRewards(rewardTable)

	-- Reset animated properties
	backdrop.BackgroundTransparency = 1
	popup.Size = UDim2.fromScale(0, 0)
	totalRow.BackgroundTransparency = 1

	-- Play the UI pop sound right as the popup begins animating in
	playPopSound()

	-- Fade in backdrop
	TweenService:Create(backdrop, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 0.45,
	}):Play()

	-- Pop the panel in with a "Back" easing for a satisfying bounce
	TweenService:Create(popup, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = POPUP_TARGET_SIZE,
	}):Play()

	-- Fade in the total row slightly after the rows finish staggering
	task.delay(0.15 + (#rows * 0.06), function()
		if isOpen then
			TweenService:Create(totalRow, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {
				BackgroundTransparency = 0,
			}):Play()
		end
	end)

	animateRowsIn(rows)
	startGlowPulse()
end

local function closePopup()
	if not isOpen then return end
	isOpen = false

	stopGlowPulse()

	local closeTween = TweenService:Create(popup, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.fromScale(0, 0),
	})
	local backdropTween = TweenService:Create(backdrop, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		BackgroundTransparency = 1,
	})

	closeTween:Play()
	backdropTween:Play()

	closeTween.Completed:Connect(function()
		screenGui.Enabled = false
	end)
end

--=========================================================================
-- BUTTON HOOKUPS
--=========================================================================
closeButton.MouseButton1Click:Connect(closePopup)
claimButton.MouseButton1Click:Connect(closePopup)

-- Hover / press feedback for the claim button
claimButton.MouseEnter:Connect(function()
	TweenService:Create(claimButton, TweenInfo.new(0.15), {BackgroundColor3 = THEME.Green}):Play()
end)
claimButton.MouseLeave:Connect(function()
	TweenService:Create(claimButton, TweenInfo.new(0.15), {BackgroundColor3 = THEME.GreenDark}):Play()
end)
claimButton.MouseButton1Down:Connect(function()
	TweenService:Create(claimButton, TweenInfo.new(0.08), {Size = UDim2.fromScale(0.6, 0.1)}):Play()
end)
claimButton.MouseButton1Up:Connect(function()
	TweenService:Create(claimButton, TweenInfo.new(0.08), {Size = UDim2.fromScale(0.62, 0.105)}):Play()
end)

-- Hover feedback for the close button
closeButton.MouseEnter:Connect(function()
	TweenService:Create(closeButton, TweenInfo.new(0.15), {BackgroundColor3 = THEME.RedBright}):Play()
end)
closeButton.MouseLeave:Connect(function()
	TweenService:Create(closeButton, TweenInfo.new(0.15), {BackgroundColor3 = THEME.Red}):Play()
end)

--=========================================================================
-- REMOTE EVENT HOOKUP
--=========================================================================
-- Server should fire like:
--   OfflineEssenceRemote:FireClient(player, {
--       ["Earth Essence"] = 60,
--       ["Fire Essence"] = 12,
--   })
OfflineEssenceRemote.OnClientEvent:Connect(function(rewardTable)
	if typeof(rewardTable) ~= "table" then
		warn("[OfflineEssenceReward] Expected a table of rewards, got:", typeof(rewardTable))
		return
	end

	-- Guard against an empty table (nothing earned while offline)
	local hasEntries = false
	for _ in pairs(rewardTable) do
		hasEntries = true
		break
	end
	if not hasEntries then
		return
	end

	openPopup(rewardTable)
end)
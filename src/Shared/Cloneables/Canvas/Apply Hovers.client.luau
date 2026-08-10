--[[
	UpgradeTooltip.client.lua

	Mouse-following tooltip for a skill/upgrade tree.
	Drop this in StarterPlayerScripts (or StarterGui) as a LocalScript.

	SCALE VS OFFSET NOTE
	----------------------
	Every width and X-position below is UDim2 Scale so the tooltip resizes
	proportionally across resolutions/devices. Row HEIGHTS stay in Offset
	(pixels) on purpose: the description/stats section uses AutomaticSize.Y
	to fit variable-length text, and a child can't be sized in Scale of a
	parent whose own size is being *determined by* that child -- that's a
	circular dependency Roblox can't resolve (parent needs child's height,
	child needs parent's height). Text rows are only ever a handful of
	pixels tall regardless of resolution anyway, so this doesn't hurt
	readability.

	TEXTSCALED NOTE
	-----------------
	TextScaled and AutomaticSize fight each other if put on the SAME
	instance's growth axis: AutomaticSize wants the box to grow to fit the
	text, TextScaled wants the font to grow/shrink to fill the box -- with
	variable-length text that's a feedback loop with no stable answer
	(this is what was blowing the tooltip out of proportion). So:
	  - Every label whose box has a FIXED height (header/footer/stat rows,
	    the glyph badge) safely uses TextScaled, because the box size
	    never depends on the text.
	  - `descLabel` is the one label that must grow vertically with its
	    content (AutomaticSize.Y), so it keeps a normal fixed TextSize +
	    TextWrapped instead of TextScaled.
	  - UITextSizeConstraint is added to the TextScaled labels so an
	    unusually short/long string can't scale to something illegibly
	    tiny or comically large -- that's the other common way
	    TextScaled looks "broken" even without a hard crash-loop.

	The one thing that MUST stay in raw pixels is the tooltip's on-screen
	Position, since UserInputService:GetMouseLocation() always returns
	pixel coordinates -- there's no "Scale" equivalent for cursor location.
	The follow-offset itself, though, is computed as a fraction of the
	viewport rather than a hardcoded pixel padding.

	HOW IT FINDS YOUR NODES
	------------------------
	Any GuiObject (ImageButton/ImageLabel/Frame, etc.) tagged with the
	CollectionService tag "UpgradeNode" is treated as a hoverable upgrade.

		local CollectionService = game:GetService("CollectionService")
		CollectionService:AddTag(hexIcon, "UpgradeNode")

	HOW EACH NODE DESCRIBES ITSELF
	--------------------------------
	Set these Attributes on the node instance (Properties > Attributes):

		Category      (string)  -- one of the keys in CATEGORY_THEME below
		Stats         (string)  -- optional, newline-separated "Label: Value"
		Cost          (number)  -- optional
		Tier          (number)  -- optional
		Unlocked      (boolean) -- optional, greys out tooltip if false
		Requires      (string)  -- optional, prerequisite shown if locked

	Name/Description/Branch come from ReplicatedStorage.TreeUpgrades,
	keyed by node.Name.
]]

local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local treeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))

--============================================================
-- CATEGORY THEMES
--============================================================
local CATEGORY_THEME = {
	Defense = { Color = Color3.fromRGB(97, 199, 110), Glyph = "🛡", Label = "Defense" },
	Criticals = { Color = Color3.fromRGB(214, 71, 71), Glyph = "⚔", Label = "Criticals" },
	Shatter = { Color = Color3.fromRGB(224, 138, 63), Glyph = "🔥", Label = "Shatter" },
	Regen = { Color = Color3.fromRGB(178, 102, 214), Glyph = "⏱", Label = "Regen" },
	Storm = { Color = Color3.fromRGB(214, 102, 191), Glyph = "🌀", Label = "Storm" },
	Auto = { Color = Color3.fromRGB(72, 191, 178), Glyph = "💧", Label = "Auto" },
	Collection = { Color = Color3.fromRGB(214, 178, 71), Glyph = "⚙", Label = "Collection" },
	Rebirth = { Color = Color3.fromRGB(62, 161, 191), Glyph = "★", Label = "Rebirth" },
	Core = { Color = Color3.fromRGB(93, 175, 224), Glyph = "✦", Label = "Core" },
	Ultimate = { Color = Color3.fromRGB(224, 138, 63), Glyph = "★", Label = "Ultimate" },
}

local DEFAULT_THEME = {
	Color = Color3.fromRGB(180, 180, 190),
	Glyph = "?",
	Label = "Upgrade",
}

local function getTheme(category)
	return CATEGORY_THEME[category] or DEFAULT_THEME
end

--============================================================
-- BUILD THE TOOLTIP UI
--============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "UpgradeTooltipGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000
screenGui.Parent = playerGui

-- "root" is a plain positioning/sizing wrapper only -- it owns no fill of
-- its own, so there is nothing on it that could ever be drawn in front of
-- (or wash out) the actual content. It just tracks the mouse and reports
-- its resolved size, which the two layers below both key off of.
local root = Instance.new("Frame")
root.Name = "Tooltip"
root.AnchorPoint = Vector2.new(0, 0)
-- Width as a fraction of the screen; height still auto-fits content (see note above).
root.Size = UDim2.new(0.19, 0, 0, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundTransparency = 1
root.BorderSizePixel = 0
root.Visible = false
root.ZIndex = 1000
root.Parent = screenGui

-- Keep the tooltip from becoming unreadably small or absurdly large on
-- extreme aspect ratios, while still being scale-driven day to day.
local rootConstraint = Instance.new("UISizeConstraint")
rootConstraint.MinSize = Vector2.new(200, 0)
rootConstraint.MaxSize = Vector2.new(360, math.huge)
rootConstraint.Parent = root

-- LAYER 1: the visual card -- color, rounded corners, accent border.
-- ZIndex 1 (relative to root's children) guarantees this always draws
-- *behind* Content below, no matter what transparency it's set to.
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(18, 16, 26)
background.BackgroundTransparency = 0.05 -- nice solid card; safe to keep near-opaque
background.BorderSizePixel = 0
background.ZIndex = 1
background.Parent = root

local rootCorner = Instance.new("UICorner")
rootCorner.CornerRadius = UDim.new(0.06, 0)
rootCorner.Parent = background

local rootStroke = Instance.new("UIStroke")
rootStroke.Name = "AccentStroke"
rootStroke.Thickness = 2
rootStroke.Color = DEFAULT_THEME.Color
rootStroke.Transparency = 0
rootStroke.Parent = background

local rootGradient = Instance.new("UIGradient")
rootGradient.Name = "AccentGradient"
rootGradient.Rotation = 90
rootGradient.Color = ColorSequence.new(DEFAULT_THEME.Color, DEFAULT_THEME.Color)
rootGradient.Parent = rootStroke

-- LAYER 2: everything the player actually reads. ZIndex 2 means this is
-- always composited on top of Background, so no fill/opacity choice on
-- the card can ever hide the text or icons living in here.
local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 0, 0)
content.AutomaticSize = Enum.AutomaticSize.Y
content.BackgroundTransparency = 1
content.ZIndex = 2
content.Parent = root

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0.04, 0)
padding.PaddingBottom = UDim.new(0.04, 10)
padding.PaddingLeft = UDim.new(0.045, 0)
padding.PaddingRight = UDim.new(0.045, 0)
padding.Parent = content

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6) -- small fixed gutter between rows; negligible at any res
listLayout.Parent = content

-- Header row: glyph badge + title + category pill
local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 34) -- fixed height -- TextScaled is safe on children of this
header.LayoutOrder = 1
header.Parent = content

local glyphBadge = Instance.new("Frame")
glyphBadge.Name = "GlyphBadge"
glyphBadge.Size = UDim2.new(0.7, 0, .7, 0) -- driven to a circle by the AspectRatio constraint below
glyphBadge.Position = UDim2.fromScale(-.01, 0.15)
glyphBadge.BackgroundColor3 = DEFAULT_THEME.Color
glyphBadge.BackgroundTransparency = 0.15
glyphBadge.Parent = header

local glyphAspect = Instance.new("UIAspectRatioConstraint")
glyphAspect.AspectRatio = 1
glyphAspect.DominantAxis = Enum.DominantAxis.Height
glyphAspect.Parent = glyphBadge

local glyphCorner = Instance.new("UICorner")
glyphCorner.CornerRadius = UDim.new(1, 0)
glyphCorner.Parent = glyphBadge

local glyphLabel = Instance.new("TextLabel")
glyphLabel.Name = "Glyph"
glyphLabel.BackgroundTransparency = 1
glyphLabel.Size = UDim2.fromScale(1, 1)
glyphLabel.Font = Enum.Font.GothamBold
glyphLabel.Text = DEFAULT_THEME.Glyph
glyphLabel.TextScaled = true
glyphLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
glyphLabel.Parent = glyphBadge

-- glyphBadge is a fixed-height circle, so TextScaled is safe here -- this
-- constraint just keeps the emoji from looking oddly tiny/huge at extreme
-- viewport sizes.
local glyphTextConstraint = Instance.new("UITextSizeConstraint")
glyphTextConstraint.MinTextSize = 12
glyphTextConstraint.MaxTextSize = 20
glyphTextConstraint.Parent = glyphLabel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0.16, 0, 0, 0)
titleLabel.Size = UDim2.new(0.84, 0, 0, 18)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "Upgrade Name"
titleLabel.TextScaled = true
titleLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local titleTextConstraint = Instance.new("UITextSizeConstraint")
titleTextConstraint.MinTextSize = 11
titleTextConstraint.MaxTextSize = 16
titleTextConstraint.Parent = titleLabel

local categoryLabel = Instance.new("TextLabel")
categoryLabel.Name = "CategoryPill"
categoryLabel.BackgroundTransparency = 1
categoryLabel.Position = UDim2.new(0.16, 0, 0, 17)
categoryLabel.Size = UDim2.new(0.84, 0, 0, 14)
categoryLabel.Font = Enum.Font.GothamMedium
categoryLabel.Text = "Category"
categoryLabel.TextScaled = true
categoryLabel.TextColor3 = DEFAULT_THEME.Color
categoryLabel.TextXAlignment = Enum.TextXAlignment.Left
categoryLabel.Parent = header

local categoryTextConstraint = Instance.new("UITextSizeConstraint")
categoryTextConstraint.MinTextSize = 9
categoryTextConstraint.MaxTextSize = 12
categoryTextConstraint.Parent = categoryLabel

-- Divider
local divider = Instance.new("Frame")
divider.Name = "Divider"
divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
divider.BackgroundTransparency = 0.9
divider.BorderSizePixel = 0
divider.Size = UDim2.new(1, 0, 0, 1) -- hairline; a Scale height here would round to 0px
divider.LayoutOrder = 2
divider.Parent = content

-- Description: kept OFF TextScaled on purpose -- see TEXTSCALED NOTE at
-- the top. This is the one label that must grow the tooltip vertically
-- with variable-length text, so it uses a fixed TextSize + TextWrapped.
local descLabel = Instance.new("TextLabel")
descLabel.Name = "Description"
descLabel.BackgroundTransparency = 1
descLabel.Size = UDim2.new(1, 0, 0, 0)
descLabel.AutomaticSize = Enum.AutomaticSize.Y
descLabel.Font = Enum.Font.Gotham
descLabel.RichText = true
descLabel.Text = "Description goes here."
descLabel.TextSize = 12
descLabel.TextWrapped = true
descLabel.TextColor3 = Color3.fromRGB(205, 205, 215)
descLabel.TextXAlignment = Enum.TextXAlignment.Left
descLabel.TextYAlignment = Enum.TextYAlignment.Top
descLabel.LayoutOrder = 3
descLabel.Parent = content

-- Stats list container
local statsFrame = Instance.new("Frame")
statsFrame.Name = "Stats"
statsFrame.BackgroundTransparency = 1
statsFrame.Size = UDim2.new(1, 0, 0, 0)
statsFrame.AutomaticSize = Enum.AutomaticSize.Y
statsFrame.LayoutOrder = 4
statsFrame.Parent = content

local statsLayout = Instance.new("UIListLayout")
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.Padding = UDim.new(0, 2)
statsLayout.Parent = statsFrame

-- Footer row: cost + tier
local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.BackgroundTransparency = 1
footer.Size = UDim2.new(1, 0, 0, 16)
footer.LayoutOrder = 5
footer.Parent = content

local costLabel = Instance.new("TextLabel")
costLabel.Name = "Cost"
costLabel.BackgroundTransparency = 1
costLabel.Size = UDim2.new(1, 0, 1, 0)
costLabel.Font = Enum.Font.GothamBold
costLabel.Text = ""
costLabel.TextScaled = true
costLabel.TextColor3 = Color3.fromRGB(230, 220, 150)
costLabel.TextXAlignment = Enum.TextXAlignment.Left
costLabel.Parent = footer

local costTextConstraint = Instance.new("UITextSizeConstraint")
costTextConstraint.MinTextSize = 10
costTextConstraint.MaxTextSize = 13
costTextConstraint.Parent = costLabel

local tierLabel = Instance.new("TextLabel")
tierLabel.Name = "Tier"
tierLabel.BackgroundTransparency = 1
tierLabel.Position = UDim2.new(0.6, 0, 0, 0)
tierLabel.Size = UDim2.new(0.4, 0, 1, 0)
tierLabel.Font = Enum.Font.GothamMedium
tierLabel.Text = ""
tierLabel.TextScaled = true
tierLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
tierLabel.TextXAlignment = Enum.TextXAlignment.Right
tierLabel.Parent = footer

local tierTextConstraint = Instance.new("UITextSizeConstraint")
tierTextConstraint.MinTextSize = 9
tierTextConstraint.MaxTextSize = 12
tierTextConstraint.Parent = tierLabel

-- Locked banner (only shown if Unlocked attribute == false)
local lockedLabel = Instance.new("TextLabel")
lockedLabel.Name = "Locked"
lockedLabel.BackgroundTransparency = 1
lockedLabel.Size = UDim2.new(1, 0, .25,0)
lockedLabel.Font = Enum.Font.GothamBold
lockedLabel.Text = ""
lockedLabel.TextScaled = true
lockedLabel.TextColor3 = Color3.fromRGB(220, 110, 110)
lockedLabel.TextXAlignment = Enum.TextXAlignment.Left
lockedLabel.Visible = false
lockedLabel.LayoutOrder = 6
lockedLabel.Parent = content

local lockedTextConstraint = Instance.new("UITextSizeConstraint")
lockedTextConstraint.MinTextSize = 9
lockedTextConstraint.MaxTextSize = 12
lockedTextConstraint.Parent = lockedLabel

--============================================================
-- HELPERS
--============================================================

local function clearStatRows()
	for _, child in ipairs(statsFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function addStatRow(text)
	local row = Instance.new("TextLabel")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 14) -- fixed height -- safe for TextScaled
	row.Font = Enum.Font.Gotham
	row.Text = "• " .. text
	row.TextScaled = true
	row.TextColor3 = Color3.fromRGB(190, 195, 205)
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Parent = statsFrame

	local rowTextConstraint = Instance.new("UITextSizeConstraint")
	rowTextConstraint.MinTextSize = 9
	rowTextConstraint.MaxTextSize = 12
	rowTextConstraint.Parent = row
end

-- Populate is intentionally side-effect free: the old version connected a
-- new node AttributeChanged listener and a new player AttributeChanged
-- listener every single time the cursor entered a node. A long upgrade-tree
-- session therefore accumulated duplicate callbacks indefinitely. Binding
-- now happens once per node below; this function only paints current state.
local function populateTooltip(node)
	local ok, deets = pcall(treeUpgrades.GetUpgrade, node.Name)
	if not ok or type(deets) ~= "table" then
		return
	end

	local category = node:GetAttribute("Category") or deets.Branch or "Defense"
	local theme = getTheme(category)
	titleLabel.Text = deets.Name
	categoryLabel.Text = deets.Branch or theme.Label
	categoryLabel.TextColor3 = theme.Color
	glyphLabel.Text = theme.Glyph
	glyphBadge.BackgroundColor3 = theme.Color
	rootStroke.Color = theme.Color
	rootGradient.Color = ColorSequence.new(theme.Color, theme.Color:Lerp(Color3.new(1, 1, 1), 0.35))
	descLabel.Text = deets.Description or ""

	clearStatRows()
	local statsText = node:GetAttribute("Stats")
	if statsText and statsText ~= "" then
		for line in tostring(statsText):gmatch("[^\r\n]+") do
			addStatRow(line)
		end
	end

	local tier = math.max(0, math.floor(tonumber(node:GetAttribute("Tier")) or 0))
	local maxLevel = math.max(1, math.floor(tonumber(deets.MaxLevel) or 1))
	local cost = node:GetAttribute("Cost")
	if tier >= maxLevel then
		tierLabel.Text = "★ MAX LEVEL"
		costLabel.Text = "MASTERED"
	else
		local costText = cost ~= nil and tostring(cost) or ""
		costLabel.Text = costText ~= "" and costText or "Cost unavailable"
		tierLabel.Text = ("TIER %d / %d"):format(tier, maxLevel)
	end

	local unlocked = node:GetAttribute("Unlocked") ~= false
	if not unlocked then
		local requires = node:GetAttribute("Requires")
		local requiresText = requires ~= nil and tostring(requires):gsub("^%s*(.-)%s*$", "%1") or ""
		lockedLabel.Text = requiresText ~= "" and ("🔒 REQUIRES: " .. requiresText) or "🔒 LOCKED PATH"
		lockedLabel.Visible = true
		background.BackgroundTransparency = 0.2
		descLabel.TextTransparency = 0.32
	else
		lockedLabel.Visible = false
		background.BackgroundTransparency = 0.035
		descLabel.TextTransparency = 0
	end
end

--============================================================
-- SHOW / HIDE / FOLLOW LOGIC
--============================================================

local currentNode = nil
local fadeTween = nil

local uiScale = Instance.new("UIScale")
uiScale.Scale = 0.9
uiScale.Parent = root

local function showTooltip(node)
	currentNode = node
	populateTooltip(node)
	root.Visible = true

	if fadeTween then
		fadeTween:Cancel()
	end
	uiScale.Scale = 0.9
	fadeTween = TweenService:Create(uiScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	fadeTween:Play()
end

local function hideTooltip(node)
	if currentNode ~= node then
		return
	end
	currentNode = nil
	root.Visible = false
end

-- Follow-offset as a fraction of the viewport instead of a hardcoded pixel
-- value, so the gap between cursor and tooltip stays visually consistent
-- across resolutions.
local PADDING_SCALE = 0.012

local function updatePosition()
	if not root.Visible then
		return
	end
	local mouseLoc = UserInputService:GetMouseLocation()
	local viewportSize = screenGui.AbsoluteSize
	local padding = viewportSize.X * PADDING_SCALE

	local tooltipSize = root.AbsoluteSize
	local x = mouseLoc.X + padding
	local y = mouseLoc.Y + padding

	-- Flip to the left/above if it would overflow the screen edge
	if x + tooltipSize.X > viewportSize.X then
		x = mouseLoc.X - tooltipSize.X - padding
	end
	if y + tooltipSize.Y > viewportSize.Y then
		y = mouseLoc.Y - tooltipSize.Y - padding
	end

	-- Position must stay in pixel offset: GetMouseLocation() has no Scale
	-- equivalent, so this is the one spot that cannot be converted.
	root.Position = UDim2.fromOffset(x, y)
end

RunService.RenderStepped:Connect(updatePosition)

--============================================================
-- HOOK UP EXISTING + FUTURE TAGGED NODES
--============================================================

local boundNodes = setmetatable({}, { __mode = "k" })
local REFRESH_ATTRIBUTES = {
	Tier = true,
	Cost = true,
	Stats = true,
	Unlocked = true,
	Requires = true,
	Category = true,
}

local function bindNode(node)
	if not node:IsA("GuiObject") or not node:IsDescendantOf(playerGui) then
		return
	end
	if boundNodes[node] then
		return
	end
	boundNodes[node] = true

	node.MouseEnter:Connect(function()
		showTooltip(node)
	end)

	node.MouseLeave:Connect(function()
		hideTooltip(node)
	end)

	-- Upgrade art commonly puts a full-size TextButton over the tagged
	-- Frame. Listen on that actual hit target for touch so mobile details
	-- don't depend on whether input propagation reaches the parent Frame.
	local touchTarget = node:FindFirstChildWhichIsA("GuiButton", true) or node
	touchTarget.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			showTooltip(node)
			task.delay(2.8, function()
				hideTooltip(node)
			end)
		end
	end)

	node.AttributeChanged:Connect(function(attribute)
		if currentNode == node and REFRESH_ATTRIBUTES[attribute] then
			populateTooltip(node)
		end
	end)

	node.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			hideTooltip(node)
		end
	end)
end

for _, node in ipairs(CollectionService:GetTagged("UpgradeNode")) do
	bindNode(node)
end

CollectionService:GetInstanceAddedSignal("UpgradeNode"):Connect(bindNode)

CollectionService:GetInstanceRemovedSignal("UpgradeNode"):Connect(function(node)
	hideTooltip(node)
end)

player:GetAttributeChangedSignal("Rebirths"):Connect(function()
	if currentNode and currentNode.Parent then
		populateTooltip(currentNode)
	end
end)

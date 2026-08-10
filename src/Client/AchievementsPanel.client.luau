--[[
	AchievementsPanel (LocalScript -> StarterPlayerScripts)
	========================================================
	Displays the 13 Roblox badges (grid, earned/locked/secret) and the new
	in-game Milestones (list with a progress bar and a claim button) that
	AchievementsService.server.luau tracks

	Rows/cells are built ONCE at load and only ever have their properties
	UPDATED on each sync -- not destroyed and rebuilt -- because the server
	pushes a fresh sync every 5 seconds so progress bars creep forward
	live while the panel is open; rebuilding ~22 instances every 5 seconds
	would flicker and reset the scroll position out from under the player.

	The client decides nothing: it draws whatever snapshot the server
	sends and fires "I'd like to claim this" requests, same contract as
	every other panel in this game.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("AchievementsRemotes")
local SyncRemote = remotesFolder:WaitForChild("AchievementsSync")
local ClaimRemote = remotesFolder:WaitForChild("ClaimMilestone")
local RequestSyncRemote = remotesFolder:WaitForChild("RequestAchievementsSync")

local formatNumber = ProgressionConfig.FormatNumber

-- =========================================================================
-- THEME -- warm bronze/teal, distinct from the other four panels.
-- =========================================================================

local THEME = {
	Background = Color3.fromRGB(14, 24, 26),
	Panel = Color3.fromRGB(20, 34, 36),
	Row = Color3.fromRGB(28, 46, 48),
	RowReady = Color3.fromRGB(36, 58, 40),
	Accent = Color3.fromRGB(80, 200, 190),
	Gold = Color3.fromRGB(255, 205, 90),
	White = Color3.fromRGB(255, 255, 255),
	Grey = Color3.fromRGB(160, 178, 178),
	Locked = Color3.fromRGB(40, 40, 44),
}

local LAYOUT = {
	-- Continues the established rhythm on the right shortcut rail: Prestige
	-- Shop 0.213, Sanctum 0.295, Leaderboard 0.377 -- each 0.082 apart.
	-- (x=0.895 used to collide with MainGui.Right.Holder's own nav bar --
	-- see that file's LAYOUT comment.)
	ButtonPosition = UDim2.fromScale(0.952, 0.459),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.044, 0.062),
	PanelSize = UDim2.fromScale(0.58, 0.76),
}

-- =========================================================================
-- HELPERS
-- =========================================================================

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 10) }, parent)
end

local function stroke(parent, color, thickness, enabled)
	return new("UIStroke", {
		Color = color or THEME.Accent,
		Thickness = thickness or 2,
		Enabled = enabled ~= false,
	}, parent)
end

local function tween(instance, info, props)
	return TweenService:Create(instance, info, props)
end

local function formatReward(reward)
	if reward.Type == "Essence" then
		return "+" .. formatNumber(reward.Amount) .. " 🌿"
	elseif reward.Type == "SolarEssence" then
		return "+" .. formatNumber(reward.Amount) .. " ☀️"
	elseif reward.Type == "Shards" then
		return "+" .. tostring(reward.Amount) .. " 🔷"
	end
	return ""
end

-- =========================================================================
-- ROOT
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "AchievementsPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 65,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 120,
}, screenGui)

-- =========================================================================
-- STATE (server pushes {Badges = {{Id,Earned},...}, Milestones =
-- {{Id,Progress,Complete,Claimed},...}} -- reindexed here by Id)
-- =========================================================================

local state = {
	BadgesById = {},
	MilestonesById = {},
}

local isOpen = false

-- =========================================================================
-- OPEN BUTTON
-- =========================================================================

local openButton = new("TextButton", {
	Name = "AchievementsButton",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundColor3 = THEME.Panel,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 50,
}, screenGui)
corner(openButton, UDim.new(0.28, 0))
stroke(openButton, THEME.Accent, 2.5)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, openButton)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🏅",
	TextScaled = true,
	ZIndex = 51,
}, openButton)

local openCaption = new("TextLabel", {
	Name = "Caption",
	Size = UDim2.fromScale(1, 0.26),
	Position = UDim2.fromScale(0, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "GOALS",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 51,
}, openButton)
new("UITextSizeConstraint", { MaxTextSize = 12 }, openCaption)

-- Shown when at least one milestone is complete and waiting to be claimed.
local openBadge = new("Frame", {
	Name = "Badge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.34, 0.34),
	BackgroundColor3 = THEME.Gold,
	Visible = false,
	ZIndex = 53,
}, openButton)
corner(openBadge, UDim.new(1, 0))
stroke(openBadge, THEME.White, 2)

new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "!",
	TextColor3 = THEME.Background,
	TextScaled = true,
	ZIndex = 54,
}, openBadge)

Juice.ButtonFeel(openButton, { HoverScale = 1.07 })

-- =========================================================================
-- PANEL
-- =========================================================================

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = LAYOUT.PanelSize,
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 130,
}, screenGui)
corner(panel, UDim.new(0, 18))
stroke(panel, THEME.Accent, 3)

local panelScale = new("UIScale", { Scale = 0.85 }, panel)

new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 40, 42)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 20, 22)),
	}),
	Rotation = 90,
}, panel)

local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.fromScale(1, 0.13),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	ZIndex = 131,
}, panel)
corner(titleBar, UDim.new(0, 18))

new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0.4),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	ZIndex = 131,
}, titleBar)

local title = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.035, 0.4),
	Size = UDim2.fromScale(0.6, 0.46),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🏅  Achievements",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 133,
}, titleBar)
new("UITextSizeConstraint", { MaxTextSize = 24 }, title)

local subtitle = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.035, 0.78),
	Size = UDim2.fromScale(0.75, 0.28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Badges, and Milestones with real rewards to claim",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 133,
}, titleBar)
new("UITextSizeConstraint", { MaxTextSize = 13 }, subtitle)

local closeButton = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.968, 0.5),
	Size = UDim2.fromScale(0.07, 0.52),
	BackgroundColor3 = Color3.fromRGB(230, 80, 90),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "✕",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 133,
}, titleBar)
corner(closeButton, UDim.new(0.3, 0))
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, closeButton)
Juice.ButtonFeel(closeButton, { HoverScale = 1.1 })

-- =========================================================================
-- SCROLLING LIST (badge grid, then milestone rows -- both direct children
-- so a single UIListLayout stacks the grid container above the rows)
-- =========================================================================

local listHolder = new("ScrollingFrame", {
	Name = "List",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.16),
	Size = UDim2.fromScale(0.95, 0.81),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = THEME.Accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 131,
}, panel)

new("UIPadding", {
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 2),
	PaddingBottom = UDim.new(0, 10),
}, listHolder)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, listHolder)

local function addSectionHeader(text, color, order)
	local header = new("Frame", {
		Name = text .. "Header",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 132,
	}, listHolder)

	local label = new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.02, 0.5),
		Size = UDim2.fromScale(0.5, 0.85),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, header)
	new("UITextSizeConstraint", { MaxTextSize = 14 }, label)

	local rule = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.46, 0, 0, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = 133,
	}, header)

	return header
end

-- =========================================================================
-- BADGES (built once, updated in place)
-- =========================================================================

addSectionHeader("🏅 BADGES", THEME.Accent, 1)

local badgeGrid = new("Frame", {
	Name = "BadgeGrid",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	LayoutOrder = 2,
	ZIndex = 131,
}, listHolder)

new("UIGridLayout", {
	CellSize = UDim2.new(0, 76, 0, 82),
	CellPadding = UDim2.new(0, 8, 0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
}, badgeGrid)

local badgeCells = {}

for i, def in ipairs(AchievementsConfig.Badges) do
	local cell = new("Frame", {
		Name = "Badge_" .. def.Id,
		BackgroundColor3 = THEME.Locked,
		BorderSizePixel = 0,
		LayoutOrder = i,
		ZIndex = 132,
	}, badgeGrid)
	corner(cell, UDim.new(0.16, 0))
	local cellStroke = stroke(cell, THEME.Gold, 1.5, false)

	local icon = new("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromScale(1, 0.56),
		Position = UDim2.fromScale(0, 0.06),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "❓",
		TextTransparency = 0.4,
		TextScaled = true,
		ZIndex = 133,
	}, cell)

	local label = new("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0.92, 0.34),
		Position = UDim2.fromScale(0.04, 0.62),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "???",
		TextColor3 = THEME.Grey,
		TextWrapped = true,
		TextScaled = true,
		ZIndex = 133,
	}, cell)
	new("UITextSizeConstraint", { MaxTextSize = 11 }, label)

	badgeCells[def.Id] = { Cell = cell, Stroke = cellStroke, Icon = icon, Label = label }
end

-- =========================================================================
-- MILESTONES (built once, updated in place)
-- =========================================================================

addSectionHeader("🎯 MILESTONES", THEME.Gold, 1000)

local milestoneRows = {}

for i, def in ipairs(AchievementsConfig.Milestones) do
	local row = new("Frame", {
		Name = "Milestone_" .. def.Id,
		Size = UDim2.new(1, 0, 0, 66),
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = 1000 + i,
		ZIndex = 132,
	}, listHolder)
	corner(row, UDim.new(0.12, 0))
	local rowStroke = stroke(row, THEME.Gold, 2, false)

	new("TextLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.02, 0.5),
		Size = UDim2.fromScale(0.09, 0.7),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = def.Icon,
		TextScaled = true,
		ZIndex = 133,
	}, row)

	new("TextLabel", {
		Name = "Name",
		Position = UDim2.fromScale(0.13, 0.08),
		Size = UDim2.fromScale(0.5, 0.34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = def.Name,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)

	new("TextLabel", {
		Name = "Description",
		Position = UDim2.fromScale(0.13, 0.42),
		Size = UDim2.fromScale(0.5, 0.24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = def.Description,
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)

	local barBG = new("Frame", {
		Name = "BarBG",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.13, 0.9),
		Size = UDim2.fromScale(0.5, 0.12),
		BackgroundColor3 = THEME.Locked,
		BorderSizePixel = 0,
		ZIndex = 133,
	}, row)
	corner(barBG, UDim.new(1, 0))

	local barFill = new("Frame", {
		Name = "BarFill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
		ZIndex = 134,
	}, barBG)
	corner(barFill, UDim.new(1, 0))

	local claimButton = new("TextButton", {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.97, 0.5),
		Size = UDim2.fromScale(0.3, 0.64),
		BackgroundColor3 = THEME.Locked,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = formatReward(def.Reward),
		TextColor3 = THEME.Grey,
		TextScaled = true,
		Active = false,
		ZIndex = 133,
	}, row)
	corner(claimButton, UDim.new(0.2, 0))
	new("UITextSizeConstraint", { MaxTextSize = 13 }, claimButton)
	Juice.ButtonFeel(claimButton, { HoverScale = 1.05 })

	claimButton.MouseButton1Click:Connect(function()
		local entry = state.MilestonesById[def.Id]
		if entry and entry.Complete and not entry.Claimed then
			ClaimRemote:FireServer(def.Id)
		end
	end)

	milestoneRows[def.Id] = {
		Row = row, Stroke = rowStroke, BarFill = barFill, ClaimButton = claimButton,
	}
end

-- =========================================================================
-- RENDER (updates existing instances -- never destroys/rebuilds)
-- =========================================================================

local function renderBadge(def)
	local refs = badgeCells[def.Id]
	if not refs then
		return
	end
	local entry = state.BadgesById[def.Id]
	local earned = entry ~= nil and entry.Earned

	refs.Cell.BackgroundColor3 = earned and THEME.Row or THEME.Locked
	refs.Stroke.Enabled = earned

	local revealed = earned or not def.Secret
	refs.Icon.Text = revealed and def.Icon or "❓"
	refs.Icon.TextTransparency = earned and 0 or 0.4
	refs.Label.Text = revealed and def.Name or "???"
	refs.Label.TextColor3 = earned and THEME.White or THEME.Grey
end

local function renderMilestone(def)
	local refs = milestoneRows[def.Id]
	if not refs then
		return
	end
	local entry = state.MilestonesById[def.Id] or { Progress = 0, Complete = false, Claimed = false }

	tween(refs.BarFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(math.clamp(entry.Progress, 0, 1), 1),
	}):Play()
	refs.BarFill.BackgroundColor3 = entry.Complete and THEME.Gold or THEME.Accent

	local claimable = entry.Complete and not entry.Claimed
	refs.Stroke.Enabled = claimable
	refs.Row.BackgroundColor3 = claimable and THEME.RowReady or THEME.Row

	refs.ClaimButton.Active = claimable
	if entry.Claimed then
		refs.ClaimButton.Text = "✓ Claimed"
		refs.ClaimButton.BackgroundColor3 = THEME.Locked
		refs.ClaimButton.TextColor3 = THEME.Grey
	elseif claimable then
		refs.ClaimButton.Text = "Claim " .. formatReward(def.Reward)
		refs.ClaimButton.BackgroundColor3 = THEME.Gold
		refs.ClaimButton.TextColor3 = THEME.Background
	else
		refs.ClaimButton.Text = formatReward(def.Reward)
		refs.ClaimButton.BackgroundColor3 = THEME.Locked
		refs.ClaimButton.TextColor3 = THEME.Grey
	end
end

local function render()
	for _, def in ipairs(AchievementsConfig.Badges) do
		renderBadge(def)
	end

	local anyClaimable = false
	for _, def in ipairs(AchievementsConfig.Milestones) do
		renderMilestone(def)
		local entry = state.MilestonesById[def.Id]
		if entry and entry.Complete and not entry.Claimed then
			anyClaimable = true
		end
	end

	openBadge.Visible = anyClaimable and not isOpen
end

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local function open()
	if isOpen then
		return
	end
	isOpen = true

	openBadge.Visible = false
	render()

	-- Ask for a fresh read the moment the panel opens, same defensiveness
	-- as Sanctum/Prestige Shop's RequestSync.
	RequestSyncRemote:FireServer()

	backdrop.Visible = true
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	panel.Visible = true
	panelScale.Scale = 0.85
	tween(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()

	local out = tween(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.85 })
	out:Play()
	out.Completed:Connect(function()
		if not isOpen then
			panel.Visible = false
			backdrop.Visible = false
		end
	end)

	render()
end

openButton.MouseButton1Click:Connect(function()
	if isOpen then
		close()
	else
		open()
	end
end)

closeButton.MouseButton1Click:Connect(close)
backdrop.Activated:Connect(close)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then
		close()
	end
end)

-- =========================================================================
-- SYNC
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if type(payload.Badges) == "table" then
		local byId = {}
		for _, entry in ipairs(payload.Badges) do
			byId[entry.Id] = entry
		end
		state.BadgesById = byId
	end

	if type(payload.Milestones) == "table" then
		local byId = {}
		for _, entry in ipairs(payload.Milestones) do
			byId[entry.Id] = entry
		end
		state.MilestonesById = byId
	end

	render()
end)

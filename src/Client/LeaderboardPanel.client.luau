--[[
	LeaderboardPanel (LocalScript -> StarterPlayerScripts)
	=======================================================
	Displays the global Top Essence / Top Rebirths leaderboards that
	LeaderboardService.server.luau maintains. Purely a viewer -- it draws
	whatever snapshot the server pushes and never computes or trusts
	anything itself, same contract as SanctumPanel/RebirthShopPanel.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("LeaderboardRemotes")
local SyncRemote = remotesFolder:WaitForChild("LeaderboardSync")

local formatNumber = ProgressionConfig.FormatNumber

-- =========================================================================
-- THEME -- warm gold/bronze, distinct from Sanctum's purple and the
-- Prestige Shop's amber, since this is neither a shop nor an upgrade tree.
-- =========================================================================

local THEME = {
	Background = Color3.fromRGB(28, 22, 12),
	Panel = Color3.fromRGB(40, 32, 18),
	Row = Color3.fromRGB(54, 43, 24),
	RowSelf = Color3.fromRGB(90, 70, 20),
	TabActive = Color3.fromRGB(255, 200, 60),
	TabInactive = Color3.fromRGB(54, 43, 24),
	Gold = Color3.fromRGB(255, 200, 60),
	Silver = Color3.fromRGB(200, 205, 215),
	Bronze = Color3.fromRGB(210, 140, 80),
	White = Color3.fromRGB(255, 255, 255),
	Grey = Color3.fromRGB(180, 166, 140),
}

local LAYOUT = {
	-- Continue the same right-side shortcut rail and vertical rhythm used
	-- by Prestige Shop and Sanctum. (x=0.895 used to collide with
	-- MainGui.Right.Holder's own nav bar -- see that file's LAYOUT
	-- comment.)
	ButtonPosition = UDim2.fromScale(0.952, 0.377),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.044, 0.062),
	PanelSize = UDim2.fromScale(0.5, 0.68),
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

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or THEME.Gold,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	}, parent)
end

local function tween(instance, info, props)
	return TweenService:Create(instance, info, props)
end

local RANK_COLORS = { [1] = THEME.Gold, [2] = THEME.Silver, [3] = THEME.Bronze }
local function rankColor(rank)
	return RANK_COLORS[rank] or THEME.White
end
local RANK_MEDALS = { [1] = "🥇", [2] = "🥈", [3] = "🥉" }

-- =========================================================================
-- ROOT
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "LeaderboardPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 64,
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
-- STATE
-- =========================================================================

local BOARD_ORDER = { "Essence", "Rebirths", "WeeklyEssence" }
local BOARD_META = {
	Essence = { Name = "Essence", Icon = "🌿" },
	Rebirths = { Name = "Rebirths", Icon = "🔥" },
	-- Resets every UTC week (see LeaderboardService's Dynamic board /
	-- week-numbered store name) so newer players always have a board
	-- where the lifetime veterans aren't an unreachable wall.
	WeeklyEssence = { Name = "This Week", Icon = "📅" },
}

local state = {
	Boards = { Essence = {}, Rebirths = {}, WeeklyEssence = {} },
	ActiveBoard = "Essence",
}

local isOpen = false

-- =========================================================================
-- OPEN BUTTON
-- =========================================================================

local openButton = new("TextButton", {
	Name = "LeaderboardButton",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundColor3 = THEME.Panel,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 50,
}, screenGui)
corner(openButton, UDim.new(0.28, 0))
stroke(openButton, THEME.Gold, 2.5)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, openButton)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🏆",
	TextScaled = true,
	ZIndex = 51,
}, openButton)

local openCaption = new("TextLabel", {
	Name = "Caption",
	Size = UDim2.fromScale(1, 0.26),
	Position = UDim2.fromScale(0, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "RANKS",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 51,
}, openButton)
new("UITextSizeConstraint", { MaxTextSize = 12 }, openCaption)

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
stroke(panel, THEME.Gold, 3)

local panelScale = new("UIScale", { Scale = 0.85 }, panel)

new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(46, 36, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 18, 10)),
	}),
	Rotation = 90,
}, panel)

local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.fromScale(1, 0.14),
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
	Size = UDim2.fromScale(0.65, 0.46),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🏆  Leaderboards",
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
	Text = "Top 50, refreshes every few minutes",
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
-- TABS
-- =========================================================================

local tabHolder = new("Frame", {
	Name = "Tabs",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.17),
	Size = UDim2.fromScale(0.95, 0.09),
	BackgroundTransparency = 1,
	ZIndex = 131,
}, panel)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, tabHolder)

local tabButtons = {}

local function buildTab(boardId, order)
	local meta = BOARD_META[boardId]
	local tab = new("TextButton", {
		Name = boardId .. "Tab",
		Size = UDim2.fromScale(0.32, 1),
		BackgroundColor3 = THEME.TabInactive,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = meta.Icon .. "  " .. meta.Name,
		TextColor3 = THEME.White,
		TextScaled = true,
		LayoutOrder = order,
		ZIndex = 132,
	}, tabHolder)
	corner(tab, UDim.new(0.25, 0))
	new("UITextSizeConstraint", { MaxTextSize = 14 }, tab)
	Juice.ButtonFeel(tab, { HoverScale = 1.03 })
	tabButtons[boardId] = tab
	return tab
end

for i, boardId in ipairs(BOARD_ORDER) do
	buildTab(boardId, i)
end

-- =========================================================================
-- ROWS
-- =========================================================================

local listHolder = new("ScrollingFrame", {
	Name = "List",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.29),
	Size = UDim2.fromScale(0.95, 0.66),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = THEME.Gold,
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
	Padding = UDim.new(0, 6),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, listHolder)

local emptyLabel = new("TextLabel", {
	Name = "EmptyNote",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "No rankings yet -- be the first!",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	Visible = false,
	LayoutOrder = -1,
	ZIndex = 132,
}, listHolder)

local outsideNote = new("TextLabel", {
	Name = "OutsideNote",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "You're not in the Top 50 yet -- keep going!",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	Visible = false,
	LayoutOrder = 9999,
	ZIndex = 132,
}, listHolder)

local function buildRow(entry, isSelf)
	local row = new("Frame", {
		Name = "Row" .. tostring(entry.Rank),
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = isSelf and THEME.RowSelf or THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = entry.Rank,
		ZIndex = 132,
	}, listHolder)
	corner(row, UDim.new(0.2, 0))
	if isSelf then
		stroke(row, THEME.Gold, 1.5)
	end

	local rankText = RANK_MEDALS[entry.Rank] or ("#" .. tostring(entry.Rank))
	new("TextLabel", {
		Name = "Rank",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.03, 0.5),
		Size = UDim2.fromScale(0.16, 0.7),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = rankText,
		TextColor3 = rankColor(entry.Rank),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)

	new("TextLabel", {
		Name = "PlayerName",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.22, 0.5),
		Size = UDim2.fromScale(0.5, 0.7),
		BackgroundTransparency = 1,
		Font = isSelf and Enum.Font.GothamBlack or Enum.Font.GothamMedium,
		Text = (isSelf and "★ " or "") .. entry.Name,
		TextColor3 = isSelf and THEME.Gold or THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 133,
	}, row)

	new("TextLabel", {
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.96, 0.5),
		Size = UDim2.fromScale(0.32, 0.7),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = formatNumber(entry.Value),
		TextColor3 = THEME.Gold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 133,
	}, row)

	return row
end

local activeRows = {}
local function clearRows()
	for _, row in ipairs(activeRows) do
		row:Destroy()
	end
	activeRows = {}
end

local function render()
	clearRows()

	local entries = state.Boards[state.ActiveBoard] or {}
	emptyLabel.Visible = #entries == 0

	local selfInList = false
	for _, entry in ipairs(entries) do
		local isSelf = entry.UserId == player.UserId
		if isSelf then
			selfInList = true
		end
		table.insert(activeRows, buildRow(entry, isSelf))
	end

	outsideNote.Visible = (#entries > 0) and not selfInList

	for boardId, tab in pairs(tabButtons) do
		local active = boardId == state.ActiveBoard
		tween(tab, TweenInfo.new(0.15), {
			BackgroundColor3 = active and THEME.TabActive or THEME.TabInactive,
		}):Play()
		tab.TextColor3 = active and THEME.Background or THEME.White
	end
end

for boardId, tab in pairs(tabButtons) do
	tab.MouseButton1Click:Connect(function()
		if state.ActiveBoard == boardId then
			return
		end
		state.ActiveBoard = boardId
		render()
	end)
end

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local function open()
	if isOpen then
		return
	end
	isOpen = true

	render()

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

	for _, boardId in ipairs(BOARD_ORDER) do
		if type(payload[boardId]) == "table" then
			state.Boards[boardId] = payload[boardId]
		end
	end

	if isOpen then
		render()
	end
end)

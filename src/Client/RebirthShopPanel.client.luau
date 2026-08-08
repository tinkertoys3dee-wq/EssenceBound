--[[
	RebirthShopPanel (LocalScript -> StarterPlayerScripts)
	=======================================================
	The Prestige Shop interface: where Rebirth Currency ("Prestige Shards")
	is spent. Structurally a near-twin of SanctumPanel.client.luau -- same
	build-entirely-in-code approach, same "client draws, server decides"
	authority model, same render/affordability-pulse/announce-once pattern
	-- themed differently (gold/amber "ascension" palette vs the Sanctum's
	cool purple) so the two shops still read as distinct rooms.

	The client decides nothing here either: it draws whatever snapshot
	RebirthShopService sends and fires "I'd like to buy this" requests: the
	server re-derives level, cost and balance and is the only thing that
	can grant anything.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RebirthShopUpgrades = require(ReplicatedStorage:WaitForChild("RebirthShopUpgrades"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local remotesFolder = ReplicatedStorage:WaitForChild("RebirthShopRemotes")
local PurchaseRemote = remotesFolder:WaitForChild("PurchaseRebirthUpgrade")
local SyncRemote = remotesFolder:WaitForChild("RebirthShopSync")
local RequestSyncRemote = remotesFolder:WaitForChild("RequestRebirthShopSync")

-- =========================================================================
-- THEME
-- =========================================================================
-- Warm gold/amber "ascension" palette, deliberately distinct from the
-- Sanctum's cool purple -- this is the rarer, higher-tier currency, and
-- should read that way at a glance.

local THEME = {
	Background = Color3.fromRGB(36, 24, 10),
	Panel = Color3.fromRGB(48, 32, 14),
	Row = Color3.fromRGB(64, 44, 20),
	RowHover = Color3.fromRGB(82, 58, 28),
	Gold = Color3.fromRGB(255, 200, 90),
	GoldDim = Color3.fromRGB(160, 130, 80),
	Accent = Color3.fromRGB(255, 165, 60),
	Green = Color3.fromRGB(58, 209, 118),
	White = Color3.fromRGB(255, 255, 255),
	Grey = Color3.fromRGB(180, 166, 148),
	Locked = Color3.fromRGB(70, 60, 46),
}

local LAYOUT = {
	-- One slot below the Sanctum button (0.895, 0.295) in the same manual
	-- left-edge column -- move this one line if it ever collides with
	-- anything on a given screen size.
	ButtonPosition = UDim2.fromScale(0.895, 0.213),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.062, 0.062),
	-- Five upgrades, one section header -- shorter list than the Sanctum's
	-- nine, so a smaller panel keeps rows from looking sparse and stretched.
	PanelSize = UDim2.fromScale(0.56, 0.6),
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

local formatNumber = ProgressionConfig.FormatNumber

-- =========================================================================
-- ROOT
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "RebirthShopPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 63,
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

local state = {
	Balance = 0,
	Rebirths = 0,
	Upgrades = {},
}

local isOpen = false

-- =========================================================================
-- OPEN BUTTON
-- =========================================================================

local openButton = new("TextButton", {
	Name = "RebirthShopButton",
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
	Text = "🔮",
	TextScaled = true,
	ZIndex = 51,
}, openButton)

local openCaption = new("TextLabel", {
	Name = "Caption",
	Size = UDim2.fromScale(1, 0.26),
	Position = UDim2.fromScale(0, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "PRESTIGE",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 51,
}, openButton)
new("UITextSizeConstraint", { MaxTextSize = 12 }, openCaption)

-- Shown when at least one upgrade is affordable, so players discover the
-- shop exists rather than having to go looking for it.
local openBadge = new("Frame", {
	Name = "Badge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.34, 0.34),
	BackgroundColor3 = THEME.Green,
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
	TextColor3 = THEME.White,
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
stroke(panel, THEME.Gold, 3)

local panelScale = new("UIScale", { Scale = 0.85 }, panel)

new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 38, 16)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 20, 8)),
	}),
	Rotation = 90,
}, panel)

local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.fromScale(1, 0.18),
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
	Size = UDim2.fromScale(0.5, 0.46),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🔮  Prestige Shop",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 133,
}, titleBar)
new("UITextSizeConstraint", { MaxTextSize = 24 }, title)

local subtitle = new("TextLabel", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.035, 0.78),
	Size = UDim2.fromScale(0.6, 0.28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Bought with Prestige Shards -- survives rebirth, just like the Sanctum",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 133,
}, titleBar)
new("UITextSizeConstraint", { MaxTextSize = 13 }, subtitle)

-- Live balance readout, so the player never has to close the panel to
-- check whether they can afford the next tier.
local balanceLabel = new("TextLabel", {
	Name = "Balance",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.88, 0.5),
	Size = UDim2.fromScale(0.34, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "0",
	TextColor3 = THEME.Gold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 133,
}, titleBar)
new("UITextSizeConstraint", { MaxTextSize = 20 }, balanceLabel)

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
-- UPGRADE ROWS
-- =========================================================================

local listHolder = new("ScrollingFrame", {
	Name = "List",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.21),
	Size = UDim2.fromScale(0.95, 0.75),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = THEME.Gold,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 131,
}, panel)

-- Same reasoning as SanctumPanel: padding on the scroll frame rather than
-- negative row widths, so the scrollbar never overlaps a row and the last
-- row doesn't butt against the panel edge.
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
		Size = UDim2.fromScale(0.6, 0.85),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, header)
	new("UITextSizeConstraint", { MaxTextSize = 14 }, label)

	new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(0.36, 0, 0, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = 133,
	}, header)

	return header
end

local rows = {}

addSectionHeader("🔮 PRESTIGE UPGRADES  •  each one changes how you play", THEME.Gold, 0)

for index, def in ipairs(RebirthShopUpgrades.List) do
	local row = new("Frame", {
		Name = def.Id,
		Size = UDim2.new(1, 0, 0, 96),
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = index,
		ZIndex = 132,
	}, listHolder)
	corner(row, UDim.new(0, 12))
	local rowStroke = stroke(row, THEME.Locked, 2)

	local icon = new("TextLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.022, 0.5),
		Size = UDim2.fromScale(0.085, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = def.Icon,
		TextScaled = true,
		ZIndex = 133,
	}, row)

	local nameLabel = new("TextLabel", {
		Position = UDim2.fromScale(0.12, 0.1),
		Size = UDim2.fromScale(0.45, 0.22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = def.Name,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 18 }, nameLabel)

	local descLabel = new("TextLabel", {
		Position = UDim2.fromScale(0.12, 0.33),
		Size = UDim2.fromScale(0.6, 0.28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = def.Description,
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 12 }, descLabel)

	local effectLabel = new("TextLabel", {
		Position = UDim2.fromScale(0.12, 0.66),
		Size = UDim2.fromScale(0.6, 0.24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = THEME.Green,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, effectLabel)

	local levelLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.975, 0.08),
		Size = UDim2.fromScale(0.24, 0.2),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 133,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, levelLabel)

	-- Level pips: a glanceable read on how far along this upgrade is.
	local pipHolder = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.975, 0.3),
		Size = UDim2.fromScale(0.24, 0.08),
		BackgroundTransparency = 1,
		ZIndex = 133,
	}, row)

	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pipHolder)

	local pips = {}
	for pipIndex = 1, def.MaxLevel do
		local pip = new("Frame", {
			Name = "Pip" .. pipIndex,
			Size = UDim2.new(1 / def.MaxLevel, -2, 1, 0),
			BackgroundColor3 = THEME.Locked,
			BorderSizePixel = 0,
			LayoutOrder = pipIndex,
			ZIndex = 133,
		}, pipHolder)
		corner(pip, UDim.new(1, 0))
		pips[pipIndex] = pip
	end

	local buyButton = new("TextButton", {
		Name = "Buy",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.975, 0.92),
		Size = UDim2.fromScale(0.24, 0.32),
		BackgroundColor3 = THEME.Locked,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		ZIndex = 134,
	}, row)
	corner(buyButton, UDim.new(0.28, 0))
	new("UITextSizeConstraint", { MaxTextSize = 15 }, buyButton)
	Juice.ButtonFeel(buyButton, { HoverScale = 1.05 })

	buyButton.MouseButton1Click:Connect(function()
		local entry = state.Upgrades and state.Upgrades[index]
		if not entry or not entry.Cost then
			return
		end
		if state.Balance < entry.Cost then
			return
		end
		PurchaseRemote:FireServer(def.Id)
	end)

	row.MouseEnter:Connect(function()
		tween(row, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = THEME.RowHover,
		}):Play()
	end)

	row.MouseLeave:Connect(function()
		tween(row, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundColor3 = THEME.Row,
		}):Play()
	end)

	rows[index] = {
		Row = row,
		Stroke = rowStroke,
		Icon = icon,
		Effect = effectLabel,
		Level = levelLabel,
		Pips = pips,
		Buy = buyButton,
		Affordable = false,
	}
end

-- =========================================================================
-- AFFORDABILITY PULSE
-- =========================================================================

task.spawn(function()
	local bright = true

	while true do
		for _, row in ipairs(rows) do
			if row.Affordable and row.Stroke.Parent then
				tween(row.Stroke, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Transparency = bright and 0 or 0.55,
				}):Play()
			end
		end

		bright = not bright
		task.wait(0.6)
	end
end)

-- =========================================================================
-- RENDER
-- =========================================================================

local lastLevels = {}

local function render()
	balanceLabel.Text = RebirthShopUpgrades.CURRENCY_ICON .. " " .. formatNumber(state.Balance)

	local anyAffordable = false

	for index, row in ipairs(rows) do
		local entry = state.Upgrades and state.Upgrades[index]
		if not entry then
			continue
		end

		row.Effect.Text = entry.Level > 0 and entry.CurrentEffect or "Dormant -- not yet unlocked"
		row.Effect.TextColor3 = entry.Level > 0 and THEME.Green or THEME.Grey
		row.Level.Text = ("Lv %d / %d"):format(entry.Level, entry.MaxLevel)

		for pipIndex, pip in ipairs(row.Pips) do
			pip.BackgroundColor3 = pipIndex <= entry.Level and THEME.Gold or THEME.Locked
		end

		local maxed = entry.Level >= entry.MaxLevel
		local affordable = entry.Cost ~= nil and state.Balance >= entry.Cost

		row.Affordable = affordable and not maxed

		if maxed then
			row.Buy.Text = "MAXED"
			row.Buy.BackgroundColor3 = THEME.Locked
			row.Buy.TextColor3 = THEME.Gold
			row.Stroke.Color = THEME.Gold
			row.Stroke.Transparency = 0.4
		elseif affordable then
			anyAffordable = true
			row.Buy.Text = formatNumber(entry.Cost)
			row.Buy.BackgroundColor3 = THEME.Gold
			row.Buy.TextColor3 = Color3.fromRGB(40, 26, 8)
			row.Stroke.Color = THEME.Gold
			-- Transparency deliberately NOT set here -- the affordability
			-- pulse owns that property while a row is affordable.
		else
			row.Buy.Text = formatNumber(entry.Cost or 0)
			row.Buy.BackgroundColor3 = THEME.Locked
			row.Buy.TextColor3 = THEME.Grey
			row.Stroke.Color = THEME.Locked
			row.Stroke.Transparency = 0.3
		end

		local previous = lastLevels[index]
		if previous ~= nil and entry.Level > previous then
			Juice.Punch(Juice.GetScale(row.Row), 0.06, 0.3)

			-- Explicit flash-and-return rather than Juice.PulseBackground --
			-- same reasoning as SanctumPanel: hover also drives this row's
			-- BackgroundColor3, and the cached-base helper would go stale.
			row.Row.BackgroundColor3 = THEME.Gold
			tween(row.Row, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = THEME.Row,
			}):Play()

			if juiceLayer then
				local center = Juice.CenterOf(row.Icon, juiceLayer)
				if center then
					Juice.Burst(juiceLayer, center, {
						Count = 14,
						Colors = { THEME.Gold, THEME.White, THEME.Accent },
						Distance = 150,
						Duration = 0.7,
						Size = { 4, 10 },
						ZIndex = 200,
					})
					Juice.Ring(juiceLayer, center, {
						Color = THEME.Gold,
						StartSize = 30,
						EndSize = 150,
						Duration = 0.5,
						Thickness = 3,
					})
				end
			end
		end
		lastLevels[index] = entry.Level
	end

	openBadge.Visible = anyAffordable and not isOpen
end

-- =========================================================================
-- DISCOVERABILITY
-- =========================================================================

local hasAnnounced = false

local function announceOnce()
	if hasAnnounced or isOpen then
		return
	end
	hasAnnounced = true

	Juice.Punch(Juice.GetScale(openButton), 0.25, 0.45)

	if juiceLayer then
		local center = Juice.CenterOf(openButton, juiceLayer)
		if center then
			Juice.Ring(juiceLayer, center, {
				Color = THEME.Gold,
				StartSize = 40,
				EndSize = 170,
				Duration = 0.6,
				Thickness = 3,
			})
			Juice.FloatText(juiceLayer, center - UDim2.fromOffset(0, 50), "Prestige Shop ready!", {
				Color = THEME.Gold,
				Duration = 1.6,
				Rise = 44,
				TextSize = 22,
			})
		end
	end
end

task.spawn(function()
	while true do
		if openBadge.Visible then
			tween(openBadge, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.fromScale(0.4, 0.4),
			}):Play()
		end
		task.wait(0.5)
		if openBadge.Visible then
			tween(openBadge, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.fromScale(0.34, 0.34),
			}):Play()
		end
		task.wait(0.5)
	end
end)

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local function open()
	if isOpen then
		return
	end
	isOpen = true

	render()

	RequestSyncRemote:FireServer()

	backdrop.Visible = true
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	panel.Visible = true
	panelScale.Scale = 0.85
	tween(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	openBadge.Visible = false
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
-- SERVER STATE
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	state.Balance = tonumber(payload.Balance) or 0
	state.Rebirths = tonumber(payload.Rebirths) or 0
	state.Upgrades = payload.Upgrades or {}

	render()

	if openBadge.Visible then
		announceOnce()
	end
end)

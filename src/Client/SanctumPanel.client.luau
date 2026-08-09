--[[
	SanctumPanel (LocalScript -> StarterPlayerScripts)
	==================================================
	The Shadow Sanctum interface: where Shadow Essence is finally spendable.

	Built entirely in code (same as LoadingScreen, Tutorial, NewDiscovery
	and ProgressionHud) so it needs nothing hand-built in Studio.

	The client decides nothing. It draws whatever snapshot SanctumService
	sends and fires "I'd like to buy this" requests; the server re-derives
	the level, cost and balance and is the only thing that can grant
	anything. Buttons disable themselves purely as a courtesy so the player
	isn't clicking something that will bounce.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local SanctumUpgrades = require(ReplicatedStorage:WaitForChild("SanctumUpgrades"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local remotesFolder = ReplicatedStorage:WaitForChild("SanctumRemotes")
local PurchaseRemote = remotesFolder:WaitForChild("PurchaseSanctumUpgrade")
local SyncRemote = remotesFolder:WaitForChild("SanctumSync")
local RequestSyncRemote = remotesFolder:WaitForChild("RequestSanctumSync")

-- =========================================================================
-- THEME
-- =========================================================================
-- Deliberately cooler and more purple than the Progression panels: the
-- Sanctum is the "shadow" side of the economy and should feel like a
-- different room, while still clearly belonging to the same game.

local THEME = {
	Background = Color3.fromRGB(20, 12, 36),
	Panel = Color3.fromRGB(28, 17, 48),
	Row = Color3.fromRGB(40, 24, 66),
	RowHover = Color3.fromRGB(52, 32, 84),
	Shadow = Color3.fromRGB(170, 130, 255),
	ShadowDim = Color3.fromRGB(96, 74, 150),
	Accent = Color3.fromRGB(247, 165, 60),
	Green = Color3.fromRGB(58, 209, 118),
	White = Color3.fromRGB(255, 255, 255),
	Grey = Color3.fromRGB(158, 148, 172),
	Locked = Color3.fromRGB(58, 50, 76),
	Gold = Color3.fromRGB(255, 215, 0),
}

local LAYOUT = {
	-- Sits under the progression button stack on the left edge. Move this
	-- one line if it collides with anything on a given screen size.
	--
	-- Was 0.895: a real screenshot showed this whole column (Sanctum,
	-- Prestige Shop, Ranks, Goals) rendering directly on top of MainGui.
	-- Right.Holder's own live nav bar (Upgrades/Zones/Rebirth/Index/
	-- Shop/Settings -- see UIInitializerHooks.client.luau), which
	-- occupies that same x=0.895 band. 0.92 matches ProgressionHud's
	-- Daily/Quest/Codes stack, confirmed clear of that same nav bar in
	-- the same screenshot -- proven-safe, not a second guess.
	ButtonPosition = UDim2.fromScale(0.92, 0.295),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.062, 0.062),
	-- Taller than it was (0.62) now the list holds nine upgrades across two
	-- sections -- centred at 0.5, this spans 0.14..0.86 and still leaves a
	-- clear margin top and bottom on a 16:9 screen.
	PanelSize = UDim2.fromScale(0.56, 0.72),
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
		Color = color or THEME.Shadow,
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
	Name = "SanctumPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 62,
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
	Lifetime = 0,
	Upgrades = {},
}

local isOpen = false

-- =========================================================================
-- OPEN BUTTON
-- =========================================================================

local openButton = new("TextButton", {
	Name = "SanctumButton",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundColor3 = THEME.Panel,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 50,
}, screenGui)
corner(openButton, UDim.new(0.28, 0))
stroke(openButton, THEME.Shadow, 2.5)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, openButton)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🌑",
	TextScaled = true,
	ZIndex = 51,
}, openButton)

local openCaption = new("TextLabel", {
	Name = "Caption",
	Size = UDim2.fromScale(1, 0.26),
	Position = UDim2.fromScale(0, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "SANCTUM",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 51,
}, openButton)
new("UITextSizeConstraint", { MaxTextSize = 12 }, openCaption)

-- Shown when at least one upgrade is affordable, so players discover the
-- Sanctum exists rather than having to go looking for it.
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
stroke(panel, THEME.Shadow, 3)

local panelScale = new("UIScale", { Scale = 0.85 }, panel)

-- Subtle vertical gradient gives the panel depth rather than reading as a
-- flat rectangle.
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 20, 58)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 10, 32)),
	}),
	Rotation = 90,
}, panel)

local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.fromScale(1, 0.15),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	ZIndex = 131,
}, panel)
corner(titleBar, UDim.new(0, 18))

-- Squares off the title bar's lower corners so it meets the body flush.
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
	Text = "🌑  Shadow Sanctum",
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
	Text = "Permanent upgrades -- these survive rebirth",
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
	TextColor3 = THEME.Shadow,
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
	Position = UDim2.fromScale(0.5, 0.17),
	-- Bottom edge lands at 0.17 + 0.79 = 0.96, leaving a deliberate 4%
	-- margin inside the panel rather than running to its rounded corner.
	Size = UDim2.fromScale(0.95, 0.79),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = THEME.Shadow,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 131,
}, panel)

-- Padding on the scroll frame rather than negative row widths. The right
-- inset clears the scrollbar so rows can't slide underneath it, and the
-- bottom inset means the last row doesn't butt against the panel edge when
-- scrolled fully down. AutomaticCanvasSize accounts for UIPadding, so the
-- scrollable height stays correct.
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

-- Section headers. With nine upgrades split across two very different
-- kinds -- linear stat boosts vs periodic relic abilities -- an unbroken
-- list gives the player no way to tell which is which before reading every
-- description. LayoutOrder is spaced so headers always sort above their
-- group regardless of how many upgrades land in each.
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

	-- Hairline rule filling the space to the right of the label.
	local rule = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(0.46, 0),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		ZIndex = 133,
	}, header)
	rule.Size = UDim2.new(0.46, 0, 0, 1)

	return header
end

local rows = {}

-- Relics render below the stat upgrades, each under its own header.
local statOrder, relicOrder = 10, 1000
addSectionHeader("ENHANCEMENTS", THEME.Grey, statOrder - 1)
addSectionHeader("RELICS  •  periodic abilities", THEME.Shadow, relicOrder - 1)

for index, def in ipairs(SanctumUpgrades.List) do
	local isRelic = def.Kind == "Relic"
	local order
	if isRelic then
		relicOrder += 1
		order = relicOrder
	else
		statOrder += 1
		order = statOrder
	end

	local row = new("Frame", {
		Name = def.Id,
		Size = UDim2.new(1, 0, 0, 92),
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = order,
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
		Position = UDim2.fromScale(0.12, 0.12),
		Size = UDim2.fromScale(0.45, 0.24),
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
		Position = UDim2.fromScale(0.12, 0.37),
		Size = UDim2.fromScale(0.55, 0.26),
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
		Size = UDim2.fromScale(0.55, 0.22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = THEME.Green,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 133,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, effectLabel)

	local levelLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.975, 0.1),
		Size = UDim2.fromScale(0.24, 0.22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 133,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, levelLabel)

	-- Level pips: a glanceable read on how far along this upgrade is,
	-- which a "3 / 10" string alone doesn't give you.
	local pipHolder = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.975, 0.34),
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
		Position = UDim2.fromScale(0.975, 0.9),
		Size = UDim2.fromScale(0.24, 0.34),
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

	-- Rows are Frames, not buttons, but GuiObject still fires MouseEnter /
	-- MouseLeave -- so the whole row can respond to the cursor even though
	-- only the Buy button inside it is clickable. Without this the list
	-- feels completely inert everywhere except that one small button.
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
		-- Set by render(); read by the shared affordability pulse below.
		Affordable = false,
	}
end

-- =========================================================================
-- AFFORDABILITY PULSE
-- =========================================================================
-- One shared loop rather than a per-row loop, so every affordable row
-- breathes in sync -- staggered pulses read as noise, a single synchronised
-- rhythm reads as "these are the ones you can buy right now."

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

-- Remembers the last rendered level per row so a purchase can be
-- celebrated without replaying the effect on every routine resync (the
-- balance readout alone re-syncs on every essence change).
local lastLevels = {}

local function render()
	balanceLabel.Text = "🌑 " .. formatNumber(state.Balance)

	local anyAffordable = false

	for index, row in ipairs(rows) do
		local entry = state.Upgrades and state.Upgrades[index]
		if not entry then
			continue
		end

		row.Effect.Text = entry.Level > 0 and entry.CurrentEffect or "Not yet awakened"
		row.Effect.TextColor3 = entry.Level > 0 and THEME.Green or THEME.Grey
		row.Level.Text = ("Lv %d / %d"):format(entry.Level, entry.MaxLevel)

		for pipIndex, pip in ipairs(row.Pips) do
			pip.BackgroundColor3 = pipIndex <= entry.Level and THEME.Shadow or THEME.Locked
		end

		local maxed = entry.Level >= entry.MaxLevel
		local affordable = entry.Cost ~= nil and state.Balance >= entry.Cost

		-- Drives the shared affordability pulse. Set before the branches so
		-- every path below agrees with it.
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
			row.Buy.BackgroundColor3 = THEME.Shadow
			row.Buy.TextColor3 = Color3.fromRGB(24, 12, 40)
			row.Stroke.Color = THEME.Shadow
			-- Transparency deliberately NOT set here: the affordability
			-- pulse owns that property while a row is affordable, and
			-- writing it on every render would fight the tween mid-cycle.
		else
			row.Buy.Text = formatNumber(entry.Cost or 0)
			row.Buy.BackgroundColor3 = THEME.Locked
			row.Buy.TextColor3 = THEME.Grey
			row.Stroke.Color = THEME.Locked
			row.Stroke.Transparency = 0.3
		end

		-- Celebrate an actual level gain.
		local previous = lastLevels[index]
		if previous ~= nil and entry.Level > previous then
			Juice.Punch(Juice.GetScale(row.Row), 0.06, 0.3)

			-- Explicit flash-and-return rather than Juice.PulseBackground:
			-- that helper caches a "base" colour the first time it runs and
			-- restores to it, which goes stale now that hover also changes
			-- this row's background -- buying while hovering would have
			-- pinned the row to the hover colour permanently.
			row.Row.BackgroundColor3 = THEME.Shadow
			tween(row.Row, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundColor3 = THEME.Row,
			}):Play()

			if juiceLayer then
				local center = Juice.CenterOf(row.Icon, juiceLayer)
				if center then
					Juice.Burst(juiceLayer, center, {
						Count = 14,
						Colors = { THEME.Shadow, THEME.White, THEME.Green },
						Distance = 150,
						Duration = 0.7,
						Size = { 4, 10 },
						ZIndex = 200,
					})
					Juice.Ring(juiceLayer, center, {
						Color = THEME.Shadow,
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
-- A new button quietly appearing on the edge of the screen is easy to
-- never notice, and Shadow Essence spent years being useless -- players
-- have no reason to expect it's suddenly spendable. The first time
-- something becomes affordable, the button says so once.

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
				Color = THEME.Shadow,
				StartSize = 40,
				EndSize = 170,
				Duration = 0.6,
				Thickness = 3,
			})
			-- Offset upward so the label clears the button itself.
			Juice.FloatText(juiceLayer, center - UDim2.fromOffset(0, 50), "Sanctum ready!", {
				Color = THEME.Shadow,
				Duration = 1.6,
				Rise = 44,
				TextSize = 24,
			})
		end
	end
end

-- Slow pulse on the badge, matching the progression buttons so the whole
-- left edge behaves consistently.
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

	-- Ask for a fresh read every time the panel opens rather than trusting
	-- whatever the last push happened to contain -- self-heals from any
	-- timing edge case that causes the initial join-time sync to be missed.
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
	state.Lifetime = tonumber(payload.Lifetime) or 0
	state.Upgrades = payload.Upgrades or {}

	render()

	if openBadge.Visible then
		announceOnce()
	end
end)

--[[
	ZonePanel (LocalScript -> StarterPlayerScripts)
	===================================================
	Client for Zones (see ZonesConfig.luau, ZoneService.server.luau): a
	picker panel listing every zone, showing its lock state, unlock cost,
	and effective essence odds, plus a full-screen travel animation played
	on a CONFIRMED switch -- never optimistically before the server
	responds, same discipline WheelPanel's spin visual follows.

	Unlike this codebase's other side-panel scripts (Wheel, Achievements,
	Sanctum, ...), the trigger BUTTON itself is not built here -- it's
	authored directly in Studio as MainGui.Right.Holder.ZonesButton (this
	file only ever wires its click), the same Holder subfolder
	UIInitializerHooks.client.luau's own nav-bar block already iterates.
	If ZonesButton never appears, this script quietly does nothing rather
	than erroring -- there's no fallback button to build in its place;
	whoever places it controls that. Resolves to either the instance
	itself (if it's already a real GuiButton) or a nested TextButton/
	ImageButton inside it, since that nav-bar block's own convention for
	this folder wraps each button in a plain Frame rather than using a
	button class directly -- ZonesButton might follow either shape.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ZonesConfig = require(ReplicatedStorage:WaitForChild("ZonesConfig"))
local LuckGamepassConfig = require(ReplicatedStorage:WaitForChild("LuckGamepassConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local formatNumber = ProgressionConfig.FormatNumber

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("ZoneRemotes", 15)
if not remotesFolder then
	warn("ZonePanel: ZoneRemotes never appeared -- Zones UI disabled this session.")
	return
end

local UnlockZoneFunction = remotesFolder:WaitForChild("UnlockZone", 15)
local SwitchZoneFunction = remotesFolder:WaitForChild("SwitchZone", 15)
if not (UnlockZoneFunction and SwitchZoneFunction) then
	warn("ZonePanel: UnlockZone/SwitchZone never appeared -- Zones UI disabled this session.")
	return
end

-- The button is Studio-authored, not built here -- see the file header.
-- Generous timed waits (not bare WaitForChild) so a slow-to-replicate
-- MainGui never hangs this whole script if ZonesButton is missing/renamed;
-- it just quietly does nothing instead.
local mainGui = playerGui:WaitForChild("MainGui", 15)
local rightHolster = mainGui and mainGui:WaitForChild("Right", 15)
local rightHolder = rightHolster and rightHolster:WaitForChild("Holder", 15)
local zonesButtonInstance = rightHolder and rightHolder:WaitForChild("ZonesButton", 15)
if not zonesButtonInstance then
	warn("ZonePanel: MainGui.Right.Holder.ZonesButton never appeared -- place it to enable the Zones UI.")
	return
end

-- ZonesButton might be a real GuiButton directly, or a plain Frame
-- wrapping one (see the file header) -- resolve to whichever actually
-- has a click event before wiring anything to it.
local zonesButton = zonesButtonInstance:IsA("GuiButton") and zonesButtonInstance
	or zonesButtonInstance:FindFirstChildOfClass("TextButton")
	or zonesButtonInstance:FindFirstChildOfClass("ImageButton")
if not zonesButton then
	warn("ZonePanel: ZonesButton exists but isn't a GuiButton and has no nested TextButton/ImageButton -- can't wire a click to it.")
	return
end

-- =========================================================================
-- THEME + LAYOUT (matches WheelPanel/AchievementsPanel's modal conventions)
-- =========================================================================

local THEME = {
	Background      = Color3.fromRGB(24, 12, 40),
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(146, 136, 160),
	Locked          = Color3.fromRGB(58, 50, 76),
}

local PANEL_SIZE = UDim2.fromScale(0.44, 0.6)

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
	return new("UICorner", { CornerRadius = radius or UDim.new(0.08, 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color or THEME.Accent, Thickness = thickness or 2, Transparency = transparency or 0 }, parent)
end

local function tween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

-- =========================================================================
-- SCREEN GUI
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "ZonePanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 60,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- =========================================================================
-- PANEL SCAFFOLDING
-- =========================================================================

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 200,
}, screenGui)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = PANEL_SIZE,
	BackgroundColor3 = THEME.Background,
	Visible = false,
	ZIndex = 201,
}, screenGui)
corner(panel, UDim.new(0.04, 0))
stroke(panel, THEME.Accent, 2.5)
local panelScale = new("UIScale", { Scale = 0.85 }, panel)

new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.1, 0.03),
	Size = UDim2.fromScale(0.8, 0.08),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🗺️ Zones",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 202,
}, panel)
new("UITextSizeConstraint", { MaxTextSize = 28 }, panel.Title)

local subtitle = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.08, 0.105),
	Size = UDim2.fromScale(0.84, 0.05),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 202,
}, panel)
new("UITextSizeConstraint", { MaxTextSize = 15 }, subtitle)

local closeButton = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.965, 0.028),
	Size = UDim2.fromScale(0.065, 0.065),
	BackgroundColor3 = THEME.Locked,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "X",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 203,
}, panel)
corner(closeButton, UDim.new(0.3, 0))
Juice.ButtonFeel(closeButton, {})

local statusLabel = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.985),
	Size = UDim2.fromScale(0.94, 0.045),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 202,
}, panel)
new("UITextSizeConstraint", { MaxTextSize = 14 }, statusLabel)

-- =========================================================================
-- ZONE LIST
-- =========================================================================

local listHolder = new("ScrollingFrame", {
	Name = "List",
	Position = UDim2.fromScale(0.04, 0.17),
	Size = UDim2.fromScale(0.92, 0.74),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = THEME.Accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 202,
}, panel)

-- Keep cards and their strokes clear of both rounded edges and the
-- scrollbar. AutomaticCanvasSize includes this bottom inset, so the last
-- card can be scrolled fully into view rather than appearing clipped.
new("UIPadding", {
	PaddingLeft = UDim.new(0, 4),
	PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 2),
	PaddingBottom = UDim.new(0, 10),
}, listHolder)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, listHolder)

local ROW_HEIGHT = 138

-- Forward-declared: defined further down (STATE + ACTIONS / OPEN + CLOSE
-- sections), but captured now by every card's click handler below -- same
-- "declare local now, assign the real function later" pattern Tutorial.
-- client.luau already uses for dialogueText/nextButton/updateProgressDots,
-- which works because Lua closures capture the upvalue itself, not
-- whatever value it happened to hold at closure-creation time.
local requestZoneAction
local closePanel

-- One entry per configured zone: { Zone, Card, ActionButton, ActionLabel, OddsLabel, HereBadge }
local cards = {}

for index, zone in ipairs(ZonesConfig.Zones) do
	local card = new("Frame", {
		Name = "Card_" .. zone.Id,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = THEME.BackgroundLight,
		ZIndex = 202,
	}, listHolder)
	corner(card, UDim.new(0, 12))
	local cardStroke = stroke(card, zone.Color, 2, 0.35)

	local iconBg = new("Frame", {
		Name = "IconBg",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.045, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = zone.Color,
		ZIndex = 203,
	}, card)
	corner(iconBg, UDim.new(0.5, 0))
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, iconBg)
	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = zone.Icon,
		TextScaled = true,
		ZIndex = 204,
	}, iconBg)

	new("TextLabel", {
		Name = "Name",
		Position = UDim2.new(0.26, 0, 0.08, 0),
		Size = UDim2.new(0.42, 0, 0.24, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = zone.Name,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 203,
	}, card)

	new("TextLabel", {
		Name = "Description",
		Position = UDim2.new(0.26, 0, 0.32, 0),
		-- Stop before the action column. The previous 68%-wide box ended at
		-- 94% and rendered underneath the button, whose left edge is ~72%.
		Size = UDim2.new(0.43, 0, 0.3, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = zone.Description,
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 203,
	}, card)

	local oddsLabel = new("TextLabel", {
		Name = "Odds",
		Position = UDim2.new(0.26, 0, 0.66, 0),
		Size = UDim2.new(0.43, 0, 0.24, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 203,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 15 }, oddsLabel)

	local actionButton = new("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.975, 0, 0.5, 0),
		Size = UDim2.new(0.26, 0, 0.42, 0),
		BackgroundColor3 = THEME.Green,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = THEME.Background,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 203,
	}, card)
	corner(actionButton, UDim.new(0.2, 0))
	new("UITextSizeConstraint", { MaxTextSize = 16 }, actionButton)
	Juice.ButtonFeel(actionButton, {})

	cards[zone.Id] = {
		Zone = zone,
		Card = card,
		Stroke = cardStroke,
		OddsLabel = oddsLabel,
		ActionButton = actionButton,
	}

	actionButton.MouseButton1Click:Connect(function()
		requestZoneAction(zone)
	end)
end

-- =========================================================================
-- TRAVEL TRANSITION
-- =========================================================================
-- A full-screen veil rather than a circular wipe on purpose: a wipe needs
-- careful diagonal-coverage math to guarantee it actually reaches every
-- corner on an unusual (ultra-wide, ultra-tall mobile) aspect ratio -- a
-- plain full-screen fade gets the same "somewhere else now" beat with zero
-- risk of a screen corner ever peeking out uncovered.

local transitionGui = new("ScreenGui", {
	Name = "ZoneTransition",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 150,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local veil = new("Frame", {
	Name = "Veil",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 500,
}, transitionGui)

local cardHolder = new("Frame", {
	Name = "Card",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromScale(0.5, 0.24),
	BackgroundTransparency = 1,
	ZIndex = 501,
}, veil)
local cardScale = new("UIScale", { Scale = 0.7 }, cardHolder)

local transitionIcon = new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 0.55),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextTransparency = 1,
	ZIndex = 502,
}, cardHolder)

local transitionName = new("TextLabel", {
	Name = "Name",
	Position = UDim2.fromScale(0, 0.58),
	Size = UDim2.fromScale(1, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextTransparency = 1,
	ZIndex = 502,
}, cardHolder)
new("UITextSizeConstraint", { MaxTextSize = 30 }, transitionName)

local transitionSub = new("TextLabel", {
	Name = "Sub",
	Position = UDim2.fromScale(0, 0.82),
	Size = UDim2.fromScale(1, 0.16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Traveling...",
	TextColor3 = Color3.fromRGB(225, 220, 232),
	TextScaled = true,
	TextTransparency = 1,
	ZIndex = 502,
}, cardHolder)
new("UITextSizeConstraint", { MaxTextSize = 16 }, transitionSub)

local COVER_TIME = 0.45
local HOLD_TIME = 0.9
local RELEASE_TIME = 0.5

-- Plays a confirmed travel to `zone` and calls onComplete once the veil
-- has fully lifted again. Never called optimistically before the server
-- responds -- see requestZoneAction below.
local function playZoneTransition(zone, onComplete)
	veil.Visible = true
	veil.BackgroundColor3 = zone.Color
	veil.BackgroundTransparency = 1
	cardScale.Scale = 0.7
	transitionIcon.Text = zone.Icon
	transitionName.Text = zone.Name
	for _, label in ipairs({ transitionIcon, transitionName, transitionSub }) do
		label.TextTransparency = 1
	end

	local coverTween = tween(veil, TweenInfo.new(COVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.05,
	})
	coverTween:Play()
	coverTween.Completed:Connect(function()
		tween(cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		for _, label in ipairs({ transitionIcon, transitionName, transitionSub }) do
			tween(label, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		end

		Juice.Burst(veil, UDim2.fromScale(0.5, 0.46), {
			Count = 16,
			Colors = { THEME.White, zone.Color },
			Distance = 220,
			Duration = 0.8,
			ZIndex = 503,
		})
	end)

	task.delay(COVER_TIME + HOLD_TIME, function()
		for _, label in ipairs({ transitionIcon, transitionName, transitionSub }) do
			tween(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		end

		local releaseTween = tween(veil, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		releaseTween:Play()
		releaseTween.Completed:Connect(function()
			veil.Visible = false
			if onComplete then
				onComplete()
			end
		end)
	end)
end

-- =========================================================================
-- STATE + ACTIONS
-- =========================================================================

local actionInFlight = false

-- Rebuilds every card's dynamic bits (odds text, HERE/TRAVEL/UNLOCK
-- button) off the current attributes -- safe to call as often as needed
-- (currency ticking up, a switch/unlock landing, the panel opening).
local function refresh()
	local currentZoneId = ZonesConfig.GetCurrentZoneId(player)
	local currentZone = ZonesConfig.GetZoneById(currentZoneId)
	subtitle.Text = ("📍 Currently in: %s %s"):format(currentZone and currentZone.Icon or "", currentZone and currentZone.Name or "")

	local leaderstats = player:FindFirstChild("leaderstats")
	local earthStat = leaderstats and leaderstats:FindFirstChild("Earth Essence")
	local earthQuantity = earthStat and tonumber(earthStat:GetAttribute("Quantity")) or 0

	-- Dedicated Essence amplifies WHICHEVER zone you're standing in, not
	-- just the one you happen to be in right now -- so every card's
	-- preview should reflect ownership the same way, not only the active
	-- one. This is a preview only: the real roll (GetEssence.luau) always
	-- re-reads both live at collection time regardless of what this shows.
	local ownsDedicatedEssence = player:GetAttribute(ZonesConfig.DedicatedEssenceGamepassId) == true
	local rareEssenceMultiplier = LuckGamepassConfig.GetRareEssenceMultiplier(player)

	for zoneId, entry in pairs(cards) do
		local zone = entry.Zone
		local baseWeights = (ownsDedicatedEssence and zone.AmplifiedWeights) or zone.BaseWeights
		-- Same "multiply the rarer essence's weight" math ZonesConfig.
		-- GetEssenceWeights applies to the real roll -- mirrored here
		-- rather than called directly, since that function only ever
		-- returns the CURRENT zone's weights and this loop previews
		-- every zone, active or not.
		local weights = {
			["Earth Essence"] = baseWeights["Earth Essence"] or 0,
			["Shadow Essence"] = (baseWeights["Shadow Essence"] or 0) * rareEssenceMultiplier,
		}
		local total = weights["Earth Essence"] + weights["Shadow Essence"]
		local earthPct, shadowPct = 0, 0
		if total > 0 then
			earthPct = math.floor(100 * weights["Earth Essence"] / total + 0.5)
			shadowPct = math.floor(100 * weights["Shadow Essence"] / total + 0.5)
		end

		entry.OddsLabel.Text = ("🌍 %d%%  •  🌑 %d%%"):format(earthPct, shadowPct)

		local isCurrent = zoneId == currentZoneId
		local unlocked = ZonesConfig.IsZoneUnlocked(player, zoneId)

		entry.Stroke.Transparency = isCurrent and 0 or 0.35
		entry.Stroke.Thickness = isCurrent and 3 or 2

		local button = entry.ActionButton
		if actionInFlight then
			button.Active = false
			button.BackgroundColor3 = THEME.Locked
			button.Text = "..."
		elseif isCurrent then
			button.Active = false
			button.BackgroundColor3 = THEME.Locked
			button.Text = "📍 HERE"
		elseif unlocked then
			button.Active = true
			button.BackgroundColor3 = THEME.Green
			button.Text = "TRAVEL"
		else
			local canAfford = earthQuantity >= zone.UnlockCost
			button.Active = canAfford
			button.BackgroundColor3 = canAfford and THEME.Accent or THEME.Locked
			button.Text = ("🔒 UNLOCK\n%s Essence"):format(formatNumber(zone.UnlockCost))
		end
	end
end

requestZoneAction = function(zone)
	if actionInFlight then
		return
	end

	local currentZoneId = ZonesConfig.GetCurrentZoneId(player)
	if zone.Id == currentZoneId then
		return
	end

	local unlocked = ZonesConfig.IsZoneUnlocked(player, zone.Id)
	local remoteFn = unlocked and SwitchZoneFunction or UnlockZoneFunction

	actionInFlight = true
	statusLabel.Text = ""
	refresh()

	local ok, success, message = pcall(function()
		return remoteFn:InvokeServer(zone.Id)
	end)

	actionInFlight = false

	if not ok or not success then
		statusLabel.Text = (ok and message) or "Something went wrong -- try again."
		refresh()
		return
	end

	statusLabel.Text = ""
	refresh()
	closePanel()
	playZoneTransition(zone)
end

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local open = false

closePanel = function()
	if not open then
		return
	end
	open = false

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local outTween = tween(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.85 })
	outTween:Play()
	outTween.Completed:Connect(function()
		if not open then
			panel.Visible = false
			backdrop.Visible = false
		end
	end)
end

local function openPanel()
	if open then
		return
	end
	open = true

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	panel.Visible = true
	panelScale.Scale = 0.85
	tween(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	refresh()
end

zonesButton.Activated:Connect(openPanel)
closeButton.MouseButton1Click:Connect(closePanel)
backdrop.MouseButton1Click:Connect(closePanel)

-- =========================================================================
-- LIVE REFRESH
-- =========================================================================
-- Attributes are the only channel any of this reads (see ZonesConfig) --
-- listening for these specific ones covers every way this panel's own
-- state can change: a switch/unlock landing (CurrentZoneId, either
-- Zone_*_Unlocked), owning Dedicated Essence/Lucky Finder/Ultra Luck
-- mid-session (each changes the odds shown), or the balance moving
-- enough to afford a locked zone that couldn't be before.

player:GetAttributeChangedSignal("CurrentZoneId"):Connect(refresh)
player:GetAttributeChangedSignal(ZonesConfig.DedicatedEssenceGamepassId):Connect(refresh)
player:GetAttributeChangedSignal(LuckGamepassConfig.LuckyFinderGamepassId):Connect(refresh)
player:GetAttributeChangedSignal(LuckGamepassConfig.UltraLuckGamepassId):Connect(refresh)
for _, zone in ipairs(ZonesConfig.Zones) do
	if zone.UnlockCost > 0 then
		player:GetAttributeChangedSignal(ZonesConfig.UnlockedAttributeName(zone.Id)):Connect(refresh)
	end
end

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 15)
	local earthStat = leaderstats and leaderstats:WaitForChild("Earth Essence", 15)
	if earthStat then
		earthStat:GetAttributeChangedSignal("Quantity"):Connect(refresh)
	end
end)

refresh()

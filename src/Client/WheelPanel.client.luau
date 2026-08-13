--[[
	WheelPanel (LocalScript -> StarterPlayerScripts)
	===================================================
	Premium client presentation for the server-authoritative Fortune Wheel.
	The server chooses and grants every reward before this UI begins moving;
	the wheel only animates toward the SegmentIndex it receives.

	The wheel is built entirely from native Roblox UI: layered circular
	frames, radial dividers, jewel reward pedestals, orbiting bulbs, gradients,
	stars and a fixed mechanical pointer. No authored image asset is needed,
	so the complete experience survives a filesystem-to-Studio sync.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local WheelConfig = require(ReplicatedStorage:WaitForChild("WheelConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("WheelRemotes", 20)
if not remotesFolder then
	warn("WheelPanel: WheelRemotes never appeared -- Fortune Wheel UI disabled this session.")
	return
end

local SyncRemote = remotesFolder:WaitForChild("WheelSync", 10)
local SpinFunction = remotesFolder:WaitForChild("SpinWheel", 10)
local GetStateFunction = remotesFolder:WaitForChild("GetWheelState", 10)
if not SyncRemote or not SpinFunction or not GetStateFunction then
	warn("WheelPanel: required remotes are missing -- Fortune Wheel UI disabled this session.")
	return
end

-- =========================================================================
-- THEME + HELPERS
-- =========================================================================

local THEME = {
	Void = Color3.fromRGB(7, 6, 18),
	Background = Color3.fromRGB(18, 13, 34),
	Surface = Color3.fromRGB(34, 25, 55),
	SurfaceRaised = Color3.fromRGB(49, 35, 72),
	SurfaceDeep = Color3.fromRGB(13, 11, 28),
	Gold = Color3.fromRGB(255, 187, 66),
	GoldLight = Color3.fromRGB(255, 231, 154),
	Orange = Color3.fromRGB(255, 121, 49),
	Cyan = Color3.fromRGB(82, 220, 255),
	Green = Color3.fromRGB(72, 221, 143),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(185, 174, 205),
	Dim = Color3.fromRGB(124, 109, 149),
	Locked = Color3.fromRGB(60, 51, 79),
}

local LAYOUT = {
	ButtonAnchor = Vector2.new(1, 1),
	ButtonPosition = UDim2.fromScale(0.985, 0.97),
	ButtonSize = UDim2.fromScale(0.068, 0.068),
	ButtonMinSize = Vector2.new(64, 64),
	ButtonMaxSize = Vector2.new(86, 86),
	PanelSize = UDim2.fromScale(0.72, 0.82),
	PanelMinSize = Vector2.new(340, 340),
	PanelMaxSize = Vector2.new(980, 700),
}

local function new(className: string, props, parent: Instance?)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent: Instance, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 12) }, parent)
end

local function stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return new("UIStroke", {
		Color = color or THEME.Gold,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	}, parent)
end

local function tween(instance: Instance, info: TweenInfo, props)
	return TweenService:Create(instance, info, props)
end

local function textConstraint(label: Instance, maxSize: number, minSize: number?)
	return new("UITextSizeConstraint", {
		MaxTextSize = maxSize,
		MinTextSize = minSize or 7,
	}, label)
end

local function tierData(segment)
	return WheelConfig.GetTier(segment)
end

local function formatDuration(seconds: number): string
	return ProgressionConfig.FormatDuration(math.max(0, math.ceil(seconds)))
end

local function rewardSummary(result): string
	local lines = { ("+%s ESSENCE"):format(ProgressionConfig.FormatNumber(result.Essence or 0)) }
	if (result.SolarEssence or 0) > 0 then
		table.insert(lines, ("+%s SOLAR ESSENCE"):format(ProgressionConfig.FormatNumber(result.SolarEssence)))
	end
	if result.Shards then
		table.insert(lines, ("+%d PRESTIGE SHARDS"):format(result.Shards))
	end
	if result.PotionLabel then
		table.insert(lines, string.upper(result.PotionLabel))
	end
	return table.concat(lines, "\n")
end

-- =========================================================================
-- ROOT + PREMIUM SHORTCUT
-- =========================================================================

local oldGui = playerGui:FindFirstChild("WheelPanel")
if oldGui then
	oldGui:Destroy()
end

local screenGui = new("ScreenGui", {
	Name = "WheelPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 68,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local buttonHolder = new("Frame", {
	Name = "ButtonHolder",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundTransparency = 1,
	ZIndex = 50,
}, screenGui)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, buttonHolder)
new("UISizeConstraint", { MinSize = LAYOUT.ButtonMinSize, MaxSize = LAYOUT.ButtonMaxSize }, buttonHolder)

local shortcutAura = new("Frame", {
	Name = "Aura",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.3, 1.3),
	BackgroundColor3 = THEME.Gold,
	BackgroundTransparency = 0.84,
	ZIndex = 49,
}, buttonHolder)
corner(shortcutAura, UDim.new(0.5, 0))
local shortcutAuraScale = new("UIScale", { Scale = 1 }, shortcutAura)

local shortcutOrbit = new("Frame", {
	Name = "Orbit",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.12, 1.12),
	BackgroundTransparency = 1,
	ZIndex = 50,
}, buttonHolder)
corner(shortcutOrbit, UDim.new(0.5, 0))
stroke(shortcutOrbit, THEME.GoldLight, 1.5, 0.28)
for index = 1, 6 do
	local angle = math.rad((index - 1) * 60)
	local light = new("Frame", {
		Name = "Light" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.5, 0.5 - math.cos(angle) * 0.5),
		Size = UDim2.fromScale(0.1, 0.1),
		BackgroundColor3 = index % 2 == 0 and THEME.Cyan or THEME.GoldLight,
		ZIndex = 51,
	}, shortcutOrbit)
	corner(light, UDim.new(0.5, 0))
end

local wheelButton = new("TextButton", {
	Name = "Button",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Surface,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 52,
}, buttonHolder)
corner(wheelButton, UDim.new(0.3, 0))
local wheelButtonStroke = stroke(wheelButton, THEME.Gold, 3, 0.04)
local buttonGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(105, 54, 27)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(55, 35, 69)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(21, 17, 40)),
	}),
	Rotation = 135,
}, wheelButton)

new("TextLabel", {
	Name = "Icon",
	Position = UDim2.fromScale(0.03, 0.02),
	Size = UDim2.fromScale(0.94, 0.69),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🎡",
	TextScaled = true,
	ZIndex = 53,
}, wheelButton)

local shortcutCaption = new("TextLabel", {
	Name = "Caption",
	Position = UDim2.fromScale(0.08, 0.71),
	Size = UDim2.fromScale(0.84, 0.2),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "DAILY",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 53,
}, wheelButton)
textConstraint(shortcutCaption, 14, 7)

local availabilityBadge = new("TextLabel", {
	Name = "Availability",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1.04, -0.04),
	Size = UDim2.fromScale(0.54, 0.24),
	BackgroundColor3 = THEME.Green,
	Font = Enum.Font.GothamBlack,
	Text = "FREE",
	TextColor3 = THEME.Void,
	TextScaled = true,
	Visible = false,
	ZIndex = 55,
}, wheelButton)
corner(availabilityBadge, UDim.new(0.5, 0))
stroke(availabilityBadge, THEME.White, 1.5, 0.05)
textConstraint(availabilityBadge, 12, 7)
local availabilityScale = new("UIScale", { Scale = 1 }, availabilityBadge)

Juice.ButtonFeel(wheelButton, { HoverScale = 1.07 })

-- =========================================================================
-- MODAL SHELL + RESPONSIVE PADDING
-- =========================================================================

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(2, 1, 7),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 250,
}, screenGui)
backdrop:SetAttribute("PresentationModal", true)

local panelShadow = new("Frame", {
	Name = "PanelShadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.512),
	Size = LAYOUT.PanelSize + UDim2.fromOffset(18, 18),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.42,
	Visible = false,
	ZIndex = 250,
}, screenGui)
corner(panelShadow, UDim.new(0.045, 0))
new("UISizeConstraint", {
	MinSize = LAYOUT.PanelMinSize + Vector2.new(18, 18),
	MaxSize = LAYOUT.PanelMaxSize + Vector2.new(18, 18),
}, panelShadow)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = LAYOUT.PanelSize,
	BackgroundColor3 = THEME.Background,
	Visible = false,
	ClipsDescendants = false,
	ZIndex = 251,
}, screenGui)
corner(panel, UDim.new(0.045, 0))
local panelStroke = stroke(panel, THEME.Gold, 3, 0.04)
new("UISizeConstraint", {
	MinSize = LAYOUT.PanelMinSize,
	MaxSize = LAYOUT.PanelMaxSize,
}, panel)
new("UIPadding", {
	PaddingLeft = UDim.new(0.04, 0),
	PaddingRight = UDim.new(0.04, 0),
	PaddingTop = UDim.new(0.035, 0),
	PaddingBottom = UDim.new(0.035, 0),
}, panel)
local panelScale = new("UIScale", { Scale = 0.84 }, panel)
local panelGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(53, 27, 66)),
		ColorSequenceKeypoint.new(0.42, THEME.Background),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 12, 31)),
	}),
	Rotation = 120,
}, panel)

-- Effects use their own content-space layer. Because the panel has
-- UIPadding, measuring against the outer panel would shift rings and bursts
-- away from the hub by the padding inset on some viewport sizes.
local effectLayer = new("Frame", {
	Name = "EffectLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = false,
	ZIndex = 287,
}, panel)

local topRail = new("Frame", {
	Name = "TopRail",
	Position = UDim2.fromScale(0.08, -0.012),
	Size = UDim2.fromScale(0.84, 0.018),
	BackgroundColor3 = THEME.GoldLight,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	ZIndex = 252,
}, panel)
corner(topRail, UDim.new(0.5, 0))
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, topRail)

local title = new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.025, 0.005),
	Size = UDim2.fromScale(0.79, 0.08),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🎡  THE ASTRAL FORTUNE WHEEL",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 253,
}, panel)
textConstraint(title, 30, 11)

local subtitle = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.03, 0.085),
	Size = UDim2.fromScale(0.78, 0.04),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "One free spin daily • Earn another ticket every 60 collections",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 253,
}, panel)
textConstraint(subtitle, 15, 7)

local closeButton = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.978, 0.01),
	Size = UDim2.fromScale(0.06, 0.068),
	BackgroundColor3 = THEME.SurfaceRaised,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "×",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 257,
}, panel)
corner(closeButton, UDim.new(0.32, 0))
stroke(closeButton, THEME.GoldLight, 1.5, 0.25)
Juice.ButtonFeel(closeButton, { HoverScale = 1.08 })

-- =========================================================================
-- TICKET CHARGE STRIP
-- =========================================================================

local chargeCard = new("Frame", {
	Name = "ChargeCard",
	Position = UDim2.fromScale(0.025, 0.14),
	Size = UDim2.fromScale(0.95, 0.078),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.04,
	ZIndex = 253,
}, panel)
corner(chargeCard, UDim.new(0.35, 0))
stroke(chargeCard, THEME.Gold, 1.5, 0.42)
new("UIPadding", {
	PaddingLeft = UDim.new(0.025, 0),
	PaddingRight = UDim.new(0.025, 0),
	PaddingTop = UDim.new(0.14, 0),
	PaddingBottom = UDim.new(0.14, 0),
}, chargeCard)

local ticketIcon = new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(0.06, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🎟️",
	TextScaled = true,
	ZIndex = 254,
}, chargeCard)
local ticketText = new("TextLabel", {
	Name = "Tickets",
	Position = UDim2.fromScale(0.07, 0),
	Size = UDim2.fromScale(0.24, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "0 TICKETS BANKED",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 254,
}, chargeCard)
textConstraint(ticketText, 14, 7)

local chargeTrack = new("Frame", {
	Name = "Track",
	Position = UDim2.fromScale(0.33, 0.29),
	Size = UDim2.fromScale(0.34, 0.42),
	BackgroundColor3 = THEME.Locked,
	ZIndex = 254,
}, chargeCard)
corner(chargeTrack, UDim.new(0.5, 0))
local chargeFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Cyan,
	ZIndex = 255,
}, chargeTrack)
corner(chargeFill, UDim.new(0.5, 0))
new("UIGradient", {
	Color = ColorSequence.new(THEME.Cyan, THEME.Gold),
}, chargeFill)
local chargeAmount = new("TextLabel", {
	Name = "Amount",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "0 / 60",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 256,
}, chargeTrack)
textConstraint(chargeAmount, 11, 6)

local freeStatus = new("TextLabel", {
	Name = "FreeStatus",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.99, 0),
	Size = UDim2.fromScale(0.29, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "FREE SPIN READY",
	TextColor3 = THEME.Green,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 254,
}, chargeCard)
textConstraint(freeStatus, 14, 7)

-- =========================================================================
-- ILLUMINATED WHEEL STAGE
-- =========================================================================

local wheelStage = new("Frame", {
	Name = "WheelStage",
	Position = UDim2.fromScale(0.01, 0.235),
	Size = UDim2.fromScale(0.63, 0.55),
	BackgroundTransparency = 1,
	ZIndex = 253,
}, panel)

local stageStars = {
	{ .05, .16, "✦" }, { .14, .03, "·" }, { .3, .08, "✧" }, { .77, .04, "·" },
	{ .91, .18, "✦" }, { .98, .49, "·" }, { .86, .8, "✧" }, { .63, .92, "·" },
	{ .3, .91, "✦" }, { .08, .76, "·" }, { .01, .48, "✧" }, { .69, .13, "·" },
}
for index, starData in ipairs(stageStars) do
	local star = new("TextLabel", {
		Name = "Star" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(starData[1], starData[2]),
		Size = UDim2.fromScale(0.05, 0.07),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = starData[3],
		TextColor3 = index % 2 == 0 and THEME.Cyan or THEME.GoldLight,
		TextTransparency = 0.45,
		TextScaled = true,
		ZIndex = 254,
	}, wheelStage)
	tween(star, TweenInfo.new(0.8 + index * 0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.85,
		Rotation = index % 2 == 0 and 35 or -35,
	}):Play()
end

local wheelHolder = new("Frame", {
	Name = "WheelHolder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.48),
	Size = UDim2.fromScale(0.8, 0.94),
	BackgroundTransparency = 1,
	ZIndex = 255,
}, wheelStage)
local wheelAspect = new("UIAspectRatioConstraint", {
	AspectRatio = 1,
	DominantAxis = Enum.DominantAxis.Height,
}, wheelHolder)

-- Fit the square to whichever dimension is tighter. Landscape play is
-- height-bound; tall/narrow mobile play is width-bound, so the wheel never
-- bleeds into the ledger even when the modal itself hits its minimum width.
local function updateWheelDominantAxis()
	local stageSize = wheelStage.AbsoluteSize
	if stageSize.X <= 0 or stageSize.Y <= 0 then
		return
	end
	local proposedWidth = stageSize.X * 0.8
	local proposedHeight = stageSize.Y * 0.94
	wheelAspect.DominantAxis = proposedWidth <= proposedHeight and Enum.DominantAxis.Width or Enum.DominantAxis.Height
end

wheelStage:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateWheelDominantAxis)
task.defer(updateWheelDominantAxis)

local farGlow = new("Frame", {
	Name = "FarGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.32, 1.32),
	BackgroundColor3 = THEME.Gold,
	BackgroundTransparency = 0.88,
	ZIndex = 255,
}, wheelHolder)
corner(farGlow, UDim.new(0.5, 0))
local farGlowScale = new("UIScale", { Scale = 1 }, farGlow)

local energyRingOuter = new("Frame", {
	Name = "OuterEnergyRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.18, 1.18),
	BackgroundTransparency = 1,
	ZIndex = 256,
}, wheelHolder)
corner(energyRingOuter, UDim.new(0.5, 0))
stroke(energyRingOuter, THEME.GoldLight, 2, 0.32)
for index = 1, 12 do
	local angle = math.rad((index - 1) * 30)
	local glyph = new("TextLabel", {
		Name = "Glyph" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.5, 0.5 - math.cos(angle) * 0.5),
		Size = UDim2.fromScale(0.075, 0.075),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = index % 3 == 0 and "◆" or "✦",
		TextColor3 = index % 2 == 0 and THEME.Cyan or THEME.GoldLight,
		TextTransparency = 0.2,
		TextScaled = true,
		ZIndex = 257,
	}, energyRingOuter)
	textConstraint(glyph, 18, 6)
end

local energyRingInner = new("Frame", {
	Name = "InnerEnergyRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.08, 1.08),
	BackgroundTransparency = 1,
	ZIndex = 257,
}, wheelHolder)
corner(energyRingInner, UDim.new(0.5, 0))
stroke(energyRingInner, THEME.Cyan, 1.5, 0.45)

local wheelBase = new("Frame", {
	Name = "WheelBase",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Surface,
	ClipsDescendants = false,
	ZIndex = 258,
}, wheelHolder)
corner(wheelBase, UDim.new(0.5, 0))
local wheelBaseStroke = stroke(wheelBase, THEME.Gold, 5, 0.02)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(86, 44, 40)),
		ColorSequenceKeypoint.new(0.34, Color3.fromRGB(46, 31, 72)),
		ColorSequenceKeypoint.new(0.68, Color3.fromRGB(25, 39, 68)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(74, 42, 35)),
	}),
	Rotation = 45,
}, wheelBase)

local wheelInset = new("Frame", {
	Name = "Inset",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.89, 0.89),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.18,
	ZIndex = 259,
}, wheelBase)
corner(wheelInset, UDim.new(0.5, 0))
stroke(wheelInset, THEME.GoldLight, 2, 0.48)

local wheelRing = new("Frame", {
	Name = "WheelRing",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 260,
}, wheelBase)

local SEGMENT_COUNT = WheelConfig.SegmentCount
local SEGMENT_ANGLE = 360 / SEGMENT_COUNT
local BADGE_ORBIT_SCALE = 0.36
local BADGE_SIZE_SCALE = 0.205

-- Radial separators turn the circular face into eight readable physical
-- slots even though Roblox has no native pie-wedge UI primitive.
for index = 1, SEGMENT_COUNT do
	local spoke = new("Frame", {
		Name = "Spoke" .. index,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.012, 0.43),
		BackgroundColor3 = index % 2 == 0 and THEME.Cyan or THEME.Gold,
		BackgroundTransparency = 0.56,
		BorderSizePixel = 0,
		Rotation = (index - 1) * SEGMENT_ANGLE + SEGMENT_ANGLE / 2,
		ZIndex = 260,
	}, wheelRing)
	corner(spoke, UDim.new(0.5, 0))
end

local badges = {}
local badgeStrokes = {}
local badgeScales = {}

for index, segment in ipairs(WheelConfig.Segments) do
	local angleDeg = (index - 1) * SEGMENT_ANGLE
	local angleRad = math.rad(angleDeg)
	local offsetX = math.sin(angleRad) * BADGE_ORBIT_SCALE
	local offsetY = -math.cos(angleRad) * BADGE_ORBIT_SCALE
	local tier = tierData(segment)

	local badgeShadow = new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.53, 0.56),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.55,
		ZIndex = 260,
	})
	corner(badgeShadow, UDim.new(0.3, 0))

	local badge = new("Frame", {
		Name = "Segment" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5 + offsetX, 0, 0.5 + offsetY, 0),
		Size = UDim2.fromScale(BADGE_SIZE_SCALE, BADGE_SIZE_SCALE),
		BackgroundColor3 = segment.Color,
		ZIndex = 262,
	}, wheelRing)
	badgeShadow.Parent = badge
	corner(badge, UDim.new(0.3, 0))
	local badgeStroke = stroke(badge, tier.Color, 2, 0.18)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, segment.Color:Lerp(THEME.White, 0.24)),
			ColorSequenceKeypoint.new(0.52, segment.Color),
			ColorSequenceKeypoint.new(1, segment.Color:Lerp(THEME.Void, 0.42)),
		}),
		Rotation = 130,
	}, badge)
	local badgeScale = new("UIScale", { Scale = 1 }, badge)

	new("TextLabel", {
		Name = "Icon",
		Position = UDim2.fromScale(0.08, 0.04),
		Size = UDim2.fromScale(0.84, 0.62),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = segment.Icon,
		TextScaled = true,
		ZIndex = 263,
	}, badge)

	local badgeLabel = new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.05, 0.69),
		Size = UDim2.fromScale(0.9, 0.22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.upper(segment.Label),
		TextColor3 = THEME.White,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 263,
	}, badge)
	textConstraint(badgeLabel, 12, 5)

	badges[index] = badge
	badgeStrokes[index] = badgeStroke
	badgeScales[index] = badgeScale
end

-- Twenty-four warm/cool bulbs stay fixed on the cabinet while the reward
-- face rotates beneath them, giving the wheel a physical arcade silhouette.
for index = 1, 24 do
	local angle = math.rad((index - 1) * 15)
	local bulb = new("Frame", {
		Name = "Bulb" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.472, 0.5 - math.cos(angle) * 0.472),
		Size = UDim2.fromScale(0.033, 0.033),
		BackgroundColor3 = index % 2 == 0 and THEME.GoldLight or THEME.Cyan,
		BackgroundTransparency = 0.05,
		ZIndex = 266,
	}, wheelBase)
	corner(bulb, UDim.new(0.5, 0))
	stroke(bulb, THEME.White, 1, 0.35)
	tween(bulb, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (index % 6) * 0.08), {
		BackgroundTransparency = 0.62,
		Size = UDim2.fromScale(0.025, 0.025),
	}):Play()
end

local hubGlow = new("Frame", {
	Name = "HubGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.32, 0.32),
	BackgroundColor3 = THEME.Gold,
	BackgroundTransparency = 0.66,
	ZIndex = 267,
}, wheelBase)
corner(hubGlow, UDim.new(0.5, 0))
local hubGlowScale = new("UIScale", { Scale = 1 }, hubGlow)

local hub = new("Frame", {
	Name = "Hub",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.24, 0.24),
	BackgroundColor3 = THEME.SurfaceDeep,
	ZIndex = 268,
}, wheelBase)
corner(hub, UDim.new(0.5, 0))
local hubStroke = stroke(hub, THEME.GoldLight, 3, 0.02)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(96, 55, 31), Color3.fromRGB(30, 25, 58)),
	Rotation = 45,
}, hub)

local hubRing = new("Frame", {
	Name = "HubRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.76, 0.76),
	BackgroundTransparency = 1,
	ZIndex = 269,
}, hub)
corner(hubRing, UDim.new(0.5, 0))
stroke(hubRing, THEME.Cyan, 1.5, 0.28)
for index = 1, 4 do
	local angle = math.rad((index - 1) * 90)
	local gem = new("Frame", {
		Name = "Gem" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.5, 0.5 - math.cos(angle) * 0.5),
		Size = UDim2.fromScale(0.14, 0.14),
		BackgroundColor3 = index % 2 == 0 and THEME.GoldLight or THEME.Cyan,
		Rotation = 45,
		ZIndex = 270,
	}, hubRing)
	corner(gem, UDim.new(0.18, 0))
end

new("TextLabel", {
	Name = "Crown",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✦",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 271,
}, hub)

local pointerGlow = new("Frame", {
	Name = "PointerGlow",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, -0.08),
	Size = UDim2.fromScale(0.22, 0.23),
	BackgroundColor3 = THEME.Gold,
	BackgroundTransparency = 0.72,
	ZIndex = 272,
}, wheelHolder)
corner(pointerGlow, UDim.new(0.5, 0))

local pointer = new("Frame", {
	Name = "Pointer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, -0.055),
	Size = UDim2.fromScale(0.15, 0.17),
	BackgroundColor3 = THEME.SurfaceDeep,
	ZIndex = 273,
}, wheelHolder)
corner(pointer, UDim.new(0.3, 0))
stroke(pointer, THEME.GoldLight, 2.5, 0.02)
local pointerScale = new("UIScale", { Scale = 1 }, pointer)
new("TextLabel", {
	Name = "Arrow",
	Position = UDim2.fromScale(0.08, 0.2),
	Size = UDim2.fromScale(0.84, 0.95),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "▼",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 274,
}, pointer)

local candidateLabel = new("TextLabel", {
	Name = "Candidate",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1.01),
	Size = UDim2.fromScale(0.72, 0.085),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.08,
	Font = Enum.Font.GothamBlack,
	Text = "THE WHEEL AWAITS",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 275,
}, wheelStage)
corner(candidateLabel, UDim.new(0.5, 0))
stroke(candidateLabel, THEME.Gold, 1.5, 0.42)
textConstraint(candidateLabel, 16, 7)

-- =========================================================================
-- PRIZE LEDGER + RESULT CHAMBER
-- =========================================================================

local prizePanel = new("Frame", {
	Name = "PrizePanel",
	Position = UDim2.fromScale(0.655, 0.235),
	Size = UDim2.fromScale(0.325, 0.55),
	BackgroundColor3 = THEME.Surface,
	ZIndex = 253,
}, panel)
corner(prizePanel, UDim.new(0.06, 0))
local prizePanelStroke = stroke(prizePanel, THEME.Gold, 2, 0.18)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(50, 35, 71), Color3.fromRGB(23, 18, 42)),
	Rotation = 115,
}, prizePanel)
new("UIPadding", {
	PaddingLeft = UDim.new(0.05, 0),
	PaddingRight = UDim.new(0.05, 0),
	PaddingTop = UDim.new(0.035, 0),
	PaddingBottom = UDim.new(0.035, 0),
}, prizePanel)

local prizeLedger = new("Frame", {
	Name = "Ledger",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 254,
}, prizePanel)

local ledgerTitle = new("TextLabel", {
	Name = "Title",
	Size = UDim2.fromScale(1, 0.105),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "POSSIBLE FORTUNES",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 255,
}, prizeLedger)
textConstraint(ledgerTitle, 18, 8)

local ledgerRows = {}
local ledgerStrokes = {}
for index, segment in ipairs(WheelConfig.Segments) do
	local tier = tierData(segment)
	local row = new("Frame", {
		Name = "Prize" .. index,
		Position = UDim2.fromScale(0, 0.12 + (index - 1) * 0.105),
		Size = UDim2.fromScale(1, 0.087),
		BackgroundColor3 = THEME.SurfaceDeep,
		BackgroundTransparency = 0.13,
		ZIndex = 255,
	}, prizeLedger)
	corner(row, UDim.new(0.22, 0))
	local rowStroke = stroke(row, tier.Color, 1.3, 0.62)
	new("UIPadding", {
		PaddingLeft = UDim.new(0.035, 0),
		PaddingRight = UDim.new(0.035, 0),
		PaddingTop = UDim.new(0.08, 0),
		PaddingBottom = UDim.new(0.08, 0),
	}, row)

	new("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromScale(0.16, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = segment.Icon,
		TextScaled = true,
		ZIndex = 256,
	}, row)
	local rowName = new("TextLabel", {
		Name = "Name",
		Position = UDim2.fromScale(0.18, 0),
		Size = UDim2.fromScale(0.52, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = segment.Label,
		TextColor3 = tier.Color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 256,
	}, row)
	textConstraint(rowName, 13, 6)
	local odds = new("TextLabel", {
		Name = "Odds",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.27, 1),
		BackgroundColor3 = tier.Color,
		BackgroundTransparency = 0.14,
		Font = Enum.Font.GothamBlack,
		Text = ("%g%%"):format(segment.Weight),
		TextColor3 = THEME.Void,
		TextScaled = true,
		ZIndex = 256,
	}, row)
	corner(odds, UDim.new(0.5, 0))
	textConstraint(odds, 12, 6)

	ledgerRows[index] = row
	ledgerStrokes[index] = rowStroke
end

local resultCard = new("Frame", {
	Name = "ResultCard",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 260,
}, prizePanel)
local resultScale = new("UIScale", { Scale = 0.78 }, resultCard)

local resultEyebrow = new("TextLabel", {
	Name = "Eyebrow",
	Size = UDim2.fromScale(1, 0.09),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "THE WHEEL HAS SPOKEN",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 261,
}, resultCard)
textConstraint(resultEyebrow, 13, 7)

local resultIcon = new("TextLabel", {
	Name = "Icon",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.1),
	Size = UDim2.fromScale(0.5, 0.27),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "👑",
	TextScaled = true,
	ZIndex = 261,
}, resultCard)

local resultName = new("TextLabel", {
	Name = "Name",
	Position = UDim2.fromScale(0, 0.38),
	Size = UDim2.fromScale(1, 0.12),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "JACKPOT",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 261,
}, resultCard)
textConstraint(resultName, 24, 9)

local resultTier = new("TextLabel", {
	Name = "Tier",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.515),
	Size = UDim2.fromScale(0.48, 0.075),
	BackgroundColor3 = THEME.Gold,
	Font = Enum.Font.GothamBlack,
	Text = "JACKPOT FORTUNE",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 261,
}, resultCard)
corner(resultTier, UDim.new(0.5, 0))
local resultTierStroke = stroke(resultTier, THEME.White, 1.5, 0.24)
textConstraint(resultTier, 12, 6)

local rewardBox = new("Frame", {
	Name = "RewardBox",
	Position = UDim2.fromScale(0, 0.62),
	Size = UDim2.fromScale(1, 0.19),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.05,
	ZIndex = 261,
}, resultCard)
corner(rewardBox, UDim.new(0.12, 0))
local rewardBoxStroke = stroke(rewardBox, THEME.Gold, 1.5, 0.42)
new("UIPadding", {
	PaddingLeft = UDim.new(0.06, 0),
	PaddingRight = UDim.new(0.06, 0),
	PaddingTop = UDim.new(0.1, 0),
	PaddingBottom = UDim.new(0.1, 0),
}, rewardBox)
local rewardText = new("TextLabel", {
	Name = "Reward",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "+30K ESSENCE",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 262,
}, rewardBox)
textConstraint(rewardText, 17, 7)

local resultDescription = new("TextLabel", {
	Name = "Description",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.98),
	Size = UDim2.fromScale(0.94, 0.13),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "The crown lands: the wheel yields its richest fortune.",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 261,
}, resultCard)
textConstraint(resultDescription, 13, 7)

-- =========================================================================
-- STATUS + SPIN CONTROL
-- =========================================================================

local statusLabel = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.805),
	Size = UDim2.fromScale(0.92, 0.045),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Loading your fortunes...",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 253,
}, panel)
textConstraint(statusLabel, 15, 7)

local spinButton = new("TextButton", {
	Name = "SpinButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.965),
	Size = UDim2.fromScale(0.56, 0.105),
	BackgroundColor3 = THEME.Green,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "SPIN THE WHEEL — FREE",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 253,
}, panel)
corner(spinButton, UDim.new(0.35, 0))
stroke(spinButton, THEME.GoldLight, 2.5, 0.05)
new("UIGradient", {
	Color = ColorSequence.new(THEME.Green, THEME.Gold),
	Rotation = 10,
}, spinButton)
new("UIPadding", {
	PaddingLeft = UDim.new(0.08, 0),
	PaddingRight = UDim.new(0.08, 0),
}, spinButton)
textConstraint(spinButton, 23, 9)
Juice.ButtonFeel(spinButton, { HoverScale = 1.035 })

local leftSpark = new("TextLabel", {
	Name = "LeftSpark",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.055, 0.5),
	Size = UDim2.fromScale(0.07, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✦",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 254,
}, spinButton)
local rightSpark = leftSpark:Clone()
rightSpark.Name = "RightSpark"
rightSpark.Position = UDim2.fromScale(0.945, 0.5)
rightSpark.Parent = spinButton

-- =========================================================================
-- STATE + DISPLAY
-- =========================================================================

local wheelState = {
	Tickets = 0,
	CollectionsSinceLastTicket = 0,
	FreeSpinReady = false,
	FreeSpinReadyAt = 0,
}

local dataLoaded = false
local spinning = false
local open = false
local transientStatus = nil
local serverTimeOffset = 0
local lastPointerIndex = nil
local spinStartedAt = 0
local lastTickAt = 0

local function serverNow(): number
	return os.time() + serverTimeOffset
end

local function clearHighlights()
	for index in ipairs(badges) do
		local tier = tierData(WheelConfig.Segments[index])
		badgeStrokes[index].Thickness = 2
		badgeStrokes[index].Transparency = 0.18
		badgeScales[index].Scale = 1
		ledgerRows[index].BackgroundTransparency = 0.13
		ledgerStrokes[index].Color = tier.Color
		ledgerStrokes[index].Thickness = 1.3
		ledgerStrokes[index].Transparency = 0.62
	end
end

local function highlightSegment(index: number?, punch: boolean?)
	if not index or not badges[index] then
		return
	end
	clearHighlights()
	local segment = WheelConfig.Segments[index]
	local tier = tierData(segment)
	badgeStrokes[index].Color = tier.Color
	badgeStrokes[index].Thickness = 4
	badgeStrokes[index].Transparency = 0
	badgeScales[index].Scale = 1.12
	ledgerRows[index].BackgroundTransparency = 0
	ledgerStrokes[index].Color = tier.Color
	ledgerStrokes[index].Thickness = 2.2
	ledgerStrokes[index].Transparency = 0.05
	candidateLabel.Text = string.upper(segment.Label)
	candidateLabel.TextColor3 = tier.Color
	candidateLabel.BackgroundColor3 = tier.Glow:Lerp(THEME.SurfaceDeep, 0.76)
	if punch then
		Juice.Punch(pointerScale, 0.17, 0.11)
	end
end

local function applyPayload(payload)
	if type(payload) ~= "table" then
		return
	end
	if tonumber(payload.ServerNow) then
		serverTimeOffset = math.floor(tonumber(payload.ServerNow)) - os.time()
	end

	wheelState.Tickets = math.max(0, math.floor(tonumber(payload.Tickets) or 0))
	wheelState.CollectionsSinceLastTicket = math.max(0, math.floor(tonumber(payload.CollectionsSinceLastTicket) or 0))
	wheelState.FreeSpinReady = payload.FreeSpinReady == true
	if tonumber(payload.FreeSpinReadyAt) then
		wheelState.FreeSpinReadyAt = tonumber(payload.FreeSpinReadyAt)
	else
		wheelState.FreeSpinReadyAt = serverNow() + math.max(0, tonumber(payload.FreeSpinSecondsRemaining) or 0)
	end
	dataLoaded = true
end

local function refreshStatus()
	local ready = dataLoaded and serverNow() >= wheelState.FreeSpinReadyAt
	wheelState.FreeSpinReady = ready
	local hasSpin = ready or wheelState.Tickets > 0

	availabilityBadge.Visible = hasSpin and not spinning
	availabilityBadge.Text = ready and "FREE" or ("×%d"):format(wheelState.Tickets)
	availabilityBadge.BackgroundColor3 = ready and THEME.Green or THEME.Gold
	wheelButtonStroke.Color = hasSpin and THEME.Green or THEME.Gold
	shortcutCaption.TextColor3 = hasSpin and THEME.Green or THEME.GoldLight

	ticketText.Text = ("%d TICKET%s BANKED"):format(wheelState.Tickets, wheelState.Tickets == 1 and "" or "S")
	local progress = math.clamp(wheelState.CollectionsSinceLastTicket / WheelConfig.CollectionsPerTicket, 0, 1)
	tween(chargeFill, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(progress, 1),
	}):Play()
	chargeAmount.Text = ("%d / %d"):format(wheelState.CollectionsSinceLastTicket, WheelConfig.CollectionsPerTicket)

	if not dataLoaded then
		freeStatus.Text = "READING THE STARS..."
		freeStatus.TextColor3 = THEME.Muted
		spinButton.Active = true
		spinButton.BackgroundColor3 = THEME.Locked
		spinButton.Text = "LOADING FORTUNE..."
		statusLabel.Text = "Loading your spins..."
		return
	end

	if ready then
		freeStatus.Text = "FREE SPIN READY"
		freeStatus.TextColor3 = THEME.Green
	else
		local remaining = math.max(0, wheelState.FreeSpinReadyAt - serverNow())
		freeStatus.Text = "FREE IN " .. formatDuration(remaining)
		freeStatus.TextColor3 = THEME.GoldLight
	end

	if spinning then
		spinButton.Active = false
		spinButton.BackgroundColor3 = THEME.Locked
		spinButton.Text = "DESTINY IN MOTION..."
		statusLabel.Text = transientStatus or "The pointer is chasing your fortune."
		return
	end

	-- Resting stays clickable so it can explain when the next chance arrives.
	spinButton.Active = true
	spinButton.BackgroundColor3 = hasSpin and THEME.Green or THEME.Locked
	if ready then
		spinButton.Text = "SPIN THE WHEEL — FREE"
	elseif wheelState.Tickets > 0 then
		spinButton.Text = ("USE TICKET — %d LEFT"):format(wheelState.Tickets)
	else
		spinButton.Text = "THE WHEEL IS RESTING"
	end

	if transientStatus then
		statusLabel.Text = transientStatus
	elseif ready then
		local remainingCollections = math.max(0, WheelConfig.CollectionsPerTicket - wheelState.CollectionsSinceLastTicket)
		statusLabel.Text = ("Your free fortune is ready • %d collections to the next ticket"):format(remainingCollections)
	else
		statusLabel.Text = ("Next free spin in %s • Every collection charges another ticket"):format(
			formatDuration(wheelState.FreeSpinReadyAt - serverNow())
		)
	end
end

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local function closePanel()
	if not open or spinning then
		return
	end
	open = false
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local outTween = tween(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0.84,
	})
	outTween:Play()
	outTween.Completed:Connect(function()
		if not open then
			panel.Visible = false
			panelShadow.Visible = false
			backdrop.Visible = false
		end
	end)
end

local function openPanel()
	if open then
		return
	end
	open = true
	transientStatus = nil
	resultCard.Visible = false
	prizeLedger.Visible = true
	panelStroke.Color = THEME.Gold
	prizePanelStroke.Color = THEME.Gold
	wheelBaseStroke.Color = THEME.Gold
	hubStroke.Color = THEME.GoldLight
	clearHighlights()
	candidateLabel.Text = "THE WHEEL AWAITS"
	candidateLabel.TextColor3 = THEME.GoldLight
	candidateLabel.BackgroundColor3 = THEME.SurfaceDeep
	refreshStatus()

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	panelShadow.Visible = true
	panel.Visible = true
	panelScale.Scale = 0.84
	tween(backdrop, TweenInfo.new(0.24), { BackgroundTransparency = 0.34 }):Play()
	tween(panelScale, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Juice.Punch(Juice.GetScale(wheelButton), 0.08, 0.2)
end

wheelButton.Activated:Connect(openPanel)
closeButton.Activated:Connect(closePanel)
backdrop.Activated:Connect(closePanel)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.Escape then
		closePanel()
	end
end)

_G.EssenceboundWheel = {
	Open = openPanel,
	Close = closePanel,
	IsOpen = function()
		return open
	end,
}

-- =========================================================================
-- AMBIENT MOTION + POINTER TICKS
-- =========================================================================

local uiPop = Juice.FindSound("SFX/UI/UIPop")

local function segmentUnderPointer(): number
	local localAngle = (-wheelRing.Rotation) % 360
	return (math.floor((localAngle + SEGMENT_ANGLE / 2) / SEGMENT_ANGLE) % SEGMENT_COUNT) + 1
end

RunService.RenderStepped:Connect(function(dt)
	if not screenGui.Parent then
		return
	end

	buttonGradient.Rotation = (buttonGradient.Rotation + dt * 9) % 360
	shortcutOrbit.Rotation = (shortcutOrbit.Rotation + dt * 18) % 360
	panelGradient.Rotation = (panelGradient.Rotation + dt * 2.2) % 360

	if panel.Visible then
		energyRingOuter.Rotation = (energyRingOuter.Rotation + dt * (spinning and 150 or 12)) % 360
		energyRingInner.Rotation = (energyRingInner.Rotation - dt * (spinning and 110 or 8)) % 360
		hubRing.Rotation = (hubRing.Rotation + dt * (spinning and 180 or 24)) % 360

		-- Reward cards stay upright while their positions orbit with wheelRing.
		for _, badge in ipairs(badges) do
			badge.Rotation = -wheelRing.Rotation
		end

		if spinning then
			local pointerIndex = segmentUnderPointer()
			if pointerIndex ~= lastPointerIndex then
				lastPointerIndex = pointerIndex
				highlightSegment(pointerIndex, true)
				local now = os.clock()
				if now - lastTickAt > 0.045 then
					lastTickAt = now
					local progress = math.clamp((now - spinStartedAt) / 5.1, 0, 1)
					Juice.PlaySound(uiPop, { Pitch = 0.74 + progress * 0.55, Volume = 0.28 })
				end
			end
		end
	end
end)

tween(shortcutAuraScale, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.12,
}):Play()
tween(shortcutAura, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.92,
}):Play()
tween(availabilityScale, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.16,
}):Play()
tween(farGlowScale, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.08,
}):Play()
tween(farGlow, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.78,
}):Play()
tween(hubGlowScale, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.14,
}):Play()
tween(leftSpark, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Rotation = 90,
	TextTransparency = 0.5,
}):Play()
tween(rightSpark, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.2), {
	Rotation = -90,
	TextTransparency = 0.5,
}):Play()

-- =========================================================================
-- SPIN + LANDING CELEBRATION
-- =========================================================================

local SPIN_DURATION = 5.1
local EXTRA_SPINS = 7

local function populateResult(segment, result)
	local tier = tierData(segment)
	resultIcon.Text = segment.Icon
	resultIcon.TextColor3 = tier.Color
	resultName.Text = string.upper(segment.Label)
	resultName.TextColor3 = tier.Color
	resultTier.Text = string.upper(segment.Tier) .. " FORTUNE"
	resultTier.BackgroundColor3 = tier.Color
	resultTierStroke.Color = tier.Glow
	rewardText.Text = rewardSummary(result)
	rewardText.TextColor3 = tier.Color
	resultDescription.Text = segment.Description
	rewardBoxStroke.Color = tier.Color
	prizePanelStroke.Color = tier.Color
	panelStroke.Color = tier.Glow
	wheelBaseStroke.Color = tier.Color
	hubStroke.Color = tier.Color

	prizeLedger.Visible = false
	resultCard.Visible = true
	resultScale.Scale = 0.72
	tween(resultScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function celebrateResult(segmentIndex, result)
	local badge = badges[segmentIndex]
	local segment = WheelConfig.Segments[segmentIndex]
	if not badge or not segment then
		spinning = false
		refreshStatus()
		return
	end

	local tier = tierData(segment)
	local rank = tier.Rank
	highlightSegment(segmentIndex, false)
	populateResult(segment, result)
	Juice.Punch(badgeScales[segmentIndex], rank >= 4 and 0.5 or 0.34, 0.42)
	Juice.Punch(pointerScale, 0.35, 0.36)
	Juice.Punch(Juice.GetScale(prizePanel), rank >= 4 and 0.14 or 0.08, 0.38)

	local center = Juice.CenterOf(hub, effectLayer)
	local effectZ = 290
	if center then
		Juice.Ring(effectLayer, center, {
			Color = tier.Color,
			StartSize = 45,
			EndSize = rank >= 4 and 330 or 245,
			Duration = 0.7,
			Thickness = rank >= 4 and 5 or 3,
			ZIndex = effectZ,
		})
		task.delay(0.12, function()
			Juice.Ring(effectLayer, center, {
				Color = tier.Glow,
				StartSize = 30,
				EndSize = rank >= 4 and 270 or 190,
				Duration = 0.78,
				Thickness = 2,
				ZIndex = effectZ,
			})
		end)
		if rank >= 5 then
			task.delay(0.24, function()
				Juice.Ring(effectLayer, center, {
					Color = THEME.White,
					StartSize = 24,
					EndSize = 380,
					Duration = 0.9,
					Thickness = 3,
					ZIndex = effectZ,
				})
			end)
		end

		Juice.Burst(effectLayer, center, {
			Count = rank >= 5 and 32 or (rank >= 4 and 25 or (rank >= 3 and 19 or 13)),
			Colors = { tier.Color, tier.Glow, THEME.GoldLight, THEME.White },
			Distance = rank >= 4 and 185 or 125,
			Duration = rank >= 4 and 0.95 or 0.68,
			Size = rank >= 4 and { 6, 15 } or { 4, 10 },
			ZIndex = effectZ + 1,
		})
		Juice.FloatText(effectLayer, center - UDim2.fromOffset(0, 42), segment.RevealQuote, {
			Color = tier.Color,
			Duration = 1.25,
			Rise = 88,
			TextSize = rank >= 4 and 35 or 28,
			ZIndex = effectZ + 2,
		})
		task.delay(0.22, function()
			Juice.FloatText(effectLayer, center + UDim2.fromOffset(0, 38), rewardSummary(result):gsub("\n", "  •  "), {
				Color = THEME.White,
				Duration = 1.35,
				Rise = 62,
				TextSize = 21,
				ZIndex = effectZ + 2,
			})
		end)
	end

	if rank >= 3 then
		Juice.Flash(screenGui, {
			Color = tier.Color,
			Peak = rank >= 5 and 0.52 or 0.73,
			Duration = rank >= 5 and 0.72 or 0.46,
			ZIndex = 310,
		})
	end
	if rank >= 4 then
		Juice.Shake(panel, rank >= 5 and 10 or 6, 0.42)
	end

	Juice.PlaySound(uiPop, { Pitch = 0.82 + rank * 0.11, Volume = 0.85 })
	transientStatus = rank >= 5 and "JACKPOT! The crown has chosen you." or (segment.Label .. " has been delivered to your balance.")
	spinning = false
	refreshStatus()
end

local function spinRingTo(segmentIndex, onDone)
	local targetAngle = (segmentIndex - 1) * SEGMENT_ANGLE
	local targetMod = (360 - targetAngle) % 360
	local currentMod = wheelRing.Rotation % 360
	local forwardDelta = (targetMod - currentMod + 360) % 360
	local finalRotation = wheelRing.Rotation + EXTRA_SPINS * 360 + forwardDelta

	spinStartedAt = os.clock()
	lastPointerIndex = nil
	lastTickAt = 0
	local center = Juice.CenterOf(hub, effectLayer)
	if center then
		Juice.Ring(effectLayer, center, {
			Color = THEME.GoldLight,
			StartSize = 35,
			EndSize = 230,
			Duration = 0.58,
			ZIndex = 288,
		})
	end
	tween(farGlow, TweenInfo.new(0.25), { BackgroundTransparency = 0.66 }):Play()
	tween(pointerGlow, TweenInfo.new(0.25), { BackgroundTransparency = 0.48 }):Play()

	-- Last-second cabinet charge makes the deceleration feel consequential.
	task.delay(SPIN_DURATION - 1.05, function()
		if not spinning then
			return
		end
		Juice.Punch(hubGlowScale, 0.28, 0.45)
		if center then
			Juice.Burst(effectLayer, center, {
				Count = 10,
				Colors = { THEME.GoldLight, THEME.Cyan },
				Distance = 95,
				Duration = 0.55,
				Size = { 3, 8 },
				ZIndex = 289,
			})
		end
	end)

	local spinTween = tween(wheelRing, TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Rotation = finalRotation,
	})
	spinTween:Play()
	spinTween.Completed:Connect(function()
		tween(farGlow, TweenInfo.new(0.35), { BackgroundTransparency = 0.88 }):Play()
		tween(pointerGlow, TweenInfo.new(0.35), { BackgroundTransparency = 0.72 }):Play()
		if onDone then
			onDone()
		end
	end)
end

local function requestSpin()
	local ready = serverNow() >= wheelState.FreeSpinReadyAt
	if spinning then
		return
	end
	if not dataLoaded then
		NotificationService.Info("Your Daily Wheel chances are still loading.", {
			Title = "Reading Your Fortune",
			Icon = "✦",
			Key = "wheel-loading",
		})
		return
	end
	if not (ready or wheelState.Tickets > 0) then
		NotificationService.Warning(("Your next free spin arrives in %s. Collect %d more orbs to earn a ticket."):format(
			formatDuration(wheelState.FreeSpinReadyAt - serverNow()),
			math.max(0, WheelConfig.CollectionsPerTicket - wheelState.CollectionsSinceLastTicket)
		), {
			Title = "No Spin Available Yet",
			Icon = "⌛",
			Key = "wheel-resting",
		})
		return
	end

	spinning = true
	transientStatus = "The cabinet awakens — listen for the pointer."
	resultCard.Visible = false
	prizeLedger.Visible = true
	panelStroke.Color = THEME.Gold
	prizePanelStroke.Color = THEME.Gold
	wheelBaseStroke.Color = THEME.Gold
	hubStroke.Color = THEME.GoldLight
	clearHighlights()
	candidateLabel.Text = "FORTUNES IN MOTION..."
	candidateLabel.TextColor3 = THEME.GoldLight
	candidateLabel.BackgroundColor3 = THEME.SurfaceDeep
	refreshStatus()

	local ok, success, message, result = pcall(function()
		return SpinFunction:InvokeServer()
	end)
	if not ok or not success then
		spinning = false
		transientStatus = ok and (message or "The wheel refused the spin. Try again.") or "The wheel lost its connection. Try again."
		NotificationService.Push(transientStatus, {
			Kind = ok and "Warning" or "Error",
			Title = ok and "Spin Unavailable" or "Wheel Connection Lost",
			Icon = ok and "⌛" or "×",
			Key = "wheel-spin-failed",
		})
		Juice.Shake(spinButton, 4, 0.25)
		refreshStatus()
		return
	end

	if type(result) ~= "table" or not WheelConfig.Segments[result.SegmentIndex] then
		spinning = false
		transientStatus = "The wheel returned an unreadable fortune."
		NotificationService.Error(transientStatus, {
			Title = "Fortune Unreadable",
			Key = "wheel-invalid-result",
		})
		refreshStatus()
		return
	end

	spinRingTo(result.SegmentIndex, function()
		celebrateResult(result.SegmentIndex, result)
	end)
end

spinButton.Activated:Connect(requestSpin)

-- =========================================================================
-- SYNC + LOCAL COUNTDOWN
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	applyPayload(payload)
	if not spinning then
		transientStatus = nil
	end
	refreshStatus()
end)

task.spawn(function()
	local ok, payload = pcall(function()
		return GetStateFunction:InvokeServer()
	end)
	if ok and type(payload) == "table" then
		applyPayload(payload)
	end
	refreshStatus()
end)

task.spawn(function()
	while screenGui.Parent do
		task.wait(1)
		refreshStatus()
	end
end)

refreshStatus()

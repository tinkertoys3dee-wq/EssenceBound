--[[
	ProphecyPanel (LocalScript -> StarterPlayerScripts)
	====================================================
	A code-built magic crystal interface for temporary Prophecy boons.
	The server chooses every result before this script animates it; all of
	the spinning runes, wisps, flashes and rapid omen cycling below are
	presentation only.

	No external image assets are required. The crystal, pedestal, orbiting
	runes, starlight and rarity effects are layered Frames, strokes,
	gradients and text glyphs, so the full feature appears when the repo is
	synced even though EssenceBound's authored Studio UI is not in source.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ProphecyConfig = require(ReplicatedStorage:WaitForChild("ProphecyConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("ProphecyRemotes", 20)
if not remotesFolder then
	warn("ProphecyPanel: ProphecyRemotes never appeared -- crystal UI disabled this session.")
	return
end

local SyncRemote = remotesFolder:WaitForChild("ProphecySync", 10)
local RollFunction = remotesFolder:WaitForChild("RollProphecy", 10)
local GetStateFunction = remotesFolder:WaitForChild("GetProphecyState", 10)
if not SyncRemote or not RollFunction or not GetStateFunction then
	warn("ProphecyPanel: required remotes are missing -- crystal UI disabled this session.")
	return
end

-- =========================================================================
-- THEME + HELPERS
-- =========================================================================

local THEME = {
	Void = Color3.fromRGB(8, 5, 18),
	Background = Color3.fromRGB(20, 12, 38),
	Surface = Color3.fromRGB(34, 22, 58),
	SurfaceRaised = Color3.fromRGB(47, 29, 76),
	SurfaceDeep = Color3.fromRGB(15, 10, 30),
	Violet = Color3.fromRGB(160, 92, 255),
	VioletLight = Color3.fromRGB(217, 172, 255),
	Cyan = Color3.fromRGB(87, 226, 255),
	Gold = Color3.fromRGB(255, 199, 83),
	GoldLight = Color3.fromRGB(255, 235, 171),
	Green = Color3.fromRGB(80, 225, 156),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(183, 169, 207),
	Dim = Color3.fromRGB(123, 106, 153),
	Locked = Color3.fromRGB(58, 48, 77),
}

local LAYOUT = {
	-- Large, immediately discoverable shortcut in the open upper-right
	-- corner. The min/max bounds keep it prominent on phones without
	-- becoming enormous on high-resolution desktop displays.
	ButtonAnchor = Vector2.new(1, 0),
	ButtonPosition = UDim2.fromScale(0.985, 0.02),
	ButtonSize = UDim2.fromScale(0.068, 0.068),
	ButtonMinSize = Vector2.new(68, 68),
	ButtonMaxSize = Vector2.new(88, 88),
	PanelSize = UDim2.fromScale(0.62, 0.78),
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
		Color = color or THEME.Violet,
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
		MinTextSize = minSize or 8,
	}, label)
end

local function formatTime(seconds: number): string
	return ProgressionConfig.FormatDuration(math.max(0, math.ceil(seconds)))
end

local function rarityData(prophecy)
	return (prophecy and ProphecyConfig.GetRarity(prophecy.Rarity)) or ProphecyConfig.Rarities.Common
end

-- =========================================================================
-- ROOT + ALWAYS-VISIBLE SHORTCUT
-- =========================================================================

local oldGui = playerGui:FindFirstChild("ProphecyPanel")
if oldGui then
	oldGui:Destroy()
end

local screenGui = new("ScreenGui", {
	Name = "ProphecyPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 69,
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
new("UISizeConstraint", {
	MinSize = LAYOUT.ButtonMinSize,
	MaxSize = LAYOUT.ButtonMaxSize,
}, buttonHolder)

local shortcutAura = new("Frame", {
	Name = "Aura",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.28, 1.28),
	BackgroundColor3 = THEME.Violet,
	BackgroundTransparency = 0.82,
	ZIndex = 49,
}, buttonHolder)
corner(shortcutAura, UDim.new(0.5, 0))
local shortcutAuraScale = new("UIScale", { Scale = 1 }, shortcutAura)

local crystalButton = new("TextButton", {
	Name = "CrystalButton",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Surface,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 51,
}, buttonHolder)
corner(crystalButton, UDim.new(0.28, 0))
local crystalButtonStroke = stroke(crystalButton, THEME.VioletLight, 3, 0.05)
local buttonGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(81, 47, 119)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(39, 24, 66)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 15, 42)),
	}),
	Rotation = 135,
}, crystalButton)

new("TextLabel", {
	Name = "Icon",
	Position = UDim2.fromScale(0, 0.02),
	Size = UDim2.fromScale(1, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🔮",
	TextScaled = true,
	ZIndex = 52,
}, crystalButton)

local shortcutCaption = new("TextLabel", {
	Name = "Caption",
	Position = UDim2.fromScale(0.06, 0.7),
	Size = UDim2.fromScale(0.88, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "FATE",
	TextColor3 = THEME.VioletLight,
	TextScaled = true,
	ZIndex = 52,
}, crystalButton)
textConstraint(shortcutCaption, 14, 7)

local readyDot = new("Frame", {
	Name = "ReadyDot",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1.03, -0.03),
	Size = UDim2.fromScale(0.25, 0.25),
	BackgroundColor3 = THEME.Green,
	Visible = false,
	ZIndex = 54,
}, crystalButton)
corner(readyDot, UDim.new(0.5, 0))
stroke(readyDot, THEME.White, 1.5, 0.05)
local readyScale = new("UIScale", { Scale = 1 }, readyDot)

Juice.ButtonFeel(crystalButton, { HoverScale = 1.08 })

-- Compact active-omen timer follows the larger shortcut to the top-right,
-- keeping the current boon and its remaining time attached to its source.
local activeHud = new("TextButton", {
	Name = "ActiveProphecy",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(0.985, -98, 0.02, 40),
	Size = UDim2.fromScale(0.175, 0.044),
	BackgroundColor3 = THEME.SurfaceDeep,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 47,
}, screenGui)
corner(activeHud, UDim.new(0.5, 0))
local activeHudStroke = stroke(activeHud, THEME.Violet, 2, 0.15)
new("UIPadding", {
	PaddingLeft = UDim.new(0.045, 0),
	PaddingRight = UDim.new(0.045, 0),
	PaddingTop = UDim.new(0.12, 0),
	PaddingBottom = UDim.new(0.12, 0),
}, activeHud)

local activeHudIcon = new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(0.18, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🔮",
	TextScaled = true,
	ZIndex = 48,
}, activeHud)
local activeHudName = new("TextLabel", {
	Name = "Name",
	Position = UDim2.fromScale(0.2, 0),
	Size = UDim2.fromScale(0.53, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 48,
}, activeHud)
textConstraint(activeHudName, 13, 7)
local activeHudTimer = new("TextLabel", {
	Name = "Timer",
	Position = UDim2.fromScale(0.74, 0),
	Size = UDim2.fromScale(0.26, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = THEME.VioletLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 48,
}, activeHud)
textConstraint(activeHudTimer, 13, 7)
Juice.ButtonFeel(activeHud, { HoverScale = 1.025 })

-- =========================================================================
-- MODAL SHELL (PADDED AT EVERY NESTING LEVEL)
-- =========================================================================

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(3, 1, 8),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 300,
}, screenGui)
backdrop:SetAttribute("PresentationModal", true)

local panelShadow = new("Frame", {
	Name = "PanelShadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.512),
	Size = LAYOUT.PanelSize + UDim2.fromOffset(18, 18),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.45,
	Visible = false,
	ZIndex = 300,
}, screenGui)
corner(panelShadow, UDim.new(0.045, 0))

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = LAYOUT.PanelSize,
	BackgroundColor3 = THEME.Background,
	Visible = false,
	ClipsDescendants = false,
	ZIndex = 301,
}, screenGui)
corner(panel, UDim.new(0.045, 0))
local panelStroke = stroke(panel, THEME.Violet, 3, 0.05)
new("UISizeConstraint", {
	-- Low enough to remain fully on-screen in phone landscape, while the
	-- text constraints below keep the compact version legible.
	MinSize = Vector2.new(320, 340),
	MaxSize = Vector2.new(860, 660),
}, panel)
-- This is real frame padding, not visual empty space: every content child
-- is laid out inside this inset, keeping titles, cards and the roll button
-- away from both the rounded edge and animated border on narrow screens.
new("UIPadding", {
	PaddingLeft = UDim.new(0.045, 0),
	PaddingRight = UDim.new(0.045, 0),
	PaddingTop = UDim.new(0.038, 0),
	PaddingBottom = UDim.new(0.038, 0),
}, panel)
local panelScale = new("UIScale", { Scale = 0.84 }, panel)

local panelGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(43, 20, 72)),
		ColorSequenceKeypoint.new(0.42, THEME.Background),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 11, 34)),
	}),
	Rotation = 125,
}, panel)

local topGlow = new("Frame", {
	Name = "TopGlow",
	Position = UDim2.fromScale(0.08, -0.013),
	Size = UDim2.fromScale(0.84, 0.02),
	BackgroundColor3 = THEME.VioletLight,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 302,
}, panel)
corner(topGlow, UDim.new(0.5, 0))
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, topGlow)

local title = new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.035, 0.005),
	Size = UDim2.fromScale(0.78, 0.085),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🔮  THE PROPHECY CRYSTAL",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 303,
}, panel)
textConstraint(title, 30, 12)

local subtitle = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.04, 0.092),
	Size = UDim2.fromScale(0.78, 0.045),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Peer beyond the veil. Draw a temporary boon from one possible future.",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 303,
}, panel)
textConstraint(subtitle, 15, 8)

local closeButton = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.978, 0.012),
	Size = UDim2.fromScale(0.065, 0.073),
	BackgroundColor3 = THEME.SurfaceRaised,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "×",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 306,
}, panel)
corner(closeButton, UDim.new(0.32, 0))
stroke(closeButton, THEME.VioletLight, 1.5, 0.25)
Juice.ButtonFeel(closeButton, { HoverScale = 1.08 })

-- =========================================================================
-- FATE / PITY METER
-- =========================================================================

local fateCard = new("Frame", {
	Name = "FateMeter",
	Position = UDim2.fromScale(0.035, 0.15),
	Size = UDim2.fromScale(0.93, 0.075),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.08,
	ZIndex = 303,
}, panel)
corner(fateCard, UDim.new(0.3, 0))
stroke(fateCard, THEME.Violet, 1.5, 0.42)
new("UIPadding", {
	PaddingLeft = UDim.new(0.025, 0),
	PaddingRight = UDim.new(0.025, 0),
	PaddingTop = UDim.new(0.14, 0),
	PaddingBottom = UDim.new(0.14, 0),
}, fateCard)

local fateIcon = new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(0.065, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "✦",
	TextColor3 = THEME.Gold,
	TextScaled = true,
	ZIndex = 304,
}, fateCard)
local fateText = new("TextLabel", {
	Name = "Label",
	Position = UDim2.fromScale(0.075, 0),
	Size = UDim2.fromScale(0.48, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "FATE IS AWAKENING",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 304,
}, fateCard)
textConstraint(fateText, 14, 7)

local fateTrack = new("Frame", {
	Name = "Track",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.985, 0.5),
	Size = UDim2.fromScale(0.4, 0.42),
	BackgroundColor3 = THEME.Locked,
	ZIndex = 304,
}, fateCard)
corner(fateTrack, UDim.new(0.5, 0))
local fateFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Gold,
	ZIndex = 305,
}, fateTrack)
corner(fateFill, UDim.new(0.5, 0))
new("UIGradient", {
	Color = ColorSequence.new(THEME.Violet, THEME.Gold),
}, fateFill)

-- =========================================================================
-- CRYSTAL BALL STAGE
-- =========================================================================

local orbStage = new("Frame", {
	Name = "CrystalStage",
	Position = UDim2.fromScale(0.025, 0.245),
	Size = UDim2.fromScale(0.47, 0.535),
	BackgroundTransparency = 1,
	ZIndex = 303,
}, panel)

local stageStars = {
	{ 0.07, 0.18, "·", 0.52 }, { 0.17, 0.05, "✦", 0.62 }, { 0.84, 0.14, "·", 0.44 },
	{ 0.94, 0.34, "✧", 0.62 }, { 0.08, 0.56, "✧", 0.7 }, { 0.83, 0.7, "·", 0.48 },
	{ 0.26, 0.84, "·", 0.64 }, { 0.72, 0.88, "✦", 0.7 },
}
for index, starData in ipairs(stageStars) do
	local star = new("TextLabel", {
		Name = "StageStar" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(starData[1], starData[2]),
		Size = UDim2.fromScale(0.06, 0.08),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = starData[3],
		TextColor3 = index % 2 == 0 and THEME.Cyan or THEME.VioletLight,
		TextTransparency = starData[4],
		TextScaled = true,
		ZIndex = 304,
	}, orbStage)
	tween(star, TweenInfo.new(0.9 + index * 0.13, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = math.max(0.08, starData[4] - 0.36),
		Rotation = index % 2 == 0 and 35 or -35,
	}):Play()
end

local orbHolder = new("Frame", {
	Name = "OrbHolder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.43),
	Size = UDim2.fromScale(0.66, 0.78),
	BackgroundTransparency = 1,
	ZIndex = 305,
}, orbStage)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, orbHolder)

local farGlow = new("Frame", {
	Name = "FarGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.4, 1.4),
	BackgroundColor3 = THEME.Violet,
	BackgroundTransparency = 0.86,
	ZIndex = 305,
}, orbHolder)
corner(farGlow, UDim.new(0.5, 0))
local farGlowScale = new("UIScale", { Scale = 1 }, farGlow)
tween(farGlowScale, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.08,
}):Play()
tween(farGlow, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.76,
}):Play()

local runeRingOuter = new("Frame", {
	Name = "OuterRuneRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.25, 1.25),
	BackgroundTransparency = 1,
	ZIndex = 306,
}, orbHolder)
corner(runeRingOuter, UDim.new(0.5, 0))
stroke(runeRingOuter, THEME.VioletLight, 1.4, 0.45)

local runeGlyphs = { "✦", "◇", "☾", "◈", "✧", "ᚱ", "✦", "◇", "☽", "◈", "✧", "ᚠ" }
for index, glyph in ipairs(runeGlyphs) do
	local angle = math.rad((index - 1) * (360 / #runeGlyphs))
	new("TextLabel", {
		Name = "Rune" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.5, 0.5 - math.cos(angle) * 0.5),
		Size = UDim2.fromScale(0.12, 0.12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = glyph,
		TextColor3 = index % 3 == 0 and THEME.Gold or THEME.VioletLight,
		TextTransparency = 0.12,
		TextScaled = true,
		ZIndex = 307,
	}, runeRingOuter)
end

local runeRingInner = new("Frame", {
	Name = "InnerRuneRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.08, 1.08),
	BackgroundTransparency = 1,
	ZIndex = 307,
}, orbHolder)
corner(runeRingInner, UDim.new(0.5, 0))
local innerRuneStroke = stroke(runeRingInner, THEME.Cyan, 1.3, 0.38)

for index = 1, 8 do
	local angle = math.rad((index - 1) * 45 + 22.5)
	local mark = new("Frame", {
		Name = "Mark" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.sin(angle) * 0.49, 0.5 - math.cos(angle) * 0.49),
		Size = UDim2.fromScale(0.035, 0.1),
		BackgroundColor3 = THEME.Cyan,
		BackgroundTransparency = 0.2,
		Rotation = (index - 1) * 45,
		ZIndex = 308,
	}, runeRingInner)
	corner(mark, UDim.new(0.5, 0))
end

local orb = new("Frame", {
	Name = "CrystalBall",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.93, 0.93),
	BackgroundColor3 = THEME.Violet,
	ClipsDescendants = true,
	ZIndex = 309,
}, orbHolder)
corner(orb, UDim.new(0.5, 0))
local orbStroke = stroke(orb, THEME.VioletLight, 3, 0.02)
local orbScale = new("UIScale", { Scale = 1 }, orb)
local orbGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(56, 27, 110)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(104, 59, 196)),
		ColorSequenceKeypoint.new(0.68, Color3.fromRGB(52, 128, 182)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(29, 24, 78)),
	}),
	Rotation = 35,
}, orb)

local orbHaze = new("Frame", {
	Name = "Haze",
	Position = UDim2.fromScale(-0.1, 0.12),
	Size = UDim2.fromScale(1.2, 0.48),
	BackgroundColor3 = THEME.Cyan,
	BackgroundTransparency = 0.8,
	Rotation = -12,
	ZIndex = 310,
}, orb)
corner(orbHaze, UDim.new(0.5, 0))
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.48, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Rotation = 90,
}, orbHaze)

local swirlOne = new("Frame", {
	Name = "SwirlOne",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.82, 0.34),
	BackgroundTransparency = 1,
	Rotation = -18,
	ZIndex = 311,
}, orb)
corner(swirlOne, UDim.new(0.5, 0))
stroke(swirlOne, THEME.Cyan, 3, 0.48)
local swirlTwo = new("Frame", {
	Name = "SwirlTwo",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.58, 0.78),
	BackgroundTransparency = 1,
	Rotation = 24,
	ZIndex = 311,
}, orb)
corner(swirlTwo, UDim.new(0.5, 0))
stroke(swirlTwo, THEME.VioletLight, 2, 0.55)

local crystalStars = {
	{ .21, .27, .055 }, { .67, .2, .045 }, { .79, .42, .035 }, { .29, .63, .04 },
	{ .62, .72, .055 }, { .48, .34, .03 }, { .18, .48, .025 }, { .77, .68, .025 },
}
for index, starData in ipairs(crystalStars) do
	local star = new("TextLabel", {
		Name = "CrystalStar" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(starData[1], starData[2]),
		Size = UDim2.fromScale(starData[3] * 2, starData[3] * 2),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = index % 3 == 0 and "·" or "✦",
		TextColor3 = index % 2 == 0 and THEME.GoldLight or THEME.White,
		TextTransparency = 0.25,
		TextScaled = true,
		ZIndex = 312,
	}, orb)
	tween(star, TweenInfo.new(0.65 + index * 0.17, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.82,
	}):Play()
end

local orbIcon = new("TextLabel", {
	Name = "VisionIcon",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.42, 0.42),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "◈",
	TextColor3 = THEME.White,
	TextStrokeColor3 = THEME.Violet,
	TextStrokeTransparency = 0.35,
	TextScaled = true,
	ZIndex = 313,
}, orb)

local orbShine = new("Frame", {
	Name = "Shine",
	Position = UDim2.fromScale(0.19, 0.1),
	Size = UDim2.fromScale(0.2, 0.4),
	BackgroundColor3 = THEME.White,
	BackgroundTransparency = 0.78,
	Rotation = 34,
	ZIndex = 314,
}, orb)
corner(orbShine, UDim.new(0.5, 0))

-- Faceted pedestal: three simple layers keep the ball grounded and make
-- it read as a physical divination object rather than another round icon.
local pedestalNeck = new("Frame", {
	Name = "PedestalNeck",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.71),
	Size = UDim2.fromScale(0.27, 0.11),
	BackgroundColor3 = Color3.fromRGB(113, 73, 147),
	Rotation = 0,
	ZIndex = 306,
}, orbStage)
corner(pedestalNeck, UDim.new(0.18, 0))
stroke(pedestalNeck, THEME.Gold, 1.5, 0.2)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(55, 31, 85), Color3.fromRGB(177, 117, 170)),
	Rotation = 90,
}, pedestalNeck)

local pedestalBase = new("Frame", {
	Name = "PedestalBase",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.79),
	Size = UDim2.fromScale(0.5, 0.12),
	BackgroundColor3 = Color3.fromRGB(77, 47, 104),
	ZIndex = 307,
}, orbStage)
corner(pedestalBase, UDim.new(0.28, 0))
stroke(pedestalBase, THEME.Gold, 2, 0.1)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(41, 25, 65)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(144, 91, 141)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 24, 59)),
	}),
}, pedestalBase)

local pedestalGem = new("TextLabel", {
	Name = "PedestalGem",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.22, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "◇",
	TextColor3 = THEME.Cyan,
	TextScaled = true,
	ZIndex = 308,
}, pedestalBase)

-- =========================================================================
-- READING CARD
-- =========================================================================

local readingCard = new("Frame", {
	Name = "ReadingCard",
	Position = UDim2.fromScale(0.515, 0.245),
	Size = UDim2.fromScale(0.45, 0.535),
	BackgroundColor3 = THEME.Surface,
	ZIndex = 303,
}, panel)
corner(readingCard, UDim.new(0.06, 0))
local readingStroke = stroke(readingCard, THEME.Violet, 2, 0.18)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(48, 29, 78), Color3.fromRGB(25, 17, 45)),
	Rotation = 115,
}, readingCard)
-- Nested padding is intentionally generous: long prophecy names and the
-- three-part Mythic benefit must never touch the border or one another.
new("UIPadding", {
	PaddingLeft = UDim.new(0.055, 0),
	PaddingRight = UDim.new(0.055, 0),
	PaddingTop = UDim.new(0.045, 0),
	PaddingBottom = UDim.new(0.045, 0),
}, readingCard)

local readingName = new("TextLabel", {
	Name = "ReadingName",
	Size = UDim2.fromScale(1, 0.16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "THE VEIL AWAITS",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 304,
}, readingCard)
textConstraint(readingName, 25, 10)

local rarityBadge = new("TextLabel", {
	Name = "Rarity",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.185),
	Size = UDim2.fromScale(0.5, 0.1),
	BackgroundColor3 = THEME.Locked,
	Font = Enum.Font.GothamBlack,
	Text = "UNREAD FUTURE",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 304,
}, readingCard)
corner(rarityBadge, UDim.new(0.5, 0))
local rarityStroke = stroke(rarityBadge, THEME.Dim, 1.5, 0.2)
textConstraint(rarityBadge, 13, 7)

local benefitBox = new("Frame", {
	Name = "BenefitBox",
	Position = UDim2.fromScale(0, 0.32),
	Size = UDim2.fromScale(1, 0.245),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.05,
	ZIndex = 304,
}, readingCard)
corner(benefitBox, UDim.new(0.12, 0))
stroke(benefitBox, THEME.VioletLight, 1.5, 0.5)
new("UIPadding", {
	PaddingLeft = UDim.new(0.06, 0),
	PaddingRight = UDim.new(0.06, 0),
	PaddingTop = UDim.new(0.12, 0),
	PaddingBottom = UDim.new(0.12, 0),
}, benefitBox)
new("TextLabel", {
	Name = "Eyebrow",
	Size = UDim2.fromScale(1, 0.28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "TEMPORARY BOON",
	TextColor3 = THEME.Dim,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 305,
}, benefitBox)
textConstraint(benefitBox.Eyebrow, 11, 6)
local benefitText = new("TextLabel", {
	Name = "Benefit",
	Position = UDim2.fromScale(0, 0.32),
	Size = UDim2.fromScale(1, 0.64),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "Draw one free temporary power.",
	TextColor3 = THEME.VioletLight,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 305,
}, benefitBox)
textConstraint(benefitText, 18, 8)

local loreText = new("TextLabel", {
	Name = "Lore",
	Position = UDim2.fromScale(0.025, 0.605),
	Size = UDim2.fromScale(0.95, 0.19),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "The crystal remembers every humble omen. Fate ensures a Rare prophecy within eight readings.",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 304,
}, readingCard)
textConstraint(loreText, 14, 7)

local durationLabel = new("TextLabel", {
	Name = "Duration",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.965),
	Size = UDim2.fromScale(0.95, 0.115),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Every reading is free",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 304,
}, readingCard)
textConstraint(durationLabel, 14, 7)

-- =========================================================================
-- STATUS + ROLL BUTTON
-- =========================================================================

local statusLabel = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.8),
	Size = UDim2.fromScale(0.91, 0.045),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Reading the crystal...",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 304,
}, panel)
textConstraint(statusLabel, 14, 7)

local rollButton = new("TextButton", {
	Name = "RollButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.965),
	Size = UDim2.fromScale(0.58, 0.105),
	BackgroundColor3 = THEME.Violet,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "READ THE CRYSTAL — FREE",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 304,
}, panel)
corner(rollButton, UDim.new(0.35, 0))
local rollStroke = stroke(rollButton, THEME.GoldLight, 2.5, 0.08)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(110, 61, 214), Color3.fromRGB(76, 178, 212)),
	Rotation = 15,
}, rollButton)
new("UIPadding", {
	PaddingLeft = UDim.new(0.08, 0),
	PaddingRight = UDim.new(0.08, 0),
}, rollButton)
textConstraint(rollButton, 22, 9)
Juice.ButtonFeel(rollButton, { HoverScale = 1.035 })

local buttonSparkLeft = new("TextLabel", {
	Name = "SparkLeft",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.055, 0.5),
	Size = UDim2.fromScale(0.07, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "✦",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 305,
}, rollButton)
local buttonSparkRight = buttonSparkLeft:Clone()
buttonSparkRight.Name = "SparkRight"
buttonSparkRight.Position = UDim2.fromScale(0.945, 0.5)
buttonSparkRight.Parent = rollButton

-- =========================================================================
-- STATE + RENDERING
-- =========================================================================

local state = {
	ServerNow = 0,
	NextRollAt = 0,
	ActiveId = "",
	ExpiresAt = 0,
	TotalRolls = 0,
	RollsSinceRare = 0,
	PityRolls = ProphecyConfig.PityRolls,
}
local serverTimeOffset = 0
local dataLoaded = false
local rolling = false
local open = false
local transientStatus = nil
local lastRenderedActiveId = nil

local function serverNow(): number
	return os.time() + serverTimeOffset
end

local function renderProphecy(prophecy, isCycling: boolean?)
	if not prophecy then
		orbIcon.Text = "◈"
		orbIcon.TextColor3 = THEME.White
		readingName.Text = "THE VEIL AWAITS"
		readingName.TextColor3 = THEME.White
		rarityBadge.Text = "UNREAD FUTURE"
		rarityBadge.TextColor3 = THEME.Muted
		rarityBadge.BackgroundColor3 = THEME.Locked
		rarityStroke.Color = THEME.Dim
		benefitText.Text = "Draw one free temporary power."
		benefitText.TextColor3 = THEME.VioletLight
		loreText.Text = "The crystal remembers every humble omen. Fate ensures a Rare prophecy within eight readings."
		durationLabel.Text = "Every reading is free"
		readingStroke.Color = THEME.Violet
		orbStroke.Color = THEME.VioletLight
		innerRuneStroke.Color = THEME.Cyan
		return
	end

	local rarity = rarityData(prophecy)
	orbIcon.Text = prophecy.Icon
	orbIcon.TextColor3 = rarity.Color
	readingName.Text = string.upper(prophecy.Name)
	readingName.TextColor3 = rarity.Color
	rarityBadge.Text = string.upper(prophecy.Rarity) .. " PROPHECY"
	rarityBadge.TextColor3 = THEME.Void
	rarityBadge.BackgroundColor3 = rarity.Color
	rarityStroke.Color = rarity.Glow
	benefitText.Text = isCycling and prophecy.RevealQuote or prophecy.Benefit
	benefitText.TextColor3 = rarity.Color
	loreText.Text = isCycling and "The future is still changing..." or prophecy.Lore
	durationLabel.Text = isCycling and "THE VEIL IS OPEN" or ("ACTIVE FOR %s"):format(formatTime(prophecy.Duration))
	readingStroke.Color = rarity.Color
	orbStroke.Color = rarity.Color
	innerRuneStroke.Color = rarity.Glow
end

local function applyPayload(payload)
	if type(payload) ~= "table" then
		return
	end

	if tonumber(payload.ServerNow) then
		serverTimeOffset = math.floor(tonumber(payload.ServerNow)) - os.time()
	end
	state.ServerNow = tonumber(payload.ServerNow) or state.ServerNow
	state.NextRollAt = math.max(0, tonumber(payload.NextRollAt) or 0)
	state.ActiveId = type(payload.ActiveId) == "string" and payload.ActiveId or ""
	state.ExpiresAt = math.max(0, tonumber(payload.ExpiresAt) or 0)
	state.TotalRolls = math.max(0, tonumber(payload.TotalRolls) or 0)
	state.RollsSinceRare = math.clamp(
		math.floor(tonumber(payload.RollsSinceRare) or 0),
		0,
		ProphecyConfig.PityRolls - 1
	)
	state.PityRolls = tonumber(payload.PityRolls) or ProphecyConfig.PityRolls
	dataLoaded = true
end

local function refresh()
	local now = serverNow()
	local activeProphecy = ProphecyConfig.GetById(state.ActiveId)
	local activeRemaining = math.max(0, state.ExpiresAt - now)
	if activeRemaining <= 0 then
		activeProphecy = nil
	end

	local ready = dataLoaded and now >= state.NextRollAt
	readyDot.Visible = ready and not rolling
	crystalButtonStroke.Color = ready and THEME.Green or THEME.VioletLight
	shortcutCaption.TextColor3 = ready and THEME.Green or THEME.VioletLight

	activeHud.Visible = activeProphecy ~= nil
	if activeProphecy then
		local rarity = rarityData(activeProphecy)
		activeHudIcon.Text = activeProphecy.Icon
		activeHudName.Text = activeProphecy.Name
		activeHudName.TextColor3 = rarity.Color
		activeHudTimer.Text = formatTime(activeRemaining)
		activeHudTimer.TextColor3 = rarity.Color
		activeHudStroke.Color = rarity.Glow
	end

	local pityProgress = state.RollsSinceRare / math.max(1, ProphecyConfig.PityRolls - 1)
	tween(fateFill, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(math.clamp(pityProgress, 0, 1), 1),
	}):Play()
	local readingsUntilGuarantee = ProphecyConfig.PityRolls - state.RollsSinceRare
	if state.RollsSinceRare >= ProphecyConfig.PityRolls - 1 then
		fateText.Text = "FATE FULL — NEXT READING IS RARE+"
		fateIcon.Text = "★"
	else
		fateText.Text = ("FATE • RARE+ WITHIN %d READINGS"):format(readingsUntilGuarantee)
		fateIcon.Text = "✦"
	end

	if not rolling and lastRenderedActiveId ~= (activeProphecy and activeProphecy.Id or "") then
		renderProphecy(activeProphecy)
		lastRenderedActiveId = activeProphecy and activeProphecy.Id or ""
	end

	if not dataLoaded then
		rollButton.Active = true
		rollButton.BackgroundColor3 = THEME.Locked
		rollButton.Text = "CONSULTING THE STARS..."
		statusLabel.Text = "Your fate is still loading."
		return
	end

	if rolling then
		rollButton.Active = false
		rollButton.BackgroundColor3 = THEME.Locked
		rollButton.Text = "THE VEIL IS OPEN..."
		statusLabel.Text = transientStatus or "Countless futures are passing through the crystal."
		return
	end

	-- A sleeping crystal remains clickable so the cooldown is explained.
	rollButton.Active = true
	rollButton.BackgroundColor3 = ready and THEME.Violet or THEME.Locked
	if ready then
		rollButton.Text = "READ THE CRYSTAL — FREE"
		statusLabel.Text = transientStatus or "The crystal is awake. One prophecy will replace any active omen."
	else
		local remaining = math.max(0, state.NextRollAt - now)
		rollButton.Text = "CRYSTAL REAWAKENS IN " .. formatTime(remaining)
		if activeProphecy then
			statusLabel.Text = transientStatus or (activeProphecy.Name .. " is shaping your path.")
		else
			statusLabel.Text = transientStatus or "The vision has faded. The crystal is gathering starlight."
		end
	end
end

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local function closePanel()
	if not open or rolling then
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
	if not PresentationCoordinator.CanOpenModal() then
		return
	end
	open = true
	transientStatus = nil
	refresh()

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	panelShadow.Visible = true
	panel.Visible = true
	panelScale.Scale = 0.84
	tween(backdrop, TweenInfo.new(0.24), { BackgroundTransparency = 0.36 }):Play()
	tween(panelScale, TweenInfo.new(0.36, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
	Juice.Punch(Juice.GetScale(crystalButton), 0.08, 0.2)
end

crystalButton.Activated:Connect(openPanel)
activeHud.Activated:Connect(openPanel)
closeButton.Activated:Connect(closePanel)
backdrop.Activated:Connect(closePanel)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		closePanel()
	end
end)

_G.EssenceboundProphecy = {
	Open = openPanel,
	Close = closePanel,
	IsOpen = function()
		return open
	end,
}

-- =========================================================================
-- AMBIENT MOTION + REVEAL
-- =========================================================================

RunService.RenderStepped:Connect(function(dt)
	if not screenGui.Parent then
		return
	end

	buttonGradient.Rotation = (buttonGradient.Rotation + dt * 8) % 360
	panelGradient.Rotation = (panelGradient.Rotation + dt * 2.5) % 360
	if panel.Visible then
		local speed = rolling and 260 or 18
		runeRingOuter.Rotation = (runeRingOuter.Rotation + dt * speed) % 360
		runeRingInner.Rotation = (runeRingInner.Rotation - dt * (rolling and 190 or 13)) % 360
		swirlOne.Rotation = (swirlOne.Rotation + dt * (rolling and 105 or 21)) % 360
		swirlTwo.Rotation = (swirlTwo.Rotation - dt * (rolling and 80 or 15)) % 360
		orbGradient.Rotation = (orbGradient.Rotation + dt * (rolling and 80 or 7)) % 360
	end
end)

tween(shortcutAuraScale, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.13,
}):Play()
tween(shortcutAura, TweenInfo.new(1.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.9,
}):Play()
tween(readyScale, TweenInfo.new(0.65, Enum.EasingStyle.Back, Enum.EasingDirection.InOut, -1, true), {
	Scale = 1.28,
}):Play()
tween(buttonSparkLeft, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Rotation = 90,
	TextTransparency = 0.5,
}):Play()
tween(buttonSparkRight, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0.2), {
	Rotation = -90,
	TextTransparency = 0.5,
}):Play()

local uiPop = Juice.FindSound("SFX/UI/UIPop")

local function playRevealEffects(prophecy, pityTriggered: boolean)
	local rarity = rarityData(prophecy)
	local rank = rarity.Rank
	local center = Juice.CenterOf(orb, panel)
	if not center then
		return
	end

	local effectZ = 330
	Juice.Ring(panel, center, {
		Color = rarity.Color,
		StartSize = 52,
		EndSize = rank >= 4 and 310 or 230,
		Duration = 0.65,
		Thickness = rank >= 4 and 5 or 3,
		ZIndex = effectZ,
	})
	task.delay(0.12, function()
		Juice.Ring(panel, center, {
			Color = rarity.Glow,
			StartSize = 35,
			EndSize = rank >= 4 and 250 or 185,
			Duration = 0.72,
			Thickness = 2,
			ZIndex = effectZ,
		})
	end)
	Juice.Burst(panel, center, {
		Count = rank >= 5 and 30 or (rank >= 4 and 24 or (rank >= 3 and 18 or 12)),
		Colors = { rarity.Color, rarity.Glow, THEME.White, THEME.GoldLight },
		Distance = rank >= 4 and 175 or 120,
		Duration = rank >= 4 and 0.9 or 0.65,
		Size = rank >= 4 and { 6, 14 } or { 4, 10 },
		ZIndex = effectZ + 1,
	})

	Juice.FloatText(panel, center - UDim2.fromOffset(0, 45), prophecy.RevealQuote, {
		Color = rarity.Color,
		Duration = 1.2,
		Rise = 82,
		TextSize = rank >= 4 and 34 or 27,
		ZIndex = effectZ + 2,
	})
	if pityTriggered then
		task.delay(0.18, function()
			Juice.FloatText(panel, center + UDim2.fromOffset(0, 35), "✦ FATE ANSWERS ✦", {
				Color = THEME.GoldLight,
				Duration = 1.25,
				Rise = 62,
				TextSize = 25,
				ZIndex = effectZ + 3,
			})
		end)
	end

	Juice.Punch(orbScale, rank >= 4 and 0.42 or 0.28, 0.45)
	Juice.Punch(Juice.GetScale(readingCard), rank >= 4 and 0.14 or 0.08, 0.35)
	if rank >= 3 then
		Juice.Flash(screenGui, {
			Color = rarity.Color,
			Peak = rank >= 5 and 0.56 or 0.72,
			Duration = rank >= 5 and 0.7 or 0.45,
			ZIndex = 340,
		})
	end
	if rank >= 4 then
		Juice.Shake(panel, rank >= 5 and 9 or 6, 0.38)
	end

	Juice.PlaySound(uiPop, { Pitch = 0.82 + rank * 0.11, Volume = 0.8 })
end

local function animateReading(prophecy, pityTriggered: boolean)
	transientStatus = pityTriggered and "FATE HAS FILLED — a Rare-or-better future must answer." or "The crystal is searching countless possible futures..."
	refresh()
	Juice.Punch(orbScale, 0.18, 0.24)
	local center = Juice.CenterOf(orb, panel)
	if center then
		Juice.Ring(panel, center, {
			Color = THEME.VioletLight,
			StartSize = 30,
			EndSize = 190,
			Duration = 0.55,
			ZIndex = 328,
		})
	end

	-- Accelerating/decelerating cosmetic visions. The selected prophecy is
	-- already final on the server; none of these candidates can affect it.
	local totalVisions = 24
	for index = 1, totalVisions do
		local catalogIndex = ((index * 5 + state.TotalRolls) % #ProphecyConfig.Prophecies) + 1
		local candidate = ProphecyConfig.Prophecies[catalogIndex]
		renderProphecy(candidate, true)
		Juice.Punch(orbScale, 0.045 + index / totalVisions * 0.025, 0.1)

		if index % 3 == 0 then
			Juice.PlaySound(uiPop, {
				Pitch = 0.78 + (index / totalVisions) * 0.55,
				Volume = 0.3,
			})
		end
		if center and index % 6 == 0 then
			Juice.Burst(panel, center, {
				Count = 5,
				Colors = { rarityData(candidate).Color, THEME.White },
				Distance = 55 + index * 2,
				Duration = 0.35,
				Size = { 3, 7 },
				ZIndex = 329,
			})
		end

		local edgeSlowdown = math.abs(index - (totalVisions + 1) / 2) / (totalVisions / 2)
		task.wait(0.045 + edgeSlowdown * 0.055)
	end

	renderProphecy(prophecy)
	lastRenderedActiveId = prophecy.Id
	playRevealEffects(prophecy, pityTriggered)
	transientStatus = pityTriggered and "Fate delivered its promise. The prophecy is active now." or "The prophecy is active now — make this future count."
	rolling = false
	refresh()
end

local function requestReading()
	if rolling then
		return
	end
	if not dataLoaded then
		NotificationService.Info("Your prophecy history is still loading.", {
			Title = "Consulting the Stars",
			Icon = "✦",
			Key = "prophecy-loading",
		})
		return
	end
	if serverNow() < state.NextRollAt then
		NotificationService.Warning(("The crystal reawakens in %s."):format(formatTime(state.NextRollAt - serverNow())), {
			Title = "Crystal Recharging",
			Icon = "◈",
			Key = "prophecy-cooldown",
		})
		return
	end

	rolling = true
	transientStatus = "The veil stirs..."
	refresh()

	local ok, success, message, result = pcall(function()
		return RollFunction:InvokeServer()
	end)

	if not ok or not success then
		rolling = false
		if ok and type(result) == "table" and type(result.State) == "table" then
			applyPayload(result.State)
		end
		transientStatus = ok and (message or "The crystal went quiet. Try again.") or "The vision was interrupted. Try again."
		NotificationService.Push(transientStatus, {
			Kind = ok and "Warning" or "Error",
			Title = ok and "Vision Unavailable" or "Vision Interrupted",
			Icon = ok and "◈" or "×",
			Key = "prophecy-roll-failed",
		})
		Juice.Shake(rollButton, 4, 0.25)
		refresh()
		return
	end

	if type(result) ~= "table" then
		rolling = false
		transientStatus = "The crystal returned an unreadable vision. Try again."
		NotificationService.Error(transientStatus, {
			Title = "Vision Unreadable",
			Key = "prophecy-invalid-result",
		})
		refresh()
		return
	end

	if type(result.State) == "table" then
		applyPayload(result.State)
	end
	local prophecy = ProphecyConfig.GetById(result.ProphecyId)
	if not prophecy then
		rolling = false
		transientStatus = "The prophecy could not be deciphered."
		NotificationService.Error(transientStatus, {
			Title = "Prophecy Missing",
			Key = "prophecy-missing-result",
		})
		refresh()
		return
	end

	animateReading(prophecy, result.PityTriggered == true)
end

rollButton.Activated:Connect(requestReading)

-- =========================================================================
-- SYNC + COUNTDOWN
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	applyPayload(payload)
	if not rolling then
		transientStatus = nil
	end
	refresh()
end)

task.spawn(function()
	local ok, payload = pcall(function()
		return GetStateFunction:InvokeServer()
	end)
	if ok and type(payload) == "table" then
		applyPayload(payload)
	end
	refresh()
end)

task.spawn(function()
	while screenGui.Parent do
		task.wait(1)
		refresh()
	end
end)

refresh()

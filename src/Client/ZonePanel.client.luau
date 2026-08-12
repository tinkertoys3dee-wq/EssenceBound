--[[
	ZonePanel (LocalScript -> StarterPlayerScripts)
	===================================================
	Client for Zones (see ZonesConfig.luau, ZoneService.server.luau): a
	picker panel listing every zone, showing its lock state, unlock cost,
	and effective essence odds, plus a full-screen travel animation played
	on a CONFIRMED switch -- never optimistically before the server
	responds, same discipline WheelPanel's spin visual follows.

	The preferred trigger is the Studio-authored
	MainGui.Right.Holder.ZonesButton. If syncback ever omits or renames that
	instance, this script creates a matching fallback in the same slot so
	the entire zones feature can never become undiscoverable. Either a
	direct GuiButton or a Frame-wrapped TextButton/ImageButton is accepted.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ZonesConfig = require(ReplicatedStorage:WaitForChild("ZonesConfig"))
local LuckGamepassConfig = require(ReplicatedStorage:WaitForChild("LuckGamepassConfig"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local EssenceVisuals = require(ReplicatedStorage:WaitForChild("EssenceVisuals"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
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

-- Prefer the Studio-authored navigation instance. Generous timed waits (not
-- bare WaitForChild) keep a slow or incomplete MainGui from hanging the
-- whole script; the code-created fallback below takes over if resolution
-- fails.
local mainGui = playerGui:WaitForChild("MainGui", 15)
local rightHolster = mainGui and mainGui:WaitForChild("Right", 15)
local rightHolder = rightHolster and rightHolster:WaitForChild("Holder", 15)
local zonesButtonInstance = rightHolder and rightHolder:WaitForChild("ZonesButton", 15)

-- ZonesButton might be a real GuiButton directly, or a plain Frame
-- wrapping one (see the file header) -- resolve to whichever actually
-- has a click event before wiring anything to it.
local zonesButton
if zonesButtonInstance then
	zonesButton = zonesButtonInstance:IsA("GuiButton") and zonesButtonInstance
		or zonesButtonInstance:FindFirstChildWhichIsA("TextButton", true)
		or zonesButtonInstance:FindFirstChildWhichIsA("ImageButton", true)
end
if not zonesButton then
	warn("ZonePanel: Zones navigation trigger missing or invalid -- using code-created fallback.")
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

-- Right.Holder is Studio-owned and isn't fully represented in this repo.
-- Keep the feature reachable if that authored button is ever lost during a
-- sync by rebuilding only the missing entry point, not the whole nav rail.
if not zonesButton then
	local fallbackHolder = new("Frame", {
		Name = "FallbackZonesButtonHolder",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.84, 0.415),
		Size = UDim2.fromScale(0.13, 0.066),
		BackgroundTransparency = 1,
		ZIndex = 60,
	}, screenGui)

	zonesButton = new("TextButton", {
		Name = "FallbackZonesButton",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.BackgroundLight,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "💎  ZONES",
		TextColor3 = THEME.White,
		TextScaled = true,
		ZIndex = 61,
	}, fallbackHolder)
	corner(zonesButton, UDim.new(0.32, 0))
	stroke(zonesButton, THEME.Accent, 2, 0.08)
	new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 15 }, zonesButton)
	Juice.ButtonFeel(zonesButton, { HoverScale = 1.05 })
end

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
	local specialtyShort = (zone.SpecialtyEssence or "Essence"):gsub(" Essence", "")
	local card = new("Frame", {
		Name = "Card_" .. zone.Id,
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = THEME.BackgroundLight,
		BorderSizePixel = 0,
		ZIndex = 202,
	}, listHolder)
	card:SetAttribute("AstralAccentColor", zone.Color)
	corner(card, UDim.new(0, 12))
	local cardStroke = stroke(card, zone.Color, 2, 0.35)

	local iconBg = new("Frame", {
		Name = "EssenceOrbPedestal",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.04, 0, 0.45, 0),
		Size = UDim2.new(0, 0, 0.56, 0),
		BackgroundColor3 = zone.Color,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		ZIndex = 203,
	}, card)
	iconBg:SetAttribute("AstralAccentColor", zone.Color)
	corner(iconBg, UDim.new(0.5, 0))
	stroke(iconBg, zone.Color, 1.6, 0.18)
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, iconBg)

	local orbGlow = new("ImageLabel", {
		Name = "OrbGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.75, 1.75),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Glow.png",
		ImageColor3 = zone.Color,
		ImageTransparency = 0.64,
		ZIndex = 203,
	}, iconBg)

	local orbRing = new("ImageLabel", {
		Name = "OrbOrbit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.25, 1.25),
		BackgroundTransparency = 1,
		Image = "rbxassetid://91692624575395",
		ImageColor3 = zone.Color,
		ImageTransparency = 0.28,
		ZIndex = 204,
	}, iconBg)

	local orbImage = new("ImageLabel", {
		Name = "EssenceOrbImage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.78, 0.78),
		BackgroundTransparency = 1,
		Image = zone.EssenceOrbImage or "",
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 205,
	}, iconBg)
	EssenceVisuals.ApplyToImage(orbImage, zone.SpecialtyEssence, { Scale = 0.98 })
	local orbScale = new("UIScale", { Scale = 1 }, orbImage)

	local glyphBadge = new("TextLabel", {
		Name = "ZoneGlyph",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(-0.05, -0.05),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = THEME.Background,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = zone.Icon,
		TextScaled = true,
		ZIndex = 206,
	}, iconBg)
	glyphBadge:SetAttribute("AstralAccentColor", zone.Color)
	corner(glyphBadge, UDim.new(0.5, 0))
	stroke(glyphBadge, zone.Color, 1.2, 0.1)

	local specialtyLabel = new("TextLabel", {
		Name = "SpecialtyPill",
		Position = UDim2.new(0.025, 0, 0.79, 0),
		Size = UDim2.new(0.2, 0, 0.12, 0),
		BackgroundColor3 = zone.Color,
		BackgroundTransparency = 0.8,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = string.upper(specialtyShort) .. " ORB",
		TextColor3 = zone.Color:Lerp(THEME.White, 0.5),
		TextScaled = true,
		ZIndex = 204,
	}, card)
	specialtyLabel:SetAttribute("AstralAccentColor", zone.Color)
	corner(specialtyLabel, UDim.new(1, 0))
	stroke(specialtyLabel, zone.Color, 1, 0.35)
	new("UITextSizeConstraint", { MinTextSize = 7, MaxTextSize = 10 }, specialtyLabel)

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
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = THEME.Background,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 203,
	}, card)
	actionButton:SetAttribute("AstralAccentColor", zone.Color)
	corner(actionButton, UDim.new(0.2, 0))
	new("UITextSizeConstraint", { MaxTextSize = 16 }, actionButton)
	Juice.ButtonFeel(actionButton, {})

	cards[zone.Id] = {
		Zone = zone,
		Card = card,
		Stroke = cardStroke,
		OddsLabel = oddsLabel,
		ActionButton = actionButton,
		OrbGlow = orbGlow,
		OrbRing = orbRing,
		OrbScale = orbScale,
		SpecialtyLabel = specialtyLabel,
	}

	actionButton.MouseButton1Click:Connect(function()
		requestZoneAction(zone)
	end)
end

-- =========================================================================
-- TRAVEL TRANSITION
-- =========================================================================
-- This is a short, confirmed-server-only travel cinematic rather than an
-- optimistic loading splash. A full-screen input-catching veil guarantees
-- complete coverage on every aspect ratio; two energy shutters close over
-- the old zone, the destination's REAL collectible orb is attuned inside a
-- counter-rotating portal, then the new zone is revealed. Every animation
-- is a finite TweenService tween (no hidden RenderStepped loops), and a
-- token invalidates delayed callbacks if another transition supersedes it.

local PORTAL_RING_IMAGE = "rbxassetid://91692624575395"

local transitionGui = new("ScreenGui", {
	Name = "ZoneTransition",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 150,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local veil = new("TextButton", {
	Name = "Veil",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Active = false,
	Modal = false,
	Selectable = false,
	Visible = false,
	ZIndex = 500,
}, transitionGui)

local veilGradient = new("UIGradient", {
	Rotation = 28,
	Color = ColorSequence.new(THEME.Background, THEME.BackgroundLight),
}, veil)

local radialGlow = new("ImageLabel", {
	Name = "AstralDestinationGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.fromScale(0.92, 1.32),
	BackgroundTransparency = 1,
	Image = "rbxasset://textures/ui/Glow.png",
	ImageColor3 = THEME.Accent,
	ImageTransparency = 1,
	ZIndex = 501,
}, veil)

-- Sliding halves hide the old zone before the attunement reveal. Their
-- gradients are recolored per destination rather than hardcoded to one
-- generic blue travel effect.
local leftShutter = new("Frame", {
	Name = "AstralLeftGate",
	Position = UDim2.fromScale(-0.52, 0),
	Size = UDim2.fromScale(0.52, 1),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ZIndex = 502,
}, veil)
local leftShutterGradient = new("UIGradient", { Rotation = 0 }, leftShutter)

local rightShutter = new("Frame", {
	Name = "AstralRightGate",
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.52, 1),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ZIndex = 502,
}, veil)
local rightShutterGradient = new("UIGradient", { Rotation = 180 }, rightShutter)

local seam = new("Frame", {
	Name = "AstralGateSeam",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.0025, 0.86),
	BackgroundColor3 = THEME.White,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 503,
}, veil)
new("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.25),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.8, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, seam)

local streakLayer = new("Frame", {
	Name = "AstralTravelStreaks",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 504,
}, veil)

local travelStreaks = {}
for index = 1, 16 do
	local travelsRight = index % 2 == 0
	local y = 0.08 + (((index * 37) % 82) / 100)
	local startX = travelsRight and -0.24 or 1.24
	local endX = travelsRight and 1.24 or -0.24
	local streak = new("Frame", {
		Name = "AstralStreak" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(startX, y),
		Size = UDim2.fromScale(0.12 + ((index % 4) * 0.025), 0.003 + ((index % 3) * 0.001)),
		BackgroundColor3 = THEME.White,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Rotation = travelsRight and -4 or 4,
		ZIndex = 504,
	}, streakLayer)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.38, 0.12),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, streak)
	table.insert(travelStreaks, {
		Object = streak,
		Start = UDim2.fromScale(startX, y),
		Finish = UDim2.fromScale(endX, y + (travelsRight and -0.025 or 0.025)),
	})
end

local transitionStage = new("CanvasGroup", {
	Name = "AstralAttunementStage",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 1,
	ZIndex = 505,
}, veil)

local topRule = new("Frame", {
	Name = "AstralTopRule",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.095),
	Size = UDim2.fromScale(0.32, 0.0025),
	BackgroundColor3 = THEME.Accent,
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	ZIndex = 506,
}, transitionStage)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.1),
		NumberSequenceKeypoint.new(0.75, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, topRule)

local transitionEyebrow = new("TextLabel", {
	Name = "AstralAttunementEyebrow",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.045),
	Size = UDim2.fromScale(0.54, 0.044),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✦  ESSENCE PATH // ZONE ATTUNEMENT  ✦",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	TextTransparency = 0.06,
	ZIndex = 506,
}, transitionStage)
new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 18 }, transitionEyebrow)

local portalRoot = new("Frame", {
	Name = "AstralPortal",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.38),
	Size = UDim2.fromScale(0.28, 0.34),
	BackgroundTransparency = 1,
	ZIndex = 506,
}, transitionStage)
new("UIAspectRatioConstraint", {
	AspectRatio = 1,
	DominantAxis = Enum.DominantAxis.Height,
}, portalRoot)
new("UISizeConstraint", {
	MinSize = Vector2.new(145, 145),
	MaxSize = Vector2.new(320, 320),
}, portalRoot)
local portalScale = new("UIScale", { Scale = 0.5 }, portalRoot)

local portalGlow = new("ImageLabel", {
	Name = "AstralPortalGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.9, 1.9),
	BackgroundTransparency = 1,
	Image = "rbxasset://textures/ui/Glow.png",
	ImageColor3 = THEME.Accent,
	ImageTransparency = 0.9,
	ZIndex = 506,
}, portalRoot)

local portalOuterRing = new("ImageLabel", {
	Name = "AstralPortalOuterRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.42, 1.42),
	BackgroundTransparency = 1,
	Image = PORTAL_RING_IMAGE,
	ImageColor3 = THEME.Accent,
	ImageTransparency = 0.05,
	ZIndex = 507,
}, portalRoot)

local portalInnerRing = new("ImageLabel", {
	Name = "AstralPortalInnerRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.08, 1.08),
	BackgroundTransparency = 1,
	Image = PORTAL_RING_IMAGE,
	ImageColor3 = THEME.White,
	ImageTransparency = 0.34,
	ZIndex = 508,
}, portalRoot)

local moteOrbit = new("Frame", {
	Name = "AstralMoteOrbit",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.18, 1.18),
	BackgroundTransparency = 1,
	ZIndex = 509,
}, portalRoot)
for index, position in ipairs({
	UDim2.fromScale(0.5, 0.01),
	UDim2.fromScale(0.99, 0.5),
	UDim2.fromScale(0.5, 0.99),
	UDim2.fromScale(0.01, 0.5),
}) do
	local mote = new("Frame", {
		Name = "AstralPortalMote" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(index % 2 == 0 and 6 or 9, index % 2 == 0 and 6 or 9),
		BackgroundColor3 = THEME.White,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 509,
	}, moteOrbit)
	corner(mote, UDim.new(1, 0))
end

local portalDisc = new("Frame", {
	Name = "AstralPortalCore",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.8),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	ZIndex = 510,
}, portalRoot)
corner(portalDisc, UDim.new(1, 0))
local portalStroke = stroke(portalDisc, THEME.Accent, 2.4, 0.08)
local portalDiscGradient = new("UIGradient", {
	Rotation = 42,
	Color = ColorSequence.new(THEME.Background, THEME.BackgroundLight),
}, portalDisc)

local transitionOrb = new("ImageLabel", {
	Name = "AstralDestinationOrb",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.7, 0.7),
	BackgroundTransparency = 1,
	Image = "",
	ScaleType = Enum.ScaleType.Fit,
	ZIndex = 511,
}, portalDisc)
local transitionOrbScale = new("UIScale", { Scale = 0.45 }, transitionOrb)

local transitionGlyph = new("TextLabel", {
	Name = "AstralDestinationGlyph",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.83, 0.18),
	Size = UDim2.fromScale(0.23, 0.23),
	BackgroundColor3 = THEME.Background,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextScaled = true,
	ZIndex = 512,
}, portalRoot)
corner(transitionGlyph, UDim.new(1, 0))
local glyphStroke = stroke(transitionGlyph, THEME.Accent, 1.4, 0.08)

local transitionName = new("TextLabel", {
	Name = "AstralDestinationName",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.585),
	Size = UDim2.fromScale(0.82, 0.075),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextStrokeColor3 = THEME.Background,
	TextStrokeTransparency = 0.55,
	ZIndex = 506,
}, transitionStage)
new("UITextSizeConstraint", { MinTextSize = 21, MaxTextSize = 44 }, transitionName)

local transitionSpecialty = new("TextLabel", {
	Name = "AstralDestinationResonance",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.665),
	Size = UDim2.fromScale(0.68, 0.04),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	ZIndex = 506,
}, transitionStage)
new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 17 }, transitionSpecialty)

local transitionStatus = new("TextLabel", {
	Name = "AstralTravelStatus",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.725),
	Size = UDim2.fromScale(0.7, 0.035),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "LOCATING ESSENCE PATH...",
	TextColor3 = Color3.fromRGB(225, 220, 232),
	TextScaled = true,
	ZIndex = 506,
}, transitionStage)
new("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = 15 }, transitionStatus)

local progressTrack = new("Frame", {
	Name = "AstralAttunementTrack",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.78),
	Size = UDim2.fromScale(0.42, 0.018),
	BackgroundColor3 = THEME.White,
	BackgroundTransparency = 0.72,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 506,
}, transitionStage)
corner(progressTrack, UDim.new(1, 0))
stroke(progressTrack, THEME.White, 1, 0.65)
new("UISizeConstraint", {
	MinSize = Vector2.new(170, 10),
	MaxSize = Vector2.new(520, 15),
}, progressTrack)

local progressFill = new("Frame", {
	Name = "AstralAttunementEnergy",
	Size = UDim2.fromScale(0.02, 1),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 507,
}, progressTrack)
corner(progressFill, UDim.new(1, 0))
local progressGradient = new("UIGradient", {
	Color = ColorSequence.new(THEME.Accent, THEME.White),
}, progressFill)

local progressGlint = new("Frame", {
	Name = "AstralProgressGlint",
	Position = UDim2.fromScale(-0.35, 0),
	Size = UDim2.fromScale(0.28, 1),
	BackgroundColor3 = THEME.White,
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 508,
}, progressFill)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, progressGlint)

local arrivalLabel = new("TextLabel", {
	Name = "AstralArrivalLabel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.825),
	Size = UDim2.fromScale(0.42, 0.034),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "ATTUNING DESTINATION",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 506,
}, transitionStage)
new("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = 13 }, arrivalLabel)

local COVER_TIME = 0.42
local DISPLAY_TIME = 1.72
local RELEASE_TIME = 0.48
local transitionToken = 0
local activeTransitionTweens = {}
local transitionSound = Juice.FindSound("SFX/UI/UIPop")

local function cancelTransitionTweens()
	for _, activeTween in ipairs(activeTransitionTweens) do
		activeTween:Cancel()
	end
	table.clear(activeTransitionTweens)
end

local function playTransitionTween(object, info, properties)
	local activeTween = tween(object, info, properties)
	table.insert(activeTransitionTweens, activeTween)
	activeTween:Play()
	return activeTween
end

-- Plays a confirmed travel to `zone` and calls onComplete once the veil
-- has fully lifted again. Never called optimistically before the server
-- responds -- see requestZoneAction below.
local function playZoneTransition(zone, onComplete)
	transitionToken += 1
	local myToken = transitionToken
	cancelTransitionTweens()

	local specialtyName = string.upper(zone.SpecialtyEssence or "ESSENCE")
	local deepColor = zone.Color:Lerp(Color3.fromRGB(7, 3, 16), 0.78)
	local middleColor = zone.Color:Lerp(THEME.Background, 0.56)
	local highlightColor = zone.Color:Lerp(THEME.White, 0.56)

	veil.Visible = true
	veil.Active = true
	veil.Modal = true
	veil.BackgroundColor3 = deepColor
	veil.BackgroundTransparency = 1
	veilGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(6, 3, 14)),
		ColorSequenceKeypoint.new(0.48, middleColor),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 2, 10)),
	})
	radialGlow.ImageColor3 = zone.Color
	radialGlow.ImageTransparency = 1
	radialGlow.Size = UDim2.fromScale(0.48, 0.7)

	leftShutter.Position = UDim2.fromScale(-0.52, 0)
	rightShutter.Position = UDim2.fromScale(1, 0)
	leftShutter.BackgroundColor3 = deepColor
	rightShutter.BackgroundColor3 = deepColor
	leftShutterGradient.Color = ColorSequence.new(deepColor, middleColor)
	rightShutterGradient.Color = ColorSequence.new(deepColor, middleColor)
	seam.BackgroundColor3 = highlightColor
	seam.BackgroundTransparency = 1

	transitionStage.GroupTransparency = 1
	portalScale.Scale = 0.5
	transitionOrbScale.Scale = 0.45
	portalGlow.ImageColor3 = zone.Color
	portalGlow.ImageTransparency = 0.9
	portalOuterRing.ImageColor3 = zone.Color
	portalOuterRing.ImageTransparency = 0.05
	portalOuterRing.Size = UDim2.fromScale(1.42, 1.42)
	portalOuterRing.Rotation = -55
	portalInnerRing.ImageColor3 = highlightColor
	portalInnerRing.ImageTransparency = 0.34
	portalInnerRing.Rotation = 45
	moteOrbit.Rotation = 0
	portalDisc.BackgroundColor3 = deepColor
	portalDiscGradient.Color = ColorSequence.new(deepColor, middleColor)
	portalStroke.Color = highlightColor
	glyphStroke.Color = highlightColor
	EssenceVisuals.ApplyToImage(transitionOrb, zone.SpecialtyEssence, { Scale = 0.98 })
	transitionGlyph.Text = zone.Icon
	transitionGlyph.BackgroundColor3 = deepColor
	transitionName.Text = string.upper(zone.Name)
	transitionName.TextColor3 = highlightColor
	transitionSpecialty.Text = ("✦  %s RESONANCE  ✦"):format(specialtyName)
	transitionSpecialty.TextColor3 = zone.Color:Lerp(THEME.White, 0.36)
	transitionStatus.Text = "LOCATING ESSENCE PATH..."
	arrivalLabel.Text = "ATTUNING DESTINATION"
	arrivalLabel.TextColor3 = zone.Color:Lerp(THEME.White, 0.2)
	topRule.BackgroundColor3 = zone.Color
	progressFill.BackgroundColor3 = zone.Color
	progressFill.Size = UDim2.fromScale(0.02, 1)
	progressGradient.Color = ColorSequence.new(zone.Color, highlightColor)
	progressGlint.Position = UDim2.fromScale(-0.35, 0)

	for _, streakData in ipairs(travelStreaks) do
		streakData.Object.Position = streakData.Start
		streakData.Object.BackgroundColor3 = highlightColor
		streakData.Object.BackgroundTransparency = 1
	end

	local coverTween = playTransitionTween(veil, TweenInfo.new(COVER_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.015,
	})
	playTransitionTween(leftShutter, TweenInfo.new(COVER_TIME * 0.88, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0, 0),
	})
	playTransitionTween(rightShutter, TweenInfo.new(COVER_TIME * 0.88, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.48, 0),
	})
	playTransitionTween(radialGlow, TweenInfo.new(COVER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 0.54,
		Size = UDim2.fromScale(1.02, 1.48),
	})

	coverTween.Completed:Connect(function()
		if transitionToken ~= myToken or not veil.Visible then
			return
		end

		playTransitionTween(transitionStage, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			GroupTransparency = 0,
		})
		playTransitionTween(portalScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		playTransitionTween(transitionOrbScale, TweenInfo.new(0.62, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		})
		playTransitionTween(portalGlow, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			ImageTransparency = 0.2,
		})
		playTransitionTween(portalOuterRing, TweenInfo.new(1.48, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Rotation = 305,
		})
		playTransitionTween(portalInnerRing, TweenInfo.new(1.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Rotation = -315,
		})
		playTransitionTween(moteOrbit, TweenInfo.new(1.62, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Rotation = 360,
		})
		playTransitionTween(progressFill, TweenInfo.new(1.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 1),
		})
		playTransitionTween(progressGlint, TweenInfo.new(1.08, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			Position = UDim2.fromScale(1.05, 0),
		})
		playTransitionTween(seam, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.08,
		})

		for index, streakData in ipairs(travelStreaks) do
			task.delay(((index - 1) % 4) * 0.045, function()
				if transitionToken ~= myToken then
					return
				end
				streakData.Object.BackgroundTransparency = 0.18
				playTransitionTween(streakData.Object, TweenInfo.new(0.62 + ((index % 3) * 0.09), Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Position = streakData.Finish,
					BackgroundTransparency = 1,
				})
			end)
		end

		Juice.PlaySound(transitionSound, { Pitch = 0.82, Volume = 0.55 })
		Juice.Flash(veil, { Color = highlightColor, Peak = 0.82, Duration = 0.34, ZIndex = 520 })
		Juice.Ring(veil, UDim2.fromScale(0.5, 0.38), {
			Color = highlightColor,
			StartSize = 70,
			EndSize = 300,
			Duration = 0.72,
			Thickness = 4,
			ZIndex = 513,
		})
		task.delay(0.18, function()
			if transitionToken == myToken then
				Juice.Ring(veil, UDim2.fromScale(0.5, 0.38), {
					Color = zone.Color,
					StartSize = 90,
					EndSize = 410,
					Duration = 0.82,
					Thickness = 2.5,
					ZIndex = 513,
				})
			end
		end)
		Juice.Burst(veil, UDim2.fromScale(0.5, 0.46), {
			Count = 22,
			Colors = { THEME.White, highlightColor, zone.Color },
			Distance = 250,
			Duration = 0.92,
			Size = { 4, 11 },
			ZIndex = 514,
		})

		task.delay(0.56, function()
			if transitionToken == myToken then
				transitionStatus.Text = "ESSENCE SIGNATURE ACQUIRED"
				arrivalLabel.Text = "PATH STABILIZING"
				Juice.PlaySound(transitionSound, { Pitch = 1.04, Volume = 0.38 })
			end
		end)
		task.delay(1.12, function()
			if transitionToken == myToken then
				transitionStatus.Text = "DESTINATION LOCKED"
				arrivalLabel.Text = "✦  ARRIVAL CONFIRMED  ✦"
				Juice.Punch(transitionOrbScale, 0.15, 0.22)
			end
		end)
	end)

	task.delay(COVER_TIME + DISPLAY_TIME, function()
		if transitionToken ~= myToken then
			return
		end

		playTransitionTween(transitionStage, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		})
		playTransitionTween(portalScale, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Scale = 1.36,
		})
		playTransitionTween(portalOuterRing, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Size = UDim2.fromScale(1.9, 1.9),
			ImageTransparency = 1,
		})
		playTransitionTween(seam, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		playTransitionTween(leftShutter, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(-0.52, 0),
		})
		playTransitionTween(rightShutter, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(1, 0),
		})
		playTransitionTween(radialGlow, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			ImageTransparency = 1,
		})
		Juice.Flash(veil, { Color = THEME.White, Peak = 0.88, Duration = 0.28, ZIndex = 520 })

		local releaseTween = playTransitionTween(veil, TweenInfo.new(RELEASE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		releaseTween.Completed:Connect(function()
			if transitionToken ~= myToken then
				return
			end
			table.clear(activeTransitionTweens)
			veil.Visible = false
			veil.Active = false
			veil.Modal = false
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
	local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0

	-- Dedicated Essence amplifies WHICHEVER zone you're standing in, not
	-- just the one you happen to be in right now -- so every card's
	-- preview should reflect ownership the same way, not only the active
	-- one. This is a preview only: the real roll (GetEssence.luau) always
	-- re-reads both live at collection time regardless of what this shows.
	for zoneId, entry in pairs(cards) do
		local zone = entry.Zone
		local weights = ZonesConfig.GetEssenceWeightsForZone(zone, player)
		local total = 0
		for _, weight in pairs(weights) do
			total += weight
		end
		local oddsParts = {}
		for _, essence in ipairs(EssenceConfig.Ordered) do
			local percent = total > 0 and math.floor(100 * (weights[essence.Name] or 0) / total + 0.5) or 0
			table.insert(oddsParts, ("%s %d%%"):format(essence.Glyph, percent))
		end
		entry.OddsLabel.Text = table.concat(oddsParts, "  •  ")

		local isCurrent = zoneId == currentZoneId
		local unlocked = ZonesConfig.IsZoneUnlocked(player, zoneId)

		entry.Stroke.Color = zone.Color
		entry.Stroke.Transparency = isCurrent and 0 or 0.35
		entry.Stroke.Thickness = isCurrent and 3 or 2
		entry.Card.BackgroundColor3 = isCurrent
			and THEME.BackgroundLight:Lerp(zone.Color, 0.13)
			or THEME.BackgroundLight
		entry.OrbGlow.ImageTransparency = isCurrent and 0.38 or 0.64
		entry.OrbRing.ImageTransparency = isCurrent and 0.06 or 0.28
		entry.SpecialtyLabel.BackgroundTransparency = isCurrent and 0.66 or 0.8

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
			local requiredRebirth = tonumber(zone.RebirthRequired) or 0
			if rebirths < requiredRebirth then
				-- Locked cards stay clickable so the player gets an explanation
				-- instead of a button that appears to ignore them.
				button.Active = true
				button.BackgroundColor3 = THEME.Locked
				button.Text = ("🔒 REBIRTH %d\nREQUIRED"):format(requiredRebirth)
			else
				local canAfford = true
				local costParts = {}
				local unlockCosts = ZonesConfig.GetUnlockCosts(zone)
				for _, essence in ipairs(EssenceConfig.Ordered) do
					local amount = unlockCosts[essence.DataKey]
					if amount then
						local stat = leaderstats and leaderstats:FindFirstChild(essence.Name)
						local balance = stat and tonumber(stat:GetAttribute("Quantity")) or 0
						canAfford = canAfford and balance >= amount
						table.insert(costParts, ("%s %s"):format(formatNumber(amount), essence.ShortName))
					end
				end
				button.Active = true
				button.BackgroundColor3 = canAfford and THEME.Accent or THEME.Locked
				button.Text = "🔒 UNLOCK\n" .. table.concat(costParts, " + ")
			end
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
		local failureMessage = (ok and message) or "Something went wrong -- try again."
		statusLabel.Text = failureMessage
		local isGate = string.find(string.lower(tostring(failureMessage)), "need", 1, true)
			or string.find(string.lower(tostring(failureMessage)), "rebirth", 1, true)
			or string.find(string.lower(tostring(failureMessage)), "unlock", 1, true)
		NotificationService.Push(failureMessage, {
			Kind = isGate and "Warning" or "Error",
			Title = isGate and "Zone Locked" or "Travel Interrupted",
			Icon = isGate and "◇" or "×",
			Key = "zone-failure:" .. zone.Id,
		})
		refresh()
		return
	end

	statusLabel.Text = ""
	refresh()
	NotificationService.Success(
		unlocked and ("Traveling to %s."):format(zone.Name) or ("%s unlocked — traveling now."):format(zone.Name),
		{
			Title = unlocked and "Zone Attuned" or "New Zone Unlocked",
			Icon = zone.Icon,
			Duration = 2.7,
			Key = "zone-success:" .. zone.Id,
		}
	)
	closePanel()
	playZoneTransition(zone)
end

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local open = false
local openAnimationToken = 0

closePanel = function()
	if not open then
		return
	end
	open = false
	openAnimationToken += 1

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
	openAnimationToken += 1
	local myOpenToken = openAnimationToken

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	panel.Visible = true
	panelScale.Scale = 0.85
	tween(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	refresh()

	-- Each zone's real orb materializes when the picker opens. Finite,
	-- staggered ring turns keep the art feeling alive without running
	-- animation loops behind a closed panel.
	local currentZoneId = ZonesConfig.GetCurrentZoneId(player)
	for index, zone in ipairs(ZonesConfig.Zones) do
		local entry = cards[zone.Id]
		task.delay((index - 1) * 0.075, function()
			if not open or openAnimationToken ~= myOpenToken or not entry.Card.Parent then
				return
			end
			local isCurrent = zone.Id == currentZoneId
			local restingGlowTransparency = isCurrent and 0.38 or 0.64
			entry.OrbRing.Rotation = -38
			entry.OrbScale.Scale = 0.72
			entry.OrbGlow.ImageTransparency = 0.12
			tween(entry.OrbRing, TweenInfo.new(0.72, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Rotation = 322,
			}):Play()
			tween(entry.OrbScale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
			tween(entry.OrbGlow, TweenInfo.new(0.64, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				ImageTransparency = restingGlowTransparency,
			}):Play()
		end)
	end
end

_G.EssenceboundZones = {
	Open = openPanel,
	Close = closePanel,
	IsOpen = function()
		return open
	end,
}

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
player:GetAttributeChangedSignal(MonetizationConfig.GetOwnershipAttribute(ZonesConfig.DedicatedEssenceGamepassId)):Connect(refresh)
player:GetAttributeChangedSignal(MonetizationConfig.GetOwnershipAttribute(LuckGamepassConfig.LuckyFinderGamepassId)):Connect(refresh)
player:GetAttributeChangedSignal(MonetizationConfig.GetOwnershipAttribute(LuckGamepassConfig.UltraLuckGamepassId)):Connect(refresh)
player:GetAttributeChangedSignal("ProphecyRareWeightMultiplier"):Connect(refresh)
for _, zone in ipairs(ZonesConfig.Zones) do
	if next(zone.UnlockCosts or {}) then
		player:GetAttributeChangedSignal(ZonesConfig.UnlockedAttributeName(zone.Id)):Connect(refresh)
	end
end
player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)

task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 15)
	if not leaderstats then
		return
	end
	for _, essence in ipairs(EssenceConfig.Ordered) do
		local stat = leaderstats:WaitForChild(essence.Name, 15)
		if stat then
			stat:GetAttributeChangedSignal("Quantity"):Connect(refresh)
		end
	end
end)

refresh()

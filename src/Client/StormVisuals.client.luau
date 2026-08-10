--[[
	StormVisuals (LocalScript -> StarterPlayerScripts)
	===================================================
	Presentation-only director for Essence Storms. OrbClicker remains the
	owner of collectible falling orbs and StormController remains the
	server-authoritative owner of timing/rewards; this script only turns the
	already-confirmed StormStart / StormEnd signals into a premium event.

	The effect has three layers:
	  1. a restrained full-screen weather grade that never consumes input,
	  2. a tri-essence storm eye using Earth, Shadow, and Solar orb artwork,
	  3. pooled rain streaks plus short, self-cleaning lightning strikes.

	Only three looping tweens (the portal rings and tri-orb orbit) live for
	the storm's duration.
	Rain streaks are pooled, lightning instances are Debris-cleaned, and a
	storm token invalidates every delayed callback as soon as the event ends
	or a newer event replaces it. This keeps a 60-second storm safe on phones
	without flattening the spectacle.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local ZonesConfig = require(ReplicatedStorage:WaitForChild("ZonesConfig"))
local EssenceVisuals = require(ReplicatedStorage:WaitForChild("EssenceVisuals"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local EssenceStormEvent = remotes:WaitForChild("EssenceStorm")

local RING_IMAGE = "rbxassetid://91692624575395"
local GLOW_IMAGE = "rbxasset://textures/ui/Glow.png"

local function new(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	}, parent)
end

local function tween(object, duration, style, direction, props)
	local activeTween = TweenService:Create(
		object,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		props
	)
	activeTween:Play()
	return activeTween
end

local screenGui = new("ScreenGui", {
	Name = "EssenceStormVisuals",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 34,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- A plain inactive Frame cannot intercept clicks. The storm can therefore
-- look screen-filling without making the normal HUD or falling orbs harder
-- to use—the most important interaction rule for a collectible rain event.
local root = new("Frame", {
	Name = "StormAtmosphere",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	Visible = false,
	ZIndex = 1,
}, screenGui)

local tint = new("Frame", {
	Name = "WeatherGrade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(20, 35, 72),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 1,
}, root)
local tintGradient = new("UIGradient", {
	Rotation = 90,
}, tint)

local topCloud = new("ImageLabel", {
	Name = "StormCeiling",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, -0.38),
	Size = UDim2.fromScale(1.38, 0.78),
	BackgroundTransparency = 1,
	Image = GLOW_IMAGE,
	ImageColor3 = Color3.fromRGB(112, 202, 255),
	ImageTransparency = 1,
	Active = false,
	ZIndex = 2,
}, root)

local bottomHaze = new("ImageLabel", {
	Name = "GroundHaze",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1.15),
	Size = UDim2.fromScale(1.25, 0.48),
	BackgroundTransparency = 1,
	Image = GLOW_IMAGE,
	ImageColor3 = Color3.fromRGB(187, 104, 255),
	ImageTransparency = 1,
	Rotation = 180,
	Active = false,
	ZIndex = 2,
}, root)

local leftEdge = new("Frame", {
	Name = "LeftStormEdge",
	Size = UDim2.fromScale(0.17, 1),
	BackgroundColor3 = Color3.fromRGB(112, 202, 255),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 2,
}, root)
local leftEdgeGradient = new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, leftEdge)

local rightEdge = new("Frame", {
	Name = "RightStormEdge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.fromScale(0.17, 1),
	BackgroundColor3 = Color3.fromRGB(187, 104, 255),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 2,
}, root)
local rightEdgeGradient = new("UIGradient", {
	Rotation = 180,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, rightEdge)

local rainLayer = new("Frame", {
	Name = "StormRain",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = false,
	ZIndex = 3,
}, root)

-- Pooled once, then recycled for the entire event. There can never be more
-- than this fixed count regardless of storm duration or intensity.
local rainStreaks = {}
for index = 1, 24 do
	local streak = new("Frame", {
		Name = "RainStreak" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.1, -0.2),
		Size = UDim2.new(0, 2, 0.12, 0),
		BackgroundColor3 = Color3.fromRGB(140, 220, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Rotation = -8,
		Active = false,
		ZIndex = 3,
	}, rainLayer)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.22, 0.1),
			NumberSequenceKeypoint.new(0.8, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, streak)
	table.insert(rainStreaks, streak)
end

local portalRoot = new("Frame", {
	Name = "StormEye",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, -0.12),
	Size = UDim2.fromScale(0.22, 0.25),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 5,
}, root)
new("UIAspectRatioConstraint", {
	AspectRatio = 1,
	DominantAxis = Enum.DominantAxis.Width,
}, portalRoot)
new("UISizeConstraint", {
	MinSize = Vector2.new(118, 118),
	MaxSize = Vector2.new(250, 250),
}, portalRoot)
local portalScale = new("UIScale", { Scale = 0.35 }, portalRoot)

local portalGlow = new("ImageLabel", {
	Name = "StormEyeGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(2.1, 2.1),
	BackgroundTransparency = 1,
	Image = GLOW_IMAGE,
	ImageColor3 = Color3.fromRGB(112, 202, 255),
	ImageTransparency = 1,
	Active = false,
	ZIndex = 5,
}, portalRoot)

local outerRing = new("ImageLabel", {
	Name = "StormEyeOuterRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.36, 1.36),
	BackgroundTransparency = 1,
	Image = RING_IMAGE,
	ImageColor3 = Color3.fromRGB(112, 202, 255),
	ImageTransparency = 1,
	Active = false,
	ZIndex = 6,
}, portalRoot)

local innerRing = new("ImageLabel", {
	Name = "StormEyeInnerRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.03, 1.03),
	BackgroundTransparency = 1,
	Image = RING_IMAGE,
	ImageColor3 = Color3.fromRGB(222, 188, 255),
	ImageTransparency = 1,
	Active = false,
	ZIndex = 7,
}, portalRoot)

local core = new("Frame", {
	Name = "StormEyeCore",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.62, 0.62),
	BackgroundColor3 = Color3.fromRGB(15, 24, 58),
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 8,
}, portalRoot)
corner(core)
local coreStroke = stroke(core, Color3.fromRGB(112, 202, 255), 2.2, 0.06)
local coreGradient = new("UIGradient", { Rotation = 35 }, core)

local stormGlyph = new("TextLabel", {
	Name = "StormGlyph",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "ϟ",
	TextColor3 = Color3.fromRGB(240, 248, 255),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(25, 12, 55),
	TextStrokeTransparency = 0.52,
	Active = false,
	ZIndex = 9,
}, core)

-- The actual collectible assets orbit the storm eye, making it immediately
-- clear that this event rains every essence currency—not generic sparks.
local orbOrbit = new("Frame", {
	Name = "StormEssenceOrbit",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.03, 1.03),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = false,
	ZIndex = 10,
}, portalRoot)

local earthOrb = new("ImageLabel", {
	Name = "EarthEssenceOrb",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.05, 0.5),
	Size = UDim2.fromScale(0.23, 0.23),
	BackgroundTransparency = 1,
	Image = ZonesConfig.EssenceOrbImages["Earth Essence"],
	ScaleType = Enum.ScaleType.Fit,
	Active = false,
	ZIndex = 10,
}, orbOrbit)
local shadowOrb = new("ImageLabel", {
	Name = "ShadowEssenceOrb",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.95, 0.5),
	Size = UDim2.fromScale(0.23, 0.23),
	BackgroundTransparency = 1,
	Image = ZonesConfig.EssenceOrbImages["Shadow Essence"],
	ScaleType = Enum.ScaleType.Fit,
	Active = false,
	ZIndex = 10,
}, orbOrbit)
local solarOrb = new("ImageLabel", {
	Name = "SolarEssenceOrb",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.05),
	Size = UDim2.fromScale(0.27, 0.27),
	BackgroundTransparency = 1,
	ScaleType = Enum.ScaleType.Fit,
	Active = false,
	ZIndex = 11,
}, orbOrbit)

EssenceVisuals.ApplyToImage(earthOrb, "Earth Essence")
EssenceVisuals.ApplyToImage(shadowOrb, "Shadow Essence")
EssenceVisuals.ApplyToImage(solarOrb, "Solar Essence", { Scale = 1.08 })

local banner = new("CanvasGroup", {
	Name = "StormArrivalBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.31),
	Size = UDim2.fromScale(0.64, 0.17),
	BackgroundColor3 = Color3.fromRGB(13, 18, 45),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Active = false,
	Visible = false,
	ZIndex = 12,
}, root)
corner(banner, UDim.new(0, 20))
local bannerStroke = stroke(banner, Color3.fromRGB(112, 202, 255), 2.3, 0.06)
local bannerGradient = new("UIGradient", { Rotation = 12 }, banner)
new("UISizeConstraint", {
	MinSize = Vector2.new(300, 90),
	MaxSize = Vector2.new(760, 168),
}, banner)
local bannerScale = new("UIScale", { Scale = 0.76 }, banner)

local bannerTopRule = new("Frame", {
	Name = "BannerChargeLine",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromScale(0.76, 0.025),
	BackgroundColor3 = Color3.fromRGB(112, 202, 255),
	BorderSizePixel = 0,
	ZIndex = 13,
}, banner)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.24, 0),
		NumberSequenceKeypoint.new(0.76, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, bannerTopRule)

local bannerTitle = new("TextLabel", {
	Name = "StormTitle",
	Position = UDim2.fromScale(0.13, 0.2),
	Size = UDim2.fromScale(0.74, 0.33),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "ESSENCE STORM",
	TextColor3 = Color3.fromRGB(236, 248, 255),
	TextScaled = true,
	TextStrokeColor3 = Color3.fromRGB(20, 8, 44),
	TextStrokeTransparency = 0.52,
	Active = false,
	ZIndex = 13,
}, banner)
new("UITextSizeConstraint", { MinTextSize = 17, MaxTextSize = 36 }, bannerTitle)

local bannerSubtitle = new("TextLabel", {
	Name = "StormSubtitle",
	Position = UDim2.fromScale(0.12, 0.56),
	Size = UDim2.fromScale(0.76, 0.2),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "THE VEIL IS RAINING ESSENCE",
	TextColor3 = Color3.fromRGB(170, 220, 255),
	TextScaled = true,
	Active = false,
	ZIndex = 13,
}, banner)
new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 16 }, bannerSubtitle)

local bannerHint = new("TextLabel", {
	Name = "StormHint",
	Position = UDim2.fromScale(0.12, 0.78),
	Size = UDim2.fromScale(0.76, 0.13),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "COLLECT THE FALLING ORBS  •  BONUS ESSENCE IS ACTIVE",
	TextColor3 = Color3.fromRGB(205, 205, 225),
	TextScaled = true,
	Active = false,
	ZIndex = 13,
}, banner)
new("UITextSizeConstraint", { MinTextSize = 7, MaxTextSize = 12 }, bannerHint)

local bannerEarth = new("ImageLabel", {
	Name = "EarthPreview",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.07, 0.5),
	Size = UDim2.fromScale(0.1, 0.46),
	BackgroundTransparency = 1,
	Image = ZonesConfig.EssenceOrbImages["Earth Essence"],
	ScaleType = Enum.ScaleType.Fit,
	Active = false,
	ZIndex = 14,
}, banner)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, bannerEarth)

local bannerShadow = new("ImageLabel", {
	Name = "ShadowPreview",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.93, 0.5),
	Size = UDim2.fromScale(0.1, 0.46),
	BackgroundTransparency = 1,
	Image = ZonesConfig.EssenceOrbImages["Shadow Essence"],
	ScaleType = Enum.ScaleType.Fit,
	Active = false,
	ZIndex = 14,
}, banner)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, bannerShadow)

local bannerSolar = new("ImageLabel", {
	Name = "SolarPreview",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.075),
	Size = UDim2.fromScale(0.065, 0.31),
	BackgroundTransparency = 1,
	ScaleType = Enum.ScaleType.Fit,
	Active = false,
	ZIndex = 14,
}, banner)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, bannerSolar)

EssenceVisuals.ApplyToImage(bannerEarth, "Earth Essence")
EssenceVisuals.ApplyToImage(bannerShadow, "Shadow Essence")
EssenceVisuals.ApplyToImage(bannerSolar, "Solar Essence", { Scale = 1.04 })

local normalPalette = {
	Primary = Color3.fromRGB(105, 207, 255),
	Secondary = Color3.fromRGB(190, 105, 255),
	Highlight = Color3.fromRGB(236, 248, 255),
	Deep = Color3.fromRGB(11, 18, 48),
	TintPeak = 0.925,
	Rain = {
		Color3.fromRGB(117, 232, 168),
		Color3.fromRGB(183, 118, 255),
		Color3.fromRGB(255, 184, 48),
	},
}

local goldenPalette = {
	Primary = Color3.fromRGB(255, 208, 62),
	Secondary = Color3.fromRGB(255, 132, 38),
	Highlight = Color3.fromRGB(255, 250, 194),
	Deep = Color3.fromRGB(50, 25, 5),
	TintPeak = 0.89,
	Rain = {
		Color3.fromRGB(255, 222, 80),
		Color3.fromRGB(255, 247, 188),
		Color3.fromRGB(255, 154, 45),
	},
}

local stormActive = false
local stormGolden = false
local stormToken = 0
local bannerToken = 0
local majorTweens = {}
local rainTweens = {}
local rainCursor = 0
local arrivalSound = Juice.FindSound("SFX/UI/UIPop")

local function cancelMajorTweens()
	for _, activeTween in ipairs(majorTweens) do
		activeTween:Cancel()
	end
	table.clear(majorTweens)
end

local function trackMajor(activeTween)
	table.insert(majorTweens, activeTween)
	return activeTween
end

local function stopRain()
	for streak, activeTween in pairs(rainTweens) do
		activeTween:Cancel()
		streak.BackgroundTransparency = 1
	end
	table.clear(rainTweens)
end

local function applyPalette(palette)
	tint.BackgroundColor3 = palette.Deep
	tintGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.Deep:Lerp(palette.Primary, 0.28)),
		ColorSequenceKeypoint.new(0.48, palette.Deep),
		ColorSequenceKeypoint.new(1, palette.Deep:Lerp(palette.Secondary, 0.2)),
	})
	topCloud.ImageColor3 = palette.Primary
	bottomHaze.ImageColor3 = palette.Secondary
	leftEdge.BackgroundColor3 = palette.Primary
	rightEdge.BackgroundColor3 = palette.Secondary
	leftEdgeGradient.Color = ColorSequence.new(palette.Primary, palette.Deep)
	rightEdgeGradient.Color = ColorSequence.new(palette.Secondary, palette.Deep)
	portalGlow.ImageColor3 = palette.Primary
	outerRing.ImageColor3 = palette.Primary
	innerRing.ImageColor3 = palette.Secondary:Lerp(palette.Highlight, 0.42)
	core.BackgroundColor3 = palette.Deep
	coreStroke.Color = palette.Highlight
	coreGradient.Color = ColorSequence.new(palette.Deep, palette.Secondary:Lerp(palette.Deep, 0.5))
	stormGlyph.TextColor3 = palette.Highlight
	banner.BackgroundColor3 = palette.Deep
	bannerStroke.Color = palette.Primary
	bannerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, palette.Deep:Lerp(palette.Primary, 0.2)),
		ColorSequenceKeypoint.new(0.52, palette.Deep),
		ColorSequenceKeypoint.new(1, palette.Deep:Lerp(palette.Secondary, 0.2)),
	})
	bannerTopRule.BackgroundColor3 = palette.Primary
	bannerTitle.TextColor3 = palette.Highlight
	bannerSubtitle.TextColor3 = palette.Primary:Lerp(palette.Highlight, 0.3)
end

local function showBanner(titleText, subtitleText, hintText, holdTime)
	bannerToken += 1
	local myBannerToken = bannerToken
	banner.Visible = true
	banner.GroupTransparency = 1
	bannerScale.Scale = 0.76
	banner.Position = UDim2.fromScale(0.5, 0.285)
	bannerTitle.Text = titleText
	bannerSubtitle.Text = subtitleText
	bannerHint.Text = hintText

	tween(banner, 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		GroupTransparency = 0,
		Position = UDim2.fromScale(0.5, 0.31),
	})
	tween(bannerScale, 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 })

	task.delay(holdTime or 2.25, function()
		if bannerToken ~= myBannerToken or not banner.Parent then
			return
		end
		local hideTween = tween(banner, 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
			GroupTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.285),
		})
		hideTween.Completed:Connect(function()
			if bannerToken == myBannerToken then
				banner.Visible = false
			end
		end)
	end)
end

local function spawnRainStreak(palette, token)
	rainCursor = (rainCursor % #rainStreaks) + 1
	local streak = rainStreaks[rainCursor]
	local priorTween = rainTweens[streak]
	if priorTween then
		priorTween:Cancel()
	end

	local startX = -0.06 + math.random() * 1.03
	local drift = 0.07 + math.random() * 0.08
	local duration = 0.58 + math.random() * 0.46
	streak.Position = UDim2.fromScale(startX, -0.18)
	streak.Size = UDim2.new(0, math.random(2, 4), 0.1 + math.random() * 0.1, 0)
	streak.BackgroundColor3 = palette.Rain[(rainCursor % #palette.Rain) + 1]
	streak.BackgroundTransparency = 0.12 + math.random() * 0.18
	streak.Rotation = -8 - math.random(0, 6)

	local activeTween = tween(streak, duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, {
		Position = UDim2.fromScale(startX + drift, 1.2),
		BackgroundTransparency = 0.86,
	})
	rainTweens[streak] = activeTween
	activeTween.Completed:Connect(function()
		if rainTweens[streak] == activeTween then
			rainTweens[streak] = nil
			streak.BackgroundTransparency = 1
		end
		if stormToken ~= token then
			streak.BackgroundTransparency = 1
		end
	end)
end

local function spawnLightning(palette, token)
	if stormToken ~= token or not stormActive then
		return
	end

	local boltHolder = new("Frame", {
		Name = "LightningStrike",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = 4,
	}, root)
	local x = 0.12 + math.random() * 0.76
	local y = -0.03
	for segmentIndex = 1, 5 do
		local segmentHeight = 0.075 + math.random() * 0.045
		local rotation = math.random(-24, 24)
		local segment = new("Frame", {
			Name = "BoltSegment" .. segmentIndex,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.new(0, stormGolden and 5 or 3, segmentHeight, 0),
			BackgroundColor3 = palette.Highlight,
			BackgroundTransparency = 0.02,
			BorderSizePixel = 0,
			Rotation = rotation,
			Active = false,
			ZIndex = 5,
		}, boltHolder)
		local glow = new("Frame", {
			Name = "BoltGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, stormGolden and 18 or 12, 1, 0),
			BackgroundColor3 = palette.Primary,
			BackgroundTransparency = 0.68,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 4,
		}, segment)
		corner(glow)
		x += (math.random() - 0.5) * 0.065
		y += segmentHeight * 0.78
	end

	Debris:AddItem(boltHolder, 0.52)
	Juice.Flash(root, {
		Color = palette.Highlight,
		Peak = stormGolden and 0.88 or 0.93,
		Duration = 0.22,
		ZIndex = 6,
	})
	task.delay(0.08, function()
		if not boltHolder.Parent then
			return
		end
		for _, descendant in ipairs(boltHolder:GetDescendants()) do
			if descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
				tween(descendant, 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
					BackgroundTransparency = 1,
				})
			end
		end
	end)
end

local function runAtmosphere(token, palette)
	task.spawn(function()
		while stormActive and stormToken == token do
			local batchCount = stormGolden and 4 or 3
			for _ = 1, batchCount do
				spawnRainStreak(palette, token)
			end

			if math.random() < (stormGolden and 0.34 or 0.22) then
				spawnLightning(palette, token)
			end

			if math.random() < 0.22 then
				Juice.Ring(root, UDim2.fromScale(0.5, 0.12), {
					Color = palette.Primary,
					StartSize = 55,
					EndSize = stormGolden and 300 or 230,
					Duration = 0.72,
					Thickness = stormGolden and 3 or 2,
					ZIndex = 7,
				})
			end

			task.wait(stormGolden and 0.3 or 0.42)
		end
	end)
end

local function surgeExistingStorm(isGolden)
	stormGolden = isGolden
	local palette = isGolden and goldenPalette or normalPalette
	applyPalette(palette)
	showBanner(
		isGolden and "✦ GOLDEN STORM SURGE ✦" or "⚡ STORM SURGE ⚡",
		"THE ESSENCE RAIN HAS BEEN EXTENDED",
		"MORE TIME  •  MORE ORBS  •  KEEP COLLECTING",
		1.75
	)
	Juice.Flash(root, {
		Color = palette.Highlight,
		Peak = isGolden and 0.72 or 0.82,
		Duration = 0.4,
		ZIndex = 18,
	})
	Juice.Burst(root, UDim2.fromScale(0.5, 0.2), {
		Count = isGolden and 24 or 17,
		Colors = { palette.Primary, palette.Secondary, palette.Highlight },
		Distance = 220,
		Duration = 0.8,
		Size = { 4, 10 },
		ZIndex = 17,
	})
	Juice.PlaySound(arrivalSound, { Pitch = isGolden and 1.42 or 1.05, Volume = 0.55 })
end

local function beginStorm(isGolden)
	if stormActive then
		surgeExistingStorm(isGolden)
		return
	end

	stormActive = true
	stormGolden = isGolden
	stormToken += 1
	local token = stormToken
	local palette = isGolden and goldenPalette or normalPalette

	cancelMajorTweens()
	stopRain()
	applyPalette(palette)

	root.Visible = true
	tint.BackgroundTransparency = 1
	topCloud.Position = UDim2.fromScale(0.5, -0.38)
	topCloud.ImageTransparency = 1
	bottomHaze.Position = UDim2.fromScale(0.5, 1.15)
	bottomHaze.ImageTransparency = 1
	leftEdge.BackgroundTransparency = 1
	rightEdge.BackgroundTransparency = 1
	portalRoot.Position = UDim2.fromScale(0.5, -0.12)
	portalScale.Scale = 0.35
	portalGlow.ImageTransparency = 1
	outerRing.ImageTransparency = 1
	innerRing.ImageTransparency = 1
	outerRing.Rotation = -30
	innerRing.Rotation = 30
	orbOrbit.Rotation = 0

	trackMajor(tween(tint, 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		BackgroundTransparency = palette.TintPeak,
	}))
	trackMajor(tween(topCloud, 0.72, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, {
		Position = UDim2.fromScale(0.5, -0.24),
		ImageTransparency = isGolden and 0.62 or 0.72,
	}))
	trackMajor(tween(bottomHaze, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		Position = UDim2.fromScale(0.5, 1.08),
		ImageTransparency = isGolden and 0.76 or 0.84,
	}))
	trackMajor(tween(leftEdge, 0.72, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		BackgroundTransparency = isGolden and 0.91 or 0.94,
	}))
	trackMajor(tween(rightEdge, 0.72, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		BackgroundTransparency = isGolden and 0.91 or 0.94,
	}))
	trackMajor(tween(portalRoot, 0.66, Enum.EasingStyle.Back, Enum.EasingDirection.Out, {
		Position = UDim2.fromScale(0.5, -0.015),
	}))
	trackMajor(tween(portalScale, 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out, { Scale = 1 }))
	trackMajor(tween(portalGlow, 0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		ImageTransparency = isGolden and 0.24 or 0.4,
	}))
	trackMajor(tween(outerRing, 0.44, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		ImageTransparency = 0.08,
	}))
	trackMajor(tween(innerRing, 0.44, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, {
		ImageTransparency = 0.22,
	}))

	-- These three inexpensive rotations are the only persistent tweens and
	-- are canceled immediately by endStorm/cancelMajorTweens.
	trackMajor(TweenService:Create(outerRing, TweenInfo.new(7.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		Rotation = 330,
	}))
	majorTweens[#majorTweens]:Play()
	trackMajor(TweenService:Create(innerRing, TweenInfo.new(5.8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		Rotation = -330,
	}))
	majorTweens[#majorTweens]:Play()
	trackMajor(TweenService:Create(orbOrbit, TweenInfo.new(isGolden and 3.8 or 5.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
		Rotation = 360,
	}))
	majorTweens[#majorTweens]:Play()

	showBanner(
		isGolden and "✦ GOLDEN ESSENCE STORM ✦" or "⚡ ESSENCE STORM ⚡",
		isGolden and "THE SKY HAS TURNED TO GOLD" or "THE VEIL IS RAINING ESSENCE",
		isGolden and "MASSIVE PAYOUTS  •  COLLECT EVERYTHING" or "EARTH + SHADOW + SOLAR  •  COLLECT THE RAIN",
		2.45
	)

	Juice.Flash(root, {
		Color = palette.Highlight,
		Peak = isGolden and 0.5 or 0.68,
		Duration = 0.68,
		ZIndex = 18,
	})
	Juice.Ring(root, UDim2.fromScale(0.5, 0.13), {
		Color = palette.Primary,
		StartSize = 70,
		EndSize = isGolden and 480 or 380,
		Duration = 1,
		Thickness = isGolden and 5 or 3,
		ZIndex = 16,
	})
	Juice.Burst(root, UDim2.fromScale(0.5, 0.2), {
		Count = isGolden and 32 or 22,
		Colors = { palette.Primary, palette.Secondary, palette.Highlight },
		Distance = isGolden and 320 or 260,
		Duration = 1.05,
		Size = { 4, isGolden and 14 or 11 },
		ZIndex = 17,
	})
	Juice.PlaySound(arrivalSound, {
		Pitch = isGolden and 1.5 or 0.76,
		Volume = isGolden and 0.72 or 0.62,
	})

	task.delay(0.22, function()
		if stormToken == token then
			spawnLightning(palette, token)
		end
	end)
	runAtmosphere(token, palette)
end

local function endStorm()
	if not stormActive then
		return
	end

	stormActive = false
	stormToken += 1
	local token = stormToken
	local palette = stormGolden and goldenPalette or normalPalette
	cancelMajorTweens()
	stopRain()

	showBanner(
		"THE STORM SUBSIDES",
		"THE VEIL HAS GROWN QUIET",
		"THE NEXT ESSENCE STORM IS ALREADY GATHERING",
		1.05
	)
	Juice.Ring(root, UDim2.fromScale(0.5, 0.14), {
		Color = palette.Secondary,
		StartSize = 160,
		EndSize = 420,
		Duration = 0.8,
		Thickness = 2,
		ZIndex = 16,
	})
	Juice.PlaySound(arrivalSound, { Pitch = 0.62, Volume = 0.38 })

	tween(tint, 1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
	tween(topCloud, 1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Position = UDim2.fromScale(0.5, -0.38),
		ImageTransparency = 1,
	})
	tween(bottomHaze, 0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Position = UDim2.fromScale(0.5, 1.15),
		ImageTransparency = 1,
	})
	tween(leftEdge, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
	tween(rightEdge, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { BackgroundTransparency = 1 })
	tween(portalScale, 0.68, Enum.EasingStyle.Back, Enum.EasingDirection.In, { Scale = 0.25 })
	tween(portalRoot, 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In, {
		Position = UDim2.fromScale(0.5, -0.15),
	})
	tween(portalGlow, 0.62, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { ImageTransparency = 1 })
	tween(outerRing, 0.62, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { ImageTransparency = 1 })
	tween(innerRing, 0.62, Enum.EasingStyle.Quad, Enum.EasingDirection.In, { ImageTransparency = 1 })

	task.delay(1.45, function()
		if stormToken == token and not stormActive then
			root.Visible = false
			stormGolden = false
		end
	end)
end

EssenceStormEvent.OnClientEvent:Connect(function(action, payload)
	if action == "StormStart" then
		payload = payload or {}
		beginStorm(payload.IsGolden == true)
	elseif action == "StormEnd" then
		endStorm()
	end
end)

-- If replication beat this LocalScript to the start signal (for example
-- after a very fast reconnect), recover the atmosphere from authoritative
-- player attributes instead of leaving an active storm visually silent.
task.defer(function()
	if player:GetAttribute("StormActive") == true and not stormActive then
		beginStorm(player:GetAttribute("StormIsGolden") == true)
	end
end)

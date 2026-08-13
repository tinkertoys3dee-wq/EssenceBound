--[[
	GroupRewardPrompt (LocalScript -> StarterPlayerScripts)
	=======================================================
	A polished, responsive community-reward panel for non-members. The
	client only presents benefits and asks for a recheck; GroupRewardService
	verifies membership server-side and owns the GroupMember attribute.

	Every number shown here comes from GroupRewardConfig, the same module
	used by the gameplay hooks. The panel therefore cannot drift into
	advertising a benefit that the player does not actually receive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("GroupRewardConfig"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

if not GroupRewardConfig.IsEnabled() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local checkMembership = ReplicatedStorage:WaitForChild("CheckGroupMembership")

-- =========================================================================
-- THEME + LAYOUT
-- =========================================================================

local THEME = {
	Void = Color3.fromRGB(10, 7, 19),
	Background = Color3.fromRGB(24, 15, 39),
	Surface = Color3.fromRGB(39, 25, 58),
	SurfaceRaised = Color3.fromRGB(50, 32, 70),
	SurfaceHover = Color3.fromRGB(62, 40, 84),
	Accent = Color3.fromRGB(255, 172, 66),
	AccentLight = Color3.fromRGB(255, 222, 145),
	Essence = Color3.fromRGB(76, 226, 144),
	Crit = Color3.fromRGB(255, 204, 84),
	Offline = Color3.fromRGB(107, 177, 255),
	Danger = Color3.fromRGB(255, 113, 123),
	Muted = Color3.fromRGB(184, 174, 202),
	Dim = Color3.fromRGB(125, 113, 145),
	White = Color3.fromRGB(255, 255, 255),
}

local LAYOUT = {
	-- Sits beside the lower progression rail, below MainGui's authored nav.
	-- This keeps it clear of both the third progression shortcut and the
	-- larger bottom-corner Wheel button.
	ButtonPosition = UDim2.fromScale(0.82, 0.87),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.044, 0.062),
	CardSize = UDim2.fromScale(0.54, 0.72),
}

local ESSENCE_PERCENT = math.floor((GroupRewardConfig.BonusMultiplier - 1) * 100 + 0.5)
local CRIT_PERCENT = math.floor(GroupRewardConfig.CritChanceBonus * 100 + 0.5)
local OFFLINE_PERCENT = math.floor((GroupRewardConfig.OfflineEarningsMultiplier - 1) * 100 + 0.5)

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
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 12) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or THEME.Accent,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	}, parent)
end

local function tween(instance, info, props)
	return TweenService:Create(instance, info, props)
end

local function constrainText(label, minSize, maxSize)
	return new("UITextSizeConstraint", {
		MinTextSize = minSize or 8,
		MaxTextSize = maxSize or 18,
	}, label)
end

local function applyButtonFeel(target, hoverScale, pressedScale, hoverColor)
	local baseColor = target.BackgroundColor3
	local scale = new("UIScale", { Scale = 1 }, target)
	target:SetAttribute("JuiceFeelApplied", true)

	target.MouseEnter:Connect(function()
		tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = hoverScale or 1.035,
		}):Play()
		if hoverColor and target.BackgroundTransparency < 1 then
			tween(target, TweenInfo.new(0.14), { BackgroundColor3 = hoverColor }):Play()
		end
	end)

	target.MouseLeave:Connect(function()
		tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
		if hoverColor and target.BackgroundTransparency < 1 then
			tween(target, TweenInfo.new(0.14), { BackgroundColor3 = baseColor }):Play()
		end
	end)

	target.MouseButton1Down:Connect(function()
		tween(scale, TweenInfo.new(0.06), { Scale = pressedScale or 0.97 }):Play()
	end)

	target.MouseButton1Up:Connect(function()
		tween(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = hoverScale or 1.035,
		}):Play()
	end)
end

-- =========================================================================
-- ROOT + SHORTCUT
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "GroupRewardPrompt",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 61,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local holder = new("Frame", {
	Name = "ButtonHolder",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundTransparency = 1,
	ZIndex = 50,
}, screenGui)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, holder)

local shortcutGlow = new("Frame", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.24, 1.24),
	BackgroundColor3 = THEME.Accent,
	BackgroundTransparency = 0.82,
	ZIndex = 50,
}, holder)
corner(shortcutGlow, UDim.new(0.3, 0))

local button = new("TextButton", {
	Name = "Button",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Surface,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 51,
}, holder)
corner(button, UDim.new(0.28, 0))
stroke(button, THEME.Accent, 2.5, 0.05)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 42, 91)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(31, 20, 49)),
	}),
	Rotation = 135,
}, button)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 0.58),
	Position = UDim2.fromScale(0, 0.05),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✦",
	TextColor3 = THEME.AccentLight,
	TextScaled = true,
	TextStrokeColor3 = THEME.Accent,
	TextStrokeTransparency = 0.65,
	ZIndex = 52,
}, button)

local caption = new("TextLabel", {
	Name = "Caption",
	Size = UDim2.fromScale(0.9, 0.25),
	Position = UDim2.fromScale(0.05, 0.69),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "+" .. tostring(ESSENCE_PERCENT) .. "%",
	TextColor3 = THEME.Essence,
	TextScaled = true,
	ZIndex = 52,
}, button)
constrainText(caption, 7, 13)

local freeBadge = new("Frame", {
	Name = "FreeBadge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1.08, -0.08),
	Size = UDim2.fromScale(0.48, 0.25),
	BackgroundColor3 = THEME.Essence,
	ZIndex = 54,
}, holder)
corner(freeBadge, UDim.new(1, 0))
stroke(freeBadge, THEME.White, 1.2, 0.18)
local freeLabel = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "FREE",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 55,
}, freeBadge)
constrainText(freeLabel, 6, 10)

applyButtonFeel(button, 1.08, 0.93)

-- =========================================================================
-- POPUP SHELL
-- =========================================================================

local popupRoot = new("Frame", {
	Name = "PopupRoot",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 99,
}, screenGui)

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Void,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 100,
}, popupRoot)
backdrop:SetAttribute("PresentationModal", true)

local outerHalo = new("Frame", {
	Name = "OuterHalo",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.59, 0.8),
	BackgroundColor3 = THEME.Accent,
	BackgroundTransparency = 0.93,
	ZIndex = 101,
}, popupRoot)
new("UISizeConstraint", { MinSize = Vector2.new(280, 310), MaxSize = Vector2.new(760, 675) }, outerHalo)
corner(outerHalo, UDim.new(0, 32))

local cardShadow = new("Frame", {
	Name = "CardShadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 10, 0.5, 14),
	Size = LAYOUT.CardSize,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.34,
	ZIndex = 102,
}, popupRoot)
new("UISizeConstraint", { MinSize = Vector2.new(270, 300), MaxSize = Vector2.new(700, 610) }, cardShadow)
corner(cardShadow, UDim.new(0, 26))
local shadowScale = new("UIScale", { Scale = 0.82 }, cardShadow)

local card = new("Frame", {
	Name = "RewardCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = LAYOUT.CardSize,
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 103,
}, popupRoot)
new("UISizeConstraint", { MinSize = Vector2.new(270, 300), MaxSize = Vector2.new(700, 610) }, card)
corner(card, UDim.new(0, 26))
local cardStroke = stroke(card, THEME.Accent, 2.5, 0.05)
local cardScale = new("UIScale", { Scale = 0.82 }, card)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(48, 28, 68)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(29, 18, 45)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 11, 29)),
	}),
	Rotation = 118,
}, card)

local accentBar = new("Frame", {
	Name = "AccentBar",
	Size = UDim2.fromScale(1, 0.014),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 105,
}, card)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.Essence),
		ColorSequenceKeypoint.new(0.5, THEME.AccentLight),
		ColorSequenceKeypoint.new(1, THEME.Crit),
	}),
}, accentBar)

local headerWash = new("Frame", {
	Name = "HeaderWash",
	Size = UDim2.fromScale(1, 0.29),
	BackgroundColor3 = THEME.SurfaceRaised,
	BackgroundTransparency = 0.18,
	BorderSizePixel = 0,
	ZIndex = 104,
}, card)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(71, 39, 94)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 22, 55)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.45),
	}),
	Rotation = 12,
}, headerWash)

-- Static constellation marks provide detail without assets or per-frame work.
for index, mote in ipairs({
	{ 0.06, 0.08, 5, THEME.Accent },
	{ 0.84, 0.07, 4, THEME.Essence },
	{ 0.92, 0.21, 6, THEME.AccentLight },
	{ 0.72, 0.17, 3, THEME.Offline },
}) do
	local dot = new("Frame", {
		Name = "Mote" .. tostring(index),
		Position = UDim2.fromScale(mote[1], mote[2]),
		Size = UDim2.fromOffset(mote[3], mote[3]),
		BackgroundColor3 = mote[4],
		BackgroundTransparency = 0.16,
		ZIndex = 106,
	}, card)
	corner(dot, UDim.new(1, 0))
end

local crest = new("Frame", {
	Name = "Crest",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.055, 0.145),
	Size = UDim2.fromScale(0.115, 0.13),
	BackgroundColor3 = THEME.SurfaceRaised,
	ZIndex = 107,
}, card)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, crest)
corner(crest, UDim.new(0.28, 0))
stroke(crest, THEME.AccentLight, 2, 0.08)
new("UIGradient", {
	Color = ColorSequence.new(THEME.Accent, Color3.fromRGB(121, 70, 160)),
	Rotation = 45,
}, crest)
local crestLabel = new("ImageLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = "rbxassetid://127976500372870",
	ZIndex = 108,
}, crest)
corner(crestLabel, UDim.new(0.28, 0))
local eyebrow = new("TextLabel", {
	Name = "Eyebrow",
	Position = UDim2.fromScale(0.195, 0.047),
	Size = UDim2.fromScale(0.63, 0.042),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = string.upper(GroupRewardConfig.GroupName) .. "  •  MEMBER REWARD",
	TextColor3 = THEME.AccentLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 107,
}, card)
constrainText(eyebrow, 8, 13)

local title = new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.195, 0.091),
	Size = UDim2.fromScale(0.66, 0.075),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "POWER IN NUMBERS",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 107,
}, card)
constrainText(title, 15, 28)

local subtitle = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.195, 0.17),
	Size = UDim2.fromScale(0.67, 0.055),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Join the community. Keep every bonus forever.",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 107,
}, card)
constrainText(subtitle, 8, 14)

local permanentPill = new("Frame", {
	Name = "PermanentPill",
	Position = UDim2.fromScale(0.195, 0.231),
	Size = UDim2.fromScale(0.31, 0.038),
	BackgroundColor3 = Color3.fromRGB(31, 92, 66),
	ZIndex = 107,
}, card)
corner(permanentPill, UDim.new(1, 0))
stroke(permanentPill, THEME.Essence, 1, 0.35)
local permanentLabel = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "✓  FREE  •  PERMANENT",
	TextColor3 = THEME.Essence,
	TextScaled = true,
	ZIndex = 108,
}, permanentPill)
constrainText(permanentLabel, 7, 11)

local topCloseButton = new("TextButton", {
	Name = "TopCloseButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.965, 0.035),
	Size = UDim2.fromOffset(34, 34),
	BackgroundColor3 = THEME.Surface,
	BackgroundTransparency = 0.16,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextColor3 = THEME.Muted,
	TextSize = 23,
	ZIndex = 110,
}, card)
corner(topCloseButton, UDim.new(1, 0))
stroke(topCloseButton, THEME.Dim, 1, 0.5)

new("Frame", {
	Name = "HeaderDivider",
	Position = UDim2.fromScale(0.055, 0.289),
	Size = UDim2.fromScale(0.89, 0.0025),
	BackgroundColor3 = THEME.Accent,
	BackgroundTransparency = 0.58,
	BorderSizePixel = 0,
	ZIndex = 106,
}, card)

-- =========================================================================
-- BENEFIT CARDS
-- =========================================================================

local sectionHeading = new("TextLabel", {
	Name = "SectionHeading",
	Position = UDim2.fromScale(0.055, 0.315),
	Size = UDim2.fromScale(0.5, 0.042),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "MEMBER BENEFITS",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 106,
}, card)
constrainText(sectionHeading, 10, 16)

local sectionSub = new("TextLabel", {
	Name = "SectionSub",
	Position = UDim2.fromScale(0.055, 0.354),
	Size = UDim2.fromScale(0.89, 0.035),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "All three stack with your upgrades and passes.",
	TextColor3 = THEME.Dim,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 106,
}, card)
constrainText(sectionSub, 8, 12)

local benefitGrid = new("Frame", {
	Name = "BenefitGrid",
	Position = UDim2.fromScale(0.055, 0.405),
	Size = UDim2.fromScale(0.89, 0.26),
	BackgroundTransparency = 1,
	ZIndex = 106,
}, card)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0.018, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, benefitGrid)

local function addBenefitCard(order, symbol, valueText, labelText, detailText, color)
	local benefit = new("Frame", {
		Name = labelText:gsub("%s+", "") .. "Benefit",
		Size = UDim2.fromScale(0.321, 1),
		BackgroundColor3 = THEME.Surface,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ZIndex = 107,
	}, benefitGrid)
	corner(benefit, UDim.new(0, 14))
	stroke(benefit, color, 1.5, 0.34)
	new("UIGradient", {
		Color = ColorSequence.new(THEME.SurfaceRaised, THEME.Surface),
		Rotation = 90,
	}, benefit)

	local topLine = new("Frame", {
		Name = "TopLine",
		Size = UDim2.fromScale(1, 0.035),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = 108,
	}, benefit)
	corner(topLine, UDim.new(1, 0))

	local iconBadge = new("Frame", {
		Name = "IconBadge",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.085),
		Size = UDim2.fromScale(0.31, 0.29),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.82,
		ZIndex = 108,
	}, benefit)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, iconBadge)
	corner(iconBadge, UDim.new(1, 0))
	stroke(iconBadge, color, 1.5, 0.22)
	local icon = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = symbol,
		TextColor3 = color,
		TextScaled = true,
		ZIndex = 109,
	}, iconBadge)
	constrainText(icon, 12, 23)

	local value = new("TextLabel", {
		Name = "Value",
		Position = UDim2.fromScale(0.07, 0.405),
		Size = UDim2.fromScale(0.86, 0.2),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = valueText,
		TextColor3 = color,
		TextScaled = true,
		ZIndex = 108,
	}, benefit)
	constrainText(value, 12, 24)

	local label = new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.07, 0.61),
		Size = UDim2.fromScale(0.86, 0.13),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = labelText,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 108,
	}, benefit)
	constrainText(label, 7, 13)

	local detail = new("TextLabel", {
		Name = "Detail",
		Position = UDim2.fromScale(0.07, 0.765),
		Size = UDim2.fromScale(0.86, 0.13),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = detailText,
		TextColor3 = THEME.Muted,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 108,
	}, benefit)
	constrainText(detail, 6, 11)

	return benefit
end

addBenefitCard(1, "◆", "+" .. tostring(ESSENCE_PERCENT) .. "%", "ESSENCE", "Every reward", THEME.Essence)
addBenefitCard(2, "✦", "+" .. tostring(CRIT_PERCENT) .. "%", "CRIT CHANCE", "Stacks freely", THEME.Crit)
addBenefitCard(3, "◈", "+" .. tostring(OFFLINE_PERCENT) .. "%", "OFFLINE", "Harvest boost", THEME.Offline)

new("Frame", {
	Name = "FooterDivider",
	Position = UDim2.fromScale(0.055, 0.698),
	Size = UDim2.fromScale(0.89, 0.0025),
	BackgroundColor3 = THEME.Dim,
	BackgroundTransparency = 0.62,
	BorderSizePixel = 0,
	ZIndex = 106,
}, card)

-- =========================================================================
-- ACTIONS
-- =========================================================================

local joinButton = new("TextButton", {
	Name = "JoinButton",
	Position = UDim2.fromScale(0.055, 0.73),
	Size = UDim2.fromScale(0.89, 0.105),
	BackgroundColor3 = THEME.Accent,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "JOIN " .. string.upper(GroupRewardConfig.GroupName) .. "   ↗",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 107,
}, card)
corner(joinButton, UDim.new(0, 13))
stroke(joinButton, THEME.AccentLight, 1.5, 0.08)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(255, 215, 115), Color3.fromRGB(246, 139, 65)),
	Rotation = 8,
}, joinButton)
constrainText(joinButton, 11, 19)

local verifyButton = new("TextButton", {
	Name = "VerifyButton",
	Position = UDim2.fromScale(0.055, 0.858),
	Size = UDim2.fromScale(0.58, 0.065),
	BackgroundColor3 = THEME.SurfaceRaised,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "✓  I'VE JOINED — VERIFY",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 107,
}, card)
corner(verifyButton, UDim.new(0, 10))
stroke(verifyButton, THEME.Dim, 1, 0.34)
constrainText(verifyButton, 8, 14)

local closeButton = new("TextButton", {
	Name = "CloseButton",
	Position = UDim2.fromScale(0.67, 0.858),
	Size = UDim2.fromScale(0.275, 0.065),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "MAYBE LATER",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 107,
}, card)
constrainText(closeButton, 8, 13)

local statusLabel = new("TextLabel", {
	Name = "Status",
	Position = UDim2.fromScale(0.055, 0.942),
	Size = UDim2.fromScale(0.89, 0.03),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "SERVER-VERIFIED  •  BENEFITS APPLY INSTANTLY",
	TextColor3 = THEME.Dim,
	TextScaled = true,
	ZIndex = 107,
}, card)
constrainText(statusLabel, 7, 11)

applyButtonFeel(joinButton, 1.018, 0.975, Color3.fromRGB(255, 183, 73))
applyButtonFeel(verifyButton, 1.018, 0.975, THEME.SurfaceHover)
applyButtonFeel(topCloseButton, 1.08, 0.9, THEME.SurfaceHover)

-- The soft glows breathe with TweenService rather than a render-step loop.
tween(shortcutGlow, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.92,
}):Play()
tween(outerHalo, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	BackgroundTransparency = 0.975,
}):Play()

-- =========================================================================
-- INTERACTION + MEMBERSHIP STATE
-- =========================================================================

local animationId = 0
local isVerifying = false
local celebratingSuccess = false

local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color or THEME.Dim
end

local function showPopup()
	if player:GetAttribute("GroupMember") == true or popupRoot.Visible then
		return
	end
	if not PresentationCoordinator.CanOpenModal() then
		return
	end

	animationId += 1
	popupRoot.Visible = true
	backdrop.BackgroundTransparency = 1
	cardScale.Scale = 0.82
	shadowScale.Scale = 0.82
	cardStroke.Transparency = 0.55

	if not isVerifying then
		verifyButton.Text = "✓  I'VE JOINED — VERIFY"
		setStatus("SERVER-VERIFIED  •  BENEFITS APPLY INSTANTLY", THEME.Dim)
	end

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.18 }):Play()
	tween(cardScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	tween(shadowScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	tween(cardStroke, TweenInfo.new(0.3), { Transparency = 0.05 }):Play()
end

local function hidePopup()
	if not popupRoot.Visible then
		return
	end

	animationId += 1
	local thisAnimation = animationId
	tween(backdrop, TweenInfo.new(0.16), { BackgroundTransparency = 1 }):Play()
	tween(cardScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()
	tween(shadowScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 }):Play()

	task.delay(0.17, function()
		if animationId == thisAnimation then
			popupRoot.Visible = false
		end
	end)
end

button.Activated:Connect(showPopup)
backdrop.Activated:Connect(hidePopup)
closeButton.Activated:Connect(hidePopup)
topCloseButton.Activated:Connect(hidePopup)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and popupRoot.Visible and input.KeyCode == Enum.KeyCode.Escape then
		hidePopup()
	end
end)

joinButton.Activated:Connect(function()
	local ok = pcall(function()
		GuiService:OpenBrowserWindowAsync(GroupRewardConfig.GroupUrl:format(GroupRewardConfig.GroupId))
	end)

	if ok then
		setStatus("GROUP OPENED  •  RETURN HERE AND PRESS VERIFY", THEME.AccentLight)
		NotificationService.Info("Join the group, return to EssenceBound, then press Verify.", {
			Title = "Group Page Opened",
			Icon = "◆",
			Key = "group-page-opened",
		})
	else
		setStatus("COULDN'T OPEN THE GROUP ON THIS DEVICE", THEME.Danger)
		NotificationService.Error("Roblox could not open the group page on this device.", {
			Title = "Group Page Unavailable",
			Key = "group-page-error",
		})
	end
end)

verifyButton.Activated:Connect(function()
	if isVerifying then
		return
	end

	isVerifying = true
	verifyButton.Text = "CHECKING MEMBERSHIP..."
	setStatus("ASKING ROBLOX TO CONFIRM YOUR MEMBERSHIP", THEME.AccentLight)

	local ok, isMember, reason = pcall(function()
		return checkMembership:InvokeServer()
	end)

	if ok and isMember then
		celebratingSuccess = true
		isVerifying = false
		holder.Visible = false
		verifyButton.Text = "✓  VERIFIED — BONUSES ACTIVE"
		verifyButton.BackgroundColor3 = Color3.fromRGB(31, 105, 72)
		setStatus("WELCOME IN  •  EVERY MEMBER BENEFIT IS NOW LIVE", THEME.Essence)
		NotificationService.Success(("Your group bonuses are live: +%d%% essence, +%d%% critical chance, and +%d%% offline earnings."):format(
			ESSENCE_PERCENT,
			CRIT_PERCENT,
			OFFLINE_PERCENT
		), {
			Title = "Community Bonuses Activated",
			Icon = "✓",
			Duration = 5,
			Key = "group-verified",
		})

		task.delay(1.6, function()
			celebratingSuccess = false
			hidePopup()
		end)
	else
		isVerifying = false
		if ok and reason == "Cooldown" then
			verifyButton.Text = "WAIT A MOMENT"
			setStatus("VERIFICATION IS COOLING DOWN", THEME.AccentLight)
			NotificationService.Info("Please wait a few seconds before checking membership again.", {
				Title = "Verification Cooling Down",
				Icon = "⌛",
				Key = "group-check-cooldown",
			})
		elseif ok and reason ~= "Unavailable" then
			verifyButton.Text = "NOT FOUND — TRY AGAIN"
			setStatus("JOIN FIRST, THEN GIVE ROBLOX A MOMENT TO UPDATE", THEME.Danger)
			NotificationService.Warning("Membership was not found yet. Join the group, wait a moment, then verify again.", {
				Title = "Membership Not Found",
				Icon = "⌛",
				Key = "group-not-found",
			})
		else
			verifyButton.Text = "CHECK FAILED — TRY AGAIN"
			setStatus("ROBLOX COULD NOT VERIFY MEMBERSHIP", THEME.Danger)
			NotificationService.Error("The membership check could not reach Roblox. Try again in a moment.", {
				Title = "Verification Interrupted",
				Key = "group-check-error",
			})
		end
		task.delay(2.4, function()
			if verifyButton.Parent and player:GetAttribute("GroupMember") ~= true then
				verifyButton.Text = "✓  I'VE JOINED — VERIFY"
				verifyButton.BackgroundColor3 = THEME.SurfaceRaised
				setStatus("SERVER-VERIFIED  •  BENEFITS APPLY INSTANTLY", THEME.Dim)
			end
		end)
	end
end)

-- Nothing needs to remain visible after membership is verified; every
-- benefit is already read from the server-owned GroupMember attribute.
local function waitForAttribute(name, timeoutSeconds)
	local deadline = os.clock() + timeoutSeconds
	while player:GetAttribute(name) == nil and os.clock() < deadline do
		task.wait(0.25)
	end
	return player:GetAttribute(name)
end

holder.Visible = false

task.spawn(function()
	local isMember = waitForAttribute("GroupMember", 15) == true
	holder.Visible = not isMember
	-- Keep the FREE shortcut discoverable, but never force this promotional
	-- panel over a new player's first five seconds. It was one of the startup
	-- popups competing with Tutorial/Offline/Daily; opening it is now an
	-- explicit player choice and still uses the same server verification.
end)

player:GetAttributeChangedSignal("GroupMember"):Connect(function()
	local isMember = player:GetAttribute("GroupMember") == true
	holder.Visible = not isMember
	if isMember and not isVerifying and not celebratingSuccess then
		hidePopup()
	end
end)

--[[
	GroupRewardPrompt (LocalScript -> StarterPlayerScripts)
	========================================================
	A compact reminder button and a one-time join popup for non-members.
	Membership itself is granted server-side by
	GroupRewardService; this script only ever asks -- see EssenceMultiplier
	for where the bonus is actually applied.

	The call to action hands off to Roblox's own community page via
	GuiService:OpenBrowserWindowAsync; the follow-up button asks the server
	to verify membership again so the reward can activate immediately.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("GroupRewardConfig"))

if not GroupRewardConfig.IsEnabled() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local checkMembership = ReplicatedStorage:WaitForChild("CheckGroupMembership")

-- =========================================================================
-- THEME + LAYOUT (matches the rest of the right-edge button column)
-- =========================================================================

local THEME = {
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	Muted           = Color3.fromRGB(190, 181, 205),
	Overlay         = Color3.fromRGB(8, 4, 14),
	White           = Color3.fromRGB(255, 255, 255),
}

local LAYOUT = {
	-- Continues the RebirthShop (0.213) / Sanctum (0.295) / Leaderboard
	-- (0.377) / Achievements (0.459) column at the same x=0.952, but
	-- skips past ProgressionHud's Daily/Quest/Codes stack, which now
	-- occupies ~0.51-0.75 after being moved off this same column (see
	-- ProgressionHud.client.luau's LAYOUT comment) -- 0.8 keeps a clear
	-- gap below that stack instead of continuing the 0.082 stride
	-- straight into it. (x=0.895 used to collide with MainGui.Right.
	-- Holder's own nav bar -- see that file's LAYOUT comment.)
	ButtonPosition = UDim2.fromScale(0.952, 0.8),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.044, 0.062),
}

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

local function stroke(parent, color, thickness)
	return new("UIStroke", { Color = color or THEME.Accent, Thickness = thickness or 2.5 }, parent)
end

-- =========================================================================
-- BUILD
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

local button = new("TextButton", {
	Name = "Button",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BackgroundLight,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 51,
}, holder)
corner(button, UDim.new(0.28, 0))
stroke(button, THEME.Accent, 2.5)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 0.62),
	Position = UDim2.fromScale(0, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "👥",
	TextScaled = true,
	ZIndex = 52,
}, button)

local caption = new("TextLabel", {
	Name = "Caption",
	Size = UDim2.fromScale(1, 0.26),
	Position = UDim2.fromScale(0, 0.7),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = ("+%d%%"):format(math.floor((GroupRewardConfig.BonusMultiplier - 1) * 100 + 0.5)),
	TextColor3 = THEME.Green,
	TextScaled = true,
	ZIndex = 52,
}, button)
new("UITextSizeConstraint", { MaxTextSize = 13 }, caption)

local overlay = new("TextButton", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Overlay,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 100,
}, screenGui)

-- A separate offset layer gives the card depth without relying on an image
-- asset, so the prompt looks consistent on every device immediately.
local cardShadow = new("Frame", {
	Name = "CardShadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 8, 0.5, 12),
	Size = UDim2.fromScale(0.4, 0.5),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.38,
	ZIndex = 101,
}, overlay)
new("UISizeConstraint", { MinSize = Vector2.new(320, 340), MaxSize = Vector2.new(540, 430) }, cardShadow)
corner(cardShadow, UDim.new(0, 24))

local card = new("Frame", {
	Name = "RewardCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.4, 0.5),
	BackgroundColor3 = Color3.fromRGB(31, 16, 51),
	ClipsDescendants = true,
	ZIndex = 102,
}, overlay)
new("UISizeConstraint", { MinSize = Vector2.new(320, 340), MaxSize = Vector2.new(540, 430) }, card)
corner(card, UDim.new(0, 24))
local cardStroke = stroke(card, THEME.Accent, 2.5)
cardStroke.Transparency = 0.08
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(61, 29, 89)),
		ColorSequenceKeypoint.new(0.52, Color3.fromRGB(35, 18, 57)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 11, 37)),
	}),
	Rotation = 125,
}, card)
local cardScale = new("UIScale", { Scale = 0.86 }, card)
local shadowScale = new("UIScale", { Scale = 0.86 }, cardShadow)

-- Decorative glow and motes make the reward feel special while remaining
-- lightweight: these are static UI shapes, not per-frame particle effects.
local glow = new("Frame", {
	Name = "EssenceGlow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.18),
	Size = UDim2.fromScale(0.62, 0.54),
	BackgroundColor3 = THEME.Green,
	BackgroundTransparency = 0.88,
	ZIndex = 103,
}, card)
corner(glow, UDim.new(1, 0))
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Rotation = 90,
}, glow)

for index, mote in ipairs({
	{ 0.09, 0.13, 5, THEME.Accent },
	{ 0.88, 0.18, 4, THEME.Green },
	{ 0.15, 0.43, 3, THEME.Green },
	{ 0.91, 0.48, 5, THEME.Accent },
}) do
	local dot = new("Frame", {
		Name = "Mote" .. index,
		Position = UDim2.fromScale(mote[1], mote[2]),
		Size = UDim2.fromOffset(mote[3], mote[3]),
		BackgroundColor3 = mote[4],
		BackgroundTransparency = 0.18,
		ZIndex = 104,
	}, card)
	corner(dot, UDim.new(1, 0))
end

local iconBadge = new("Frame", {
	Name = "IconBadge",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.055),
	Size = UDim2.fromOffset(58, 58),
	BackgroundColor3 = Color3.fromRGB(43, 26, 65),
	ZIndex = 105,
}, card)
corner(iconBadge, UDim.new(1, 0))
stroke(iconBadge, THEME.Accent, 2)
new("UIGradient", {
	Color = ColorSequence.new(THEME.Accent, THEME.Green),
	Rotation = 45,
}, iconBadge)
new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✦",
	TextColor3 = THEME.White,
	TextSize = 32,
	ZIndex = 106,
}, iconBadge)

new("TextLabel", {
	Name = "Eyebrow",
	Position = UDim2.fromScale(0.1, 0.205),
	Size = UDim2.fromScale(0.8, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = string.upper(GroupRewardConfig.GroupName),
	TextColor3 = THEME.Accent,
	TextSize = 13,
	ZIndex = 105,
}, card)

new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.08, 0.27),
	Size = UDim2.fromScale(0.84, 0.09),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "COMMUNITY REWARD",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 105,
}, card)

local rewardPill = new("Frame", {
	Name = "RewardPill",
	Position = UDim2.fromScale(0.18, 0.385),
	Size = UDim2.fromScale(0.64, 0.13),
	BackgroundColor3 = Color3.fromRGB(29, 102, 69),
	ZIndex = 105,
}, card)
corner(rewardPill, UDim.new(1, 0))
local pillStroke = stroke(rewardPill, THEME.Green, 2)
pillStroke.Transparency = 0.2
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(37, 145, 91), Color3.fromRGB(24, 87, 67)),
	Rotation = 15,
}, rewardPill)
new("TextLabel", {
	Name = "Reward",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = ("✦  +%d%% ESSENCE  ✦"):format(math.floor((GroupRewardConfig.BonusMultiplier - 1) * 100 + 0.5)),
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 106,
}, rewardPill)

new("TextLabel", {
	Name = "Description",
	Position = UDim2.fromScale(0.1, 0.54),
	Size = UDim2.fromScale(0.8, 0.09),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Join once. Earn more essence on every reward, forever.",
	TextColor3 = THEME.Muted,
	TextWrapped = true,
	TextScaled = true,
	ZIndex = 105,
}, card)

local joinButton = new("TextButton", {
	Name = "JoinButton",
	Position = UDim2.fromScale(0.1, 0.66),
	Size = UDim2.fromScale(0.8, 0.135),
	BackgroundColor3 = THEME.Accent,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "JOIN " .. string.upper(GroupRewardConfig.GroupName) .. "  →",
	TextColor3 = Color3.fromRGB(35, 18, 48),
	TextScaled = true,
	ZIndex = 105,
}, card)
corner(joinButton, UDim.new(0, 12))
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(255, 204, 92), Color3.fromRGB(244, 137, 66)),
	Rotation = 12,
}, joinButton)
local joinStroke = stroke(joinButton, Color3.fromRGB(255, 224, 145), 1.5)
joinStroke.Transparency = 0.15

local verifyButton = new("TextButton", {
	Name = "VerifyButton",
	Position = UDim2.fromScale(0.1, 0.82),
	Size = UDim2.fromScale(0.52, 0.1),
	BackgroundColor3 = Color3.fromRGB(53, 38, 72),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "✓  I'VE JOINED — CHECK",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 105,
}, card)
corner(verifyButton, UDim.new(0, 9))
local verifyStroke = stroke(verifyButton, Color3.fromRGB(113, 91, 137), 1)
verifyStroke.Transparency = 0.3

local closeButton = new("TextButton", {
	Name = "CloseButton",
	Position = UDim2.fromScale(0.65, 0.82),
	Size = UDim2.fromScale(0.25, 0.1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "MAYBE LATER",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 105,
}, card)

local topCloseButton = new("TextButton", {
	Name = "TopCloseButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.95, 0.045),
	Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = Color3.fromRGB(58, 39, 76),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextColor3 = THEME.Muted,
	TextSize = 23,
	ZIndex = 107,
}, card)
corner(topCloseButton, UDim.new(1, 0))

local function applyButtonFeel(target, hoverColor)
	local baseColor = target.BackgroundColor3
	local scale = new("UIScale", { Scale = 1 }, target)
	target:SetAttribute("JuiceFeelApplied", true)
	target.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.025 }):Play()
		if target.BackgroundTransparency < 1 then
			TweenService:Create(target, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
		end
	end)
	target.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		if target.BackgroundTransparency < 1 then
			TweenService:Create(target, TweenInfo.new(0.12), { BackgroundColor3 = baseColor }):Play()
		end
	end)
	target.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.97 }):Play()
	end)
	target.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1.025 }):Play()
	end)
end

applyButtonFeel(joinButton, Color3.fromRGB(255, 184, 75))
applyButtonFeel(verifyButton, Color3.fromRGB(67, 49, 88))
applyButtonFeel(topCloseButton, Color3.fromRGB(77, 53, 97))

local function showPopup()
	if player:GetAttribute("GroupMember") == true then
		return
	end
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	cardScale.Scale = 0.86
	shadowScale.Scale = 0.86
	TweenService:Create(overlay, TweenInfo.new(0.2), { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(cardScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(shadowScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function hidePopup()
	if not overlay.Visible then
		return
	end
	TweenService:Create(overlay, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(cardScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.92 }):Play()
	TweenService:Create(shadowScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.92 }):Play()
	task.delay(0.16, function()
		if overlay.BackgroundTransparency >= 0.99 then
			overlay.Visible = false
		end
	end)
end

-- Hover/press feel, matching every other button in this codebase.
do
	button:SetAttribute("JuiceFeelApplied", true)
	local scale = new("UIScale", { Scale = 1 }, button)
	local scaleTarget = 1.07

	local function tween(instance, info, props)
		return TweenService:Create(instance, info, props)
	end

	button.MouseEnter:Connect(function()
		tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scaleTarget }):Play()
	end)
	button.MouseLeave:Connect(function()
		tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, TweenInfo.new(0.07), { Scale = scaleTarget * 0.9 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scaleTarget }):Play()
	end)
end

button.MouseButton1Click:Connect(function()
	showPopup()
end)

joinButton.MouseButton1Click:Connect(function()
	-- Wrapped: OpenBrowserWindowAsync can fail (platform restrictions,
	-- console/mobile quirks) and must never error out this click handler.
	pcall(function()
		GuiService:OpenBrowserWindowAsync(GroupRewardConfig.GroupUrl:format(GroupRewardConfig.GroupId))
	end)
end)

closeButton.MouseButton1Click:Connect(hidePopup)
topCloseButton.MouseButton1Click:Connect(hidePopup)
overlay.MouseButton1Click:Connect(hidePopup)

verifyButton.MouseButton1Click:Connect(function()
	verifyButton.Text = "CHECKING..."
	local ok, isMember = pcall(function()
		return checkMembership:InvokeServer()
	end)
	if ok and isMember then
		hidePopup()
	else
		verifyButton.Text = "NOT YET — TRY AGAIN"
		task.delay(2, function()
			if verifyButton.Parent then
				verifyButton.Text = "✓  I'VE JOINED — CHECK"
			end
		end)
	end
end)

-- =========================================================================
-- VISIBILITY
-- =========================================================================
-- Nothing left to do once the player is actually a member -- the bonus is
-- already applying server-side regardless of whether this button is ever
-- shown again.

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
	if not isMember then
		task.wait(5)
		showPopup()
	end
end)

player:GetAttributeChangedSignal("GroupMember"):Connect(function()
	local isMember = player:GetAttribute("GroupMember") == true
	holder.Visible = not isMember
	if isMember then
		hidePopup()
	end
end)

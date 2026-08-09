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
	BackgroundTransparency = 0.25,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 100,
}, screenGui)

local card = new("Frame", {
	Name = "RewardCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.38, 0.44),
	BackgroundColor3 = THEME.BackgroundLight,
	ZIndex = 101,
}, overlay)
new("UISizeConstraint", { MinSize = Vector2.new(300, 300), MaxSize = Vector2.new(520, 390) }, card)
corner(card, UDim.new(0, 20))
stroke(card, THEME.Accent, 3)
local cardScale = new("UIScale", { Scale = 0.86 }, card)

new("TextLabel", {
	Name = "Eyebrow",
	Position = UDim2.fromScale(0.08, 0.06),
	Size = UDim2.fromScale(0.84, 0.1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = string.upper(GroupRewardConfig.GroupName) .. " MEMBER REWARD",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	ZIndex = 102,
}, card)

new("TextLabel", {
	Name = "Reward",
	Position = UDim2.fromScale(0.08, 0.18),
	Size = UDim2.fromScale(0.84, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = ("+%d%% ESSENCE"):format(math.floor((GroupRewardConfig.BonusMultiplier - 1) * 100 + 0.5)),
	TextColor3 = THEME.Green,
	TextScaled = true,
	ZIndex = 102,
}, card)

new("TextLabel", {
	Name = "Description",
	Position = UDim2.fromScale(0.1, 0.42),
	Size = UDim2.fromScale(0.8, 0.13),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = ("Join our Roblox community to earn %d%% more essence on every reward."):format(
		math.floor((GroupRewardConfig.BonusMultiplier - 1) * 100 + 0.5)
	),
	TextColor3 = THEME.Muted,
	TextWrapped = true,
	TextScaled = true,
	ZIndex = 102,
}, card)

local joinButton = new("TextButton", {
	Name = "JoinButton",
	Position = UDim2.fromScale(0.1, 0.61),
	Size = UDim2.fromScale(0.8, 0.16),
	BackgroundColor3 = THEME.Accent,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "JOIN " .. string.upper(GroupRewardConfig.GroupName),
	TextColor3 = THEME.BackgroundLight,
	TextScaled = true,
	ZIndex = 102,
}, card)
corner(joinButton, UDim.new(0, 10))

local verifyButton = new("TextButton", {
	Name = "VerifyButton",
	Position = UDim2.fromScale(0.1, 0.8),
	Size = UDim2.fromScale(0.55, 0.1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "I'VE JOINED — CHECK",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 102,
}, card)

local closeButton = new("TextButton", {
	Name = "CloseButton",
	Position = UDim2.fromScale(0.69, 0.8),
	Size = UDim2.fromScale(0.21, 0.1),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "LATER",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 102,
}, card)

local function showPopup()
	if player:GetAttribute("GroupMember") == true then
		return
	end
	overlay.Visible = true
	cardScale.Scale = 0.86
	TweenService:Create(cardScale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function hidePopup()
	overlay.Visible = false
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
				verifyButton.Text = "I'VE JOINED — CHECK"
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

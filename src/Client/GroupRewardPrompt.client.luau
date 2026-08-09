--[[
	GroupRewardPrompt (LocalScript -> StarterPlayerScripts)
	========================================================
	A single button that opens the game's Roblox group page and, once the
	player has actually joined and rejoined the game, disappears (there's
	nothing left to do). Membership itself is granted server-side by
	GroupRewardService; this script only ever asks -- see EssenceMultiplier
	for where the bonus is actually applied.

	A complete no-op until GroupRewardConfig.GroupId is configured -- see
	that file for why this is safe to ship unconfigured. Unlike this
	codebase's other side-panel buttons (Sanctum, Rebirth Shop, ...) this
	one has no in-game panel to open: clicking it hands off to Roblox's
	own group page via GuiService:OpenBrowserWindowAsync, so there's
	nothing here to duplicate that Roblox already owns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("GroupRewardConfig"))

if not GroupRewardConfig.IsEnabled() then
	return
end

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================================================================
-- THEME + LAYOUT (matches the rest of the right-edge button column)
-- =========================================================================

local THEME = {
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
}

local LAYOUT = {
	-- Continues the RebirthShop (0.213) / Sanctum (0.295) / Leaderboard
	-- (0.377) / Achievements (0.459) column at the same x=0.92, but
	-- skips past ProgressionHud's Daily/Quest/Codes stack, which
	-- occupies ~0.51-0.75 (see ProgressionHud.client.luau's LAYOUT
	-- comment) -- 0.8 keeps a clear gap below that stack instead of
	-- continuing the 0.082 stride straight into it.
	--
	-- x was 0.895: a real screenshot showed the rest of this column
	-- rendering directly on top of MainGui.Right.Holder's own live nav
	-- bar (Upgrades/Zones/Rebirth/Index/Shop/Settings -- see
	-- UIInitializerHooks.client.luau), which occupies that same x=0.895
	-- band. 0.92 matches ProgressionHud's Daily/Quest/Codes stack,
	-- confirmed clear of that same nav bar in the same screenshot --
	-- proven-safe, not a second guess. Moved this button to match its
	-- whole column even though this specific button's y=0.8 likely sits
	-- below the nav bar's own bottom edge either way -- one shared x
	-- for the whole column is simpler to reason about than a
	-- per-button exception.
	ButtonPosition = UDim2.fromScale(0.92, 0.8),
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonSize = UDim2.fromScale(0.062, 0.062),
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
	-- Wrapped: OpenBrowserWindowAsync can fail (platform restrictions,
	-- console/mobile quirks) and must never error out this click handler.
	pcall(function()
		GuiService:OpenBrowserWindowAsync(GroupRewardConfig.GroupUrl:format(GroupRewardConfig.GroupId))
	end)
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
end)

player:GetAttributeChangedSignal("GroupMember"):Connect(function()
	holder.Visible = player:GetAttribute("GroupMember") ~= true
end)

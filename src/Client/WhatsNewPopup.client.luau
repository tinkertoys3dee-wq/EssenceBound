--[[
	WhatsNewPopup (LocalScript -> StarterPlayerScripts)
	====================================================
	A one-time "here's what's new" popup, shown once per WhatsNewConfig
	version bump to players who have played before.

	WHY THIS EXISTS
	-----------------
	Leaderboards, the Achievements panel, Essence Rush and the comeback
	bonus were all added purely additively -- nothing in-game ever told an
	existing player any of it showed up. This is the fix: a short, closable
	popup that lists what's new, shown once, driven entirely by
	WhatsNewConfig so future updates just mean editing that file.

	WHY IT NEVER SHOWS ON A PLAYER'S VERY FIRST SESSION
	------------------------------------------------------
	"What's New" implies "since you last played" -- showing it to someone
	who has never played is confusing framing, and would also mean stacking
	a third automatic popup on top of the tutorial and ProgressionHud's
	first-session Daily nudge. This script reads SeenTutorial the moment it
	first appears (which PlayerDataHandler sets from the SAVED value at
	join, before Tutorial.client's own logic runs) -- if it's already true,
	this is a returning player and the gate passes; if it's false, this is
	their first-ever session and the popup is skipped entirely THIS
	session. Next time they join, SeenTutorial will be true (from finishing
	it) and SeenWhatsNewVersion will still be behind, so it shows then --
	exactly the "catch a returning player up" moment this exists for.

	THE CLIENT DECIDES NOTHING THAT MATTERS
	------------------------------------------
	This popup grants no reward -- it's pure announcement. Marking it seen
	only updates a preference flag through the same UpdateData remote every
	other Seen* flag already uses, gated server-side by UpdateData's own
	ALLOWED_ROOTS allowlist.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local WhatsNewConfig = require(ReplicatedStorage:WaitForChild("WhatsNewConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local UpdData = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdateData")

-- =========================================================================
-- THEME (matches ProgressionHud / AchievementsPanel / LeaderboardPanel)
-- =========================================================================

local THEME = {
	Background      = Color3.fromRGB(24, 12, 40),
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Row             = Color3.fromRGB(44, 25, 68),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(158, 148, 172),
	Red             = Color3.fromRGB(230, 80, 90),
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
	return new("UIStroke", { Color = color or THEME.Accent, Thickness = thickness or 2 }, parent)
end

local function tween(instance, info, props)
	return TweenService:Create(instance, info, props)
end

local function addButtonFeel(button, scaleTarget)
	button:SetAttribute("JuiceFeelApplied", true)
	local scale = new("UIScale", { Scale = 1 }, button)
	scaleTarget = scaleTarget or 1.06

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

-- =========================================================================
-- BUILD
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "WhatsNewPopup",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 66,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, playerGui)

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 100,
}, screenGui)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.4, 0.5),
	BackgroundColor3 = THEME.Background,
	BorderSizePixel = 0,
	ZIndex = 110,
}, screenGui)
corner(panel, UDim.new(0, 18))
stroke(panel, THEME.Accent, 3)

new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 22, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 10, 34)),
	}),
	Rotation = 90,
}, panel)

local panelScale = new("UIScale", { Scale = 0.85 }, panel)

local glow = new("ImageLabel", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.52, 0.72),
	BackgroundTransparency = 1,
	Image = "rbxasset://textures/ui/Glow.png",
	ImageColor3 = THEME.Accent,
	ImageTransparency = 0.85,
	ZIndex = 105,
}, screenGui)

local titleBar = new("Frame", {
	Name = "TitleBar",
	Size = UDim2.fromScale(1, 0.14),
	BackgroundColor3 = THEME.BackgroundLight,
	BorderSizePixel = 0,
	ZIndex = 111,
}, panel)
corner(titleBar, UDim.new(0, 18))
new("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0.4),
	BackgroundColor3 = THEME.BackgroundLight,
	BorderSizePixel = 0,
	ZIndex = 111,
}, titleBar)

local titleLabel = new("TextLabel", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🎉 " .. WhatsNewConfig.Title,
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 113,
}, titleBar)
new("UITextSizeConstraint", { MaxTextSize = 28 }, titleLabel)

local closeButton = new("TextButton", {
	Name = "CloseButton",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.955, 0.5),
	Size = UDim2.fromScale(0.09, 0.55),
	BackgroundColor3 = THEME.Red,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "✕",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 113,
}, titleBar)
corner(closeButton, UDim.new(0.3, 0))
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, closeButton)
addButtonFeel(closeButton)

local list = new("ScrollingFrame", {
	Name = "List",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.18),
	Size = UDim2.fromScale(0.9, 0.62),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = THEME.Accent,
	CanvasSize = UDim2.fromScale(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 111,
}, panel)

local listLayout = new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 10),
}, list)

for index, entry in ipairs(WhatsNewConfig.Highlights) do
	local row = new("Frame", {
		Name = "Entry" .. index,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = index,
		ZIndex = 112,
	}, list)
	corner(row, UDim.new(0, 10))

	-- Fixed offset size/position, deliberately NOT scale -- `row` is
	-- AutomaticSize.Y, and a child whose size or position on that same
	-- axis is scale-based would be circular (the row can't resolve its
	-- own height from a child whose height depends on the row's height).
	-- `text` below avoids this because its AutomaticSize.Y depends only
	-- on its own wrapped content, never on the row.
	new("TextLabel", {
		Name = "Icon",
		Position = UDim2.new(0.03, 0, 0, 10),
		Size = UDim2.new(0.12, 0, 0, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = entry.Icon or "✨",
		TextScaled = true,
		ZIndex = 113,
	}, row)

	local text = new("TextLabel", {
		Name = "Text",
		Position = UDim2.fromScale(0.17, 0),
		Size = UDim2.fromScale(0.8, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = entry.Text or "",
		TextColor3 = THEME.White,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		ZIndex = 113,
	}, row)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
	}, text)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 10),
	}, row)
end

local ctaButton = new("TextButton", {
	Name = "CTA",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.965),
	Size = UDim2.fromScale(0.5, 0.11),
	BackgroundColor3 = THEME.Green,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "LET'S GO!",
	TextColor3 = THEME.Background,
	TextScaled = true,
	ZIndex = 113,
}, panel)
corner(ctaButton, UDim.new(0.3, 0))
stroke(ctaButton, THEME.White, 2)
new("UITextSizeConstraint", { MaxTextSize = 22 }, ctaButton)
addButtonFeel(ctaButton)

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local isOpen = false

local function markSeen()
	UpdData:FireServer(WhatsNewConfig.CurrentVersion, "=", "SeenWhatsNewVersion")
end

local function closePopup()
	if not isOpen then
		return
	end
	isOpen = false
	markSeen()

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local outTween = tween(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.85 })
	outTween:Play()
	outTween.Completed:Connect(function()
		if not isOpen then
			screenGui.Enabled = false
		end
	end)
end

local function openPopup()
	if isOpen then
		return
	end
	isOpen = true

	screenGui.Enabled = true
	panelScale.Scale = 0.85
	backdrop.BackgroundTransparency = 1

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()
	tween(panelScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	if juiceLayer then
		local center = Juice.CenterOf(titleBar, juiceLayer)
		if center then
			Juice.Burst(juiceLayer, center, {
				Count = 20,
				Colors = { THEME.Accent, THEME.Green, THEME.White },
				Distance = 220,
				Duration = 0.9,
				Size = { 5, 12 },
				ZIndex = 205,
			})
		end
	end
end

backdrop.Activated:Connect(closePopup)
closeButton.MouseButton1Click:Connect(closePopup)
ctaButton.MouseButton1Click:Connect(closePopup)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and isOpen then
		closePopup()
	end
end)

-- =========================================================================
-- TRIGGER
-- =========================================================================

local function waitForAttribute(name, timeoutSeconds)
	local deadline = os.clock() + timeoutSeconds
	while player:GetAttribute(name) == nil and os.clock() < deadline do
		task.wait(0.25)
	end
	return player:GetAttribute(name)
end

task.spawn(function()
	-- A brand-new player's SeenTutorial is set to `false` (their saved
	-- default) at the same moment a returning player's is set to `true` --
	-- both happen synchronously from saved data before either the tutorial
	-- or this script's own logic runs, so the first value observed here IS
	-- the value from before this session started.
	local hadSeenTutorialAtJoin = waitForAttribute("SeenTutorial", 30) == true
	if not hadSeenTutorialAtJoin then
		return
	end

	local seenVersion = tonumber(waitForAttribute("SeenWhatsNewVersion", 10)) or 0
	if seenVersion >= WhatsNewConfig.CurrentVersion then
		return
	end

	-- Longer than ProgressionHud's ~2s first-session nudge delay, so on the
	-- rare join where a Daily-reward nudge is ALSO pending, that one settles
	-- first rather than two modals fighting for the same moment.
	task.wait(6)
	if not isOpen then
		openPopup()
	end
end)

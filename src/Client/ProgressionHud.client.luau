--[[
	ProgressionHud (LocalScript -> StarterPlayerScripts)
	====================================================
	All of the player-facing UI for the three retention systems driven by
	ServerScriptService.ProgressionService:

		1. Daily login streak panel (7 day cycle)
		2. Daily quest panel (3 rotating goals)
		3. Playtime chest bar (session-length rewards)
		4. A shared reward toast used by all three

	BUILT ENTIRELY IN CODE -- AND WHY
	----------------------------------
	Every frame, label and button below is created with Instance.new
	rather than living in StarterGui. That's deliberate: the place file's
	UI is authored in Studio, and this script has to be able to add a
	complete interface without anyone hand-building matching instances
	there first. It also means this file is fully self-contained -- delete
	it and every trace of these systems disappears from the screen with
	no leftover empty frames in the place.

	The same pattern is already used by LoadingScreen, Tutorial and
	NewDiscovery, so this is consistent with how the game builds its
	other code-driven interfaces.

	THE CLIENT DECIDES NOTHING
	---------------------------
	This script never grants anything. It draws whatever state the server
	sends and fires "I'd like to claim" requests; ProgressionService
	re-validates every one of them. Locked-looking buttons remain responsive
	so NotificationService can explain what is missing or when to return.

	LAYOUT
	-------
	Screen positions for the on-screen elements are collected in LAYOUT
	below. If any of them collide with existing UI on a given screen size,
	they can each be moved by editing one line there rather than hunting
	through the construction code.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local remotesFolder = ReplicatedStorage:WaitForChild("ProgressionRemotes")
local SyncRemote = remotesFolder:WaitForChild("ProgressionSync")
local ClaimDailyRemote = remotesFolder:WaitForChild("ClaimDaily")
local ClaimQuestRemote = remotesFolder:WaitForChild("ClaimQuest")
local ClaimChestRemote = remotesFolder:WaitForChild("ClaimChest")
local ToastRemote = remotesFolder:WaitForChild("RewardToast")
local RedeemCodeFunction = remotesFolder:WaitForChild("RedeemCode")

-- =========================================================================
-- THEME + LAYOUT
-- =========================================================================
-- Colors match the palette already used by UIInitializerHooks so these
-- panels read as part of the same game rather than bolted on.

local THEME = {
	Background      = Color3.fromRGB(24, 12, 40),
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Panel           = Color3.fromRGB(30, 16, 48),
	Row             = Color3.fromRGB(44, 25, 68),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(158, 148, 172),
	Locked          = Color3.fromRGB(58, 50, 76),
	Red             = Color3.fromRGB(230, 80, 90),
	Gold            = Color3.fromRGB(255, 215, 0),
}

local LAYOUT = {
	-- Vertical button stack (Daily + Quests + Codes). Anchored to the right
	-- edge, below the currency panel that occupies the top-left.
	--
	-- The stack now starts at y=0.59 (top-anchored) directly beneath the
	-- Astral Forge's fifth rail slot. A compact fixed band and small gap keep
	-- all three square buttons above the bottom-corner Wheel at every common
	-- landscape resolution.
	--
	-- This replaces the old center-at-0.63 layout, whose large proportional
	-- list padding actually overflowed into GroupReward even before Forge was
	-- added. GroupReward now sits beside this lower rail, not on top of it.
	--
	-- Originally this stack lived near y=0.2 and overlapped the Prestige and
	-- Sanctum shortcuts on the same x column.
	--
	-- x=0.952 (was 0.895, then briefly 0.92): a real screenshot showed
	-- the whole RebirthShop/Sanctum/Leaderboard/Achievements/GroupReward
	-- column rendering directly on top of MainGui.Right.Holder's own
	-- live nav bar (Upgrades/Zones/Rebirth/Index/Shop/Settings). 0.952
	-- is the shared shortcut rail every code-created button on the right
	-- edge now uses -- keeps them all clear of the Studio-authored rows.
	ButtonsPosition = UDim2.fromScale(0.952, 0.59),
	ButtonsAnchor = Vector2.new(0, 0),
	ButtonSize = UDim2.fromScale(0.044, 0.062),
	ButtonsHeight = 0.27,

	-- The old y=0.12 placement covered MainGui.Right.ManualSummonButton
	-- (the CLAIM First Find bar). Put the pill immediately beneath it and
	-- above the first navigation row instead.
	ChestPosition = UDim2.fromScale(0.78, 0.18),
	ChestAnchor = Vector2.new(0, 0.5),
	ChestSize = UDim2.fromScale(0.14, 0.043),

	-- Reward toast, dropping in from the top edge.
	ToastPosition = UDim2.fromScale(0.5, 0.055),
	ToastHidden = UDim2.fromScale(0.5, -0.15),
	ToastSize = UDim2.fromScale(0.28, 0.085),
}

local CLAIM_SOUND_NAME = "UIPop"

-- =========================================================================
-- SMALL HELPERS
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
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 10) }, parent)
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

-- The game's existing UI click sound, if it's present. Wrapped because a
-- missing sound must never break a claim.
local function playClickSound()
	pcall(function()
		local sfx = SoundService:FindFirstChild("SFX")
		local ui = sfx and sfx:FindFirstChild("UI")
		local sound = ui and ui:FindFirstChild(CLAIM_SOUND_NAME)
		if sound then
			sound:Play()
		end
	end)
end

-- Hover/press feel, applied to every button here so they behave like the
-- rest of the game's buttons.
local function addButtonFeel(button, scaleTarget)
	-- Marks this button as already animated so the global Juice.ButtonFeel
	-- pass in UIManagement doesn't add a second, competing one.
	button:SetAttribute("JuiceFeelApplied", true)

	local scale = new("UIScale", { Scale = 1 }, button)
	scaleTarget = scaleTarget or 1.07

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

	return scale
end

-- =========================================================================
-- ROOT GUI
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "ProgressionHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 60,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- Shared dimmed backdrop for the two modal panels.
local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 100,
}, screenGui)

-- =========================================================================
-- STATE
-- =========================================================================

local state = {
	Daily = nil,
	Quests = {},
	Chest = nil,
}

-- Local clock reference so the chest countdown stays smooth between the
-- server's periodic state pushes instead of only ticking when one lands.
local chestSyncedAt = os.clock()

local openPanel = nil -- "Daily" | "Quests" | nil

-- =========================================================================
-- REWARD TOAST
-- =========================================================================

local toastFrame = new("Frame", {
	Name = "RewardToast",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = LAYOUT.ToastHidden,
	Size = LAYOUT.ToastSize,
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 200,
}, screenGui)
corner(toastFrame, UDim.new(0, 14))
stroke(toastFrame, THEME.Accent, 2.5)

-- Purely decorative; parented on creation and never referenced again.
new("ImageLabel", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.35, 2),
	BackgroundTransparency = 1,
	Image = "rbxasset://textures/ui/Glow.png",
	ImageColor3 = THEME.Accent,
	ImageTransparency = 0.65,
	ZIndex = 199,
}, toastFrame)

local toastIcon = new("TextLabel", {
	Name = "Icon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.045, 0.5),
	Size = UDim2.fromScale(0.16, 0.62),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🎁",
	TextScaled = true,
	ZIndex = 201,
}, toastFrame)

local toastTitle = new("TextLabel", {
	Name = "Title",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromScale(0.23, 0.18),
	Size = UDim2.fromScale(0.72, 0.34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "Reward",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 201,
}, toastFrame)
new("UITextSizeConstraint", { MaxTextSize = 22 }, toastTitle)

local toastSubtitle = new("TextLabel", {
	Name = "Subtitle",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromScale(0.23, 0.52),
	Size = UDim2.fromScale(0.72, 0.3),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 201,
}, toastFrame)
new("UITextSizeConstraint", { MaxTextSize = 16 }, toastSubtitle)

local toastQueue = {}
local toastShowing = false

local toastScale = Juice.GetScale(toastFrame)

local function playToast(payload)
	-- Reward state is already visible in the panels and balances. During a
	-- focused presentation, suppress this redundant celebration instead of
	-- saving a stack that would avalanche immediately afterward.
	if PresentationCoordinator.HasPendingPresentation() then
		return
	end
	toastIcon.Text = payload.Icon or "🎁"
	toastTitle.Text = payload.Title or "Reward"
	toastSubtitle.Text = payload.Subtitle or ""

	toastFrame.Position = LAYOUT.ToastHidden
	toastFrame.Visible = true

	local inTween = tween(toastFrame, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = LAYOUT.ToastPosition,
	})
	inTween:Play()
	inTween.Completed:Wait()

	-- Landing beat: earning something should feel like an event, not a
	-- notification. Purely cosmetic -- the reward was already granted and
	-- validated server-side before this ever ran.
	Juice.Punch(toastScale, 0.12, 0.3)

	if juiceLayer then
		local center = Juice.CenterOf(toastFrame, juiceLayer)
		if center then
			Juice.Burst(juiceLayer, center, {
				Count = 16,
				Colors = { THEME.Gold, THEME.Accent, THEME.White },
				Distance = 190,
				Duration = 0.8,
				Size = { 5, 12 },
				ZIndex = 205,
			})
		end
	end

	task.wait(2.4)

	local outTween = tween(toastFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = LAYOUT.ToastHidden,
	})
	outTween:Play()
	outTween.Completed:Wait()

	toastFrame.Visible = false
end

local function processToastQueue()
	if toastShowing then
		return
	end
	toastShowing = true

	while #toastQueue > 0 do
		local payload = table.remove(toastQueue, 1)
		local ok, err = pcall(playToast, payload)
		if not ok then
			warn("[ProgressionHud] Toast failed: " .. tostring(err))
			toastFrame.Visible = false
		end
	end

	toastShowing = false
end

PresentationCoordinator.Changed:Connect(function()
	if PresentationCoordinator.HasPendingPresentation() then
		toastFrame.Visible = false
	end
end)

ToastRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	table.insert(toastQueue, payload)
	playClickSound()
	task.spawn(processToastQueue)
end)

-- =========================================================================
-- SIDE BUTTONS (Daily + Quests)
-- =========================================================================

local buttonHolder = new("Frame", {
	Name = "ProgressionButtons",
	AnchorPoint = LAYOUT.ButtonsAnchor,
	Position = LAYOUT.ButtonsPosition,
	Size = UDim2.fromScale(LAYOUT.ButtonSize.X.Scale, LAYOUT.ButtonsHeight),
	BackgroundTransparency = 1,
	ZIndex = 50,
}, screenGui)

local buttonListLayout = new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.02, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, buttonHolder)

-- Very short landscape phones have less vertical space above the Wheel's
-- enforced 64px minimum. Narrow this one lower band only; the four primary
-- rail shortcuts and the Forge stay full-sized, while Daily/Quests/Codes
-- remain separate, visible buttons instead of overlapping the Wheel.
local cameraViewportConnection = nil
local function updateProgressionButtonBand()
	local camera = workspace.CurrentCamera
	local compact = camera ~= nil and camera.ViewportSize.Y < 500
	buttonHolder.Size = compact
		and UDim2.fromScale(0.03, 0.215)
		or UDim2.fromScale(LAYOUT.ButtonSize.X.Scale, LAYOUT.ButtonsHeight)
	buttonListLayout.Padding = compact and UDim.new(0.015, 0) or UDim.new(0.02, 0)
end

local function bindProgressionViewport()
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateProgressionButtonBand)
	end
	updateProgressionButtonBand()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindProgressionViewport)
bindProgressionViewport()

-- Builds one round icon button with an unread "!" badge.
local function createSideButton(icon, labelText, order)
	local holder = new("Frame", {
		Name = labelText .. "ButtonHolder",
		Size = UDim2.fromScale(1, 0.28),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		ZIndex = 50,
	}, buttonHolder)

	new("UIAspectRatioConstraint", {
		AspectRatio = 1,
		DominantAxis = Enum.DominantAxis.Width,
	}, holder)

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
		Text = icon,
		TextScaled = true,
		ZIndex = 52,
	}, button)

	local caption = new("TextLabel", {
		Name = "Caption",
		Size = UDim2.fromScale(1, 0.26),
		Position = UDim2.fromScale(0, 0.7),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = labelText,
		TextColor3 = THEME.White,
		TextScaled = true,
		ZIndex = 52,
	}, button)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, caption)

	-- Attention badge: shown whenever something is actually claimable.
	local badge = new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = THEME.Red,
		Visible = false,
		ZIndex = 53,
	}, button)
	corner(badge, UDim.new(1, 0))
	stroke(badge, THEME.White, 2)

	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "!",
		TextColor3 = THEME.White,
		TextScaled = true,
		ZIndex = 54,
	}, badge)

	addButtonFeel(button)

	return button, badge
end

local dailyButton, dailyBadge = createSideButton("🎁", "DAILY", 1)
local questButton, questBadge = createSideButton("📜", "QUESTS", 2)
local codeButton = createSideButton("🎟️", "CODES", 3)

-- A slow pulse on a badge draws the eye without being loud about it.
task.spawn(function()
	while true do
		for _, badge in ipairs({ dailyBadge, questBadge }) do
			if badge.Visible then
				tween(badge, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Size = UDim2.fromScale(0.4, 0.4),
				}):Play()
			end
		end
		task.wait(0.5)
		for _, badge in ipairs({ dailyBadge, questBadge }) do
			if badge.Visible then
				tween(badge, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Size = UDim2.fromScale(0.34, 0.34),
				}):Play()
			end
		end
		task.wait(0.5)
	end
end)

-- =========================================================================
-- PLAYTIME CHEST PILL
-- =========================================================================

local chestPill = new("TextButton", {
	Name = "ChestPill",
	AnchorPoint = LAYOUT.ChestAnchor,
	Position = LAYOUT.ChestPosition,
	Size = LAYOUT.ChestSize,
	BackgroundColor3 = THEME.Panel,
	AutoButtonColor = false,
	Text = "",
	-- Stays hidden until the server's first state push, so it never
	-- flashes a placeholder countdown on join.
	Visible = false,
	ZIndex = 50,
}, screenGui)
corner(chestPill, UDim.new(0.35, 0))
local chestStroke = stroke(chestPill, THEME.Locked, 2)

-- Fill bar showing progress toward the next chest.
local chestFillHolder = new("Frame", {
	Name = "FillHolder",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.fromScale(1, 0.16),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 51,
}, chestPill)
corner(chestFillHolder, UDim.new(0.5, 0))

local chestFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 52,
}, chestFillHolder)
corner(chestFill, UDim.new(0.5, 0))

local chestIcon = new("TextLabel", {
	Name = "Icon",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.04, 0.44),
	Size = UDim2.fromScale(0.18, 0.6),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🎁",
	TextScaled = true,
	ZIndex = 53,
}, chestPill)

local chestLabel = new("TextLabel", {
	Name = "Label",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.24, 0.44),
	Size = UDim2.fromScale(0.72, 0.55),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Next chest...",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 53,
}, chestPill)
new("UITextSizeConstraint", { MaxTextSize = 15 }, chestLabel)

addButtonFeel(chestPill, 1.04)

-- =========================================================================
-- PANEL SCAFFOLDING (shared by Daily + Quests)
-- =========================================================================

local function createPanel(titleText, subtitleText, sizeScale)
	local panel = new("Frame", {
		Name = titleText .. "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = sizeScale,
		BackgroundColor3 = THEME.Background,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 110,
	}, screenGui)
	corner(panel, UDim.new(0, 18))
	stroke(panel, THEME.Accent, 3)

	-- Vertical gradient so the panel reads as a lit surface rather than a
	-- flat rectangle. Subtle on purpose: strong enough to give depth,
	-- weak enough that text contrast is unaffected anywhere on it.
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(38, 22, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 10, 34)),
		}),
		Rotation = 90,
	}, panel)

	-- Soft glow lifting the panel off the dimmed backdrop.
	--
	-- Must be a SIBLING of the panel, not a child: under
	-- ZIndexBehavior.Sibling a child always draws above its parent's
	-- background regardless of ZIndex, so nesting this would wash an
	-- orange haze over the panel's own contents instead of sitting behind
	-- it. Its visibility is chained to the panel's below.
	local glow = new("ImageLabel", {
		Name = titleText .. "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(sizeScale.X.Scale * 1.3, sizeScale.Y.Scale * 1.45),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Glow.png",
		ImageColor3 = THEME.Accent,
		ImageTransparency = 0.85,
		Visible = false,
		ZIndex = 105,
	}, screenGui)

	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		glow.Visible = panel.Visible
	end)

	local scale = new("UIScale", { Scale = 0.85 }, panel)

	local titleBar = new("Frame", {
		Name = "TitleBar",
		Size = UDim2.fromScale(1, 0.16),
		BackgroundColor3 = THEME.BackgroundLight,
		BorderSizePixel = 0,
		ZIndex = 111,
	}, panel)
	corner(titleBar, UDim.new(0, 18))

	-- Squares off the bottom corners of the title bar so it meets the
	-- panel body flush instead of showing a rounded seam.
	new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundColor3 = THEME.BackgroundLight,
		BorderSizePixel = 0,
		ZIndex = 111,
	}, titleBar)

	local title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.42),
		Size = UDim2.fromScale(0.6, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = titleText,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 113,
	}, titleBar)
	new("UITextSizeConstraint", { MaxTextSize = 26 }, title)

	local subtitle = new("TextLabel", {
		Name = "Subtitle",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.78),
		Size = UDim2.fromScale(0.7, 0.3),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = subtitleText or "",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 113,
	}, titleBar)
	new("UITextSizeConstraint", { MaxTextSize = 14 }, subtitle)

	local closeButton = new("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.965, 0.5),
		Size = UDim2.fromScale(0.075, 0.55),
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

	local body = new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.18),
		Size = UDim2.fromScale(0.94, 0.79),
		BackgroundTransparency = 1,
		ZIndex = 111,
	}, panel)

	return {
		Frame = panel,
		Scale = scale,
		Body = body,
		Subtitle = subtitle,
		CloseButton = closeButton,
	}
end

local dailyPanel = createPanel("Daily Rewards", "Come back each day for a bigger reward", UDim2.fromScale(0.56, 0.46))
local questPanel = createPanel("Daily Quests", "Three goals, new every day", UDim2.fromScale(0.5, 0.52))
local codePanel = createPanel("Enter Code", "Codes are posted by the game's creator", UDim2.fromScale(0.42, 0.34))

-- =========================================================================
-- PANEL OPEN / CLOSE
-- =========================================================================

-- Registry keyed by panel name, so adding another panel later needs only
-- an entry here rather than another branch in the open/close logic.
local panels = {
	Daily = dailyPanel,
	Quests = questPanel,
	Codes = codePanel,
}

-- Populated after each panel's content is built further below.
local panelRefreshers = {}

-- Forward declarations: the panel bodies are constructed further down,
-- but showPanel and the countdown ticker both need to reach them.
local refreshDaily, refreshQuests

local function closePanel()
	if not openPanel then
		return
	end

	local target = panels[openPanel]
	openPanel = nil
	if not target then
		return
	end

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()

	local outTween = tween(target.Scale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.85 })
	outTween:Play()
	outTween.Completed:Connect(function()
		if openPanel == nil then
			target.Frame.Visible = false
			backdrop.Visible = false
		end
	end)
end

local manualProgressionPanelOpened = false

local function showPanel(which, allowedOwner)
	if openPanel == which then
		closePanel()
		return
	end
	if openPanel == nil and not PresentationCoordinator.CanOpenModal(allowedOwner) then
		return
	end

	local target = panels[which]
	if not target then
		return
	end

	if openPanel and panels[openPanel] then
		panels[openPanel].Frame.Visible = false
	end

	openPanel = which

	local refresher = panelRefreshers[which]
	if refresher then
		refresher()
	end

	backdrop.Visible = true
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	target.Frame.Visible = true
	target.Scale.Scale = 0.85
	tween(target.Scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	playClickSound()
end

backdrop.Activated:Connect(closePanel)
for _, panel in pairs(panels) do
	panel.CloseButton.MouseButton1Click:Connect(closePanel)
end
dailyButton.MouseButton1Click:Connect(function()
	manualProgressionPanelOpened = true
	showPanel("Daily")
end)
questButton.MouseButton1Click:Connect(function()
	manualProgressionPanelOpened = true
	showPanel("Quests")
end)
codeButton.MouseButton1Click:Connect(function()
	manualProgressionPanelOpened = true
	showPanel("Codes")
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape and openPanel then
		closePanel()
	end
end)

-- =========================================================================
-- DAILY PANEL CONTENT
-- =========================================================================

local dayCardGrid = new("Frame", {
	Name = "DayGrid",
	Size = UDim2.fromScale(1, 0.62),
	BackgroundTransparency = 1,
	ZIndex = 112,
}, dailyPanel.Body)

new("UIGridLayout", {
	CellSize = UDim2.fromScale(0.128, 0.86),
	CellPadding = UDim2.fromScale(0.0155, 0.06),
	FillDirectionMaxCells = 7,
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, dayCardGrid)

local dayCards = {}

for index, reward in ipairs(ProgressionConfig.DailyRewards) do
	local card = new("Frame", {
		Name = "Day" .. index,
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = index,
		ZIndex = 112,
	}, dayCardGrid)
	corner(card, UDim.new(0, 10))
	local cardStroke = stroke(card, THEME.Locked, 2)

	local dayLabel = new("TextLabel", {
		Name = "DayLabel",
		Position = UDim2.fromScale(0, 0.06),
		Size = UDim2.fromScale(1, 0.18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = reward.Title,
		TextColor3 = THEME.Grey,
		TextScaled = true,
		ZIndex = 113,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, dayLabel)

	new("TextLabel", {
		Name = "Icon",
		Position = UDim2.fromScale(0, 0.26),
		Size = UDim2.fromScale(1, 0.34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = reward.Icon,
		TextScaled = true,
		ZIndex = 113,
	}, card)

	local amountLabel = new("TextLabel", {
		Name = "Amount",
		Position = UDim2.fromScale(0, 0.62),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = ProgressionConfig.FormatNumber(reward.Essence),
		TextColor3 = THEME.Green,
		TextScaled = true,
		ZIndex = 113,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 15 }, amountLabel)

	local bonusParts = {}
	if (tonumber(reward.SolarEssence) or 0) > 0 then
		table.insert(bonusParts, "+" .. ProgressionConfig.FormatNumber(reward.SolarEssence) .. " ☀")
	end
	if reward.Potion then
		table.insert(bonusParts, "BOOST")
	end
	local bonusLabel = new("TextLabel", {
		Name = "Bonus",
		Position = UDim2.fromScale(0, 0.82),
		Size = UDim2.fromScale(1, 0.15),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = table.concat(bonusParts, " • "),
		TextColor3 = THEME.Accent,
		TextScaled = true,
		ZIndex = 113,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 11 }, bonusLabel)

	-- Covers a day already collected in this cycle.
	local claimedOverlay = new("Frame", {
		Name = "ClaimedOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.55,
		Visible = false,
		ZIndex = 114,
	}, card)
	corner(claimedOverlay, UDim.new(0, 10))

	new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "✓",
		TextColor3 = THEME.Green,
		TextScaled = true,
		ZIndex = 115,
	}, claimedOverlay)

	dayCards[index] = {
		Card = card,
		Stroke = cardStroke,
		DayLabel = dayLabel,
		Amount = amountLabel,
		ClaimedOverlay = claimedOverlay,
	}
end

local dailyStatusLabel = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.66),
	Size = UDim2.fromScale(0.9, 0.1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 113,
}, dailyPanel.Body)
new("UITextSizeConstraint", { MaxTextSize = 15 }, dailyStatusLabel)

local dailyClaimButton = new("TextButton", {
	Name = "ClaimButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromScale(0.42, 0.19),
	BackgroundColor3 = THEME.Green,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "CLAIM",
	TextColor3 = THEME.Background,
	TextScaled = true,
	ZIndex = 113,
}, dailyPanel.Body)
corner(dailyClaimButton, UDim.new(0.3, 0))
stroke(dailyClaimButton, THEME.White, 2)
new("UITextSizeConstraint", { MaxTextSize = 22 }, dailyClaimButton)
addButtonFeel(dailyClaimButton)

function refreshDaily()
	local daily = state.Daily
	if not daily then
		return
	end

	-- Which cycle slot each card represents relative to the current streak.
	local pendingIndex = select(2, ProgressionConfig.GetDailyRewardForStreak(daily.PendingStreak or 1))
	local claimedThisCycle = daily.CanClaim and (pendingIndex - 1) or pendingIndex

	for index, card in ipairs(dayCards) do
		local isClaimed = index <= claimedThisCycle
		local isNext = daily.CanClaim and index == pendingIndex

		card.ClaimedOverlay.Visible = isClaimed
		card.Stroke.Color = isNext and THEME.Accent or THEME.Locked
		card.Stroke.Thickness = isNext and 3.5 or 2
		card.DayLabel.TextColor3 = isNext and THEME.Accent or THEME.Grey
		card.Card.BackgroundColor3 = isNext and THEME.BackgroundLight or THEME.Row

		-- Amounts are shown scaled to this player's own progression, so
		-- the number on the card is the number they'll actually receive.
		local reward = ProgressionConfig.DailyRewards[index]
		card.Amount.Text = ProgressionConfig.FormatNumber(
			ProgressionConfig.ScaleReward(reward.Essence, state.Rebirths or 0)
		)
	end

	-- Only shown once a freeze is actually banked -- nothing to explain
	-- (and nothing about being "at risk") when there isn't one yet.
	local freezeSuffix = ""
	if (daily.StreakFreezes or 0) > 0 then
		freezeSuffix = ("  •  🛡️ x%d"):format(daily.StreakFreezes)
	end

	if daily.CanClaim then
		dailyClaimButton.Text = "CLAIM DAY " .. tostring(daily.PendingStreak or 1)
		dailyClaimButton.BackgroundColor3 = THEME.Green
		dailyClaimButton.Active = true
		dailyStatusLabel.Text = ("Current streak: %d day(s)  •  Best: %d%s")
			:format(daily.Streak or 0, daily.BestStreak or 0, freezeSuffix)
	else
		dailyClaimButton.Text = "CLAIMED TODAY"
		dailyClaimButton.BackgroundColor3 = THEME.Locked
		-- Keep completed rewards responsive: clicking explains when the next
		-- one arrives instead of making the interface feel broken.
		dailyClaimButton.Active = true
		dailyStatusLabel.Text = ("Streak: %d day(s)  •  Next reward in %s%s")
			:format(daily.Streak or 0, ProgressionConfig.FormatDuration(daily.SecondsUntilReset or 0), freezeSuffix)
	end
end

dailyClaimButton.MouseButton1Click:Connect(function()
	if not state.Daily then
		NotificationService.Info("Your daily streak is still loading.", {
			Title = "Rewards Still Loading",
			Key = "daily-loading",
		})
		return
	end
	if not state.Daily.CanClaim then
		NotificationService.Info(("You already claimed today. The next reward arrives in %s."):format(
			ProgressionConfig.FormatDuration(state.Daily.SecondsUntilReset or 0)
		), {
			Title = "Daily Reward Claimed",
			Icon = "✓",
			Key = "daily-already-claimed",
		})
		return
	end
	ClaimDailyRemote:FireServer()
end)

-- =========================================================================
-- QUEST PANEL CONTENT
-- =========================================================================

local questRows = {}

local questList = new("Frame", {
	Name = "QuestList",
	Size = UDim2.fromScale(1, 0.84),
	BackgroundTransparency = 1,
	ZIndex = 112,
}, questPanel.Body)

new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.04, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, questList)

for slot = 1, ProgressionConfig.QuestsPerDay do
	local row = new("Frame", {
		Name = "Quest" .. slot,
		Size = UDim2.fromScale(1, 0.30),
		BackgroundColor3 = THEME.Row,
		BorderSizePixel = 0,
		LayoutOrder = slot,
		ZIndex = 112,
	}, questList)
	corner(row, UDim.new(0, 12))
	local rowStroke = stroke(row, THEME.Locked, 2)

	local icon = new("TextLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.025, 0.5),
		Size = UDim2.fromScale(0.1, 0.55),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "🔮",
		TextScaled = true,
		ZIndex = 113,
	}, row)

	local title = new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromScale(0.14, 0.12),
		Size = UDim2.fromScale(0.5, 0.28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "Quest",
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 113,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 18 }, title)

	local description = new("TextLabel", {
		Name = "Description",
		Position = UDim2.fromScale(0.14, 0.4),
		Size = UDim2.fromScale(0.5, 0.24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 113,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 14 }, description)

	-- Progress bar
	local barBg = new("Frame", {
		Name = "BarBg",
		Position = UDim2.fromScale(0.14, 0.7),
		Size = UDim2.fromScale(0.5, 0.14),
		BackgroundColor3 = THEME.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 113,
	}, row)
	corner(barBg, UDim.new(0.5, 0))

	local barFill = new("Frame", {
		Name = "BarFill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
		ZIndex = 114,
	}, barBg)
	corner(barFill, UDim.new(0.5, 0))

	local progressLabel = new("TextLabel", {
		Name = "ProgressLabel",
		Position = UDim2.fromScale(0.655, 0.68),
		Size = UDim2.fromScale(0.16, 0.18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "0 / 0",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 113,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 13 }, progressLabel)

	local rewardLabel = new("TextLabel", {
		Name = "Reward",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.975, 0.14),
		Size = UDim2.fromScale(0.3, 0.24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = THEME.Green,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 113,
	}, row)
	new("UITextSizeConstraint", { MaxTextSize = 15 }, rewardLabel)

	local claimButton = new("TextButton", {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.975, 0.86),
		Size = UDim2.fromScale(0.26, 0.36),
		BackgroundColor3 = THEME.Locked,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "CLAIM",
		TextColor3 = THEME.Grey,
		TextScaled = true,
		ZIndex = 114,
	}, row)
	corner(claimButton, UDim.new(0.3, 0))
	new("UITextSizeConstraint", { MaxTextSize = 16 }, claimButton)
	addButtonFeel(claimButton)

	claimButton.MouseButton1Click:Connect(function()
		local questState = state.Quests and state.Quests[slot]
		if not questState then
			NotificationService.Info("Your daily quests are still loading.", {
				Title = "Quests Still Loading",
				Key = "quest-loading",
			})
			return
		end
		if questState.Claimed then
			NotificationService.Info((questState.Title or "This quest") .. " has already been claimed.", {
				Title = "Quest Complete",
				Icon = "✓",
				Key = "quest-claimed:" .. slot,
			})
			return
		end
		if (questState.Progress or 0) < (questState.Target or math.huge) then
			local remaining = math.max(0, (questState.Target or 0) - (questState.Progress or 0))
			NotificationService.Info(("%s needs %s more progress before it can be claimed."):format(
				questState.Title or "This quest",
				ProgressionConfig.FormatNumber(remaining)
			), {
				Title = "Quest In Progress",
				Icon = questState.Icon or "◆",
				Key = "quest-incomplete:" .. slot,
			})
			return
		end
		ClaimQuestRemote:FireServer(slot)
	end)

	questRows[slot] = {
		Row = row,
		Stroke = rowStroke,
		Icon = icon,
		Title = title,
		Description = description,
		BarFill = barFill,
		ProgressLabel = progressLabel,
		RewardLabel = rewardLabel,
		ClaimButton = claimButton,
	}
end

local questResetLabel = new("TextLabel", {
	Name = "ResetLabel",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromScale(0.9, 0.1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 113,
}, questPanel.Body)
new("UITextSizeConstraint", { MaxTextSize = 14 }, questResetLabel)

function refreshQuests()
	for slot, row in ipairs(questRows) do
		local quest = state.Quests and state.Quests[slot]

		if not quest then
			row.Row.Visible = false
		else
			row.Row.Visible = true
			row.Icon.Text = quest.Icon or "🔮"
			row.Title.Text = quest.Title or "Quest"
			row.Description.Text = quest.Description or ""
			row.RewardLabel.Text = "+" .. ProgressionConfig.FormatNumber(quest.Reward or 0)

			local target = math.max(1, quest.Target or 1)
			local progress = math.clamp(quest.Progress or 0, 0, target)
			local ratio = progress / target
			local complete = progress >= target

			tween(row.BarFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(ratio, 1),
			}):Play()

			row.ProgressLabel.Text = ("%s / %s"):format(
				ProgressionConfig.FormatNumber(progress),
				ProgressionConfig.FormatNumber(target)
			)

			if quest.Claimed then
				row.ClaimButton.Text = "DONE ✓"
				row.ClaimButton.BackgroundColor3 = THEME.Locked
				row.ClaimButton.TextColor3 = THEME.Green
				row.ClaimButton.Active = true
				row.Stroke.Color = THEME.Green
				row.BarFill.BackgroundColor3 = THEME.Green
			elseif complete then
				row.ClaimButton.Text = "CLAIM"
				row.ClaimButton.BackgroundColor3 = THEME.Green
				row.ClaimButton.TextColor3 = THEME.Background
				row.ClaimButton.Active = true
				row.Stroke.Color = THEME.Accent
				row.BarFill.BackgroundColor3 = THEME.Green
			else
				row.ClaimButton.Text = "CLAIM"
				row.ClaimButton.BackgroundColor3 = THEME.Locked
				row.ClaimButton.TextColor3 = THEME.Grey
				row.ClaimButton.Active = true
				row.Stroke.Color = THEME.Locked
				row.BarFill.BackgroundColor3 = THEME.Accent
			end
		end
	end

	local seconds = state.Daily and state.Daily.SecondsUntilReset or 0
	questResetLabel.Text = "New quests in " .. ProgressionConfig.FormatDuration(seconds)
end

-- =========================================================================
-- CODE PANEL CONTENT
-- =========================================================================

local codeBox = new("TextBox", {
	Name = "CodeBox",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.06),
	Size = UDim2.fromScale(0.9, 0.28),
	BackgroundColor3 = THEME.Row,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	PlaceholderText = "Type a code...",
	PlaceholderColor3 = THEME.Grey,
	Text = "",
	TextColor3 = THEME.White,
	TextScaled = true,
	ClearTextOnFocus = false,
	ZIndex = 113,
}, codePanel.Body)
corner(codeBox, UDim.new(0, 10))
stroke(codeBox, THEME.Locked, 2)
new("UITextSizeConstraint", { MaxTextSize = 22 }, codeBox)

local codeStatus = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromScale(0.92, 0.2),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 113,
}, codePanel.Body)
new("UITextSizeConstraint", { MaxTextSize = 15 }, codeStatus)

local codeSubmit = new("TextButton", {
	Name = "Submit",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 1),
	Size = UDim2.fromScale(0.55, 0.26),
	BackgroundColor3 = THEME.Green,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "REDEEM",
	TextColor3 = THEME.Background,
	TextScaled = true,
	ZIndex = 113,
}, codePanel.Body)
corner(codeSubmit, UDim.new(0.3, 0))
stroke(codeSubmit, THEME.White, 2)
new("UITextSizeConstraint", { MaxTextSize = 20 }, codeSubmit)
addButtonFeel(codeSubmit)

local codeSubmitBusy = false

local function submitCode()
	if codeSubmitBusy then
		return
	end

	local entered = codeBox.Text
	if entered:gsub("%s", "") == "" then
		codeStatus.Text = "Enter a code first."
		codeStatus.TextColor3 = THEME.Grey
		NotificationService.Info("Type a code before pressing redeem.", {
			Title = "Enter a Code",
			Icon = "#",
			Key = "code-empty",
		})
		return
	end

	codeSubmitBusy = true
	codeSubmit.Text = "..."
	codeStatus.Text = ""

	-- InvokeServer yields and can throw if the server errors or the
	-- player leaves mid-call, so the whole thing is wrapped and the
	-- button is always restored.
	task.spawn(function()
		local ok, success, message = pcall(function()
			return RedeemCodeFunction:InvokeServer(entered)
		end)

		codeSubmitBusy = false
		codeSubmit.Text = "REDEEM"

		if not ok then
			codeStatus.Text = "Something went wrong -- try again."
			codeStatus.TextColor3 = THEME.Red
			NotificationService.Error(codeStatus.Text, {
				Title = "Code Connection Failed",
				Key = "code-connection",
			})
			return
		end

		codeStatus.Text = tostring(message or "")
		codeStatus.TextColor3 = success and THEME.Green or THEME.Red

		if success then
			codeBox.Text = ""
			NotificationService.Success(tostring(message or "Your reward was delivered."), {
				Title = "Code Redeemed",
				Icon = "#",
				Key = "code-success",
			})
		else
			NotificationService.Warning(tostring(message or "That code could not be redeemed."), {
				Title = "Code Not Redeemed",
				Icon = "#",
				Key = "code-failed:" .. string.lower(entered),
			})
		end
	end)
end

codeSubmit.MouseButton1Click:Connect(submitCode)
codeBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submitCode()
	end
end)

panelRefreshers.Daily = function() refreshDaily() end
panelRefreshers.Quests = function() refreshQuests() end
panelRefreshers.Codes = function()
	codeStatus.Text = ""
	codeSubmit.Text = "REDEEM"
	codeSubmitBusy = false
end

-- =========================================================================
-- BADGE / CHEST STATE
-- =========================================================================

local function anyQuestClaimable()
	for _, quest in pairs(state.Quests or {}) do
		if not quest.Claimed and (quest.Progress or 0) >= (quest.Target or math.huge) then
			return true
		end
	end
	return false
end

local function refreshBadges()
	dailyBadge.Visible = (state.Daily and state.Daily.CanClaim) == true
	questBadge.Visible = anyQuestClaimable()
end

-- Chest pill is redrawn every frame-ish so its countdown stays live
-- between server pushes; `Ready` is still only ever decided by the
-- server value plus locally elapsed time, and the claim is re-validated
-- server-side regardless.
local function refreshChest()
	local chest = state.Chest
	if not chest then
		chestPill.Visible = false
		return
	end

	chestPill.Visible = true

	local elapsed = (chest.Elapsed or 0) + (os.clock() - chestSyncedAt)
	local target = math.max(1, chest.NextAt or 1)
	local ratio = math.clamp(elapsed / target, 0, 1)
	local ready = elapsed >= target

	chestFill.Size = UDim2.fromScale(ratio, 1)
	chestIcon.Text = chest.NextIcon or "🎁"

	if ready then
		chestLabel.Text = ("CLAIM %s"):format(chest.NextTitle or "Chest")
		chestLabel.TextColor3 = THEME.Gold
		chestStroke.Color = THEME.Gold
		chestStroke.Thickness = 3
		chestFill.BackgroundColor3 = THEME.Gold
		chestPill.Active = true
	else
		chestLabel.Text = ("%s in %s"):format(
			chest.NextTitle or "Chest",
			ProgressionConfig.FormatDuration(target - elapsed)
		)
		chestLabel.TextColor3 = THEME.White
		chestStroke.Color = THEME.Locked
		chestStroke.Thickness = 2
		chestFill.BackgroundColor3 = THEME.Accent
		chestPill.Active = true
	end
end

chestPill.MouseButton1Click:Connect(function()
	local chest = state.Chest
	if not chest then
		NotificationService.Info("Your playtime chest is still loading.", {
			Title = "Chest Still Loading",
			Key = "chest-loading",
		})
		return
	end

	local elapsed = (chest.Elapsed or 0) + (os.clock() - chestSyncedAt)
	if elapsed < (chest.NextAt or math.huge) then
		NotificationService.Info(("%s unlocks in %s."):format(
			chest.NextTitle or "Your next chest",
			ProgressionConfig.FormatDuration((chest.NextAt or elapsed) - elapsed)
		), {
			Title = "Playtime Chest Charging",
			Icon = chest.NextIcon or "🎁",
			Key = "chest-not-ready",
		})
		return
	end

	ClaimChestRemote:FireServer()
end)

-- A gentle pulse while a chest is waiting to be collected.
task.spawn(function()
	while true do
		task.wait(0.6)
		local chest = state.Chest
		if chest then
			local elapsed = (chest.Elapsed or 0) + (os.clock() - chestSyncedAt)
			if elapsed >= (chest.NextAt or math.huge) then
				tween(chestPill, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					BackgroundColor3 = THEME.BackgroundLight,
				}):Play()
				task.wait(0.3)
				tween(chestPill, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					BackgroundColor3 = THEME.Panel,
				}):Play()
			end
		end
	end
end)

-- =========================================================================
-- SERVER STATE
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	state.Daily = payload.Daily or state.Daily
	state.Quests = payload.Quests or state.Quests
	state.Rebirths = payload.Rebirths or state.Rebirths

	if payload.Chest then
		state.Chest = payload.Chest
		chestSyncedAt = os.clock()
	end

	refreshBadges()
	refreshChest()

	if openPanel == "Daily" then
		refreshDaily()
	elseif openPanel == "Quests" then
		refreshQuests()
	end
end)

-- Local ticker: keeps countdowns moving between server pushes.
task.spawn(function()
	while true do
		task.wait(1)

		refreshChest()

		if state.Daily and state.Daily.SecondsUntilReset then
			state.Daily.SecondsUntilReset = math.max(0, state.Daily.SecondsUntilReset - 1)
		end

		if openPanel == "Quests" then
			questResetLabel.Text = "New quests in "
				.. ProgressionConfig.FormatDuration(state.Daily and state.Daily.SecondsUntilReset or 0)
		elseif openPanel == "Daily" then
			refreshDaily()
		end
	end
end)

-- =========================================================================
-- RETURNING-PLAYER DAILY NUDGE
-- =========================================================================
-- Returning players with a claim ready get one queued reminder. New players
-- already have guided onboarding and keep Daily as an explicit badge/button.

task.spawn(function()
	local deadline = os.clock() + 45
	while os.clock() < deadline do
		if state.Daily then
			break
		end
		task.wait(0.5)
	end

	if not state.Daily or not state.Daily.CanClaim then
		return
	end
	local journeyAttributeDeadline = os.clock() + 5
	while player:GetAttribute("FirstJourneyEligible") == nil and os.clock() < journeyAttributeDeadline do
		task.wait(0.1)
	end
	-- A newcomer already has Tutorial followed by the eight-minute Awakening
	-- journey. Keep Daily's unread badge/button available, but make opening it
	-- their choice instead of adding another mandatory post-tutorial frame.
	if player:GetAttribute("FirstJourneyEligible") ~= false then
		return
	end

	local lease = PresentationCoordinator.Acquire("DailyWelcome", {
		Priority = 46,
		QuietAfter = 0.8,
	})
	if not lease then
		return
	end

	local ok, err = xpcall(function()
		if state.Daily and state.Daily.CanClaim and openPanel == nil and not manualProgressionPanelOpened then
			showPanel("Daily", "DailyWelcome")
			-- This is an optional nudge, not a hard onboarding gate. Give the
			-- player time to claim/read it, then close it before the next queued
			-- frame. A manual close releases the slot immediately.
			local openedAt = os.clock()
			while openPanel == "Daily" and os.clock() - openedAt < 18 do
				task.wait(0.2)
			end
			if openPanel == "Daily" then
				closePanel()
				task.wait(0.25)
			end
		end
	end, debug.traceback)
	if not ok then
		if openPanel == "Daily" then
			closePanel()
		end
		warn("[ProgressionHud] Daily welcome presentation failed: " .. tostring(err))
	end

	PresentationCoordinator.Release(lease, 0.8)
end)

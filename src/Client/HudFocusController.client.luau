--[[
	HudFocusController (LocalScript -> StarterPlayerScripts)
	========================================================
	EssenceBound has intentionally grown into a feature-rich game, but putting
	every entry point on-screen at once makes the HUD read as a wall of choices.
	This controller adds progressive disclosure without deleting or replacing a
	single existing button:

	  * Core play stays visible: Upgrades, Zones, Rebirth, Shop and Storm.
	  * Collection/utility and advanced systems live behind one MORE control.
	  * Existing buttons keep their original parents, visuals and click handlers.
	  * Any visible child Badge is rolled up onto MORE while the drawer is shut.

	Keeping the real buttons in place is important. Several screens are authored
	in Studio while newer ones are created by separate LocalScripts, so cloning or
	reparenting them would risk breaking their bindings or responsive layouts.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local THEME = {
	Void = Color3.fromRGB(11, 8, 24),
	Panel = Color3.fromRGB(30, 20, 48),
	Raised = Color3.fromRGB(48, 31, 72),
	Accent = Color3.fromRGB(91, 220, 255),
	AccentOpen = Color3.fromRGB(255, 175, 62),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(182, 169, 205),
	Danger = Color3.fromRGB(245, 82, 105),
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

local function tween(instance: Instance, info: TweenInfo, props)
	return TweenService:Create(instance, info, props)
end

local function corner(parent: Instance, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 12) }, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
	}, parent)
end

local oldGui = playerGui:FindFirstChild("HudFocusController")
if oldGui then
	oldGui:Destroy()
end

-- DisplayOrder 59 keeps this control above the Studio-authored HUD while all
-- code-created modal backdrops (60+) naturally cover it when a panel opens.
local screenGui = new("ScreenGui", {
	Name = "HudFocusController",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 59,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local menuButton = new("TextButton", {
	Name = "MoreSystemsButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0.807, 0.235),
	Size = UDim2.fromScale(0.132, 0.058),
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 50,
}, screenGui)
corner(menuButton, UDim.new(0.28, 0))
local menuStroke = stroke(menuButton, THEME.Accent, 2, 0.08)
local menuScale = new("UIScale", { Scale = 1 }, menuButton)
new("UISizeConstraint", {
	MinSize = Vector2.new(110, 32),
	MaxSize = Vector2.new(190, 48),
}, menuButton)

new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(57, 37, 84)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 17, 40)),
	}),
	Rotation = 90,
}, menuButton)

local accentBar = new("Frame", {
	Name = "Accent",
	Size = UDim2.fromScale(0.035, 0.68),
	Position = UDim2.fromScale(0.035, 0.16),
	BackgroundColor3 = THEME.Accent,
	BorderSizePixel = 0,
	ZIndex = 51,
}, menuButton)
corner(accentBar, UDim.new(1, 0))

local iconLabel = new("TextLabel", {
	Name = "Icon",
	Position = UDim2.fromScale(0.09, 0.08),
	Size = UDim2.fromScale(0.2, 0.84),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "☰",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	ZIndex = 52,
}, menuButton)
new("UITextSizeConstraint", { MinTextSize = 10, MaxTextSize = 22 }, iconLabel)

local titleLabel = new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.3, 0.11),
	Size = UDim2.fromScale(0.49, 0.42),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "MORE",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 52,
}, menuButton)
new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 16 }, titleLabel)

local subtitleLabel = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.3, 0.53),
	Size = UDim2.fromScale(0.54, 0.28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "LOADING SYSTEMS",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 52,
}, menuButton)
new("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 10 }, subtitleLabel)

local chevron = new("TextLabel", {
	Name = "Chevron",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.91, 0.5),
	Size = UDim2.fromScale(0.12, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "›",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	ZIndex = 52,
}, menuButton)

local attentionBadge = new("Frame", {
	Name = "AttentionBadge",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1.035, -0.09),
	Size = UDim2.fromScale(0.15, 0.46),
	BackgroundColor3 = THEME.Danger,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 55,
}, menuButton)
corner(attentionBadge, UDim.new(1, 0))
stroke(attentionBadge, THEME.White, 1.5, 0.04)
local attentionScale = new("UIScale", { Scale = 1 }, attentionBadge)
new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "!",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 56,
}, attentionBadge)

-- These two tiny labels make the long legacy rail read as two deliberate
-- sections when the drawer is open, rather than one unbroken icon column.
local masteryHeader = new("TextLabel", {
	Name = "MasteryHeader",
	Position = UDim2.fromScale(0.946, 0.158),
	Size = UDim2.fromScale(0.052, 0.021),
	BackgroundColor3 = THEME.Void,
	BackgroundTransparency = 0.16,
	Font = Enum.Font.GothamBlack,
	Text = "MASTERY",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	Visible = false,
	ZIndex = 45,
}, screenGui)
corner(masteryHeader, UDim.new(1, 0))
new("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 9 }, masteryHeader)

local rewardsHeader = new("TextLabel", {
	Name = "RewardsHeader",
	Position = UDim2.fromScale(0.946, 0.57),
	Size = UDim2.fromScale(0.052, 0.021),
	BackgroundColor3 = THEME.Void,
	BackgroundTransparency = 0.16,
	Font = Enum.Font.GothamBlack,
	Text = "REWARDS",
	TextColor3 = THEME.AccentOpen,
	TextScaled = true,
	Visible = false,
	ZIndex = 45,
}, screenGui)
corner(rewardsHeader, UDim.new(1, 0))
new("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 9 }, rewardsHeader)

-- Every entry here points to an existing shortcut container. No panel or
-- trigger is rebuilt; Visible is the only property the focus layer controls.
local GENERATED_TARGETS = {
	{ Gui = "RebirthShopPanel", Child = "RebirthShopButton" },
	{ Gui = "SanctumPanel", Child = "SanctumButton" },
	{ Gui = "LeaderboardPanel", Child = "LeaderboardButton" },
	{ Gui = "AchievementsPanel", Child = "AchievementsButton" },
	{ Gui = "AstralForgePanel", Child = "ButtonHolder" },
	{ Gui = "ProgressionHud", Child = "ProgressionButtons" },
	{ Gui = "WheelPanel", Child = "ButtonHolder" },
	{ Gui = "GroupRewardPrompt", Child = "ButtonHolder" },
}

local managedTargets = setmetatable({}, { __mode = "k" })
local desiredVisibility = setmetatable({}, { __mode = "k" })
-- Roblox experiences can use deferred signal delivery. A plain boolean that is
-- cleared immediately after assigning Visible is therefore not a safe
-- re-entrancy guard: GetPropertyChangedSignal may run on the next scheduler
-- turn, see the guard already cleared, and record our temporary hidden state as
-- the system's real desired state. Keep the controller's last expected value
-- instead, so both immediate and arbitrarily deferred signals can identify it.
local controllerVisibility = setmetatable({}, { __mode = "k" })
local hookedButtons = setmetatable({}, { __mode = "k" })
local drawerOpen = false
local setDrawerOpen

local function navKey(name: string): string
	return string.lower(tostring(name)):gsub("button", ""):gsub("%s+", "")
end

local function applyTargetVisibility(target: GuiObject)
	local shouldShow = drawerOpen and desiredVisibility[target] ~= false
	if target.Visible == shouldShow then
		return
	end

	controllerVisibility[target] = shouldShow
	target.Visible = shouldShow
end

local function hookButton(button: Instance)
	if hookedButtons[button] or not button:IsA("GuiButton") then
		return
	end
	hookedButtons[button] = true
	button.Activated:Connect(function()
		-- Let the button's original handler open its panel first, then return the
		-- HUD to focused mode behind the modal.
		task.defer(function()
			if drawerOpen then
				setDrawerOpen(false)
			end
		end)
	end)
end

local function manageTarget(target: Instance?)
	if not target or not target:IsA("GuiObject") or managedTargets[target] then
		return
	end
	managedTargets[target] = true
	desiredVisibility[target] = target.Visible

	hookButton(target)
	for _, descendant in ipairs(target:GetDescendants()) do
		hookButton(descendant)
	end
	target.DescendantAdded:Connect(hookButton)

	target:GetPropertyChangedSignal("Visible"):Connect(function()
		if controllerVisibility[target] == target.Visible then
			return
		end
		desiredVisibility[target] = target.Visible
		if not drawerOpen and target.Visible then
			applyTargetVisibility(target)
		end
	end)

	applyTargetVisibility(target)
end

local function discoverTargets()
	-- Studio-authored secondary navigation. Core progression entries remain
	-- visible, while reference/settings tools join the MORE drawer.
	local mainGui = playerGui:FindFirstChild("MainGui")
	local right = mainGui and mainGui:FindFirstChild("Right")
	local holder = right and right:FindFirstChild("Holder")
	if holder then
		for _, child in ipairs(holder:GetChildren()) do
			local key = navKey(child.Name)
			if key == "index" or key == "inventory" or key == "settings" then
				manageTarget(child)
			end
		end
	end

	for _, spec in ipairs(GENERATED_TARGETS) do
		local gui = playerGui:FindFirstChild(spec.Gui)
		manageTarget(gui and gui:FindFirstChild(spec.Child))
	end
end

local function managedButtonCount(): number
	local count = 0
	for target in pairs(managedTargets) do
		if target.Parent then
			if target:IsA("GuiButton") then
				count += 1
			else
				for _, descendant in ipairs(target:GetDescendants()) do
					if descendant:IsA("GuiButton") then
						count += 1
					end
				end
			end
		end
	end
	return count
end

local function hiddenAttentionReady(): boolean
	for target in pairs(managedTargets) do
		if target.Parent then
			for _, descendant in ipairs(target:GetDescendants()) do
				if descendant:IsA("GuiObject")
					and string.find(string.lower(descendant.Name), "badge", 1, true)
					and descendant.Visible
				then
					return true
				end
			end
		end
	end
	return false
end

local hadAttention = false
local function refreshMenuCopy()
	local count = managedButtonCount()
	local hasAttention = hiddenAttentionReady()
	attentionBadge.Visible = not drawerOpen and hasAttention

	if drawerOpen then
		titleLabel.Text = "CLOSE"
		subtitleLabel.Text = "RETURN TO CORE"
	elseif hasAttention then
		titleLabel.Text = "MORE"
		subtitleLabel.Text = "REWARD READY"
	elseif count > 0 then
		titleLabel.Text = "MORE"
		subtitleLabel.Text = ("%d SYSTEM%s"):format(count, count == 1 and "" or "S")
	else
		titleLabel.Text = "MORE"
		subtitleLabel.Text = "LOADING SYSTEMS"
	end

	if hasAttention and not hadAttention and not drawerOpen then
		attentionScale.Scale = 0.65
		tween(attentionScale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
	hadAttention = hasAttention
end

setDrawerOpen = function(open: boolean)
	local wasOpen = drawerOpen
	drawerOpen = open

	for target in pairs(managedTargets) do
		if target.Parent then
			-- Capture the systems' own current visibility only on a real
			-- open -> closed transition. Newly discovered targets are already
			-- hidden in focused mode, so sampling them again there would replace
			-- their intended `true` state with our own temporary `false`.
			if not open and wasOpen then
				desiredVisibility[target] = target.Visible
			end
			applyTargetVisibility(target)
		end
	end

	masteryHeader.Visible = open
	rewardsHeader.Visible = open
	local color = open and THEME.AccentOpen or THEME.Accent
	tween(menuButton, TweenInfo.new(0.18), {
		BackgroundColor3 = open and THEME.Raised or THEME.Panel,
	}):Play()
	tween(menuStroke, TweenInfo.new(0.18), { Color = color }):Play()
	tween(accentBar, TweenInfo.new(0.18), { BackgroundColor3 = color }):Play()
	tween(iconLabel, TweenInfo.new(0.18), { TextColor3 = color }):Play()
	tween(chevron, TweenInfo.new(0.22, Enum.EasingStyle.Back), {
		Rotation = open and 180 or 0,
		TextColor3 = color,
	}):Play()
	refreshMenuCopy()
end

menuButton.MouseEnter:Connect(function()
	tween(menuScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.035,
	}):Play()
end)
menuButton.MouseLeave:Connect(function()
	tween(menuScale, TweenInfo.new(0.14, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
end)
menuButton.MouseButton1Down:Connect(function()
	tween(menuScale, TweenInfo.new(0.07), { Scale = 0.965 }):Play()
end)
menuButton.MouseButton1Up:Connect(function()
	tween(menuScale, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.035,
	}):Play()
end)
menuButton.Activated:Connect(function()
	setDrawerOpen(not drawerOpen)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and drawerOpen and input.KeyCode == Enum.KeyCode.Escape then
		setDrawerOpen(false)
	end
end)

playerGui.ChildAdded:Connect(function()
	task.defer(discoverTargets)
end)

-- Some code-created systems intentionally wait for server remotes before
-- constructing their shortcuts. A tiny periodic discovery pass makes startup
-- order irrelevant and also covers scripts restored by a Studio live sync.
task.spawn(function()
	while screenGui.Parent do
		discoverTargets()
		refreshMenuCopy()
		task.wait(0.75)
	end
end)

discoverTargets()
setDrawerOpen(false)

-- One restrained entrance pulse teaches the new hierarchy without adding
-- another persistent notification or tutorial step.
task.delay(2.5, function()
	if screenGui.Parent and not drawerOpen then
		tween(menuScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1.06,
		}):Play()
		task.delay(0.32, function()
			if menuScale.Parent then
				tween(menuScale, TweenInfo.new(0.24, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			end
		end)
	end
end)

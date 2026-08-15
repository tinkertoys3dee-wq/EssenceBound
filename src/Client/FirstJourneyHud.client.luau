--[[
	FirstJourneyHud (LocalScript -> StarterPlayerScripts)
	=====================================================
	A compact, cinematic companion for the first twelve minutes. The HUD sits
	in the lower-center breathing room above the relic timer bar, away from
	the main orb, left stats and right menu rail. It waits until the tutorial
	is finished/skipped, then reveals the current objective, its next reward,
	the full action-gated route and the twelve-minute resonance timer.

	Everything here is presentation. FirstJourneyService owns eligibility,
	progress, time, multipliers and rewards.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local FirstJourneyConfig = require(ReplicatedStorage:WaitForChild("FirstJourneyConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local remotesFolder = ReplicatedStorage:WaitForChild("FirstJourneyRemotes", 20)
if not remotesFolder then
	warn("FirstJourneyHud: journey remotes did not appear; HUD disabled this session")
	return
end

local SyncRemote = remotesFolder:WaitForChild("JourneySync", 10)
local EventRemote = remotesFolder:WaitForChild("JourneyEvent", 10)
local GetStateFunction = remotesFolder:WaitForChild("GetJourneyState", 10)
if not SyncRemote or not EventRemote or not GetStateFunction then
	warn("FirstJourneyHud: one or more journey remotes are missing")
	return
end

-- =========================================================================
-- THEME + HELPERS
-- =========================================================================

local THEME = {
	Void = Color3.fromRGB(4, 6, 14),
	Deep = Color3.fromRGB(10, 12, 27),
	Surface = Color3.fromRGB(20, 23, 43),
	Raised = Color3.fromRGB(35, 37, 62),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(181, 187, 211),
	Dim = Color3.fromRGB(102, 108, 138),
	Earth = Color3.fromRGB(105, 239, 158),
	Cyan = Color3.fromRGB(82, 221, 255),
	Shadow = Color3.fromRGB(194, 106, 255),
	Solar = Color3.fromRGB(255, 181, 58),
	SolarLight = Color3.fromRGB(255, 236, 164),
}

local HIDDEN_POSITION = UDim2.fromScale(0.5, 1.08)
local VISIBLE_POSITION = UDim2.fromScale(0.5, 0.875)
local COLLAPSED_POSITION = UDim2.fromScale(0.5, 0.885)

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

local function stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
	}, parent)
end

local function textConstraint(label: Instance, maxSize: number, minSize: number?)
	return new("UITextSizeConstraint", {
		MaxTextSize = maxSize,
		MinTextSize = minSize or 7,
	}, label)
end

local function tween(instance: Instance, info: TweenInfo, props)
	return TweenService:Create(instance, info, props)
end

local function stageAccent(stageIndex: number)
	local definition = FirstJourneyConfig.GetStage(stageIndex)
	return definition and definition.Accent or THEME.Solar
end

local function formatProgress(progress, target)
	return ("%s / %s"):format(
		tostring(math.max(0, math.floor(tonumber(progress) or 0))),
		tostring(math.max(1, math.floor(tonumber(target) or 1)))
	)
end

local oldGui = playerGui:FindFirstChild("FirstJourneyHud")
if oldGui then
	oldGui:Destroy()
end

-- =========================================================================
-- ROOT + AMBIENT FRAME
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "FirstJourneyHud",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 48,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local holder = new("Frame", {
	Name = "JourneyHolder",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = HIDDEN_POSITION,
	Size = UDim2.new(0.47, 0, 0, 132),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 100,
}, screenGui)
new("UISizeConstraint", {
	MinSize = Vector2.new(310, 118),
	MaxSize = Vector2.new(620, 132),
}, holder)

local aura = new("Frame", {
	Name = "Aura",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 18, 1, 18),
	BackgroundColor3 = THEME.Earth,
	BackgroundTransparency = 0.84,
	BorderSizePixel = 0,
	ZIndex = 99,
}, holder)
corner(aura, UDim.new(0, 22))
local auraScale = new("UIScale", { Scale = 1 }, aura)

local panel = new("Frame", {
	Name = "Panel",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Deep,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 100,
}, holder)
corner(panel, UDim.new(0, 18))
local panelStroke = stroke(panel, THEME.Earth, 2.2, 0.08)
local panelScale = new("UIScale", { Scale = 1 }, panel)

local panelGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(33, 38, 67)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(14, 17, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 15, 41)),
	}),
	Rotation = 12,
}, panel)

-- Broad diagonal light that drifts across each completed stage.
local sheen = new("Frame", {
	Name = "Sheen",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(-0.25, 0.5),
	Size = UDim2.fromScale(0.22, 2.2),
	Rotation = 18,
	BackgroundColor3 = THEME.White,
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	ZIndex = 101,
}, panel)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, sheen)

-- Decorative corner runes remain subtle enough not to compete with copy.
for index, runeText in ipairs({ "✦", "◇", "✧", "·" }) do
	local rune = new("TextLabel", {
		Name = "Rune" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(index <= 2 and 0.045 or 0.955, index % 2 == 0 and 0.82 or 0.2),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = runeText,
		TextColor3 = index % 2 == 0 and THEME.Shadow or THEME.Earth,
		TextScaled = true,
		TextTransparency = 0.62,
		ZIndex = 102,
	}, panel)
	tween(rune, TweenInfo.new(1.5 + index * 0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		TextTransparency = 0.88,
		Rotation = index % 2 == 0 and 80 or -80,
	}):Play()
end

local content = new("Frame", {
	Name = "Content",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 104,
}, panel)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 18),
	PaddingRight = UDim.new(0, 18),
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
}, content)

-- =========================================================================
-- HEADER
-- =========================================================================

local stageMedallion = new("Frame", {
	Name = "StageMedallion",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0, 14),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = THEME.Earth,
	BorderSizePixel = 0,
	ZIndex = 105,
}, content)
corner(stageMedallion, UDim.new(1, 0))
local medallionStroke = stroke(stageMedallion, THEME.White, 1.4, 0.18)
local medallionScale = new("UIScale", { Scale = 1 }, stageMedallion)

local stageIcon = new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✦",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 106,
}, stageMedallion)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
	PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
}, stageIcon)

local eyebrow = new("TextLabel", {
	Name = "Eyebrow",
	Position = UDim2.new(0, 38, 0, 0),
	Size = UDim2.new(0.52, -38, 0, 13),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "ESSENCE AWAKENING  •  1 / 6",
	TextColor3 = THEME.Earth,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 105,
}, content)
textConstraint(eyebrow, 11, 7)

local stageTitle = new("TextLabel", {
	Name = "StageTitle",
	Position = UDim2.new(0, 38, 0, 13),
	Size = UDim2.new(0.56, -38, 0, 17),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "First Spark",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 105,
}, content)
textConstraint(stageTitle, 16, 8)

local timerChip = new("Frame", {
	Name = "TimerChip",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -32, 0, 0),
	Size = UDim2.fromOffset(116, 29),
	BackgroundColor3 = THEME.Raised,
	BorderSizePixel = 0,
	ZIndex = 105,
}, content)
corner(timerChip, UDim.new(1, 0))
local timerStroke = stroke(timerChip, THEME.Earth, 1.4, 0.25)
local timerScale = new("UIScale", { Scale = 1 }, timerChip)

local timerLabel = new("TextLabel", {
	Name = "Timer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "✧ 0:00 / 12:00",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 106,
}, timerChip)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9),
	PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
}, timerLabel)
textConstraint(timerLabel, 13, 7)

local collapseButton = new("TextButton", {
	Name = "Collapse",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 1),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = Color3.fromRGB(43, 45, 68),
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "–",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	ZIndex = 108,
}, content)
corner(collapseButton, UDim.new(1, 0))
stroke(collapseButton, THEME.Dim, 1, 0.35)
Juice.ButtonFeel(collapseButton, { HoverScale = 1.09 })

-- =========================================================================
-- OBJECTIVE + PROGRESS
-- =========================================================================

local objectiveLabel = new("TextLabel", {
	Name = "Objective",
	Position = UDim2.new(0, 0, 0, 37),
	Size = UDim2.new(1, -82, 0, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Collect 3 essence orbs",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 105,
}, content)
textConstraint(objectiveLabel, 15, 8)

local countLabel = new("TextLabel", {
	Name = "Count",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 38),
	Size = UDim2.fromOffset(76, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "0 / 3",
	TextColor3 = THEME.Earth,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 105,
}, content)
textConstraint(countLabel, 14, 8)

local progressTrack = new("Frame", {
	Name = "ProgressTrack",
	Position = UDim2.new(0, 0, 0, 61),
	Size = UDim2.new(1, 0, 0, 9),
	BackgroundColor3 = Color3.fromRGB(44, 47, 72),
	BorderSizePixel = 0,
	ZIndex = 105,
}, content)
corner(progressTrack, UDim.new(1, 0))

local progressFill = new("Frame", {
	Name = "ProgressFill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Earth,
	BorderSizePixel = 0,
	ZIndex = 106,
}, progressTrack)
corner(progressFill, UDim.new(1, 0))
local progressGradient = new("UIGradient", {
	Color = ColorSequence.new(THEME.White, THEME.Earth),
}, progressFill)

local progressGlow = new("Frame", {
	Name = "ProgressGlow",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(1, 0.5),
	Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = THEME.Earth,
	BackgroundTransparency = 0.38,
	BorderSizePixel = 0,
	ZIndex = 105,
}, progressFill)
corner(progressGlow, UDim.new(1, 0))

local actionButton = new("TextButton", {
	Name = "StageAction",
	Position = UDim2.new(0, 0, 0, 74),
	Size = UDim2.new(0.23, -4, 0, 20),
	BackgroundColor3 = THEME.Earth,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "FIND ORBS",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 106,
}, content)
corner(actionButton, UDim.new(1, 0))
local actionStroke = stroke(actionButton, THEME.White, 1, 0.56)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, actionButton)
textConstraint(actionButton, 10, 6)
Juice.ButtonFeel(actionButton, { HoverScale = 1.035 })

local hintLabel = new("TextLabel", {
	Name = "Hint",
	Position = UDim2.new(0.24, 0, 0, 75),
	Size = UDim2.new(0.34, -4, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Move your collection ring over falling essence.",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 105,
}, content)
textConstraint(hintLabel, 11, 7)

local rewardLabel = new("TextLabel", {
	Name = "Reward",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 75),
	Size = UDim2.new(0.41, 0, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "NEXT  +75 Earth Essence",
	TextColor3 = THEME.SolarLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 105,
}, content)
textConstraint(rewardLabel, 11, 7)

local milestoneRow = new("Frame", {
	Name = "Milestones",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(0.74, 0, 0, 17),
	BackgroundTransparency = 1,
	ZIndex = 105,
}, content)
local milestoneLayout = new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, milestoneRow)

local milestonePips = {}
for index, stage in ipairs(FirstJourneyConfig.Stages) do
	local pip = new("Frame", {
		Name = stage.Id,
		LayoutOrder = index,
		Size = UDim2.fromOffset(14, 8),
		BackgroundColor3 = Color3.fromRGB(54, 58, 81),
		BorderSizePixel = 0,
		ZIndex = 106,
	}, milestoneRow)
	corner(pip, UDim.new(1, 0))
	local pipStroke = stroke(pip, THEME.Dim, 1, 0.55)
	milestonePips[index] = { Frame = pip, Stroke = pipStroke }
end

local rushRibbon = new("Frame", {
	Name = "RushRibbon",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, -0.03),
	Size = UDim2.fromOffset(214, 25),
	BackgroundColor3 = Color3.fromRGB(103, 48, 16),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 112,
}, holder)
corner(rushRibbon, UDim.new(1, 0))
local rushStroke = stroke(rushRibbon, THEME.Solar, 1.8, 0.05)
local rushText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "☀  2× AWAKENING RUSH  ☀",
	TextColor3 = THEME.SolarLight,
	TextScaled = true,
	ZIndex = 113,
}, rushRibbon)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
	PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
}, rushText)
textConstraint(rushText, 13, 7)
local rushScale = new("UIScale", { Scale = 1 }, rushRibbon)

-- =========================================================================
-- COLLAPSED COMPASS
-- =========================================================================

local collapsedButton = new("TextButton", {
	Name = "CollapsedCompass",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = HIDDEN_POSITION,
	Size = UDim2.new(0.36, 0, 0, 48),
	BackgroundColor3 = THEME.Deep,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 120,
}, screenGui)
new("UISizeConstraint", {
	MinSize = Vector2.new(260, 48),
	MaxSize = Vector2.new(470, 48),
}, collapsedButton)
corner(collapsedButton, UDim.new(1, 0))
local collapsedStroke = stroke(collapsedButton, THEME.Earth, 2, 0.08)
local collapsedScale = new("UIScale", { Scale = 1 }, collapsedButton)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(36, 40, 68), Color3.fromRGB(12, 15, 29)),
	Rotation = 90,
}, collapsedButton)

local collapsedIcon = new("TextLabel", {
	Position = UDim2.new(0, 8, 0, 7),
	Size = UDim2.fromOffset(34, 34),
	BackgroundColor3 = THEME.Earth,
	Font = Enum.Font.GothamBlack,
	Text = "✦",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 121,
}, collapsedButton)
corner(collapsedIcon, UDim.new(1, 0))

local collapsedTitle = new("TextLabel", {
	Position = UDim2.new(0, 50, 0, 5),
	Size = UDim2.new(1, -154, 0, 19),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "First Spark",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 121,
}, collapsedButton)
textConstraint(collapsedTitle, 14, 7)

local collapsedProgressTrack = new("Frame", {
	Position = UDim2.new(0, 50, 0, 29),
	Size = UDim2.new(1, -154, 0, 7),
	BackgroundColor3 = Color3.fromRGB(49, 52, 77),
	BorderSizePixel = 0,
	ZIndex = 121,
}, collapsedButton)
corner(collapsedProgressTrack, UDim.new(1, 0))
local collapsedProgressFill = new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Earth,
	BorderSizePixel = 0,
	ZIndex = 122,
}, collapsedProgressTrack)
corner(collapsedProgressFill, UDim.new(1, 0))

local collapsedTimer = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(88, 29),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "0:00 / 12:00",
	TextColor3 = THEME.Earth,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 121,
}, collapsedButton)
textConstraint(collapsedTimer, 13, 7)
Juice.ButtonFeel(collapsedButton, { HoverScale = 1.025 })

-- =========================================================================
-- LIVE STATE + PRESENTATION
-- =========================================================================

local currentState = nil
local syncedAtClock = os.clock()
local syncedSeconds = 0
local shown = false
local collapsed = false
local finalePlaying = false
local previousProgressRatio = 0
local stageCelebrationQueue = {}
local stageCelebrationWorker = false
local pendingFinale = nil

local function tutorialComplete()
	return player:GetAttribute("SeenTutorial") == true
end

local function currentActiveSeconds()
	if not currentState then
		return 0
	end
	local base = syncedSeconds
	if currentState.Eligible and not currentState.Completed then
		base += os.clock() - syncedAtClock
	end
	return math.min(tonumber(currentState.Duration) or FirstJourneyConfig.DurationSeconds, base)
end

local function setAccent(accent: Color3)
	aura.BackgroundColor3 = accent
	panelStroke.Color = accent
	stageMedallion.BackgroundColor3 = accent
	medallionStroke.Color = THEME.White
	eyebrow.TextColor3 = accent
	timerStroke.Color = accent
	countLabel.TextColor3 = accent
	progressFill.BackgroundColor3 = accent
	progressGlow.BackgroundColor3 = accent
	progressGradient.Color = ColorSequence.new(THEME.White, accent)
	actionButton.BackgroundColor3 = accent
	actionStroke.Color = THEME.White
	collapsedStroke.Color = accent
	collapsedIcon.BackgroundColor3 = accent
	collapsedTimer.TextColor3 = accent
	collapsedProgressFill.BackgroundColor3 = accent
end

local function updateMilestones(stageIndex: number)
	for index, pipData in ipairs(milestonePips) do
		if index < stageIndex then
			pipData.Frame.BackgroundColor3 = FirstJourneyConfig.Stages[index].Accent
			pipData.Stroke.Color = THEME.White
			pipData.Stroke.Transparency = 0.35
		elseif index == stageIndex then
			local accent = stageAccent(stageIndex)
			pipData.Frame.BackgroundColor3 = accent
			pipData.Stroke.Color = accent
			pipData.Stroke.Transparency = 0
		else
			pipData.Frame.BackgroundColor3 = Color3.fromRGB(54, 58, 81)
			pipData.Stroke.Color = THEME.Dim
			pipData.Stroke.Transparency = 0.55
		end
	end
end

local function revealHolder()
	if shown or not currentState or not tutorialComplete() or PresentationCoordinator.HasPendingPresentation() then
		return
	end
	if not currentState.Eligible or currentState.Completed then
		return
	end

	shown = true
	if collapsed then
		collapsedButton.Visible = true
		collapsedButton.Position = HIDDEN_POSITION
		tween(collapsedButton, TweenInfo.new(0.48, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = COLLAPSED_POSITION,
		}):Play()
	else
		holder.Visible = true
		holder.Position = HIDDEN_POSITION
		panelScale.Scale = 0.88
		tween(holder, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = VISIBLE_POSITION,
		}):Play()
		tween(panelScale, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
end

local function hideAll(instant: boolean?)
	shown = false
	if instant then
		holder.Visible = false
		collapsedButton.Visible = false
		holder.Position = HIDDEN_POSITION
		collapsedButton.Position = HIDDEN_POSITION
		return
	end

	tween(holder, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = HIDDEN_POSITION,
	}):Play()
	tween(collapsedButton, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = HIDDEN_POSITION,
	}):Play()
	task.delay(0.42, function()
		if not shown then
			holder.Visible = false
			collapsedButton.Visible = false
		end
	end)
end

-- This HUD is useful between beats, but it should not sit underneath a
-- tutorial, reward modal, discovery, or cinematic. Delay its return until
-- the coordinator has been truly idle so a quiet gap between two queued
-- presentations cannot make the panel flash on for a fraction of a second.
local presentationChangeVersion = 0
PresentationCoordinator.Changed:Connect(function()
	presentationChangeVersion += 1
	local version = presentationChangeVersion
	if PresentationCoordinator.HasPendingPresentation() then
		hideAll(false)
		return
	end

	task.spawn(function()
		if PresentationCoordinator.WaitUntilIdle(0.75, 4)
			and presentationChangeVersion == version
		then
			revealHolder()
		end
	end)
end)

local function applyState(payload)
	if type(payload) ~= "table" then
		return
	end

	currentState = payload
	syncedSeconds = math.max(0, tonumber(payload.ActiveSeconds) or 0)
	syncedAtClock = os.clock()

	if not payload.Eligible then
		hideAll(true)
		return
	end
	if payload.Completed then
		if not finalePlaying then
			hideAll(false)
		end
		return
	end

	local stage = payload.Stage or {}
	local stageIndex = math.max(1, tonumber(payload.StageIndex) or 1)
	local accent = stageAccent(stageIndex)
	setAccent(accent)

	stageIcon.Text = tostring(stage.Icon or "✦")
	stageTitle.Text = tostring(stage.Name or "Essence Awakening")
	eyebrow.Text = ("ESSENCE AWAKENING  •  %d / %d"):format(
		math.min(stageIndex, payload.StageCount or #FirstJourneyConfig.Stages),
		payload.StageCount or #FirstJourneyConfig.Stages
	)
	objectiveLabel.Text = tostring(stage.Objective or "Follow the resonance")
	hintLabel.Text = tostring(stage.Hint or "Keep collecting essence.")
	rewardLabel.Text = "NEXT  " .. tostring(stage.RewardText or payload.FinalRewardText or "Mystery reward")
	countLabel.Text = tostring(stage.ProgressText or formatProgress(stage.Progress, stage.Target))
	if stage.ProgressText then
		countLabel.Size = UDim2.fromOffset(136, 18)
		objectiveLabel.Size = UDim2.new(1, -144, 0, 20)
	else
		countLabel.Size = UDim2.fromOffset(76, 18)
		objectiveLabel.Size = UDim2.new(1, -82, 0, 20)
	end
	actionButton.Visible = stage.Action ~= nil
	actionButton.Active = stage.Locked ~= true
	if stage.Locked then
		actionButton.Text = "UNLOCKS " .. FirstJourneyConfig.FormatTime(stage.UnlockAt)
		actionButton.BackgroundColor3 = THEME.Raised
		actionButton.TextColor3 = THEME.Dim
	else
		actionButton.Text = tostring(stage.ActionLabel or "GO")
		actionButton.BackgroundColor3 = accent
		actionButton.TextColor3 = THEME.Void
	end
	if actionButton.Visible then
		hintLabel.Position = UDim2.new(0.24, 0, 0, 75)
		hintLabel.Size = UDim2.new(0.34, -4, 0, 18)
	else
		hintLabel.Position = UDim2.new(0, 0, 0, 75)
		hintLabel.Size = UDim2.new(0.57, -4, 0, 18)
	end
	collapsedTitle.Text = (payload.RushActive and "2× RUSH  •  " or "")
		.. tostring(stage.Name or "Essence Awakening")
	collapsedIcon.Text = tostring(stage.Icon or "✦")

	local target = math.max(1, tonumber(stage.Target) or 1)
	local ratio = math.clamp((tonumber(stage.Progress) or 0) / target, 0, 1)
	local duration = math.abs(ratio - previousProgressRatio) > 0.35 and 0.32 or 0.18
	previousProgressRatio = ratio
	tween(progressFill, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()
	tween(collapsedProgressFill, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(ratio, 1),
	}):Play()

	updateMilestones(stageIndex)
	rushRibbon.Visible = payload.RushActive == true
	if payload.RushActive then
		rushText.Text = ("☀  %g× AWAKENING RUSH  ☀"):format(tonumber(payload.RushMultiplier) or 2)
	end

	revealHolder()
end

local function setCollapsed(value: boolean)
	if collapsed == value or not currentState then
		return
	end
	collapsed = value

	if value then
		collapsedButton.Visible = true
		collapsedButton.Position = HIDDEN_POSITION
		tween(holder, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = HIDDEN_POSITION,
		}):Play()
		task.delay(0.18, function()
			if collapsed then
				holder.Visible = false
				tween(collapsedButton, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = COLLAPSED_POSITION,
				}):Play()
			end
		end)
	else
		holder.Visible = true
		holder.Position = HIDDEN_POSITION
		tween(collapsedButton, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Position = HIDDEN_POSITION,
		}):Play()
		task.delay(0.13, function()
			if not collapsed then
				collapsedButton.Visible = false
				tween(holder, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Position = VISIBLE_POSITION,
				}):Play()
			end
		end)
	end
end

collapseButton.MouseButton1Click:Connect(function()
	setCollapsed(true)
end)
collapsedButton.MouseButton1Click:Connect(function()
	setCollapsed(false)
end)

actionButton.Activated:Connect(function()
	local stage = currentState and currentState.Stage
	if type(stage) ~= "table" or stage.Locked == true then
		return
	end

	local action = stage.Action
	if action == "Upgrades" then
		local popupApi = rawget(_G, "PopupUI")
		if popupApi and type(popupApi.Open) == "function" then
			popupApi.Open("UpgradesPopup")
		end
	elseif action == "Prophecy" then
		local prophecyApi = rawget(_G, "EssenceboundProphecy")
		if prophecyApi and type(prophecyApi.Open) == "function" then
			prophecyApi.Open()
		end
	else
		-- Core-orb actions need screen space, not another modal.
		setCollapsed(true)
	end
end)

-- =========================================================================
-- STAGE + RUSH CELEBRATIONS
-- =========================================================================

local uiPop = Juice.FindSound("SFX/UI/UIPop")

local function sweepSheen()
	sheen.Position = UDim2.fromScale(-0.25, 0.5)
	tween(sheen, TweenInfo.new(0.72, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(1.25, 0.5),
	}):Play()
end

local function stageCelebration(payload)
	if not tutorialComplete() or PresentationCoordinator.HasPendingPresentation() then
		return
	end

	if collapsed then
		setCollapsed(false)
	end
	local accent = stageAccent(tonumber(payload.StageIndex) or 1)
	Juice.Punch(panelScale, 0.075, 0.32)
	Juice.Punch(medallionScale, 0.34, 0.35)
	Juice.PulseBackground(stageMedallion, THEME.White, 0.45)
	sweepSheen()

	local center = juiceLayer and Juice.CenterOf(panel, juiceLayer)
	if juiceLayer and center then
		Juice.Ring(juiceLayer, center, {
			Color = accent, StartSize = 55, EndSize = 260, Duration = 0.58, Thickness = 3,
		})
		Juice.Burst(juiceLayer, center, {
			Count = 14,
			Colors = { accent, THEME.White, THEME.SolarLight },
			Distance = 130,
			Duration = 0.7,
			Size = { 5, 11 },
		})
		Juice.FloatText(juiceLayer, center - UDim2.fromOffset(0, 45),
			(tostring(payload.Icon or "✦") .. "  " .. tostring(payload.StageName or "STAGE COMPLETE")), {
				Color = accent, Duration = 1.35, Rise = 42, TextSize = 27,
			})
		Juice.FloatText(juiceLayer, center + UDim2.fromOffset(0, 6), tostring(payload.RewardText or "Reward claimed"), {
			Color = THEME.SolarLight, Duration = 1.45, Rise = 34, TextSize = 17,
		})
	end

	for index = 0, 2 do
		task.delay(index * 0.08, function()
			Juice.PlaySound(uiPop, { Pitch = 0.92 + index * 0.16, Volume = 0.55 })
		end)
	end
end

local function rushCelebration(payload)
	if not tutorialComplete() or PresentationCoordinator.HasPendingPresentation() then
		return
	end

	rushRibbon.Visible = true
	Juice.Punch(rushScale, 0.22, 0.42)
	Juice.Punch(auraScale, 0.18, 0.5)
	Juice.Flash(juiceLayer or screenGui, {
		Color = THEME.Solar,
		Peak = 0.78,
		Duration = 0.72,
		ZIndex = 190,
	})

	if juiceLayer then
		local center = UDim2.fromScale(0.5, 0.33)
		for ringIndex = 1, 3 do
			task.delay((ringIndex - 1) * 0.11, function()
				Juice.Ring(juiceLayer, center, {
					Color = ringIndex == 2 and THEME.White or THEME.Solar,
					StartSize = 35 + ringIndex * 12,
					EndSize = 230 + ringIndex * 70,
					Duration = 0.65 + ringIndex * 0.1,
					Thickness = 4 - ringIndex * 0.6,
				})
			end)
		end
		Juice.Burst(juiceLayer, center, {
			Count = 24,
			Colors = { THEME.Solar, THEME.SolarLight, THEME.White, THEME.Shadow },
			Distance = 210,
			Duration = 0.9,
			Size = { 6, 14 },
		})
		Juice.FloatText(juiceLayer, center, "☀  2× AWAKENING RUSH  ☀", {
			Color = THEME.SolarLight, Duration = 1.8, Rise = 70, TextSize = 38,
		})
		Juice.FloatText(juiceLayer, center + UDim2.fromOffset(0, 52), "Every essence gain is doubled", {
			Color = THEME.White, Duration = 1.8, Rise = 48, TextSize = 19,
		})
	end

	for index = 0, 4 do
		task.delay(index * 0.09, function()
			Juice.PlaySound(uiPop, { Pitch = 0.78 + index * 0.13, Volume = 0.62 })
		end)
	end
end

local MINUTE_BEATS = {
	[1] = { Text = "RESONANCE 8%  •  THE BOND HOLDS", Color = THEME.Earth },
	[2] = { Text = "RESONANCE 17%  •  FIRST CACHE OPEN", Color = THEME.Cyan },
	[4] = { Text = "RESONANCE 33%  •  SURGE STABILIZED", Color = THEME.Solar },
	[5] = { Text = "RESONANCE 42%  •  BRONZE CACHE OPEN", Color = THEME.Cyan },
	[6] = { Text = "RESONANCE 50%  •  SECOND PHASE", Color = THEME.Shadow },
	[8] = { Text = "RESONANCE 67%  •  CHOOSE YOUR PATH", Color = THEME.Earth },
	[10] = { Text = "RESONANCE 83%  •  FINAL RUN", Color = THEME.SolarLight },
	[11] = { Text = "RESONANCE 92%  •  FINAL CHARGE", Color = THEME.Solar },
}

local function minuteCelebration(payload)
	if not tutorialComplete() or PresentationCoordinator.HasPendingPresentation() then
		return
	end
	local beat = MINUTE_BEATS[tonumber(payload.Minute)]
	if not beat then
		return
	end

	Juice.Punch(collapsed and collapsedScale or panelScale, 0.045, 0.25)
	Juice.Punch(timerScale, 0.12, 0.28)
	Juice.PulseBackground(timerChip, beat.Color, 0.5)
	local target = collapsed and collapsedButton or panel
	local center = juiceLayer and Juice.CenterOf(target, juiceLayer)
	if juiceLayer and center then
		Juice.Ring(juiceLayer, center, {
			Color = beat.Color,
			StartSize = 35,
			EndSize = 190,
			Duration = 0.48,
			Thickness = 2,
		})
		Juice.FloatText(juiceLayer, center - UDim2.fromOffset(0, 34), beat.Text, {
			Color = beat.Color,
			Duration = 1.25,
			Rise = 34,
			TextSize = 19,
		})
	end
	Juice.PlaySound(uiPop, { Pitch = 0.9 + (tonumber(payload.Minute) or 1) * 0.035, Volume = 0.32 })
end

-- =========================================================================
-- TWELVE-MINUTE FINALE
-- =========================================================================

local function playFinale(payload)
	if finalePlaying then
		return
	end
	finalePlaying = true
	local finaleLease = PresentationCoordinator.Acquire("AwakeningFinale", {
		Priority = 90,
		QuietAfter = 1,
	})
	if not finaleLease then
		finalePlaying = false
		return
	end
	hideAll(false)

	local overlay = new("TextButton", {
		Name = "AwakeningFinale",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = THEME.Void,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = true,
		Modal = true,
		Text = "",
		ZIndex = 500,
	}, screenGui)
	tween(overlay, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.08,
	}):Play()
	local visualGroup = new("CanvasGroup", {
		Name = "FinaleVisuals",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 0,
		ZIndex = 501,
	}, overlay)

	local vignette = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(22, 10, 43),
		BackgroundTransparency = 0.58,
		BorderSizePixel = 0,
		ZIndex = 501,
	}, visualGroup)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 7, 17)),
			ColorSequenceKeypoint.new(0.48, Color3.fromRGB(35, 15, 61)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(61, 28, 9)),
		}),
		Rotation = 20,
	}, vignette)

	for index = 1, 34 do
		local size = math.random(2, 7)
		local star = new("Frame", {
			Name = "Star" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(3, 97) / 100, math.random(4, 96) / 100),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = index % 4 == 0 and THEME.Shadow or (index % 3 == 0 and THEME.Solar or THEME.Cyan),
			BackgroundTransparency = math.random(25, 75) / 100,
			BorderSizePixel = 0,
			ZIndex = 502,
		}, visualGroup)
		corner(star, UDim.new(1, 0))
		tween(star, TweenInfo.new(0.7 + math.random() * 1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, math.random() * 0.8), {
			BackgroundTransparency = 0.92,
			Size = UDim2.fromOffset(size * 0.45, size * 0.45),
		}):Play()
	end

	local card = new("Frame", {
		Name = "FinaleCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.76),
		BackgroundTransparency = 1,
		ZIndex = 510,
	}, visualGroup)
	new("UISizeConstraint", {
		-- 300px tall still fits a common phone landscape viewport; the old
		-- 390px minimum would force the finale off-screen on those devices.
		MinSize = Vector2.new(300, 300),
		MaxSize = Vector2.new(800, 610),
	}, card)
	local cardScale = new("UIScale", { Scale = 0.48 }, card)
	tween(cardScale, TweenInfo.new(0.85, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local halo = new("Frame", {
		Name = "Halo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(250, 250),
		BackgroundColor3 = THEME.Solar,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 508,
	}, card)
	corner(halo, UDim.new(1, 0))
	local haloScale = new("UIScale", { Scale = 0.72 }, halo)
	tween(haloScale, TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Scale = 1.12,
	}):Play()

	for ringIndex = 1, 3 do
		local ring = new("Frame", {
			Name = "RuneRing" .. ringIndex,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.32),
			Size = UDim2.fromOffset(130 + ringIndex * 62, 130 + ringIndex * 62),
			BackgroundTransparency = 1,
			ZIndex = 511,
		}, card)
		corner(ring, UDim.new(1, 0))
		local ringLine = stroke(ring, ringIndex == 2 and THEME.Shadow or THEME.Solar, 2.6 - ringIndex * 0.35, 0.28 + ringIndex * 0.12)
		tween(ring, TweenInfo.new(4 + ringIndex * 1.2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
			Rotation = ringIndex % 2 == 0 and -360 or 360,
		}):Play()
		tween(ringLine, TweenInfo.new(1 + ringIndex * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
			Transparency = 0.7,
		}):Play()
	end

	local essenceIds = { "EarthEssence", "ShadowEssence", "SolarEssence" }
	for index, essenceId in ipairs(essenceIds) do
		local essence = EssenceConfig.Get(essenceId)
		local orbHolder = new("Frame", {
			Name = essenceId,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(index == 1 and 0.24 or (index == 2 and 0.76 or 0.5), index == 3 and 0.17 or 0.39),
			Size = UDim2.fromOffset(index == 3 and 104 or 84, index == 3 and 104 or 84),
			BackgroundColor3 = essence.Color,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 515,
		}, card)
		corner(orbHolder, UDim.new(1, 0))
		stroke(orbHolder, essence.Color, 2.3, 0.08)
		local orbScale = new("UIScale", { Scale = 0 }, orbHolder)
		task.delay(0.2 + index * 0.16, function()
			tween(orbScale, TweenInfo.new(0.62, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)

		new("ImageLabel", {
			Name = "OrbImage",
			Position = UDim2.fromScale(0.08, 0.08),
			Size = UDim2.fromScale(0.84, 0.84),
			BackgroundTransparency = 1,
			Image = essence.IconImage,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 516,
		}, orbHolder)
		local glyph = new("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = essence.Glyph,
			TextColor3 = THEME.White,
			TextScaled = true,
			TextTransparency = essence.IconImage ~= "" and 1 or 0,
			ZIndex = 516,
		}, orbHolder)
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16),
		}, glyph)
	end

	local title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.51),
		Size = UDim2.fromScale(0.96, 0.1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "ESSENCE AWAKENED",
		TextColor3 = THEME.SolarLight,
		TextScaled = true,
		TextStrokeColor3 = Color3.fromRGB(71, 28, 8),
		TextStrokeTransparency = 0.18,
		TextTransparency = 1,
		ZIndex = 520,
	}, card)
	textConstraint(title, 46, 20)
	task.delay(0.72, function()
		tween(title, TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			Position = UDim2.fromScale(0.5, 0.49),
		}):Play()
	end)

	local subtitle = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.605),
		Size = UDim2.fromScale(0.88, 0.05),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "The first convergence is complete. Your real ascent begins now.",
		TextColor3 = THEME.White,
		TextScaled = true,
		TextTransparency = 1,
		ZIndex = 520,
	}, card)
	textConstraint(subtitle, 17, 8)
	task.delay(0.98, function()
		tween(subtitle, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
		}):Play()
	end)

	local rewardCard = new("Frame", {
		Name = "Rewards",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.fromScale(0.82, 0.13),
		BackgroundColor3 = Color3.fromRGB(31, 25, 52),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		ZIndex = 520,
	}, card)
	corner(rewardCard, UDim.new(0, 14))
	stroke(rewardCard, THEME.Solar, 2, 0.14)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(55, 31, 66), Color3.fromRGB(35, 26, 20)),
		Rotation = 90,
	}, rewardCard)

	local rewardTitle = new("TextLabel", {
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.92, 0.3),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "AWAKENING CACHE CLAIMED",
		TextColor3 = THEME.SolarLight,
		TextScaled = true,
		ZIndex = 521,
	}, rewardCard)
	textConstraint(rewardTitle, 15, 8)
	local rewardCopy = new("TextLabel", {
		Position = UDim2.fromScale(0.04, 0.43),
		Size = UDim2.fromScale(0.92, 0.23),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = tostring(payload.RewardText or FirstJourneyConfig.FinalRewardText),
		TextColor3 = THEME.White,
		TextScaled = true,
		ZIndex = 521,
	}, rewardCard)
	textConstraint(rewardCopy, 15, 7)
	local potionCopy = new("TextLabel", {
		Position = UDim2.fromScale(0.04, 0.68),
		Size = UDim2.fromScale(0.92, 0.22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "⚡ " .. tostring(payload.PotionText or FirstJourneyConfig.PostJourneyPotion.Label),
		TextColor3 = THEME.Cyan,
		TextScaled = true,
		ZIndex = 521,
	}, rewardCard)
	textConstraint(potionCopy, 14, 7)

	local continueButton = new("TextButton", {
		Name = "Continue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.98),
		Size = UDim2.fromScale(0.52, 0.085),
		BackgroundColor3 = THEME.Solar,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBlack,
		Text = "BEGIN YOUR ASCENT  ›",
		TextColor3 = THEME.Void,
		TextScaled = true,
		Visible = false,
		ZIndex = 525,
	}, card)
	corner(continueButton, UDim.new(1, 0))
	stroke(continueButton, THEME.White, 2, 0.12)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18),
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	}, continueButton)
	textConstraint(continueButton, 18, 9)
	Juice.ButtonFeel(continueButton, { HoverScale = 1.045 })
	local continueScale = Juice.GetScale(continueButton)

	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true
		Juice.PlaySound(uiPop, { Pitch = 1.18, Volume = 0.65 })
		tween(cardScale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.76 }):Play()
		tween(overlay, TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		}):Play()
		tween(visualGroup, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
		}):Play()
		task.delay(0.5, function()
			if overlay.Parent then
				overlay:Destroy()
			end
			finalePlaying = false
			PresentationCoordinator.Release(finaleLease, 1)
		end)
	end

	continueButton.MouseButton1Click:Connect(dismiss)
	task.delay(1.25, function()
		if not overlay.Parent then
			return
		end
		continueButton.Visible = true
		if continueScale then
			continueScale.Scale = 0
			tween(continueScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
	task.delay(10, dismiss)

	Juice.Flash(visualGroup, { Color = THEME.Solar, Peak = 0.67, Duration = 0.9, ZIndex = 540 })
	for index = 0, 5 do
		task.delay(0.2 + index * 0.12, function()
			Juice.PlaySound(uiPop, { Pitch = 0.65 + index * 0.13, Volume = 0.72 })
		end)
	end

	task.delay(0.55, function()
		if not overlay.Parent then
			return
		end
		for ringIndex = 1, 4 do
			task.delay((ringIndex - 1) * 0.1, function()
				Juice.Ring(visualGroup, UDim2.fromScale(0.5, 0.36), {
					Color = ringIndex % 2 == 0 and THEME.Shadow or THEME.Solar,
					StartSize = 60,
					EndSize = 310 + ringIndex * 90,
					Duration = 0.75 + ringIndex * 0.13,
					Thickness = 4,
					ZIndex = 509,
				})
			end)
		end
		Juice.Burst(visualGroup, UDim2.fromScale(0.5, 0.36), {
			Count = 32,
			Colors = { THEME.Earth, THEME.Cyan, THEME.Shadow, THEME.Solar, THEME.White },
			Distance = 260,
			Duration = 1.1,
			Size = { 6, 15 },
			ZIndex = 530,
		})
	end)
end

local function startFinale(payload)
	task.spawn(function()
		local ok, err = xpcall(function()
			playFinale(payload)
		end, debug.traceback)
		if not ok then
			local orphanedOverlay = screenGui:FindFirstChild("AwakeningFinale")
			if orphanedOverlay then
				orphanedOverlay:Destroy()
			end
			finalePlaying = false
			PresentationCoordinator.ForceRelease("AwakeningFinale", 1)
			warn("[FirstJourneyHud] Finale presentation failed: " .. tostring(err))
		end
	end)
end

local function runStageCelebrationQueue()
	if stageCelebrationWorker then
		return
	end
	stageCelebrationWorker = true

	task.spawn(function()
		while #stageCelebrationQueue > 0 do
			local payload = table.remove(stageCelebrationQueue, 1)
			stageCelebration(payload)
			task.wait(1.15)

			-- The finale is the strongest beat. Once it is waiting, discard any
			-- additional rapid-fire stage cards rather than making the player sit
			-- through a queue before seeing the moment they just unlocked.
			if pendingFinale then
				table.clear(stageCelebrationQueue)
				break
			end
		end

		stageCelebrationWorker = false
		if pendingFinale then
			local finalePayload = pendingFinale
			pendingFinale = nil
			startFinale(finalePayload)
		end
	end)
end

local function enqueueStageCelebration(payload)
	table.insert(stageCelebrationQueue, payload)
	runStageCelebrationQueue()
end

-- =========================================================================
-- REMOTES + CLOCK
-- =========================================================================

SyncRemote.OnClientEvent:Connect(applyState)
EventRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Snapshot then
		applyState(payload.Snapshot)
	end

	if payload.Type == "StageCompleted" then
		enqueueStageCelebration(payload)
	elseif payload.Type == "RushStarted" then
		rushCelebration(payload)
	elseif payload.Type == "MinuteReached" then
		minuteCelebration(payload)
	elseif payload.Type == "JourneyCompleted" then
		if stageCelebrationWorker then
			pendingFinale = payload
		else
			startFinale(payload)
		end
	end
end)

player:GetAttributeChangedSignal("SeenTutorial"):Connect(function()
	if tutorialComplete() then
		revealHolder()
	end
end)

-- Smooth local timer between the server's five-second truth syncs. It never
-- advances progress or rewards; each sync snaps the baseline back to the
-- authoritative ActiveSeconds value.
task.spawn(function()
	while screenGui.Parent do
		task.wait(0.2)
		if currentState and currentState.Eligible and not currentState.Completed then
			local elapsed = currentActiveSeconds()
			local duration = tonumber(currentState.Duration) or FirstJourneyConfig.DurationSeconds
			local text = FirstJourneyConfig.FormatTime(elapsed) .. " / " .. FirstJourneyConfig.FormatTime(duration)
			timerLabel.Text = "✧ " .. text
			collapsedTimer.Text = text

			local rushSoon = elapsed >= FirstJourneyConfig.RushStartsAt - 30
				and elapsed < FirstJourneyConfig.RushStartsAt
			if rushSoon then
				local remaining = math.max(0, math.ceil(FirstJourneyConfig.RushStartsAt - elapsed))
				rushRibbon.Visible = true
				rushText.Text = ("☀  2× RUSH CHARGING  %ds  ☀"):format(remaining)
			elseif not currentState.RushActive then
				rushRibbon.Visible = false
			end
		end
	end
end)

-- Low-cost ambient pulse, stopped automatically with the ScreenGui.
task.spawn(function()
	while screenGui.Parent do
		local target = currentState and currentState.RushActive and 1.13 or 1.055
		tween(auraScale, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = target }):Play()
		task.wait(0.82)
		tween(auraScale, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Scale = 1 }):Play()
		task.wait(0.82)
	end
end)

-- RemoteFunction closes the listener-before-first-push race. Retry briefly
-- because PlayerDataHandler's DataStore fetch may still be finishing.
task.spawn(function()
	for _ = 1, 12 do
		local ok, payload = pcall(function()
			return GetStateFunction:InvokeServer()
		end)
		if ok and type(payload) == "table" then
			applyState(payload)
			return
		end
		task.wait(0.5)
	end
end)

--[[
	AstralForgePanel (LocalScript -> StarterPlayerScripts)
	======================================================
	A code-built, animated crafting chamber for chosen temporary infusions.
	The client never deducts currency or grants a boon: it selects a recipe,
	asks AstralForgeService to craft it, and only plays the convergence
	sequence after the server confirms the transaction.

	The chamber intentionally uses native Roblox UI -- layered gradients,
	rune rings, real Essence icon assets, energy beams, embers and responsive
	tweens -- so every visual arrives with source sync and needs no Studio-side
	frame setup.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AstralForgeConfig = require(ReplicatedStorage:WaitForChild("AstralForgeConfig"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("AstralForgeRemotes", 20)
if not remotesFolder then
	warn("AstralForgePanel: remotes never appeared -- forge UI disabled this session.")
	return
end

local SyncRemote = remotesFolder:WaitForChild("ForgeSync", 10)
local CraftFunction = remotesFolder:WaitForChild("CraftRecipe", 10)
local GetStateFunction = remotesFolder:WaitForChild("GetForgeState", 10)
if not SyncRemote or not CraftFunction or not GetStateFunction then
	warn("AstralForgePanel: required remotes are missing -- forge UI disabled this session.")
	return
end

-- =========================================================================
-- THEME + HELPERS
-- =========================================================================

local THEME = {
	Void = Color3.fromRGB(5, 7, 15),
	Background = Color3.fromRGB(14, 16, 29),
	Surface = Color3.fromRGB(25, 28, 45),
	SurfaceRaised = Color3.fromRGB(38, 40, 61),
	SurfaceDeep = Color3.fromRGB(9, 11, 22),
	Gold = Color3.fromRGB(255, 185, 65),
	GoldLight = Color3.fromRGB(255, 232, 160),
	Orange = Color3.fromRGB(255, 104, 47),
	Cyan = Color3.fromRGB(85, 224, 255),
	Purple = Color3.fromRGB(190, 104, 255),
	Green = Color3.fromRGB(76, 226, 148),
	Red = Color3.fromRGB(242, 87, 105),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(177, 178, 198),
	Dim = Color3.fromRGB(112, 113, 137),
	Locked = Color3.fromRGB(53, 53, 68),
}

local LAYOUT = {
	-- The fifth slot in the shared right shortcut rail: Prestige .213,
	-- Sanctum .295, Ranks .377, Achievements .459, Forge .541. Progression's
	-- three-button group starts at .63, leaving deliberate breathing room.
	ButtonAnchor = Vector2.new(0, 0.5),
	ButtonPosition = UDim2.fromScale(0.952, 0.541),
	ButtonSize = UDim2.fromScale(0.044, 0.062),
	PanelSize = UDim2.fromScale(0.72, 0.82),
	PanelMaxSize = Vector2.new(1080, 760),
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

local function corner(parent: Instance, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 12) }, parent)
end

local function stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return new("UIStroke", {
		Color = color or THEME.Gold,
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

local function formatTime(seconds: number): string
	return ProgressionConfig.FormatDuration(math.max(0, math.ceil(seconds)))
end

local function formatNumber(value: number): string
	return ProgressionConfig.FormatNumber(math.max(0, math.floor(tonumber(value) or 0)))
end

local function makeGradient(parent: Instance, colors, rotation: number?)
	return new("UIGradient", {
		Color = ColorSequence.new(colors),
		Rotation = rotation or 0,
	}, parent)
end

-- =========================================================================
-- ROOT + SHORTCUT
-- =========================================================================

local oldGui = playerGui:FindFirstChild("AstralForgePanel")
if oldGui then
	oldGui:Destroy()
end

local screenGui = new("ScreenGui", {
	Name = "AstralForgePanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 70,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local buttonHolder = new("Frame", {
	Name = "ButtonHolder",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundTransparency = 1,
	ZIndex = 55,
}, screenGui)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, buttonHolder)

local shortcutAura = new("Frame", {
	Name = "Aura",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1.35, 1.28),
	BackgroundColor3 = THEME.Orange,
	BackgroundTransparency = 0.82,
	ZIndex = 54,
}, buttonHolder)
corner(shortcutAura, UDim.new(0.28, 0))
local shortcutAuraScale = new("UIScale", { Scale = 1 }, shortcutAura)

local forgeButton = new("TextButton", {
	Name = "ForgeButton",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Surface,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 56,
}, buttonHolder)
corner(forgeButton, UDim.new(0.25, 0))
local forgeButtonStroke = stroke(forgeButton, THEME.Gold, 2.5, 0.08)
local shortcutGradient = makeGradient(forgeButton, {
	ColorSequenceKeypoint.new(0, Color3.fromRGB(91, 39, 35)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(43, 29, 45)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 20, 34)),
}, 135)

new("TextLabel", {
	Name = "Icon",
	Position = UDim2.fromScale(0, -0.01),
	Size = UDim2.fromScale(1, 0.72),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "⚒",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextStrokeColor3 = THEME.Orange,
	TextStrokeTransparency = 0.45,
	ZIndex = 57,
}, forgeButton)

local shortcutCaption = new("TextLabel", {
	Name = "Caption",
	Position = UDim2.fromScale(0.04, 0.69),
	Size = UDim2.fromScale(0.92, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "FORGE",
	TextColor3 = THEME.Gold,
	TextScaled = true,
	ZIndex = 57,
}, forgeButton)
textConstraint(shortcutCaption, 12, 6)

local shortcutStatus = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1.07, -0.07),
	Size = UDim2.fromScale(0.35, 0.27),
	BackgroundColor3 = THEME.Gold,
	Font = Enum.Font.GothamBlack,
	Text = "★",
	TextColor3 = THEME.Void,
	TextScaled = true,
	ZIndex = 59,
}, forgeButton)
corner(shortcutStatus, UDim.new(0.5, 0))
stroke(shortcutStatus, THEME.White, 1.4, 0.08)
local shortcutStatusScale = new("UIScale", { Scale = 1 }, shortcutStatus)

for index = 1, 3 do
	local spark = new("TextLabel", {
		Name = "Spark" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.18 + index * 0.2, index % 2 == 0 and 0.14 or 0.88),
		Size = UDim2.fromScale(0.2, 0.18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "✦",
		TextColor3 = index == 2 and THEME.Cyan or THEME.GoldLight,
		TextScaled = true,
		TextTransparency = 0.2,
		ZIndex = 58,
	}, buttonHolder)
	tween(spark, TweenInfo.new(0.7 + index * 0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, index * 0.1), {
		TextTransparency = 0.78,
		Rotation = index % 2 == 0 and 100 or -100,
	}):Play()
end

Juice.ButtonFeel(forgeButton, { HoverScale = 1.08 })

-- =========================================================================
-- MODAL SCAFFOLDING
-- =========================================================================

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.Void,
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 200,
}, screenGui)
backdrop:SetAttribute("PresentationModal", true)

local panelShadow = new("Frame", {
	Name = "Shadow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.516),
	Size = LAYOUT.PanelSize + UDim2.fromOffset(22, 22),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.42,
	Visible = false,
	ZIndex = 201,
}, screenGui)
corner(panelShadow, UDim.new(0.035, 0))
new("UISizeConstraint", { MaxSize = LAYOUT.PanelMaxSize + Vector2.new(22, 22) }, panelShadow)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = LAYOUT.PanelSize,
	BackgroundColor3 = THEME.Background,
	ClipsDescendants = true,
	Visible = false,
	ZIndex = 202,
}, screenGui)
corner(panel, UDim.new(0.035, 0))
local panelStroke = stroke(panel, THEME.Gold, 3, 0.06)
new("UISizeConstraint", { MaxSize = LAYOUT.PanelMaxSize }, panel)
local panelScale = new("UIScale", { Scale = 0.84 }, panel)
local panelGradient = makeGradient(panel, {
	ColorSequenceKeypoint.new(0, Color3.fromRGB(37, 25, 45)),
	ColorSequenceKeypoint.new(0.42, THEME.Background),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 18, 30)),
}, 128)

-- The normal chamber is intentionally broad. On short landscape phones,
-- claim more of the viewport so the recipe costs and craft action keep the
-- same padding instead of being compressed into one another.
local forgeViewportConnection = nil
local function updateForgeViewport()
	local camera = workspace.CurrentCamera
	local compact = camera ~= nil and camera.ViewportSize.Y < 500
	local size = compact and UDim2.fromScale(0.94, 0.92) or LAYOUT.PanelSize
	panel.Size = size
	panelShadow.Size = size + UDim2.fromOffset(22, 22)
end

local function bindForgeViewport()
	if forgeViewportConnection then
		forgeViewportConnection:Disconnect()
		forgeViewportConnection = nil
	end
	local camera = workspace.CurrentCamera
	if camera then
		forgeViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateForgeViewport)
	end
	updateForgeViewport()
end


workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindForgeViewport)
bindForgeViewport()

-- Fine inner border and corner ornaments give the panel a forged plate
-- silhouette instead of one flat rounded rectangle.
local innerBorder = new("Frame", {
	Name = "InnerBorder",
	Position = UDim2.fromScale(0.012, 0.016),
	Size = UDim2.fromScale(0.976, 0.968),
	BackgroundTransparency = 1,
	ZIndex = 203,
}, panel)
corner(innerBorder, UDim.new(0.03, 0))
stroke(innerBorder, THEME.GoldLight, 1, 0.76)

for index, position in ipairs({
	UDim2.fromScale(0.025, 0.025),
	UDim2.fromScale(0.975, 0.025),
	UDim2.fromScale(0.025, 0.975),
	UDim2.fromScale(0.975, 0.975),
}) do
	new("TextLabel", {
		Name = "CornerRune" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromScale(0.035, 0.045),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = index % 2 == 0 and "◆" or "◇",
		TextColor3 = THEME.Gold,
		TextScaled = true,
		TextTransparency = 0.12,
		Rotation = 45,
		ZIndex = 205,
	}, panel)
end

for index = 1, 26 do
	local x = ((index * 37) % 97) / 100
	local y = ((index * 53) % 89) / 100
	local star = new("TextLabel", {
		Name = "BackgroundSpark" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(index % 4 == 0 and 8 or 5, index % 4 == 0 and 8 or 5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = index % 5 == 0 and "✦" or "•",
		TextColor3 = index % 3 == 0 and THEME.Cyan or THEME.Gold,
		TextScaled = true,
		TextTransparency = 0.72,
		ZIndex = 203,
	}, panel)
	tween(star, TweenInfo.new(1.2 + (index % 5) * 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (index % 7) * 0.11), {
		TextTransparency = 0.25,
	}):Play()
end

-- =========================================================================
-- HEADER
-- =========================================================================

local header = new("Frame", {
	Name = "Header",
	Position = UDim2.fromScale(0.025, 0.022),
	Size = UDim2.fromScale(0.95, 0.105),
	BackgroundTransparency = 1,
	ZIndex = 210,
}, panel)

local crest = new("Frame", {
	Name = "Crest",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0, 0.5),
	Size = UDim2.fromScale(0.067, 0.76),
	BackgroundColor3 = THEME.SurfaceRaised,
	ZIndex = 211,
}, header)
corner(crest, UDim.new(0.25, 0))
stroke(crest, THEME.Gold, 2, 0.08)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, crest)
local crestText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "⚒",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextStrokeColor3 = THEME.Orange,
	TextStrokeTransparency = 0.5,
	ZIndex = 212,
}, crest)
new("UIPadding", {
	PaddingLeft = UDim.new(0.16, 0), PaddingRight = UDim.new(0.16, 0),
	PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0),
}, crestText)

local title = new("TextLabel", {
	Name = "Title",
	Position = UDim2.fromScale(0.08, 0.03),
	Size = UDim2.fromScale(0.46, 0.48),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "THE ASTRAL FORGE",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 211,
}, header)
textConstraint(title, 31, 12)

local subtitle = new("TextLabel", {
	Name = "Subtitle",
	Position = UDim2.fromScale(0.081, 0.54),
	Size = UDim2.fromScale(0.5, 0.28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "CHOOSE A CURRENT  •  FEED THE FLAME  •  BIND ITS POWER",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 211,
}, header)
textConstraint(subtitle, 13, 6)

local masteryPanel = new("Frame", {
	Name = "Mastery",
	Position = UDim2.fromScale(0.6, 0.06),
	Size = UDim2.fromScale(0.31, 0.76),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.1,
	ZIndex = 211,
}, header)
corner(masteryPanel, UDim.new(0.18, 0))
local masteryStroke = stroke(masteryPanel, THEME.Cyan, 1.5, 0.28)

local masteryName = new("TextLabel", {
	Name = "Name",
	Position = UDim2.fromScale(0.06, 0.08),
	Size = UDim2.fromScale(0.88, 0.34),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "FORGE MASTERY • LOADING",
	TextColor3 = THEME.Cyan,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 212,
}, masteryPanel)
textConstraint(masteryName, 14, 7)

local masteryTrack = new("Frame", {
	Name = "Track",
	Position = UDim2.fromScale(0.06, 0.51),
	Size = UDim2.fromScale(0.88, 0.18),
	BackgroundColor3 = THEME.Locked,
	ZIndex = 212,
}, masteryPanel)
corner(masteryTrack, UDim.new(0.5, 0))
local masteryFill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = THEME.Cyan,
	ZIndex = 213,
}, masteryTrack)
corner(masteryFill, UDim.new(0.5, 0))
makeGradient(masteryFill, {
	ColorSequenceKeypoint.new(0, THEME.Purple),
	ColorSequenceKeypoint.new(1, THEME.Cyan),
})
local masteryProgress = new("TextLabel", {
	Name = "Progress",
	Position = UDim2.fromScale(0.06, 0.72),
	Size = UDim2.fromScale(0.88, 0.2),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 212,
}, masteryPanel)
textConstraint(masteryProgress, 11, 6)

local closeButton = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.995, 0.02),
	Size = UDim2.fromScale(0.045, 0.46),
	BackgroundColor3 = THEME.SurfaceRaised,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "×",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 214,
}, header)
corner(closeButton, UDim.new(0.3, 0))
stroke(closeButton, THEME.Red, 1.5, 0.25)
Juice.ButtonFeel(closeButton, { HoverScale = 1.08 })

-- =========================================================================
-- RECIPE SIDEBAR
-- =========================================================================

local sidebar = new("Frame", {
	Name = "Recipes",
	Position = UDim2.fromScale(0.03, 0.145),
	Size = UDim2.fromScale(0.29, 0.815),
	BackgroundColor3 = THEME.SurfaceDeep,
	BackgroundTransparency = 0.06,
	ZIndex = 210,
}, panel)
corner(sidebar, UDim.new(0.035, 0))
stroke(sidebar, THEME.Gold, 1.5, 0.65)

new("TextLabel", {
	Name = "Heading",
	Position = UDim2.fromScale(0.06, 0.025),
	Size = UDim2.fromScale(0.88, 0.06),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "INFUSION RECIPES",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 211,
}, sidebar)

local recipeList = new("Frame", {
	Name = "List",
	Position = UDim2.fromScale(0.045, 0.105),
	Size = UDim2.fromScale(0.91, 0.83),
	BackgroundTransparency = 1,
	ZIndex = 211,
}, sidebar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.018, 0),
}, recipeList)

local recipeCards = {}
for index, recipe in ipairs(AstralForgeConfig.Recipes) do
	local card = new("TextButton", {
		Name = recipe.Id,
		Size = UDim2.fromScale(1, 0.232),
		BackgroundColor3 = THEME.Surface,
		BackgroundTransparency = 0.04,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = index,
		ZIndex = 212,
	}, recipeList)
	corner(card, UDim.new(0.1, 0))
	local cardStroke = stroke(card, recipe.Color, 1.5, 0.58)
	local cardGradient = makeGradient(card, {
		ColorSequenceKeypoint.new(0, recipe.GlowColor:Lerp(THEME.Surface, 0.55)),
		ColorSequenceKeypoint.new(0.42, THEME.Surface),
		ColorSequenceKeypoint.new(1, THEME.SurfaceDeep),
	}, 20)

	local iconPlate = new("Frame", {
		Name = "IconPlate",
		Position = UDim2.fromScale(0.035, 0.16),
		Size = UDim2.fromScale(0.22, 0.68),
		BackgroundColor3 = recipe.GlowColor,
		BackgroundTransparency = 0.5,
		ZIndex = 213,
	}, card)
	corner(iconPlate, UDim.new(0.22, 0))
	stroke(iconPlate, recipe.Color, 1.5, 0.15)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, iconPlate)
	new("TextLabel", {
		Name = "Rune",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = recipe.Rune,
		TextColor3 = recipe.Color,
		TextScaled = true,
		TextStrokeColor3 = THEME.Void,
		TextStrokeTransparency = 0.35,
		ZIndex = 214,
	}, iconPlate)

	local cardName = new("TextLabel", {
		Name = "RecipeName",
		Position = UDim2.fromScale(0.29, 0.13),
		Size = UDim2.fromScale(0.65, 0.27),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = recipe.Name,
		TextColor3 = THEME.White,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 213,
	}, card)
	textConstraint(cardName, 17, 7)

	local benefit = new("TextLabel", {
		Name = "Benefit",
		Position = UDim2.fromScale(0.29, 0.44),
		Size = UDim2.fromScale(0.65, 0.22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = recipe.Benefit,
		TextColor3 = recipe.Color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 213,
	}, card)
	textConstraint(benefit, 12, 6)

	local lockLabel = new("TextLabel", {
		Name = "Lock",
		Position = UDim2.fromScale(0.29, 0.7),
		Size = UDim2.fromScale(0.65, 0.17),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "",
		TextColor3 = THEME.Dim,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 213,
	}, card)
	textConstraint(lockLabel, 10, 6)

	local featuredBadge = new("TextLabel", {
		Name = "Featured",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1.02, -0.055),
		Size = UDim2.fromScale(0.32, 0.21),
		BackgroundColor3 = THEME.Gold,
		Font = Enum.Font.GothamBlack,
		Text = "★ -20%",
		TextColor3 = THEME.Void,
		TextScaled = true,
		Visible = false,
		ZIndex = 215,
	}, card)
	corner(featuredBadge, UDim.new(0.35, 0))
	textConstraint(featuredBadge, 10, 6)

	Juice.ButtonFeel(card, { HoverScale = 1.025 })
	recipeCards[recipe.Id] = {
		Card = card,
		Stroke = cardStroke,
		Gradient = cardGradient,
		Name = cardName,
		Lock = lockLabel,
		Featured = featuredBadge,
	}
end

local sidebarHint = new("TextLabel", {
	Name = "Hint",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.982),
	Size = UDim2.fromScale(0.9, 0.035),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "ONE ACTIVE INFUSION • CRAFTING REPLACES IT",
	TextColor3 = THEME.Dim,
	TextScaled = true,
	ZIndex = 211,
}, sidebar)
textConstraint(sidebarHint, 10, 5)

-- =========================================================================
-- FORGE CHAMBER
-- =========================================================================

local chamber = new("Frame", {
	Name = "Chamber",
	Position = UDim2.fromScale(0.34, 0.145),
	Size = UDim2.fromScale(0.63, 0.475),
	BackgroundColor3 = THEME.SurfaceDeep,
	ClipsDescendants = true,
	ZIndex = 210,
}, panel)
corner(chamber, UDim.new(0.04, 0))
local chamberStroke = stroke(chamber, THEME.Gold, 2, 0.25)
local chamberGradient = makeGradient(chamber, {
	ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 18, 38)),
	ColorSequenceKeypoint.new(0.48, Color3.fromRGB(12, 20, 34)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(23, 14, 30)),
}, 100)

-- Distant radial glow behind the machinery.
local chamberGlow = new("Frame", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromScale(0.54, 0.92),
	BackgroundColor3 = THEME.Orange,
	BackgroundTransparency = 0.88,
	ZIndex = 211,
}, chamber)
corner(chamberGlow, UDim.new(0.5, 0))
local chamberGlowScale = new("UIScale", { Scale = 1 }, chamberGlow)

local featuredBanner = new("Frame", {
	Name = "FeaturedBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.028),
	Size = UDim2.fromScale(0.68, 0.105),
	BackgroundColor3 = Color3.fromRGB(80, 48, 26),
	BackgroundTransparency = 0.05,
	ZIndex = 230,
}, chamber)
corner(featuredBanner, UDim.new(0.35, 0))
stroke(featuredBanner, THEME.Gold, 1.5, 0.16)
makeGradient(featuredBanner, {
	ColorSequenceKeypoint.new(0, Color3.fromRGB(63, 34, 36)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(103, 63, 29)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 28, 49)),
})
local featuredText = new("TextLabel", {
	Name = "Text",
	Position = UDim2.fromScale(0.04, 0.12),
	Size = UDim2.fromScale(0.92, 0.4),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "★ FEATURED FLAME",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 231,
}, featuredBanner)
textConstraint(featuredText, 14, 7)
local rotationText = new("TextLabel", {
	Name = "Rotation",
	Position = UDim2.fromScale(0.04, 0.54),
	Size = UDim2.fromScale(0.92, 0.28),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "20% OFF • 25% LONGER",
	TextColor3 = THEME.Gold,
	TextScaled = true,
	ZIndex = 231,
}, featuredBanner)
textConstraint(rotationText, 10, 5)

-- Energy beams converge into the center before the icons. Their opacity
-- pulses independently, making the chamber feel alive even while idle.
local beamSpecs = {
	{ Position = UDim2.fromScale(0.335, 0.59), Size = UDim2.fromScale(0.28, 0.012), Rotation = -9, Color = EssenceConfig.GetColor("Earth Essence") },
	{ Position = UDim2.fromScale(0.665, 0.59), Size = UDim2.fromScale(0.28, 0.012), Rotation = 9, Color = EssenceConfig.GetColor("Shadow Essence") },
	{ Position = UDim2.fromScale(0.5, 0.37), Size = UDim2.fromScale(0.23, 0.012), Rotation = 90, Color = EssenceConfig.GetColor("Solar Essence") },
}
local energyBeams = {}
for index, spec in ipairs(beamSpecs) do
	local beam = new("Frame", {
		Name = "EnergyBeam" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = spec.Position,
		Size = spec.Size,
		Rotation = spec.Rotation,
		BackgroundColor3 = spec.Color,
		BackgroundTransparency = 0.58,
		BorderSizePixel = 0,
		ZIndex = 213,
	}, chamber)
	corner(beam, UDim.new(0.5, 0))
	new("UIGradient", {
		Color = ColorSequence.new(spec.Color, THEME.White),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.55, 0.05),
			NumberSequenceKeypoint.new(1, 0.5),
		}),
	}, beam)
	tween(beam, TweenInfo.new(0.8 + index * 0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, index * 0.12), {
		BackgroundTransparency = 0.2,
	}):Play()
	table.insert(energyBeams, beam)
end

local coreRig = new("Frame", {
	Name = "CoreRig",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.56),
	Size = UDim2.fromScale(0.37, 0.66),
	BackgroundTransparency = 1,
	ZIndex = 216,
}, chamber)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, coreRig)

local outerRing = new("Frame", {
	Name = "OuterRuneRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.98, 0.98),
	BackgroundTransparency = 1,
	ZIndex = 216,
}, coreRig)
corner(outerRing, UDim.new(0.5, 0))
stroke(outerRing, THEME.Gold, 2, 0.28)
for index = 1, 12 do
	local angle = (index - 1) / 12 * math.pi * 2
	local rune = new("TextLabel", {
		Name = "Rune" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.48, 0.5 + math.sin(angle) * 0.48),
		Size = UDim2.fromScale(0.12, 0.12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = ({ "ᚠ", "ᚦ", "ᛋ", "ᛟ" })[((index - 1) % 4) + 1],
		TextColor3 = index % 3 == 0 and THEME.Cyan or THEME.GoldLight,
		TextScaled = true,
		TextTransparency = 0.12,
		Rotation = math.deg(angle) + 90,
		ZIndex = 217,
	}, outerRing)
	textConstraint(rune, 18, 7)
end

local middleRing = new("Frame", {
	Name = "MiddleRing",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.72, 0.72),
	BackgroundTransparency = 1,
	ZIndex = 218,
}, coreRig)
corner(middleRing, UDim.new(0.5, 0))
stroke(middleRing, THEME.Cyan, 2, 0.35)
for index = 1, 8 do
	local angle = (index - 1) / 8 * math.pi * 2
	new("Frame", {
		Name = "Tick" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.5, 0.5 + math.sin(angle) * 0.5),
		Size = UDim2.fromScale(0.07, 0.035),
		Rotation = math.deg(angle),
		BackgroundColor3 = index % 2 == 0 and THEME.Purple or THEME.Cyan,
		BorderSizePixel = 0,
		ZIndex = 219,
	}, middleRing)
end

local coreAura = new("Frame", {
	Name = "CoreAura",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.58, 0.58),
	BackgroundColor3 = THEME.Orange,
	BackgroundTransparency = 0.73,
	ZIndex = 220,
}, coreRig)
corner(coreAura, UDim.new(0.5, 0))
local coreAuraScale = new("UIScale", { Scale = 1 }, coreAura)

local forgeCore = new("Frame", {
	Name = "ForgeCore",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.44, 0.44),
	BackgroundColor3 = THEME.Orange,
	ZIndex = 221,
}, coreRig)
corner(forgeCore, UDim.new(0.28, 0))
local coreStroke = stroke(forgeCore, THEME.GoldLight, 3, 0.03)
local coreGradient = makeGradient(forgeCore, {
	ColorSequenceKeypoint.new(0, THEME.GoldLight),
	ColorSequenceKeypoint.new(0.28, THEME.Orange),
	ColorSequenceKeypoint.new(0.68, THEME.Purple),
	ColorSequenceKeypoint.new(1, THEME.Cyan),
}, 45)
local coreScale = new("UIScale", { Scale = 1 }, forgeCore)

local coreRune = new("TextLabel", {
	Name = "CoreRune",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "ᛟ",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextStrokeColor3 = THEME.Orange,
	TextStrokeTransparency = 0.2,
	ZIndex = 222,
}, forgeCore)
new("UIPadding", {
	PaddingLeft = UDim.new(0.18, 0), PaddingRight = UDim.new(0.18, 0),
	PaddingTop = UDim.new(0.1, 0), PaddingBottom = UDim.new(0.1, 0),
}, coreRune)

-- Physical anvil silhouette under the suspended core.
local anvilTop = new("Frame", {
	Name = "AnvilTop",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.88),
	Size = UDim2.fromScale(0.28, 0.045),
	BackgroundColor3 = Color3.fromRGB(90, 92, 112),
	BorderSizePixel = 0,
	ZIndex = 223,
}, chamber)
corner(anvilTop, UDim.new(0.4, 0))
makeGradient(anvilTop, {
	ColorSequenceKeypoint.new(0, THEME.GoldLight),
	ColorSequenceKeypoint.new(0.15, Color3.fromRGB(118, 118, 139)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 42, 59)),
}, 90)
local anvilStem = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.89),
	Size = UDim2.fromScale(0.08, 0.06),
	BackgroundColor3 = Color3.fromRGB(55, 57, 74),
	BorderSizePixel = 0,
	ZIndex = 222,
}, chamber)
local anvilBase = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.942),
	Size = UDim2.fromScale(0.19, 0.025),
	BackgroundColor3 = Color3.fromRGB(45, 46, 61),
	BorderSizePixel = 0,
	ZIndex = 222,
}, chamber)
corner(anvilBase, UDim.new(0.4, 0))

local essenceNodes = {}
local nodeSpecs = {
	{ Essence = EssenceConfig.Get("Earth Essence"), Position = UDim2.fromScale(0.16, 0.63) },
	{ Essence = EssenceConfig.Get("Shadow Essence"), Position = UDim2.fromScale(0.84, 0.63) },
	{ Essence = EssenceConfig.Get("Solar Essence"), Position = UDim2.fromScale(0.5, 0.25) },
}

for index, spec in ipairs(nodeSpecs) do
	local definition = spec.Essence
	local node = new("Frame", {
		Name = definition.Id .. "Node",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = spec.Position,
		Size = UDim2.fromScale(0.11, 0.18),
		BackgroundColor3 = definition.DeepColor,
		BackgroundTransparency = 0.08,
		ZIndex = 224,
	}, chamber)
	corner(node, UDim.new(0.3, 0))
	local nodeStroke = stroke(node, definition.Color, 2, 0.1)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, node)
	local nodeScale = new("UIScale", { Scale = 1 }, node)

	local aura = new("Frame", {
		Name = "Aura",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.35, 1.35),
		BackgroundColor3 = definition.Color,
		BackgroundTransparency = 0.8,
		ZIndex = 223,
	}, node)
	corner(aura, UDim.new(0.5, 0))

	new("TextLabel", {
		Name = "GlyphFallback",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = definition.Glyph,
		TextColor3 = definition.Color,
		TextScaled = true,
		ZIndex = 225,
	}, node)

	new("ImageLabel", {
		Name = "OrbIcon",
		Position = UDim2.fromScale(0.09, 0.09),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundTransparency = 1,
		Image = definition.IconImage,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 226,
	}, node)

	local label = new("TextLabel", {
		Name = "Name",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1.05),
		Size = UDim2.fromScale(1.8, 0.28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.upper(definition.ShortName),
		TextColor3 = definition.Color,
		TextScaled = true,
		TextStrokeColor3 = THEME.Void,
		TextStrokeTransparency = 0.2,
		ZIndex = 226,
	}, node)
	textConstraint(label, 11, 5)

	tween(aura, TweenInfo.new(0.9 + index * 0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, index * 0.1), {
		BackgroundTransparency = 0.93,
		Size = UDim2.fromScale(1.55, 1.55),
	}):Play()

	essenceNodes[index] = {
		Node = node,
		Scale = nodeScale,
		Stroke = nodeStroke,
		Definition = definition,
		Home = spec.Position,
	}
end

local chamberStatus = new("TextLabel", {
	Name = "ChamberStatus",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.985),
	Size = UDim2.fromScale(0.5, 0.04),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "THE FORGE AWAITS A RECIPE",
	TextColor3 = THEME.Dim,
	TextScaled = true,
	ZIndex = 230,
}, chamber)
textConstraint(chamberStatus, 11, 5)

-- =========================================================================
-- RECIPE DETAILS + CRAFT ACTION
-- =========================================================================

local details = new("Frame", {
	Name = "Details",
	Position = UDim2.fromScale(0.34, 0.635),
	Size = UDim2.fromScale(0.63, 0.325),
	BackgroundColor3 = THEME.Surface,
	BackgroundTransparency = 0.03,
	ZIndex = 210,
}, panel)
corner(details, UDim.new(0.055, 0))
local detailsStroke = stroke(details, THEME.Gold, 1.5, 0.36)

local selectedIcon = new("TextLabel", {
	Name = "Icon",
	Position = UDim2.fromScale(0.025, 0.045),
	Size = UDim2.fromScale(0.08, 0.24),
	BackgroundColor3 = THEME.SurfaceRaised,
	Font = Enum.Font.GothamBlack,
	Text = "ᚠ",
	TextColor3 = THEME.Gold,
	TextScaled = true,
	ZIndex = 212,
}, details)
corner(selectedIcon, UDim.new(0.23, 0))
local selectedIconStroke = stroke(selectedIcon, THEME.Gold, 1.5, 0.15)

local selectedName = new("TextLabel", {
	Name = "Name",
	Position = UDim2.fromScale(0.12, 0.04),
	Size = UDim2.fromScale(0.48, 0.13),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "VERDANT FLUX",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 212,
}, details)
textConstraint(selectedName, 22, 9)

local selectedBenefit = new("TextLabel", {
	Name = "Benefit",
	Position = UDim2.fromScale(0.12, 0.175),
	Size = UDim2.fromScale(0.55, 0.09),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = THEME.Green,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 212,
}, details)
textConstraint(selectedBenefit, 13, 6)

local durationBadge = new("TextLabel", {
	Name = "Duration",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.97, 0.045),
	Size = UDim2.fromScale(0.25, 0.115),
	BackgroundColor3 = THEME.SurfaceDeep,
	Font = Enum.Font.GothamBlack,
	Text = "⏳ --",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	ZIndex = 212,
}, details)
corner(durationBadge, UDim.new(0.4, 0))
stroke(durationBadge, THEME.Gold, 1.2, 0.4)
textConstraint(durationBadge, 13, 6)

local description = new("TextLabel", {
	Name = "Description",
	Position = UDim2.fromScale(0.025, 0.315),
	Size = UDim2.fromScale(0.95, 0.14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 212,
}, details)
textConstraint(description, 12, 6)

local costHolder = new("Frame", {
	Name = "Costs",
	Position = UDim2.fromScale(0.025, 0.49),
	Size = UDim2.fromScale(0.61, 0.19),
	BackgroundTransparency = 1,
	ZIndex = 212,
}, details)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0.018, 0),
}, costHolder)

local costChips = {}
for index, definition in ipairs(EssenceConfig.Ordered) do
	local chip = new("Frame", {
		Name = definition.Id,
		Size = UDim2.fromScale(0.31, 0.86),
		BackgroundColor3 = definition.DeepColor:Lerp(THEME.SurfaceDeep, 0.45),
		BackgroundTransparency = 0.08,
		Visible = false,
		LayoutOrder = index,
		ZIndex = 213,
	}, costHolder)
	corner(chip, UDim.new(0.35, 0))
	local chipStroke = stroke(chip, definition.Color, 1.2, 0.32)
	new("TextLabel", {
		Name = "Glyph",
		Position = UDim2.fromScale(0.06, 0.08),
		Size = UDim2.fromScale(0.25, 0.84),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = definition.Glyph,
		TextScaled = true,
		ZIndex = 214,
	}, chip)
	local amountLabel = new("TextLabel", {
		Name = "Amount",
		Position = UDim2.fromScale(0.32, 0.08),
		Size = UDim2.fromScale(0.63, 0.84),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "0",
		TextColor3 = definition.Color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 214,
	}, chip)
	textConstraint(amountLabel, 13, 6)
	costChips[definition.Id] = {
		Chip = chip,
		Stroke = chipStroke,
		Amount = amountLabel,
		Definition = definition,
	}
end

local statusLabel = new("TextLabel", {
	Name = "Status",
	Position = UDim2.fromScale(0.025, 0.72),
	Size = UDim2.fromScale(0.61, 0.19),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Muted,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 212,
}, details)
textConstraint(statusLabel, 11, 5)

local craftButton = new("TextButton", {
	Name = "Craft",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.fromScale(0.972, 0.67),
	Size = UDim2.fromScale(0.315, 0.46),
	BackgroundColor3 = THEME.Orange,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "IGNITE THE FORGE",
	TextColor3 = THEME.White,
	TextScaled = true,
	TextWrapped = true,
	TextStrokeColor3 = THEME.Void,
	TextStrokeTransparency = 0.55,
	ZIndex = 214,
}, details)
corner(craftButton, UDim.new(0.18, 0))
local craftButtonStroke = stroke(craftButton, THEME.GoldLight, 2.5, 0.05)
local craftGradient = makeGradient(craftButton, {
	ColorSequenceKeypoint.new(0, THEME.Gold),
	ColorSequenceKeypoint.new(0.38, THEME.Orange),
	ColorSequenceKeypoint.new(1, THEME.Purple),
}, 15)
local craftButtonScale = new("UIScale", { Scale = 1 }, craftButton)
new("UIPadding", {
	PaddingLeft = UDim.new(0.08, 0), PaddingRight = UDim.new(0.08, 0),
	PaddingTop = UDim.new(0.08, 0), PaddingBottom = UDim.new(0.08, 0),
}, craftButton)
textConstraint(craftButton, 19, 8)
Juice.ButtonFeel(craftButton, { HoverScale = 1.035 })

local craftSubtext = new("TextLabel", {
	Name = "Subtext",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.94),
	Size = UDim2.fromScale(0.9, 0.22),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "ONE ACTIVE INFUSION",
	TextColor3 = THEME.GoldLight,
	TextScaled = true,
	TextTransparency = 0.08,
	ZIndex = 215,
}, craftButton)
textConstraint(craftSubtext, 10, 5)

-- Shared bottom bar avoids adding another independently positioned timer
-- over the game. Clicking the active pill reopens the Forge.
local activePill = Juice.RegisterRelicPill(playerGui, {
	Name = "AstralForge",
	Icon = "⚒",
	Color = THEME.Gold,
	Order = 80,
})
local activePillButton = nil
if activePill then
	activePillButton = new("TextButton", {
		Name = "OpenForge",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 4,
	}, activePill.Pill)
end

-- =========================================================================
-- CLIENT STATE + RENDERING
-- =========================================================================

local state = {
	ServerNow = os.time(),
	FeaturedRecipeId = "",
	ActiveRecipeId = "",
	ExpiresAt = 0,
	ActiveDuration = 0,
	TotalCrafts = 0,
	RecipeCrafts = {},
	MasteryTier = 0,
	MasteryName = "Spark Initiate",
	NextMasteryCrafts = 3,
	Rebirths = tonumber(player:GetAttribute("Rebirths")) or 0,
}
local stateClock = os.clock()
local dataLoaded = false
local selectedRecipeId = AstralForgeConfig.Recipes[1].Id
local open = false
local crafting = false
local transientStatus = nil
local ringSpeed = 1
local emberAccumulator = 0

local function serverNow(): number
	return (tonumber(state.ServerNow) or os.time()) + (os.clock() - stateClock)
end

local function applyPayload(payload)
	if type(payload) ~= "table" then
		return
	end

	state.ServerNow = tonumber(payload.ServerNow) or os.time()
	stateClock = os.clock()
	state.FeaturedRecipeId = type(payload.FeaturedRecipeId) == "string" and payload.FeaturedRecipeId or ""
	state.ActiveRecipeId = type(payload.ActiveRecipeId) == "string" and payload.ActiveRecipeId or ""
	state.ExpiresAt = math.max(0, tonumber(payload.ExpiresAt) or 0)
	state.ActiveDuration = math.max(0, tonumber(payload.ActiveDuration) or 0)
	state.TotalCrafts = math.max(0, math.floor(tonumber(payload.TotalCrafts) or 0))
	state.RecipeCrafts = type(payload.RecipeCrafts) == "table" and payload.RecipeCrafts or {}
	state.MasteryTier = math.max(0, math.floor(tonumber(payload.MasteryTier) or 0))
	state.MasteryName = tostring(payload.MasteryName or "Spark Initiate")
	state.NextMasteryCrafts = tonumber(payload.NextMasteryCrafts)
	state.Rebirths = math.max(0, math.floor(tonumber(payload.Rebirths) or player:GetAttribute("Rebirths") or 0))
	dataLoaded = true
end

local function getBalance(definition): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(definition.Name)
	return stat and (tonumber(stat:GetAttribute("Quantity")) or 0) or 0
end

local function refresh()
	local now = serverNow()
	local featured = AstralForgeConfig.GetFeaturedRecipe(now)
	local selected = AstralForgeConfig.GetRecipe(selectedRecipeId) or AstralForgeConfig.Recipes[1]
	local rebirths = tonumber(player:GetAttribute("Rebirths")) or state.Rebirths or 0
	local active = AstralForgeConfig.GetRecipe(state.ActiveRecipeId)
	if not active or state.ExpiresAt <= now then
		active = nil
	end

	shortcutStatus.Visible = active ~= nil or featured ~= nil
	shortcutStatus.Text = active and "◆" or "★"
	shortcutStatus.BackgroundColor3 = active and active.Color or THEME.Gold
	forgeButtonStroke.Color = active and active.Color or THEME.Gold
	shortcutCaption.TextColor3 = active and active.Color or THEME.Gold

	if activePill then
		activePill.Pill.Visible = active ~= nil
		if active then
			local remaining = math.max(0, state.ExpiresAt - now)
			local duration = math.max(1, state.ActiveDuration)
			activePill.Label.Text = active.Icon .. "  " .. formatTime(remaining)
			activePill.Fill.Size = UDim2.fromScale(math.clamp(remaining / duration, 0, 1), 1)
			activePill.Fill.BackgroundColor3 = active.Color
			activePill.Stroke.Color = active.Color
		end
	end

	local mastery, nextMastery = AstralForgeConfig.GetMastery(state.TotalCrafts, state.RecipeCrafts)
	masteryName.Text = ("FORGE MASTERY %d • %s"):format(mastery.Tier, string.upper(mastery.Name))
	masteryName.TextColor3 = mastery.Tier >= 4 and THEME.GoldLight or THEME.Cyan
	masteryStroke.Color = mastery.Tier >= 4 and THEME.Gold or THEME.Cyan
	if nextMastery then
		local startCrafts = mastery.CraftsRequired
		local span = math.max(1, nextMastery.CraftsRequired - startCrafts)
		local progress = math.clamp((state.TotalCrafts - startCrafts) / span, 0, 1)
		masteryFill.Size = UDim2.fromScale(progress, 1)
		local requiredRecipe = AstralForgeConfig.GetRecipe(nextMastery.RequiredRecipeId)
		local hasRequiredRecipe = not requiredRecipe
			or (tonumber(state.RecipeCrafts[requiredRecipe.Id]) or 0) > 0
		if state.TotalCrafts >= nextMastery.CraftsRequired and not hasRequiredRecipe then
			masteryProgress.Text = "mastery test: forge " .. requiredRecipe.Name
			masteryFill.Size = UDim2.fromScale(1, 1)
		else
			masteryProgress.Text = ("%d / %d crafts • next: +%d%% duration"):format(
				state.TotalCrafts,
				nextMastery.CraftsRequired,
				math.floor((nextMastery.DurationMultiplier - 1) * 100 + 0.5)
			)
		end
	else
		masteryFill.Size = UDim2.fromScale(1, 1)
		masteryProgress.Text = ("%d crafts • maximum duration mastery"):format(state.TotalCrafts)
	end

	rotationText.Text = ("20%% OFF • 25%% LONGER • ROTATES IN %s"):format(
		formatTime(AstralForgeConfig.GetSecondsUntilRotation(now))
	)
	featuredText.Text = featured and ("★ FEATURED: " .. string.upper(featured.Name)) or "★ FEATURED FLAME"

	for recipeId, entry in pairs(recipeCards) do
		local recipe = AstralForgeConfig.GetRecipe(recipeId)
		local isSelected = recipeId == selectedRecipeId
		local isFeatured = featured and featured.Id == recipeId
		local isLocked = rebirths < recipe.RebirthRequired
		entry.Featured.Visible = isFeatured
		entry.Lock.Text = isLocked
			and ("🔒 REBIRTH %d REQUIRED"):format(recipe.RebirthRequired)
			or ((state.RecipeCrafts[recipeId] or 0) > 0
				and ("FORGED %d×"):format(state.RecipeCrafts[recipeId])
				or "READY TO DISCOVER")
		entry.Lock.TextColor3 = isLocked and THEME.Red or THEME.Dim
		entry.Stroke.Color = isSelected and THEME.White or recipe.Color
		entry.Stroke.Thickness = isSelected and 2.5 or 1.5
		entry.Stroke.Transparency = isSelected and 0.02 or 0.58
		entry.Card.BackgroundColor3 = isSelected and recipe.GlowColor:Lerp(THEME.Surface, 0.58) or THEME.Surface
		entry.Name.TextColor3 = isLocked and THEME.Muted or THEME.White
	end

	selectedIcon.Text = selected.Rune
	selectedIcon.TextColor3 = selected.Color
	selectedIcon.BackgroundColor3 = selected.GlowColor:Lerp(THEME.SurfaceDeep, 0.55)
	selectedIconStroke.Color = selected.Color
	selectedName.Text = string.upper(selected.Name)
	selectedBenefit.Text = selected.Benefit
	selectedBenefit.TextColor3 = selected.Color
	description.Text = selected.Description .. "  “" .. selected.Flavor .. ".”"
	detailsStroke.Color = selected.Color
	chamberStroke.Color = selected.Color
	coreRune.Text = selected.Rune
	coreStroke.Color = selected.Color
	chamberStatus.TextColor3 = selected.Color

	local prospectiveRecipeCrafts = table.clone(state.RecipeCrafts)
	prospectiveRecipeCrafts[selected.Id] = (tonumber(prospectiveRecipeCrafts[selected.Id]) or 0) + 1
	local prospectiveDuration = AstralForgeConfig.GetDuration(selected, state.TotalCrafts + 1, now, prospectiveRecipeCrafts)
	durationBadge.Text = "⏳ " .. formatTime(prospectiveDuration)
	durationBadge.TextColor3 = selected.Color

	local costs = AstralForgeConfig.GetCosts(selected, now)
	local affordable = true
	for _, definition in ipairs(EssenceConfig.Ordered) do
		local chip = costChips[definition.Id]
		local amount = tonumber(costs[definition.DataKey] or costs[definition.Name] or costs[definition.Id]) or 0
		chip.Chip.Visible = amount > 0
		if amount > 0 then
			local balance = getBalance(definition)
			local hasEnough = balance >= amount
			affordable = affordable and hasEnough
			chip.Amount.Text = formatNumber(amount)
			chip.Amount.TextColor3 = hasEnough and definition.Color or THEME.Red
			chip.Stroke.Color = hasEnough and definition.Color or THEME.Red
			chip.Stroke.Transparency = hasEnough and 0.32 or 0.02
		end
	end

	local locked = rebirths < selected.RebirthRequired
	local replacing = active and active.Id ~= selected.Id
	local refreshing = active and active.Id == selected.Id
	if crafting then
		craftButton.Text = "BINDING THE CURRENTS..."
		craftSubtext.Text = "THE FORGE IS IN MOTION"
		craftButton.BackgroundColor3 = THEME.Locked
		statusLabel.Text = transientStatus or "Essence is converging around the astral core."
		chamberStatus.Text = "CONVERGENCE IN PROGRESS"
	elseif locked then
		craftButton.Text = ("LOCKED • REBIRTH %d"):format(selected.RebirthRequired)
		craftSubtext.Text = "TAP TO SEE THE REQUIREMENT"
		craftButton.BackgroundColor3 = THEME.Locked
		statusLabel.Text = transientStatus or ("This recipe stabilizes at Rebirth %d."):format(selected.RebirthRequired)
		chamberStatus.Text = "RUNES UNSTABLE • MORE REBIRTHS REQUIRED"
	elseif not dataLoaded then
		craftButton.Text = "READING THE RUNES..."
		craftSubtext.Text = "FORGE RECORDS LOADING"
		craftButton.BackgroundColor3 = THEME.Locked
		statusLabel.Text = transientStatus or "Synchronizing your forge mastery and active infusion."
		chamberStatus.Text = "AWAKENING THE CHAMBER"
	else
		craftButton.Text = refreshing and "REFORGE & REFRESH" or (replacing and "REPLACE INFUSION" or "IGNITE THE FORGE")
		craftSubtext.Text = affordable and (featured and featured.Id == selected.Id and "FEATURED FLAME BONUS ACTIVE" or "SERVER-BOUND CRAFT") or "TAP TO SEE WHAT IS MISSING"
		craftButton.BackgroundColor3 = affordable and selected.GlowColor or THEME.Locked
		statusLabel.Text = transientStatus
			or (replacing and ("Crafting will replace " .. active.Name .. ".")
				or (refreshing and "Recasting refreshes the timer from now."
					or "Only one Forge infusion can be active at a time."))
		chamberStatus.Text = active and (string.upper(active.Name) .. " • " .. formatTime(state.ExpiresAt - now) .. " REMAINING") or "THE FORGE AWAITS YOUR ESSENCE"
	end

	craftButton.Active = not crafting
	craftButtonStroke.Color = selected.Color
end

-- =========================================================================
-- OPEN / CLOSE + SELECTION
-- =========================================================================

local function requestFreshState()
	task.spawn(function()
		local ok, payload = pcall(function()
			return GetStateFunction:InvokeServer()
		end)
		if ok and type(payload) == "table" then
			applyPayload(payload)
		end
		refresh()
	end)
end

local function closePanel()
	if not open or crafting then
		return
	end
	open = false
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local outTween = tween(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.84 })
	outTween:Play()
	outTween.Completed:Connect(function()
		if not open then
			panel.Visible = false
			panelShadow.Visible = false
			backdrop.Visible = false
		end
	end)
end

local function openPanel()
	if open then
		return
	end
	if not PresentationCoordinator.CanOpenModal() then
		return
	end
	open = true
	transientStatus = nil
	refresh()
	requestFreshState()

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	panelShadow.Visible = true
	panel.Visible = true
	panelScale.Scale = 0.84
	tween(backdrop, TweenInfo.new(0.24), { BackgroundTransparency = 0.3 }):Play()
	tween(panelScale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Juice.Punch(Juice.GetScale(forgeButton), 0.09, 0.22)
end

forgeButton.Activated:Connect(openPanel)
if activePillButton then
	activePillButton.Activated:Connect(openPanel)
end
closeButton.Activated:Connect(closePanel)
backdrop.Activated:Connect(closePanel)

for recipeId, entry in pairs(recipeCards) do
	entry.Card.Activated:Connect(function()
		if crafting then
			return
		end
		selectedRecipeId = recipeId
		transientStatus = nil
		local recipe = AstralForgeConfig.GetRecipe(recipeId)
		if recipe then
			Juice.Punch(Juice.GetScale(entry.Card), 0.06, 0.16)
			tween(coreRune, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextColor3 = recipe.Color,
				Rotation = coreRune.Rotation + 90,
			}):Play()
		end
		refresh()
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.Escape then
		closePanel()
	end
end)

_G.EssenceboundForge = {
	Open = openPanel,
	Close = closePanel,
	IsOpen = function()
		return open
	end,
}

-- =========================================================================
-- AMBIENT + CRAFT ANIMATION
-- =========================================================================

local uiPop = Juice.FindSound("SFX/UI/UIPop")

local function spawnEmber(color: Color3?)
	if not panel.Visible then
		return
	end
	local startX = 0.34 + math.random() * 0.32
	local ember = new("Frame", {
		Name = "ForgeEmber",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(startX, 0.84 + math.random() * 0.08),
		Size = UDim2.fromOffset(math.random(3, 7), math.random(3, 7)),
		BackgroundColor3 = color or (math.random() > 0.5 and THEME.Gold or THEME.Orange),
		BackgroundTransparency = 0.05,
		Rotation = math.random(0, 90),
		ZIndex = 229,
	}, chamber)
	corner(ember, UDim.new(0.5, 0))
	local drift = (math.random() - 0.5) * 0.18
	local rise = tween(ember, TweenInfo.new(0.85 + math.random() * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(startX + drift, 0.2 + math.random() * 0.25),
		BackgroundTransparency = 1,
		Rotation = ember.Rotation + math.random(-180, 180),
		Size = UDim2.fromOffset(1, 1),
	})
	rise:Play()
	rise.Completed:Connect(function()
		ember:Destroy()
	end)
end

RunService.RenderStepped:Connect(function(dt)
	if not screenGui.Parent then
		return
	end
	shortcutGradient.Rotation = (shortcutGradient.Rotation + dt * 11) % 360
	panelGradient.Rotation = (panelGradient.Rotation + dt * 1.8) % 360
	if panel.Visible then
		outerRing.Rotation = (outerRing.Rotation + dt * 17 * ringSpeed) % 360
		middleRing.Rotation = (middleRing.Rotation - dt * 25 * ringSpeed) % 360
		coreGradient.Rotation = (coreGradient.Rotation + dt * 24 * ringSpeed) % 360
		chamberGradient.Rotation = (chamberGradient.Rotation + dt * 3) % 360
		craftGradient.Rotation = (craftGradient.Rotation + dt * 8) % 360
		emberAccumulator += dt * (crafting and 4 or 1)
		if emberAccumulator >= 0.22 then
			emberAccumulator = 0
			spawnEmber(crafting and (AstralForgeConfig.GetRecipe(selectedRecipeId) or {}).Color or nil)
		end
	end
end)

tween(shortcutAuraScale, TweenInfo.new(1.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.14 }):Play()
tween(shortcutAura, TweenInfo.new(1.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.92 }):Play()
tween(shortcutStatusScale, TweenInfo.new(0.72, Enum.EasingStyle.Back, Enum.EasingDirection.InOut, -1, true), { Scale = 1.22 }):Play()
tween(chamberGlowScale, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.13 }):Play()
tween(coreAuraScale, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.18 }):Play()
tween(coreScale, TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()

local function playCraftReveal(recipe, result)
	ringSpeed = 8
	chamberStatus.Text = "THE CURRENTS ANSWER"
	transientStatus = "Binding " .. recipe.Name .. " into your Essence..."
	refresh()

	local center = Juice.CenterOf(forgeCore, chamber)
	for index, nodeData in ipairs(essenceNodes) do
		tween(nodeData.Node, TweenInfo.new(0.36, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0.5, 0.56),
		}):Play()
		task.delay((index - 1) * 0.08, function()
			Juice.Punch(nodeData.Scale, 0.24, 0.22)
			Juice.PlaySound(uiPop, { Pitch = 0.78 + index * 0.12, Volume = 0.45 })
		end)
	end

	Juice.Punch(coreScale, 0.28, 0.4)
	if center then
		Juice.Ring(chamber, center, {
			Color = recipe.Color,
			StartSize = 36,
			EndSize = 230,
			Duration = 0.62,
			Thickness = 4,
			ZIndex = 238,
		})
	end

	task.wait(0.42)
	if center then
		Juice.Burst(chamber, center, {
			Count = recipe.Id == "trinity_crown" and 34 or 24,
			Colors = { recipe.Color, recipe.GlowColor, THEME.GoldLight, THEME.Cyan, THEME.White },
			Distance = recipe.Id == "trinity_crown" and 210 or 155,
			Duration = 0.9,
			Size = { 5, 13 },
			ZIndex = 240,
		})
		Juice.Ring(chamber, center, {
			Color = recipe.GlowColor,
			StartSize = 48,
			EndSize = 290,
			Duration = 0.78,
			Thickness = 2,
			ZIndex = 239,
		})
		Juice.FloatText(chamber, center - UDim2.fromOffset(0, 34), recipe.Flavor, {
			Color = recipe.Color,
			Duration = 1.35,
			Rise = 78,
			TextSize = recipe.Id == "trinity_crown" and 30 or 25,
			ZIndex = 244,
		})
	end

	Juice.Flash(screenGui, {
		Color = recipe.Color,
		Peak = recipe.Id == "trinity_crown" and 0.5 or 0.68,
		Duration = recipe.Id == "trinity_crown" and 0.68 or 0.45,
		ZIndex = 260,
	})
	Juice.Shake(panel, recipe.Id == "trinity_crown" and 9 or 5, 0.36)
	Juice.Punch(coreScale, recipe.Id == "trinity_crown" and 0.48 or 0.34, 0.48)
	Juice.PlaySound(uiPop, { Pitch = recipe.Id == "trinity_crown" and 1.35 or 1.18, Volume = 0.9 })

	for _, nodeData in ipairs(essenceNodes) do
		tween(nodeData.Node, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = nodeData.Home,
		}):Play()
	end

	if result.MasteryTierUp then
		task.delay(0.18, function()
			Juice.FloatText(panel, UDim2.fromScale(0.735, 0.12), "★ FORGE MASTERY ASCENDED ★", {
				Color = THEME.GoldLight,
				Duration = 1.5,
				Rise = 62,
				TextSize = 27,
				ZIndex = 270,
			})
			Juice.Punch(Juice.GetScale(masteryPanel), 0.12, 0.38)
		end)
	end

	task.wait(0.62)
	ringSpeed = 1
	crafting = false
	transientStatus = recipe.Name .. " is bound. Make the flame count."
	refresh()
end

local function requestCraft()
	if crafting then
		return
	end
	if not dataLoaded then
		NotificationService.Info("Your forge records are still synchronizing.", {
			Title = "Reading the Runes",
			Icon = "⚒",
			Key = "forge-client-loading",
		})
		requestFreshState()
		return
	end

	local recipe = AstralForgeConfig.GetRecipe(selectedRecipeId)
	if not recipe then
		return
	end

	crafting = true
	transientStatus = "Presenting your Essence to the forge..."
	refresh()
	Juice.Punch(craftButtonScale, 0.08, 0.18)

	local ok, success, message, result = pcall(function()
		return CraftFunction:InvokeServer(recipe.Id)
	end)
	if not ok or not success then
		crafting = false
		transientStatus = ok and (message or "The forge refused the recipe.") or "The forge connection broke. Try again."
		if not ok then
			NotificationService.Error(transientStatus, {
				Title = "Forge Interrupted",
				Icon = "×",
				Key = "forge-network-error",
			})
		end
		Juice.Shake(craftButton, 5, 0.28)
		ringSpeed = 1
		refresh()
		return
	end

	if type(result) ~= "table" then
		crafting = false
		transientStatus = "The forge returned an unreadable result."
		NotificationService.Error(transientStatus, {
			Title = "Forge Result Missing",
			Key = "forge-invalid-result",
		})
		refresh()
		return
	end
	if type(result.State) == "table" then
		applyPayload(result.State)
	end
	task.spawn(playCraftReveal, recipe, result)
end

craftButton.Activated:Connect(requestCraft)

-- =========================================================================
-- SYNC + LIVE ECONOMY REFRESH
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	applyPayload(payload)
	if not crafting then
		transientStatus = nil
	end
	refresh()
end)

player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats", 20)
	if not leaderstats then
		return
	end
	for _, definition in ipairs(EssenceConfig.Ordered) do
		local stat = leaderstats:WaitForChild(definition.Name, 20)
		if stat then
			stat:GetAttributeChangedSignal("Quantity"):Connect(refresh)
		end
	end
end)

task.spawn(function()
	local ok, payload = pcall(function()
		return GetStateFunction:InvokeServer()
	end)
	if ok and type(payload) == "table" then
		applyPayload(payload)
	end
	refresh()
end)

task.spawn(function()
	while screenGui.Parent do
		task.wait(1)
		refresh()
	end
end)

refresh()

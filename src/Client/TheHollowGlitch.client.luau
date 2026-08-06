-- LocalScript (place in StarterPlayer > StarterPlayerScripts)
-- EssenceBound :: Ambient Glitches + The Hollowed One Milestone Event (v3 - Enhanced + New Features)
-- Builds on the bugfixed v2. See notes at the bottom for what's new and why.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local leaderstats = player:WaitForChild("leaderstats")
local earthEssenceStat = leaderstats:WaitForChild("Earth Essence")

local badgefunc = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("GrantBadge")

----------------------------------------------------------------
-- SHARED HELPERS
----------------------------------------------------------------
local GLITCH_CHARS = "!@#$%&*?/\\|~^#▓▒░"

local RP = game:GetService("ReplicatedStorage")
local loading = RP:WaitForChild("Remotes"):WaitForChild("LoadingDone")
loading.Event:Wait()

local function scrambleText(originalText, intensity)
	intensity = intensity or 0.35
	local chars = {}
	for i = 1, #originalText do
		local c = originalText:sub(i, i)
		if c ~= " " and math.random() < intensity then
			c = GLITCH_CHARS:sub(math.random(1, #GLITCH_CHARS), math.random(1, #GLITCH_CHARS))
		end
		table.insert(chars, c)
	end
	return table.concat(chars)
end

local function formatNumber(n)
	n = math.floor(n)
	local formatted = tostring(n)
	local k
	repeat
		formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return formatted
end

-- inserts thin spacing between characters for a "tracked out" eyebrow-text look
local function trackOut(text)
	local out = {}
	for i = 1, #text do
		table.insert(out, text:sub(i, i))
	end
	return table.concat(out, " ")
end

local function lerpColor(c1, c2, t)
	return Color3.new(
		c1.R + (c2.R - c1.R) * t,
		c1.G + (c2.G - c1.G) * t,
		c1.B + (c2.B - c1.B) * t
	)
end

-- NEW: dialogue lines can now use "%n" for the player's name in addition to "%s"
-- for the essence count. %n is substituted first (plain text substitution),
-- then %s is handled through string.format so existing lines keep working
-- untouched. A line needs neither, either, or both tokens.
local function formatLine(rawLine, essenceNow)
	local line = rawLine:gsub("%%n", player.Name)
	if rawLine:find("%%s") then
		line = string.format(line, formatNumber(essenceNow))
	end
	return line
end

----------------------------------------------------------------
-- PART 1: AMBIENT MICRO-GLITCH SYSTEM (small, local UI hiccups)
----------------------------------------------------------------
local AMBIENT_INTERVAL_MIN = 50
local AMBIENT_INTERVAL_MAX = 90
local AMBIENT_DURATION = 0.4
local AMBIENT_MIN_ELEMENTS = 1
local AMBIENT_MAX_ELEMENTS = 2
local AMBIENT_MAX_OFFSET = 5
local AMBIENT_MAX_ROTATION = 4

local ambientIntensified = false

local function getAllGuiObjects()
	local objects = {}
	for _, sg in ipairs(playerGui:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled and sg.Name ~= "HollowedOneUI" then
			for _, d in ipairs(sg:GetDescendants()) do
				if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("Frame") or d:IsA("ImageLabel") then
					table.insert(objects, d)
				end
			end
		end
	end
	return objects
end

local function captureState(obj)
	local state = { Position = obj.Position, Rotation = obj.Rotation }
	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		state.TextColor3 = obj.TextColor3
		state.Text = obj.Text
	end
	return state
end

local function restoreState(obj, state)
	if not obj or not obj.Parent then return end
	TweenService:Create(obj, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
		Position = state.Position, Rotation = state.Rotation,
	}):Play()
	if state.TextColor3 then obj.TextColor3 = state.TextColor3 end
	if state.Text then obj.Text = state.Text end
end

local function ambientGlitchEvent()
	local allObjects = getAllGuiObjects()
	if #allObjects == 0 then return end
	local numToGlitch = math.random(AMBIENT_MIN_ELEMENTS, AMBIENT_MAX_ELEMENTS)
	local affected = {}
	for i = 1, numToGlitch do
		local obj = allObjects[math.random(1, #allObjects)]
		local dup = false
		for _, e in ipairs(affected) do if e.obj == obj then dup = true break end end
		if not dup then
			local state = captureState(obj)
			local entry = { obj = obj, state = state, tween = nil }
			table.insert(affected, entry)
			local ox, oy = math.random(-AMBIENT_MAX_OFFSET, AMBIENT_MAX_OFFSET), math.random(-AMBIENT_MAX_OFFSET, AMBIENT_MAX_OFFSET)
			entry.tween = TweenService:Create(obj, TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), {
				Position = UDim2.new(state.Position.X.Scale, state.Position.X.Offset + ox, state.Position.Y.Scale, state.Position.Y.Offset + oy),
				Rotation = state.Rotation + math.random(-AMBIENT_MAX_ROTATION, AMBIENT_MAX_ROTATION),
			})
			entry.tween:Play()
			if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text ~= "" then
				obj.Text = scrambleText(state.Text, 0.3)
				if math.random() < 0.4 then obj.TextColor3 = Color3.fromRGB(255, 0, 0) end
			end
		end
	end
	task.delay(AMBIENT_DURATION, function()
		for _, e in ipairs(affected) do
			if e.tween then
				e.tween:Cancel()
			end
			restoreState(e.obj, e.state)
		end
	end)
end

task.spawn(function()
	while true do
		if ambientIntensified then
			task.wait(math.random(2, 5))
		else
			task.wait(math.random(AMBIENT_INTERVAL_MIN, AMBIENT_INTERVAL_MAX))
		end
		ambientGlitchEvent()
	end
end)

----------------------------------------------------------------
-- PART 2: THE HOLLOWED ONE — MILESTONE EVENT SYSTEM
----------------------------------------------------------------

-- >>> ASSET IDS: fill these in once you have art/sound. Full list at the bottom. <
local ASSETS = {
	ShroudTexture   = "rbxassetid://137064267248972", -- smoky/static veil, tiled, sits over the figure
	StaticTexture   = "rbxassetid://123290727098947", -- TV static/noise, used for glitch flicker bursts
	ScanlineTexture = "rbxassetid://102052518064370", -- thin horizontal scanline tile, subtle CRT feel
	VignetteTexture = "rbxassetid://98763414081982", -- radial dark gradient (transparent center -> black edges)
	GlowTexture     = "rbxassetid://101060370277727", -- soft radial white/colored glow (transparent center -> transparent edges, bright middle)
	FigureImages = {
		"rbxassetid://0", -- Tier 1
		"rbxassetid://0", -- Tier 2
		"rbxassetid://0", -- Tier 3
		"rbxassetid://0", -- Tier 4
		"rbxassetid://0", -- Tier 5
		"rbxassetid://0", -- Tier 6
	},
	AmbientDrone  = "rbxassetid://73194026034105", -- low ominous hum, loops while frame is up
	RevealStinger = "rbxassetid://101795937446775", -- short sting when the name reveals
	CrackSound    = "rbxassetid://136424791038267", -- sharp crack/glass-fracture sound for entrance flash
	WhisperSound  = "rbxassetid://140241113370120", -- optional: faint whisper layered under body text typing
	PremonitionWhisper= "rbxassetid://98528296092296", -- NEW: very quiet stinger for the premonition flicker	
}

local FULL_NAME = "THE HOLLOWED ONE"

local function getRevealedName(revealPercent)
	if revealPercent <= 0 then return "???" end
	if revealPercent >= 1 then return FULL_NAME end
	local chars = {}
	for i = 1, #FULL_NAME do
		local c = FULL_NAME:sub(i, i)
		if c == " " then
			table.insert(chars, " ")
		elseif math.random() <= revealPercent then
			table.insert(chars, c)
		else
			table.insert(chars, GLITCH_CHARS:sub(math.random(1, #GLITCH_CHARS), math.random(1, #GLITCH_CHARS)))
		end
	end
	return table.concat(chars)
end

----------------------------------------------------------------
-- MILESTONE DEFINITIONS
-- AccentColor evolves the whole event's color language per tier -
-- cool ash/grey early -> deepening blood red -> stark bone white at the end.
-- NEW: each tier now has one line using "%n" (the player's name) mixed into
-- its pool, so personalization surfaces sometimes but not predictably -
-- since only 3 of the pool get chosen per event.
----------------------------------------------------------------
local Milestones = {
	{
		Tier = 1, Threshold = 1000, NameRevealPercent = 0, ShroudTransparency = 0.05,
		Eyebrow = "SIGNAL DETECTED", AccentColor = Color3.fromRGB(120, 120, 130),
		Lines = {
			"Something stirs in the space between your clicks.",
			"%s fragments gathered. It has begun to notice.",
			"A presence, formless, watches from beyond the glass.",
			"Do you feel it yet? The weight of being seen?",
			"%n. I did not expect to learn your name so soon.",
		},
	},
	{
		Tier = 2, Threshold = 15000, NameRevealPercent = 0.2, ShroudTransparency = 0.18,
		Eyebrow = "PRESENCE CONFIRMED", AccentColor = Color3.fromRGB(150, 90, 90),
		Lines = {
			"%s essence now flows through you. It flows through Us as well.",
			"The Hollow... something... draws closer.",
			"Your hunger for essence is not unnoticed. It is admired. Or perhaps resented.",
			"Names are cages. I am not yet ready to be caged.",
			"Hello, %n. Yes - I know your name too.",
		},
	},
	{
		Tier = 3, Threshold = 100000, NameRevealPercent = 0.4, ShroudTransparency = 0.35,
		Eyebrow = "OBSERVATION ONGOING", AccentColor = Color3.fromRGB(170, 60, 55),
		Lines = {
			"%s. Such a small number, and yet you cling to it like salvation.",
			"I have watched a thousand hands grasp at essence exactly like yours.",
			"The Hollowed One remembers every collector. Even the ones who stop.",
			"Keep going. I want to see how far the hollow reaches.",
			"%n. A forgettable name, until it wasn't.",
		},
	},
	{
		Tier = 4, Threshold = 500000, NameRevealPercent = 0.65, ShroudTransparency = 0.55,
		ShakeIntensity = 0.3, Eyebrow = "PATTERN RECOGNIZED", AccentColor = Color3.fromRGB(190, 40, 40),
		Lines = {
			"%s essence claimed. Do you think you are accumulating, or being harvested?",
			"I see the shape of what you are becoming.",
			"Every fragment you take, something else grows quieter.",
			"You are doing so well. That is what concerns me.",
			"%n. That is what they call you. I prefer to simply call you mine.",
		},
	},
	{
		Tier = 5, Threshold = 2500000, NameRevealPercent = 0.85, ShroudTransparency = 0.72,
		ShakeIntensity = 0.5, Eyebrow = "CONCEALMENT ENDING", AccentColor = Color3.fromRGB(210, 25, 25),
		Lines = {
			"%s. I no longer need to hide the shape of my name from you.",
			"THE HOLLOWED ONE. Say it. It changes nothing, but say it.",
			"You have outpaced the others. Most stop here. Few understand why.",
			"The essence was never truly yours. It was only ever passing through.",
			"Do not look away, %n. I am almost done hiding.",
		},
	},
	{
		Tier = 6, Threshold = 10000000, NameRevealPercent = 1.0, ShroudTransparency = 0.92,
		ShakeIntensity = 0.8, Eyebrow = "NOTHING LEFT HIDDEN", AccentColor = Color3.fromRGB(235, 235, 230),
		Lines = {
			"%s essence. There is no higher number that will satisfy what you began.",
			"THE HOLLOWED ONE has finished watching. Now it simply waits.",
			"You have taken everything offered, and asked for more. Good.",
			"There is nothing left to reveal. Only what you do next.",
			"%n. There is nowhere left for either of us to hide.",
		},
	},
}
table.sort(Milestones, function(a, b) return a.Threshold < b.Threshold end)

local triggeredTiers = {}
local eventQueue = {}
local isEventActive = false
-- NEW: in-memory log of past encounters, viewable in-game (see PART 5 below).
local sightingsLog = {}

----------------------------------------------------------------
-- UI CONSTRUCTION
----------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HollowedOneUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000
screenGui.Parent = playerGui

-- ===== Full-screen dim + vignette + scanlines (sit under the frame, over the game) =====
local dimOverlay = Instance.new("Frame")
dimOverlay.Name = "DimOverlay"
dimOverlay.Size = UDim2.new(1, 0, 1, 0)
dimOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
dimOverlay.BackgroundTransparency = 1
dimOverlay.ZIndex = 5
dimOverlay.Parent = screenGui

local vignetteOverlay = Instance.new("ImageLabel")
vignetteOverlay.Name = "VignetteOverlay"
vignetteOverlay.Size = UDim2.new(1, 0, 1, 0)
vignetteOverlay.BackgroundTransparency = 1
vignetteOverlay.Image = ASSETS.VignetteTexture
vignetteOverlay.ImageColor3 = Color3.new(0, 0, 0)
vignetteOverlay.ImageTransparency = 1
vignetteOverlay.ScaleType = Enum.ScaleType.Stretch
vignetteOverlay.ZIndex = 6
vignetteOverlay.Parent = screenGui

local scanlineOverlay = Instance.new("ImageLabel")
scanlineOverlay.Name = "ScanlineOverlay"
scanlineOverlay.Size = UDim2.new(1, 0, 1, 0)
scanlineOverlay.BackgroundTransparency = 1
scanlineOverlay.Image = ASSETS.ScanlineTexture
scanlineOverlay.ImageTransparency = 1
scanlineOverlay.ScaleType = Enum.ScaleType.Tile
scanlineOverlay.TileSize = UDim2.new(0, 4, 0, 4)
scanlineOverlay.ZIndex = 7
scanlineOverlay.Parent = screenGui

-- ===== Crack flash layer: a handful of jagged lines that flash once on entrance =====
local crackLayer = Instance.new("Frame")
crackLayer.Name = "CrackLayer"
crackLayer.Size = UDim2.new(1, 0, 1, 0)
crackLayer.BackgroundTransparency = 1
crackLayer.ZIndex = 8
crackLayer.Visible = false
crackLayer.Parent = screenGui

local crackLines = {}
for i = 1, 7 do
	local line = Instance.new("Frame")
	line.Name = "Crack" .. i
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Size = UDim2.new(0, math.random(150, 500), 0, 2)
	line.Position = UDim2.new(math.random(20, 80) / 100, 0, math.random(10, 90) / 100, 0)
	line.Rotation = math.random(-80, 80)
	line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	line.BackgroundTransparency = 1
	line.BorderSizePixel = 0
	line.ZIndex = 8
	line.Parent = crackLayer
	table.insert(crackLines, line)
end

-- ===== NEW: Premonition flash label =====
-- Sits between the crack layer (8) and the real event frame (20+), so it
-- never visually competes with the actual milestone event. Used for a
-- split-second subliminal flicker that hints the next tier is close.
local premonitionLabel = Instance.new("TextLabel")
premonitionLabel.Name = "PremonitionLabel"
premonitionLabel.AnchorPoint = Vector2.new(0.5, 0.5)
premonitionLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
premonitionLabel.Size = UDim2.new(0.6, 0, 0, 46)
premonitionLabel.BackgroundTransparency = 1
premonitionLabel.Font = Enum.Font.Antique
premonitionLabel.Text = ""
premonitionLabel.TextColor3 = Color3.fromRGB(200, 40, 45)
premonitionLabel.TextTransparency = 1
premonitionLabel.TextScaled = true
premonitionLabel.ZIndex = 9
premonitionLabel.Parent = screenGui

-- ===== NEW: Watcher Mark — a persistent HUD glyph that appears the first =====
-- time the Hollowed One notices the player (Tier 1) and never fully leaves
-- again. Blinks occasionally. Changes at Tier 6 once nothing is hidden.
local watcherMark = Instance.new("TextLabel")
watcherMark.Name = "WatcherMark"
watcherMark.AnchorPoint = Vector2.new(1, 1)
watcherMark.Position = UDim2.new(1, -18, 1, -18)
watcherMark.Size = UDim2.new(0, 24, 0, 24)
watcherMark.BackgroundTransparency = 1
watcherMark.Font = Enum.Font.RobotoMono
watcherMark.Text = "◉"
watcherMark.TextColor3 = Color3.fromRGB(150, 30, 35)
watcherMark.TextTransparency = 1 -- hidden until Tier 1 fires
watcherMark.TextSize = 18
watcherMark.ZIndex = 15
watcherMark.Parent = screenGui

-- ===== Main descending frame =====
local eventFrame = Instance.new("Frame")
eventFrame.Name = "EventFrame"
eventFrame.AnchorPoint = Vector2.new(0.5, 0)
eventFrame.Position = UDim2.new(0.5, 0, -1.1, 0)
eventFrame.Size = UDim2.new(0.34, 0, 0.3, 0)
eventFrame.BackgroundColor3 = Color3.fromRGB(6, 5, 8)
eventFrame.BackgroundTransparency = 0.05
eventFrame.BorderSizePixel = 0
eventFrame.ZIndex = 20
eventFrame.Parent = screenGui

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MinSize = Vector2.new(330, 500)
sizeConstraint.MaxSize = Vector2.new(480, 740)
sizeConstraint.Parent = eventFrame

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 6)
frameCorner.Parent = eventFrame

-- animated glow stroke - color tweens per tier, thickness pulses gently
local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(90, 15, 20)
frameStroke.Thickness = 1.5
frameStroke.Transparency = 0.25
frameStroke.Parent = eventFrame

-- a second, larger, softer stroke behind it to fake an outer glow
local frameGlowStroke = Instance.new("UIStroke")
frameGlowStroke.Color = Color3.fromRGB(90, 15, 20)
frameGlowStroke.Thickness = 4
frameGlowStroke.Transparency = 0.75
frameGlowStroke.Parent = eventFrame

-- inner hairline for a "double border" engraved look
local innerLine = Instance.new("Frame")
innerLine.Name = "InnerLine"
innerLine.Size = UDim2.new(1, -14, 1, -14)
innerLine.Position = UDim2.new(0, 7, 0, 7)
innerLine.BackgroundTransparency = 1
innerLine.ZIndex = 20
innerLine.Parent = eventFrame

local innerStroke = Instance.new("UIStroke")
innerStroke.Color = Color3.fromRGB(60, 55, 55)
innerStroke.Thickness = 1
innerStroke.Transparency = 0.6
innerStroke.Parent = innerLine

-- corner brackets (built from thin frame "L" shapes at each corner)
local function buildCornerBracket(cornerAnchor, xSign, ySign)
	local holder = Instance.new("Frame")
	holder.Name = "CornerBracket"
	holder.AnchorPoint = cornerAnchor
	holder.Position = UDim2.new(cornerAnchor.X, xSign * 10, cornerAnchor.Y, ySign * 10)
	holder.Size = UDim2.new(0, 22, 0, 22)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 21
	holder.Parent = eventFrame

	local horiz = Instance.new("Frame")
	horiz.Size = UDim2.new(1, 0, 0, 2)
	horiz.Position = UDim2.new(0, 0, cornerAnchor.Y, 0)
	horiz.AnchorPoint = Vector2.new(0, cornerAnchor.Y)
	horiz.BackgroundColor3 = Color3.fromRGB(150, 30, 35)
	horiz.BorderSizePixel = 0
	horiz.ZIndex = 21
	horiz.Parent = holder

	local vert = Instance.new("Frame")
	vert.Size = UDim2.new(0, 2, 1, 0)
	vert.Position = UDim2.new(cornerAnchor.X, 0, 0, 0)
	vert.AnchorPoint = Vector2.new(cornerAnchor.X, 0)
	vert.BackgroundColor3 = Color3.fromRGB(150, 30, 35)
	vert.BorderSizePixel = 0
	vert.ZIndex = 21
	vert.Parent = holder

	return holder, {horiz, vert}
end

local cornerBrackets = {}
local cornerAccentPieces = {}
local specs = {
	{Vector2.new(0, 0), 1, 1},
	{Vector2.new(1, 0), -1, 1},
	{Vector2.new(0, 1), 1, -1},
	{Vector2.new(1, 1), -1, -1},
}
for _, s in ipairs(specs) do
	local holder, pieces = buildCornerBracket(s[1], s[2], s[3])
	table.insert(cornerBrackets, holder)
	for _, p in ipairs(pieces) do table.insert(cornerAccentPieces, p) end
end

-- ===== ContentColumn: holds ONLY the flowing/stacked content =====
-- Everything with a LayoutOrder must be parented to THIS, not eventFrame,
-- or it gets sucked into the list layout and breaks positioning.
local contentColumn = Instance.new("Frame")
contentColumn.Name = "ContentColumn"
contentColumn.Size = UDim2.new(1, 0, 1, 0)
contentColumn.BackgroundTransparency = 1
contentColumn.ZIndex = 20
contentColumn.Parent = eventFrame

local framePadding = Instance.new("UIPadding")
framePadding.PaddingTop = UDim.new(0, 22)
framePadding.PaddingBottom = UDim.new(0, 18)
framePadding.PaddingLeft = UDim.new(0, 20)
framePadding.PaddingRight = UDim.new(0, 20)
framePadding.Parent = contentColumn

-- ===== Animated diagonal stripe backdrop (subtle, behind all content) =====
-- Stays parented to eventFrame directly (NOT contentColumn) so it's
-- exempt from the list layout and can use its own manual Size/Position.
local stripeBackdrop = Instance.new("Frame")
stripeBackdrop.Name = "StripeBackdrop"
stripeBackdrop.Size = UDim2.new(2, 0, 2, 0)
stripeBackdrop.Position = UDim2.new(-0.5, 0, -0.5, 0)
stripeBackdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
stripeBackdrop.BackgroundTransparency = 1
stripeBackdrop.ZIndex = 18
stripeBackdrop.Parent = eventFrame

local stripeGradient = Instance.new("UIGradient")
stripeGradient.Rotation = 45
stripeGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.97),
	NumberSequenceKeypoint.new(0.5, 0.99),
	NumberSequenceKeypoint.new(1, 0.97),
})
stripeGradient.Color = ColorSequence.new(Color3.fromRGB(150, 30, 35))
stripeGradient.Parent = stripeBackdrop

local stripeAnimActive = false
local function startStripeAnimation()
	stripeAnimActive = true
	task.spawn(function()
		local t = 0
		while stripeAnimActive do
			t += 0.15
			stripeGradient.Rotation = 45 + math.sin(t) * 8
			task.wait(0.05)
		end
	end)
end
local function stopStripeAnimation()
	stripeAnimActive = false
end

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = contentColumn

-- ===== Eyebrow text (small tracked-out label above the figure) =====
local eyebrowLabel = Instance.new("TextLabel")
eyebrowLabel.Name = "EyebrowLabel"
eyebrowLabel.Size = UDim2.new(1, 0, 0, 16)
eyebrowLabel.BackgroundTransparency = 1
eyebrowLabel.Font = Enum.Font.RobotoMono
eyebrowLabel.Text = ""
eyebrowLabel.TextColor3 = Color3.fromRGB(150, 60, 60)
eyebrowLabel.TextSize = 12
eyebrowLabel.TextTransparency = 0.15
eyebrowLabel.LayoutOrder = 0
eyebrowLabel.ZIndex = 21
eyebrowLabel.Parent = contentColumn

-- ===== Figure container (deep layered stack) =====
local figureContainer = Instance.new("Frame")
figureContainer.Name = "FigureContainer"
figureContainer.Size = UDim2.new(0.68, 0, 0.4, 0)
figureContainer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
figureContainer.BackgroundTransparency = 0.15
figureContainer.ClipsDescendants = true
figureContainer.LayoutOrder = 1
figureContainer.ZIndex = 21
figureContainer.Parent = contentColumn

local figureCorner = Instance.new("UICorner")
figureCorner.CornerRadius = UDim.new(0, 6)
figureCorner.Parent = figureContainer

local figureFrameStroke = Instance.new("UIStroke")
figureFrameStroke.Color = Color3.fromRGB(90, 15, 20)
figureFrameStroke.Thickness = 1
figureFrameStroke.Transparency = 0.5
figureFrameStroke.Parent = figureContainer

-- soft radial glow sitting behind the figure, pulses gently ("breathing")
local glowBehind = Instance.new("ImageLabel")
glowBehind.Name = "GlowBehind"
glowBehind.AnchorPoint = Vector2.new(0.5, 0.5)
glowBehind.Position = UDim2.new(0.5, 0, 0.5, 0)
glowBehind.Size = UDim2.new(1.4, 0, 1.4, 0)
glowBehind.BackgroundTransparency = 1
glowBehind.Image = ASSETS.GlowTexture
glowBehind.ImageColor3 = Color3.fromRGB(120, 20, 25)
glowBehind.ImageTransparency = 0.8
glowBehind.ScaleType = Enum.ScaleType.Fit
glowBehind.ZIndex = 21
glowBehind.Parent = figureContainer

-- base figure art (swap per tier)
local figureImage = Instance.new("ImageLabel")
figureImage.Name = "FigureImage"
figureImage.Size = UDim2.new(1, 0, 1, 0)
figureImage.BackgroundTransparency = 1
figureImage.ScaleType = Enum.ScaleType.Fit
figureImage.Image = ""
figureImage.ZIndex = 22
figureImage.Parent = figureContainer

-- chromatic-aberration ghost copies (red/cyan offset), used only during glitch bursts
local chromaRed = figureImage:Clone()
chromaRed.Name = "ChromaRed"
chromaRed.ImageColor3 = Color3.fromRGB(255, 60, 60)
chromaRed.ImageTransparency = 1
chromaRed.ZIndex = 23
chromaRed.Parent = figureContainer

local chromaCyan = figureImage:Clone()
chromaCyan.Name = "ChromaCyan"
chromaCyan.ImageColor3 = Color3.fromRGB(60, 200, 255)
chromaCyan.ImageTransparency = 1
chromaCyan.ZIndex = 23
chromaCyan.Parent = figureContainer

-- veil layer 1 (close): heavier, tweens transparency most per tier
local shroudLayer = Instance.new("ImageLabel")
shroudLayer.Name = "ShroudLayer"
shroudLayer.Size = UDim2.new(1, 0, 1, 0)
shroudLayer.BackgroundTransparency = 1
shroudLayer.ScaleType = Enum.ScaleType.Tile
shroudLayer.TileSize = UDim2.new(0, 128, 0, 128)
shroudLayer.Image = ASSETS.ShroudTexture
shroudLayer.ImageColor3 = Color3.fromRGB(0, 0, 0)
shroudLayer.ImageTransparency = 0.05
shroudLayer.ZIndex = 24
shroudLayer.Parent = figureContainer

-- veil layer 2 (far): drifts slowly for a parallax "mist moving" feel, stays subtler
local shroudLayerFar = Instance.new("ImageLabel")
shroudLayerFar.Name = "ShroudLayerFar"
shroudLayerFar.Size = UDim2.new(1.4, 0, 1.4, 0)
shroudLayerFar.Position = UDim2.new(-0.2, 0, -0.2, 0)
shroudLayerFar.BackgroundTransparency = 1
shroudLayerFar.ScaleType = Enum.ScaleType.Tile
shroudLayerFar.TileSize = UDim2.new(0, 200, 0, 200)
shroudLayerFar.Image = ASSETS.ShroudTexture
shroudLayerFar.ImageColor3 = Color3.fromRGB(10, 5, 8)
shroudLayerFar.ImageTransparency = 0.35
shroudLayerFar.ZIndex = 23
shroudLayerFar.Parent = figureContainer

-- static/noise flicker burst layer
local staticOverlay = Instance.new("ImageLabel")
staticOverlay.Name = "StaticOverlay"
staticOverlay.Size = UDim2.new(1, 0, 1, 0)
staticOverlay.BackgroundTransparency = 1
staticOverlay.Image = ASSETS.StaticTexture
staticOverlay.ScaleType = Enum.ScaleType.Tile
staticOverlay.TileSize = UDim2.new(0, 256, 0, 256)
staticOverlay.ImageTransparency = 0.5
staticOverlay.Visible = false
staticOverlay.ZIndex = 25
staticOverlay.Parent = figureContainer

-- vertical vignette gradient inside the figure box, for depth
local figureGradient = Instance.new("UIGradient")
figureGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(60, 60, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
})
figureGradient.Rotation = 90
figureGradient.Parent = shroudLayer

-- ember particle emitter target (particles get parented here, clipped to the container)
local emberHolder = Instance.new("Frame")
emberHolder.Name = "EmberHolder"
emberHolder.Size = UDim2.new(1, 0, 1, 0)
emberHolder.BackgroundTransparency = 1
emberHolder.ZIndex = 26
emberHolder.Parent = figureContainer

-- ===== NEW: Eye glint that tracks the player's cursor =====
-- A small glinting "eye" that lives inside the mist and subtly follows the
-- mouse, like something inside the shroud is looking back at whatever
-- you're looking at. Purely procedural, no asset needed.
local eyeGlint = Instance.new("Frame")
eyeGlint.Name = "EyeGlint"
eyeGlint.AnchorPoint = Vector2.new(0.5, 0.5)
eyeGlint.Position = UDim2.new(0.5, 0, 0.42, 0)
eyeGlint.Size = UDim2.new(0, 6, 0, 6)
eyeGlint.BackgroundColor3 = Color3.fromRGB(255, 70, 60)
eyeGlint.BackgroundTransparency = 1
eyeGlint.BorderSizePixel = 0
eyeGlint.ZIndex = 25
eyeGlint.Parent = figureContainer

local eyeGlintCorner = Instance.new("UICorner")
eyeGlintCorner.CornerRadius = UDim.new(1, 0)
eyeGlintCorner.Parent = eyeGlint

local eyeGlintGlow = Instance.new("UIStroke")
eyeGlintGlow.Color = Color3.fromRGB(255, 120, 100)
eyeGlintGlow.Thickness = 2
eyeGlintGlow.Transparency = 0.5
eyeGlintGlow.Parent = eyeGlint

-- ===== Rotating rune ring (procedural, no assets needed) =====
local RUNE_GLYPHS = {"✦", "☥", "✧", "⌖", "⟁", "☖", "◈", "⟡", "✥", "⚝", "☒", "⌗"}

local runeRingHolder = Instance.new("Frame")
runeRingHolder.Name = "RuneRingHolder"
runeRingHolder.AnchorPoint = Vector2.new(0.5, 0.5)
runeRingHolder.Position = UDim2.new(0.5, 0, 0.5, 0)
runeRingHolder.Size = UDim2.new(1.15, 0, 1.15, 0)
runeRingHolder.BackgroundTransparency = 1
runeRingHolder.ZIndex = 27
runeRingHolder.Parent = figureContainer

local NUM_RUNES = 10
local runeLabels = {}
for i = 1, NUM_RUNES do
	local angle = (i / NUM_RUNES) * math.pi * 2
	local rune = Instance.new("TextLabel")
	rune.Name = "Rune" .. i
	rune.AnchorPoint = Vector2.new(0.5, 0.5)
	rune.Size = UDim2.new(0, 16, 0, 16)
	rune.BackgroundTransparency = 1
	rune.Font = Enum.Font.RobotoMono
	rune.Text = RUNE_GLYPHS[math.random(1, #RUNE_GLYPHS)]
	rune.TextColor3 = Color3.fromRGB(150, 30, 35)
	rune.TextTransparency = 0.35
	rune.TextSize = 14
	rune.ZIndex = 27
	rune.Parent = runeRingHolder
	rune:SetAttribute("Angle", angle)
	table.insert(runeLabels, rune)
end

local runeRingActive = false
local function startRuneRing()
	runeRingActive = true
	task.spawn(function()
		local t = 0
		while runeRingActive do
			t += 0.01
			for i, rune in ipairs(runeLabels) do
				local baseAngle = rune:GetAttribute("Angle")
				local angle = baseAngle + t * 0.3
				local radiusX, radiusY = 0.5, 0.5
				rune.Position = UDim2.new(0.5 + math.cos(angle) * radiusX, 0, 0.5 + math.sin(angle) * radiusY, 0)
				-- occasional glyph swap for a "shifting language" feel
				if math.random() < 0.003 then
					rune.Text = RUNE_GLYPHS[math.random(1, #RUNE_GLYPHS)]
				end
			end
			RunService.RenderStepped:Wait()
		end
	end)
end
local function stopRuneRing()
	runeRingActive = false
end

-- ===== Floating background glyphs (drift upward behind the text, ambient) =====
local glyphBackdrop = Instance.new("Frame")
glyphBackdrop.Name = "GlyphBackdrop"
glyphBackdrop.Size = UDim2.new(1, 0, 1, 0)
glyphBackdrop.BackgroundTransparency = 1
glyphBackdrop.ClipsDescendants = true
glyphBackdrop.ZIndex = 19 -- behind the main content (which sits at 20-27)
glyphBackdrop.Parent = eventFrame

local BACKDROP_GLYPHS = {"0", "1", "✦", "░", "▓", "?", "#", "☥"}

local function spawnBackdropGlyph()
	local glyph = Instance.new("TextLabel")
	glyph.Size = UDim2.new(0, 14, 0, 14)
	glyph.Position = UDim2.new(math.random(5, 95) / 100, 0, 1.05, 0)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.RobotoMono
	glyph.Text = BACKDROP_GLYPHS[math.random(1, #BACKDROP_GLYPHS)]
	glyph.TextColor3 = Color3.fromRGB(80, 20, 25)
	glyph.TextTransparency = 0.75
	glyph.TextSize = math.random(10, 16)
	glyph.ZIndex = 19
	glyph.Parent = glyphBackdrop

	local riseTime = math.random(40, 70) / 10
	local tween = TweenService:Create(glyph, TweenInfo.new(riseTime, Enum.EasingStyle.Linear), {
		Position = UDim2.new(glyph.Position.X.Scale, 0, -0.08, 0),
		TextTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function() glyph:Destroy() end)
end

local glyphEmitterActive = false
local function startGlyphEmitter()
	glyphEmitterActive = true
	task.spawn(function()
		while glyphEmitterActive do
			spawnBackdropGlyph()
			task.wait(math.random(3, 7) / 10)
		end
	end)
end
local function stopGlyphEmitter()
	glyphEmitterActive = false
end

-- ===== Scanning line sweeping the figure (like a slow security-camera scan) =====
local scanLine = Instance.new("Frame")
scanLine.Name = "ScanLine"
scanLine.Size = UDim2.new(1, 0, 0, 2)
scanLine.Position = UDim2.new(0, 0, 0, 0)
scanLine.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
scanLine.BackgroundTransparency = 0.5
scanLine.BorderSizePixel = 0
scanLine.ZIndex = 26
scanLine.Parent = figureContainer

local scanGradient = Instance.new("UIGradient")
scanGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})
scanGradient.Parent = scanLine

local scanLineActive = false
local function startScanLine()
	scanLineActive = true
	task.spawn(function()
		while scanLineActive do
			scanLine.Position = UDim2.new(0, 0, 0, 0)
			local tween = TweenService:Create(scanLine, TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Position = UDim2.new(0, 0, 1, 0),
			})
			tween:Play()
			tween.Completed:Wait()
			if not scanLineActive then break end
			task.wait(0.4)
		end
	end)
end
local function stopScanLine()
	scanLineActive = false
end

-- ===== Screen-tear glitch bars (horizontal slice displacement, whole frame) =====
local tearBarHolder = Instance.new("Frame")
tearBarHolder.Name = "TearBarHolder"
tearBarHolder.Size = UDim2.new(1, 0, 1, 0)
tearBarHolder.BackgroundTransparency = 1
tearBarHolder.ClipsDescendants = true
tearBarHolder.ZIndex = 28
tearBarHolder.Parent = eventFrame

local function doTearBarBurst()
	local numBars = math.random(2, 4)
	for i = 1, numBars do
		local bar = Instance.new("Frame")
		local barHeight = math.random(3, 10)
		bar.Size = UDim2.new(1, 0, 0, barHeight)
		bar.Position = UDim2.new(0, 0, math.random(0, 100) / 100, 0)
		bar.BackgroundColor3 = Color3.fromRGB(20, 15, 18)
		bar.BackgroundTransparency = 0.2
		bar.BorderSizePixel = 0
		bar.ZIndex = 28
		bar.Parent = tearBarHolder

		local displaceX = math.random(-14, 14)
		bar.Position = UDim2.new(0, displaceX, bar.Position.Y.Scale, 0)

		task.delay(math.random(4, 10) / 100, function()
			bar:Destroy()
		end)
	end
end

local tearBarActive = false
local function startTearBars()
	tearBarActive = true
	task.spawn(function()
		while tearBarActive do
			task.wait(math.random(15, 40) / 10)
			if tearBarActive then doTearBarBurst() end
		end
	end)
end
local function stopTearBars()
	tearBarActive = false
end
-- ===== Name block: chromatic-split title + animated underline flourish =====
local nameBlock = Instance.new("Frame")
nameBlock.Name = "NameBlock"
nameBlock.Size = UDim2.new(1, 0, 0, 46)
nameBlock.BackgroundTransparency = 1
nameBlock.LayoutOrder = 2
nameBlock.ZIndex = 21
nameBlock.Parent = contentColumn

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "NameLabel"
nameLabel.Size = UDim2.new(1, 0, 1, -10)
nameLabel.BackgroundTransparency = 1
nameLabel.Font = Enum.Font.Antique
nameLabel.Text = "???"
nameLabel.TextColor3 = Color3.fromRGB(200, 40, 45)
nameLabel.TextScaled = true
nameLabel.ZIndex = 22
nameLabel.Parent = nameBlock

-- chromatic ghost copies of the name text, offset a couple pixels for RGB-split glitch look
local nameGhostRed = nameLabel:Clone()
nameGhostRed.Name = "NameGhostRed"
nameGhostRed.Position = UDim2.new(0, -2, 0, 0)
nameGhostRed.TextColor3 = Color3.fromRGB(255, 30, 30)
nameGhostRed.TextTransparency = 1
nameGhostRed.ZIndex = 21
nameGhostRed.Parent = nameBlock

local nameGhostCyan = nameLabel:Clone()
nameGhostCyan.Name = "NameGhostCyan"
nameGhostCyan.Position = UDim2.new(0, 2, 0, 0)
nameGhostCyan.TextColor3 = Color3.fromRGB(30, 210, 255)
nameGhostCyan.TextTransparency = 1
nameGhostCyan.ZIndex = 21
nameGhostCyan.Parent = nameBlock

-- animated underline flourish beneath the name, grows outward from center
local underlineFlourish = Instance.new("Frame")
underlineFlourish.Name = "UnderlineFlourish"
underlineFlourish.AnchorPoint = Vector2.new(0.5, 0)
underlineFlourish.Position = UDim2.new(0.5, 0, 1, -6)
underlineFlourish.Size = UDim2.new(0, 0, 0, 1.5)
underlineFlourish.BackgroundColor3 = Color3.fromRGB(150, 30, 35)
underlineFlourish.BorderSizePixel = 0
underlineFlourish.ZIndex = 22
underlineFlourish.Parent = nameBlock

local underlineGradient = Instance.new("UIGradient")
underlineGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})
underlineGradient.Parent = underlineFlourish

-- ===== Tier progress pips (shows which milestones have fired, 1-6) =====
local pipRow = Instance.new("Frame")
pipRow.Name = "PipRow"
pipRow.Size = UDim2.new(1, 0, 0, 12)
pipRow.BackgroundTransparency = 1
pipRow.LayoutOrder = 3
pipRow.ZIndex = 21
pipRow.Parent = contentColumn

local pipListLayout = Instance.new("UIListLayout")
pipListLayout.FillDirection = Enum.FillDirection.Horizontal
pipListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
pipListLayout.Padding = UDim.new(0, 8)
pipListLayout.SortOrder = Enum.SortOrder.LayoutOrder
pipListLayout.Parent = pipRow

local pips = {}
local pipTweens = {}
for i = 1, #Milestones do
	local pip = Instance.new("Frame")
	pip.Name = "Pip" .. i
	pip.Size = UDim2.new(0, 7, 0, 7)
	pip.BackgroundColor3 = Color3.fromRGB(50, 45, 45)
	pip.BorderSizePixel = 0
	pip.LayoutOrder = i
	pip.ZIndex = 21
	pip.Parent = pipRow
	local pipCorner = Instance.new("UICorner")
	pipCorner.CornerRadius = UDim.new(1, 0)
	pipCorner.Parent = pip
	local pipStroke = Instance.new("UIStroke")
	pipStroke.Color = Color3.fromRGB(90, 20, 25)
	pipStroke.Thickness = 1
	pipStroke.Transparency = 0.5
	pipStroke.Parent = pip
	pips[i] = pip
end

-- ===== Divider with center ornament =====
local dividerHolder = Instance.new("Frame")
dividerHolder.Name = "DividerHolder"
dividerHolder.Size = UDim2.new(1, 0, 0, 10)
dividerHolder.BackgroundTransparency = 1
dividerHolder.LayoutOrder = 4
dividerHolder.ZIndex = 21
dividerHolder.Parent = contentColumn

local dividerLeft = Instance.new("Frame")
dividerLeft.AnchorPoint = Vector2.new(1, 0.5)
dividerLeft.Position = UDim2.new(0.46, 0, 0.5, 0)
dividerLeft.Size = UDim2.new(0.5, 0, 0, 1)
dividerLeft.BackgroundColor3 = Color3.fromRGB(120, 20, 30)
dividerLeft.BackgroundTransparency = 0.4
dividerLeft.BorderSizePixel = 0
dividerLeft.ZIndex = 21
dividerLeft.Parent = dividerHolder

local dividerRight = dividerLeft:Clone()
dividerRight.AnchorPoint = Vector2.new(0, 0.5)
dividerRight.Position = UDim2.new(0.54, 0, 0.5, 0)
dividerRight.Parent = dividerHolder

local dividerDot = Instance.new("Frame")
dividerDot.AnchorPoint = Vector2.new(0.5, 0.5)
dividerDot.Position = UDim2.new(0.5, 0, 0.5, 0)
dividerDot.Size = UDim2.new(0, 4, 0, 4)
dividerDot.Rotation = 45
dividerDot.BackgroundColor3 = Color3.fromRGB(150, 30, 35)
dividerDot.BorderSizePixel = 0
dividerDot.ZIndex = 21
dividerDot.Parent = dividerHolder

-- ===== Body text =====
local bodyText = Instance.new("TextLabel")
bodyText.Name = "BodyText"
bodyText.Size = UDim2.new(1, 0, 0.28, 0)
bodyText.BackgroundTransparency = 1
bodyText.Font = Enum.Font.Garamond
bodyText.Text = ""
bodyText.TextColor3 = Color3.fromRGB(210, 205, 200)
bodyText.TextWrapped = true
bodyText.TextSize = 18
bodyText.TextYAlignment = Enum.TextYAlignment.Top
bodyText.LayoutOrder = 5
bodyText.ZIndex = 21
bodyText.Parent = contentColumn

-- ===== Footer: essence count + session flourish =====
local footerHolder = Instance.new("Frame")
footerHolder.Name = "FooterHolder"
footerHolder.Size = UDim2.new(1, 0, 0, 34)
footerHolder.BackgroundTransparency = 1
footerHolder.LayoutOrder = 6
footerHolder.ZIndex = 21
footerHolder.Parent = contentColumn

local footerDivider = Instance.new("Frame")
footerDivider.Size = UDim2.new(0.3, 0, 0, 1)
footerDivider.Position = UDim2.new(0.35, 0, 0, 0)
footerDivider.BackgroundColor3 = Color3.fromRGB(90, 20, 25)
footerDivider.BackgroundTransparency = 0.5
footerDivider.BorderSizePixel = 0
footerDivider.ZIndex = 21
footerDivider.Parent = footerHolder

local footerText = Instance.new("TextLabel")
footerText.Name = "FooterText"
footerText.Size = UDim2.new(1, 0, 0, 18)
footerText.Position = UDim2.new(0, 0, 0, 10)
footerText.BackgroundTransparency = 1
footerText.Font = Enum.Font.RobotoMono
footerText.Text = ""
footerText.TextColor3 = Color3.fromRGB(120, 30, 35)
footerText.TextTransparency = 0.2
footerText.TextSize = 12
footerText.ZIndex = 21
footerText.Parent = footerHolder

-- ===== NEW: Sightings Log panel (press H to toggle) =====
-- A small collectible-feeling log of every past encounter: tier name,
-- time it happened, and the lines it said. Hidden by default.
local logFrame = Instance.new("Frame")
logFrame.Name = "SightingsLogFrame"
logFrame.AnchorPoint = Vector2.new(0, 1)
logFrame.Position = UDim2.new(0, 16, 1, -16)
logFrame.Size = UDim2.new(0, 280, 0, 260)
logFrame.BackgroundColor3 = Color3.fromRGB(6, 5, 8)
logFrame.BackgroundTransparency = 0.1
logFrame.Visible = false
logFrame.ZIndex = 50
logFrame.Parent = screenGui

local logCorner = Instance.new("UICorner")
logCorner.CornerRadius = UDim.new(0, 6)
logCorner.Parent = logFrame

local logStroke = Instance.new("UIStroke")
logStroke.Color = Color3.fromRGB(120, 20, 25)
logStroke.Thickness = 1
logStroke.Transparency = 0.4
logStroke.Parent = logFrame

local logTitle = Instance.new("TextLabel")
logTitle.Name = "LogTitle"
logTitle.Size = UDim2.new(1, -20, 0, 26)
logTitle.Position = UDim2.new(0, 10, 0, 8)
logTitle.BackgroundTransparency = 1
logTitle.Font = Enum.Font.RobotoMono
logTitle.Text = trackOut("SIGHTINGS")
logTitle.TextColor3 = Color3.fromRGB(180, 40, 45)
logTitle.TextSize = 13
logTitle.TextXAlignment = Enum.TextXAlignment.Left
logTitle.ZIndex = 51
logTitle.Parent = logFrame

local logHint = Instance.new("TextLabel")
logHint.Name = "LogHint"
logHint.Size = UDim2.new(1, -20, 0, 14)
logHint.Position = UDim2.new(0, 10, 0, 30)
logHint.BackgroundTransparency = 1
logHint.Font = Enum.Font.RobotoMono
logHint.Text = "press H to close"
logHint.TextColor3 = Color3.fromRGB(90, 90, 95)
logHint.TextSize = 10
logHint.TextXAlignment = Enum.TextXAlignment.Left
logHint.ZIndex = 51
logHint.Parent = logFrame

local logScroll = Instance.new("ScrollingFrame")
logScroll.Name = "LogScroll"
logScroll.Position = UDim2.new(0, 10, 0, 50)
logScroll.Size = UDim2.new(1, -20, 1, -60)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 4
logScroll.ScrollBarImageColor3 = Color3.fromRGB(120, 20, 25)
logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
logScroll.ZIndex = 51
logScroll.Parent = logFrame

local logListLayout = Instance.new("UIListLayout")
logListLayout.SortOrder = Enum.SortOrder.LayoutOrder
logListLayout.Padding = UDim.new(0, 10)
logListLayout.Parent = logScroll
local SFX = SoundService:WaitForChild("SFX")
-- ===== Sounds =====
local droneSound = Instance.new("Sound")
droneSound.Name = "HollowedDrone"
droneSound.SoundId = ASSETS.AmbientDrone
droneSound.Volume = 0.5
droneSound.Looped = true
droneSound.SoundGroup = SFX
droneSound.Parent = SFX

local stingerSound = Instance.new("Sound")
stingerSound.Name = "HollowedStinger"
stingerSound.SoundId = ASSETS.RevealStinger
stingerSound.Volume = 0.7
stingerSound.SoundGroup = SFX
stingerSound.Parent = SFX

local crackSound = Instance.new("Sound")
crackSound.Name = "HollowedCrack"
crackSound.SoundId = ASSETS.CrackSound
crackSound.Volume = 0.6
crackSound.SoundGroup = SFX
crackSound.Parent = SFX

local whisperSound = Instance.new("Sound")
whisperSound.Name = "HollowedWhisper"
whisperSound.SoundId = ASSETS.WhisperSound
whisperSound.Volume = 0.25
whisperSound.Looped = true
whisperSound.SoundGroup = SFX
whisperSound.Parent = SFX

local premonitionSound = Instance.new("Sound")
premonitionSound.Name = "HollowedPremonition"
premonitionSound.SoundId = ASSETS.PremonitionWhisper
premonitionSound.Volume = 0.12
premonitionSound.SoundGroup = SFX
premonitionSound.Parent = SFX

----------------------------------------------------------------
-- EFFECT HELPERS
----------------------------------------------------------------

local function staticFlickerBurst(duration)
	task.spawn(function()
		local endTime = os.clock() + duration
		while os.clock() < endTime do
			staticOverlay.Visible = true
			task.wait(math.random(2, 5) / 100)
			staticOverlay.Visible = false
			task.wait(math.random(4, 10) / 100)
		end
		staticOverlay.Visible = false
	end)
end

-- brief RGB-split flash on the figure + name, sells "reality is glitching" moments
local function chromaBurst(duration)
	task.spawn(function()
		local t = 0
		local step = 0.03
		while t < duration do
			local jitter = math.random(2, 5)
			chromaRed.Position = UDim2.new(0, -jitter, 0, 0)
			chromaCyan.Position = UDim2.new(0, jitter, 0, 0)
			chromaRed.ImageTransparency = 0.55
			chromaCyan.ImageTransparency = 0.55
			nameGhostRed.Position = UDim2.new(0, -jitter, 0, 0)
			nameGhostCyan.Position = UDim2.new(0, jitter, 0, 0)
			nameGhostRed.TextTransparency = 0.4
			nameGhostCyan.TextTransparency = 0.4
			task.wait(step)
			chromaRed.ImageTransparency = 1
			chromaCyan.ImageTransparency = 1
			nameGhostRed.TextTransparency = 1
			nameGhostCyan.TextTransparency = 1
			task.wait(step)
			t += step * 2
		end
	end)
end

local function crackFlash()
	crackLayer.Visible = true
	crackSound:Play()
	for _, line in ipairs(crackLines) do
		line.BackgroundTransparency = math.random(20, 55) / 100
	end
	task.wait(0.09)
	for _, line in ipairs(crackLines) do
		TweenService:Create(line, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	end
	task.delay(0.6, function() crackLayer.Visible = false end)
end

-- spawns a single rising, fading ember inside the figure container
local function spawnEmber()
	local ember = Instance.new("Frame")
	ember.Size = UDim2.new(0, math.random(2, 4), 0, math.random(2, 4))
	ember.Position = UDim2.new(math.random(5, 95) / 100, 0, 1.05, 0)
	ember.BackgroundColor3 = Color3.fromRGB(180, 50, 40)
	ember.BackgroundTransparency = 0.3
	ember.BorderSizePixel = 0
	ember.ZIndex = 26
	ember.Parent = emberHolder
	local emberCorner = Instance.new("UICorner")
	emberCorner.CornerRadius = UDim.new(1, 0)
	emberCorner.Parent = ember

	local riseTime = math.random(25, 45) / 10
	local drift = (math.random() - 0.5) * 0.3
	local tween = TweenService:Create(ember, TweenInfo.new(riseTime, Enum.EasingStyle.Linear), {
		Position = UDim2.new(ember.Position.X.Scale + drift, 0, -0.1, 0),
		BackgroundTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function() ember:Destroy() end)
end

local emberEmitterActive = false
local function startEmberEmitter()
	emberEmitterActive = true
	task.spawn(function()
		while emberEmitterActive do
			spawnEmber()
			task.wait(math.random(15, 40) / 100)
		end
	end)
end
local function stopEmberEmitter()
	emberEmitterActive = false
end

-- gentle breathing pulse on the figure container + its glow, loops until stopped
local breathingActive = false
local function startBreathing()
	breathingActive = true
	task.spawn(function()
		while breathingActive do
			TweenService:Create(glowBehind, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				ImageTransparency = 0.65,
				Size = UDim2.new(1.55, 0, 1.55, 0),
			}):Play()
			task.wait(2.2)
			if not breathingActive then break end
			TweenService:Create(glowBehind, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				ImageTransparency = 0.8,
				Size = UDim2.new(1.4, 0, 1.4, 0),
			}):Play()
			task.wait(2.2)
		end
	end)
end
local function stopBreathing()
	breathingActive = false
end

-- ===== NEW: Eye tracking — the glint inside the shroud follows the cursor =====
local eyeTrackingActive = false
local EYE_MAX_DRIFT = 5 -- max pixels the glint can shift toward the cursor
local function startEyeTracking()
	eyeTrackingActive = true
	TweenService:Create(eyeGlint, TweenInfo.new(0.6), { BackgroundTransparency = 0.25 }):Play()
	task.spawn(function()
		while eyeTrackingActive do
			local ok, mouseLoc = pcall(function() return UserInputService:GetMouseLocation() end)
			if ok and figureContainer.Parent then
				local containerPos = figureContainer.AbsolutePosition
				local containerSize = figureContainer.AbsoluteSize
				if containerSize.X > 0 and containerSize.Y > 0 then
					local centerX = containerPos.X + containerSize.X / 2
					local centerY = containerPos.Y + containerSize.Y * 0.42
					local dx = math.clamp((mouseLoc.X - centerX) / 40, -1, 1)
					local dy = math.clamp((mouseLoc.Y - centerY) / 40, -1, 1)
					eyeGlint.Position = UDim2.new(0.5, dx * EYE_MAX_DRIFT, 0.42, dy * EYE_MAX_DRIFT)
				end
			end
			RunService.RenderStepped:Wait()
		end
	end)
end
local function stopEyeTracking()
	eyeTrackingActive = false
	TweenService:Create(eyeGlint, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
end

-- ===== NEW: Watcher Mark behavior =====
local watcherActive = false
local function watcherBlink()
	local closeTween = TweenService:Create(watcherMark, TweenInfo.new(0.06, Enum.EasingStyle.Quad), {
		Size = UDim2.new(0, 24, 0, 2),
	})
	closeTween:Play()
	closeTween.Completed:Wait()
	local openTween = TweenService:Create(watcherMark, TweenInfo.new(0.08, Enum.EasingStyle.Quad), {
		Size = UDim2.new(0, 24, 0, 24),
	})
	openTween:Play()
end

local function startWatcherMark()
	if watcherActive then return end
	watcherActive = true
	TweenService:Create(watcherMark, TweenInfo.new(2), { TextTransparency = 0.35 }):Play()
	task.spawn(function()
		while watcherActive do
			task.wait(math.random(15, 45))
			if watcherActive then watcherBlink() end
		end
	end)
end

-- called once Tier 6 fires: the mark stops being a half-hidden hint and
-- becomes a fully visible, permanently-lit rune in the accent color.
local function evolveWatcherMark(accentColor)
	TweenService:Create(watcherMark, TweenInfo.new(2), {
		TextTransparency = 0.05,
		TextColor3 = accentColor,
	}):Play()
end

-- ===== NEW: Premonition system =====
-- Occasionally, when the player is close to their next milestone, reality
-- flickers for a single frame — a scrambled fragment of the next name
-- flashes at screen center and vanishes almost before it registers. Never
-- fires while a real event is playing.
local function getNextMilestoneProgress()
	local quantity = earthEssenceStat:GetAttribute("Quantity") or 0
	for _, milestone in ipairs(Milestones) do
		if not triggeredTiers[milestone.Tier] then
			return quantity / milestone.Threshold, milestone
		end
	end
	return 1, nil
end

local function premonitionFlash(nextMilestone)
	task.spawn(function()
		premonitionLabel.Text = scrambleText(getRevealedName(nextMilestone.NameRevealPercent), 0.75)
		local dimTween = TweenService:Create(dimOverlay, TweenInfo.new(0.05), { BackgroundTransparency = 0.7 })
		local labelTween = TweenService:Create(premonitionLabel, TweenInfo.new(0.05), { TextTransparency = 0.25 })
		dimTween:Play()
		labelTween:Play()
		if ASSETS.PremonitionWhisper ~= "rbxassetid://0" then premonitionSound:Play() end
		staticFlickerBurst(0.12)
		task.wait(0.09)
		TweenService:Create(dimOverlay, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(premonitionLabel, TweenInfo.new(0.15), { TextTransparency = 1 }):Play()
	end)
end

task.spawn(function()
	while true do
		task.wait(math.random(6, 14))
		if not isEventActive then
			local progress, nextMilestone = getNextMilestoneProgress()
			if nextMilestone and progress > 0.85 then
				-- chance ramps from 0% at 85% progress up to ~40% right at the threshold
				local chance = ((progress - 0.85) / 0.15) * 0.4
				if math.random() < chance then
					premonitionFlash(nextMilestone)
				end
			end
		end
	end
end)

-- typewriter with occasional glitch-flash on letters
local function typeText(label, fullText, charDelay)
	label.Text = ""
	for i = 1, #fullText do
		local revealed = fullText:sub(1, i)
		local lastChar = fullText:sub(i, i)
		if lastChar:match("%a") and math.random() < 0.12 then
			label.Text = revealed:sub(1, i - 1) .. GLITCH_CHARS:sub(math.random(1, #GLITCH_CHARS), math.random(1, #GLITCH_CHARS)) .. "▍"
			task.wait(0.02)
		end
		label.Text = revealed .. "▍"
		task.wait(charDelay)
	end
	-- settle without cursor briefly, then blink a couple times before clearing
	label.Text = fullText
	for i = 1, 3 do
		task.wait(0.25)
		label.Text = fullText .. "▍"
		task.wait(0.25)
		label.Text = fullText
	end
end

-- camera shake: tracks the last applied offset so it can be undone before
-- applying the next one, and undone entirely on stop, instead of the
-- camera permanently drifting away frame after frame.
local activeShakeConnection = nil
local shakeLastOffset = Vector3.new(0, 0, 0)

local function startCameraShake(intensity)
	local camera = workspace.CurrentCamera
	if not camera then return end
	shakeLastOffset = Vector3.new(0, 0, 0)
	activeShakeConnection = RunService.RenderStepped:Connect(function()
		local newOffset = Vector3.new((math.random() - 0.5) * intensity, (math.random() - 0.5) * intensity, 0)
		camera.CFrame = camera.CFrame * CFrame.new(-shakeLastOffset) * CFrame.new(newOffset)
		shakeLastOffset = newOffset
	end)
end

local function stopCameraShake()
	local camera = workspace.CurrentCamera
	if activeShakeConnection then
		activeShakeConnection:Disconnect()
		activeShakeConnection = nil
	end
	if camera then
		camera.CFrame = camera.CFrame * CFrame.new(-shakeLastOffset)
	end
	shakeLastOffset = Vector3.new(0, 0, 0)
end

-- retints the whole frame's accent elements (stroke, glow, name, pips) to a milestone's AccentColor
local function applyAccentColor(color)
	TweenService:Create(frameStroke, TweenInfo.new(1.5), { Color = color }):Play()
	TweenService:Create(frameGlowStroke, TweenInfo.new(1.5), { Color = color }):Play()
	TweenService:Create(nameLabel, TweenInfo.new(1.5), { TextColor3 = color }):Play()
	TweenService:Create(glowBehind, TweenInfo.new(1.5), { ImageColor3 = color }):Play()
	TweenService:Create(underlineFlourish, TweenInfo.new(1.5), { BackgroundColor3 = color }):Play()
	TweenService:Create(eyebrowLabel, TweenInfo.new(1.5), { TextColor3 = lerpColor(color, Color3.new(1,1,1), 0.3) }):Play()
	for _, piece in ipairs(cornerAccentPieces) do
		TweenService:Create(piece, TweenInfo.new(1.5), { BackgroundColor3 = color }):Play()
	end
end

local function updatePips(currentTierIndex)
	for i, pip in ipairs(pips) do
		if pipTweens[i] then
			pipTweens[i]:Cancel()
			pipTweens[i] = nil
		end
		if i < currentTierIndex then
			pip.BackgroundColor3 = Color3.fromRGB(150, 30, 35)
		elseif i == currentTierIndex then
			pipTweens[i] = TweenService:Create(pip, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
				BackgroundColor3 = Color3.fromRGB(230, 60, 60),
			})
			pipTweens[i]:Play()
		else
			pip.BackgroundColor3 = Color3.fromRGB(50, 45, 45)
		end
	end
end

----------------------------------------------------------------
-- NEW: PART 5 — SIGHTINGS LOG PANEL (toggle with H)
----------------------------------------------------------------
local function refreshSightingsLog()
	for _, child in ipairs(logScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	if #sightingsLog == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Font = Enum.Font.Garamond
		emptyLabel.Text = "Nothing has spoken to you yet."
		emptyLabel.TextColor3 = Color3.fromRGB(120, 115, 115)
		emptyLabel.TextWrapped = true
		emptyLabel.TextSize = 14
		emptyLabel.ZIndex = 51
		emptyLabel.Parent = logScroll
		return
	end
	for i = #sightingsLog, 1, -1 do
		local entry = sightingsLog[i]
		local card = Instance.new("Frame")
		card.Name = "Entry" .. i
		card.Size = UDim2.new(1, 0, 0, 0)
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.BackgroundTransparency = 1
		card.LayoutOrder = #sightingsLog - i
		card.ZIndex = 51
		card.Parent = logScroll

		local cardLayout = Instance.new("UIListLayout")
		cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardLayout.Padding = UDim.new(0, 2)
		cardLayout.Parent = card

		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 14)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.RobotoMono
		header.Text = string.format("TIER %d · %s", entry.tier, entry.timestamp)
		header.TextColor3 = Color3.fromRGB(150, 30, 35)
		header.TextSize = 11
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.ZIndex = 51
		header.Parent = card

		for _, line in ipairs(entry.lines) do
			local lineLabel = Instance.new("TextLabel")
			lineLabel.Size = UDim2.new(1, 0, 0, 0)
			lineLabel.AutomaticSize = Enum.AutomaticSize.Y
			lineLabel.BackgroundTransparency = 1
			lineLabel.Font = Enum.Font.Garamond
			lineLabel.Text = "\"" .. formatLine(line, entry.essenceNow) .. "\""
			lineLabel.TextColor3 = Color3.fromRGB(190, 185, 180)
			lineLabel.TextWrapped = true
			lineLabel.TextSize = 13
			lineLabel.TextXAlignment = Enum.TextXAlignment.Left
			lineLabel.ZIndex = 51
			lineLabel.Parent = card
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.H then
		logFrame.Visible = not logFrame.Visible
		if logFrame.Visible then refreshSightingsLog() end
	end
end)

----------------------------------------------------------------
-- MAIN EVENT SEQUENCE
----------------------------------------------------------------
local UpdateData = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("UpdateData")

local musics = game:GetService("SoundService"):WaitForChild("Music")

local function playHollowedEvent(milestone)
	musics.Volume = 0
	
	if milestone.Tier == 1 then
		if not player:GetAttribute("1472053267504184") then
			badgefunc:FireServer("1472053267504184")
		end
	end
	
	if milestone.Tier == 6 then
		if not player:GetAttribute("3749419964014047") then
			badgefunc:FireServer("3749419964014047")
		end
	end
	
	UpdateData:FireServer(true,"=","HollowedMilestones","HollowMilestone"..milestone.Tier)
	ambientIntensified = true

	-- reset visuals
	figureImage.Image = ASSETS.FigureImages[milestone.Tier] or ""
	chromaRed.Image = figureImage.Image
	chromaCyan.Image = figureImage.Image
	shroudLayer.ImageTransparency = 0.03
	nameLabel.Text = "???"
	nameGhostRed.Text = "???"
	nameGhostCyan.Text = "???"
	eyebrowLabel.Text = ""
	bodyText.Text = ""
	footerText.Text = ""
	underlineFlourish.Size = UDim2.new(0, 0, 0, 1.5)
	eventFrame.Position = UDim2.new(0.5, 0, -0.7, 0)
	updatePips(milestone.Tier)
	applyAccentColor(milestone.AccentColor)

	-- entrance: crack flash first, then dim/vignette/scanlines fade in, then frame slides down
	crackFlash()
	TweenService:Create(dimOverlay, TweenInfo.new(1, Enum.EasingStyle.Sine), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(vignetteOverlay, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { ImageTransparency = 0.15 }):Play()
	TweenService:Create(scanlineOverlay, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { ImageTransparency = 0.75 }):Play()

	local slideDown = TweenService:Create(eventFrame, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.05, 0),
	})
	slideDown:Play()
	staticFlickerBurst(1.8)
	droneSound:Play()
	if ASSETS.WhisperSound ~= "rbxassetid://0" then whisperSound:Play() end
	slideDown.Completed:Wait()

	startBreathing()
	startEmberEmitter()
	startEyeTracking()

	startRuneRing()
	startGlyphEmitter()
	startScanLine()
	startTearBars()
	startStripeAnimation()

	-- eyebrow text types in
	typeText(eyebrowLabel, trackOut(milestone.Eyebrow), 0.02)
	task.wait(0.3)

	-- reveal the shroud slowly (figure becomes more visible)
	TweenService:Create(shroudLayer, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { ImageTransparency = milestone.ShroudTransparency }):Play()
	TweenService:Create(shroudLayerFar, TweenInfo.new(2.6, Enum.EasingStyle.Sine), { ImageTransparency = milestone.ShroudTransparency + 0.1 }):Play()
	task.wait(0.6)

	-- reveal the name with a glitchy scramble-in, chroma burst, stinger
	local revealedName = getRevealedName(milestone.NameRevealPercent)
	chromaBurst(1.0)
	for i = 1, 6 do
		local scrambled = scrambleText(revealedName, 0.6)
		nameLabel.Text = scrambled
		nameGhostRed.Text = scrambled
		nameGhostCyan.Text = scrambled
		task.wait(0.05)
	end
	nameLabel.Text = revealedName
	nameGhostRed.Text = revealedName
	nameGhostCyan.Text = revealedName
	stingerSound:Play()
	staticFlickerBurst(0.4)
	TweenService:Create(underlineFlourish, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.55, 0, 0, 1.5),
	}):Play()

	if milestone.ShakeIntensity then
		startCameraShake(milestone.ShakeIntensity)
	end

	task.wait(0.5)

	-- pick 3 random lines, inject essence count / player name
	local pool = {}
	for _, line in ipairs(milestone.Lines) do table.insert(pool, line) end
	local chosen = {}
	local count = math.min(3, #pool)
	for i = 1, count do
		local idx = math.random(1, #pool)
		table.insert(chosen, table.remove(pool, idx))
	end

	local essenceNow = earthEssenceStat:GetAttribute("Quantity") or 0
	footerText.Text = string.format("ESSENCE HELD  ·  %s", formatNumber(essenceNow))

	-- NEW: log this encounter for the Sightings panel
	table.insert(sightingsLog, {
		tier = milestone.Tier,
		eyebrow = milestone.Eyebrow,
		timestamp = os.date("%H:%M:%S"),
		lines = chosen,
		essenceNow = essenceNow,
	})

	for _, line in ipairs(chosen) do
		local formattedLine = formatLine(line, essenceNow)
		typeText(bodyText, formattedLine, 0.025)
		if math.random() < 0.35 then chromaBurst(0.3) end
		task.wait(1.6)
		bodyText.Text = scrambleText(formattedLine, 0.7)
		task.wait(0.15)
		bodyText.Text = ""
		task.wait(0.3)
	end

	task.wait(1.2)

	if milestone.ShakeIntensity then
		stopCameraShake()
	end
	stopBreathing()
	stopEmberEmitter()
	stopEyeTracking()

	stopRuneRing()
	stopGlyphEmitter()
	stopScanLine()
	stopTearBars()
	stopStripeAnimation()
	-- exit: slide up + fade dim/vignette/scanlines
	local slideUp = TweenService:Create(eventFrame, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, -1.1, 0),
	})
	TweenService:Create(dimOverlay, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(vignetteOverlay, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { ImageTransparency = 1 }):Play()
	TweenService:Create(scanlineOverlay, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { ImageTransparency = 1 }):Play()
	slideUp:Play()
	staticFlickerBurst(0.6)

	slideUp.Completed:Wait()
	droneSound:Stop()
	if whisperSound.IsPlaying then whisperSound:Stop() end
	ambientIntensified = false

	-- NEW: Tier 1 permanently plants the Watcher Mark; Tier 6 evolves it
	-- into its final, fully-visible form.
	if milestone.Tier == 1 then
		startWatcherMark()
	elseif milestone.Tier == 6 then
		evolveWatcherMark(milestone.AccentColor)
	end
	musics.Volume = 0.5
end

local function processQueue()
	if isEventActive or #eventQueue == 0 then return end
	isEventActive = true
	local milestone = table.remove(eventQueue, 1)
	task.spawn(function()
		playHollowedEvent(milestone)
		isEventActive = false
		processQueue()
	end)
end

local function checkMilestones()
	local quantity = earthEssenceStat:GetAttribute("Quantity") or 0
	for _, milestone in ipairs(Milestones) do
		if quantity >= milestone.Threshold and not triggeredTiers[milestone.Tier] and not player:GetAttribute("HollowMilestone"..milestone.Tier)then
			triggeredTiers[milestone.Tier] = true
			table.insert(eventQueue, milestone)
		end
	end
	processQueue()
end

earthEssenceStat:GetAttributeChangedSignal("Quantity"):Connect(checkMilestones)
checkMilestones()

--[[
	WHAT'S NEW IN THIS VERSION (on top of the v2 bugfixes):

	1. EYE GLINT THAT TRACKS THE CURSOR
	   A tiny glinting eye lives inside the mist over the figure and drifts
	   toward wherever your mouse is (see EyeGlint + startEyeTracking /
	   stopEyeTracking). It fades in only while an event is playing. Fully
	   procedural — no asset ID needed.

	2. THE WATCHER MARK
	   A small rune in the bottom-right corner of the screen (WatcherMark)
	   stays hidden until Tier 1 fires, then fades in and stays — a
	   permanent reminder that it's still there. It blinks at random
	   intervals (watcherBlink) and, at Tier 6, brightens into its final
	   accent-colored form (evolveWatcherMark) since "nothing is hidden"
	   anymore.

	3. PREMONITION FLICKERS
	   When the player is within striking distance of their next milestone
	   (getNextMilestoneProgress > 85%), there's a small and growing chance
	   every several seconds of a single-frame subliminal flash: a
	   scrambled fragment of the *next* tier's name flickers at screen
	   center for about a tenth of a second (premonitionFlash), quiet
	   enough that the player might not be sure they saw it. Never fires
	   during a real event.

	4. PERSONALIZED DIALOGUE
	   Milestone lines can now use "%n" for the player's Roblox name in
	   addition to the existing "%s" for essence count (see formatLine).
	   Each tier got one new line using %n added to its pool — since only
	   3 of each tier's lines get chosen per event, personalization surfaces
	   unpredictably rather than every time, which keeps it unsettling
	   instead of gimmicky.

	5. SIGHTINGS LOG (press H)
	   Every encounter is now recorded (sightingsLog) with its tier, a
	   timestamp, and the exact lines it spoke to you. Press H in-game to
	   toggle a small panel (bottom-left) listing past sightings, newest
	   first — a lightweight ARG-style "receipts" feature for players who
	   want to go back and reread what it said.

	Reminder: ASSETS still has placeholder rbxassetid://0 values for all
	textures/figure art, and a new PremonitionWhisper sound slot was added
	(currently pointing at the same placeholder ID as the others) — wire
	up real assets there before these will fully read.
]]
--[[
	================================================================
	 LoadingScreen.lua — EssenceBound Client Loading Sequence
	================================================================

	PLACEMENT:
		StarterPlayer > StarterPlayerScripts > (this file, as a LocalScript)

	Self-contained. Builds its own UI tree on join, preloads assets,
	and fades away once loading is done and the player acknowledges
	the prompt (or after a grace period).

	DESIGN NOTES:
		- Every UDim2 in this file uses .fromScale(). Nothing uses
		  .fromOffset() or raw pixel math. Anything that must render
		  as a true circle (orb, satellites, particles, eyes, rune
		  ticks) gets a UIAspectRatioConstraint so scale math can
		  never stretch it into an ellipse on unusual aspect ratios.
		- Both orb images (CONFIG.LargeOrbImage / SmallOrbImage) are
		  assumed to always be set — there is no plain-shape fallback
		  path, so paste your asset IDs in before shipping.
		- The ominous system is a large weighted pool of independent
		  effects on a randomized timer, and it escalates — as
		  progress nears completion, events fire more often and the
		  background bleeds darker, so the tension has a shape.
		- A skip button fades in 5 seconds after the screen opens.
		  Clicking it (or pressing any key/click, same as before)
		  immediately jumps straight to the fade-out/cleanup sequence,
		  regardless of how far real asset loading has gotten.
	--------------------------------------------------------------
]]

--============================================================
-- SECTION 1: SERVICES
--============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--============================================================
-- SECTION 2: CONFIG
--============================================================

local CONFIG = {

	-- ================= ASSETS (required) =================
	LargeOrbImage = "rbxassetid://72641569769631",
	SmallOrbImage = "rbxassetid://72641569769631",
	Music = game:GetService("SoundService"):WaitForChild("Music"):WaitForChild("Loading Screen"):WaitForChild("Music1"),
	-- ================= TIMING =================
	MinDisplayTime = 2.25,
	FadeTime = 0.7,
	GraceAfterComplete = 1.5,
	SkipButtonDelay = 5, -- seconds before the skip button fades in

	-- ================= OMINOUS SYSTEM =================
	OminousMinGap = 1.6,
	OminousMaxGap = 3.2,
	-- once progress crosses this threshold, gaps shrink toward the "Escalated" values
	EscalationThreshold = 0.75,
	EscalatedMinGap = 0.7,
	EscalatedMaxGap = 1.5,

	-- ================= COLORS =================
	ColorBackgroundTop = Color3.fromRGB(20, 9, 30),
	ColorBackgroundMid = Color3.fromRGB(9, 5, 16),
	ColorBackgroundBottom = Color3.fromRGB(16, 7, 24),
	ColorBackgroundTense = Color3.fromRGB(30, 6, 10),
	ColorEssenceBright = Color3.fromRGB(180, 255, 200),
	ColorEssenceMid = Color3.fromRGB(50, 210, 100),
	ColorEssenceDark = Color3.fromRGB(15, 90, 45),
	ColorEmber = Color3.fromRGB(230, 130, 60),
	ColorGoldAccent = Color3.fromRGB(190, 160, 80),
	ColorOverlordRed = Color3.fromRGB(180, 30, 30),
	ColorGlitchCyan = Color3.fromRGB(60, 220, 220),
	ColorTextPrimary = Color3.fromRGB(235, 255, 235),
	ColorTextSecondary = Color3.fromRGB(190, 200, 195),
	ColorTextFaint = Color3.fromRGB(120, 130, 125),

	-- ================= LORE TEXT =================

	FlavorLines = {
		"Essence stirs beneath the roots...",
		"Something old is counting your steps.",
		"The orb remembers every hand that has touched it.",
		"Rebirth is not an ending. It never was.",
		"Not all who gather essence are welcome to keep it.",
		"The forest listens before it grows.",
		"Storms do not fall here. They are sent.",
		"Every critical spark was permitted, not earned.",
		"The rarest essence was never meant to be found.",
		"There is a ledger. You are already on it.",
		"It has watched every rebirth from the first.",
		"The gates do not open. They are allowed to.",
		"Some upgrades were never for sale. They were traded.",
		"You were not the only one who clicked first.",
		"The orb was warm before you arrived.",
	},

	StageText = {
		{ threshold = 0.00, text = "Initializing essence core..." },
		{ threshold = 0.12, text = "Binding orb resonance..." },
		{ threshold = 0.26, text = "Calibrating rebirth matrix..." },
		{ threshold = 0.40, text = "Counting what has been gathered..." },
		{ threshold = 0.54, text = "Something is already counting too." },
		{ threshold = 0.68, text = "Sealing the forest gates..." },
		{ threshold = 0.80, text = "It has noticed the seal." },
		{ threshold = 0.90, text = "Almost." },
		{ threshold = 0.97, text = "Ready." },
	},

	OverlordLines = {
		"i see you.",
		"you are not the first.",
		"keep gathering.",
		"it is watching the orb, not you.",
		"welcome back. again.",
		"the count continues.",
		"you were expected.",
		"do not stop collecting.",
		"it remembers this part best.",
		"there is always a next rebirth.",
		"nothing gathered is ever truly yours.",
	},

	-- shorter, quieter lines for off-center corner whispers
	CornerWhispers = {
		"...again...",
		"...still counting...",
		"...closer...",
		"...it knows...",
		"...not long now...",
		"...patience...",
	},

	-- scrolling marquee ticker fragments along the very bottom edge
	TickerFragments = {
		"THE ESSENCE REMEMBERS  ·  ",
		"NOTHING IS GIVEN, ONLY LENT  ·  ",
		"REBIRTH IS A PROMISE, NOT A RESET  ·  ",
		"THE ORB HAS SEEN THIS BEFORE  ·  ",
		"YOU ARE ON THE LEDGER  ·  ",
	},

	-- Old Norse-style runic glyphs used purely as decorative ambient symbols
	DriftSymbols = { "ᚠ", "ᚢ", "ᚦ", "ᚨ", "ᚱ", "ᚲ", "ᚷ", "ᚹ", "ᚺ", "ᛝ", "ᛟ", "ᛒ" },
}

--============================================================
-- SECTION 3: SMALL UTILITIES
--============================================================

local Lifecycle = {
	active = true,
	connections = {},
}

function Lifecycle:track(connection)
	table.insert(self.connections, connection)
	return connection
end

function Lifecycle:shutdown()
	self.active = false
	for _, connection in ipairs(self.connections) do
		if typeof(connection) == "RBXScriptConnection" and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(self.connections)
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function randomFloat(min, max)
	return min + math.random() * (max - min)
end

local function pickRandom(list)
	return list[math.random(1, #list)]
end

local function newInstance(className, properties, parent)
	local inst = Instance.new(className)
	for property, value in pairs(properties or {}) do
		inst[property] = value
	end
	inst.Parent = parent
	return inst
end

local function forceSquare(instance, aspectType)
	newInstance("UIAspectRatioConstraint", {
		AspectRatio = 1,
		AspectType = aspectType or Enum.AspectType.FitWithinMaxSize,
	}, instance)
end

--============================================================
-- SECTION 4: ROOT GUI
--============================================================

local gui = newInstance("ScreenGui", {
	Name = "LoadingScreen",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 10000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local root = newInstance("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromScale(0, 0),
	BackgroundColor3 = CONFIG.ColorBackgroundMid,
	BorderSizePixel = 0,
	ZIndex = 1,
	ClipsDescendants = true,
}, gui)

local bgGradient = newInstance("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CONFIG.ColorBackgroundTop),
		ColorSequenceKeypoint.new(0.5, CONFIG.ColorBackgroundMid),
		ColorSequenceKeypoint.new(1, CONFIG.ColorBackgroundBottom),
	}),
	Rotation = 90,
}, root)

-- Slow ambient gradient drift
Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		local tw = TweenService:Create(
			bgGradient,
			TweenInfo.new(16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Rotation = bgGradient.Rotation + 30 }
		)
		tw:Play()
		tw.Completed:Wait()
	end
end))

-- Tension tracker — read by several systems below so escalation is consistent
local tension = { level = 0 } -- 0 = calm, 1 = fully escalated

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		local targetColor = Color3.new(
			lerp(CONFIG.ColorBackgroundMid.R, CONFIG.ColorBackgroundTense.R, tension.level),
			lerp(CONFIG.ColorBackgroundMid.G, CONFIG.ColorBackgroundTense.G, tension.level),
			lerp(CONFIG.ColorBackgroundMid.B, CONFIG.ColorBackgroundTense.B, tension.level)
		)
		root.BackgroundColor3 = targetColor
		task.wait(0.2)
	end
end))

--============================================================
-- SECTION 5: DRIFTING FOG LAYERS
--============================================================

local fogLayer = newInstance("Frame", {
	Name = "FogLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 2,
	ClipsDescendants = true,
}, root)

local function buildFogBand(verticalScale, colorTint, alphaBase, speed, startScaleX)
	local band = newInstance("Frame", {
		Size = UDim2.fromScale(1.6, verticalScale),
		Position = UDim2.fromScale(startScaleX, math.random(0, 80) / 100),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = colorTint,
		BackgroundTransparency = alphaBase,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, fogLayer)

	newInstance("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, alphaBase),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, band)

	Lifecycle:track(task.spawn(function()
		while Lifecycle.active and band.Parent do
			local goingRight = band.Position.X.Scale < 0.5
			local targetX = goingRight and 1.3 or -0.3

			local tw = TweenService:Create(
				band,
				TweenInfo.new(speed, Enum.EasingStyle.Linear),
				{ Position = UDim2.fromScale(targetX, band.Position.Y.Scale) }
			)
			tw:Play()
			tw.Completed:Wait()

			if band.Parent then
				band.Position = UDim2.fromScale(goingRight and -0.3 or 1.3, math.random(0, 80) / 100)
			end
		end
	end))

	return band
end

buildFogBand(0.18, Color3.fromRGB(40, 20, 60), 0.9, 26, -0.3)
buildFogBand(0.14, Color3.fromRGB(15, 40, 25), 0.93, 34, 1.2)
buildFogBand(0.20, Color3.fromRGB(30, 10, 15), 0.94, 40, -0.5)
buildFogBand(0.10, Color3.fromRGB(50, 15, 20), 0.95, 48, 0.8)

--============================================================
-- SECTION 6: SCANLINE OVERLAY (subtle CRT texture)
--============================================================

local scanlineLayer = newInstance("Frame", {
	Name = "Scanlines",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 15,
}, root)

local SCANLINE_COUNT = 48
for i = 1, SCANLINE_COUNT do
	local y = i / SCANLINE_COUNT
	newInstance("Frame", {
		Size = UDim2.fromScale(1, 0.0016),
		Position = UDim2.fromScale(0, y),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		ZIndex = 15,
	}, scanlineLayer)
end

-- Very slow vertical drift of the whole scanline field for a subtle "signal" feel
Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		scanlineLayer.Position = UDim2.fromScale(0, 0)
		local tw = TweenService:Create(
			scanlineLayer,
			TweenInfo.new(4, Enum.EasingStyle.Linear),
			{ Position = UDim2.fromScale(0, 0.02) }
		)
		tw:Play()
		tw.Completed:Wait()
	end
end))

--============================================================
-- SECTION 7: VIGNETTE (darkened corners, heartbeat pulse)
--============================================================

local vignetteLayer = newInstance("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, root)

local vignetteCorners = {
	{ anchor = Vector2.new(0, 0), pos = UDim2.fromScale(0, 0), rotation = 135 },
	{ anchor = Vector2.new(1, 0), pos = UDim2.fromScale(1, 0), rotation = 225 },
	{ anchor = Vector2.new(0, 1), pos = UDim2.fromScale(0, 1), rotation = 45 },
	{ anchor = Vector2.new(1, 1), pos = UDim2.fromScale(1, 1), rotation = 315 },
}

local vignetteCornerFrames = {}
for _, corner in ipairs(vignetteCorners) do
	local cornerFrame = newInstance("Frame", {
		Size = UDim2.fromScale(0.55, 0.55),
		Position = corner.pos,
		AnchorPoint = corner.anchor,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, vignetteLayer)

	newInstance("UIGradient", {
		Rotation = corner.rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, cornerFrame)

	table.insert(vignetteCornerFrames, cornerFrame)
end

-- Heartbeat pulse — a double-thump darkening rhythm layered under everything else
Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		local beatGap = lerp(1.1, 0.5, tension.level)
		local pauseGap = lerp(1.6, 0.6, tension.level)

		for _, thumpCount in ipairs({ 1, 2 }) do
			for _, frame in ipairs(vignetteCornerFrames) do
				TweenService:Create(frame, TweenInfo.new(0.12), { BackgroundTransparency = 0.7 }):Play()
			end
			task.wait(0.12)
			for _, frame in ipairs(vignetteCornerFrames) do
				TweenService:Create(frame, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
			end
			task.wait(beatGap * 0.35)
		end

		task.wait(pauseGap)
	end
end))

--============================================================
-- SECTION 8: CORNER VINE / THORN ORNAMENTS (all four corners)
--============================================================

local function buildVineCluster(anchor, position, mirrorX)
	local cluster = newInstance("Frame", {
		Size = UDim2.fromScale(0.22, 0.22),
		Position = position,
		AnchorPoint = anchor,
		BackgroundTransparency = 1,
		ZIndex = 4,
	}, root)

	local segmentCount = 6
	for i = 1, segmentCount do
		local t = i / segmentCount
		local segment = newInstance("Frame", {
			Size = UDim2.fromScale(0.5 - t * 0.32, 0.045),
			Position = UDim2.fromScale(t * (mirrorX and -0.35 or 0.35), t * 0.55),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = mirrorX and (40 + t * 30) or (-40 - t * 30),
			BackgroundColor3 = Color3.fromRGB(35, 70, 40),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, cluster)
		newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, segment)

		if i % 2 == 0 then
			local leaf = newInstance("Frame", {
				Size = UDim2.fromScale(0.09, 0.09),
				Position = UDim2.fromScale(0.5, 0),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = CONFIG.ColorEssenceMid,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, segment)
			newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, leaf)
			forceSquare(leaf)
		end
	end

	return cluster
end

buildVineCluster(Vector2.new(0, 0), UDim2.fromScale(0, 0), false)
buildVineCluster(Vector2.new(1, 1), UDim2.fromScale(1, 1), true)
buildVineCluster(Vector2.new(1, 0), UDim2.fromScale(1, 0), true)
buildVineCluster(Vector2.new(0, 1), UDim2.fromScale(0, 1), false)

--============================================================
-- SECTION 9: AMBIENT PARTICLES — motes, embers, falling leaves
--============================================================

local particleLayer = newInstance("Frame", {
	Name = "ParticleLayer",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 3,
}, root)

-- Rising essence motes — small glowing orbs drifting upward
local function spawnMote()
	if not Lifecycle.active then return end

	local scaleSize = randomFloat(0.008, 0.02)
	local particle = newInstance("ImageLabel", {
		Size = UDim2.fromScale(scaleSize, scaleSize),
		Position = UDim2.fromScale(math.random(), 1.05),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = CONFIG.SmallOrbImage,
		ImageColor3 = CONFIG.ColorEssenceMid,
		ImageTransparency = 0.25,
		ZIndex = 3,
	}, particleLayer)
	forceSquare(particle)

	local driftX = randomFloat(-0.08, 0.08)
	local duration = randomFloat(6, 12)

	local tw = TweenService:Create(
		particle,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{
			Position = UDim2.fromScale(particle.Position.X.Scale + driftX, -0.06),
			ImageTransparency = 1,
		}
	)
	tw:Play()
	tw.Completed:Connect(function()
		if particle.Parent then particle:Destroy() end
	end)
end

-- Slow-drifting embers — warmer color, rarer, rise more lazily
local function spawnEmber()
	if not Lifecycle.active then return end

	local scaleSize = randomFloat(0.004, 0.01)
	local particle = newInstance("Frame", {
		Size = UDim2.fromScale(scaleSize, scaleSize),
		Position = UDim2.fromScale(math.random(), 1.05),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.ColorEmber,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, particleLayer)
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, particle)
	forceSquare(particle)

	local duration = randomFloat(9, 16)
	local sway = randomFloat(-0.04, 0.04)

	local tw = TweenService:Create(
		particle,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{
			Position = UDim2.fromScale(particle.Position.X.Scale + sway, -0.05),
			BackgroundTransparency = 1,
		}
	)
	tw:Play()
	tw.Completed:Connect(function()
		if particle.Parent then particle:Destroy() end
	end)
end

-- Falling leaves — drift downward with a swaying sine-wave path
local function spawnLeaf()
	if not Lifecycle.active then return end

	local scaleSize = randomFloat(0.01, 0.022)
	local leaf = newInstance("Frame", {
		Size = UDim2.fromScale(scaleSize, scaleSize * 0.6),
		Position = UDim2.fromScale(math.random(), -0.05),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.ColorEssenceDark,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Rotation = math.random(0, 360),
		ZIndex = 3,
	}, particleLayer)
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, leaf)

	local baseX = leaf.Position.X.Scale
	local duration = randomFloat(7, 13)
	local swayAmplitude = randomFloat(0.02, 0.05)
	local startClock = os.clock()

	Lifecycle:track(task.spawn(function()
		while leaf.Parent and Lifecycle.active do
			local t = (os.clock() - startClock) / duration
			if t >= 1 then break end
			local swayX = baseX + math.sin(t * math.pi * 4) * swayAmplitude
			leaf.Position = UDim2.fromScale(swayX, lerp(-0.05, 1.05, t))
			leaf.Rotation = leaf.Rotation + 0.6
			leaf.BackgroundTransparency = lerp(0.3, 1, t)
			task.wait()
		end
		if leaf.Parent then leaf:Destroy() end
	end))
end

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		spawnMote()
		task.wait(randomFloat(0.12, 0.3))
	end
end))

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		task.wait(randomFloat(1.4, 2.6))
		spawnEmber()
	end
end))

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		task.wait(randomFloat(0.9, 1.8))
		spawnLeaf()
	end
end))

--============================================================
-- SECTION 10: TITLE + CHROMATIC ABERRATION GLITCH LAYER
--============================================================

local titleHolder = newInstance("Frame", {
	Name = "TitleHolder",
	Size = UDim2.fromScale(0.6, 0.08),
	Position = UDim2.fromScale(0.5, 0.14),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, root)

-- Ghost copies rendered behind the real title, nudged off-color, hidden by
-- default. During glitch events they flash into slightly offset positions.
local titleGhostRed = newInstance("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = CONFIG.ColorOverlordRed,
	TextTransparency = 1,
	TextScaled = true,
	ZIndex = 5,
}, titleHolder)
newInstance("UITextSizeConstraint", { MaxTextSize = 44, MinTextSize = 20 }, titleGhostRed)

local titleGhostCyan = newInstance("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromScale(0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = CONFIG.ColorGlitchCyan,
	TextTransparency = 1,
	TextScaled = true,
	ZIndex = 5,
}, titleHolder)
newInstance("UITextSizeConstraint", { MaxTextSize = 44, MinTextSize = 20 }, titleGhostCyan)

local title = newInstance("TextLabel", {
	Name = "Title",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = CONFIG.ColorTextPrimary,
	TextScaled = true,
	TextTransparency = 0,
	ZIndex = 6,
}, titleHolder)
newInstance("UITextSizeConstraint", { MaxTextSize = 44, MinTextSize = 20 }, title)

local titleStroke = newInstance("UIStroke", {
	Color = CONFIG.ColorEssenceMid,
	Thickness = 1.5,
	Transparency = 0.2,
}, title)

local FULL_TITLE = "ESSENCEBOUND"
local sounds = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("GlitchSounds")
local glitchSound1 = sounds:WaitForChild("Sound1")
local glitchsound2 = sounds:WaitForChild("Sound2")
local glitchsound3 = sounds:WaitForChild("Sound3")

Lifecycle:track(task.spawn(function()
	for i = 1, #FULL_TITLE do
		if not Lifecycle.active then return end
		local partial = string.sub(FULL_TITLE, 1, i)
		title.Text = partial
		titleGhostRed.Text = partial
		titleGhostCyan.Text = partial
		task.wait(0.035)
	end
end))

local function effectChromaticGlitch()

	titleGhostRed.Position = UDim2.fromScale(-0.01, 0)
	titleGhostCyan.Position = UDim2.fromScale(0.01, 0)
	titleGhostRed.TextTransparency = 0.35
	titleGhostCyan.TextTransparency = 0.35
	local num = math.random(1, 3)
	if num == 1 then
		glitchSound1:Play()
	elseif num == 2 then
		glitchsound2:Play()
	else
		glitchsound3:Play()
	end
	task.wait(randomFloat(0.06, 0.14))
	titleGhostRed.TextTransparency = 1
	titleGhostCyan.TextTransparency = 1
	titleGhostRed.Position = UDim2.fromScale(0, 0)
	titleGhostCyan.Position = UDim2.fromScale(0, 0)
end

--============================================================
-- SECTION 11: CENTERPIECE — ORB, RUNE RING, SATELLITES
--============================================================

local centerHolder = newInstance("Frame", {
	Name = "Center",
	Size = UDim2.fromScale(0.42, 0.42),
	Position = UDim2.fromScale(0.5, 0.46),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, root)
forceSquare(centerHolder)

-- Soft bloom, built from stacked translucent layers
local glowStack = newInstance("Frame", {
	Size = UDim2.fromScale(1, 1),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, centerHolder)

for i = 1, 4 do
	local glow = newInstance("Frame", {
		Size = UDim2.fromScale(1 + i * 0.12, 1 + i * 0.12),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = CONFIG.ColorEssenceMid,
		BackgroundTransparency = 0.86 + i * 0.03,
		BorderSizePixel = 0,
		ZIndex = 6 - i,
	}, glowStack)
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	forceSquare(glow)
end

-- Static rune ring — a circle of thin tick marks around the orb, distinct
-- from the orbiting satellites, rotating slowly in the opposite direction
local runeRing = newInstance("Frame", {
	Size = UDim2.fromScale(1.15, 1.15),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, centerHolder)
forceSquare(runeRing)

local RUNE_TICK_COUNT = 20
for i = 1, RUNE_TICK_COUNT do
	local angle = (i / RUNE_TICK_COUNT) * 360
	local tick = newInstance("Frame", {
		Size = UDim2.fromScale(0.02, 0.09),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 1.55),
		Rotation = angle,
		BackgroundColor3 = CONFIG.ColorGoldAccent,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, runeRing)
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, tick)
end

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		runeRing.Rotation = (runeRing.Rotation - 0.08) % 360
		task.wait()
	end
end))

-- Main orb
local orb = newInstance("ImageLabel", {
	Name = "Orb",
	Size = UDim2.fromScale(0.72, 0.72),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Image = CONFIG.LargeOrbImage,
	ZIndex = 8,
}, centerHolder)
forceSquare(orb)

-- One-shot shockwave ring burst, fired once when the title finishes typing
local function fireShockwave()
	local ring = newInstance("Frame", {
		Size = UDim2.fromScale(0.72, 0.72),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 8,
	}, centerHolder)
	newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
	local ringStroke = newInstance("UIStroke", {
		Color = CONFIG.ColorEssenceBright,
		Thickness = 3,
		Transparency = 0.1,
	}, ring)
	forceSquare(ring)

	local tw = TweenService:Create(
		ring,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(2.2, 2.2) }
	)
	local strokeTw = TweenService:Create(ringStroke, TweenInfo.new(0.9), { Transparency = 1 })
	tw:Play()
	strokeTw:Play()
	tw.Completed:Connect(function()
		ring:Destroy()
	end)
end

Lifecycle:track(task.spawn(function()
	task.wait(0.035 * #FULL_TITLE + 0.15)
	if Lifecycle.active then
		fireShockwave()
	end
end))

-- Breathing pulse
Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		local grow = TweenService:Create(
			centerHolder,
			TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Size = UDim2.fromScale(0.44, 0.44) }
		)
		grow:Play()
		grow.Completed:Wait()
		if not Lifecycle.active then break end
		local shrink = TweenService:Create(
			centerHolder,
			TweenInfo.new(1.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Size = UDim2.fromScale(0.40, 0.40) }
		)
		shrink:Play()
		shrink.Completed:Wait()
	end
end))

-- Orbit container for satellites
local orbitContainer = newInstance("Frame", {
	Size = UDim2.fromScale(1.5, 1.5),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 7,
}, centerHolder)
forceSquare(orbitContainer)

local SATELLITE_COUNT = 7
local satellites = {}

for i = 1, SATELLITE_COUNT do
	local satSize = randomFloat(0.05, 0.09)
	local satellite = newInstance("ImageLabel", {
		Size = UDim2.fromScale(satSize, satSize),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = CONFIG.SmallOrbImage,
		ZIndex = 7,
	}, orbitContainer)
	forceSquare(satellite)

	satellites[i] = {
		instance = satellite,
		angleOffset = (i / SATELLITE_COUNT) * (2 * math.pi),
		radius = randomFloat(0.36, 0.44),
		speedMultiplier = randomFloat(0.7, 1.3),
	}
end

local orbitAngle = 0
Lifecycle:track(RunService.RenderStepped:Connect(function(dt)
	orbitAngle += dt * 0.6
	for _, sat in ipairs(satellites) do
		local angle = orbitAngle * sat.speedMultiplier + sat.angleOffset
		local x = 0.5 + math.cos(angle) * sat.radius
		local y = 0.5 + math.sin(angle) * sat.radius
		sat.instance.Position = UDim2.fromScale(x, y)
	end
end))

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		orbitContainer.Rotation = (orbitContainer.Rotation + 0.15) % 360
		task.wait()
	end
end))

--============================================================
-- SECTION 12: FLAVOR TEXT (lore, typewriter cycling)
--============================================================

local flavorHolder = newInstance("Frame", {
	Size = UDim2.fromScale(0.6, 0.06),
	Position = UDim2.fromScale(0.5, 0.66),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, root)

local flavorText = newInstance("TextLabel", {
	Name = "FlavorText",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = CONFIG.ColorTextSecondary,
	TextTransparency = 0.1,
	TextScaled = true,
	TextWrapped = true,
	ZIndex = 6,
}, flavorHolder)
newInstance("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 12 }, flavorText)

--============================================================
-- SECTION 13: CORNER WHISPER LAYER (quiet, off-center murmurs)
--============================================================

local cornerWhisperLabel = newInstance("TextLabel", {
	Size = UDim2.fromScale(0.3, 0.04),
	Position = UDim2.fromScale(0.14, 0.9),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = CONFIG.ColorTextFaint,
	TextTransparency = 1,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
}, root)
newInstance("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 9 }, cornerWhisperLabel)

local function effectCornerWhisper()
	local corners = {
		{ pos = UDim2.fromScale(0.03, 0.08), anchor = Vector2.new(0, 0), align = Enum.TextXAlignment.Left },
		{ pos = UDim2.fromScale(0.97, 0.08), anchor = Vector2.new(1, 0), align = Enum.TextXAlignment.Right },
		{ pos = UDim2.fromScale(0.03, 0.92), anchor = Vector2.new(0, 1), align = Enum.TextXAlignment.Left },
		{ pos = UDim2.fromScale(0.97, 0.92), anchor = Vector2.new(1, 1), align = Enum.TextXAlignment.Right },
	}
	local chosen = pickRandom(corners)
	cornerWhisperLabel.Position = chosen.pos
	cornerWhisperLabel.AnchorPoint = chosen.anchor
	cornerWhisperLabel.TextXAlignment = chosen.align
	cornerWhisperLabel.Text = pickRandom(CONFIG.CornerWhispers)

	TweenService:Create(cornerWhisperLabel, TweenInfo.new(0.5), { TextTransparency = 0.3 }):Play()
	task.wait(randomFloat(1.0, 1.8))
	TweenService:Create(cornerWhisperLabel, TweenInfo.new(0.8), { TextTransparency = 1 }):Play()
end

--============================================================
-- SECTION 14: DRIFTING RUNIC SYMBOLS (rare background ambience)
--============================================================

local function effectSymbolDrift()
	local symbol = newInstance("TextLabel", {
		Size = UDim2.fromScale(0.05, 0.08),
		Position = UDim2.fromScale(randomFloat(0.1, 0.9), randomFloat(0.15, 0.85)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = pickRandom(CONFIG.DriftSymbols),
		TextColor3 = CONFIG.ColorEssenceMid,
		TextTransparency = 1,
		TextScaled = true,
		ZIndex = 4,
	}, root)
	newInstance("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14 }, symbol)

	TweenService:Create(symbol, TweenInfo.new(0.5), { TextTransparency = 0.55 }):Play()
	task.wait(randomFloat(0.5, 1.0))
	local fadeOut = TweenService:Create(symbol, TweenInfo.new(0.7), { TextTransparency = 1 })
	fadeOut:Play()
	fadeOut.Completed:Wait()
	symbol:Destroy()
end

--============================================================
-- SECTION 15: MARQUEE WHISPER TICKER
--============================================================

local tickerClip = newInstance("Frame", {
	Size = UDim2.fromScale(1, 0.025),
	Position = UDim2.fromScale(0, 0.985),
	AnchorPoint = Vector2.new(0, 0.5),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	ZIndex = 6,
}, root)

local tickerText = newInstance("TextLabel", {
	Size = UDim2.fromScale(3, 1),
	Position = UDim2.fromScale(1, 0),
	AnchorPoint = Vector2.new(0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = table.concat(CONFIG.TickerFragments):rep(2),
	TextColor3 = CONFIG.ColorTextFaint,
	TextTransparency = 0.35,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 6,
}, tickerClip)
newInstance("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, tickerText)

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		tickerText.Position = UDim2.fromScale(1, 0)
		local tw = TweenService:Create(
			tickerText,
			TweenInfo.new(22, Enum.EasingStyle.Linear),
			{ Position = UDim2.fromScale(-2, 0) }
		)
		tw:Play()
		tw.Completed:Wait()
	end
end))

--============================================================
-- SECTION 16: PROGRESS BAR
--============================================================

local barBack = newInstance("Frame", {
	Name = "ProgressBarBack",
	Size = UDim2.fromScale(0.32, 0.032),
	Position = UDim2.fromScale(0.5, 0.85),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(20, 14, 30),
	BorderSizePixel = 0,
	ZIndex = 6,
	ClipsDescendants = true,
}, root)

newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)
local barBackStroke = newInstance("UIStroke", {
	Color = CONFIG.ColorGoldAccent,
	Thickness = 1.5,
	Transparency = 0.3,
}, barBack)

local barFill = newInstance("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = CONFIG.ColorEssenceMid,
	BorderSizePixel = 0,
	ZIndex = 7,
}, barBack)

newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, barFill)
newInstance("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CONFIG.ColorEssenceBright),
		ColorSequenceKeypoint.new(1, CONFIG.ColorEssenceDark),
	}),
}, barFill)

local shimmer = newInstance("Frame", {
	Size = UDim2.fromScale(0.16, 1),
	Position = UDim2.fromScale(-0.2, 0),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.75,
	BorderSizePixel = 0,
	ZIndex = 8,
}, barFill)
newInstance("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, shimmer)

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		shimmer.Position = UDim2.fromScale(-0.2, 0)
		local tw = TweenService:Create(
			shimmer,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = UDim2.fromScale(1.05, 0) }
		)
		tw:Play()
		tw.Completed:Wait()
		task.wait(0.5)
	end
end))

local percentLabel = newInstance("TextLabel", {
	Size = UDim2.fromScale(0.32, 0.03),
	Position = UDim2.fromScale(0.5, 0.895),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "0%",
	TextColor3 = CONFIG.ColorTextSecondary,
	TextScaled = true,
	ZIndex = 6,
}, root)
newInstance("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 10 }, percentLabel)

local stageLabel = newInstance("TextLabel", {
	Size = UDim2.fromScale(0.4, 0.028),
	Position = UDim2.fromScale(0.5, 0.8),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = CONFIG.ColorGoldAccent,
	TextScaled = true,
	ZIndex = 6,
}, root)
newInstance("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 10 }, stageLabel)

local stageCounterLabel = newInstance("TextLabel", {
	Size = UDim2.fromScale(0.2, 0.022),
	Position = UDim2.fromScale(0.5, 0.775),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "",
	TextColor3 = CONFIG.ColorTextFaint,
	TextTransparency = 0.3,
	TextScaled = true,
	ZIndex = 6,
}, root)
newInstance("UITextSizeConstraint", { MaxTextSize = 11, MinTextSize = 8 }, stageCounterLabel)

--============================================================
-- SECTION 17: OVERLORD WHISPER + EYES + SILHOUETTE + CRACKS
--============================================================

local overlordLabel = newInstance("TextLabel", {
	Name = "OverlordWhisper",
	Size = UDim2.fromScale(0.9, 0.1),
	Position = UDim2.fromScale(0.5, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = CONFIG.ColorOverlordRed,
	TextTransparency = 1,
	TextScaled = true,
	ZIndex = 20,
}, root)
newInstance("UITextSizeConstraint", { MaxTextSize = 40, MinTextSize = 18 }, overlordLabel)
pcall(function() overlordLabel.Font = Enum.Font.Creepster end)

local eyesHolder = newInstance("Frame", {
	Size = UDim2.fromScale(0.14, 0.03),
	Position = UDim2.fromScale(0.5, 0.28),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	ZIndex = 4,
}, root)

local eyeLeft = newInstance("Frame", {
	Size = UDim2.fromScale(0.4, 1),
	Position = UDim2.fromScale(0.2, 0.5),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = CONFIG.ColorOverlordRed,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 4,
}, eyesHolder)
newInstance("UICorner", { CornerRadius = UDim.new(1, 0) }, eyeLeft)
forceSquare(eyeLeft)

local eyeRight = eyeLeft:Clone()
eyeRight.Position = UDim2.fromScale(0.8, 0.5)
eyeRight.Parent = eyesHolder

local silhouette = newInstance("Frame", {
	Size = UDim2.fromScale(0.1, 0.42),
	Position = UDim2.fromScale(0.92, 0.72),
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 4,
}, root)
newInstance("UICorner", { CornerRadius = UDim.new(0.5, 0) }, silhouette)

-- Crack layer — thin jagged lines that flash across the screen briefly
local crackLayer = newInstance("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 18,
}, root)

local crackLines = {}
for i = 1, 5 do
	local crack = newInstance("Frame", {
		Size = UDim2.fromScale(randomFloat(0.3, 0.6), 0.004),
		Position = UDim2.fromScale(randomFloat(0.1, 0.9), randomFloat(0.1, 0.9)),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = randomFloat(-60, 60),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 18,
	}, crackLayer)
	table.insert(crackLines, crack)
end

--============================================================
-- SECTION 18: OMINOUS EFFECT FUNCTIONS
--============================================================

local function screenShake(intensity, duration)
	local originalPos = root.Position
	local startClock = os.clock()
	while os.clock() - startClock < duration and Lifecycle.active do
		local offsetX = randomFloat(-intensity, intensity)
		local offsetY = randomFloat(-intensity, intensity)
		root.Position = UDim2.fromScale(originalPos.X.Scale + offsetX, originalPos.Y.Scale + offsetY)
		RunService.RenderStepped:Wait()
	end
	root.Position = originalPos
end

local function effectOverlordWhisper()
	local line = pickRandom(CONFIG.OverlordLines)
	overlordLabel.Text = line
	overlordLabel.TextTransparency = 0
	task.spawn(function() screenShake(0.006, 0.18) end)
	task.wait(randomFloat(0.1, 0.22))
	overlordLabel.TextTransparency = 1
end

local function effectRedFlash()
	local num = math.random(1, 3)
	if num == 1 then
		glitchSound1:Play()
	elseif num == 2 then
		glitchsound2:Play()
	else
		glitchsound3:Play()
	end
	local originalColor = root.BackgroundColor3
	root.BackgroundColor3 = Color3.fromRGB(25, 4, 4)
	task.spawn(function() screenShake(0.004, 0.12) end)
	task.wait(0.09)
	root.BackgroundColor3 = originalColor
end

local function effectEyesOpen()
	eyesHolder.Position = UDim2.fromScale(randomFloat(0.3, 0.7), randomFloat(0.15, 0.4))
	local fadeIn = TweenService:Create(eyeLeft, TweenInfo.new(0.15), { BackgroundTransparency = 0.35 })
	local fadeIn2 = TweenService:Create(eyeRight, TweenInfo.new(0.15), { BackgroundTransparency = 0.35 })
	fadeIn:Play()
	fadeIn2:Play()
	task.wait(randomFloat(0.4, 0.9))
	TweenService:Create(eyeLeft, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(eyeRight, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
end

local function effectSilhouette()
	local fromSide = math.random() > 0.5
	silhouette.Position = UDim2.fromScale(fromSide and 0.96 or 0.04, 0.72)
	silhouette.AnchorPoint = Vector2.new(fromSide and 1 or 0, 1)
	TweenService:Create(silhouette, TweenInfo.new(0.25), { BackgroundTransparency = 0.55 }):Play()
	task.wait(randomFloat(0.3, 0.6))
	TweenService:Create(silhouette, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

local GLITCH_CHARS = "!@#$%&*^~?"

local function effectTextGlitch()

	local original = flavorText.Text
	if original == "" then return end
	local num = math.random(1, 3)
	if num == 1 then
		glitchSound1:Play()
	elseif num == 2 then
		glitchsound2:Play()
	else
		glitchsound3:Play()
	end
	for _ = 1, 4 do
		local scrambled = {}
		for i = 1, #original do
			local char = string.sub(original, i, i)
			if char ~= " " and math.random() < 0.4 then
				char = string.sub(GLITCH_CHARS, math.random(1, #GLITCH_CHARS), math.random(1, #GLITCH_CHARS))
			end
			table.insert(scrambled, char)
		end
		flavorText.Text = table.concat(scrambled)
		task.wait(0.045)
	end
	flavorText.Text = original
end

local progressStutterFlag = { active = false }
local function effectProgressStutter()
	progressStutterFlag.active = true
	task.wait(randomFloat(0.15, 0.3))
	progressStutterFlag.active = false
end

local function effectCrackFlash()
	local num = math.random(1, 3)
	if num == 1 then
		glitchSound1:Play()
	elseif num == 2 then
		glitchsound2:Play()
	else
		glitchsound3:Play()
	end
	for _, crack in ipairs(crackLines) do
		crack.Position = UDim2.fromScale(randomFloat(0.1, 0.9), randomFloat(0.1, 0.9))
		crack.Rotation = randomFloat(-60, 60)
		crack.Size = UDim2.fromScale(randomFloat(0.3, 0.6), 0.004)
	end
	for _, crack in ipairs(crackLines) do
		crack.BackgroundTransparency = randomFloat(0.2, 0.5)
	end
	task.spawn(function() screenShake(0.005, 0.1) end)
	task.wait(0.08)
	for _, crack in ipairs(crackLines) do
		crack.BackgroundTransparency = 1
	end
end

local function effectTremor()
	local num = math.random(1, 3)
	if num == 1 then
		glitchSound1:Play()
	elseif num == 2 then
		glitchsound2:Play()
	else
		glitchsound3:Play()
	end
	screenShake(0.012, 0.35)
end

-- Weighted pool: {func, weight}. Higher weight = more common.
local OMINOUS_POOL = {
	{ effectOverlordWhisper, 3 },
	{ effectRedFlash, 2 },
	{ effectEyesOpen, 3 },
	{ effectSilhouette, 2 },
	{ effectTextGlitch, 3 },
	{ effectProgressStutter, 2 },
	{ effectCornerWhisper, 3 },
	{ effectSymbolDrift, 2 },
	{ effectChromaticGlitch, 2 },
	{ effectCrackFlash, 1 },
	{ effectTremor, 1 },
}

local function pickWeighted(pool)
	local total = 0
	for _, entry in ipairs(pool) do
		total += entry[2]
	end
	local roll = randomFloat(0, total)
	local cumulative = 0
	for _, entry in ipairs(pool) do
		cumulative += entry[2]
		if roll <= cumulative then
			return entry[1]
		end
	end
	return pool[#pool][1]
end

Lifecycle:track(task.spawn(function()
	while Lifecycle.active do
		local minGap = lerp(CONFIG.OminousMinGap, CONFIG.EscalatedMinGap, tension.level)
		local maxGap = lerp(CONFIG.OminousMaxGap, CONFIG.EscalatedMaxGap, tension.level)
		task.wait(randomFloat(minGap, maxGap))
		if not Lifecycle.active then break end
		local effect = pickWeighted(OMINOUS_POOL)

		local ok = pcall(effect)
		if not ok then
			-- swallow effect errors so one bad effect can't break the loop
		end
	end
end))

--============================================================
-- SECTION 19: STAGE TEXT DRIVER
--============================================================

local currentStageIndex = 0

local function updateStageText(progress)
	local newIndex = currentStageIndex
	for i, stage in ipairs(CONFIG.StageText) do
		if progress >= stage.threshold then
			newIndex = i
		end
	end

	if newIndex ~= currentStageIndex then
		currentStageIndex = newIndex
		local stage = CONFIG.StageText[currentStageIndex]

		local fadeOut = TweenService:Create(stageLabel, TweenInfo.new(0.2), { TextTransparency = 1 })
		fadeOut:Play()
		fadeOut.Completed:Wait()
		stageLabel.Text = stage.text
		stageCounterLabel.Text = string.format("STAGE %d / %d", currentStageIndex, #CONFIG.StageText)
		TweenService:Create(stageLabel, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	end

	tension.level = math.clamp((progress - CONFIG.EscalationThreshold) / (1 - CONFIG.EscalationThreshold), 0, 1)
end

--============================================================
-- SECTION 20: FLAVOR TEXT CYCLER
--============================================================

Lifecycle:track(task.spawn(function()
	local index = 0
	while Lifecycle.active do
		index = (index % #CONFIG.FlavorLines) + 1
		local line = CONFIG.FlavorLines[index]

		flavorText.Text = ""
		for c = 1, #line do
			if not Lifecycle.active then return end
			flavorText.Text = string.sub(line, 1, c)
			task.wait(0.014)
		end

		task.wait(randomFloat(0.9, 1.4))
	end
end))

--============================================================
-- SECTION 21: ASSET PRELOADING
--============================================================

local startClock = os.clock()
local loadingComplete = false
local realProgress = 0

Lifecycle:track(task.spawn(function()
	local assets = game:GetDescendants()
	local total = math.max(#assets, 1)
	local loaded = 0

	-- Batched into a single PreloadAsync call (was one call per descendant,
	-- serially -- much slower on low-end/mobile devices, and this loading
	-- screen is the very first thing every new player waits through). The
	-- per-asset callback still drives the same progressive loading bar.
	local ok = pcall(function()
		ContentProvider:PreloadAsync(assets, function()
			loaded += 1
			realProgress = loaded / total
		end)
	end)

	if not ok then
		realProgress = 1
	end

	loadingComplete = true
end))

--============================================================
-- SECTION 22: PROGRESS BAR DRIVER
--============================================================

local displayedProgress = 0

Lifecycle:track(RunService.RenderStepped:Connect(function()
	local elapsed = os.clock() - startClock
	local timeFloor = math.clamp(elapsed / CONFIG.MinDisplayTime, 0, 0.97)
	local target = math.max(realProgress, timeFloor)

	if loadingComplete and elapsed >= CONFIG.MinDisplayTime then
		target = 1
	end

	if progressStutterFlag.active then
		target = math.max(0, target - 0.05)
	end

	displayedProgress = lerp(displayedProgress, target, 0.16)
	if target >= 0.999 and displayedProgress > 0.995 then
		displayedProgress = 1
	end

	barFill.Size = UDim2.fromScale(displayedProgress, 1)
	percentLabel.Text = math.floor(displayedProgress * 100) .. "%"
	updateStageText(displayedProgress)
end))

--============================================================
-- SECTION 23: "PRESS TO CONTINUE" PROMPT + SKIP BUTTON
--============================================================

local playerReady = false
local acceptAnyKeyInput = false -- flips true only once loading has genuinely finished
local TweenServiceRef = TweenService -- local alias, kept for parity with original naming used below

local function finishLoading()
	if playerReady then return end
	playerReady = true
end

-- "click or press any key" prompt — appears once loading has actually
-- finished (kept from the original behavior), so it still communicates
-- "we're done, jump in whenever."
local continuePrompt = newInstance("TextLabel", {
	Size = UDim2.fromScale(0.3, 0.03),
	Position = UDim2.fromScale(0.5, 0.93),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "click or press any key to enter",
	TextColor3 = CONFIG.ColorTextSecondary,
	TextTransparency = 1,
	TextScaled = true,
	ZIndex = 6,
}, root)
newInstance("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 9 }, continuePrompt)

-- Skip button — fades in CONFIG.SkipButtonDelay seconds after the screen
-- opens, regardless of load progress, so impatient players always have an
-- escape hatch even during a slow preload.
local skipButton = newInstance("TextButton", {
	Name = "SkipButton",
	Size = UDim2.fromScale(0.12, 0.045),
	Position = UDim2.fromScale(0.96, 0.05),
	AnchorPoint = Vector2.new(1, 0),
	BackgroundColor3 = Color3.fromRGB(30, 16, 46),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "SKIP ▸",
	TextColor3 = CONFIG.ColorTextSecondary,
	TextTransparency = 1,
	TextScaled = true,
	ZIndex = 25,
}, root)
newInstance("UICorner", { CornerRadius = UDim.new(0.3, 0) }, skipButton)
local skipStroke = newInstance("UIStroke", {
	Color = CONFIG.ColorGoldAccent,
	Thickness = 1.5,
	Transparency = 1,
}, skipButton)
newInstance("UIPadding", {
	PaddingLeft = UDim.new(0.08, 0),
	PaddingRight = UDim.new(0.08, 0),
}, skipButton)
local skipTextConstraint = newInstance("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 9 }, skipButton)

skipButton.MouseEnter:Connect(function()
	TweenService:Create(skipButton, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(50, 28, 74) }):Play()
	TweenService:Create(skipButton, TweenInfo.new(0.15), { TextColor3 = CONFIG.ColorTextPrimary }):Play()
end)
skipButton.MouseLeave:Connect(function()
	TweenService:Create(skipButton, TweenInfo.new(0.15), { BackgroundColor3 = Color3.fromRGB(30, 16, 46) }):Play()
	TweenService:Create(skipButton, TweenInfo.new(0.15), { TextColor3 = CONFIG.ColorTextSecondary }):Play()
end)
skipButton.MouseButton1Click:Connect(function()
	finishLoading()
end)

Lifecycle:track(task.delay(CONFIG.SkipButtonDelay, function()
	if not Lifecycle.active or playerReady then return end
	acceptAnyKeyInput = true
	TweenService:Create(skipButton, TweenInfo.new(0.4), { BackgroundTransparency = 0.15 }):Play()
	TweenService:Create(skipButton, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(skipStroke, TweenInfo.new(0.4), { Transparency = 0.3 }):Play()
end))

-- Once real loading + the min display time are both done, reveal the
-- "click or press any key" prompt and let any key/click finish things.
Lifecycle:track(task.spawn(function()
	while Lifecycle.active and not playerReady and (not loadingComplete or displayedProgress < 0.999 or (os.clock() - startClock) < CONFIG.MinDisplayTime) do
		task.wait(0.1)
	end

	if not Lifecycle.active or playerReady then return end

	acceptAnyKeyInput = true
	TweenService:Create(continuePrompt, TweenInfo.new(0.5), { TextTransparency = 0.2 }):Play()

	Lifecycle:track(task.spawn(function()
		while Lifecycle.active and continuePrompt.Parent and not playerReady do
			local fadeOut = TweenService:Create(continuePrompt, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextTransparency = 0.7 })
			fadeOut:Play()
			fadeOut.Completed:Wait()
			if not continuePrompt.Parent or playerReady then break end
			local fadeIn = TweenService:Create(continuePrompt, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextTransparency = 0.2 })
			fadeIn:Play()
			fadeIn.Completed:Wait()
		end
	end))
end))

local inputConnection
local ready = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LoadingDone")

inputConnection = UserInputService.InputBegan:Connect(function(_, gameProcessed)
	if gameProcessed or playerReady or not acceptAnyKeyInput then return end
	finishLoading()
end)

Lifecycle:track(inputConnection)

-- Grace period fallback: if nobody clicks/presses/skips, auto-continue
-- shortly after loading has ACTUALLY finished — meaning real asset preload
-- is done, the progress bar has visibly caught up to 100%, and the minimum
-- display time has elapsed. Only loadingComplete was checked before, which
-- can flip true almost instantly on small games, causing the screen to
-- close far too early.
task.spawn(function()
	while not playerReady and (not loadingComplete or displayedProgress < 0.999 or (os.clock() - startClock) < CONFIG.MinDisplayTime) do
		task.wait(0.1)
	end
	if playerReady then return end

	local waited = 0
	while not playerReady and waited < CONFIG.GraceAfterComplete do
		task.wait(0.1)
		waited += 0.1
	end
	finishLoading()
end)

CONFIG.Music:Play()

while not playerReady do
	task.wait(0.05)
end

if inputConnection.Connected then
	inputConnection:Disconnect()
end

local fadeOutTween = TweenService:Create(CONFIG.Music, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
	Volume = 0,
})
fadeOutTween:Play()
fadeOutTween.Completed:Wait()

CONFIG.Music:Stop()
CONFIG.Music.Volume = CONFIG.Music:GetAttribute("OriginalVolume") or CONFIG.Music.Volume -- restore volume for next time it plays
ready:Fire("Done")

--============================================================
-- SECTION 24: FADE OUT + FULL CLEANUP
--============================================================

Lifecycle:shutdown()

local fadeTargets = {
	{ instance = root, prop = "BackgroundTransparency", value = 1 },
	{ instance = title, prop = "TextTransparency", value = 1 },
	{ instance = titleStroke, prop = "Transparency", value = 1 },
	{ instance = flavorText, prop = "TextTransparency", value = 1 },
	{ instance = barBack, prop = "BackgroundTransparency", value = 1 },
	{ instance = barBackStroke, prop = "Transparency", value = 1 },
	{ instance = barFill, prop = "BackgroundTransparency", value = 1 },
	{ instance = percentLabel, prop = "TextTransparency", value = 1 },
	{ instance = stageLabel, prop = "TextTransparency", value = 1 },
	{ instance = stageCounterLabel, prop = "TextTransparency", value = 1 },
	{ instance = continuePrompt, prop = "TextTransparency", value = 1 },
	{ instance = skipButton, prop = "TextTransparency", value = 1 },
	{ instance = skipButton, prop = "BackgroundTransparency", value = 1 },
	{ instance = skipStroke, prop = "Transparency", value = 1 },
	{ instance = orb, prop = "ImageTransparency", value = 1 },
	{ instance = tickerText, prop = "TextTransparency", value = 1 },
}

for _, target in ipairs(fadeTargets) do
	TweenService:Create(target.instance, TweenInfo.new(CONFIG.FadeTime, Enum.EasingStyle.Quad), { [target.prop] = target.value }):Play()
end

for _, satellite in ipairs(satellites) do
	TweenService:Create(satellite.instance, TweenInfo.new(CONFIG.FadeTime, Enum.EasingStyle.Quad), { ImageTransparency = 1 }):Play()
end

task.wait(CONFIG.FadeTime + 0.1)
gui:Destroy()
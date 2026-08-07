--[[
	AmbientBackground (LocalScript -> StarterPlayerScripts)
	=======================================================
	A living backdrop for the game: slow drifting essence motes at several
	parallax depths, a gently shifting colour wash, and a soft vignette to
	frame the play area.

	WHY
	----
	The game is played entirely in a ScreenGui, so whatever sits behind the
	orb IS the environment -- there's no 3D world doing that job. A static
	background makes even a well-animated foreground feel flat and cheap,
	which matters a lot for the audience this game is aimed at.

	WHERE IT SITS
	--------------
	Its own ScreenGui at DisplayOrder -10, so it renders BEHIND every
	existing interface without any of them needing to know it exists. All
	of its contents are plain Frames with no Active flag, so it can never
	intercept a click meant for the orb or a button.

	PERFORMANCE
	------------
	Phones and low-end laptops are the majority of this audience, so:
	  - every mote is created ONCE and then reused forever (a fixed pool),
	    so there is no per-frame instance churn or garbage,
	  - motion is driven by TweenService rather than a RunService loop, so
	    the work happens in Roblox's own scheduler,
	  - counts are deliberately modest and scale down automatically on
	    small screens (see MOTE_COUNT / isSmallScreen below).

	Nothing here reads or writes gameplay state. It is decoration only, and
	can be deleted wholesale with no other file caring.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================================================================
-- PALETTE + TUNING
-- =========================================================================
-- Colours follow the game's existing deep-purple / essence-green identity
-- so this reads as the same world the UI lives in.

local COLOR_DEEP = Color3.fromRGB(16, 8, 28)
local COLOR_MID = Color3.fromRGB(30, 15, 50)
local COLOR_GLOW_A = Color3.fromRGB(70, 180, 120)   -- essence green
local COLOR_GLOW_B = Color3.fromRGB(120, 70, 200)   -- arcane purple

local MOTE_COLORS = {
	Color3.fromRGB(140, 255, 190),
	Color3.fromRGB(190, 160, 255),
	Color3.fromRGB(255, 230, 160),
}

-- Three parallax layers. Nearer motes are bigger, brighter and faster,
-- which is what sells depth on a flat 2D backdrop.
local LAYERS = {
	{ Count = 10, SizeRange = { 3, 5 },  Transparency = 0.75, SpeedRange = { 26, 40 } },
	{ Count = 8,  SizeRange = { 5, 8 },  Transparency = 0.6,  SpeedRange = { 16, 26 } },
	{ Count = 5,  SizeRange = { 9, 14 }, Transparency = 0.45, SpeedRange = { 10, 17 } },
}

-- =========================================================================
-- ROOT
-- =========================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AmbientBackground"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
-- Negative order keeps this behind MainGui, the popups and every effect
-- layer without needing to touch any of their DisplayOrder values.
screenGui.DisplayOrder = -10
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Backdrop"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = COLOR_DEEP
root.BorderSizePixel = 0
root.ZIndex = 1
root.Parent = screenGui

-- =========================================================================
-- BASE WASH
-- =========================================================================
-- A vertical gradient that slowly rotates and shifts. Cheap (one instance)
-- and does most of the heavy lifting in making the screen feel alive.

local wash = Instance.new("UIGradient")
wash.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLOR_MID),
	ColorSequenceKeypoint.new(0.5, COLOR_DEEP),
	ColorSequenceKeypoint.new(1, COLOR_MID),
})
wash.Rotation = 90
wash.Parent = root

task.spawn(function()
	-- A long, slow cycle -- fast enough to notice over a session, slow
	-- enough that it never pulls attention from the orb.
	while root.Parent do
		local a = TweenService:Create(wash, TweenInfo.new(18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Rotation = 115,
		})
		a:Play()
		a.Completed:Wait()

		local b = TweenService:Create(wash, TweenInfo.new(18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Rotation = 65,
		})
		b:Play()
		b.Completed:Wait()
	end
end)

-- =========================================================================
-- COLOURED GLOW POOLS
-- =========================================================================
-- Two large, very soft radial glows drifting slowly in opposite arcs.
-- These give the backdrop colour variation without any per-frame cost.

local function createGlow(color, startScale, anchorX, anchorY)
	local glow = Instance.new("ImageLabel")
	glow.Name = "AmbientGlow"
	glow.BackgroundTransparency = 1
	glow.Image = "rbxasset://textures/ui/Glow.png"
	glow.ImageColor3 = color
	glow.ImageTransparency = 0.82
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(anchorX, anchorY)
	glow.Size = UDim2.fromScale(startScale, startScale)
	glow.ZIndex = 2
	glow.Parent = root
	return glow
end

local glowA = createGlow(COLOR_GLOW_A, 1.1, 0.25, 0.35)
local glowB = createGlow(COLOR_GLOW_B, 1.3, 0.78, 0.68)

local function driftGlow(glow, positions, duration)
	task.spawn(function()
		local index = 1
		while glow.Parent do
			index = (index % #positions) + 1
			local target = positions[index]

			local tween = TweenService:Create(
				glow,
				TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ Position = UDim2.fromScale(target[1], target[2]) }
			)
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

driftGlow(glowA, { { 0.2, 0.3 }, { 0.35, 0.6 }, { 0.15, 0.75 }, { 0.3, 0.4 } }, 22)
driftGlow(glowB, { { 0.8, 0.7 }, { 0.65, 0.35 }, { 0.85, 0.25 }, { 0.7, 0.6 } }, 26)

-- =========================================================================
-- PARALLAX MOTES
-- =========================================================================
-- Each mote is created once and then recycled: when it drifts off the top
-- of the screen it is repositioned at the bottom and sent up again. No
-- instance is ever created or destroyed after startup.

local moteHolder = Instance.new("Frame")
moteHolder.Name = "Motes"
moteHolder.Size = UDim2.fromScale(1, 1)
moteHolder.BackgroundTransparency = 1
moteHolder.ZIndex = 3
moteHolder.Parent = root

-- Small screens get proportionally fewer motes: the same count on a phone
-- is both visually busier and relatively more expensive.
local function isSmallScreen()
	local viewport = screenGui.AbsoluteSize
	return viewport.X > 0 and viewport.X < 700
end

local function randomFloat(min, max)
	return min + math.random() * (max - min)
end

local function createMote(layer)
	local mote = Instance.new("Frame")
	mote.Name = "Mote"
	mote.AnchorPoint = Vector2.new(0.5, 0.5)
	mote.BackgroundColor3 = MOTE_COLORS[math.random(1, #MOTE_COLORS)]
	mote.BackgroundTransparency = layer.Transparency
	mote.BorderSizePixel = 0
	mote.ZIndex = 3

	local size = math.random(layer.SizeRange[1], layer.SizeRange[2])
	mote.Size = UDim2.fromOffset(size, size)
	mote.Parent = moteHolder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = mote

	return mote
end

-- One long-lived loop per mote. Each iteration is a single tween, so the
-- cost between iterations is zero -- the scheduler does the work.
local function runMote(mote, layer)
	task.spawn(function()
		while mote.Parent do
			local startX = randomFloat(0.02, 0.98)
			-- Gentle horizontal wander so they don't rise in straight lines.
			local endX = math.clamp(startX + randomFloat(-0.08, 0.08), 0, 1)
			local travelTime = randomFloat(layer.SpeedRange[1], layer.SpeedRange[2])

			mote.Position = UDim2.fromScale(startX, randomFloat(1.02, 1.25))
			mote.BackgroundTransparency = 1

			-- Fade in as it enters, so motes never pop into existence.
			TweenService:Create(mote, TweenInfo.new(travelTime * 0.2, Enum.EasingStyle.Sine), {
				BackgroundTransparency = layer.Transparency,
			}):Play()

			local rise = TweenService:Create(
				mote,
				TweenInfo.new(travelTime, Enum.EasingStyle.Linear),
				{ Position = UDim2.fromScale(endX, -0.1) }
			)
			rise:Play()

			-- Fade out over the last stretch of the climb.
			task.delay(travelTime * 0.75, function()
				if mote.Parent then
					TweenService:Create(mote, TweenInfo.new(travelTime * 0.25, Enum.EasingStyle.Sine), {
						BackgroundTransparency = 1,
					}):Play()
				end
			end)

			rise.Completed:Wait()

			-- Stagger re-entry so the field never falls into a visible rhythm.
			task.wait(randomFloat(0, 2.5))
		end
	end)
end

task.spawn(function()
	-- Give the viewport a moment to report a real size before deciding how
	-- many motes to spawn.
	task.wait(1)
	local small = isSmallScreen()

	for _, layer in ipairs(LAYERS) do
		local count = small and math.max(2, math.floor(layer.Count * 0.55)) or layer.Count

		for i = 1, count do
			local mote = createMote(layer)
			runMote(mote, layer)
			-- Spread the initial spawn out so they don't all start together.
			task.wait(randomFloat(0.05, 0.3))
		end
	end
end)

-- =========================================================================
-- VIGNETTE
-- =========================================================================
-- Darkens the extreme edges so the centre of the screen -- where the orb
-- lives -- reads as the focal point. Four edge gradients rather than an
-- image asset, so it needs no upload and scales to any aspect ratio.

local function createVignetteEdge(size, position, anchor, rotation)
	local edge = Instance.new("Frame")
	edge.Name = "VignetteEdge"
	edge.Size = size
	edge.Position = position
	edge.AnchorPoint = anchor
	edge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	edge.BorderSizePixel = 0
	edge.ZIndex = 4
	edge.Parent = root

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	return edge
end

createVignetteEdge(UDim2.fromScale(1, 0.22), UDim2.fromScale(0.5, 0), Vector2.new(0.5, 0), 90)
createVignetteEdge(UDim2.fromScale(1, 0.22), UDim2.fromScale(0.5, 1), Vector2.new(0.5, 1), 270)
createVignetteEdge(UDim2.fromScale(0.16, 1), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), 0)
createVignetteEdge(UDim2.fromScale(0.16, 1), UDim2.fromScale(1, 0.5), Vector2.new(1, 0.5), 180)

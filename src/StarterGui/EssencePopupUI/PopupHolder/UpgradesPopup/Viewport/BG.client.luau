--!strict
--[[
	HexTreeAnimatedBackground (v2 — much more animation + responsiveness)

	HOW TO USE:
	1. In Explorer, find the Frame that holds your hex tree nodes.
	2. Insert a LocalScript as a CHILD of that Frame.
	3. Paste this entire file into it. Press Play.

	WHAT'S NEW vs the first version:
	- A rotating, resize-aware wireframe hex-grid layer under the tree
	- A cursor-following glow "spotlight" with spring smoothing
	- Ambient particles now brighten/grow when the cursor passes near them
	- Two particle species: drifting dust + slowly rising embers
	- Nebula color pools now orbit gently instead of sitting static
	- Click / tap anywhere spawns an expanding ripple ring
	- Random comet streaks periodically cross the whole background
	- Random "synapse" flashes randomly connect two branch color pools,
	  like the tree's energy briefly arcing between schools
	- Central hub now has rotating swirl rings + slow hue drift
	- A slow overall "breathing" zoom on the whole background layer
	- A pulsing vignette for cinematic depth
]]

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- ============================================================
-- 1. FIND THE FRAME THIS SHOULD RENDER BEHIND
-- ============================================================

local host = script.Parent
if not (host and host:IsA("GuiObject")) then
	warn("[HexTreeAnimatedBackground] Place this script inside a Frame (or other GuiObject) — the one that holds your hex tree nodes.")
	return
end

-- ============================================================
-- 2. CONFIG
-- ============================================================

local BRANCHES = {
	{ name = "Arcane",  color = Color3.fromRGB(168, 132, 255), anchor = Vector2.new(0.27, 0.20) },
	{ name = "Alchemy", color = Color3.fromRGB(232, 116, 196), anchor = Vector2.new(0.14, 0.38) },
	{ name = "Toxin",   color = Color3.fromRGB(84, 220, 196),  anchor = Vector2.new(0.06, 0.54) },
	{ name = "Relic",   color = Color3.fromRGB(240, 204, 108), anchor = Vector2.new(0.09, 0.63) },
	{ name = "Frost",   color = Color3.fromRGB(120, 198, 255), anchor = Vector2.new(0.49, 0.14) },
	{ name = "Nature",  color = Color3.fromRGB(112, 218, 140), anchor = Vector2.new(0.62, 0.18) },
	{ name = "Ember",   color = Color3.fromRGB(244, 168, 92),  anchor = Vector2.new(0.55, 0.31) },
	{ name = "Blood",   color = Color3.fromRGB(232, 96, 96),   anchor = Vector2.new(0.73, 0.34) },
	{ name = "Wealth",  color = Color3.fromRGB(244, 212, 108), anchor = Vector2.new(0.68, 0.62) },
	{ name = "Tide",    color = Color3.fromRGB(96, 198, 224),  anchor = Vector2.new(0.50, 0.66) },
	{ name = "Core",    color = Color3.fromRGB(255, 150, 210), anchor = Vector2.new(0.87, 0.42) },
}

local HUB_ANCHOR = Vector2.new(0.50, 0.50)
local HUB_COLOR = Color3.fromRGB(140, 210, 255)

local DUST_COUNT = 70
local EMBER_COUNT = 20
local PARALLAX_STRENGTH = 16
local MOUSE_BOOST_RADIUS = 70       -- px; particles within this glow brighter
local BASE_BACKDROP_COLOR = Color3.fromRGB(6, 8, 16)

local HEX_GRID_RADIUS = 62           -- px, size of each wireframe hex cell
local HEX_GRID_THICKNESS = 1
local HEX_GRID_COLOR = Color3.fromRGB(90, 120, 180)
local HEX_GRID_BASE_TRANSPARENCY = 0.93
local HEX_GRID_ROTATION_SPEED = 0.6  -- degrees per second

local COMET_MIN_INTERVAL, COMET_MAX_INTERVAL = 3.5, 8
local SYNAPSE_MIN_INTERVAL, SYNAPSE_MAX_INTERVAL = 1.2, 3.2

local isPaused = not host.Parent.Visible

local function refreshPausedState()
	isPaused = not host.Parent.Visible
end
host.Parent:GetPropertyChangedSignal("Visible"):Connect(function()
	refreshPausedState()
end)
-- ============================================================
-- 3. SMALL HELPERS
-- ============================================================

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function pingpong(x: number): number
	return (math.sin(x * math.pi * 2) + 1) / 2
end

local function createGlow(parent: Instance, sizeScale: number, color: Color3, anchorFrac: Vector2, zindex: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Glow"
	img.BackgroundTransparency = 1
	img.Image = "rbxasset://textures/particles/smoke_main.dds"
	img.ImageColor3 = color
	img.ImageTransparency = 0.85
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Position = UDim2.fromScale(anchorFrac.X, anchorFrac.Y)
	img.Size = UDim2.fromScale(sizeScale, sizeScale)
	img.ZIndex = zindex
	img.Parent = parent
	return img
end

local function createDot(parent: Instance, size: number, color: Color3, zindex: number): Frame
	local dot = Instance.new("Frame")
	dot.Name = "Particle"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = zindex

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot

	dot.Parent = parent
	return dot
end

-- Thin rotated Frame used as a straight line segment between two pixel
-- points, relative to whatever parent it's given (parent should be
-- positioned/sized in pixel Offset space for this math to be correct).
local function createLineSegment(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, transparency: number, zindex: number): Frame
	local delta = b - a
	local length = delta.Magnitude
	local angle = math.deg(math.atan2(delta.Y, delta.X))

	local seg = Instance.new("Frame")
	seg.Name = "Segment"
	seg.AnchorPoint = Vector2.new(0.5, 0.5)
	seg.Size = UDim2.fromOffset(math.max(length, 0.1), thickness)
	seg.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	seg.Rotation = angle
	seg.BackgroundColor3 = color
	seg.BackgroundTransparency = transparency
	seg.BorderSizePixel = 0
	seg.ZIndex = zindex
	seg.Parent = parent
	return seg
end

-- ============================================================
-- 4. BUILD THE CANVAS
-- ============================================================

local canvas = Instance.new("Frame")
canvas.Name = "AnimatedBackground"
canvas.Size = UDim2.fromScale(1, 1)
canvas.Position = UDim2.fromScale(0, 0)
canvas.BackgroundColor3 = BASE_BACKDROP_COLOR
canvas.BorderSizePixel = 0
canvas.ClipsDescendants = true
canvas.ZIndex = 10
canvas.Parent = host

do
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 45
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, BASE_BACKDROP_COLOR:Lerp(Color3.new(1, 1, 1), 0.04)),
		ColorSequenceKeypoint.new(0.5, BASE_BACKDROP_COLOR),
		ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
	})
	gradient.Parent = canvas
end

-- Everything that "breathes" together lives inside this scaled group.
local breatheLayer = Instance.new("Frame")
breatheLayer.Name = "BreatheLayer"
breatheLayer.BackgroundTransparency = 1
breatheLayer.Size = UDim2.fromScale(1, 1)
breatheLayer.ZIndex = 12
breatheLayer.Parent = canvas

local breatheScale = Instance.new("UIScale")
breatheScale.Scale = 1
breatheScale.Parent = breatheLayer

-- Hex wireframe grid sits at the very back, rotates slowly.
local hexGridContainer = Instance.new("Frame")
hexGridContainer.Name = "HexGrid"
hexGridContainer.BackgroundTransparency = 1
hexGridContainer.AnchorPoint = Vector2.new(0.5, 0.5)
hexGridContainer.Position = UDim2.fromScale(0.5, 0.5)
hexGridContainer.Size = UDim2.fromScale(1.6, 1.6) -- oversized so rotation never shows corners
hexGridContainer.ZIndex = 11
hexGridContainer.Parent = breatheLayer

-- Everything that should pan with the mouse (nebula, particles, hub)
-- lives in this layer instead, nested inside the breathing layer.
local parallaxLayer = Instance.new("Frame")
parallaxLayer.Name = "ParallaxLayer"
parallaxLayer.BackgroundTransparency = 1
parallaxLayer.Size = UDim2.fromScale(1, 1)
parallaxLayer.ZIndex = 13
parallaxLayer.Parent = breatheLayer

-- Foreground effects layer (ripples, comets, synapse flashes) sits on
-- top of everything else in the background stack but still behind tree
-- nodes since its ZIndex is still deeply negative relative to them.
local effectsLayer = Instance.new("Frame")
effectsLayer.Name = "EffectsLayer"
effectsLayer.BackgroundTransparency = 1
effectsLayer.Size = UDim2.fromScale(1, 1)
effectsLayer.ZIndex = 14
effectsLayer.Parent = canvas

-- Vignette on top of everything in the background stack.
local vignette = Instance.new("ImageLabel")
vignette.Name = "Vignette"
vignette.BackgroundTransparency = 1
vignette.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"
vignette.ImageColor3 = Color3.new(0, 0, 0)
vignette.ImageTransparency = 1
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.Size = UDim2.fromScale(1, 1)
vignette.ZIndex = 15
vignette.Parent = canvas
do
	local vgrad = Instance.new("UIGradient")
	vgrad.Rotation = 90
	vgrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.75, 1),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	vgrad.Parent = vignette
end

-- ============================================================
-- 5. HEX WIREFRAME GRID (rebuilt whenever the host resizes)
-- ============================================================

type HexCell = {
	segments: { Frame },
	center: Vector2,
	phase: number,
}

local hexCells: { HexCell } = {}

local function clearHexGrid()
	for _, cell in ipairs(hexCells) do
		for _, seg in ipairs(cell.segments) do
			seg:Destroy()
		end
	end
	table.clear(hexCells)
end

local function buildHexGrid()
	clearHexGrid()

	local size = hexGridContainer.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local r = HEX_GRID_RADIUS
	local horizSpacing = r * 1.5
	local vertSpacing = r * math.sqrt(3)

	local cols = math.ceil(size.X / horizSpacing) + 2
	local rows = math.ceil(size.Y / vertSpacing) + 2

	for col = 0, cols do
		for row = 0, rows do
			local cx = col * horizSpacing
			local cy = row * vertSpacing + (col % 2 == 1 and vertSpacing / 2 or 0)

			local center = Vector2.new(cx, cy)

			local segments = {}
			for i = 0, 5 do
				local a1 = math.rad(60 * i)
				local a2 = math.rad(60 * (i + 1))
				local p1 = center + Vector2.new(math.cos(a1), math.sin(a1)) * r
				local p2 = center + Vector2.new(math.cos(a2), math.sin(a2)) * r
				local seg = createLineSegment(hexGridContainer, p1, p2, HEX_GRID_THICKNESS, HEX_GRID_COLOR, HEX_GRID_BASE_TRANSPARENCY, 11)
				table.insert(segments, seg)
			end

			table.insert(hexCells, {
				segments = segments,
				center = center,
				phase = math.random() * 100,
			})
		end
	end
end

buildHexGrid()

do
	local resizePending = false
	hexGridContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if resizePending then
			return
		end
		resizePending = true
		task.delay(0.25, function()
			resizePending = false
			if hexGridContainer.Parent then
				buildHexGrid()
			end
		end)
	end)
end

-- ============================================================
-- 6. NEBULA GLOW POOLS (gentle orbit + pulse)
-- ============================================================

type NebulaBlob = {
	image: ImageLabel,
	anchor: Vector2,
	phase: number,
	pulseSpeed: number,
	orbitSpeed: number,
	orbitRadius: number,
	baseSizeScale: number,
}

local nebulaBlobs: { NebulaBlob } = {}

for _, branch in ipairs(BRANCHES) do
	local sizeScale = math.random(16, 24) / 100
	local glow = createGlow(parallaxLayer, sizeScale, branch.color, branch.anchor, 11)

	table.insert(nebulaBlobs, {
		image = glow,
		anchor = branch.anchor,
		phase = math.random() * 100,
		pulseSpeed = 0.15 + math.random() * 0.2,
		orbitSpeed = 0.05 + math.random() * 0.08,
		orbitRadius = 0.008 + math.random() * 0.012,
		baseSizeScale = sizeScale,
	})
end

-- ============================================================
-- 7. PARTICLES — dust (drift) + embers (rise)
-- ============================================================

type Particle = {
	frame: Frame,
	fracX: number,
	fracY: number,
	noiseSeedX: number,
	noiseSeedY: number,
	twinkleSeed: number,
	twinkleSpeed: number,
	baseSize: number,
	rises: boolean,
	riseSpeed: number,
}

local particles: { Particle } = {}

local function spawnParticle(rises: boolean)
	local branch = BRANCHES[math.random(1, #BRANCHES)]
	local size = rises and math.random(3, 6) or math.random(2, 5)
	local dot = createDot(parallaxLayer, size, branch.color, 13)

	local fracX = math.random()
	local fracY = math.random()
	dot.Position = UDim2.fromScale(fracX, fracY)

	table.insert(particles, {
		frame = dot,
		fracX = fracX,
		fracY = fracY,
		noiseSeedX = math.random() * 1000,
		noiseSeedY = math.random() * 1000,
		twinkleSeed = math.random() * 1000,
		twinkleSpeed = 0.8 + math.random() * 1.2,
		baseSize = size,
		rises = rises,
		riseSpeed = rises and (0.015 + math.random() * 0.02) or 0,
	})
end

for _ = 1, DUST_COUNT do
	spawnParticle(false)
end
for _ = 1, EMBER_COUNT do
	spawnParticle(true)
end

-- ============================================================
-- 8. CENTRAL HUB — pulsing + rotating swirl rings
-- ============================================================

type HubRing = {
	image: ImageLabel,
	offset: number,
	spinSpeed: number,
}

local RING_COUNT = 4
local hubRings: { HubRing } = {}

for i = 1, RING_COUNT do
	local ring = createGlow(parallaxLayer, 0.06, HUB_COLOR, HUB_ANCHOR, 12)
	ring.ImageTransparency = 0.5
	local gradient = Instance.new("UIGradient")
	gradient.Parent = ring

	table.insert(hubRings, {
		image = ring,
		offset = (i - 1) / RING_COUNT,
		spinSpeed = (i % 2 == 0 and 1 or -1) * (20 + i * 6),
	})
end

-- ============================================================
-- 9. MOUSE TRACKING — spotlight, parallax, particle proximity boost
-- ============================================================

local mouseSpotlight = createGlow(parallaxLayer, 0.14, Color3.fromRGB(255, 255, 255), Vector2.new(0.5, 0.5), 13)
mouseSpotlight.ImageTransparency = 1 -- fades in only once the mouse has actually moved

local targetParallax = Vector2.new(0, 0)
local currentParallax = Vector2.new(0, 0)
local targetMousePixel: Vector2? = nil
local currentMousePixel = Vector2.new(0, 0)
local hasMouseInput = UserInputService.MouseEnabled

local GUIService = game:GetService("GuiService")
local function updateMouseTarget(screenPos: Vector2)
	local size = host.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local local_ = screenPos - host.AbsolutePosition + GUIService:GetGuiInset()
	targetMousePixel = local_
	targetMousePixel = Vector2.new(targetMousePixel.X* 1.5,targetMousePixel.Y) 
	local relX = local_.X / size.X - .5
	local relY = local_.Y / size.Y - 0.5
	targetParallax = Vector2.new(relX * PARALLAX_STRENGTH * 2, relY * PARALLAX_STRENGTH * 2)
end

if hasMouseInput then
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			updateMouseTarget(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
end
UserInputService.TouchMoved:Connect(function(touch)
	updateMouseTarget(Vector2.new(touch.Position.X, touch.Position.Y))
end)

-- ============================================================
-- 10. CLICK / TAP RIPPLES
-- ============================================================

local function spawnRipple(localPos: Vector2)
	local ripple = Instance.new("Frame")
	ripple.Name = "Ripple"
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.Position = UDim2.fromOffset(localPos.X, localPos.Y)
	ripple.Size = UDim2.fromOffset(0, 0)
	ripple.BackgroundTransparency = 1
	ripple.ZIndex = 17
	ripple.Parent = effectsLayer

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(200, 220, 255)
	stroke.Transparency = 0.1
	stroke.Parent = ripple

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ripple

	local grow = TweenService:Create(ripple, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(220, 220),
	})
	local fade = TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
	})

	grow:Play()
	fade:Play()
	fade.Completed:Connect(function()
		ripple:Destroy()
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	local size = host.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local local_ = Vector2.new(input.Position.X, input.Position.Y) - host.AbsolutePosition - GUIService:GetGuiInset()
	if local_.X < 0 or local_.Y < 0 or local_.X > size.X or local_.Y > size.Y then
		return -- click was outside this frame; ignore
	end

	spawnRipple(local_)
end)

-- ============================================================
-- 11. COMETS — occasional streaks crossing the whole background
-- ============================================================

local function spawnComet()
	local size = host.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end

	local goingRight = math.random() > 0.5
	local startY = math.random(0, math.floor(size.Y))
	local endY = math.random(0, math.floor(size.Y))
	local startX = goingRight and -40 or size.X + 40
	local endX = goingRight and size.X + 40 or -40

	local comet = Instance.new("Frame")
	comet.Name = "Comet"
	comet.AnchorPoint = Vector2.new(0.5, 0.5)
	comet.Size = UDim2.fromOffset(3, 3)
	comet.Position = UDim2.fromOffset(startX, startY)
	comet.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	comet.BackgroundTransparency = 1
	comet.ZIndex = 16
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = comet
	comet.Parent = effectsLayer

	local duration = 1.2 + math.random() * 0.8

	local fadeIn = TweenService:Create(comet, TweenInfo.new(duration * 0.15, Enum.EasingStyle.Linear), {
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(4, 4),
	})
	local move = TweenService:Create(comet, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Position = UDim2.fromOffset(endX, endY),
	})
	local fadeOut = TweenService:Create(comet, TweenInfo.new(duration * 0.25, Enum.EasingStyle.Linear), {
		BackgroundTransparency = 1,
	})

	fadeIn:Play()
	move:Play()

	task.delay(duration * 0.7, function()
		if comet.Parent then
			fadeOut:Play()
		end
	end)
	task.delay(duration + 0.4, function()
		comet:Destroy()
	end)
end

task.spawn(function()
	while canvas.Parent do
		task.wait(math.random(COMET_MIN_INTERVAL * 10, COMET_MAX_INTERVAL * 10) / 10)
		if canvas.Parent and not isPaused then
			spawnComet()
		end
	end
end)

-- ============================================================
-- 12. SYNAPSE FLASHES — brief energy arcs between branch pools
-- ============================================================

local function spawnSynapseFlash()
	local size = host.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 or #BRANCHES < 2 then
		return
	end

	local a = BRANCHES[math.random(1, #BRANCHES)]
	local b = BRANCHES[math.random(1, #BRANCHES)]
	if a == b then
		return
	end

	local p1 = Vector2.new(a.anchor.X * size.X, a.anchor.Y * size.Y)
	local p2 = Vector2.new(b.anchor.X * size.X, b.anchor.Y * size.Y)

	local avgColor = a.color:Lerp(b.color, 0.5)
	local seg = createLineSegment(effectsLayer, p1, p2, 1.5, avgColor, 1, 15)

	local flashIn = TweenService:Create(seg, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.35,
	})
	flashIn:Play()

	task.delay(0.2, function()
		if seg.Parent then
			local flashOut = TweenService:Create(seg, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			})
			flashOut:Play()
			flashOut.Completed:Connect(function()
				seg:Destroy()
			end)
		end
	end)
end

task.spawn(function()
	while canvas.Parent do
		task.wait(math.random(SYNAPSE_MIN_INTERVAL * 10, SYNAPSE_MAX_INTERVAL * 10) / 10)
		if canvas.Parent and not isPaused then
			spawnSynapseFlash()
		end
	end
end)

-- ============================================================
-- 13. MAIN UPDATE LOOP
-- ============================================================

local t = 0

local heartbeatConn: RBXScriptConnection
heartbeatConn = RunService.Heartbeat:Connect(function(dt)
	if not canvas.Parent then
		heartbeatConn:Disconnect()
		return
	end
	
	if isPaused then
		-- Frame is hidden (or not yet visible) — skip all particle,
		-- nebula, hex-grid, and hub math this frame. `t` intentionally
		-- doesn't advance either, so effects resume exactly where they
		-- left off instead of jumping when the frame reopens.
		return
	end
	
	t += dt
	local canvasSize = canvas.AbsoluteSize
	local canvasAbsPos = canvas.AbsolutePosition

	-- Smooth parallax + mouse pixel tracking.
	currentParallax = currentParallax:Lerp(targetParallax, math.clamp(dt * 6, 0, 1))
	parallaxLayer.Position = UDim2.fromOffset(currentParallax.X, currentParallax.Y)

	if targetMousePixel then
		currentMousePixel = currentMousePixel:Lerp(targetMousePixel, math.clamp(dt * 10, 0, 1))
		local fracX = canvasSize.X > 0 and currentMousePixel.X / canvasSize.X or 0.5
		local fracY = canvasSize.Y > 0 and currentMousePixel.Y / canvasSize.Y or 0.5
		mouseSpotlight.Position = UDim2.fromScale(fracX , fracY)
		mouseSpotlight.ImageTransparency = 0.88
	end

	-- Whole-background slow "breathing" zoom.
	local breathe = pingpong(t * 0.08)
	breatheScale.Scale = lerp(0.985, 1.015, breathe)

	-- Rotate the wireframe hex grid slowly, plus a faint per-cell twinkle
	-- and a brightness boost for cells near the cursor.
	hexGridContainer.Rotation = (t * HEX_GRID_ROTATION_SPEED) % 360

	for _, cell in ipairs(hexCells) do
		local twinkle = pingpong((t + cell.phase) * 0.1)
		local transparency = HEX_GRID_BASE_TRANSPARENCY - twinkle * 0.05

		if targetMousePixel then
			local cellAbs = canvasAbsPos + cell.center -- approximation; grid isn't rotated in this calc, close enough for a soft glow cue
			local dist = (cellAbs - (canvasAbsPos + currentMousePixel)).Magnitude
			if dist < MOUSE_BOOST_RADIUS then
				local boost = 1 - (dist / MOUSE_BOOST_RADIUS)
				transparency = lerp(transparency, 0.5, boost)
			end
		end

		for _, seg in ipairs(cell.segments) do
			seg.BackgroundTransparency = transparency
		end
	end

	-- Nebula: pulse size/opacity and orbit slowly around each anchor.
	for _, blob in ipairs(nebulaBlobs) do
		local pulse = pingpong((t + blob.phase) * blob.pulseSpeed)
		local scale = blob.baseSizeScale * (1 + (pulse - 0.5) * 0.15)
		blob.image.Size = UDim2.fromScale(scale, scale)
		blob.image.ImageTransparency = 0.80 + (pulse - 0.5) * 0.12

		local orbitAngle = (t + blob.phase) * blob.orbitSpeed * math.pi * 2
		local ox = blob.anchor.X + math.cos(orbitAngle) * blob.orbitRadius
		local oy = blob.anchor.Y + math.sin(orbitAngle) * blob.orbitRadius
		blob.image.Position = UDim2.fromScale(ox, oy)
	end

	-- Particles: drift/rise, twinkle, and brighten near the mouse.
	for _, p in ipairs(particles) do
		local driftX = math.noise(p.noiseSeedX, t * 0.15) * 10
		local driftY = math.noise(p.noiseSeedY, t * 0.15) * 10

		local fracY = p.fracY
		if p.rises then
			fracY = (p.fracY - t * p.riseSpeed) % 1
		end

		p.frame.Position = UDim2.new(p.fracX, driftX, fracY, driftY)

		local twinkle = pingpong((t + p.twinkleSeed) * p.twinkleSpeed)
		local alpha = 0.15 + twinkle * 0.5
		local sizeMult = 1

		if targetMousePixel then
			local particleAbs = canvasAbsPos + Vector2.new(p.fracX * canvasSize.X + driftX, fracY * canvasSize.Y + driftY)
			local mouseAbs = canvasAbsPos + currentMousePixel
			local dist = (particleAbs - mouseAbs).Magnitude
			if dist < MOUSE_BOOST_RADIUS then
				local boost = 1 - (dist / MOUSE_BOOST_RADIUS)
				alpha = lerp(alpha, 1, boost)
				sizeMult = lerp(1, 1.8, boost)
			end
		end

		p.frame.BackgroundTransparency = 1 - alpha
		p.frame.Size = UDim2.fromOffset(p.baseSize * sizeMult, p.baseSize * sizeMult)
	end

	-- Hub: expanding rings + independent gradient spin + slow hue drift.
	local hue = (t * 0.02) % 1
	for _, ring in ipairs(hubRings) do
		local period = 2.4
		local rt = ((t / period) + ring.offset) % 1
		local scale = 0.05 + rt * 0.14
		ring.image.Size = UDim2.fromScale(scale, scale)
		ring.image.ImageTransparency = 0.3 + rt * 0.65
		ring.image.ImageColor3 = Color3.fromHSV((hue + ring.offset * 0.05) % 1, 0.35, 1)

		local gradient = ring.image:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Rotation = (t * ring.spinSpeed) % 360
		end
	end

	-- Vignette breathes very slightly darker/lighter over a long period.
	local vignetteGrad = vignette:FindFirstChildOfClass("UIGradient")
	if vignetteGrad then
		local vpulse = pingpong(t * 0.05)
		vignetteGrad.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.75, 1),
			NumberSequenceKeypoint.new(1, lerp(0.45, 0.65, vpulse)),
		})
	end
end)

-- ============================================================
-- 14. CLEANUP
-- ============================================================

script.AncestryChanged:Connect(function()
	if not script:IsDescendantOf(game) then
		heartbeatConn:Disconnect()
		canvas:Destroy()
	end
end)

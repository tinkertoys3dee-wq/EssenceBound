--[[
	OrbAura (LocalScript -> StarterPlayerScripts)
	=============================================
	Gives the great orb a sense of presence: concentric rings turning at
	different speeds and directions, a soft breathing glow, and motes
	orbiting it. It also dims as the orb's energy depletes, so the bar
	under the orb is not the only place that mechanic is expressed.

	WHY A SEPARATE SCREENGUI
	-------------------------
	The aura has to render BEHIND the orb. Rather than inserting frames
	into MainGui and depending on the place file's ZIndex values (which
	aren't in this repo and could change in Studio at any time), this lives
	in its own ScreenGui at DisplayOrder -5: above AmbientBackground (-10),
	below MainGui (0). That ordering is guaranteed regardless of how the
	orb's own hierarchy is arranged.

	The cost of that is having to track the orb's on-screen rectangle
	manually, which is what mirrorToOrb below does. Since the orb doesn't
	move during play, that's driven by change signals rather than a
	per-frame loop.

	Nothing here reads or writes gameplay state -- it only observes the
	OrbCurrentHP / OrbMaxHP attributes the server already publishes for the
	energy bar. Decoration only.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainGui = playerGui:WaitForChild("MainGui")
local center = mainGui:WaitForChild("Center")
local largeOrbFolder = center:WaitForChild("LargeOrbFolder")
local largeOrb = largeOrbFolder:WaitForChild("LargeOrb")

-- =========================================================================
-- PALETTE
-- =========================================================================

local RING_INNER = Color3.fromRGB(120, 240, 170)
local RING_OUTER = Color3.fromRGB(160, 120, 255)
local GLOW_COLOR = Color3.fromRGB(110, 230, 160)
local MOTE_COLOR = Color3.fromRGB(190, 255, 215)

-- How much bigger than the orb each element sits.
local GLOW_SCALE = 2.6
local RING_SCALES = { 1.35, 1.7, 2.05 }
local MOTE_ORBIT_SCALE = 1.5
local MOTE_COUNT = 6

-- =========================================================================
-- ROOT
-- =========================================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "OrbAura"
screenGui.ResetOnSpawn = false
-- Must MATCH MainGui's inset handling, because mirrorToOrb positions the
-- aura straight from largeOrb.AbsolutePosition. If the two ScreenGuis
-- disagree about where the screen starts, the aura lands offset from the
-- orb by the height of the topbar. Set to false to line up with MainGui.
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = -5 -- between the backdrop and MainGui
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Anchor frame that tracks the orb's on-screen rectangle. Everything else
-- is sized in scale relative to this, so the whole aura follows the orb
-- across resolutions without any per-element maths.
local anchor = Instance.new("Frame")
anchor.Name = "Anchor"
anchor.AnchorPoint = Vector2.new(0.5, 0.5)
anchor.BackgroundTransparency = 1
anchor.Size = UDim2.fromOffset(100, 100)
anchor.Visible = false -- shown once the orb reports a real size
anchor.Parent = screenGui

local function mirrorToOrb()
	local size = largeOrb.AbsoluteSize
	local pos = largeOrb.AbsolutePosition

	if size.X <= 0 or size.Y <= 0 then
		anchor.Visible = false
		return
	end

	-- This ScreenGui shares MainGui's inset handling (IgnoreGuiInset =
	-- false), so the orb's AbsolutePosition and this frame's offset are in
	-- the same coordinate space and need no correction.
	anchor.Size = UDim2.fromOffset(size.X, size.Y)
	anchor.Position = UDim2.fromOffset(pos.X + size.X / 2, pos.Y + size.Y / 2)
	anchor.Visible = true
end

mirrorToOrb()
largeOrb:GetPropertyChangedSignal("AbsolutePosition"):Connect(mirrorToOrb)
largeOrb:GetPropertyChangedSignal("AbsoluteSize"):Connect(mirrorToOrb)

-- The orb's own UIScale animates on hover/click, which changes its
-- AbsoluteSize -- following that exactly would make the aura pump on every
-- click. Re-checking on a slow timer instead keeps the aura steady while
-- still adapting to a genuine layout or resolution change.
task.spawn(function()
	while anchor.Parent do
		task.wait(2)
		mirrorToOrb()
	end
end)

-- =========================================================================
-- BREATHING GLOW
-- =========================================================================

local glow = Instance.new("ImageLabel")
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.fromScale(0.5, 0.5)
glow.Size = UDim2.fromScale(GLOW_SCALE, GLOW_SCALE)
glow.BackgroundTransparency = 1
glow.Image = "rbxasset://textures/ui/Glow.png"
glow.ImageColor3 = GLOW_COLOR
glow.ImageTransparency = 0.62
glow.ZIndex = 1
glow.Parent = anchor

task.spawn(function()
	while glow.Parent do
		local out = TweenService:Create(glow, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Size = UDim2.fromScale(GLOW_SCALE * 1.12, GLOW_SCALE * 1.12),
		})
		out:Play()
		out.Completed:Wait()

		local back = TweenService:Create(glow, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Size = UDim2.fromScale(GLOW_SCALE, GLOW_SCALE),
		})
		back:Play()
		back.Completed:Wait()
	end
end)

-- =========================================================================
-- ROTATING RINGS
-- =========================================================================
-- Thin rings turning at different speeds and alternating directions. The
-- counter-rotation is what makes it read as "machinery with power in it"
-- rather than a single spinning decal.

local rings = {}

for index, scaleMult in ipairs(RING_SCALES) do
	local ring = Instance.new("Frame")
	ring.Name = "Ring" .. index
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(scaleMult, scaleMult)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 2
	ring.Parent = anchor

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = index == 2 and 2 or 1.5
	stroke.Transparency = 0.55 + (index * 0.08)
	stroke.Parent = ring

	-- A gradient on the stroke makes each ring fade in and out around its
	-- circumference as it turns, instead of being a flat circle.
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RING_INNER),
		ColorSequenceKeypoint.new(0.5, RING_OUTER),
		ColorSequenceKeypoint.new(1, RING_INNER),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0),
		NumberSequenceKeypoint.new(0.75, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = stroke

	table.insert(rings, {
		Gradient = gradient,
		Stroke = stroke,
		-- Alternating sign gives the counter-rotation; outer rings turn
		-- slower, which reads as depth.
		Speed = (index % 2 == 0 and -1 or 1) * (26 - index * 5),
	})
end

RunService.Heartbeat:Connect(function(dt)
	for _, ring in ipairs(rings) do
		local gradient = ring.Gradient
		if gradient.Parent then
			gradient.Rotation = (gradient.Rotation + ring.Speed * dt) % 360
		end
	end
end)

-- =========================================================================
-- ORBITING MOTES
-- =========================================================================
-- Small points circling the orb on slightly different radii and phases.
-- Positions are computed on Heartbeat because a circular path can't be
-- expressed as a single tween.

local motes = {}

for i = 1, MOTE_COUNT do
	local mote = Instance.new("Frame")
	mote.Name = "OrbitMote" .. i
	mote.AnchorPoint = Vector2.new(0.5, 0.5)
	mote.Size = UDim2.fromOffset(math.random(4, 7), math.random(4, 7))
	mote.BackgroundColor3 = MOTE_COLOR
	mote.BackgroundTransparency = 0.25
	mote.BorderSizePixel = 0
	mote.ZIndex = 3
	mote.Parent = anchor

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = mote

	table.insert(motes, {
		Instance = mote,
		Phase = math.random() * math.pi * 2,
		Speed = 0.25 + math.random() * 0.3,
		Radius = MOTE_ORBIT_SCALE * (0.88 + math.random() * 0.3),
		-- Squashing the vertical radius suggests the motes are orbiting on
		-- a tilted plane rather than flat on the screen.
		Tilt = 0.45 + math.random() * 0.25,
	})
end

local elapsed = 0

RunService.Heartbeat:Connect(function(dt)
	elapsed += dt

	for _, mote in ipairs(motes) do
		local instance = mote.Instance
		if instance.Parent then
			local angle = mote.Phase + elapsed * mote.Speed
			local x = 0.5 + math.cos(angle) * (mote.Radius * 0.5)
			local y = 0.5 + math.sin(angle) * (mote.Radius * 0.5 * mote.Tilt)

			instance.Position = UDim2.fromScale(x, y)

			-- Fade the ones on the far side of the orbit so they read as
			-- passing behind the orb.
			local depth = (math.sin(angle) + 1) / 2
			instance.BackgroundTransparency = 0.2 + (1 - depth) * 0.55
		end
	end
end)

-- =========================================================================
-- ENERGY RESPONSE
-- =========================================================================
-- The aura dims and cools as the orb's energy drains, so the state is
-- readable from the orb itself and not only from the bar beneath it. This
-- reads the same attributes the energy bar already uses; it never writes.

local function updateEnergyResponse()
	local currentHP = tonumber(player:GetAttribute("OrbCurrentHP"))
	local maxHP = tonumber(player:GetAttribute("OrbMaxHP"))

	if not currentHP or not maxHP or maxHP <= 0 then
		return
	end

	local ratio = math.clamp(currentHP / maxHP, 0, 1)

	-- Never fully dark: at zero energy the aura should look drained, not
	-- switched off, or the orb reads as broken rather than recharging.
	TweenService:Create(glow, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 0.62 + (1 - ratio) * 0.28,
		ImageColor3 = GLOW_COLOR:Lerp(Color3.fromRGB(90, 70, 120), 1 - ratio),
	}):Play()

	for index, ring in ipairs(rings) do
		if ring.Stroke.Parent then
			TweenService:Create(ring.Stroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = (0.55 + (index * 0.08)) + (1 - ratio) * 0.3,
			}):Play()
		end
	end
end

player:GetAttributeChangedSignal("OrbCurrentHP"):Connect(updateEnergyResponse)
player:GetAttributeChangedSignal("OrbMaxHP"):Connect(updateEnergyResponse)
updateEnergyResponse()

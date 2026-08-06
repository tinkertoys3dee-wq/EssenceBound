--!strict
--============================================================================
-- RebirthEffect.lua
--============================================================================
-- A fully self-contained "Rebirth" UI animation module for Roblox Studio.
--
-- This module does NOT hook into any remotes, leaderstats, or datastores.
-- It only knows how to play a big, juicy, layered screen animation inside
-- a ScreenGui you give it. Wire it up yourself from a LocalScript, e.g.:
--
--     local RebirthEffect = require(path.to.RebirthEffect)
--     local handle = RebirthEffect.Play(playerGui:WaitForChild("RebirthGui"), {
--         RebirthCount = 7,
--         Theme = "Gold",
--     })
--     handle.Completed:Connect(function()
--         print("Rebirth animation finished!")
--     end)
--
-- Everything below is pure Lua / Roblox API. No external assets required --
-- every visual (rings, beams, sparkles, glows) is built from Frames,
-- UICorner, UIStroke, and UIGradient so it works in any place with zero
-- imported images or sounds.
--============================================================================

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local RebirthEffect = {}
RebirthEffect.__index = RebirthEffect

--============================================================================
-- SECTION 1: SMALL UTILITIES
--============================================================================

-- Deep-copies a plain Lua table (no metatables, no cyclic refs expected).
local function deepCopy(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Recursively merges `override` on top of `base`, returning a NEW table.
-- Values in `override` win. Nested tables are merged, not replaced wholesale,
-- unless the override value isn't a table.
local function deepMerge(base, override)
	local result = deepCopy(base)
	if override == nil then
		return result
	end
	for key, value in pairs(override) do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = deepMerge(result[key], value)
		else
			result[key] = value
		end
	end
	return result
end

-- Clamp a number between lo and hi.
local function clamp(n, lo, hi)
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

-- Linear interpolation.
local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Random float between min and max.
local function randomFloat(min, max)
	return min + math.random() * (max - min)
end

-- Random point on unit circle -> returns unit Vector2-ish (x, y).
local function randomUnitDirection()
	local angle = math.random() * math.pi * 2
	return math.cos(angle), math.sin(angle)
end

--============================================================================
-- SECTION 2: EASING FUNCTIONS
--============================================================================
-- Roblox's TweenService already ships with easing styles, but a handful of
-- manual, per-frame-driven effects in this module (particle bursts, camera
-- shake decay, sparkle twinkle) need raw easing functions we can sample by
-- hand inside a RunService loop. These all take t in [0, 1] and return an
-- eased value, generally also in/around [0, 1].

local Easing = {}

function Easing.Linear(t)
	return t
end

function Easing.InQuad(t)
	return t * t
end

function Easing.OutQuad(t)
	return 1 - (1 - t) * (1 - t)
end

function Easing.InOutQuad(t)
	if t < 0.5 then
		return 2 * t * t
	end
	return 1 - ((-2 * t + 2) ^ 2) / 2
end

function Easing.InCubic(t)
	return t * t * t
end

function Easing.OutCubic(t)
	local u = 1 - t
	return 1 - u * u * u
end

function Easing.InOutCubic(t)
	if t < 0.5 then
		return 4 * t * t * t
	end
	local u = -2 * t + 2
	return 1 - (u * u * u) / 2
end

function Easing.OutExpo(t)
	if t >= 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * t)
end

function Easing.InExpo(t)
	if t <= 0 then
		return 0
	end
	return 2 ^ (10 * (t - 1))
end

function Easing.OutBack(t, overshoot)
	overshoot = overshoot or 1.70158
	local u = t - 1
	return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
end

function Easing.InBack(t, overshoot)
	overshoot = overshoot or 1.70158
	return (overshoot + 1) * t * t * t - overshoot * t * t
end

function Easing.OutElastic(t)
	if t == 0 or t == 1 then
		return t
	end
	local c4 = (2 * math.pi) / 3
	return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * c4) + 1
end

function Easing.OutBounce(t)
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	else
		t -= 2.625 / d1
		return n1 * t * t + 0.984375
	end
end

--============================================================================
-- SECTION 3: A MINIMAL SIGNAL IMPLEMENTATION
--============================================================================
-- We avoid depending on a BindableEvent so the module never has to parent
-- an Instance anywhere just to fire a callback. This is a tiny pub/sub.

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local entry = { fn = fn, connected = true }
	table.insert(self._handlers, entry)
	local connection = {}
	function connection.Disconnect(_self)
		entry.connected = false
	end
	connection.Destroy = connection.Disconnect
	return connection
end

function Signal:Fire(...)
	-- Copy the list first in case a handler disconnects mid-fire.
	local handlers = table.clone(self._handlers)
	for _, entry in ipairs(handlers) do
		if entry.connected then
			local ok, err = pcall(entry.fn, ...)
			if not ok then
				warn("[RebirthEffect] Signal handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:DisconnectAll()
	table.clear(self._handlers)
end

--============================================================================
-- SECTION 4: DEFAULT CONFIGURATION
--============================================================================
-- Everything here can be overridden per-call via the `options` table passed
-- to RebirthEffect.Play / RebirthEffect.new. Colors are grouped into named
-- "themes" so you can flip the whole palette with one string.

local THEMES = {
	Gold = {
		Primary = Color3.fromRGB(255, 214, 92),
		Secondary = Color3.fromRGB(255, 250, 214),
		Accent = Color3.fromRGB(255, 170, 40),
		Flash = Color3.fromRGB(255, 255, 255),
	},
	Amethyst = {
		Primary = Color3.fromRGB(178, 102, 255),
		Secondary = Color3.fromRGB(230, 200, 255),
		Accent = Color3.fromRGB(120, 40, 200),
		Flash = Color3.fromRGB(240, 220, 255),
	},
	Inferno = {
		Primary = Color3.fromRGB(255, 90, 40),
		Secondary = Color3.fromRGB(255, 200, 80),
		Accent = Color3.fromRGB(180, 20, 20),
		Flash = Color3.fromRGB(255, 230, 200),
	},
	Frost = {
		Primary = Color3.fromRGB(120, 210, 255),
		Secondary = Color3.fromRGB(220, 245, 255),
		Accent = Color3.fromRGB(40, 120, 200),
		Flash = Color3.fromRGB(230, 250, 255),
	},
	Emerald = {
		Primary = Color3.fromRGB(60, 220, 130),
		Secondary = Color3.fromRGB(200, 255, 220),
		Accent = Color3.fromRGB(10, 140, 70),
		Flash = Color3.fromRGB(220, 255, 235),
	},
}

local DEFAULT_CONFIG = {
	-- Which named palette (see THEMES above) to draw from. You can also pass
	-- a fully custom `Colors` table instead (see below) to skip themes.
	Theme = "Gold",

	-- Optional explicit color override. If any of these are set they win
	-- over the Theme lookup for that specific slot.
	Colors = {
		Primary = nil,
		Secondary = nil,
		Accent = nil,
		Flash = nil,
	},

	-- Purely cosmetic label data, both optional.
	RebirthCount = nil, -- if set, shows "Rebirth #N"
	TitleText = "REBIRTH!",

	-- Master duration knobs, in seconds.
	Timing = {
		FlashIn = 0.08,
		FlashHold = 0.05,
		FlashOut = 0.35,
		RingStagger = 0.12,
		RingLifetime = 1.1,
		BurstLifetime = 1.4,
		BeamLifetime = 1.0,
		TitlePopDuration = 0.55,
		TitleHoldDuration = 1.1,
		TitleFadeOutDuration = 0.5,
		SubtitleDelay = 0.25,
		SparkleDuration = 1.8,
		TotalSafetyTimeout = 6, -- hard cap so Play() can never hang forever
	},

	-- Particle / element counts. Turn these down on low-end platforms.
	Counts = {
		ShockwaveRings = 3,
		BurstParticles = 42,
		EnergyBeams = 10,
		Sparkles = 26,
	},

	-- Camera shake is optional because some games manage CurrentCamera
	-- themselves and don't want anything else nudging its CFrame.
	CameraShake = {
		Enabled = false,
		Magnitude = 0.25,
		Duration = 0.5,
		Roughness = 12,
	},

	-- Layering. If your ScreenGui already has other UI in it, bump this up
	-- so the effect draws above everything.
	DisplayOrder = 50,

	-- If true, the module will also nudge a soft screen-edge "vignette"
	-- glow in and back out for extra oomph.
	VignettePulse = true,

	-- If true, a brief RGB-split "glitch" flicker plays right as the flash
	-- fades, for a snappier, more impactful feel.
	ChromaticFlicker = true,
}

--============================================================================
-- SECTION 5: GENERIC INSTANCE POOL
--============================================================================
-- Rather than constantly calling Instance.new / Destroy for every single
-- particle (which is fine in Roblox but still wasteful at these volumes),
-- we keep a small recycling pool per shape. Pools are per-effect-handle so
-- two rebirth animations playing at once don't fight over the same pool.

local InstancePool = {}
InstancePool.__index = InstancePool

function InstancePool.new(factory)
	return setmetatable({
		_factory = factory,
		_free = {},
	}, InstancePool)
end

function InstancePool:Get()
	local inst = table.remove(self._free)
	if inst == nil then
		inst = self._factory()
	end
	return inst
end

function InstancePool:Release(inst)
	inst.Visible = false
	inst.Parent = nil
	table.insert(self._free, inst)
end

function InstancePool:DestroyAll()
	for _, inst in ipairs(self._free) do
		inst:Destroy()
	end
	table.clear(self._free)
end

--============================================================================
-- SECTION 6: SHAPE FACTORIES
--============================================================================
-- Small helpers that build the raw Instances used throughout the effect.
-- Keeping them centralized means every particle/ring/beam looks consistent
-- and is easy to re-skin later.

-- A circular Frame (Frame + UICorner at 1,0 corner radius = perfect circle
-- as long as the Frame itself is square).
local function newCircle(size, color, transparency)
	local frame = Instance.new("Frame")
	frame.Name = "Circle"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	return frame
end

-- A circular *outline only* frame, built from a filled circle with a hole
-- punched visually via a UIStroke and a transparent background. Good for
-- shockwave rings.
local function newRing(size, color, thickness, transparency)
	local frame = Instance.new("Frame")
	frame.Name = "Ring"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "RingStroke"
	stroke.Color = color
	stroke.Thickness = thickness or 4
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	return frame
end

-- A thin rectangular "beam" frame, anchored at its left-center so rotating
-- it makes it sweep around a fixed origin point like a sunburst spoke.
local function newBeam(length, thickness, color, transparency)
	local frame = Instance.new("Frame")
	frame.Name = "Beam"
	frame.AnchorPoint = Vector2.new(0, 0.5)
	frame.Size = UDim2.fromOffset(length, thickness)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.85, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = frame

	return frame
end

-- A small diamond ("sparkle") shape made by rotating a square frame 45deg.
local function newSparkle(size, color, transparency)
	local frame = Instance.new("Frame")
	frame.Name = "Sparkle"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.Rotation = 45
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = frame

	return frame
end

-- Soft radial "glow" built from several stacked, increasingly transparent
-- circles. Roblox UIGradient can't do true radial gradients on its own, so
-- stacking discs is the classic workaround for a soft halo look.
local function newGlow(maxSize, color, layers)
	layers = layers or 5
	local holder = Instance.new("Frame")
	holder.Name = "Glow"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(maxSize, maxSize)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0

	for i = 1, layers do
		local t = i / layers
		local disc = newCircle(maxSize * t, color, 1 - (1 - t) * 0.9)
		disc.ZIndex = i
		disc.Parent = holder
	end

	return holder
end

--============================================================================
-- SECTION 7: THE MAIN CLASS
--============================================================================

-- Resolve the effective color table for a config (Theme lookup + any
-- explicit Colors overrides layered on top).
local function resolveColors(config)
	local theme = THEMES[config.Theme] or THEMES.Gold
	local colors = {
		Primary = config.Colors.Primary or theme.Primary,
		Secondary = config.Colors.Secondary or theme.Secondary,
		Accent = config.Colors.Accent or theme.Accent,
		Flash = config.Colors.Flash or theme.Flash,
	}
	return colors
end

-- Internal constructor. Not exposed directly; use RebirthEffect.Play.
function RebirthEffect.new(options)
	local self = setmetatable({}, RebirthEffect)

	self.Config = deepMerge(DEFAULT_CONFIG, options)
	self.Colors = resolveColors(self.Config)

	self.Completed = Signal.new()
	self.Stopped = false
	self.Destroyed = false

	self._connections = {}
	self._root = nil -- the Frame we build everything inside of
	self._pools = {}
	self._activeTweens = {}
	self._activeThreads = {}

	return self
end

-- Track a RBXScriptConnection so we can clean it up later.
function RebirthEffect:_track(connection)
	table.insert(self._connections, connection)
	return connection
end

-- Get (creating if needed) a pool for a given shape-key.
function RebirthEffect:_getPool(key, factory)
	if not self._pools[key] then
		self._pools[key] = InstancePool.new(factory)
	end
	return self._pools[key]
end

--============================================================================
-- SECTION 8: ROOT CONTAINER
--============================================================================
-- Builds the full-screen container Frame that everything else parents to.
-- Keeping one root means cleanup is a single Destroy() call.

function RebirthEffect:_buildRoot(screenGui)
	assert(screenGui and screenGui:IsA("ScreenGui"), "RebirthEffect requires a ScreenGui to play into")

	screenGui.DisplayOrder = math.max(screenGui.DisplayOrder, self.Config.DisplayOrder)

	local root = Instance.new("Frame")
	root.Name = "RebirthEffectRoot"
	root.Size = UDim2.fromScale(1, 1)
	root.Position = UDim2.fromScale(0, 0)
	root.BackgroundTransparency = 1
	root.ClipsDescendants = false
	root.ZIndex = 1
	root.Parent = screenGui

	self._root = root
	return root
end

--============================================================================
-- SECTION 9: SCREEN FLASH
--============================================================================

function RebirthEffect:_playScreenFlash()
	local config = self.Config
	local colors = self.Colors

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = colors.Flash
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 100
	flash.Parent = self._root

	local tIn = TweenService:Create(
		flash,
		TweenInfo.new(config.Timing.FlashIn, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.05 }
	)
	tIn:Play()
	tIn.Completed:Wait()

	task.wait(config.Timing.FlashHold)

	local tOut = TweenService:Create(
		flash,
		TweenInfo.new(config.Timing.FlashOut, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	tOut:Play()
	tOut.Completed:Wait()

	flash:Destroy()
end

--============================================================================
-- SECTION 10: CHROMATIC FLICKER (stylized RGB-split glitch)
--============================================================================
-- Not a real post-process chromatic aberration (Roblox UI can't sample the
-- framebuffer like that) -- instead we fake the *feel* of one with three
-- tinted, slightly offset full-screen frames that snap toward center.

function RebirthEffect:_playChromaticFlicker()
	if not self.Config.ChromaticFlicker then
		return
	end

	local holder = Instance.new("Frame")
	holder.Name = "ChromaticFlicker"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 90
	holder.Parent = self._root

	local channels = {
		{ color = Color3.fromRGB(255, 60, 60), offset = Vector2.new(-10, 0) },
		{ color = Color3.fromRGB(60, 255, 90), offset = Vector2.new(0, 0) },
		{ color = Color3.fromRGB(60, 120, 255), offset = Vector2.new(10, 0) },
	}

	local frames = {}
	for _, channel in ipairs(channels) do
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, 20, 1, 20)
		f.Position = UDim2.fromOffset(channel.offset.X, channel.offset.Y)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = channel.color
		f.BackgroundTransparency = 0.9
		f.BorderSizePixel = 0
		f.Parent = holder
		table.insert(frames, f)
	end

	local duration = 0.18
	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = clamp(elapsed / duration, 0, 1)
		local eased = Easing.OutCubic(t)
		for _, f in ipairs(frames) do
			local baseOffset = f.Position
			local newX = lerp(baseOffset.X.Offset, 0, eased)
			f.Position = UDim2.new(0.5, newX, 0.5, 0)
			f.BackgroundTransparency = lerp(0.9, 1, eased)
		end
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	self:_track(connection)

	task.wait(duration + 0.05)
	holder:Destroy()
end

--============================================================================
-- SECTION 11: SHOCKWAVE RINGS
--============================================================================

function RebirthEffect:_playShockwaveRing(delayTime)
	local config = self.Config
	local colors = self.Colors

	task.wait(delayTime)
	if self.Stopped then
		return
	end

	local ring = newRing(10, colors.Primary, 6, 0.1)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.ZIndex = 20
	ring.Parent = self._root

	local targetSize = 1400
	local lifetime = config.Timing.RingLifetime

	local sizeTween = TweenService:Create(
		ring,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(targetSize, targetSize) }
	)

	local stroke = ring:FindFirstChildOfClass("UIStroke")
	local strokeTween = TweenService:Create(
		stroke,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Transparency = 1, Thickness = 0.5 }
	)

	sizeTween:Play()
	strokeTween:Play()
	sizeTween.Completed:Wait()

	ring:Destroy()
end

function RebirthEffect:_playAllShockwaveRings()
	local config = self.Config
	local threads = {}
	for i = 1, config.Counts.ShockwaveRings do
		local delayTime = (i - 1) * config.Timing.RingStagger
		local thread = task.spawn(function()
			self:_playShockwaveRing(delayTime)
		end)
		table.insert(threads, thread)
	end
	table.insert(self._activeThreads, threads)
end

--============================================================================
-- SECTION 12: RADIAL BURST PARTICLES
--============================================================================
-- Small circles fired outward from the center with random direction/speed,
-- animated manually via RenderStepped so we get natural deceleration and
-- fade-out instead of a straight linear Tween.

function RebirthEffect:_playBurstParticles()
	local config = self.Config
	local colors = self.Colors
	local pool = self:_getPool("burst", function()
		return newCircle(10, colors.Secondary, 0)
	end)

	local particles = {}
	local count = config.Counts.BurstParticles

	for i = 1, count do
		local dx, dy = randomUnitDirection()
		local speed = randomFloat(250, 650)
		local size = randomFloat(6, 16)
		local lifetime = randomFloat(config.Timing.BurstLifetime * 0.6, config.Timing.BurstLifetime)

		local particle = pool:Get()
		particle.Size = UDim2.fromOffset(size, size)
		particle.Position = UDim2.fromScale(0.5, 0.5)
		particle.BackgroundTransparency = 0
		particle.BackgroundColor3 = (i % 3 == 0) and colors.Accent or colors.Secondary
		particle.ZIndex = 15
		particle.Visible = true
		particle.Parent = self._root

		particles[i] = {
			inst = particle,
			vx = dx * speed,
			vy = dy * speed,
			age = 0,
			lifetime = lifetime,
		}
	end

	local elapsed = 0
	local maxLifetime = config.Timing.BurstLifetime
	local damping = 2.4 -- how quickly particles decelerate, higher = faster stop

	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local anyAlive = false

		for _, data in ipairs(particles) do
			data.age += dt
			if data.age < data.lifetime then
				anyAlive = true
				local t = data.age / data.lifetime

				-- Velocity decays exponentially so particles "settle" instead
				-- of flying forever in a straight line.
				local decay = math.exp(-damping * data.age)
				local posOffsetX = (data.vx / damping) * (1 - decay)
				local posOffsetY = (data.vy / damping) * (1 - decay)

				-- Slight gravity pull downward over the particle's life for
				-- a bit of "falling sparks" flavor.
				posOffsetY += 60 * t * t

				data.inst.Position = UDim2.new(0.5, posOffsetX, 0.5, posOffsetY)
				data.inst.BackgroundTransparency = Easing.InQuad(t)
			elseif data.inst.Visible then
				pool:Release(data.inst)
			end
		end

		if not anyAlive or elapsed > maxLifetime + 0.2 then
			connection:Disconnect()
		end
	end)
	self:_track(connection)

	task.wait(maxLifetime + 0.05)

	for _, data in ipairs(particles) do
		if data.inst.Visible then
			pool:Release(data.inst)
		end
	end
end

--============================================================================
-- SECTION 13: ENERGY BEAMS (sunburst spokes)
--============================================================================

function RebirthEffect:_playEnergyBeams()
	local config = self.Config
	local colors = self.Colors
	local count = config.Counts.EnergyBeams
	local lifetime = config.Timing.BeamLifetime

	local beams = {}
	for i = 1, count do
		local angle = (360 / count) * (i - 1) + randomFloat(-6, 6)
		local length = randomFloat(220, 420)
		local thickness = randomFloat(3, 7)

		local beam = newBeam(0, thickness, colors.Primary, 0.2)
		beam.Position = UDim2.fromScale(0.5, 0.5)
		beam.Rotation = angle
		beam.ZIndex = 10
		beam.Parent = self._root

		beams[i] = { inst = beam, targetLength = length, angle = angle }
	end

	local growTweens = {}
	for _, data in ipairs(beams) do
		local tween = TweenService:Create(
			data.inst,
			TweenInfo.new(lifetime * 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(data.targetLength, data.inst.Size.Y.Offset) }
		)
		tween:Play()
		table.insert(growTweens, tween)
	end

	-- Slow continuous rotation while beams are visible, purely cosmetic.
	local rotateElapsed = 0
	local rotateConnection
	rotateConnection = RunService.RenderStepped:Connect(function(dt)
		rotateElapsed += dt
		for _, data in ipairs(beams) do
			data.inst.Rotation = data.angle + rotateElapsed * 25
		end
		if rotateElapsed > lifetime then
			rotateConnection:Disconnect()
		end
	end)
	self:_track(rotateConnection)

	task.wait(lifetime * 0.5)

	local fadeTweens = {}
	for _, data in ipairs(beams) do
		local tween = TweenService:Create(
			data.inst,
			TweenInfo.new(lifetime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1, Size = UDim2.fromOffset(data.targetLength * 0.6, 1) }
		)
		tween:Play()
		table.insert(fadeTweens, tween)
	end

	task.wait(lifetime * 0.5 + 0.05)

	for _, data in ipairs(beams) do
		data.inst:Destroy()
	end
end

--============================================================================
-- SECTION 14: CENTRAL GLOW PULSE
--============================================================================

function RebirthEffect:_playGlowPulse()
	local colors = self.Colors

	local glow = newGlow(500, colors.Primary, 6)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.ZIndex = 5
	glow.Parent = self._root

	-- Pop in, then slowly dissolve.
	glow.Size = UDim2.fromOffset(0, 0)
	local growTween = TweenService:Create(
		glow,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(500, 500) }
	)
	growTween:Play()

	task.wait(0.9)

	local fadeTween = TweenService:Create(
		glow,
		TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.fromOffset(700, 700) }
	)
	fadeTween:Play()

	-- Fade each stacked disc's transparency down manually since UIGradient
	-- can't easily be tweened for this stacked-disc trick.
	for _, disc in ipairs(glow:GetChildren()) do
		if disc:IsA("Frame") then
			TweenService:Create(
				disc,
				TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }
			):Play()
		end
	end

	fadeTween.Completed:Wait()
	glow:Destroy()
end

--============================================================================
-- SECTION 15: TITLE TEXT ("REBIRTH!")
--============================================================================

function RebirthEffect:_buildTitleLabel()
	local config = self.Config
	local colors = self.Colors

	local label = Instance.new("TextLabel")
	label.Name = "TitleLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.38)
	label.Size = UDim2.fromOffset(600, 120)
	label.BackgroundTransparency = 1
	label.Text = config.TitleText
	label.TextColor3 = colors.Primary
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.ZIndex = 50
	label.Parent = self._root

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = colors.Accent
	stroke.Parent = label

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colors.Primary),
		ColorSequenceKeypoint.new(0.5, colors.Secondary),
		ColorSequenceKeypoint.new(1, colors.Primary),
	})
	gradient.Parent = label

	return label, gradient
end

function RebirthEffect:_playTitleAnimation()
	local config = self.Config
	local label, gradient = self:_buildTitleLabel()

	-- Start invisible & tiny, then "pop" in using a manual elastic-ish scale
	-- driven by our custom Easing.OutBack, since we want the stroke and
	-- gradient to update in lockstep with the scale (Tween alone can't
	-- easily drive a "TextSize"-less UIScale AND custom easing together
	-- cleanly across all these properties without extra Instances).
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 0
	uiScale.Parent = label

	local popDuration = config.Timing.TitlePopDuration
	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = clamp(elapsed / popDuration, 0, 1)
		uiScale.Scale = Easing.OutBack(t, 1.9)
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	self:_track(connection)

	task.wait(popDuration + 0.02)
	uiScale.Scale = 1

	-- Animate the gradient's Offset back and forth for a subtle "shimmer"
	-- across the text while it holds on screen.
	local holdDuration = config.Timing.TitleHoldDuration
	local shimmerElapsed = 0
	local shimmerConnection
	shimmerConnection = RunService.RenderStepped:Connect(function(dt)
		shimmerElapsed += dt
		local t = shimmerElapsed / holdDuration
		gradient.Offset = Vector2.new(math.sin(t * math.pi * 2) * 0.5, 0)
		if shimmerElapsed > holdDuration then
			shimmerConnection:Disconnect()
		end
	end)
	self:_track(shimmerConnection)

	task.wait(holdDuration)

	local fadeOutDuration = config.Timing.TitleFadeOutDuration
	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	)
	local strokeFade = TweenService:Create(
		label:FindFirstChildOfClass("UIStroke"),
		TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1 }
	)
	local scaleUp = TweenService:Create(
		uiScale,
		TweenInfo.new(fadeOutDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Scale = 1.15 }
	)

	fadeTween:Play()
	strokeFade:Play()
	scaleUp:Play()
	fadeTween.Completed:Wait()

	label:Destroy()
end

--============================================================================
-- SECTION 16: SUBTITLE ("Rebirth #N")
--============================================================================

function RebirthEffect:_playSubtitleAnimation()
	local config = self.Config
	local colors = self.Colors

	if config.RebirthCount == nil then
		return
	end

	task.wait(config.Timing.SubtitleDelay)

	local label = Instance.new("TextLabel")
	label.Name = "SubtitleLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(400, 50)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = colors.Secondary
	label.Font = Enum.Font.GothamBold
	label.TextSize = 28
	label.TextTransparency = 1
	label.ZIndex = 50
	label.Parent = self._root

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = colors.Accent
	stroke.Transparency = 1
	stroke.Parent = label

	-- Slide up + fade in.
	label.Position = UDim2.fromScale(0.5, 0.58)
	local slideTween = TweenService:Create(
		label,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.5), TextTransparency = 0 }
	)
	local strokeTween = TweenService:Create(
		stroke,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 0 }
	)

	slideTween:Play()
	strokeTween:Play()

	-- Count up from 1 to RebirthCount if it's a positive integer greater
	-- than 1; otherwise just show the number directly.
	local target = config.RebirthCount
	if type(target) == "number" and target > 1 then
		local from = math.max(1, target - 1)
		local countDuration = 0.5
		local elapsed = 0
		local connection
		connection = RunService.RenderStepped:Connect(function(dt)
			elapsed += dt
			local t = clamp(elapsed / countDuration, 0, 1)
			local value = math.floor(lerp(from, target, Easing.OutCubic(t)) + 0.5)
			label.Text = string.format("Rebirth #%d", value)
			if t >= 1 then
				label.Text = string.format("Rebirth #%d", target)
				connection:Disconnect()
			end
		end)
		self:_track(connection)
		task.wait(countDuration)
	else
		label.Text = string.format("Rebirth #%s", tostring(target))
	end

	task.wait(1.0)

	local fadeTween = TweenService:Create(
		label,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.44) }
	)
	local strokeFadeTween = TweenService:Create(
		stroke,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1 }
	)
	fadeTween:Play()
	strokeFadeTween:Play()
	fadeTween.Completed:Wait()

	label:Destroy()
end

--============================================================================
-- SECTION 17: SPARKLE FIELD
--============================================================================
-- Small twinkling diamonds scattered across the whole screen (not just the
-- center) that fade in and out on independent random cycles for the
-- duration of the effect, giving a "magical dust" ambience.

function RebirthEffect:_playSparkleField()
	local config = self.Config
	local colors = self.Colors
	local count = config.Counts.Sparkles
	local duration = config.Timing.SparkleDuration

	local pool = self:_getPool("sparkle", function()
		return newSparkle(8, colors.Secondary, 1)
	end)

	local sparkles = {}
	for i = 1, count do
		local sparkle = pool:Get()
		local size = randomFloat(4, 10)
		sparkle.Size = UDim2.fromOffset(size, size)
		sparkle.Position = UDim2.fromScale(randomFloat(0.05, 0.95), randomFloat(0.05, 0.95))
		sparkle.BackgroundColor3 = (i % 2 == 0) and colors.Primary or colors.Secondary
		sparkle.ZIndex = 8
		sparkle.Visible = true
		sparkle.Parent = self._root

		sparkles[i] = {
			inst = sparkle,
			phase = randomFloat(0, math.pi * 2),
			speed = randomFloat(2, 5),
		}
	end

	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		for _, data in ipairs(sparkles) do
			local twinkle = (math.sin(elapsed * data.speed + data.phase) + 1) / 2
			data.inst.BackgroundTransparency = 1 - twinkle
			data.inst.Rotation = 45 + math.sin(elapsed * 0.5 + data.phase) * 20
		end
		if elapsed > duration then
			connection:Disconnect()
		end
	end)
	self:_track(connection)

	task.wait(duration)

	for _, data in ipairs(sparkles) do
		pool:Release(data.inst)
	end
end

--============================================================================
-- SECTION 18: VIGNETTE PULSE
--============================================================================
-- Four edge-anchored frames with inward gradients that briefly darken the
-- border of the screen and fade back out, drawing the eye toward center.

function RebirthEffect:_playVignettePulse()
	if not self.Config.VignettePulse then
		return
	end

	local holder = Instance.new("Frame")
	holder.Name = "Vignette"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	holder.Parent = self._root

	local edges = {
		{ size = UDim2.new(1, 0, 0, 140), pos = UDim2.new(0, 0, 0, 0), rot = 0 },
		{ size = UDim2.new(1, 0, 0, 140), pos = UDim2.new(0, 0, 1, -140), rot = 0 },
		{ size = UDim2.new(0, 140, 1, 0), pos = UDim2.new(0, 0, 0, 0), rot = 0 },
		{ size = UDim2.new(0, 140, 1, 0), pos = UDim2.new(1, -140, 0, 0), rot = 0 },
	}

	local frames = {}
	for i, edge in ipairs(edges) do
		local f = Instance.new("Frame")
		f.Size = edge.size
		f.Position = edge.pos
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = holder

		local gradient = Instance.new("UIGradient")
		local isHorizontalEdge = i <= 2
		gradient.Rotation = isHorizontalEdge and 90 or 0
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, i == 1 and 0 or (i == 2 and 1 or (i == 3 and 0 or 1))),
			NumberSequenceKeypoint.new(1, i == 1 and 1 or (i == 2 and 0 or (i == 3 and 1 or 0))),
		})
		gradient.Parent = f

		table.insert(frames, f)
	end

	local inTween = {}
	for _, f in ipairs(frames) do
		local tween = TweenService:Create(
			f,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 0.55 }
		)
		tween:Play()
		table.insert(inTween, tween)
	end

	task.wait(0.9)

	local outTweens = {}
	for _, f in ipairs(frames) do
		local tween = TweenService:Create(
			f,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ BackgroundTransparency = 1 }
		)
		tween:Play()
		table.insert(outTweens, tween)
	end

	task.wait(0.55)
	holder:Destroy()
end

--============================================================================
-- SECTION 19: CAMERA SHAKE
--============================================================================
-- Optional. Nudges workspace.CurrentCamera's CFrame with decaying random
-- offsets. Because this touches the live camera, it's OFF by default -- flip
-- Config.CameraShake.Enabled = true to use it. This uses a common trick of
-- applying a small offset every RenderStepped frame and never storing a
-- "base" CFrame, since the default camera scripts (or a custom one) keep
-- updating CurrentCamera.CFrame on their own each frame anyway; we just ride
-- on top of whatever it set for this one frame.

function RebirthEffect:_playCameraShake()
	local config = self.Config.CameraShake
	if not config.Enabled then
		return
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local duration = config.Duration
	local magnitude = config.Magnitude
	local roughness = config.Roughness

	local elapsed = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = clamp(elapsed / duration, 0, 1)
		if t >= 1 then
			connection:Disconnect()
			return
		end

		local falloff = 1 - Easing.OutQuad(t)
		local time = elapsed * roughness
		local offsetX = (math.noise(time, 0, 0)) * magnitude * falloff
		local offsetY = (math.noise(0, time, 0)) * magnitude * falloff
		local offsetRot = (math.noise(0, 0, time)) * magnitude * falloff * 2

		local shakeCFrame = CFrame.new(offsetX, offsetY, 0) * CFrame.Angles(0, 0, math.rad(offsetRot))
		camera.CFrame = camera.CFrame * shakeCFrame
	end)
	self:_track(connection)

	task.wait(duration)
end

--============================================================================
-- SECTION 20: ORCHESTRATION
--============================================================================
-- This is the timeline that decides what plays when. Effects that should
-- happen in parallel are task.spawn'd; effects that should block the
-- sequence use task.wait / :Wait() inside their own functions (see above).

function RebirthEffect:_runSequence()
	if self.Destroyed then
		return
	end

	-- 1. Flash + camera shake kick off together.
	task.spawn(function()
		self:_playCameraShake()
	end)
	self:_playScreenFlash()

	if self.Stopped or self.Destroyed then
		return
	end

	-- 2. Everything else fires roughly together right as the flash clears.
	task.spawn(function()
		self:_playChromaticFlicker()
	end)
	task.spawn(function()
		self:_playVignettePulse()
	end)
	task.spawn(function()
		self:_playAllShockwaveRings()
	end)
	task.spawn(function()
		self:_playBurstParticles()
	end)
	task.spawn(function()
		self:_playEnergyBeams()
	end)
	task.spawn(function()
		self:_playGlowPulse()
	end)
	task.spawn(function()
		self:_playSparkleField()
	end)

	-- 3. Title and subtitle run in sequence with each other but in parallel
	--    with the ambient effects above.
	self:_playTitleAnimation()
	if self.Stopped or self.Destroyed then
		return
	end
end

--============================================================================
-- SECTION 21: PUBLIC API - Play / Stop / Destroy
--============================================================================

-- Starts the animation inside the given ScreenGui. Returns `self` (the
-- effect handle) immediately; the animation itself runs asynchronously.
-- Listen for `handle.Completed:Connect(function() ... end)` to know when
-- everything has fully finished and cleaned itself up.
--
-- NOTE: this is intentionally named `_startPlaying` and not `Play`. The
-- public static `RebirthEffect.Play(screenGui, options)` further down and
-- an instance method both writing to the same `Play` key on this table
-- would silently overwrite one another (Lua doesn't distinguish `.` vs `:`
-- when it comes to *defining* keys, only when *calling* them), which used
-- to shift arguments and crash `deepMerge` on an Instance. Keeping the
-- internal one separately named avoids that collision entirely.
function RebirthEffect:_startPlaying(screenGui)
	self:_buildRoot(screenGui)

	local safetyTimeout = self.Config.Timing.TotalSafetyTimeout

	task.spawn(function()
		local finished = false

		local watchdog = task.delay(safetyTimeout, function()
			if not finished then
				warn("[RebirthEffect] Safety timeout reached, forcing cleanup.")
				self:Destroy()
			end
		end)

		local ok, err = pcall(function()
			self:_runSequence()
		end)

		finished = true
		if watchdog then
			task.cancel(watchdog)
		end

		if not ok then
			warn("[RebirthEffect] Error during sequence: " .. tostring(err))
		end

		self:_cleanup()
		self.Completed:Fire()
	end)

	return self
end

-- Signals the running sequence to stop advancing to new stages. Anything
-- already mid-tween will still finish naturally to avoid visual popping,
-- but no *new* stages will begin after this is called.
function RebirthEffect:Stop()
	self.Stopped = true
end

-- Immediately tears down all instances and connections. Safe to call more
-- than once. After calling this, the effect handle should be discarded.
function RebirthEffect:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.Stopped = true
	self:_cleanup()
end

function RebirthEffect:_cleanup()
	for _, connection in ipairs(self._connections) do
		if connection.Disconnect then
			connection:Disconnect()
		end
	end
	table.clear(self._connections)

	for _, pool in pairs(self._pools) do
		pool:DestroyAll()
	end
	table.clear(self._pools)

	if self._root then
		self._root:Destroy()
		self._root = nil
	end
end

--============================================================================
-- SECTION 22: STATIC CONVENIENCE WRAPPER
--============================================================================
-- The simplest possible call site:
--
--     RebirthEffect.Play(someScreenGui)
--
-- or with options:
--
--     RebirthEffect.Play(someScreenGui, { Theme = "Amethyst", RebirthCount = 3 })

function RebirthEffect.Play(screenGui, options)
	local instance = RebirthEffect.new(options)
	return instance:_startPlaying(screenGui)
end

-- Exposes the theme table read-only, in case a game wants to list available
-- themes in a settings menu or validate a theme name before passing it in.
function RebirthEffect.GetThemeNames()
	local names = {}
	for name in pairs(THEMES) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- Exposes a copy of the default config, useful for building a custom
-- options table by starting from the defaults and only changing a few keys.
function RebirthEffect.GetDefaultConfig()
	return deepCopy(DEFAULT_CONFIG)
end

-- Exposes the Easing library in case other UI scripts in the same game
-- want consistent, hand-rolled easing curves without pulling in a separate
-- dependency.
RebirthEffect.Easing = Easing

--============================================================================
-- END OF MODULE
--============================================================================

return RebirthEffect
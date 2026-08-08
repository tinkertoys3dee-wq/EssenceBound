--[[
	Juice (ModuleScript -> ReplicatedStorage)
	=========================================
	Shared "game feel" toolkit. Every effect in here is PURELY COSMETIC --
	nothing in this file changes a reward, a rate, or any gameplay value.
	It exists so the same punch/ring/burst/count-up behaviour can be reused
	across the client scripts instead of each one hand-rolling its own
	slightly different version.

	WHY IT'S A SHARED MODULE
	-------------------------
	Feel only reads as intentional when it's consistent: every button
	should depress the same way, every reward should pop the same way, and
	every sound should vary its pitch by the same rules. Scattering that
	logic across five scripts guarantees drift.

	PERFORMANCE
	------------
	The audience for this game is largely on phones and low-end laptops, so
	every effect here:
	  - uses TweenService rather than per-frame RunService loops wherever
	    the motion allows it,
	  - creates plain Frames (with UICorner) instead of ParticleEmitters,
	    which is much cheaper in a ScreenGui context,
	  - destroys everything it creates,
	  - is capped by ACTIVE_PARTICLE_LIMIT so a burst of rapid clicks can
	    never snowball into hundreds of live instances.

	Every public function is written to fail quietly on a nil/destroyed
	instance rather than throw -- a cosmetic effect must never be able to
	break the gameplay code that called it.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Juice = {}

-- =========================================================================
-- BUDGET
-- =========================================================================

local ACTIVE_PARTICLE_LIMIT = 90
local activeParticles = 0

local function canSpawnParticle()
	return activeParticles < ACTIVE_PARTICLE_LIMIT
end

local function trackParticle(instance, lifetime)
	activeParticles += 1
	Debris:AddItem(instance, lifetime)
	task.delay(lifetime, function()
		activeParticles = math.max(0, activeParticles - 1)
	end)
end

local function isAlive(instance)
	return typeof(instance) == "Instance" and instance.Parent ~= nil
end

-- =========================================================================
-- SOUND
-- =========================================================================
-- The same sound asset played at the same pitch dozens of times a minute
-- is what makes a clicker feel cheap. Every call here clones the source
-- sound so overlapping plays don't cut each other off, and jitters the
-- pitch so a rapid streak reads as a run of related notes rather than one
-- sample stuttering.

local DEFAULT_PITCH_RANGE = { 0.94, 1.06 }

-- Resolves "SFX/UI/UIPop" style paths, returning nil rather than erroring
-- if the sound isn't in this place.
function Juice.FindSound(path: string): Sound?
	local current: Instance? = SoundService
	for segment in string.gmatch(path, "[^/]+") do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end

	if current and current:IsA("Sound") then
		return current
	end
	return nil
end

-- opts: { Pitch = number, PitchRange = {min, max}, Volume = number }
function Juice.PlaySound(source: Sound?, opts)
	if not source or not source:IsA("Sound") then
		return
	end

	opts = opts or {}

	local ok = pcall(function()
		local clone = source:Clone()

		if opts.Pitch then
			clone.PlaybackSpeed = opts.Pitch
		else
			local range = opts.PitchRange or DEFAULT_PITCH_RANGE
			local min, max = range[1], range[2]
			clone.PlaybackSpeed = min + math.random() * (max - min)
		end

		if opts.Volume then
			clone.Volume = opts.Volume
		end

		clone.Parent = SoundService
		clone:Play()

		-- Length can be 0 until the asset loads; the fallback keeps the
		-- clone from lingering forever if it never reports a duration.
		local lifetime = (clone.Length > 0 and clone.Length or 3) + 0.25
		Debris:AddItem(clone, lifetime / math.max(0.05, clone.PlaybackSpeed))
	end)

	return ok
end

-- Maps a 0..1 intensity onto a rising musical-ish pitch. Used so a fast
-- click streak climbs instead of repeating one note.
function Juice.PitchForStreak(streak: number, maxStreak: number?): number
	maxStreak = maxStreak or 12
	local t = math.clamp((streak or 0) / maxStreak, 0, 1)
	-- Roughly a perfect fifth of travel across the streak, which stays
	-- pleasant rather than turning shrill.
	return 1 + (t * 0.5)
end

-- =========================================================================
-- SCALE PUNCH
-- =========================================================================
-- Snappy overshoot-and-settle on a UIScale. Reads as "impact" far better
-- than a linear grow, and is the cheapest possible way to make a click
-- feel like it landed.

function Juice.Punch(uiScale: UIScale?, amount: number?, duration: number?)
	if not isAlive(uiScale) then
		return
	end

	amount = amount or 0.18
	duration = duration or 0.18

	local base = uiScale:GetAttribute("JuiceBaseScale")
	if not base then
		base = uiScale.Scale
		uiScale:SetAttribute("JuiceBaseScale", base)
	end

	-- Cancel-safe: jump straight to the peak, then ease home. Overlapping
	-- punches therefore re-trigger cleanly instead of fighting each other
	-- over the same property.
	uiScale.Scale = base * (1 + amount)

	TweenService:Create(
		uiScale,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = base }
	):Play()
end

-- =========================================================================
-- SHAKE
-- =========================================================================
-- Positional jitter that always restores the element's original Position.
-- Deliberately reserved for genuinely notable moments (crits, big claims)
-- -- shaking on every single click is nauseating, especially for the
-- younger players this game is aimed at.

function Juice.Shake(target: GuiObject?, intensity: number?, duration: number?)
	if not isAlive(target) then
		return
	end

	-- Only one shake per element at a time, otherwise concurrent shakes
	-- each restore to a "base" the other one had already offset.
	if target:GetAttribute("JuiceShaking") then
		return
	end
	target:SetAttribute("JuiceShaking", true)

	intensity = intensity or 6
	duration = duration or 0.25

	local origin = target.Position

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt

			if not isAlive(target) then
				break
			end

			-- Decay so the shake settles instead of stopping dead.
			local falloff = 1 - (elapsed / duration)
			local offsetX = (math.random() * 2 - 1) * intensity * falloff
			local offsetY = (math.random() * 2 - 1) * intensity * falloff

			target.Position = origin + UDim2.fromOffset(offsetX, offsetY)
		end

		if isAlive(target) then
			target.Position = origin
			target:SetAttribute("JuiceShaking", nil)
		end
	end)
end

-- =========================================================================
-- EXPANDING RING
-- =========================================================================
-- The classic "impact" tell: a ring that races outward and fades. Cheap
-- (one Frame + stroke) and reads instantly at any screen size.

-- opts: { Color, StartSize, EndSize, Duration, Thickness, ZIndex }
function Juice.Ring(parent: GuiObject?, position: UDim2, opts)
	if not isAlive(parent) or not canSpawnParticle() then
		return
	end

	opts = opts or {}
	local duration = opts.Duration or 0.45
	local startSize = opts.StartSize or 40
	local endSize = opts.EndSize or 160

	local ring = Instance.new("Frame")
	ring.Name = "JuiceRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = position
	ring.Size = UDim2.fromOffset(startSize, startSize)
	ring.BackgroundTransparency = 1
	ring.ZIndex = opts.ZIndex or 50
	ring.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Color = opts.Color or Color3.fromRGB(255, 255, 255)
	stroke.Thickness = opts.Thickness or 3
	stroke.Transparency = 0.05
	stroke.Parent = ring

	trackParticle(ring, duration + 0.1)

	TweenService:Create(ring, TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(endSize, endSize),
	}):Play()

	TweenService:Create(stroke, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Thickness = 0,
	}):Play()

	return ring
end

-- =========================================================================
-- PARTICLE BURST
-- =========================================================================
-- Radial spray of small dots. The single most effective "something good
-- happened" signal available in a ScreenGui.

-- opts: { Count, Colors, Spread, Distance, Duration, Size, ZIndex, Gravity }
function Juice.Burst(parent: GuiObject?, position: UDim2, opts)
	if not isAlive(parent) then
		return
	end

	opts = opts or {}
	local count = opts.Count or 8
	local colors = opts.Colors or { Color3.fromRGB(255, 215, 0) }
	local duration = opts.Duration or 0.55
	local distance = opts.Distance or 90
	local sizeRange = opts.Size or { 5, 11 }

	for _ = 1, count do
		if not canSpawnParticle() then
			break
		end

		local particle = Instance.new("Frame")
		particle.Name = "JuiceParticle"
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = position
		particle.BackgroundColor3 = colors[math.random(1, #colors)]
		particle.BackgroundTransparency = 0.05
		particle.BorderSizePixel = 0
		particle.ZIndex = opts.ZIndex or 50

		local size = math.random(sizeRange[1], sizeRange[2])
		particle.Size = UDim2.fromOffset(size, size)
		particle.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = particle

		local life = duration * (0.75 + math.random() * 0.5)
		trackParticle(particle, life + 0.1)

		local angle = math.random() * math.pi * 2
		local travel = distance * (0.55 + math.random() * 0.65)
		local offsetX = math.cos(angle) * travel
		-- Slight upward bias plus optional gravity makes the spray feel
		-- like it has weight rather than being a flat starburst.
		local offsetY = math.sin(angle) * travel - (opts.Gravity or 18)

		TweenService:Create(particle, TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = position + UDim2.fromOffset(offsetX, offsetY),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size * 0.2, size * 0.2),
			Rotation = math.random(-180, 180),
		}):Play()
	end
end

-- =========================================================================
-- FLOATING TEXT
-- =========================================================================
-- Rising, fading label -- "+250", "CRITICAL!", "STREAK!". Scales in with
-- an overshoot so it pops rather than simply appearing.

-- opts: { Color, StrokeColor, Duration, Rise, TextSize, Font, ZIndex }
function Juice.FloatText(parent: GuiObject?, position: UDim2, text: string, opts)
	if not isAlive(parent) or not canSpawnParticle() then
		return
	end

	opts = opts or {}
	local duration = opts.Duration or 0.9
	local rise = opts.Rise or 70

	local label = Instance.new("TextLabel")
	label.Name = "JuiceFloatText"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = UDim2.fromOffset(160, 44)
	label.BackgroundTransparency = 1
	label.Font = opts.Font or Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = opts.Color or Color3.fromRGB(255, 235, 130)
	label.TextStrokeColor3 = opts.StrokeColor or Color3.fromRGB(30, 16, 48)
	label.TextStrokeTransparency = 0.15
	label.TextScaled = true
	label.ZIndex = opts.ZIndex or 60
	label.Parent = parent

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = opts.TextSize or 34
	constraint.Parent = label

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label

	trackParticle(label, duration + 0.1)

	TweenService:Create(scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = position - UDim2.fromOffset(0, rise),
	}):Play()

	-- Held briefly at full opacity before fading, so it's readable rather
	-- than a blur that vanishes as soon as it appears.
	task.delay(duration * 0.35, function()
		if not isAlive(label) then
			return
		end
		local fade = TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(label, fade, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)

	return label
end

-- =========================================================================
-- FULL-SCREEN FLASH
-- =========================================================================
-- A brief colour wash for genuinely big moments. Kept subtle by default:
-- a hard white flash is unpleasant and, for some players, genuinely
-- uncomfortable, so the default peak transparency stays well short of
-- opaque and the fade is quick.

-- opts: { Color, Peak, Duration, ZIndex }
function Juice.Flash(parent: GuiObject?, opts)
	if not isAlive(parent) then
		return
	end

	opts = opts or {}
	local peak = opts.Peak or 0.72
	local duration = opts.Duration or 0.4

	local flash = Instance.new("Frame")
	flash.Name = "JuiceFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = opts.Color or Color3.fromRGB(255, 240, 190)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = opts.ZIndex or 90
	flash.Parent = parent

	Debris:AddItem(flash, duration + 0.2)

	local up = TweenService:Create(flash, TweenInfo.new(duration * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = peak,
	})
	up:Play()
	up.Completed:Connect(function()
		if isAlive(flash) then
			TweenService:Create(flash, TweenInfo.new(duration * 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}):Play()
		end
	end)
end

-- =========================================================================
-- ANIMATED COUNT-UP
-- =========================================================================
-- Currency that snaps from one number to another is the single biggest
-- missed opportunity in an idle game -- the whole point of the genre is
-- watching the number climb. This rolls a label from its previous value
-- to the new one.
--
-- Concurrency is handled with a per-label token: a new call supersedes any
-- in-flight animation on the same label rather than the two interleaving
-- and producing flickering garbage.

local countTokens = {}

-- opts: { Duration, Formatter, OnComplete }
function Juice.CountUp(label: TextLabel?, fromValue: number, toValue: number, opts)
	if not isAlive(label) then
		return
	end

	opts = opts or {}
	local formatter = opts.Formatter or tostring
	local duration = opts.Duration or 0.45

	local token = (countTokens[label] or 0) + 1
	countTokens[label] = token

	-- Not worth animating a change too small to perceive.
	if math.abs(toValue - fromValue) < 1 or duration <= 0 then
		label.Text = formatter(toValue)
		label:SetAttribute("JuiceCurrentValue", toValue)
		if opts.OnComplete then
			task.spawn(opts.OnComplete)
		end
		return
	end

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt

			-- Superseded by a newer count-up, or the label is gone.
			if countTokens[label] ~= token or not isAlive(label) then
				return
			end

			-- Ease-out so it sprints then settles, which reads as more
			-- exciting than a linear roll.
			local t = math.clamp(elapsed / duration, 0, 1)
			local eased = 1 - (1 - t) ^ 3
			local current = fromValue + (toValue - fromValue) * eased
			label.Text = formatter(current)

			-- Published so a caller that re-triggers mid-roll can resume
			-- from where the number visibly IS rather than from where the
			-- last animation was aiming. Without this, a counter updated
			-- several times a second (every orb collected) visibly jumps
			-- backwards and forwards instead of climbing smoothly.
			label:SetAttribute("JuiceCurrentValue", current)
		end

		if countTokens[label] == token and isAlive(label) then
			label.Text = formatter(toValue)
			label:SetAttribute("JuiceCurrentValue", toValue)
			if opts.OnComplete then
				task.spawn(opts.OnComplete)
			end
		end
	end)
end

-- =========================================================================
-- COLOUR PULSE
-- =========================================================================
-- Flashes a label to a highlight colour and back. Used to draw the eye to
-- a number that just changed.

function Juice.PulseColor(label: TextLabel?, highlight: Color3, duration: number?)
	if not isAlive(label) then
		return
	end

	duration = duration or 0.35

	local base = label:GetAttribute("JuiceBaseColor")
	if not base then
		base = label.TextColor3
		label:SetAttribute("JuiceBaseColor", base)
	end

	label.TextColor3 = highlight
	TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextColor3 = base,
	}):Play()
end

-- Same idea for anything that isn't text (bars, panels, icons), which use
-- BackgroundColor3 rather than TextColor3.
function Juice.PulseBackground(target: GuiObject?, highlight: Color3, duration: number?)
	if not isAlive(target) then
		return
	end

	duration = duration or 0.35

	local base = target:GetAttribute("JuiceBaseBackground")
	if not base then
		base = target.BackgroundColor3
		target:SetAttribute("JuiceBaseBackground", base)
	end

	target.BackgroundColor3 = highlight
	TweenService:Create(target, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = base,
	}):Play()
end

-- Returns the element's UIScale, creating one if absent. A fresh UIScale
-- defaults to Scale = 1, so adding it never changes how anything looks --
-- it just gives Punch something to animate.
function Juice.GetScale(target: GuiObject?): UIScale?
	if not isAlive(target) then
		return nil
	end

	local existing = target:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = target
	return scale
end

-- =========================================================================
-- UNIFIED BUTTON FEEL
-- =========================================================================
-- One implementation of hover-grow / press-depress / release-settle, so
-- every button in the game responds identically. Safe to call more than
-- once on the same button -- it tags what it has already wired up.

-- opts: { HoverScale, Sound, PitchRange, Target }
function Juice.ButtonFeel(button: GuiButton?, opts)
	if not isAlive(button) or not button:IsA("GuiButton") then
		return
	end

	if button:GetAttribute("JuiceFeelApplied") then
		return
	end
	button:SetAttribute("JuiceFeelApplied", true)

	opts = opts or {}
	local hoverScale = opts.HoverScale or 1.06
	local target = opts.Target or button

	local scale = target:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = target
	end

	local baseScale = scale.Scale

	local function to(value, info)
		TweenService:Create(scale, info, { Scale = value }):Play()
	end

	button.MouseEnter:Connect(function()
		to(baseScale * hoverScale, TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end)
	button.MouseLeave:Connect(function()
		to(baseScale, TweenInfo.new(0.13, Enum.EasingStyle.Sine, Enum.EasingDirection.Out))
	end)
	button.MouseButton1Down:Connect(function()
		to(baseScale * 0.93, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
	end)
	button.MouseButton1Up:Connect(function()
		to(baseScale * hoverScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end)

	if opts.Sound then
		button.MouseButton1Click:Connect(function()
			Juice.PlaySound(opts.Sound, { PitchRange = opts.PitchRange })
		end)
	end
end

-- =========================================================================
-- SHARED EFFECT LAYER
-- =========================================================================
-- One full-screen overlay that every script spawns its effects into,
-- rather than each creating its own ScreenGui. Living outside MainGui
-- means rings and particles can never be clipped by, or disturb the
-- layout of, the game's real UI.
--
-- The container is a plain Frame, which consumes no input -- only
-- GuiButtons and Active elements do -- so this never blocks clicks on
-- anything underneath it.

function Juice.GetLayer(playerGui: Instance): Frame?
	if not playerGui then
		return nil
	end

	local existing = playerGui:FindFirstChild("JuiceFX")
	if existing then
		local layer = existing:FindFirstChild("Layer")
		if layer and layer:IsA("Frame") then
			return layer
		end
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "JuiceFX"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 40
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local layer = Instance.new("Frame")
	layer.Name = "Layer"
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.Parent = screenGui

	return layer
end

-- =========================================================================
-- SHARED RELIC BAR
-- =========================================================================
-- One shared, auto-laid-out row that every Sanctum relic's countdown pill
-- registers into, rather than each relic script hand-picking its own
-- screen position. Relics currently live across three different
-- LocalScripts (OrbClicker, CursorCollection, and any future one) --
-- coordinates picked independently in each file are exactly how pills
-- silently overlap the moment a new relic is added or the bar needs to
-- move. A UIListLayout lays every registered pill out automatically, in
-- registration order, so there's exactly one place to reposition the
-- whole group.

local relicBarLayer = nil

local function getRelicBar(playerGui: Instance): Frame?
	if not playerGui then
		return nil
	end

	if relicBarLayer and relicBarLayer.Parent then
		return relicBarLayer
	end

	local existingGui = playerGui:FindFirstChild("RelicBar")
	if existingGui then
		local existingBar = existingGui:FindFirstChild("Bar")
		if existingBar then
			relicBarLayer = existingBar
			return relicBarLayer
		end
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "RelicBar"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 45
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Bottom-center, sized as a fixed-height horizontal strip. Individual
	-- pills size themselves in offset (see Juice.RegisterRelicPill) and the
	-- UIListLayout below packs them left-to-right in registration order.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -18)
	bar.Size = UDim2.new(0, 0, 0, 30)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundTransparency = 1
	bar.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = bar

	relicBarLayer = bar
	return relicBarLayer
end

Juice.GetRelicBar = getRelicBar

-- Builds one countdown pill (icon-prefixed label + fill bar) and parents
-- it into the shared relic bar, returning the pieces the caller's own
-- countdown loop needs to update. `order` controls left-to-right position
-- among other registered pills -- callers should use a stable, distinct
-- number per relic so the bar doesn't reshuffle between sessions.
--
-- Returns nil if playerGui isn't available yet; callers should treat that
-- as "try again later" rather than erroring, same as every other Juice
-- function.
function Juice.RegisterRelicPill(playerGui: Instance, opts)
	local bar = getRelicBar(playerGui)
	if not bar then
		return nil
	end

	opts = opts or {}
	local color = opts.Color or Color3.fromRGB(190, 140, 255)

	local pill = Instance.new("Frame")
	pill.Name = (opts.Name or "Relic") .. "Countdown"
	pill.Size = UDim2.fromOffset(122, 30)
	pill.BackgroundColor3 = Color3.fromRGB(28, 17, 48)
	pill.BackgroundTransparency = 0.1
	pill.Visible = false
	pill.LayoutOrder = opts.Order or 0
	pill.Parent = bar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill

	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = color
	pillStroke.Thickness = 1.5
	pillStroke.Transparency = 0.3
	pillStroke.Parent = pill

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.75
	fill.BorderSizePixel = 0
	fill.Parent = pill

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = (opts.Icon or "") .. " --"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.ZIndex = 2
	label.Parent = pill

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 15
	textConstraint.Parent = label

	return {
		Pill = pill,
		Fill = fill,
		Label = label,
		Stroke = pillStroke,
	}
end

-- =========================================================================
-- HELPERS
-- =========================================================================

-- Converts an instance's on-screen centre into a UDim2 offset inside
-- `space`, so effects can be spawned exactly over an arbitrary element
-- regardless of how either one is anchored or nested.
function Juice.CenterOf(instance: GuiObject?, space: GuiObject?): UDim2?
	if not isAlive(instance) or not isAlive(space) then
		return nil
	end

	local pos = instance.AbsolutePosition
	local size = instance.AbsoluteSize
	local origin = space.AbsolutePosition

	return UDim2.fromOffset(
		(pos.X + size.X / 2) - origin.X,
		(pos.Y + size.Y / 2) - origin.Y
	)
end

return Juice

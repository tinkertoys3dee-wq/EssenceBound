local player = game.Players.LocalPlayer
local Gui = player:WaitForChild("PlayerGui")
local MainGui = Gui:WaitForChild("MainGui")
local Center = MainGui:WaitForChild("Center")
local LargeOrbFolder = Center:WaitForChild("LargeOrbFolder")
local LargeOrb = LargeOrbFolder:WaitForChild("LargeOrb")
local LargeOrbButton = LargeOrb:WaitForChild("TextButton")
local TweenService = game:GetService("TweenService")
local Glint = LargeOrbFolder:WaitForChild("OrbGlint")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Remotes")
local LP = LargeOrbFolder:WaitForChild("Leafparent")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local EssenceUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))
local CollectionUpgrades = require(ReplicatedStorage:WaitForChild("CollectionUpgrades"))
local Criticals = require(ReplicatedStorage:WaitForChild("CriticalsController"))

local cloneables = ReplicatedStorage:WaitForChild("Cloneables")
local ClickOrbEvent = Events:WaitForChild("ClickOrb")

local returnEvent = Events:WaitForChild("Return")
local IconIDS = {
	["EarthEssenceRegular"] = 79479049281587,
	["ShadowEssenceRegular"] = 106130917603943
}

local EssenceTypes = {
	["Earth Essence"] = {
		["Icon"] = IconIDS["EarthEssenceRegular"],
		["Name"] = "Earth Essence",
	},
	["Shadow Essence"] = {
		["Icon"] = IconIDS["ShadowEssenceRegular"],
		["Name"] = "Shadow Essence",
	},
}
local GetEssenceModule = require(ReplicatedStorage:WaitForChild("GetEssence"))
local Template = cloneables:WaitForChild("OrbClickableTemplate")

local EssenceParent = LargeOrbFolder:WaitForChild("OrbClickables")
local RunService = game:GetService("RunService")

local LargeOrbuiScale = LargeOrb:WaitForChild("UIScale")

-- 0.1 seconds makes the button feel incredibly snappy and responsive
local tweenInfo = TweenInfo.new(
	0.1,
	Enum.EasingStyle.Quad,
	Enum.EasingDirection.Out
)

local popTween = TweenService:Create(LargeOrbuiScale, tweenInfo, {Scale = 1.1}) -- Returns to 100%
local resetTween = TweenService:Create(LargeOrbuiScale, tweenInfo, {Scale = 1}) -- Squishes to 95%

-- =========================================================================
-- CLICK FEEL
-- =========================================================================
-- The great orb is the single most-repeated interaction in the game, so
-- it has to land. Everything below is cosmetic only -- no reward, rate or
-- spawn count is touched by any of it.
--
-- NOTE ON SCALE OWNERSHIP: LargeOrb's UIScale is already driven by
-- HoverClickTween (hover 1.1 / press 0.95 / release 1.1). popTween writes
-- that same property, so firing it on a manual click was overriding the
-- press-squish about a frame after it started -- the squish was there in
-- the code but never actually visible. The manual click path below now
-- leaves the scale to HoverClickTween (which is driven by real mouse
-- events and does it properly) and layers its impact on separate
-- elements instead. The automation path still uses popTween, because
-- auto-clicks fire no mouse events and would otherwise be silent.

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

-- Shared full-screen effect layer (see Juice.GetLayer) -- kept out of
-- MainGui so rings and particles can never be clipped by, or interfere
-- with the layout of, the existing UI.
local juiceLayer = Juice.GetLayer(Gui)

local ESSENCE_GREEN = Color3.fromRGB(120, 240, 160)
local ESSENCE_GOLD = Color3.fromRGB(255, 205, 80)
local ESSENCE_DEEP = Color3.fromRGB(150, 110, 240)

local clickSound = Juice.FindSound("SFX/UI/UIPop")

-- Rapid clicking escalates the feedback: the pitch climbs, the ring grows
-- and the burst thickens. Purely a feedback curve -- it does not change
-- what a click is worth.
local clickStreak = 0
local lastClickAt = 0
local STREAK_WINDOW = 0.65
local STREAK_MAX = 20

local function OrbClickJuice(isAutomated)
	local now = os.clock()

	if isAutomated then
		-- Automated clicks get the visual but never drive the streak or
		-- the rising pitch -- otherwise idle play would sit at a
		-- permanently shrill top note the player didn't earn.
		local center = Juice.CenterOf(LargeOrb, juiceLayer)
		if center then
			Juice.Ring(juiceLayer, center, {
				Color = ESSENCE_GREEN,
				StartSize = 70,
				EndSize = 150,
				Duration = 0.5,
				Thickness = 2,
			})
		end
		return
	end

	if (now - lastClickAt) <= STREAK_WINDOW then
		clickStreak = math.min(clickStreak + 1, STREAK_MAX)
	else
		clickStreak = 1
	end
	lastClickAt = now

	local intensity = clickStreak / STREAK_MAX

	if clickSound then
		Juice.PlaySound(clickSound, {
			Pitch = Juice.PitchForStreak(clickStreak, 14) * (0.97 + math.random() * 0.06),
			Volume = 0.5,
		})
	end

	local center = Juice.CenterOf(LargeOrb, juiceLayer)
	if not center then
		return
	end

	Juice.Ring(juiceLayer, center, {
		Color = intensity > 0.6 and ESSENCE_GOLD or ESSENCE_GREEN,
		StartSize = 80,
		EndSize = 170 + (intensity * 90),
		Duration = 0.45,
		Thickness = 2 + (intensity * 2),
	})

	Juice.Burst(juiceLayer, center, {
		Count = 4 + math.floor(intensity * 7),
		Colors = { ESSENCE_GREEN, ESSENCE_GOLD, ESSENCE_DEEP },
		Distance = 90 + (intensity * 70),
		Duration = 0.5,
		Size = { 4, 9 },
	})

	-- A bigger beat every 10 clicks in a row, so a sustained streak builds
	-- to something instead of flatlining.
	if clickStreak > 0 and clickStreak % 10 == 0 then
		Juice.Shake(Center, 5, 0.22)
		Juice.Burst(juiceLayer, center, {
			Count = 14,
			Colors = { ESSENCE_GOLD, Color3.fromRGB(255, 255, 255) },
			Distance = 210,
			Duration = 0.7,
			Size = { 6, 13 },
		})
	end
end

-- =========================================================================
-- COLLECTION UPGRADES: overflow_capacity (max active orbs) + magnetic_pull
-- (drift toward cursor). Both are spawn/motion concerns, so they live here
-- rather than in CollectionRing.lua, which only owns overlap detection.
-- =========================================================================

-- Base cap before any overflow_capacity levels are applied. Tune to taste -
-- this is a design choice, not something EssenceUpgrades specifies.
local BASE_MAX_ACTIVE_ORBS = 400

-- How strongly MagnetStrength pulls orbs toward the cursor, in scale-units
-- of homing speed per point of MagnetStrength. Tune to taste.
local MAGNET_PULL_COEFFICIENT = 0.15

local function ActiveOrbCount()
	return #EssenceParent:GetChildren()
end

local function CanSpawnOrb()
	local cap = BASE_MAX_ACTIVE_ORBS + CollectionUpgrades.GetMaxActiveOrbsBonus(player)
	return ActiveOrbCount() < cap
end

-- Sums EffectPerLevel * currentLevel across every upgrade with the given
-- EffectType, reading levels straight from player attributes (source of
-- truth per-upgrade is player:GetAttribute(upgradeId)).
local function GetSummedEffectFromAttributes(plr, effectType)
	local total = 0
	for _, def in ipairs(EssenceUpgrades.List) do
		if def.EffectType == effectType then
			local level = plr:GetAttribute(def.Id) or 0
			total += def.EffectPerLevel * level
		end
	end
	return total
end
-- Converts the current mouse position into the same 0-1 scale-space that
-- orb Position values use, relative to `container` (EssenceParent). Mirrors
-- the inset-handling in CollectionRing.lua so orbs and the ring agree on
-- where the cursor actually is.
local function getMouseInContainerScale(container)
	local mouseLoc = UserInputService:GetMouseLocation()
	if not MainGui.IgnoreGuiInset then
		mouseLoc = mouseLoc - GuiService:GetGuiInset()
	end

	local containerPos = container.AbsolutePosition
	local containerSize = container.AbsoluteSize
	if containerSize.X <= 0 or containerSize.Y <= 0 then
		return 0.5, 0.5
	end

	return (mouseLoc.X - containerPos.X) / containerSize.X,
		(mouseLoc.Y - containerPos.Y) / containerSize.Y
end

-- Fragments (shatter_force bonus orbs) read as smaller, dimmer, and worth
-- less essence than a real orb — visually distinct so the player can tell
-- "that was a shatter fragment" from "that was a full orb."
local FRAGMENT_VALUE_MULT = 0.35   -- essence value relative to a full orb
local FRAGMENT_SIZE_MULT = 0.55    -- shrinks the base orb size further
local FRAGMENT_EXTRA_TRANSPARENCY = 0.2 -- a bit more washed-out/translucent
local FRAGMENT_TINT = Color3.fromRGB(200, 200, 210) -- slight desaturation

local ORB_FX = {
	-- Glow
	GlowEnabled = true,
	GlowMaxSizeMult = 2.4, -- multiple of the orb's own footprint
	GlowPulseSpeed = 1.6, -- radians/sec while flying/settled
	GlowIdlePulseSpeed = 0.9, -- radians/sec while idle-orbiting (slower, calmer)
	GlowMinAlphaMult = 0.5, -- how dim the glow gets at the bottom of its pulse

	-- Motion trail
	TrailEnabled = true,
	TrailSpawnInterval = 0.035, -- seconds between ghost spawns while flying
	TrailLifetime = 0.32,
	TrailStartTransparency = 0.4,
	TrailShrinkTo = 0.4, -- ghost shrinks to this fraction of its spawn size

	-- Landing impact
	SquashStretchEnabled = true,
	SquashAmount = 0.3, -- 0-1, how extreme the squash/stretch is
	SquashRecoverTime = 0.22,
	ImpactBurstEnabled = true,
	ImpactBurstCount = 8,
	ImpactBurstLifetime = 0.42,
	ImpactRingEnabled = true,
	ImpactRingLifetime = 0.38,

	-- Idle phase
	ShimmerEnabled = true,
	ShimmerCycleSpeed = .75, -- cycles/sec across the icon
	IdleSparkleRingEnabled = true,
	IdleSparkleCount = 3,
	IdleSparkleOrbitSpeedMult = 2.6, -- relative to the orb's own orbit speed
	IdleSparkleRadiusMult = 25, -- relative to the orb's own orbit radius
	IdleSparkleSize = 1,

	-- Return trip
	ReturnStreakEnabled = true,
	ReturnPoofEnabled = true,
	ReturnPoofCount = 6,
}

-- =========================================================================
-- CRITICAL HIT VISUALS (Critical Essence tree: critical_chance_1/2/3,
-- critical_multiplier_1/2, guaranteed_crit_streak, double_crit). Everything
-- here is purely cosmetic reaction to Criticals.RollCrit's boolean -- the
-- actual bonus essence a crit is worth is computed server-side off
-- CritMultiplierBonus (see EssenceMultiplier.lua / CriticalsController.lua)
-- and is NOT influenced by anything in this table.
--
-- double_crit is intentionally NOT given its own client-side visual here:
-- RollDoubleCrit is meant to be rolled server-side (it's what actually
-- decides the payout), and re-rolling it client-side just for flair would
-- desync from that server roll -- the orb could flash "double crit" and
-- then get paid for a single crit, or vice versa. If you want a distinct
-- double-crit visual later, drive it off a server -> client signal on the
-- "collected" round-trip instead of rolling it again here.
-- =========================================================================
local CRIT_COLOR = Color3.fromRGB(255, 200, 40)     -- gold/amber crit tint
local CRIT_SIZE_MULT = 1.28                         -- crit orbs spawn noticeably bigger
local CRIT_GLOW_SIZE_MULT_BONUS = 0.9               -- extra glow radius on top of ORB_FX.GlowMaxSizeMult
local CRIT_GLOW_PULSE_SPEED_MULT = 1.6              -- crit glow pulses faster than normal
local CRIT_IMPACT_BURST_COUNT = 14                  -- bigger landing burst than a normal orb
local CRIT_IMPACT_BURST_LIFETIME = 0.5
local CRIT_LABEL_ENABLED = true
local CRIT_LABEL_RISE = 0.09                        -- how far "CRIT!" floats up, in scale-units
local CRIT_LABEL_LIFETIME = 0.55

--------------------------------------------------------------------------
-- FX HELPERS
--------------------------------------------------------------------------

-- Resolve a flavor color for this essence type so glow/sparkles/bursts
-- read as "this orb's color" instead of generic white. Falls back
-- gracefully if EssenceTypes doesn't define a Color for this type.
local function GetOrbFXColor(EssenceType)
	local def = EssenceTypes[EssenceType]
	if def and def["Color"] then
		return def["Color"]
	end
	return Color3.fromRGB(255, 245, 200)
end

-- Soft radial glow, built the classic UI way: several stacked,
-- increasingly-transparent circles. Parented under the orb so it moves
-- and gets destroyed along with it automatically — caller just needs to
-- pulse its transparency/size per frame if they want it animated.
local function CreateOrbGlow(color, orbBaseSize)
	local mult = ORB_FX.GlowMaxSizeMult
	local holder = Instance.new("Frame")
	holder.Name = "FX_Glow"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.new(0.5, 0, 0.5, 0)
	holder.Size = UDim2.new(
		orbBaseSize.X.Scale * mult, orbBaseSize.X.Offset * mult,
		orbBaseSize.Y.Scale * mult, orbBaseSize.Y.Offset * mult
	)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.ZIndex = 0

	local layerCount = 4
	for i = 1, layerCount do
		local t = i / layerCount
		local disc = Instance.new("Frame")
		disc.Name = "GlowLayer"
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.new(0.5, 0, 0.5, 0)
		disc.Size = UDim2.new(t, 0, t, 0)
		disc.BackgroundColor3 = color
		disc.BackgroundTransparency = 1 - (1 - t) * 0.85
		disc.BorderSizePixel = 0
		disc.ZIndex = i

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = disc

		disc.Parent = holder
	end

	return holder
end

-- Nudges a glow holder's transparency in a smooth sine pulse. `baseAlpha`
-- is the "brightest" transparency (usually holder starts at 1 and this
-- eases it down); `speed` controls how fast the pulse breathes.
local function UpdateGlowPulse(glowHolder, elapsed, speed, minAlphaMult)
	if not glowHolder or not glowHolder.Parent then
		return
	end
	local pulse = (math.sin(elapsed * speed) + 1) / 2 -- 0..1
	local alphaMult = minAlphaMult + (1 - minAlphaMult) * pulse
	for _, disc in ipairs(glowHolder:GetChildren()) do
		if disc:IsA("Frame") then
			local baseTransparency = disc:GetAttribute("BaseTransparency")
			if baseTransparency == nil then
				baseTransparency = disc.BackgroundTransparency
				disc:SetAttribute("BaseTransparency", baseTransparency)
			end
			-- Blend toward fully transparent based on the inverse pulse so
			-- higher alphaMult = more visible glow.
			disc.BackgroundTransparency = 1 - ((1 - baseTransparency) * alphaMult)
		end
	end
end

-- Spawns one fading "ghost" copy of the orb's icon at its current
-- position, then tweens it down to nothing and destroys itself. Totally
-- self-contained — fire and forget, no connection bookkeeping needed.
local function SpawnTrailGhost(sourceImageLabel, position, size, zIndex, parent)
	if not ORB_FX.TrailEnabled then
		return
	end

	local ghost = Instance.new("ImageLabel")
	ghost.Name = "FX_TrailGhost"
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Position = position
	ghost.Size = size
	ghost.Image = sourceImageLabel.Image
	ghost.ImageColor3 = sourceImageLabel.ImageColor3
	ghost.BackgroundTransparency = 1
	ghost.ImageTransparency = ORB_FX.TrailStartTransparency
	ghost.ZIndex = math.max(zIndex - 1, 1)
	ghost.Parent = parent

	local shrunkSize = UDim2.new(
		size.X.Scale * ORB_FX.TrailShrinkTo, size.X.Offset * ORB_FX.TrailShrinkTo,
		size.Y.Scale * ORB_FX.TrailShrinkTo, size.Y.Offset * ORB_FX.TrailShrinkTo
	)

	local tween = TweenService:Create(
		ghost,
		TweenInfo.new(ORB_FX.TrailLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ ImageTransparency = 1, Size = shrunkSize }
	)
	tween:Play()
	tween.Completed:Connect(function()
		ghost:Destroy()
	end)
end

-- Small outward-flying circle burst at a given position, for landing
-- impacts and the "arrived home" poof. Self-cleaning, no external state.
local function SpawnImpactBurst(position, color, parent, count, lifetime)
	if not ORB_FX.ImpactBurstEnabled then
		return
	end
	count = count or ORB_FX.ImpactBurstCount
	lifetime = lifetime or ORB_FX.ImpactBurstLifetime

	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + (math.random() * 0.6 - 0.3)
		local distance = 0.03 + math.random() * 0.035

		local particle = Instance.new("Frame")
		particle.Name = "FX_ImpactParticle"
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = position
		particle.Size = UDim2.new(0, 5 + math.random() * 4, 0, 5 + math.random() * 4)
		particle.BackgroundColor3 = color
		particle.BackgroundTransparency = 0.1
		particle.BorderSizePixel = 0
		particle.ZIndex = 60
		particle.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = particle

		local targetPosition = UDim2.new(
			position.X.Scale + math.cos(angle) * distance, 0,
			position.Y.Scale + math.sin(angle) * distance, 0
		)

		local moveTween = TweenService:Create(
			particle,
			TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition, BackgroundTransparency = 1, Size = UDim2.new(0, 1, 0, 1) }
		)
		moveTween:Play()
		moveTween.Completed:Connect(function()
			particle:Destroy()
		end)
	end
end

-- Expanding, fading ring at the landing spot — same "punch" as a shockwave
-- but scaled down to fit a single UI orb instead of the whole screen.
local function SpawnImpactRing(position, color, parent)
	if not ORB_FX.ImpactRingEnabled then
		return
	end

	local ring = Instance.new("Frame")
	ring.Name = "FX_ImpactRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = position
	ring.Size = UDim2.new(0, 6, 0, 6)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 55
	ring.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = color
	stroke.Transparency = 0.5
	stroke.Parent = ring

	local lifetime = ORB_FX.ImpactRingLifetime
	local sizeTween = TweenService:Create(
		ring,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0, 70, 0, 70) }
	)
	local strokeTween = TweenService:Create(
		stroke,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 1, Thickness = 0.5 }
	)

	sizeTween:Play()
	strokeTween:Play()
	sizeTween.Completed:Connect(function()
		ring:Destroy()
	end)
end

-- Floating "CRIT!" text that pops at the landing spot and drifts upward
-- while fading out. Purely cosmetic, self-cleaning — fire and forget.
local function SpawnCritLabel(position, parent)
	if not CRIT_LABEL_ENABLED then
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "FX_CritLabel"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = UDim2.new(0, 90, 0, 30)
	label.BackgroundTransparency = 1
	label.Text = "CRIT!"
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = CRIT_COLOR
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(80, 50, 0)
	label.ZIndex = 65
	label.Rotation = math.random(-8, 8)
	label.Parent = parent

	local targetPosition = UDim2.new(
		position.X.Scale, 0,
		position.Y.Scale - CRIT_LABEL_RISE, 0
	)

	local tween = TweenService:Create(
		label,
		TweenInfo.new(CRIT_LABEL_LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = targetPosition, TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		label:Destroy()
	end)
end

-- Quick squash (wide+short) then spring back to normal, applied on top of
-- whatever size the orb is already tweening toward. Purely cosmetic, runs
-- as its own short tween sequence so it never fights the main size tween
-- long-term (it converges back to `finalSize` at the end).
local function ApplySquashStretch(orbInstance, finalSize)
	if not ORB_FX.SquashStretchEnabled then
		return
	end

	local amount = ORB_FX.SquashAmount
	local squashSize = UDim2.new(
		finalSize.X.Scale * (1 + amount), finalSize.X.Offset * (1 + amount),
		finalSize.Y.Scale * (1 - amount * 0.7), finalSize.Y.Offset * (1 - amount * 0.7)
	)

	local squashTween = TweenService:Create(
		orbInstance,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = squashSize }
	)
	squashTween:Play()
	squashTween.Completed:Connect(function()
		if not orbInstance or not orbInstance.Parent then
			return
		end
		local recoverTween = TweenService:Create(
			orbInstance,
			TweenInfo.new(ORB_FX.SquashRecoverTime, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
			{ Size = finalSize }
		)
		recoverTween:Play()
	end)
end

-- Builds N tiny sparkle dots parented under the orb, each carrying its own
-- randomized phase/speed/radius multiplier so the caller can spin them
-- around the orb every frame during the idle phase. Returns a plain array
-- of { Instance, Phase, SpeedMult } tables.
local function CreateIdleSparkles(color, parent, count)
	if not ORB_FX.IdleSparkleRingEnabled then
		return {}
	end
	count = count or ORB_FX.IdleSparkleCount

	local sparkles = {}
	for i = 1, count do
		local dot = Instance.new("Frame")
		dot.Name = "FX_IdleSparkle"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.new(0, ORB_FX.IdleSparkleSize, 0, ORB_FX.IdleSparkleSize)
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = 0.2
		dot.BorderSizePixel = 0
		dot.ZIndex = 52
		dot.Rotation = 45
		dot.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = dot

		sparkles[i] = {
			Instance = dot,
			Phase = (i / count) * math.pi * 2,
			SpeedMult = 0.85 + math.random() * 0.3,
		}
	end
	return sparkles
end
-- Adds a slow-sweeping color shimmer over an ImageLabel by animating a
-- UIGradient's Offset back and forth. Returns the gradient so the caller
-- can drive it every frame; leaves the image's own color untouched since
-- the gradient blends over top rather than replacing ImageColor3.
local function CreateShimmerGradient(imageLabel)
	if not ORB_FX.ShimmerEnabled then
		return nil
	end

	local gradient = Instance.new("UIGradient")
	gradient.Name = "FX_Shimmer"
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 240, 200)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.15),
		NumberSequenceKeypoint.new(1, 0.55),
	})
	gradient.Parent = imageLabel
	return gradient
end

--------------------------------------------------------------------------
-- MAIN FUNCTION — original logic below is unchanged; FX hooks are marked.
--------------------------------------------------------------------------

-- Distinct fragment icon so it's instantly readable as "not a real orb"
-- even before checking size/color. Replace with your actual fragment asset id.
local FRAGMENT_ICON_ID = 76509516254911 -- TODO: put your fragment image asset id here

local PopSounds = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("OrbPops")
PopSounds:WaitForChild("Pop1")
PopSounds:WaitForChild("Pop2")
PopSounds:WaitForChild("Pop3")
local function SpawnOrb(EssenceType, isFragment)
	local Orb = Template:Clone()
	Orb.Name = EssenceTypes[EssenceType]["Name"]
	Orb.MainClickable.Image = isFragment
		and ("rbxassetid://" .. FRAGMENT_ICON_ID)
		or ("rbxassetid://" .. EssenceTypes[EssenceType]["Icon"])

	-- 1. Setup starting state (Centered and tiny)
	Orb.Parent = EssenceParent
	Orb.AnchorPoint = Vector2.new(0.5, 0.5)
	Orb.Position = UDim2.new(0.5, 0, 0.5, 0)
	Orb.Rotation = 0
	Orb:SetAttribute("Collectable",false)
	Orb:SetAttribute("OrbType", EssenceTypes[EssenceType]["Name"])
	Orb:SetAttribute("Collectible",false) -- CollectionRing.lua's ring watches THIS attribute
	Orb:SetAttribute("IsFragment", isFragment or false)
	local v = 1
	if isFragment then
		v = FRAGMENT_VALUE_MULT
	end
	local power = player:GetAttribute("root_awakening") or 0
	v *= (2^power)

	Orb:SetAttribute("EssenceValue", v )
	-- === CRIT ROLL ===
	-- Fragments never roll: shatter_force can spawn a burst of many
	-- fragments per click, and letting each one consume a
	-- guaranteed_crit_streak tick would blow through the streak on
	-- fragment spam instead of on real orbs. Only real orbs roll.
	-- This is the "convenience flag" half of CriticalsController -- the
	-- actual payout comes from GetCritMultiplier, called server-side off
	-- this same attribute once collection fires (see EssenceMultiplier.lua).
	local isCrit = not isFragment and Criticals.RollCrit(player) or false
	Orb:SetAttribute("IsCrit", isCrit)

	-- === FX: resolve this orb's flavor color once, reused everywhere below ===
	-- Fragments skip all FX entirely (no glow/trail/shimmer/sparkles/bursts) -
	-- they're spawned in bulk by shatter_force, so keeping them cheap matters
	-- more than making them pretty. Crits override the essence-type color
	-- with CRIT_COLOR so every crit reads the same unmistakable gold.
	local fxColor = not isFragment and (isCrit and CRIT_COLOR or GetOrbFXColor(EssenceType)) or nil

	-- === DEPTH / VARIATION SETUP ===
	local depth = math.random()
	local sizeVarianceAmount = 0.10 + (math.random() * 0.10) -- 10-20%
	local sizeVarianceSign = math.random() < 0.5 and 1 or -1
	local sizeVariance = 1 + (sizeVarianceAmount * sizeVarianceSign)
	local depthScale = 1 - (depth * 0.25) -- far orbs read up to 25% smaller (parallax)
	local totalSizeMult = sizeVariance * depthScale
	if isFragment then
		totalSizeMult *= FRAGMENT_SIZE_MULT
	end
	if isCrit then
		totalSizeMult *= CRIT_SIZE_MULT
	end

	local baseFinalSize = Orb.Size
	local finalSize = UDim2.new(
		baseFinalSize.X.Scale * totalSizeMult, baseFinalSize.X.Offset * totalSizeMult,
		baseFinalSize.Y.Scale * totalSizeMult, baseFinalSize.Y.Offset * totalSizeMult
	)

	local baseTransparency = Orb.MainClickable.ImageTransparency
	local targetTransparency = math.clamp(
		baseTransparency + (depth * 0.35) + (isFragment and FRAGMENT_EXTRA_TRANSPARENCY or 0),
		0, 0.85
	)

	Orb.ZIndex = 50 - math.floor(depth * 9)

	Orb.Size = UDim2.new(0, 0, 0, 0)
	Orb.MainClickable.ImageTransparency = 1 -- fade in from invisible

	-- === FX: glow + shimmer — skipped entirely for fragments ===
	if isFragment then
		Orb.Shadow:Destroy()
	end

	local fxGlow
	if not isFragment and ORB_FX.GlowEnabled then
		fxGlow = CreateOrbGlow(fxColor, finalSize)
		fxGlow.Parent = Orb
		fxGlow.ZIndex = 0
		if isCrit then
			-- boost the glow further for crits without mutating the shared
			-- ORB_FX table (that'd affect every other orb too)
			local boost = 1 + CRIT_GLOW_SIZE_MULT_BONUS
			fxGlow.Size = UDim2.new(
				fxGlow.Size.X.Scale * boost, fxGlow.Size.X.Offset * boost,
				fxGlow.Size.Y.Scale * boost, fxGlow.Size.Y.Offset * boost
			)
		end
	end
	local fxShimmerGradient = not isFragment and CreateShimmerGradient(Orb.MainClickable) or nil

	-- 2. Calculate target (landing) position
	local minX, maxX = -0.65, 1.65
	local minY, maxY = -.15, 1.8
	local exclusionRadius = 0.45

	local targetX, targetY
	repeat
		targetX = minX + math.random() * (maxX - minX)
		targetY = minY + math.random() * (maxY - minY)
	until (targetX - 0.5)^2 + (targetY - 0.5)^2 >= exclusionRadius^2

	local landingAbove = targetY < 0.55

	-- 3. Physics & Animation Variables
	local currentX = 0.5
	local currentY = 0.5
	local velocityY = -0.025 - (math.random() * 0.015)
	local gravity = 0.0018
	local bounceElasticity = -0.55

	TweenService:Create(Orb, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = finalSize}):Play()
	TweenService:Create(Orb.MainClickable, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency = targetTransparency}):Play()

	-- === IDLE ORBIT SETTINGS ===
	local orbitRadiusX = (0.03 + math.random() * 0.02) * depthScale
	local orbitRadiusY = orbitRadiusX * (0.5 + math.random() * 0.3)
	local orbitSpeed = (0.75 + math.random() * 0.6) * (1 - depth * 0.3)
	local orbitDirection = math.random() < 0.5 and 1 or -1
	local orbitAngleOffset = math.random() * math.pi * 2

	local bobAmplitude = 0.01 + math.random() * 0.01
	local bobSpeed = 1.0 + math.random() * 1.5

	local rotationSpeed = (math.random() * 20 - 10)

	local orbitDuration = 2 + math.random() * 2
	local returnDuration = 2 + math.random()

	-- === FX: idle sparkle ring — skipped for fragments; crits get a couple extra sparkles ===
	local fxIdleSparkles = not isFragment
		and CreateIdleSparkles(fxColor, Orb, isCrit and (ORB_FX.IdleSparkleCount + 2) or ORB_FX.IdleSparkleCount)
		or {}
	local fxTrailTimer = 0
	local fxHasPlayedImpact = false

	-- 4. The Physics/Motion Loop
	local connection
	local startTime = os.clock()
	local durationX = 0.8
	local settled = false
	local settleTime = nil

	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not Orb or not Orb.Parent or Orb:GetAttribute("Bail") then
			connection:Disconnect()
			return
		end

		local elapsed = os.clock() - startTime

		if not settled then
			local alpha = math.min(elapsed / durationX, 1)
			local easedAlpha = 1 - (1 - alpha) * (1 - alpha)
			currentX = 0.5 + (targetX - 0.5) * easedAlpha

			if landingAbove then
				local yAlpha = math.min(elapsed / durationX, 1)
				if yAlpha >= 1 then
					currentY = targetY
					settled = true
					settleTime = os.clock()
					local sound = PopSounds["Pop"..tostring(math.random(1,3))]
					sound:Play()
					Orb:SetAttribute("Collectible", true)
				else
					local c1, c3 = 1.70158, 2.70158
					local backAlpha = 1 + c3 * (yAlpha - 1)^3 + c1 * (yAlpha - 1)^2
					currentY = 0.5 + (targetY - 0.5) * backAlpha
				end
			else
				velocityY = velocityY + (gravity * (deltaTime * 60))
				currentY = currentY + velocityY

				if currentY >= targetY then
					currentY = targetY
					velocityY = velocityY * bounceElasticity

					if math.abs(velocityY) < 0.002 and alpha >= 1 then
						settled = true
						settleTime = os.clock()
						local sound = PopSounds["Pop"..tostring(math.random(1,3))]
						sound:Play()
						Orb:SetAttribute("Collectible", true)
					end
				end
			end

			Orb.Position = UDim2.new(currentX, 0, currentY, 0)

			-- === FX: trail ghosts — skipped for fragments ===
			if not isFragment and ORB_FX.TrailEnabled then
				fxTrailTimer = fxTrailTimer + deltaTime
				if fxTrailTimer >= ORB_FX.TrailSpawnInterval then
					fxTrailTimer = 0
					SpawnTrailGhost(Orb.MainClickable, Orb.Position, Orb.Size, Orb.ZIndex, EssenceParent)
				end
			end

			if fxGlow then
				UpdateGlowPulse(fxGlow, elapsed, ORB_FX.GlowPulseSpeed * (isCrit and CRIT_GLOW_PULSE_SPEED_MULT or 1), ORB_FX.GlowMinAlphaMult)
			end

			-- === FX: landing impact — skipped for fragments; crits get a bigger burst + a "CRIT!" label ===
			if not isFragment and settled and not fxHasPlayedImpact then
				fxHasPlayedImpact = true
				ApplySquashStretch(Orb, finalSize)
				if isCrit then
					SpawnImpactBurst(Orb.Position, fxColor, EssenceParent, CRIT_IMPACT_BURST_COUNT, CRIT_IMPACT_BURST_LIFETIME)
					SpawnImpactRing(Orb.Position, fxColor, EssenceParent)
					SpawnCritLabel(Orb.Position, EssenceParent)
				else
					SpawnImpactBurst(Orb.Position, fxColor, EssenceParent)
					SpawnImpactRing(Orb.Position, fxColor, EssenceParent)
				end
			end
		else
			-- C. Idle phase: gentle orbit + bob + rotation around the landing spot

			local magnetStrength = CollectionUpgrades.GetMagnetStrength(player)
			if magnetStrength > 0 then
				local mouseX, mouseY = getMouseInContainerScale(EssenceParent)

				local guiInset = GuiService:GetGuiInset()
				local containerHeight = EssenceParent.AbsoluteSize.Y
				if containerHeight > 0 then
					mouseY = mouseY - (guiInset.Y / containerHeight)
				end

				local pullAlpha = math.min(magnetStrength * MAGNET_PULL_COEFFICIENT * deltaTime, 1)

				targetX = targetX + (mouseX - targetX) * pullAlpha
				targetY = targetY + (mouseY - targetY) * pullAlpha
			end

			local orbitElapsed = os.clock() - settleTime

			if orbitElapsed >= orbitDuration then
				Orb:SetAttribute("Collectible",false)
				connection:Disconnect()

				-- === FX: return glow flicker — skipped for fragments ===
				if not isFragment and ORB_FX.ReturnStreakEnabled and fxGlow then
					TweenService:Create(
						fxGlow,
						TweenInfo.new(returnDuration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ Size = UDim2.new(0, 0, 0, 0) }
					):Play()
				end

				local returnTween = TweenService:Create(
					Orb,
					TweenInfo.new(returnDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 0)}
				)
				local fadeTween = TweenService:Create(
					Orb.MainClickable,
					TweenInfo.new(returnDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ImageTransparency = 1}
				)

				returnTween:Play()
				fadeTween:Play()

				returnTween.Completed:Connect(function()
					returnEvent:FireServer(1)

					-- === FX: arrival poof — skipped for fragments ===
					if not isFragment and ORB_FX.ReturnPoofEnabled then
						SpawnImpactBurst(
							UDim2.new(0.5, 0, 0.5, 0),
							fxColor,
							EssenceParent,
							ORB_FX.ReturnPoofCount,
							ORB_FX.ImpactBurstLifetime
						)
					end

					if Orb then
						Orb:Destroy()
					end

					popTween:Play()
				end)

				return
			end

			local orbitAngle = orbitAngleOffset + (orbitElapsed * orbitSpeed * orbitDirection)
			local orbitX = math.cos(orbitAngle) * orbitRadiusX
			local orbitY = math.sin(orbitAngle) * orbitRadiusY
			local bobY = math.sin(orbitElapsed * bobSpeed) * bobAmplitude

			Orb.Position = UDim2.new(targetX + orbitX, 0, targetY + orbitY + bobY, 0)
			Orb.Rotation = orbitElapsed * rotationSpeed

			if fxGlow then
				UpdateGlowPulse(fxGlow, elapsed, ORB_FX.GlowIdlePulseSpeed * (isCrit and CRIT_GLOW_PULSE_SPEED_MULT or 1), ORB_FX.GlowMinAlphaMult)
			end

			-- === FX: shimmer sweep — skipped for fragments ===
			if fxShimmerGradient then
				local shimmerT = (orbitElapsed * ORB_FX.ShimmerCycleSpeed) % 1
				local shimmerOffset = -1 + (shimmerT * 2)
				fxShimmerGradient.Offset = Vector2.new(shimmerOffset, 0)
			end

			-- === FX: idle sparkle ring — skipped for fragments (fxIdleSparkles is {}) ===
			if not isFragment and ORB_FX.IdleSparkleRingEnabled then
				for _, sparkle in ipairs(fxIdleSparkles) do
					local sparkleAngle = sparkle.Phase + (orbitElapsed * orbitSpeed * ORB_FX.IdleSparkleOrbitSpeedMult * sparkle.SpeedMult * orbitDirection)
					local sparkleRadiusX = orbitRadiusX * ORB_FX.IdleSparkleRadiusMult
					local sparkleRadiusY = orbitRadiusY * ORB_FX.IdleSparkleRadiusMult
					local sx = math.cos(sparkleAngle) * sparkleRadiusX
					local sy = math.sin(sparkleAngle) * sparkleRadiusY
					sparkle.Instance.Position = UDim2.new(0.5, sx * Orb.AbsoluteSize.X, 0.5, sy * Orb.AbsoluteSize.Y)
					sparkle.Instance.Rotation = 45 + (orbitElapsed * 90 * sparkle.SpeedMult)
				end
			end
		end
	end)
end


-- =========================================================================
-- ORB HP (server-authoritative via OrbController -> player Attributes)
-- =========================================================================

local bar = LP:WaitForChild("Healthbar"):WaitForChild("Healthbar")

local function updateHealthBar()
	local currentHP = player:GetAttribute("OrbCurrentHP")
	local maxHP = player:GetAttribute("OrbMaxHP")

	if currentHP == nil or maxHP == nil or maxHP <= 0 then
		return
	end

	local targetScale = currentHP / maxHP
	bar.Size = UDim2.new(math.clamp(targetScale, 0, 1), 0, 1, 0)
end

player:GetAttributeChangedSignal("OrbCurrentHP"):Connect(updateHealthBar)
player:GetAttributeChangedSignal("OrbMaxHP"):Connect(updateHealthBar)

task.spawn(function()
	if player:GetAttribute("OrbMaxHP") == nil then
		player:GetAttributeChangedSignal("OrbMaxHP"):Wait()
	end
	updateHealthBar()
end)

local deniedColor = Color3.fromRGB(255, 90, 90)
local originalOrbColor = Color3.fromRGB(255,255,255) -- adjust if color lives elsewhere on LargeOrb

-- Throttles the explanatory text so hammering a depleted orb doesn't
-- stack a dozen overlapping labels.
local lastDeniedMessageAt = 0

local function FlashDenied()
	local flashTween = TweenService:Create(LargeOrb, TweenInfo.new(0.08), {ImageColor3 = deniedColor})
	flashTween:Play()
	flashTween.Completed:Connect(function()
		TweenService:Create(LargeOrb, TweenInfo.new(0.15), {ImageColor3 = originalOrbColor}):Play()
	end)

	-- A bare colour flash reads as "this is broken" rather than "this is a
	-- mechanic". The shake gives the refusal weight, and pointing the
	-- player at the energy bar tells them what to do about it -- this was
	-- the single most confusing moment in the early game.
	Juice.Shake(Center, 7, 0.22)

	if bar then
		Juice.PulseBackground(bar, Color3.fromRGB(255, 120, 120), 0.45)
		Juice.Punch(Juice.GetScale(bar.Parent), 0.12, 0.25)
	end

	local now = os.clock()
	if (now - lastDeniedMessageAt) > 1.6 then
		lastDeniedMessageAt = now

		if clickSound then
			-- Dropped well below the normal click pitch so a refusal is
			-- instantly distinguishable by ear alone.
			Juice.PlaySound(clickSound, { Pitch = 0.55, Volume = 0.4 })
		end

		local center = Juice.CenterOf(LargeOrb, juiceLayer)
		if center then
			Juice.FloatText(juiceLayer, center, "Recharging!", {
				Color = Color3.fromRGB(255, 140, 140),
				Duration = 1,
				Rise = 60,
				TextSize = 28,
			})
		end
	end
end

LargeOrbButton.Activated:Connect(function()
	local currentHP = player:GetAttribute("OrbCurrentHP") or 0
	local shotHPCost = player:GetAttribute("OrbShotHPCost") or 0

	if not CanSpawnOrb() then
		return
	end

	if currentHP >= shotHPCost or currentHP <= 0 then
		-- Immediate click feedback, every successful click. Scale is left
		-- to HoverClickTween here (see CLICK FEEL note above) so its
		-- press-squish stays visible instead of being overridden.
		OrbClickJuice(false)

		ClickOrbEvent:FireServer()

		local baseOrbCount = 1
		-- shatter_force_1/2: fragments, not full orbs
		local fragmentCount = GetSummedEffectFromAttributes(player, "OrbsPerClick")

		-- overload_shots: chance to double the fragment burst this click
		local overloadChance = GetSummedEffectFromAttributes(player, "OverloadWaveChance")
		if overloadChance > 0 and math.random() < overloadChance then
			fragmentCount = fragmentCount * 2
		end

		-- twin_orb_manifestation: doubles everything this click produces
		if (player:GetAttribute("twin_orb_manifestation") or 0) >= 1 then
			baseOrbCount *= 2
		end

		baseOrbCount = math.floor(baseOrbCount + 0.5)
		fragmentCount = math.floor(fragmentCount + 0.5)

		for i = 1, baseOrbCount do
			if not CanSpawnOrb() then break end
			if i == 1 then
				SpawnOrb(GetEssenceModule.GetRandomEssence(player), false)
			else
				task.delay((i - 1) * 0.05, function()
					if CanSpawnOrb() then SpawnOrb(GetEssenceModule.GetRandomEssence(player), false) end
				end)
			end
		end

		for i = 1, fragmentCount do
			task.delay(i * 0.035, function()
				if CanSpawnOrb() then SpawnOrb(GetEssenceModule.GetRandomEssence(player), true) end
			end)
		end
	else
		-- click was blocked by HP — tell the player clearly, don't fail silently
		FlashDenied()
	end
end)

task.spawn(function()
	while true do
		local waitTime = math.random(5,25)/10
		task.wait(waitTime)
		if player:GetAttribute("automation_core") then
			if not CanSpawnOrb() then
				continue
			end
			local currentHP = player:GetAttribute("OrbCurrentHP") or 0
			local shotHPCost = player:GetAttribute("OrbShotHPCost") or 0
			local hasCoreResilience = (player:GetAttribute("core_resilience") or 0) >= 1
			if currentHP >= shotHPCost or (currentHP > 0 and hasCoreResilience) then
				-- Automation fires no mouse events, so popTween is the only
				-- thing that moves the orb here -- kept for that reason.
				popTween:Play()
				OrbClickJuice(true)
				ClickOrbEvent:FireServer()
				local baseOrbCount = 1
				-- shatter_force_1/2: fragments, not full orbs
				local fragmentCount = GetSummedEffectFromAttributes(player, "OrbsPerClick")
				-- overload_shots: chance to double the fragment burst this click
				local overloadChance = GetSummedEffectFromAttributes(player, "OverloadWaveChance")
				if overloadChance > 0 and math.random() < overloadChance then
					fragmentCount = fragmentCount * 2
				end
				-- twin_orb_manifestation: doubles everything this click produces
				if (player:GetAttribute("twin_orb_manifestation") or 0) >= 1 then
					baseOrbCount *= 2
				end
				baseOrbCount = math.floor(baseOrbCount + 0.5)
				fragmentCount = math.floor(fragmentCount + 0.5)
				for i = 1, baseOrbCount do
					if not CanSpawnOrb() then break end
					if i == 1 then
						SpawnOrb(GetEssenceModule.GetRandomEssence(player), false)
					else
						task.delay((i - 1) * 0.05, function()
							if CanSpawnOrb() then SpawnOrb(GetEssenceModule.GetRandomEssence(player), false) end
						end)
					end
				end
				for i = 1, fragmentCount do
					task.delay(i * 0.035, function()
						if CanSpawnOrb() then SpawnOrb(GetEssenceModule.GetRandomEssence(player), true) end
					end)
				end
			else
				-- click was blocked by HP — tell the player clearly, don't fail silently
				FlashDenied()
			end
		end
	end
end)
--[[
    ESSENCE FALL EVENT
    ==================
    Orbs drift down at an angle from a band along the top of the screen,
    like gentle rain. Click one before it exits the bounds to collect it;
    if it drifts off-screen unclaimed, it just disappears - no reward.

    StartEssenceFallEvent yields for its whole duration, so it's always
    called with task.spawn (see the StormStart handler below) rather than
    directly.
]]

-- === FALL BEHAVIOR CONFIG ===
local FALL_AREA_MIN_X = -0.65   -- left edge of the spawn band
local FALL_AREA_MAX_X = 1.65    -- right edge of the spawn band
local FALL_SPAWN_Y = -0.3      -- just above the top edge, off-screen

local FALL_ANGLE_DEGREES = 20   -- overall drift off straight-down (positive = down-and-right)
local FALL_ANGLE_VARIANCE = 10  -- +/- random spread per orb, in degrees
local FALL_SPEED_MIN = 0.5     -- scale units per second
local FALL_SPEED_MAX = 0.8

local FALL_ROTATION_SPEED_MIN = -25 -- deg/sec
local FALL_ROTATION_SPEED_MAX = 25

local OUT_OF_BOUNDS_MARGIN = 1.5 -- how far past an edge before it's considered "gone"

-------------------------------------------------------------------
-- SPAWN A SINGLE FALLING, COLLECTIBLE ORB
-------------------------------------------------------------------
local function SpawnFallingOrb(EssenceType, isGolden)
	local Orb = Template:Clone()
	Orb.Name = EssenceTypes[EssenceType]["Name"]
	Orb.MainClickable.Image = "rbxassetid://" .. EssenceTypes[EssenceType]["Icon"]

	Orb.Parent = EssenceParent
	Orb.AnchorPoint = Vector2.new(0.5, 0.5)
	Orb.Rotation = math.random(0, 360)
	Orb:SetAttribute("Collectable", false)
	Orb:SetAttribute("Collectible", false) -- CollectionRing.lua's ring watches THIS attribute
	Orb:SetAttribute("IsGolden",isGolden)
Orb:SetAttribute("OrbType",EssenceType)
	-- === CRIT ROLL ===
	-- Falling storm orbs are "real" orbs same as a direct click (unlike
	-- shatter_force fragments), so they roll same as SpawnOrb's non-fragment
	-- path. See SpawnOrb above for why fragments are excluded.
	local isCrit = Criticals.RollCrit(player)
	Orb:SetAttribute("IsCrit", isCrit)

	-- a little size variance so a shower of orbs doesn't look uniform
	local sizeVariance = 0.85 + math.random() * 0.3 -- 85%-115%
	if isCrit then
		sizeVariance *= CRIT_SIZE_MULT
	end
	local baseSize = Orb.Size
	local finalSize = UDim2.new(
		baseSize.X.Scale * sizeVariance, baseSize.X.Offset * sizeVariance,
		baseSize.Y.Scale * sizeVariance, baseSize.Y.Offset * sizeVariance
	)

	-- starting point: random spot along the top band, just off-screen
	local currentX = FALL_AREA_MIN_X + math.random() * (FALL_AREA_MAX_X - FALL_AREA_MIN_X)
	local currentY = FALL_SPAWN_Y

	Orb.Position = UDim2.new(currentX, 0, currentY, 0)
	Orb.Size = UDim2.new(0, 0, 0, 0)
	Orb.MainClickable.ImageTransparency = 1

	-- === FX: crit tint + glow, so a crit is spottable mid-fall in a busy storm ===
	local fxGlow
	if isCrit then
		Orb.MainClickable.ImageColor3 = CRIT_COLOR
		if ORB_FX.GlowEnabled then
			fxGlow = CreateOrbGlow(CRIT_COLOR, finalSize)
			fxGlow.ZIndex = 0
			fxGlow.Parent = Orb
		end
	end

	-- fall direction: mostly downward, drifting sideways at an angle
	local angleDeg = FALL_ANGLE_DEGREES + (math.random() * FALL_ANGLE_VARIANCE * 2 - FALL_ANGLE_VARIANCE)
	local angleRad = math.rad(angleDeg)
	local speed = FALL_SPEED_MIN + math.random() * (FALL_SPEED_MAX - FALL_SPEED_MIN)
	local velocityX = math.sin(angleRad) * speed
	local velocityY = math.cos(angleRad) * speed
	local rotationSpeed = FALL_ROTATION_SPEED_MIN + math.random() * (FALL_ROTATION_SPEED_MAX - FALL_ROTATION_SPEED_MIN)

	-- pop in: scale + fade from nothing
	TweenService:Create(Orb, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = finalSize,
	}):Play()
	TweenService:Create(Orb.MainClickable, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 0,
	}):Play()

	-- only clickable once it's actually visible
	task.delay(0.3, function()
		if Orb and Orb.Parent then
			Orb:SetAttribute("Collectable", true)
			Orb:SetAttribute("Collectible", true)
		end
	end)

	-- === COLLECTION ===
	local collected = false
	local connection
	local startTime = os.clock()

	-- === FALL MOTION ===
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if collected or not Orb or not Orb.Parent or Orb:GetAttribute("Bail") then
			if connection then
				connection:Disconnect()
			end
			return
		end

		-- magnetic_pull_1/2: falling orbs curve toward the cursor instead of
		-- falling in a dead-straight line, same source of truth as the
		-- idle-orbit pull above.
		--
		-- This STEERS velocity toward the cursor (reorienting the existing
		-- speed) rather than just adding acceleration on top of it. Adding
		-- acceleration alone let the orb's downward fall momentum dominate,
		-- so it would curve slightly but still sail through underneath the
		-- cursor instead of actually aiming at it.
		local magnetStrength = CollectionUpgrades.GetMagnetStrength(player)
		if magnetStrength > 0 then
			local mouseX, mouseY = getMouseInContainerScale(EssenceParent)
			local dx = mouseX - currentX
			local dy = mouseY - currentY
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist > 0.001 then
				local speed = math.sqrt(velocityX * velocityX + velocityY * velocityY)
				local desiredVelX = (dx / dist) * speed
				local desiredVelY = (dy / dist) * speed
				local steerAlpha = math.clamp(magnetStrength * MAGNET_PULL_COEFFICIENT * deltaTime, 0, 1)
				velocityX = velocityX + (desiredVelX - velocityX) * steerAlpha
				velocityY = velocityY + (desiredVelY - velocityY) * steerAlpha
			end
		end

		currentX = currentX + velocityX * deltaTime
		currentY = currentY + velocityY * deltaTime
		Orb.Position = UDim2.new(currentX, 0, currentY, 0)
		Orb.Rotation = Orb.Rotation + rotationSpeed * deltaTime

		-- === FX: crit glow pulse while falling ===
		if fxGlow then
			UpdateGlowPulse(fxGlow, os.clock() - startTime, ORB_FX.GlowPulseSpeed * CRIT_GLOW_PULSE_SPEED_MULT, ORB_FX.GlowMinAlphaMult)
		end

		-- missed: drifted past the bottom or either side, unclaimed
		if currentY > 1 + OUT_OF_BOUNDS_MARGIN
			or currentX < -OUT_OF_BOUNDS_MARGIN
			or currentX > 1 + OUT_OF_BOUNDS_MARGIN then
			connection:Disconnect()
			Orb:SetAttribute("Collectable", false)
			Orb:SetAttribute("Collectible", false)
			Orb:Destroy()
		end
	end)
end

-------------------------------------------------------------------
-- RUN A TIMED SHOWER OF FALLING ORBS
-------------------------------------------------------------------
-- Yields for the full duration - call with task.spawn(StartEssenceFallEvent, ...)
local function StartEssenceFallEvent(duration, spawnInterval, essenceTypePool, isGolden)
	spawnInterval = spawnInterval or 0.4

	local typeKeys = essenceTypePool
	if not typeKeys then
		typeKeys = {}
		for key in pairs(EssenceTypes) do
			table.insert(typeKeys, key)
		end
	end

	if #typeKeys == 0 then
		warn("StartEssenceFallEvent: no essence types available to spawn")
		return
	end

	local elapsed = 0
	while elapsed < duration do
		local waitTime = spawnInterval * (0.7 + math.random() * 0.6) -- a little variance so it isn't metronomic
		task.wait(waitTime)
		elapsed = elapsed + waitTime

		-- overflow_capacity: skip this tick's spawn if the screen's already
		-- at the active-orb cap, rather than spawning over it.
		if CanSpawnOrb() then
			local randomType = typeKeys[math.random(1, #typeKeys)]
			SpawnFallingOrb(randomType, isGolden)
		end
	end
end

---------------------------------------------------------
-- ESSENCE STORM UI + CLIENT REACTION
-- ------------------------------------------------------
-- All storm timing/gating now lives server-side in StormController, which
-- accounts for StormCooldownReduction / StormDuration / StormIntensity /
-- GoldenStormChance / manual_storm_summon / AutoStormChancePerMinute from
-- EssenceUpgrades and mirrors the results onto these player Attributes:
--   StormCooldownRemaining, StormActive, StormTimeRemaining, StormIsGolden,
--   ManualStormUnlocked, ManualStormCooldownRemaining
-- plus fires ("StormStart", {Duration, IsGolden, SpawnInterval}) /
-- ("StormEnd") over the EssenceStorm RemoteEvent. This script only reads
-- those and drives the visuals + the actual SpawnFallingOrb calls locally -
-- it no longer runs its own cooldown timer.
---------------------------------------------------------

local mainFrame = cloneables:WaitForChild("StormFrame")
mainFrame.Parent = MainGui
local fillBar = mainFrame:WaitForChild("FillBar")
local fillGlow = fillBar:WaitForChild("FillGlow")
fillGlow.Rotation = 90

local timerText = mainFrame:WaitForChild("TimerText")

-- Optional: a manual-summon button. Only shown/wired if it exists in the
-- StormFrame AND the player owns manual_storm_summon (ManualStormUnlocked).
local manualSummonButton = MainGui:WaitForChild("Right"):FindFirstChild("ManualSummonButton")

local function formatTime(seconds)
	seconds = math.max(seconds, 0)
	local minutes = math.floor(seconds / 60)
	local remSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remSeconds)
end

local waitingColor = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(211, 84, 0)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 126, 34))
})

local activeColor = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 139, 34)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 205, 50))
})

-- storm_mastery: a golden storm gets its own gradient so it visibly reads
-- as the bigger payout it is.
local goldenColor = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(184, 134, 11)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 0))
})

local function updateUI(scale, colorSeq, text)
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
	TweenService:Create(fillBar, tweenInfo, {Size = UDim2.fromScale(scale, 1)}):Play()
	fillGlow.Color = colorSeq
	timerText.Text = text
end

-- We don't know this player's actual max cooldown client-side (it depends
-- on server-side upgrade levels), so the waiting bar's fill is only an
-- estimate against the unupgraded base. Mirror StormMaxCooldown as its own
-- attribute from StormController if you want an exact fill percentage.
local ESTIMATED_MAX_COOLDOWN = 300
local currentEventThread = nil

local function refreshWaitingUI()
	if player:GetAttribute("StormActive") then return end
	local cooldownRemaining = player:GetAttribute("StormCooldownRemaining") or 0
	local displayScale = math.clamp(cooldownRemaining / ESTIMATED_MAX_COOLDOWN, 0, 1)
	updateUI(displayScale, waitingColor, "Next Essence Storm: " .. formatTime(cooldownRemaining))
end

local function refreshActiveUI()
	local timeRemaining = player:GetAttribute("StormTimeRemaining") or 0
	local isGolden = player:GetAttribute("StormIsGolden")
	local scale = math.clamp(timeRemaining / ESTIMATED_MAX_COOLDOWN, 0, 1)
	local label = isGolden
		and ("\u{2728} GOLDEN ESSENCE STORM: " .. formatTime(timeRemaining))
		or ("\u{26A0}\u{FE0F} EARTH STORM ACTIVE: " .. formatTime(timeRemaining))
	updateUI(scale, isGolden and goldenColor or activeColor, label)
end

local function refreshManualButton()

	if not manualSummonButton then return end
	local unlocked = player:GetAttribute("ManualStormUnlocked")
	local cooldownRemaining = player:GetAttribute("ManualStormCooldownRemaining") or 0
	manualSummonButton.Visible = unlocked and true or false
	manualSummonButton.Active = unlocked and cooldownRemaining <= 0

end

player:GetAttributeChangedSignal("StormCooldownRemaining"):Connect(refreshWaitingUI)
player:GetAttributeChangedSignal("StormTimeRemaining"):Connect(refreshActiveUI)
player:GetAttributeChangedSignal("StormIsGolden"):Connect(refreshActiveUI)
player:GetAttributeChangedSignal("ManualStormUnlocked"):Connect(refreshManualButton)
player:GetAttributeChangedSignal("ManualStormCooldownRemaining"):Connect(refreshManualButton)

if manualSummonButton then
	manualSummonButton.Activated:Connect(function()
		Events:WaitForChild("ManualStormSummon"):FireServer()
	end)
end

local EssenceStormEvent = Events:WaitForChild("EssenceStorm")

EssenceStormEvent.OnClientEvent:Connect(function(action, payload)
	if action == "StormStart" then
		payload = payload or {}
		local duration = payload.Duration or 60
		local spawnInterval = payload.SpawnInterval or 0.4
		local IsGolden = payload.IsGolden or false
		refreshActiveUI()

		if currentEventThread then
			task.cancel(currentEventThread)
		end
		currentEventThread = task.spawn(function()
			StartEssenceFallEvent(duration, spawnInterval, {"Earth Essence","Shadow Essence"}, IsGolden)
		end)

	elseif action == "StormEnd" then
		if currentEventThread then
			task.cancel(currentEventThread)
			currentEventThread = nil
		end
		refreshWaitingUI()
	end
end)

-- mirrored (or wait for the first one if it hasn't run yet).
task.spawn(function()
	if player:GetAttribute("StormCooldownRemaining") == nil then
		player:GetAttributeChangedSignal("StormCooldownRemaining"):Wait()
	end
	refreshWaitingUI()
	refreshManualButton()
end)


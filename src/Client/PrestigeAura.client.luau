--[[
	PrestigeAura (LocalScript -> StarterPlayerScripts)
	===================================================
	A persistent, ambient visual around the great orb that grows more
	elaborate as the player reaches rebirth milestones -- wearing prestige
	rather than burying it in a stats panel.

	WHY THIS EXISTS
	-----------------
	Rebirths already unlock real content (RebirthHandler.luau's MILESTONES:
	new upgrade routes, the Prestige Shop, the Infinity Core...), but
	nothing about reaching one is ever VISIBLE after the moment it happens.
	A player who's rebirthed 30 times looks identical, at a glance, to one
	who's rebirthed once. Making status permanently visible -- not just a
	number you'd have to go check -- is one of the most reliable levers an
	incremental game has for making progress feel like it matters, and for
	giving other players something to notice and want for themselves.

	SOURCE OF TRUTH
	------------------
	Tier thresholds and names come from RebirthModule.GetMilestoneThresholds()
	/ GetMilestone() -- the exact same milestones that already gate real
	content -- rather than a second, hand-maintained copy of the numbers
	1/5/10/25/50 living in this file. If the milestones ever change, this
	follows automatically.

	WHAT THIS DOES NOT DO
	------------------------
	Purely a client-side visual. Reads the player's own Rebirths attribute
	(already server-authoritative, mirrored by PlayerDataHandler) and
	never grants, requests, or assumes anything the server hasn't already
	decided. Deleting this script changes nothing about the economy.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local RebirthModule = require(ReplicatedStorage:WaitForChild("RebirthHandler"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MainGui = playerGui:WaitForChild("MainGui")
local Center = MainGui:WaitForChild("Center")
local LargeOrbFolder = Center:WaitForChild("LargeOrbFolder")
local LargeOrb = LargeOrbFolder:WaitForChild("LargeOrb")

local juiceLayer = Juice.GetLayer(playerGui)

-- =========================================================================
-- TIER DEFINITIONS
-- =========================================================================
-- Keyed by the same rebirth counts RebirthModule.MILESTONES already uses.
-- LayerCount/Size scale the glow; ParticleCount adds an orbiting glyph
-- ring from Tier 3 up (Ascended and beyond feel like they've earned
-- something a plain glow can't sell on its own).

local TIER_STYLES = {
	[1]  = { Color = Color3.fromRGB(235, 235, 245), Layers = 3, SizeMult = 1.35, ParticleCount = 0, RotationSpeed = 0 },
	[5]  = { Color = Color3.fromRGB(90, 170, 255),  Layers = 4, SizeMult = 1.5,  ParticleCount = 0, RotationSpeed = 0 },
	[10] = { Color = Color3.fromRGB(170, 90, 255),  Layers = 5, SizeMult = 1.65, ParticleCount = 5, RotationSpeed = 0.15 },
	[25] = { Color = Color3.fromRGB(255, 130, 40),  Layers = 6, SizeMult = 1.8,  ParticleCount = 8, RotationSpeed = 0.3 },
	[50] = { Color = Color3.fromRGB(255, 215, 80),  Layers = 7, SizeMult = 2.0,  ParticleCount = 12, RotationSpeed = 0.5 },
}

local PARTICLE_GLYPHS = { "✦", "◆", "✧", "❖" }

-- =========================================================================
-- BUILD
-- =========================================================================
-- Parented as a sibling of LargeOrb inside LargeOrbFolder, so it shares
-- the exact same coordinate space and moves/scales with the orb for free
-- -- no per-frame position tracking needed. ZIndex 0, matching this
-- codebase's own CreateOrbGlow convention in OrbClicker.client.luau, so
-- it sits behind the orb rather than covering the clickable area.

-- AnchorPoint/Position are copied directly from LargeOrb itself rather
-- than assumed to be (0.5, 0.5) -- this repo's own Argon syncback doesn't
-- capture UI property values, so LargeOrb's real anchor convention isn't
-- actually knowable from here. Copying it guarantees auraHolder starts in
-- exactly the same rectangle as the orb, however it's really anchored,
-- and later scaling stays centered on the orb rather than drifting to one
-- side. (A one-time Juice.CenterOf snapshot was considered instead, but
-- that returns a pure pixel OFFSET -- it would silently drift out of
-- alignment on any screen resize, unlike every other UDim2 in this
-- codebase's UI, which is deliberately Scale-based for exactly that
-- reason.)
local auraHolder = Instance.new("Frame")
auraHolder.Name = "PrestigeAura"
auraHolder.AnchorPoint = LargeOrb.AnchorPoint
auraHolder.Position = LargeOrb.Position
auraHolder.Size = LargeOrb.Size
auraHolder.BackgroundTransparency = 1
auraHolder.BorderSizePixel = 0
auraHolder.ZIndex = 0
auraHolder.Visible = false
auraHolder.Parent = LargeOrbFolder

local glowDiscs = {}
local MAX_LAYERS = 7
for i = 1, MAX_LAYERS do
	local t = i / MAX_LAYERS
	local disc = Instance.new("Frame")
	disc.Name = "AuraLayer" .. i
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.new(0.5, 0, 0.5, 0)
	disc.Size = UDim2.new(t, 0, t, 0)
	disc.BackgroundTransparency = 1
	disc.BorderSizePixel = 0
	disc.ZIndex = i
	disc.Visible = false

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = disc

	disc.Parent = auraHolder
	glowDiscs[i] = disc
end

local particleRing = Instance.new("Frame")
particleRing.Name = "ParticleRing"
particleRing.AnchorPoint = Vector2.new(0.5, 0.5)
particleRing.Position = UDim2.new(0.5, 0, 0.5, 0)
particleRing.Size = UDim2.new(1, 0, 1, 0)
particleRing.BackgroundTransparency = 1
particleRing.ZIndex = MAX_LAYERS + 1
particleRing.Parent = auraHolder

local MAX_PARTICLES = 12
local particleLabels = {}
for i = 1, MAX_PARTICLES do
	local glyph = Instance.new("TextLabel")
	glyph.Name = "Particle" .. i
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Size = UDim2.fromOffset(14, 14)
	glyph.BackgroundTransparency = 1
	glyph.Font = Enum.Font.GothamBold
	glyph.Text = PARTICLE_GLYPHS[((i - 1) % #PARTICLE_GLYPHS) + 1]
	glyph.TextScaled = true
	glyph.TextTransparency = 1
	glyph.ZIndex = MAX_LAYERS + 1
	glyph.Visible = false
	glyph:SetAttribute("Angle", (i / MAX_PARTICLES) * math.pi * 2)
	glyph.Parent = particleRing
	particleLabels[i] = glyph
end

-- =========================================================================
-- STATE
-- =========================================================================

local currentTierThreshold = nil -- the milestone count of the currently-applied tier, or nil
local rotationElapsed = 0
local activeParticleCount = 0
local activeRotationSpeed = 0

local function getTierForRebirths(rebirths: number): number?
	local best = nil
	for _, threshold in ipairs(RebirthModule.GetMilestoneThresholds()) do
		if rebirths >= threshold then
			best = threshold
		end
	end
	return best
end

-- Applies a tier's visuals. `animate` = false snaps instantly (used on
-- join, so a returning veteran doesn't watch their aura "grow" from
-- scratch every time they load in); true eases in for a genuine tier-up.
local function applyTier(threshold: number?, animate: boolean)
	if not threshold then
		auraHolder.Visible = false
		activeParticleCount = 0
		return
	end

	local style = TIER_STYLES[threshold]
	if not style then
		return
	end

	auraHolder.Visible = true
	activeParticleCount = style.ParticleCount
	activeRotationSpeed = style.RotationSpeed

	local orbBaseSize = LargeOrb.Size
	local targetSize = UDim2.new(
		orbBaseSize.X.Scale * style.SizeMult, orbBaseSize.X.Offset * style.SizeMult,
		orbBaseSize.Y.Scale * style.SizeMult, orbBaseSize.Y.Offset * style.SizeMult
	)

	local tweenInfo = animate and TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		or TweenInfo.new(0)

	TweenService:Create(auraHolder, tweenInfo, { Size = targetSize }):Play()

	for i, disc in ipairs(glowDiscs) do
		local shouldShow = i <= style.Layers
		disc.Visible = shouldShow
		if shouldShow then
			local t = i / style.Layers
			local targetTransparency = 1 - (1 - t) * 0.55
			disc.BackgroundColor3 = style.Color
			-- Cached so the Heartbeat pulse below has a stable value to
			-- breathe around -- reading disc.BackgroundTransparency itself
			-- there would be reading last frame's OUTPUT as this frame's
			-- base, compounding upward every frame until it settled at
			-- fully transparent and never recovered.
			disc:SetAttribute("BaseTransparency", targetTransparency)
			TweenService:Create(disc, tweenInfo, { BackgroundTransparency = targetTransparency }):Play()
		end
	end

	for i, glyph in ipairs(particleLabels) do
		local shouldShow = i <= style.ParticleCount
		glyph.Visible = shouldShow
		glyph.TextColor3 = style.Color
		TweenService:Create(glyph, tweenInfo, { TextTransparency = shouldShow and 0.15 or 1 }):Play()
	end
end

-- =========================================================================
-- AMBIENT LOOP: gentle breathing pulse + particle ring rotation
-- =========================================================================

RunService.Heartbeat:Connect(function(dt)
	if not auraHolder.Visible then
		return
	end

	rotationElapsed += dt

	-- Slow breathing pulse on the outermost layer only, so the aura reads
	-- as alive without the whole thing visibly throbbing. Always reads
	-- the STABLE BaseTransparency applyTier cached, never the live
	-- BackgroundTransparency this same loop is about to overwrite --
	-- reading its own previous output as "base" would compound upward
	-- every frame instead of oscillating around a fixed point.
	local outerDisc = glowDiscs[#glowDiscs]
	if outerDisc and outerDisc.Visible then
		local base = outerDisc:GetAttribute("BaseTransparency")
		if base then
			local pulse = (math.sin(rotationElapsed * 1.1) + 1) / 2
			outerDisc.BackgroundTransparency = base + (1 - base) * 0.3 * pulse
		end
	end

	if activeRotationSpeed > 0 and activeParticleCount > 0 then
		for i = 1, activeParticleCount do
			local glyph = particleLabels[i]
			local baseAngle = glyph:GetAttribute("Angle")
			local angle = baseAngle + rotationElapsed * activeRotationSpeed
			glyph.Position = UDim2.new(0.5 + math.cos(angle) * 0.55, 0, 0.5 + math.sin(angle) * 0.55, 0)
		end
	end
end)

-- =========================================================================
-- CELEBRATION: fires only on a genuine tier-UP, never on join
-- =========================================================================

local function celebrateTierUp(threshold: number)
	local milestone = RebirthModule.GetMilestone(threshold)
	local style = TIER_STYLES[threshold]
	if not milestone or not style then
		return
	end

	if juiceLayer then
		local center = Juice.CenterOf(LargeOrb, juiceLayer)
		if center then
			Juice.Burst(juiceLayer, center, {
				Count = 28,
				Colors = { style.Color, Color3.fromRGB(255, 255, 255) },
				Distance = 260,
				Duration = 1.0,
				Size = { 5, 14 },
				ZIndex = 220,
			})
			local tierText = "✨ " .. (milestone.title or "PRESTIGE"):upper() .. " ✨"
			Juice.FloatText(juiceLayer, center, tierText, {
				Color = style.Color,
				Duration = 1.8,
				Rise = 110,
				TextSize = 30,
			})
		end
	end

	-- Punches this aura's OWN holder, not LargeOrb's UIScale -- Juice.GetScale
	-- finds-or-creates via FindFirstChildOfClass, and LargeOrb already has a
	-- UIScale that OrbClicker.client.luau's click/hover feedback animates
	-- constantly. Punching that shared instance here would fight those
	-- tweens on the single most-clicked element in the game. auraHolder has
	-- no UIScale of its own yet, so this is a clean, exclusively-ours punch.
	Juice.Punch(Juice.GetScale(auraHolder), 0.2, 0.4)
end

-- =========================================================================
-- TRIGGER
-- =========================================================================

local function onRebirthsChanged(isInitial: boolean)
	local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	local newTier = getTierForRebirths(rebirths)

	if newTier == currentTierThreshold then
		return
	end

	local isTierUp = not isInitial and newTier ~= nil
		and (currentTierThreshold == nil or newTier > currentTierThreshold)

	currentTierThreshold = newTier
	applyTier(newTier, not isInitial)

	if isTierUp then
		celebrateTierUp(newTier)
	end
end

onRebirthsChanged(true)
player:GetAttributeChangedSignal("Rebirths"):Connect(function()
	onRebirthsChanged(false)
end)

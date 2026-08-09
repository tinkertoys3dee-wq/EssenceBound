--[[
	ZoneAmbience (LocalScript -> StarterPlayerScripts)
	======================================================
	A persistent, subtle glow behind the great orb, tinted to whichever
	zone the player is currently in (see ZonesConfig.luau) -- so "the new
	zones are just new essence orbs" is actually true at a glance, not
	just true in a picker panel you'd have to open to check. ZonePanel.
	client.luau's full-screen travel animation sells the MOMENT of
	switching; this is what keeps the destination feeling like somewhere
	different for as long as you stay there.

	SAME SAFE PATTERN AS PrestigeAura.client.luau
	--------------------------------------------------
	The glow itself is parented as a sibling of LargeOrb inside
	LargeOrbFolder, with AnchorPoint/Position/Size copied directly from
	LargeOrb rather than assumed -- and never touches LargeOrb's
	ImageColor3, which is already fought over by OrbClicker.client.luau's
	denied-click flash and other effects, each reverting to their own
	hardcoded "resting" color; adding a third, zone-varying idea of what
	that resting color should be would just make all of them wrong some
	of the time. An entirely separate, additive layer sidesteps that
	fight completely.

	The one LargeOrb property this DOES touch directly is Image (the
	orb's actual picture, swapped per zone if one is configured -- see
	ZonesConfig.Zones[*].OrbImage) -- confirmed nothing else in this
	codebase ever assigns that specific property, unlike ImageColor3, so
	there's no equivalent fight to sidestep there. The zone's own default
	image (Earthen Grove has no OrbImage configured) is whatever
	LargeOrb.Image already was at load, captured once rather than
	hardcoded a second time here.

	Deliberately more understated than PrestigeAura's own aura -- this is
	ambient environmental tint, not a second competing status effect, and
	sits at a lower ZIndex specifically so PrestigeAura's aura (and the
	orb itself) always render in front of it.

	Purely a client-side visual, same as PrestigeAura: reads CurrentZoneId
	(already server-authoritative, mirrored by PlayerDataHandler) and
	never grants, requests, or assumes anything the server hasn't already
	decided. Deleting this script changes nothing about the economy.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ZonesConfig = require(ReplicatedStorage:WaitForChild("ZonesConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MainGui = playerGui:WaitForChild("MainGui")
local Center = MainGui:WaitForChild("Center")
local LargeOrbFolder = Center:WaitForChild("LargeOrbFolder")
local LargeOrb = LargeOrbFolder:WaitForChild("LargeOrb")

-- Captured before any zone logic can touch it -- this is Earthen Grove's
-- own image, whatever it actually is in Studio, not a guess re-typed
-- here that could drift out of sync with the real asset.
local defaultOrbImage = LargeOrb.Image

-- =========================================================================
-- BUILD
-- =========================================================================

local ambienceHolder = Instance.new("Frame")
ambienceHolder.Name = "ZoneAmbience"
ambienceHolder.AnchorPoint = LargeOrb.AnchorPoint
ambienceHolder.Position = LargeOrb.Position
ambienceHolder.Size = LargeOrb.Size
ambienceHolder.BackgroundTransparency = 1
ambienceHolder.BorderSizePixel = 0
ambienceHolder.ZIndex = -1 -- behind PrestigeAura's own auraHolder (ZIndex 0) and the orb itself
ambienceHolder.Parent = LargeOrbFolder

-- Three soft, oversized discs -- brightest and smallest nearest the orb,
-- fading out into a big faint halo. Sizes are multiples of the ORB's own
-- size (copied above), same reasoning PrestigeAura's targetSize math
-- already established: staying proportional to LargeOrb.Size is what
-- keeps this centered and correctly scaled on every screen size, instead
-- of a fixed offset that would drift on anything but the screen this was
-- tuned on.
local LAYER_COUNT = 3
local SIZE_MULTS = { 1.7, 2.3, 3.0 }
local LAYER_TRANSPARENCY = { 0.75, 0.87, 0.94 } -- index 1 = innermost/brightest

local glowDiscs = {}
for i = 1, LAYER_COUNT do
	local disc = Instance.new("Frame")
	disc.Name = "ZoneGlow" .. i
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)

	local mult = SIZE_MULTS[i]
	local orbSize = LargeOrb.Size
	disc.Size = UDim2.new(orbSize.X.Scale * mult, orbSize.X.Offset * mult, orbSize.Y.Scale * mult, orbSize.Y.Offset * mult)

	disc.BackgroundTransparency = 1
	disc.BorderSizePixel = 0
	disc.ZIndex = LAYER_COUNT - i -- smallest/brightest (i=1) draws frontmost among these

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = disc

	disc.Parent = ambienceHolder
	glowDiscs[i] = disc
end

-- =========================================================================
-- COLOR
-- =========================================================================

local currentZoneId = nil

-- animate = false snaps instantly (used on join, so a returning player
-- doesn't watch the glow "grow into" their already-current zone's color
-- every time they load in); true eases into a genuine zone change.
local function applyZoneColor(zone, animate)
	local tweenInfo = animate and TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.Out) or TweenInfo.new(0)

	for i, disc in ipairs(glowDiscs) do
		local targetTransparency = LAYER_TRANSPARENCY[i]
		disc.BackgroundColor3 = zone.Color

		-- Cached so the Heartbeat breathing pulse below has a stable value
		-- to oscillate around -- same reasoning as PrestigeAura's own
		-- BaseTransparency attribute: reading live BackgroundTransparency
		-- there would read last frame's OUTPUT as this frame's base,
		-- compounding every frame instead of settling into a steady pulse.
		disc:SetAttribute("BaseTransparency", targetTransparency)
		TweenService:Create(disc, tweenInfo, { BackgroundTransparency = targetTransparency }):Play()
	end
end

-- Image swaps can't be tweened/crossfaded the way a color can -- Roblox
-- has no interpolation between two different asset ids -- so this is
-- always an instant assignment. In practice this lands right as
-- ZonePanel's own full-screen travel veil is starting to cover the
-- screen (both react to the same CurrentZoneId attribute landing at
-- roughly the same moment), which masks most of the swap anyway.
local function applyZoneImage(zone)
	LargeOrb.Image = zone.OrbImage or defaultOrbImage
end

local function onZoneChanged(isInitial)
	local zoneId = ZonesConfig.GetCurrentZoneId(player)
	if zoneId == currentZoneId then
		return
	end
	currentZoneId = zoneId

	local zone = ZonesConfig.GetZoneById(zoneId)
	if not zone then
		return
	end

	applyZoneImage(zone)

	applyZoneColor(zone, not isInitial)
end

onZoneChanged(true)
player:GetAttributeChangedSignal("CurrentZoneId"):Connect(function()
	onZoneChanged(false)
end)

-- =========================================================================
-- AMBIENT LOOP: gentle breathing pulse on the outermost layer only, so
-- the glow reads as alive without the whole thing visibly throbbing.
-- =========================================================================

local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt

	local outerDisc = glowDiscs[LAYER_COUNT]
	if not outerDisc then
		return
	end

	local base = outerDisc:GetAttribute("BaseTransparency")
	if not base then
		return
	end

	local pulse = (math.sin(elapsed * 0.8) + 1) / 2
	outerDisc.BackgroundTransparency = base + (1 - base) * 0.25 * pulse
end)

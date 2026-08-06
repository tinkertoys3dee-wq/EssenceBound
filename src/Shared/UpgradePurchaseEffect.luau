--[[
	UpgradePurchaseEffect.lua  (ModuleScript)

	Plays a themed "purchase" burst on an upgrade node: a scale punch +
	glow pulse on the node itself, an expanding ring shockwave, a handful
	of shard particles flying outward, and a rising confirmation label.
	Colors match the same category theme used by the tooltip system.

	Six specific upgrades get a bespoke, much more elaborate "deluxe"
	effect instead of the standard category burst -- see the
	SPECIAL_UPGRADE_EFFECTS table near the bottom of this file. They are
	listed there from least to most rare, and each one is intentionally
	bigger/longer/flashier than the last:

		root_awakening          - roots erupting from the ground
		manual_storm_summon     - a single lightning strike from a gathering cloud
		core_resilience         - armor plates slam in and lock into a hex shield
		storm_caller_ascension  - a triple lightning strike + ascension beam
		twin_orb_manifestation  - two orbiting orbs that collide into the node
		essence_convergence     - beams converging from every edge of the screen

	USAGE
	------
	Put this ModuleScript wherever your other tooltip/tree code lives
	(e.g. ReplicatedStorage or StarterPlayerScripts), then from a
	LocalScript:

		local PurchaseEffect = require(path.to.UpgradePurchaseEffect)

		-- node = the GuiObject (hex icon) that was just purchased
		-- category = same Category attribute/string used by the tooltip
		-- upgradeId (optional) = the upgrade's unique name/id. If it
		--   matches one of the six rare ids above, the deluxe version
		--   plays automatically instead of the normal category burst.
		PurchaseEffect.Play(node, node:GetAttribute("Category"), node.Name)

	If you already know you want a specific deluxe effect (e.g. testing
	it in isolation), you can also call it directly:

		PurchaseEffect.PlaySpecial(node, "essence_convergence")

	Typical hookup with a server purchase confirmation:

		purchaseUpgradeRemote.OnClientEvent:Connect(function(upgradeName)
			local node = findNodeByName(upgradeName) -- your own lookup
			if node then
				PurchaseEffect.Play(node, node:GetAttribute("Category"), upgradeName)
			end
		end)

	Only fire this AFTER the server confirms the purchase, not optimistically
	on click -- otherwise a rejected purchase (insufficient currency, etc.)
	would still show a "bought it!" animation.

	A note on the deluxe effects: they spawn a lot of extra GuiObjects
	(beams, orbs, motes, rings) on top of the base burst. That's by design
	since they're meant to fire rarely, but avoid calling PlaySpecial
	rapidly/repeatedly (e.g. in a loop) since each call is uncapped and
	they aren't pooled.
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PurchaseEffect = {}

--============================================================
-- CATEGORY THEMES (kept in sync with the tooltip's palette)
--============================================================
local CATEGORY_THEME = {
	Defense = { Color = Color3.fromRGB(97, 199, 110), Glyph = "🛡" },
	Criticals = { Color = Color3.fromRGB(214, 71, 71), Glyph = "⚔" },
	Shatter = { Color = Color3.fromRGB(224, 138, 63), Glyph = "🔥" },
	Regen = { Color = Color3.fromRGB(178, 102, 214), Glyph = "⏱" },
	Storm = { Color = Color3.fromRGB(214, 102, 191), Glyph = "🌀" },
	Auto = { Color = Color3.fromRGB(72, 191, 178), Glyph = "💧" },
	Collection = { Color = Color3.fromRGB(214, 178, 71), Glyph = "⚙" },
	Rebirth = { Color = Color3.fromRGB(62, 161, 191), Glyph = "★" },
	Core = { Color = Color3.fromRGB(93, 175, 224), Glyph = "✦" },
	Ultimate = { Color = Color3.fromRGB(224, 138, 63), Glyph = "★" },
}

local DEFAULT_THEME = { Color = Color3.fromRGB(255, 255, 255), Glyph = "✦" }

local function getTheme(category)
	return CATEGORY_THEME[category] or DEFAULT_THEME
end

--============================================================
-- OVERLAY GUI (shared across all effect plays)
--============================================================
local effectGui = Instance.new("ScreenGui")
effectGui.Name = "UpgradePurchaseEffectGui"
effectGui.ResetOnSpawn = false
effectGui.IgnoreGuiInset = false -- match node.AbsolutePosition's coordinate space
effectGui.DisplayOrder = 999 -- just under the tooltip's 1000
effectGui.Parent = playerGui

--============================================================
-- INTERNAL HELPERS
--============================================================

-- World-space center (in screen pixels) of a GuiObject, for spawning
-- overlay effects that line up with wherever the node actually is.
local function getNodeCenter(node)
	return node.AbsolutePosition + node.AbsoluteSize / 2
end

local HEX_RING_IMAGE = "rbxassetid://91692624575395"

-- 1) Punch-scale + glow pulse directly on the purchased node.
-- `punchScale` is optional (defaults to 1.35, the original strength) so
-- rarer effects can ask for a bigger, more dramatic punch.
local function playNodePunch(node, theme, punchScale)
	punchScale = punchScale or 1.35

	local existingScale = node:FindFirstChildOfClass("UIScale")
	local scale = existingScale or Instance.new("UIScale")
	scale.Parent = node

	scale.Scale = 1
	local punchUp = TweenService:Create(
		scale,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = punchScale }
	)
	local settleDown = TweenService:Create(
		scale,
		TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	punchUp.Completed:Once(function()
		settleDown:Play()
	end)
	punchUp:Play()

	-- Glow hugging the node's actual hex shape (a UIStroke would only trace
	-- the rectangular bounding box, not the hexagon), flashing outward and
	-- fading. Parented to effectGui (not the node) so it isn't affected by
	-- the punch-scale tween above, positioned/sized in pixel offsets since
	-- Scale here would be relative to the screen, not the node.
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)

	local glow = Instance.new("ImageLabel")
	glow.Name = "PurchaseGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(center.X, center.Y)
	glow.Size = UDim2.fromOffset(baseSize, baseSize)
	glow.BackgroundTransparency = 1
	glow.Image = HEX_RING_IMAGE
	glow.ImageColor3 = theme.Color
	glow.ImageTransparency = 0
	glow.ScaleType = Enum.ScaleType.Fit
	glow.ZIndex = 500
	glow.Parent = effectGui

	local glowTween = TweenService:Create(
		glow,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(baseSize * 1.6, baseSize * 1.6), ImageTransparency = 1 }
	)
	glowTween:Play()
	glowTween.Completed:Once(function()
		glow:Destroy()
	end)
end

-- 2) Expanding ring "shockwave" centered on the node.
local function playShockwave(center, baseSize, theme)
	local ring = Instance.new("Frame")
	ring.Name = "PurchaseRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(center.X, center.Y)
	ring.Size = UDim2.fromOffset(baseSize, baseSize)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 500
	ring.Parent = effectGui

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 4
	ringStroke.Color = theme.Color
	ringStroke.Transparency = 0.1
	ringStroke.Parent = ring

	local targetSize = baseSize * 3.2
	local tween = TweenService:Create(
		ring,
		TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(targetSize, targetSize) }
	)
	local strokeFade = TweenService:Create(
		ringStroke,
		TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	)
	tween:Play()
	strokeFade:Play()

	Debris:AddItem(ring, 0.6)
end

-- 3) Shard particles flying outward from the node and fading out.
local function playShards(center, theme, shardCount)
	for i = 1, shardCount do
		local shard = Instance.new("Frame")
		shard.Name = "PurchaseShard"
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Position = UDim2.fromOffset(center.X, center.Y)
		shard.Size = UDim2.fromOffset(8, 8)
		shard.BackgroundColor3 = theme.Color
		shard.BorderSizePixel = 0
		shard.Rotation = math.random(0, 360)
		shard.ZIndex = 500
		shard.Parent = effectGui

		local shardCorner = Instance.new("UICorner")
		shardCorner.CornerRadius = UDim.new(0.25, 0)
		shardCorner.Parent = shard

		-- Even spread around the circle, with a little randomness so it
		-- doesn't look mechanically perfect.
		local angle = (i / shardCount) * math.pi * 2 + math.random() * 0.4
		local distance = math.random(55, 90)
		local offset = Vector2.new(math.cos(angle), math.sin(angle)) * distance

		local flyTween = TweenService:Create(
			shard,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(center.X + offset.X, center.Y + offset.Y),
				Size = UDim2.fromOffset(2, 2),
				BackgroundTransparency = 1,
				Rotation = shard.Rotation + math.random(-90, 90),
			}
		)
		flyTween:Play()
		Debris:AddItem(shard, 0.55)
	end
end

-- 4) Rising confirmation label ("★ Purchased!") that floats up and fades.
local function playRisingLabel(center, theme)
	local label = Instance.new("TextLabel")
	label.Name = "PurchaseLabel"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromOffset(center.X, center.Y - 10)
	label.Size = UDim2.fromOffset(160, 24)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = theme.Glyph .. " Purchased!"
	label.TextSize = 16
	label.TextColor3 = theme.Color
	label.TextStrokeTransparency = 0.6
	label.TextTransparency = 0
	label.ZIndex = 501
	label.Parent = effectGui

	local riseTween = TweenService:Create(
		label,
		TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(center.X, center.Y - 46),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	riseTween:Play()
	Debris:AddItem(label, 0.75)
end

--============================================================
-- SHARED FX PRIMITIVES
-- Lower-level building blocks used by the six deluxe rare-upgrade
-- effects below. Kept separate from the four functions above so the
-- standard category burst is never at risk of being changed by this.
--============================================================

-- A soft circular glow that blooms (or shrinks) and fades.
local function spawnGlowPulse(center, startSize, endSize, color, transparencyStart, duration)
	local glow = Instance.new("ImageLabel")
	glow.Name = "FXGlow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromOffset(center.X, center.Y)
	glow.Size = UDim2.fromOffset(startSize, startSize)
	glow.BackgroundTransparency = 1
	glow.Image = HEX_RING_IMAGE
	glow.ImageColor3 = color
	glow.ImageTransparency = transparencyStart or 0
	glow.ScaleType = Enum.ScaleType.Fit
	glow.ZIndex = 497
	glow.Parent = effectGui

	local tween = TweenService:Create(
		glow,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(endSize, endSize), ImageTransparency = 1 }
	)
	tween:Play()
	Debris:AddItem(glow, duration + 0.1)
	return glow
end

-- Expanding ring outline. `delay` (optional) staggers when it fires, for
-- layering multiple rings one after another.
local function spawnRing(center, startSize, endSize, color, thickness, duration, delay)
	local ring = Instance.new("Frame")
	ring.Name = "FXRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(center.X, center.Y)
	ring.Size = UDim2.fromOffset(startSize, startSize)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 500
	ring.Parent = effectGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = 0.05
	stroke.Parent = ring

	local function fire()
		local grow = TweenService:Create(
			ring,
			TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(endSize, endSize) }
		)
		local fade = TweenService:Create(
			stroke,
			TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)
		grow:Play()
		fade:Play()
	end

	if delay and delay > 0 then
		task.delay(delay, fire)
	else
		fire()
	end

	Debris:AddItem(ring, duration + (delay or 0) + 0.1)
	return ring
end

-- Outward-flying shard burst. `colors` may be a single Color3 or a list of
-- Color3s to cycle through (for dual/tri-tone bursts).
local function spawnShardBurst(center, colors, shardCount, minDist, maxDist, duration, shardSize)
	if typeof(colors) == "Color3" then
		colors = { colors }
	end
	shardSize = shardSize or 8

	for i = 1, shardCount do
		local color = colors[((i - 1) % #colors) + 1]
		local shard = Instance.new("Frame")
		shard.Name = "FXShard"
		shard.AnchorPoint = Vector2.new(0.5, 0.5)
		shard.Position = UDim2.fromOffset(center.X, center.Y)
		shard.Size = UDim2.fromOffset(shardSize, shardSize)
		shard.BackgroundColor3 = color
		shard.BorderSizePixel = 0
		shard.Rotation = math.random(0, 360)
		shard.ZIndex = 500
		shard.Parent = effectGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = shard

		local angle = (i / shardCount) * math.pi * 2 + math.random() * 0.4
		local distance = math.random(minDist, maxDist)
		local offset = Vector2.new(math.cos(angle), math.sin(angle)) * distance

		local tween = TweenService:Create(
			shard,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(center.X + offset.X, center.Y + offset.Y),
				Size = UDim2.fromOffset(shardSize * 0.25, shardSize * 0.25),
				BackgroundTransparency = 1,
				Rotation = shard.Rotation + math.random(-90, 90),
			}
		)
		tween:Play()
		Debris:AddItem(shard, duration + 0.05)
	end
end

-- Rising, fading confirmation label -- a bigger/gradient-capable variant
-- of playRisingLabel above, for custom deluxe text.
local function spawnRisingLabel(center, text, color, textSize, riseDistance, duration, secondaryColor)
	local label = Instance.new("TextLabel")
	label.Name = "FXLabel"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromOffset(center.X, center.Y - 10)
	label.Size = UDim2.fromOffset(260, textSize + 10)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.TextTransparency = 0
	label.ZIndex = 501
	label.Parent = effectGui

	if secondaryColor then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(color, secondaryColor)
		gradient.Parent = label
	end

	local tween = TweenService:Create(
		label,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(center.X, center.Y - riseDistance),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	)
	tween:Play()
	Debris:AddItem(label, duration + 0.1)
	return label
end

-- Full-screen color flash for dramatic strikes/bursts.
local function spawnScreenFlash(color, peakTransparency, fadeDuration)
	local flash = Instance.new("Frame")
	flash.Name = "FXScreenFlash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 600
	flash.Parent = effectGui

	local flashIn = TweenService:Create(
		flash,
		TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = peakTransparency }
	)
	local flashOut = TweenService:Create(
		flash,
		TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	flashIn:Play()
	flashIn.Completed:Once(function()
		flashOut:Play()
	end)
	Debris:AddItem(flash, fadeDuration + 0.2)
end

-- Jagged lightning bolt between two screen points, built from a handful of
-- rotated segments. Appears instantly and fades fast, like a real strike.
local function spawnLightningBolt(startPos, endPos, color, segments, thickness)
	segments = segments or 6
	thickness = thickness or 3

	local points = { startPos }
	local mainDir = endPos - startPos
	local perp = Vector2.new(-mainDir.Y, mainDir.X)
	if perp.Magnitude > 0 then
		perp = perp.Unit
	end

	for i = 1, segments - 1 do
		local t = i / segments
		local base = startPos:Lerp(endPos, t)
		local jag = perp * math.random(-16, 16)
		table.insert(points, base + jag)
	end
	table.insert(points, endPos)

	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local segDir = b - a
		local segLen = segDir.Magnitude
		if segLen > 0 then
			local angle = math.deg(math.atan2(segDir.Y, segDir.X))

			local seg = Instance.new("Frame")
			seg.Name = "FXBoltSegment"
			seg.AnchorPoint = Vector2.new(0, 0.5)
			seg.Position = UDim2.fromOffset(a.X, a.Y)
			seg.Size = UDim2.fromOffset(segLen, thickness)
			seg.Rotation = angle
			seg.BackgroundColor3 = color
			seg.BorderSizePixel = 0
			seg.ZIndex = 520
			seg.Parent = effectGui

			local fade = TweenService:Create(
				seg,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }
			)
			task.delay(0.03, function()
				fade:Play()
			end)
			Debris:AddItem(seg, 0.3)
		end
	end
end

-- A thin beam that shoots inward from a screen-edge point toward `target`,
-- shrinking to nothing as it arrives. Used by the convergence effect.
local function spawnEdgeBeam(fromPos, targetPos, color, thickness, duration)
	local dir = targetPos - fromPos
	local fullLen = dir.Magnitude
	local angle = math.deg(math.atan2(dir.Y, dir.X))

	local beam = Instance.new("Frame")
	beam.Name = "FXEdgeBeam"
	beam.AnchorPoint = Vector2.new(0, 0.5)
	beam.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
	beam.Size = UDim2.fromOffset(fullLen, thickness)
	beam.Rotation = angle
	beam.BackgroundColor3 = color
	beam.BackgroundTransparency = 1
	beam.BorderSizePixel = 0
	beam.ZIndex = 495
	beam.Parent = effectGui

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = beam

	local appear = TweenService:Create(
		beam,
		TweenInfo.new(duration * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	local retract = TweenService:Create(
		beam,
		TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{
			Position = UDim2.fromOffset(targetPos.X, targetPos.Y),
			Size = UDim2.fromOffset(0, thickness),
			BackgroundTransparency = 1,
		}
	)
	appear:Play()
	appear.Completed:Once(function()
		retract:Play()
	end)
	Debris:AddItem(beam, duration + 0.1)
end

-- Vertical beam shooting up off-screen from the node -- power "ascending".
local function spawnAscensionBeam(center, width, color, travelHeight, duration)
	local beam = Instance.new("Frame")
	beam.Name = "FXAscensionBeam"
	beam.AnchorPoint = Vector2.new(0.5, 1)
	beam.Position = UDim2.fromOffset(center.X, center.Y)
	beam.Size = UDim2.fromOffset(width, 0)
	beam.BackgroundColor3 = color
	beam.BackgroundTransparency = 0.15
	beam.BorderSizePixel = 0
	beam.ZIndex = 490
	beam.Parent = effectGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = beam

	local grow = TweenService:Create(
		beam,
		TweenInfo.new(duration * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(width, travelHeight) }
	)
	local fade = TweenService:Create(
		beam,
		TweenInfo.new(duration * 0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	grow:Play()
	grow.Completed:Once(function()
		fade:Play()
	end)
	Debris:AddItem(beam, duration + 0.1)
end

-- A rotating "arcane circle" ring that spins continuously while scaling --
-- used as a vortex/containment ring around the node.
local function spawnVortexRing(center, startSize, endSize, color, thickness, spinDegrees, duration)
	local ring = Instance.new("Frame")
	ring.Name = "FXVortexRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromOffset(center.X, center.Y)
	ring.Size = UDim2.fromOffset(startSize, startSize)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 496
	ring.Parent = effectGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = 0.2
	stroke.Parent = ring

	local spin = TweenService:Create(
		ring,
		TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Rotation = spinDegrees }
	)
	local grow = TweenService:Create(
		ring,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(endSize, endSize) }
	)
	local fade = TweenService:Create(
		stroke,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1 }
	)
	spin:Play()
	grow:Play()
	fade:Play()
	Debris:AddItem(ring, duration + 0.1)
	return ring
end

-- A small orb that orbits `center`, driven by a Vector2Value (X = angle in
-- degrees, Y = radius in pixels) so both the spin and an inward "collision"
-- pull can be tweened smoothly just by tweening that one value.
local function spawnOrbitingOrb(center, color, orbSize, startAngleDeg, startRadius)
	local orb = Instance.new("Frame")
	orb.Name = "FXOrb"
	orb.AnchorPoint = Vector2.new(0.5, 0.5)
	orb.Size = UDim2.fromOffset(orbSize, orbSize)
	orb.BackgroundColor3 = color
	orb.BorderSizePixel = 0
	orb.ZIndex = 510
	orb.Parent = effectGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = orb

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = orb

	local state = Instance.new("Vector3Value")
	state.Value = Vector3.new(startAngleDeg, startRadius, 0)
	state.Parent = orb

	local function updatePosition()
		local angle, radius = state.Value.X, state.Value.Y
		local rad = math.rad(angle)
		local pos = center + Vector2.new(math.cos(rad), math.sin(rad)) * radius
		orb.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
	updatePosition()
	state:GetPropertyChangedSignal("Value"):Connect(updatePosition)

	return orb, state
end

--============================================================
-- RARE UPGRADE THEMES + DELUXE EFFECTS
-- Listed least -> most rare, each bigger than the last.
--============================================================

--------------------------------------------------------------
-- 1) root_awakening -- roots erupt from the ground around the node.
local ROOT_AWAKENING_THEME = {
	Primary = Color3.fromRGB(70, 168, 88),
	Secondary = Color3.fromRGB(133, 94, 54),
	Highlight = Color3.fromRGB(178, 140, 88), -- lighter brown for branch variation
	Glyph = "❁",
}

-- Recursively builds a segmented, curling root. Each call grows a chain of
-- segments; partway along, it may spawn one or two child branches that grow
-- outward from the parent at an offset angle, at reduced scale, using the
-- same logic. AnchorPoint (0.5,1) means each segment rotates around its own
-- base, so anchoring segment N+1 at segment N's tip (computed via sin/cos)
-- produces a continuous curling chain rather than disjoint straight lines.
local function buildRootTendril(basePos, leanAngle, length, width, theme, startDelay, depth)
	depth = depth or 0
	if depth > 2 or width < 1 then
		return
	end

	local maxDepthForBranching = 2
	local segmentCount = (depth == 0) and math.random(4, 6) or math.random(2, 3)
	local segmentLength = length / segmentCount
	local curlSign = (math.random() < 0.5) and 1 or -1
	local cumulativeAngle = leanAngle
	local anchorPos = basePos
	local color = (depth == 0 or math.random() < 0.6) and theme.Secondary or theme.Highlight

	for i = 1, segmentCount do
		local wiggle = (7 + math.random(-3, 4)) * curlSign * ((i % 2 == 0) and -1 or 1)
		cumulativeAngle = cumulativeAngle + wiggle

		local segWidth = math.max(1, width - (i - 1) * (width / (segmentCount + 1)))

		local rad = math.rad(cumulativeAngle)
		local tipOffset = Vector2.new(segmentLength * math.sin(rad), -segmentLength * math.cos(rad))
		local tipPos = anchorPos + tipOffset

		local segment = Instance.new("Frame")
		segment.Name = "FXRootSegment"
		segment.AnchorPoint = Vector2.new(0.5, 1)
		segment.Position = UDim2.fromOffset(anchorPos.X, anchorPos.Y)
		segment.Rotation = cumulativeAngle
		segment.Size = UDim2.fromOffset(segWidth, 0)
		segment.BackgroundColor3 = color
		segment.BorderSizePixel = 0
		segment.ZIndex = 494 - depth
		segment.Parent = effectGui

		local segCorner = Instance.new("UICorner")
		segCorner.CornerRadius = UDim.new(1, 0)
		segCorner.Parent = segment

		local segDelay = startDelay + (i - 1) * 0.07
		task.delay(segDelay, function()
			if not segment.Parent then
				return
			end
			local growTween = TweenService:Create(
				segment,
				TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(segWidth, segmentLength) }
			)
			growTween:Play()
		end)

		-- Branch off a child root partway along this chain (not on the very
		-- first or last segment, so branches look like they're forking off
		-- the middle of the parent root rather than the tip or the base).
		if depth < maxDepthForBranching and segmentCount >= 3 and (i == 2 or i == segmentCount - 1) then
			if math.random() < 0.7 then
				task.delay(segDelay + 0.16, function()
					if not segment.Parent then
						return
					end
					local branchAngle = cumulativeAngle + curlSign * math.random(35, 65) * (math.random() < 0.5 and 1 or -1)
					local branchLength = length * (0.4 + math.random() * 0.2)
					local branchWidth = math.max(1, width * 0.55)
					buildRootTendril(tipPos, branchAngle, branchLength, branchWidth, theme, 0, depth + 1)
				end)
			end
		end

		-- Thin root-hair stubs for texture, more of them on the primary root.
		if (depth == 0 and (i == 2 or i == 3 or i == 4)) or (depth > 0 and i == 2) then
			task.delay(segDelay + 0.14, function()
				if not segment.Parent then
					return
				end
				local hairAngle = cumulativeAngle + curlSign * math.random(30, 55) * (math.random() < 0.5 and 1 or -1)
				local hair = Instance.new("Frame")
				hair.Name = "FXRootHair"
				hair.AnchorPoint = Vector2.new(0.5, 1)
				hair.Position = UDim2.fromOffset(tipPos.X, tipPos.Y)
				hair.Rotation = hairAngle
				hair.Size = UDim2.fromOffset(1.5, segmentLength * 0.5)
				hair.BackgroundColor3 = theme.Secondary
				hair.BackgroundTransparency = 0.2
				hair.BorderSizePixel = 0
				hair.ZIndex = 492
				hair.Parent = effectGui

				local hairCorner = Instance.new("UICorner")
				hairCorner.CornerRadius = UDim.new(1, 0)
				hairCorner.Parent = hair

				local hairFade = TweenService:Create(
					hair,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }
				)
				hairFade:Play()
				Debris:AddItem(hair, 0.4)
			end)
		end

		-- Glowing tip flourish on the very last segment of each root chain:
		-- a small soft dot that pulses outward once, like a growth bud.
		if i == segmentCount then
			task.delay(segDelay + 0.22, function()
				if not segment.Parent then
					return
				end
				local tipGlow = Instance.new("Frame")
				tipGlow.Name = "FXRootTipGlow"
				tipGlow.AnchorPoint = Vector2.new(0.5, 0.5)
				tipGlow.Position = UDim2.fromOffset(tipPos.X, tipPos.Y)
				tipGlow.Size = UDim2.fromOffset(segWidth * 1.5, segWidth * 1.5)
				tipGlow.BackgroundColor3 = theme.Primary
				tipGlow.BackgroundTransparency = 0.3
				tipGlow.BorderSizePixel = 0
				tipGlow.ZIndex = 496
				tipGlow.Parent = effectGui

				local glowCorner = Instance.new("UICorner")
				glowCorner.CornerRadius = UDim.new(1, 0)
				glowCorner.Parent = tipGlow

				local glowTween = TweenService:Create(
					tipGlow,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(segWidth * 4, segWidth * 4), BackgroundTransparency = 1 }
				)
				glowTween:Play()
				Debris:AddItem(tipGlow, 0.5)
			end)
		end

		task.delay(segDelay + 0.2 + 0.18, function()
			if not segment.Parent then
				return
			end
			local fadeTween = TweenService:Create(
				segment,
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ BackgroundTransparency = 1 }
			)
			fadeTween:Play()
		end)

		Debris:AddItem(segment, segDelay + 0.9)

		anchorPos = tipPos
	end
end

local function playRootAwakening(node)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)
	local theme = ROOT_AWAKENING_THEME

	playNodePunch(node, { Color = theme.Primary }, 1.3)

	-- Ground burst: a squashed brown ring at the base of the node, like
	-- dust kicked up as roots break the surface.
	local groundRing = Instance.new("Frame")
	groundRing.Name = "FXGroundBurst"
	groundRing.AnchorPoint = Vector2.new(0.5, 0.5)
	groundRing.Position = UDim2.fromOffset(center.X, center.Y + baseSize * 0.35)
	groundRing.Size = UDim2.fromOffset(baseSize * 0.6, baseSize * 0.18)
	groundRing.BackgroundColor3 = theme.Secondary
	groundRing.BackgroundTransparency = 0.3
	groundRing.BorderSizePixel = 0
	groundRing.ZIndex = 495
	groundRing.Parent = effectGui

	local groundCorner = Instance.new("UICorner")
	groundCorner.CornerRadius = UDim.new(1, 0)
	groundCorner.Parent = groundRing

	local groundTween = TweenService:Create(
		groundRing,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(baseSize * 1.6, baseSize * 0.4), BackgroundTransparency = 1 }
	)
	groundTween:Play()
	Debris:AddItem(groundRing, 0.6)

	-- Root system: several primary tendrils spread evenly along the ground,
	-- each recursively branching into thinner sub-roots as they grow.
	local tendrilCount = 6
	local groundY = center.Y + baseSize * 0.4

	for i = 1, tendrilCount do
		local fraction = (tendrilCount == 1) and 0 or ((i - 1) / (tendrilCount - 1)) * 2 - 1
		local xOffset = fraction * baseSize * 0.32 + math.random(-8, 8)
		local basePos = Vector2.new(center.X + xOffset, groundY)
		local leanAngle = fraction * 16 + math.random(-5, 5)
		local startDelay = math.random() * 0.08
		local length = baseSize * (0.5 + math.random() * 0.2)
		local width = 5

		buildRootTendril(basePos, leanAngle, length, width, theme, startDelay, 0)
	end

	spawnGlowPulse(center, baseSize, baseSize * 1.5, theme.Primary, 0, 0.6)
	spawnShardBurst(center, { theme.Primary, Color3.fromRGB(190, 224, 140) }, 8, 40, 65, 0.55, 7)
	spawnRisingLabel(center, theme.Glyph .. " Root Awakening!", theme.Primary, 17, 42, 0.75)
end

--------------------------------------------------------------
-- 2) manual_storm_summon -- a storm cloud gathers, then strikes once.
--------------------------------------------------------------
local STORM_SUMMON_THEME = {
	Primary = Color3.fromRGB(255, 255, 255),
	Secondary = Color3.fromRGB(94, 110, 214),
	Glyph = "⚡",
}

local function playManualStormSummon(node)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)
	local theme = STORM_SUMMON_THEME

	playNodePunch(node, { Color = theme.Secondary }, 1.4)

	-- Storm cloud gathers just above the node. (Reuses the hex ring asset
	-- tinted dark/soft -- swap in a dedicated cloud/smoke texture here if
	-- you have one.)
	local cloudPos = Vector2.new(center.X, center.Y - baseSize * 0.9)
	local cloud = Instance.new("ImageLabel")
	cloud.Name = "FXStormCloud"
	cloud.AnchorPoint = Vector2.new(0.5, 0.5)
	cloud.Position = UDim2.fromOffset(cloudPos.X, cloudPos.Y)
	cloud.Size = UDim2.fromOffset(0, 0)
	cloud.BackgroundTransparency = 1
	cloud.Image = "rbxassetid://113594165457603"
	cloud.ImageColor3 = Color3.fromRGB(138, 138, 138)
	cloud.ImageTransparency = 0.2
	cloud.ScaleType = Enum.ScaleType.Fit
	cloud.ZIndex = 493
	cloud.Parent = effectGui

	local cloudGrow = TweenService:Create(
		cloud,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(baseSize * 1.4, baseSize * 1.4) }
	)
	cloudGrow:Play()

	task.delay(0.22, function()
		-- Strike: flash + bolt from the cloud down into the node.
		spawnScreenFlash(Color3.fromRGB(255, 255, 255), 0.82, 0.3)
		spawnLightningBolt(cloudPos, center, theme.Primary, 6, 3)
		spawnRing(center, baseSize, baseSize * 3, theme.Secondary, 4, 0.5)
		spawnShardBurst(center, { theme.Primary, theme.Secondary }, 10, 45, 80, 0.5, 6)
		spawnRisingLabel(center, theme.Glyph .. " Storm Summoned!", theme.Secondary, 17, 44, 0.75)

		local cloudFade = TweenService:Create(
			cloud,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ ImageTransparency = 1, Size = UDim2.fromOffset(baseSize * 1.8, baseSize * 1.8) }
		)
		cloudFade:Play()
		Debris:AddItem(cloud, 0.4)
	end)
end

--------------------------------------------------------------
-- 3) core_resilience -- armor plates slam in from every side and lock
--    into a hexagonal shield around the node.
--------------------------------------------------------------
local CORE_RESILIENCE_THEME = {
	Primary = Color3.fromRGB(93, 175, 224), -- steel blue, echoes the Core category
	Secondary = Color3.fromRGB(214, 226, 235), -- pale plating highlight
	Glyph = "⬡",
}

-- A single armor plate that flies in from off-node along `angleDeg`,
-- slams into position at `radius` from center, flashes its trim on
-- impact, holds briefly (reads as "locked in"), then fades. Reused N
-- times per shield in playCoreResilience, staggered via `delay`.
local function spawnArmorPlate(center, angleDeg, radius, plateWidth, plateHeight, color, delay)
	local rad = math.rad(angleDeg)
	local dir = Vector2.new(math.cos(rad), math.sin(rad))
	local finalPos = center + dir * radius
	local startPos = center + dir * (radius + 220)

	local plate = Instance.new("Frame")
	plate.Name = "FXArmorPlate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromOffset(startPos.X, startPos.Y)
	plate.Rotation = angleDeg + 90
	plate.Size = UDim2.fromOffset(plateWidth, plateHeight)
	plate.BackgroundColor3 = color
	plate.BackgroundTransparency = 0.05
	plate.BorderSizePixel = 0
	plate.ZIndex = 499
	plate.Parent = effectGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = plate

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.5
	stroke.Parent = plate

	task.delay(delay, function()
		if not plate.Parent then
			return
		end
		local slam = TweenService:Create(
			plate,
			TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(finalPos.X, finalPos.Y) }
		)
		slam:Play()
		slam.Completed:Once(function()
			if not plate.Parent then
				return
			end
			-- Impact flash on lock.
			local trimFlash = TweenService:Create(
				stroke,
				TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 0 }
			)
			trimFlash:Play()

			task.delay(0.55, function()
				if not plate.Parent then
					return
				end
				local fade = TweenService:Create(
					plate,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }
				)
				local strokeFade = TweenService:Create(
					stroke,
					TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Transparency = 1 }
				)
				fade:Play()
				strokeFade:Play()
			end)
		end)
	end)

	Debris:AddItem(plate, delay + 1.4)
end

local function playCoreResilience(node)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)
	local theme = CORE_RESILIENCE_THEME

	playNodePunch(node, { Color = theme.Primary }, 1.3)

	-- A containment ring spins up first, marking where the plates will lock.
	spawnVortexRing(center, baseSize * 0.9, baseSize * 1.35, theme.Primary, 3, 140, 0.5)

	-- Six armor plates slam inward from every direction and lock into a
	-- hexagonal shield around the node, staggered slightly so they read
	-- as assembling piece by piece rather than landing all at once.
	local plateCount = 6
	local plateRadius = baseSize * 0.85
	local lastPlateDelay = 0
	for i = 1, plateCount do
		local angleDeg = (i - 1) * (360 / plateCount) - 90
		local plateDelay = 0.35 + (i - 1) * 0.06
		lastPlateDelay = plateDelay
		spawnArmorPlate(center, angleDeg, plateRadius, baseSize * 0.32, baseSize * 0.14, theme.Primary, plateDelay)
	end

	task.delay(lastPlateDelay + 0.3, function()
		-- Final lock: the shield pulses once, solid, before releasing outward.
		spawnGlowPulse(center, baseSize * 0.8, baseSize * 1.5, theme.Secondary, 0.15, 0.4)
		spawnRing(center, baseSize * 1.7, baseSize * 3, theme.Primary, 5, 0.5)
		spawnRing(center, baseSize * 1.7, baseSize * 3.6, theme.Secondary, 2, 0.6, 0.1)
		spawnShardBurst(center, { theme.Primary, theme.Secondary }, 12, 50, 90, 0.55, 6)
		spawnRisingLabel(center, theme.Glyph .. " Core Resilience!", theme.Primary, 18, 46, 0.8, theme.Secondary)
	end)
end

--------------------------------------------------------------
-- 4) storm_caller_ascension -- a vortex opens, three bolts strike, and
--    power ascends from the node in a beam of light.
--------------------------------------------------------------
local STORM_CALLER_THEME = {
	Primary = Color3.fromRGB(255, 255, 255),
	Secondary = Color3.fromRGB(142, 91, 224),
	Tertiary = Color3.fromRGB(196, 168, 255),
	Glyph = "☈",
}

local function playStormCallerAscension(node)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)
	local theme = STORM_CALLER_THEME

	playNodePunch(node, { Color = theme.Secondary }, 1.45)

	-- The eye of the storm opens before the strikes land.
	spawnVortexRing(center, baseSize * 0.6, baseSize * 2.2, theme.Secondary, 5, 260, 0.8)
	spawnVortexRing(center, baseSize * 0.4, baseSize * 1.6, theme.Tertiary, 3, -220, 0.7)

	-- Three staggered lightning strikes from different angles.
	local strikeAngles = { -60, 10, 70 }
	for i, angleDeg in ipairs(strikeAngles) do
		task.delay(0.1 * i, function()
			local rad = math.rad(angleDeg - 90)
			local origin = center + Vector2.new(math.cos(rad), math.sin(rad)) * (baseSize * 3)
			spawnLightningBolt(origin, center, theme.Primary, 7, 3)
			spawnScreenFlash(Color3.fromRGB(255, 255, 255), 0.5, 0.2)
		end)
	end

	task.delay(0.4, function()
		spawnRing(center, baseSize, baseSize * 3.2, theme.Secondary, 5, 0.55)
		spawnRing(center, baseSize, baseSize * 4, theme.Tertiary, 3, 0.7, 0.1)
		spawnAscensionBeam(center, baseSize * 0.5, theme.Secondary, baseSize * 6, 0.9)
		spawnShardBurst(center, { theme.Primary, theme.Secondary, theme.Tertiary }, 14, 55, 100, 0.6, 7)
		spawnRisingLabel(
			center,
			theme.Glyph .. " Storm Caller Ascends!",
			theme.Secondary,
			19,
			50,
			0.85,
			theme.Tertiary
		)
	end)
end

--------------------------------------------------------------
-- 5) twin_orb_manifestation -- two orbs orbit outward, then accelerate
--    inward and collide into the node in a merged burst.
--------------------------------------------------------------
local TWIN_ORB_THEME = {
	Gold = Color3.fromRGB(224, 178, 71),
	Cyan = Color3.fromRGB(93, 200, 224),
	Glyph = "✵",
}

local function playTwinOrbManifestation(node)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)
	local theme = TWIN_ORB_THEME

	playNodePunch(node, { Color = theme.Gold }, 1.5)
	spawnVortexRing(center, baseSize * 0.5, baseSize * 1.3, theme.Gold, 3, 180, 0.9)

	local orbRadius = baseSize * 1.7
	local goldOrb, goldState = spawnOrbitingOrb(center, theme.Gold, 16, 0, orbRadius)
	local cyanOrb, cyanState = spawnOrbitingOrb(center, theme.Cyan, 16, 180, orbRadius)

	Debris:AddItem(goldOrb, 2.5)
	Debris:AddItem(cyanOrb, 2.5)

	-- Orbit for a moment first.
	local orbitTween1 = TweenService:Create(
		goldState,
		TweenInfo.new(0.7, Enum.EasingStyle.Linear),
		{ Value = Vector3.new(360, orbRadius,0) }
	)
	local orbitTween2 = TweenService:Create(
		cyanState,
		TweenInfo.new(0.7, Enum.EasingStyle.Linear),
		{ Value = Vector3.new(540, orbRadius,0) }
	)
	orbitTween1:Play()
	orbitTween2:Play()

	task.delay(0.7, function()
		-- Then accelerate rapidly inward from opposite sides.
		local collideTween1 = TweenService:Create(
			goldState,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = Vector3.new(380, 0,0) }
		)
		local collideTween2 = TweenService:Create(
			cyanState,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = Vector3.new(560, 0,0) }
		)
		local shrinkGold = TweenService:Create(
			goldOrb,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.fromOffset(6, 6) }
		)
		local shrinkCyan = TweenService:Create(
			cyanOrb,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.fromOffset(6, 6) }
		)
		collideTween1:Play()
		collideTween2:Play()
		shrinkGold:Play()
		shrinkCyan:Play()

		collideTween1.Completed:Once(function()
			goldOrb:Destroy()
			cyanOrb:Destroy()

			-- Impact: white flash + a merged ring with a gold->cyan gradient.
			spawnScreenFlash(Color3.fromRGB(255, 255, 255), 0.7, 0.3)

			local mergeRing = Instance.new("Frame")
			mergeRing.Name = "FXMergeRing"
			mergeRing.AnchorPoint = Vector2.new(0.5, 0.5)
			mergeRing.Position = UDim2.fromOffset(center.X, center.Y)
			mergeRing.Size = UDim2.fromOffset(baseSize, baseSize)
			mergeRing.BackgroundTransparency = 1
			mergeRing.ZIndex = 500
			mergeRing.Parent = effectGui

			local mergeCorner = Instance.new("UICorner")
			mergeCorner.CornerRadius = UDim.new(1, 0)
			mergeCorner.Parent = mergeRing

			local mergeStroke = Instance.new("UIStroke")
			mergeStroke.Thickness = 6
			mergeStroke.Color = theme.Gold
			mergeStroke.Transparency = 0.05
			mergeStroke.Parent = mergeRing

			local mergeGradient = Instance.new("UIGradient")
			mergeGradient.Color = ColorSequence.new(theme.Gold, theme.Cyan)
			mergeGradient.Parent = mergeStroke

			local mergeGrow = TweenService:Create(
				mergeRing,
				TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(baseSize * 3.6, baseSize * 3.6) }
			)
			local mergeFade = TweenService:Create(
				mergeStroke,
				TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			)
			mergeGrow:Play()
			mergeFade:Play()
			Debris:AddItem(mergeRing, 0.7)

			spawnShardBurst(center, { theme.Gold, theme.Cyan }, 18, 55, 100, 0.6, 7)
			spawnRisingLabel(center, theme.Glyph .. " Twin Orbs Manifest!", theme.Gold, 19, 48, 0.85, theme.Cyan)
		end)
	end)
end

--------------------------------------------------------------
-- 6) essence_convergence -- the grandest effect: beams converge from every
--    edge of the screen, energy is pulled inward, then everything erupts
--    outward in a multi-ring, multi-phase burst.
--------------------------------------------------------------
local ESSENCE_CONVERGENCE_THEME = {
	Primary = Color3.fromRGB(198, 94, 224),
	Secondary = Color3.fromRGB(224, 197, 96),
	Core = Color3.fromRGB(255, 255, 255),
	Glyph = "❂",
}

local function playEssenceConvergence(node)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)
	local theme = ESSENCE_CONVERGENCE_THEME

	local camera = Workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(1280, 720)

	-- ---- PHASE 1: beams converge from every edge of the screen ----
	local edgePoints = {
		Vector2.new(center.X, -40),
		Vector2.new(center.X, viewport.Y + 40),
		Vector2.new(-40, center.Y),
		Vector2.new(viewport.X + 40, center.Y),
		Vector2.new(-40, -40),
		Vector2.new(viewport.X + 40, -40),
		Vector2.new(-40, viewport.Y + 40),
		Vector2.new(viewport.X + 40, viewport.Y + 40),
	}
	for i, edgePos in ipairs(edgePoints) do
		local color = (i % 2 == 0) and theme.Primary or theme.Secondary
		task.delay((i - 1) * 0.045, function()
			spawnEdgeBeam(edgePos, center, color, 4, 0.5)
		end)
	end

	-- Outer containment rings spin in while the beams travel.
	spawnVortexRing(center, baseSize * 0.7, baseSize * 2, theme.Primary, 4, 300, 1.0)
	spawnVortexRing(center, baseSize * 0.5, baseSize * 1.5, theme.Secondary, 3, -260, 0.9)

	task.delay(0.5, function()
		-- ---- PHASE 2: charge -- particles pulled inward, node glows hot ----
		spawnGlowPulse(center, baseSize * 2.2, baseSize * 0.7, theme.Core, 0.4, 0.35)

		for i = 1, 10 do
			local angle = math.random() * math.pi * 2
			local dist = math.random(90, 160)
			local startPos = center + Vector2.new(math.cos(angle), math.sin(angle)) * dist
			local color = (i % 2 == 0) and theme.Primary or theme.Secondary

			local mote = Instance.new("Frame")
			mote.Name = "FXEssenceMote"
			mote.AnchorPoint = Vector2.new(0.5, 0.5)
			mote.Position = UDim2.fromOffset(startPos.X, startPos.Y)
			mote.Size = UDim2.fromOffset(6, 6)
			mote.BackgroundColor3 = color
			mote.BorderSizePixel = 0
			mote.ZIndex = 498
			mote.Parent = effectGui

			local moteCorner = Instance.new("UICorner")
			moteCorner.CornerRadius = UDim.new(1, 0)
			moteCorner.Parent = mote

			local pull = TweenService:Create(
				mote,
				TweenInfo.new(0.3 + math.random() * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = UDim2.fromOffset(center.X, center.Y),
					Size = UDim2.fromOffset(1, 1),
					BackgroundTransparency = 1,
				}
			)
			pull:Play()
			Debris:AddItem(mote, 0.6)
		end

		playNodePunch(node, { Color = theme.Core }, 1.15)
	end)

	task.delay(0.85, function()
		-- ---- PHASE 3: convergence burst ----
		spawnScreenFlash(theme.Core, 0.9, 0.4)
		playNodePunch(node, { Color = theme.Primary }, 1.6)

		spawnRing(center, baseSize, baseSize * 3, theme.Core, 6, 0.4)
		spawnRing(center, baseSize, baseSize * 4.2, theme.Primary, 4, 0.6, 0.08)
		spawnRing(center, baseSize, baseSize * 5.4, theme.Secondary, 3, 0.75, 0.16)

		spawnAscensionBeam(center, baseSize * 0.7, theme.Primary, baseSize * 8, 1.0)
		spawnShardBurst(center, { theme.Primary, theme.Secondary, theme.Core }, 26, 65, 130, 0.75, 8)

		task.delay(0.15, function()
			-- ---- PHASE 4: aftermath ----
			spawnRisingLabel(
				center,
				theme.Glyph .. " Essence Converges!",
				theme.Primary,
				22,
				56,
				1.0,
				theme.Secondary
			)
			spawnGlowPulse(center, baseSize, baseSize * 1.8, theme.Primary, 0.2, 1.2)
		end)
	end)
end

--============================================================
-- SPECIAL UPGRADE LOOKUP
--============================================================
local SPECIAL_UPGRADE_EFFECTS = {
	root_awakening = playRootAwakening,
	manual_storm_summon = playManualStormSummon,
	core_resilience = playCoreResilience,
	storm_caller_ascension = playStormCallerAscension,
	twin_orb_manifestation = playTwinOrbManifestation,
	essence_convergence = playEssenceConvergence,
}

--============================================================
-- PUBLIC API
--============================================================

-- Play the full purchase effect on `node`, themed by `category`.
-- If `upgradeId` matches one of the rare upgrades in
-- SPECIAL_UPGRADE_EFFECTS above, the deluxe version plays instead of the
-- standard category-themed burst.
function PurchaseEffect.Play(node, category, upgradeId)
	if not node or not node:IsA("GuiObject") then
		return
	end

	if upgradeId and SPECIAL_UPGRADE_EFFECTS[upgradeId] then
		SPECIAL_UPGRADE_EFFECTS[upgradeId](node)
		return
	end

	local theme = getTheme(category)
	local center = getNodeCenter(node)
	local baseSize = math.max(node.AbsoluteSize.X, node.AbsoluteSize.Y)

	playNodePunch(node, theme)
	playShockwave(center, baseSize, theme)
	playShards(center, theme, 8)
	playRisingLabel(center, theme)
end

-- Explicitly play one of the rare deluxe effects by id, bypassing the
-- category lookup entirely. Useful for testing a specific effect.
function PurchaseEffect.PlaySpecial(node, upgradeId)
	if not node or not node:IsA("GuiObject") then
		return
	end

	local fx = SPECIAL_UPGRADE_EFFECTS[upgradeId]
	if fx then
		fx(node)
	end
end

return PurchaseEffect
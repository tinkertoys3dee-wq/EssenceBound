--[[
	CollectionRing.lua (LocalScript)
	Place in: StarterPlayerScripts (or StarterGui)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RP = game:GetService("ReplicatedStorage")
local Remotes = RP:WaitForChild("Remotes")
local CollectionUpgrades = require(RP:WaitForChild("CollectionUpgrades"))

-- ============================================================
-- CONFIG
-- ============================================================
local ATTRIBUTE_NAME = "Collectible"
local MainGui = playerGui:WaitForChild("MainGui")
local SEARCH_ROOT = MainGui:WaitForChild("Center", 5)
	and MainGui.Center:WaitForChild("LargeOrbFolder", 5)
	and MainGui.Center.LargeOrbFolder:WaitForChild("OrbClickables", 5)

-- Was 20. This is the actual hit-target for the single skill the whole
-- game gates its first reward behind: hovering the ring over a moving,
-- idly-orbiting drop. At 20px (10px radius) that target was small enough
-- that a huge share of new players -- by measured data, roughly two thirds
-- of everyone who's ever played -- never once landed a collection, click
-- the great orb though they might. collection_radius_1/2 still add on top
-- of this exactly as before; this only raises the un-upgraded floor so a
-- first attempt has a real chance of landing.
local BASE_RING_SIZE = 30 -- diameter before any collection_radius upgrades are applied
local RING_COLOR = Color3.fromRGB(229, 229, 229)
local RING_THICKNESS = 3
local FOLLOW_LERP = 1

-- ============================================================
-- CHARGE CONFIG — the ring has to "fill in" (sweep from empty to a full
-- circle) while orbs sit inside it before it triggers a collection.
-- swift_collection_1/2 (GetCollectionSpeedBonus) shave time off this.
-- essence_magnet_field (HasAutoCollect) skips the charge entirely.
-- ============================================================
-- Was 0.9, then 0.5. This sits directly in the path of every single reward
-- in the game, from a brand-new player's very first orb through to a maxed
-- account's ten-thousandth -- it's the single biggest lever on how snappy
-- the whole core loop feels. swift_collection_1/2 can shave off up to
-- 2.3s combined (10*0.09 + 10*0.14), so the upgrade path still comfortably
-- reaches MIN_CHARGE_TIME well before being maxed; this change doesn't
-- reduce how meaningful that upgrade line is. Lowered again alongside the
-- BASE_RING_SIZE bump above -- a bigger target that still takes half a
-- second to fill is easy to lose to the orb's own idle-orbit drift before
-- a first-time player even realizes the ring is charging.
local BASE_CHARGE_TIME = 0.4 -- seconds to fill the ring with 0 swift_collection levels
local MIN_CHARGE_TIME = 0.15 -- charge time can never be reduced below this
local PROGRESS_RING_COLOR = Color3.fromRGB(255, 221, 84)
local PROGRESS_RING_THICKNESS = RING_THICKNESS + 1

local ABBREVIATIONS = {
	"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No"
}

local function formatNumber(value: number): string
	local absValue = math.abs(value)
	if absValue < 1000 then
		return tostring(value)
	end

	local index = math.floor(math.log10(absValue) / 3)
	if index >= #ABBREVIATIONS then
		index = #ABBREVIATIONS - 1
	end

	local shortValue = value / (10 ^ (index * 3))
	local formatted = string.format("%.2f", shortValue)
	formatted = string.gsub(formatted, "%.?0+$", "")

	return formatted .. ABBREVIATIONS[index + 1]
end

-- ============================================================
-- RING UI — parented DIRECTLY inside MainGui (same ScreenGui as the
-- orbs), NOT a separate ScreenGui. This guarantees the ring and the
-- orbs share the exact same inset/canvas behavior, no matter what
-- MainGui.IgnoreGuiInset is set to or how nested Scale layouts react
-- to it — there's only one ScreenGui's behavior to reason about now.
-- ============================================================
local ring = Instance.new("Frame")
ring.Name = "CollectionRing"
ring.AnchorPoint = Vector2.new(0.5, 0.5)
ring.Size = UDim2.new(0, BASE_RING_SIZE, 0, BASE_RING_SIZE)
ring.BackgroundTransparency = .7
ring.ZIndex = 1000 -- high enough to sit above orbs; raise further if needed
ring.Parent = MainGui

local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = ring

local ringStroke = Instance.new("UIStroke")
ringStroke.Thickness = RING_THICKNESS
ringStroke.Color = RING_COLOR
ringStroke.Transparency = 0.15
ringStroke.Parent = ring

-- ============================================================
-- CHARGE PROGRESS RING — a second circle stacked on top of `ring`.
-- Its UIStroke has a UIGradient with a hard-edged Transparency cutoff;
-- moving the cutoff point sweeps how much of the circle is visible,
-- which is what makes it read as a ring "filling in" as charge builds.
-- ============================================================
local progressRing = Instance.new("Frame")
progressRing.Name = "CollectionProgressRing"
progressRing.AnchorPoint = Vector2.new(0.5, 0.5)
progressRing.Size = ring.Size
progressRing.BackgroundTransparency = 1
progressRing.ZIndex = ring.ZIndex + 1
progressRing.Parent = MainGui

local progressCorner = Instance.new("UICorner")
progressCorner.CornerRadius = UDim.new(1, 0)
progressCorner.Parent = progressRing

local progressStroke = Instance.new("UIStroke")
progressStroke.Thickness = PROGRESS_RING_THICKNESS
progressStroke.Color = PROGRESS_RING_COLOR
progressStroke.Transparency = 0
progressStroke.Parent = progressRing

local progressGradient = Instance.new("UIGradient")
progressGradient.Rotation = -90 -- start the sweep at the top (12 o'clock) of the ring
progressGradient.Parent = progressStroke

-- Moves the visible/invisible cutoff around the ring. progress = 0 -> fully
-- hidden, progress = 1 -> fully visible (a complete ring).
local function setProgressGradient(progress)
	local p = math.clamp(progress, 0.0001, 0.9999)
	progressGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(p, 0),
		NumberSequenceKeypoint.new(p, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end
setProgressGradient(0)

-- ============================================================
-- RING SIZE — driven by CollectionUpgrades (collection_radius_1/2).
-- CHARGE TIME — driven by CollectionUpgrades (swift_collection_1/2).
-- Both are recalculated whenever a relevant upgrade attribute changes.
-- ============================================================
local ringRadius = BASE_RING_SIZE / 2
local chargeTime = BASE_CHARGE_TIME

local function updateRingSize()
	local diameter = CollectionUpgrades.GetRingSize(player, BASE_RING_SIZE)
	ring.Size = UDim2.new(0, diameter, 0, diameter)
	progressRing.Size = UDim2.new(0, diameter, 0, diameter)
	ringRadius = diameter / 2
end

local function updateChargeTime()
	local speedBonus = CollectionUpgrades.GetCollectionSpeedBonus(player)
	chargeTime = math.max(MIN_CHARGE_TIME, BASE_CHARGE_TIME - speedBonus)
end

local function onCollectionUpgradesChanged()
	updateRingSize()
	updateChargeTime()
end

onCollectionUpgradesChanged()
CollectionUpgrades.WatchAll(player, onCollectionUpgradesChanged)

-- ============================================================
-- MOUSE POSITIONING (live inset check — never goes stale)
-- ============================================================
local function getMouseInMainGuiSpace()
	local mouseLoc = UserInputService:GetMouseLocation()
	-- Read live, every frame — if you toggle IgnoreGuiInset mid-playtest
	-- this adapts immediately instead of using a value cached at script start.
	if not MainGui.IgnoreGuiInset then
		mouseLoc = mouseLoc - GuiService:GetGuiInset()
	end
	return mouseLoc
end

-- ============================================================
-- PUBLIC EVENTS
-- ============================================================

local CurrentlyInside = {}

-- ============================================================
-- COLLECTIBLE TRACKING (event-driven, not scanned every frame)
-- ============================================================
local collectibleObjects = {}
local collectibleIndex = {}
local function addCollectible(obj)
	if collectibleIndex[obj] then return end
	collectibleObjects[#collectibleObjects + 1] = obj
	collectibleIndex[obj] = #collectibleObjects
end

local function removeCollectible(obj)
	local idx = collectibleIndex[obj]
	if not idx then return end

	local lastIdx = #collectibleObjects
	local lastObj = collectibleObjects[lastIdx]

	collectibleObjects[idx] = lastObj
	collectibleIndex[lastObj] = idx
	collectibleObjects[lastIdx] = nil
	collectibleIndex[obj] = nil

	if CurrentlyInside[obj] then
		CurrentlyInside[obj] = nil
	end
end

local function syncCollectible(obj)
	if obj:GetAttribute(ATTRIBUTE_NAME) then
		addCollectible(obj)
	else
		removeCollectible(obj)
	end
end

local collectionFireable = Remotes:WaitForChild("Collection")

local Destro = SEARCH_ROOT.Parent:WaitForChild("Destro")

local TweenService = game:GetService("TweenService")

local DUST_COUNT = 7
local DUST_COLOR = Color3.fromRGB(100, 98, 90)


local function spawnDustParticle(parent, originPosition, baseZIndex, tint)
	local dust = Instance.new("Frame")
	dust.Name = "CollectDust"
	dust.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Tinted to the essence being collected. The old flat grey read as
	-- smoke rather than essence and muddied the collection moment.
	dust.BackgroundColor3 = tint or DUST_COLOR
	dust.BackgroundTransparency = 0.15
	dust.BorderSizePixel = 0
	dust.ZIndex = baseZIndex + 1
	dust.Position = originPosition

	local size = math.random(4, 10)
	dust.Size = UDim2.new(0, size, 0, size)
	dust.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dust

	-- Randomized upward drift with horizontal sway, so particles don't move in unison
	local driftX = math.random(-28, 28)
	local driftY = -math.random(40, 80) -- negative Y = rises
	local duration = 0.8 + math.random() * 0.5

	local tween = TweenService:Create(
		dust,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			Position = originPosition + UDim2.new(0, driftX, 0, driftY),
			BackgroundTransparency = 1,
			Size = UDim2.new(0, size * 0.25, 0, size * 0.25),
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		dust:Destroy()
	end)
end
local EssenceMulti = require(RP:WaitForChild("EssenceMultiplier"))

local newDiscovery = game:GetService("ReplicatedStorage"):WaitForChild("EssenceDiscovered")
local GetEssences = require(game:GetService("ReplicatedStorage"):WaitForChild("GetEssence"))

-- =========================================================================
-- COLLECTION FEEL
-- =========================================================================
-- Collecting is the payoff beat of the whole loop and it was landing
-- almost silently: a grey dust puff and a "+N". Everything below is
-- cosmetic only -- what the orb is actually worth is decided server-side.

local Juice = require(RP:WaitForChild("Juice"))
local juiceLayer = Juice.GetLayer(playerGui)

local ORB_TINTS = {
	["Earth Essence"] = Color3.fromRGB(120, 240, 160),
	["Shadow Essence"] = Color3.fromRGB(170, 130, 255),
}
local CRIT_GOLD = Color3.fromRGB(255, 205, 80)

local collectSound = Juice.FindSound("SFX/UI/UIPop")

-- Rapid collection climbs in pitch the same way the orb click does, so a
-- big harvest reads as a rising run of notes rather than one repeated
-- blip. Cosmetic only.
local collectStreak = 0
local lastCollectAt = 0

local function playCollectFeel(orb, isCrit, isGolden)
	local now = os.clock()
	if (now - lastCollectAt) <= 0.8 then
		collectStreak = math.min(collectStreak + 1, 16)
	else
		collectStreak = 1
	end
	lastCollectAt = now

	if not juiceLayer then
		return
	end

	local center = Juice.CenterOf(orb, juiceLayer)
	if not center then
		return
	end

	local tint = ORB_TINTS[orb:GetAttribute("OrbType")] or ORB_TINTS["Earth Essence"]
	if isCrit or isGolden then
		tint = CRIT_GOLD
	end

	if collectSound then
		Juice.PlaySound(collectSound, {
			Pitch = Juice.PitchForStreak(collectStreak, 18) * (isCrit and 1.25 or 1),
			Volume = isCrit and 0.5 or 0.32,
		})
	end

	Juice.Ring(juiceLayer, center, {
		Color = tint,
		StartSize = isCrit and 34 or 24,
		EndSize = isCrit and 130 or 78,
		Duration = 0.4,
		Thickness = isCrit and 3 or 2,
	})

	Juice.Burst(juiceLayer, center, {
		Count = isCrit and 12 or 5,
		Colors = { tint, Color3.fromRGB(255, 255, 255) },
		Distance = isCrit and 130 or 60,
		Duration = 0.5,
		Size = isCrit and { 5, 11 } or { 3, 7 },
	})

	-- A crit previously looked identical to any other collection once the
	-- orb was gone. Now it announces itself.
	if isCrit then
		Juice.FloatText(juiceLayer, center, "CRITICAL!", {
			Color = CRIT_GOLD,
			Duration = 0.85,
			Rise = 80,
			TextSize = 30,
		})
	end
end

local function CollectEffect(orb)
	if not orb or not orb.Parent then return end
	orb:SetAttribute("Bail", true)

	local essenceValue = orb:GetAttribute("EssenceValue") or 1
	local isCrit = orb:GetAttribute("IsCrit")
	local isGolden = orb:GetAttribute("IsGolden")

	-- Read the orb's on-screen position BEFORE it's reparented into
	-- Destro, otherwise the effects spawn wherever that folder happens to
	-- resolve to rather than where the player actually saw the orb.
	pcall(playCollectFeel, orb, isCrit, isGolden)

	orb.Parent = Destro
	collectionFireable:FireServer(orb:GetAttribute("OrbType"), essenceValue, isCrit, isGolden)
	
	if orb:GetAttribute("OrbType") == "Shadow Essence" then
		local discovered = player:GetAttribute("ShadowEssenceDiscovered") or false
		if not discovered then
			newDiscovery:Fire(orb:GetAttribute("OrbType"), GetEssences.GetOddsText(orb:GetAttribute("OrbType")))
		end
	elseif orb:GetAttribute("OrbType") == "Earth Essence" then
		local discovered = player:GetAttribute("EarthEssenceDiscovered") or false
		if not discovered then
			newDiscovery:Fire(orb:GetAttribute("OrbType"), GetEssences.GetOddsText(orb:GetAttribute("OrbType")))
		end
	end
	if orb:FindFirstChild("Shadow") then
		orb:FindFirstChild("Shadow"):Destroy()
	end
	local TextLabel = orb:FindFirstChild("Gain")
	local Stroke = TextLabel:WaitForChild("UIStroke")

	TextLabel.Text = "+"..formatNumber(math.floor(EssenceMulti.CalculateMultiplier(player,orb:GetAttribute("IsGolden"),orb:GetAttribute("IsCrit")) * essenceValue))
	local container = orb.Parent
	local imageLabel = orb:FindFirstChildWhichIsA("ImageLabel", true)
		or orb:FindFirstChild("MainClickable")

	local startPos = orb.Position
	local floatUpPos = startPos - UDim2.new(0, 0, 0, 35) -- float up 20px
	local TextUpPos = TextLabel.Position - UDim2.new(0, 0, 0, 15)

	-- === Phase 1: float up + brighten ===
	local floatTween = TweenService:Create(
		orb,
		TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = floatUpPos }
	)

	local LabelFloat = TweenService:Create(
		TextLabel,
		TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = TextUpPos }
	)

	local StrokeIn = TweenService:Create(
		Stroke,
		TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = .3 }
	)

	local LabelIn = TweenService:Create(
		TextLabel,
		TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 0.3 }
	)

	local brightenTween
	if imageLabel then
		brightenTween = TweenService:Create(
			imageLabel,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ ImageColor3 = Color3.fromRGB(251, 255, 0) }
		)
	end
	LabelFloat:Play()
	floatTween:Play()
	LabelIn:Play()
	StrokeIn:Play()
	if brightenTween then brightenTween:Play() end

	floatTween.Completed:Connect(function()
		if not orb or not orb.Parent then return end
		local shrinkTween = TweenService:Create(
			orb,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, 0, 0, 0) }
		)

		local imageFadeTween
		local StrokeFade
		local LabelFade
		if imageLabel then
			StrokeFade = TweenService:Create(
				Stroke,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			)
			LabelFade = TweenService:Create(
				TextLabel,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			)
			imageFadeTween = TweenService:Create(
				imageLabel,
				TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ ImageTransparency = 1 }
			)
		end

		shrinkTween:Play()
		if imageFadeTween then imageFadeTween:Play() end

		-- Dust/smoke burst rising out of the fading orb, staggered slightly
		local dustOrigin = orb.Position
		local baseZ = orb.ZIndex or 1
		local dustTint = ORB_TINTS[orb:GetAttribute("OrbType")] or DUST_COLOR
		if isCrit or isGolden then
			dustTint = CRIT_GOLD
		end

		for i = 1, DUST_COUNT do
			task.delay(math.random() * 0.18, function()
				if container and container.Parent then
					spawnDustParticle(container, dustOrigin, baseZ, dustTint)
				end
			end)
		end

		shrinkTween.Completed:Connect(function()
			if orb and orb.Parent then
				orb:Destroy()
			end
		end)
	end)
end
local function watch(obj)
	if player:GetAttribute(1907677938) then
		task.wait(.3)
		CollectEffect(obj)
	else
		syncCollectible(obj)

		obj:GetAttributeChangedSignal(ATTRIBUTE_NAME):Connect(function()
			syncCollectible(obj)
		end)
	end
end

for _, obj in ipairs(SEARCH_ROOT:GetChildren()) do
	watch(obj)
end

SEARCH_ROOT.ChildAdded:Connect(function(child)
	task.delay(0.2, watch, child)
end)

SEARCH_ROOT.ChildRemoved:Connect(removeCollectible)

-- ============================================================
-- DETECTION — compares ring.AbsolutePosition against orb.AbsolutePosition,
-- both resolved live by Roblox's own layout engine. Since both are now
-- children of the SAME ScreenGui, they're guaranteed to share a
-- coordinate space regardless of any nested Scale/UIScale/AspectRatio
-- quirks elsewhere in the tree. ringRadius itself now comes from
-- CollectionUpgrades and is kept current by updateRingSize() above.
-- ============================================================

local function isOverlapping(obj, ringCenterX, ringCenterY)
	if not obj.Visible then return false, nil, nil, nil end

	local pos = obj.AbsolutePosition
	local size = obj.AbsoluteSize
	local objCenterX = pos.X + size.X * 0.5
	local objCenterY = pos.Y + size.Y * 0.5
	local objRadius = (size.X > size.Y and size.X or size.Y) * 0.5

	local dx = objCenterX - ringCenterX
	local dy = objCenterY - ringCenterY
	local radiusSum = ringRadius + objRadius
	local distSq = dx * dx + dy * dy

	return distSq <= (radiusSum * radiusSum), objCenterX, objCenterY, math.sqrt(distSq)
end

-- ============================================================
-- CHARGE STATE — chargeProgress climbs from 0 -> 1 while any collectible
-- sits inside the ring, driving the progress ring's sweep. Hitting 1
-- collects every orb currently inside the radius in one batch, then
-- resets. essence_magnet_field (HasAutoCollect) skips all of this and
-- collects orbs the instant they enter, same as the old behavior.
-- ============================================================
local chargeProgress = 0

-- Set true for a few seconds at a time by the Chrono Rift relic (see the
-- bottom of this file). Declared here because updateCollection below reads
-- it every frame -- the relic only ever writes it.
local chronoRiftActive = false

local function updateCollection(ringCenterX, ringCenterY, deltaTime)
	-- Chrono Rift grants the SAME instant-collection behaviour the
	-- essence_magnet_field upgrade permanently unlocks, just temporarily --
	-- reusing that exact path rather than adding a parallel one means the
	-- rift can't drift out of sync with how auto-collect actually works.
	local hasAutoCollect = CollectionUpgrades.HasAutoCollect(player) or chronoRiftActive
	local anyOverlap = false
	local toCollect = {}

	-- Pass 1: classify overlap state only. No mutation of collectibleObjects
	-- here, since CollectEffect reparents orbs and would otherwise be
	-- mutating the array we're iterating over.
	--print(collectibleObjects)
	for _, obj in ipairs(collectibleObjects) do
		
		local overlapping = isOverlapping(obj, ringCenterX, ringCenterY)
		local wasInside = CurrentlyInside[obj]
		if overlapping then
			anyOverlap = true
			if hasAutoCollect and not wasInside then
				toCollect[#toCollect + 1] = obj
			end
			CurrentlyInside[obj] = true
		elseif wasInside then
			CurrentlyInside[obj] = nil
		end
	end

	if hasAutoCollect then
		-- essence_magnet_field: no dwell/hover required, so the charge ring
		-- stays empty and orbs collect the instant they enter the radius.
		chargeProgress = 0
		setProgressGradient(0)
	else
		if anyOverlap then
			chargeProgress = math.min(chargeProgress + deltaTime / chargeTime, 1)
		else
			chargeProgress = 0
		end
		setProgressGradient(chargeProgress)

		if chargeProgress >= 1 then
			print("done")
			-- Ring complete: collect everything currently inside the radius.
			for _, obj in ipairs(collectibleObjects) do
				if CurrentlyInside[obj] then
					toCollect[#toCollect + 1] = obj
					CurrentlyInside[obj] = nil
				end
			end
			chargeProgress = 0
			setProgressGradient(0)
		end
	end

	-- Pass 2: actually collect, now that we're done iterating collectibleObjects.
	for _, obj in ipairs(toCollect) do
		CollectEffect(obj)
	end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
local smoothedPos = nil

RunService.RenderStepped:Connect(function(deltaTime)
	local targetPos = getMouseInMainGuiSpace()
	smoothedPos = smoothedPos and smoothedPos:Lerp(targetPos, FOLLOW_LERP) or targetPos

	ring.Position = UDim2.new(0, smoothedPos.X, 0, smoothedPos.Y)
	progressRing.Position = ring.Position

	-- Use the ring's OWN resolved AbsolutePosition for detection, not the
	-- raw smoothedPos value — this way any layout quirk that affects the
	-- ring also automatically shows up identically for comparison.
	local rp = ring.AbsolutePosition
	updateCollection(rp.X + ringRadius, rp.Y + ringRadius, deltaTime)
end)

-- =========================================================================
-- VOID LASER (Sanctum relic: sanctum_laser)
-- =========================================================================
-- Periodically sweeps a beam across the field and force-collects every orb
-- currently active -- through the exact same CollectEffect() a normal
-- hover-collection already uses, so payout goes through the identical,
-- already-trusted path. Purely a periodic BONUS on top of normal play; the
-- player does nothing to trigger it.

local SanctumUpgrades = require(RP:WaitForChild("SanctumUpgrades"))

local LASER_COLOR = Color3.fromRGB(150, 90, 255)

local function playLaserSweep()
	-- Snapshot BEFORE the visual, not after: the sweep takes real time, and
	-- collecting only what existed at the moment the laser fired -- rather
	-- than also mopping up anything that spawns mid-animation -- keeps the
	-- reward tied to what the player actually had on screen, not to how
	-- long the beam happens to take to cross it.
	--
	-- Bail is checked here even though CollectEffect sets it too: this
	-- protects against a race where the ring's own updateCollection has
	-- already queued the same orb for collection on this exact frame,
	-- before its removal from collectibleObjects (which only happens once
	-- the reparent to Destro actually fires ChildRemoved) has gone through
	-- -- without this check, that orb could get CollectEffect called on it
	-- twice and be paid out twice for one collection.
	local targets = {}
	for _, obj in ipairs(collectibleObjects) do
		if obj.Parent and not obj:GetAttribute("Bail") then
			table.insert(targets, obj)
		end
	end

	if juiceLayer then
		local ok = pcall(function()
			local beam = Instance.new("Frame")
			beam.Name = "LaserRelic"
			beam.AnchorPoint = Vector2.new(0.5, 0.5)
			beam.Position = UDim2.fromScale(-0.1, 0.5)
			beam.Size = UDim2.new(0.045, 0, 1.5, 0)
			beam.Rotation = 12
			beam.BackgroundColor3 = LASER_COLOR
			beam.BackgroundTransparency = 0.15
			beam.BorderSizePixel = 0
			beam.ZIndex = 85
			beam.Parent = juiceLayer

			local edgeGlow = Instance.new("UIStroke")
			edgeGlow.Thickness = 6
			edgeGlow.Color = Color3.fromRGB(255, 255, 255)
			edgeGlow.Transparency = 0.35
			edgeGlow.Parent = beam

			local sweep = TweenService:Create(
				beam,
				TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
				{ Position = UDim2.fromScale(1.1, 0.5) }
			)
			sweep:Play()
			sweep.Completed:Wait()

			beam:Destroy()
		end)

		if not ok then
			warn("[CursorCollection] Laser sweep FX errored, continuing to the actual reward.")
		end
	end

	-- Re-checked at the moment of collection too, not just at snapshot
	-- time -- the sweep's ~0.45s runtime is enough for the player's own
	-- ring to have legitimately collected one of these in the meantime.
	for _, obj in ipairs(targets) do
		if obj.Parent and not obj:GetAttribute("Bail") then
			CollectEffect(obj)
		end
	end

	if juiceLayer then
		Juice.FloatText(juiceLayer, UDim2.fromScale(0.5, 0.42), "VOID SWEEP!", {
			Color = LASER_COLOR,
			Duration = 1,
			Rise = 60,
			TextSize = 28,
		})
	end

	local sound = Juice.FindSound("SFX/UI/UIPop")
	if sound then
		Juice.PlaySound(sound, { Pitch = 1.4, Volume = 0.45 })
	end
end

-- =========================================================================
-- LASER COUNTDOWN PILL
-- =========================================================================
-- Same reasoning as the Hammer's countdown in OrbClicker.client.luau:
-- watching a timer count down is most of what makes a periodic ability
-- feel worth having.
--
-- Registered into Juice's shared relic bar (bottom-center, auto-laid-out)
-- rather than built as a one-off ScreenGui here -- see the Hammer's
-- equivalent comment in OrbClicker.client.luau for why. Order 2 = second
-- from the left, after the Hammer.

local laserParts = Juice.RegisterRelicPill(playerGui, {
	Name = "Laser",
	Icon = "🌌",
	Color = LASER_COLOR,
	Order = 2,
})
local laserPill = laserParts.Pill
local laserPillFill = laserParts.Fill
local laserPillLabel = laserParts.Label

task.spawn(function()
	-- Blocks here, no polling, until the player owns any level of the
	-- Laser -- GetAttributeChangedSignal only wakes this thread on an
	-- actual purchase.
	while (player:GetAttribute("sanctum_laser") or 0) <= 0 do
		player:GetAttributeChangedSignal("sanctum_laser"):Wait()
	end

	laserPill.Visible = true

	while true do
		local level = player:GetAttribute("sanctum_laser") or 0
		local relicData = SanctumUpgrades.GetRelicLevelData("sanctum_laser", level)

		if not relicData then
			-- Shouldn't happen once level >= 1, but never busy-loop on a
			-- bad read.
			task.wait(5)
		else
			-- Ticks in 1-second steps rather than one blocking wait, purely
			-- so the pill above can count down live.
			local total = relicData.Interval
			local remaining = total

			while remaining > 0 do
				laserPillLabel.Text = ("🌌 %ds"):format(math.ceil(remaining))
				laserPillFill.Size = UDim2.fromScale(math.clamp(1 - (remaining / total), 0, 1), 1)

				local step = math.min(1, remaining)
				task.wait(step)
				remaining -= step
			end

			laserPillLabel.Text = "🌌 NOW!"
			laserPillFill.Size = UDim2.fromScale(1, 1)
			Juice.Punch(Juice.GetScale(laserPill), 0.25, 0.3)

			local ok, err = pcall(playLaserSweep)
			if not ok then
				warn("[CursorCollection] Laser sweep errored: " .. tostring(err))
			end
		end
	end
end)

-- =========================================================================
-- CHRONO RIFT (Sanctum relic: sanctum_chrono_rift)
-- =========================================================================
-- Periodically opens a window where collection is instant -- no hover
-- charge at all. Unlike the Hammer (spawns orbs) and the Laser (collects
-- what exists), this grants a temporary STATE, so for its duration the
-- whole loop plays differently: sweep the cursor and everything it
-- touches is gathered immediately.

local RIFT_COLOR = Color3.fromRGB(120, 255, 235)

-- Registered into Juice's shared relic bar, same as the Hammer and Laser
-- above -- see the Hammer's comment in OrbClicker.client.luau for why.
-- Order 3 = third from the left.
local riftParts = Juice.RegisterRelicPill(playerGui, {
	Name = "Rift",
	Icon = "⌛",
	Color = RIFT_COLOR,
	Order = 3,
})
local riftPill = riftParts.Pill
local riftPillFill = riftParts.Fill
local riftPillLabel = riftParts.Label

-- Full-screen tint shown only while the rift window is open, so the
-- altered state is unmistakable rather than something the player has to
-- infer from orbs behaving differently. Parented into the shared FX layer
-- rather than the relic bar's ScreenGui -- it isn't a bar element, and
-- juiceLayer already exists in this file for exactly this kind of
-- transient full-screen effect.
local riftOverlay = Instance.new("Frame")
riftOverlay.Name = "RiftOverlay"
riftOverlay.Size = UDim2.fromScale(1, 1)
riftOverlay.BackgroundColor3 = RIFT_COLOR
riftOverlay.BackgroundTransparency = 1
riftOverlay.BorderSizePixel = 0
riftOverlay.Visible = false
riftOverlay.ZIndex = 1
riftOverlay.Parent = juiceLayer

local function openChronoRift(windowSeconds)
	chronoRiftActive = true

	riftOverlay.Visible = true
	riftOverlay.BackgroundTransparency = 1
	TweenService:Create(riftOverlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.88 }):Play()

	if juiceLayer then
		Juice.FloatText(juiceLayer, UDim2.fromScale(0.5, 0.3), "CHRONO RIFT!", {
			Color = RIFT_COLOR,
			Duration = 1.3,
			Rise = 70,
			TextSize = 34,
		})
	end

	local sound = Juice.FindSound("SFX/UI/UIPop")
	if sound then
		Juice.PlaySound(sound, { Pitch = 1.7, Volume = 0.5 })
	end

	-- Counts the window down in the pill too, so the player can see how
	-- much of the instant-collect state is left rather than guessing.
	local remaining = windowSeconds
	while remaining > 0 do
		riftPillLabel.Text = ("⌛ %ds LEFT"):format(math.ceil(remaining))
		riftPillFill.Size = UDim2.fromScale(math.clamp(remaining / windowSeconds, 0, 1), 1)

		local step = math.min(0.5, remaining)
		task.wait(step)
		remaining -= step
	end

	chronoRiftActive = false

	local fadeOut = TweenService:Create(riftOverlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
	fadeOut:Play()
	fadeOut.Completed:Connect(function()
		-- Guarded: a second rift may have opened during the fade, and
		-- hiding the overlay then would blank an active window.
		if not chronoRiftActive then
			riftOverlay.Visible = false
		end
	end)
end

task.spawn(function()
	while (player:GetAttribute("sanctum_chrono_rift") or 0) <= 0 do
		player:GetAttributeChangedSignal("sanctum_chrono_rift"):Wait()
	end

	riftPill.Visible = true

	while true do
		local level = player:GetAttribute("sanctum_chrono_rift") or 0
		local relicData = SanctumUpgrades.GetRelicLevelData("sanctum_chrono_rift", level)

		if not relicData then
			task.wait(5)
		else
			local total = relicData.Interval
			local remaining = total

			while remaining > 0 do
				riftPillLabel.Text = ("⌛ %ds"):format(math.ceil(remaining))
				riftPillFill.Size = UDim2.fromScale(math.clamp(1 - (remaining / total), 0, 1), 1)

				local step = math.min(1, remaining)
				task.wait(step)
				remaining -= step
			end

			local currentLevel = player:GetAttribute("sanctum_chrono_rift") or 0
			local currentData = SanctumUpgrades.GetRelicLevelData("sanctum_chrono_rift", currentLevel)
			if currentData then
				Juice.Punch(Juice.GetScale(riftPill), 0.25, 0.3)

				local ok, err = pcall(openChronoRift, currentData.WindowSeconds)
				if not ok then
					-- Never leave the rift stuck on if the visual half
					-- errored partway through -- that would be a permanent
					-- free auto-collect.
					chronoRiftActive = false
					riftOverlay.Visible = false
					warn("[CursorCollection] Chrono Rift errored: " .. tostring(err))
				end
			end
		end
	end
end)

-- =========================================================================
-- GRAVITY WELL (Prestige Shop: rebirthshop_gravitywell)
-- =========================================================================
-- Unlike the four relics above, this isn't a Sanctum purchase -- it's
-- bought with Rebirth Currency in the Prestige Shop (RebirthShopUpgrades).
-- Same "periodic, automatic, visual" shape though, so it gets the exact
-- same countdown-pill treatment via Juice.RegisterRelicPill.
--
-- Every Interval seconds, nearby same-type orbs already sitting in the
-- field are pulled together and FUSED into one bigger orb worth more than
-- their sum. Deliberately a periodic PULSE rather than continuous
-- per-frame drifting: each orb already runs its own per-frame homing
-- animation (magnet pull toward the cursor, orbit/bob -- see SpawnOrb in
-- OrbClicker.client.luau), and a second system fighting that same
-- Position every frame would just jitter. A pulse sidesteps that
-- entirely -- it reads each orb's position once, then only ever touches
-- attributes (EssenceValue/IsCrit/IsGolden) and Bail/Destroy on the
-- consumed orbs, exactly the same handoff CollectEffect already uses.

local RebirthShopUpgrades
do
	local module = RP:FindFirstChild("RebirthShopUpgrades") or RP:WaitForChild("RebirthShopUpgrades", 10)
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			RebirthShopUpgrades = result
		end
	end
end

local GRAVITY_WELL_COLOR = Color3.fromRGB(255, 165, 60)

local gravityWellParts = Juice.RegisterRelicPill(playerGui, {
	Name = "GravityWell",
	Icon = "🌀",
	Color = GRAVITY_WELL_COLOR,
	Order = 5,
})
local gravityWellPill = gravityWellParts.Pill
local gravityWellPillFill = gravityWellParts.Fill
local gravityWellPillLabel = gravityWellParts.Label

-- Single-linkage clustering: any orb within MergeRadius of ANY orb already
-- in a cluster joins it. O(n^2) over currently-eligible orbs, which is
-- fine at the field's real size (BASE_MAX_ACTIVE_ORBS is 40, and only a
-- fraction of those are ever the same OrbType and already landed).
local function clusterByProximity(orbs, mergeRadius)
	local clusters = {}
	local assigned = {}

	for i, orb in ipairs(orbs) do
		if not assigned[orb] then
			local cluster = { orb }
			assigned[orb] = true

			-- Re-scan from the start each time a member is added, so a
			-- chain (A near B, B near C, A far from C) still merges as one
			-- cluster instead of only catching direct neighbors of the seed.
			local growing = true
			while growing do
				growing = false
				for _, candidate in ipairs(orbs) do
					if not assigned[candidate] then
						for _, member in ipairs(cluster) do
							local dx = candidate.AbsolutePosition.X - member.AbsolutePosition.X
							local dy = candidate.AbsolutePosition.Y - member.AbsolutePosition.Y
							if (dx * dx + dy * dy) <= (mergeRadius * mergeRadius) then
								table.insert(cluster, candidate)
								assigned[candidate] = true
								growing = true
								break
							end
						end
					end
				end
			end

			table.insert(clusters, cluster)
		end
	end

	return clusters
end

local function performGravityWellPulse(data)
	-- Group eligible orbs (landed, not already mid-collection) by type --
	-- orbs of different currencies can't sensibly fuse into one payout.
	local byType = {}
	for _, obj in ipairs(collectibleObjects) do
		if obj.Parent and obj.Visible and obj:GetAttribute("Collectible") and not obj:GetAttribute("Bail") then
			local orbType = obj:GetAttribute("OrbType") or "?"
			byType[orbType] = byType[orbType] or {}
			table.insert(byType[orbType], obj)
		end
	end

	local fusedAny = false

	for _, orbs in pairs(byType) do
		if #orbs >= 2 then
			local clusters = clusterByProximity(orbs, data.MergeRadius)

			for _, cluster in ipairs(clusters) do
				if #cluster >= 2 then
					fusedAny = true

					local survivor = cluster[1]
					local totalValue = 0
					local anyCrit, anyGolden = false, false

					for _, member in ipairs(cluster) do
						totalValue += (tonumber(member:GetAttribute("EssenceValue")) or 0)
						if member:GetAttribute("IsCrit") then anyCrit = true end
						if member:GetAttribute("IsGolden") then anyGolden = true end
					end

					survivor:SetAttribute("EssenceValue", totalValue * (1 + data.BonusPercent))
					if anyCrit then survivor:SetAttribute("IsCrit", true) end
					if anyGolden then survivor:SetAttribute("IsGolden", true) end

					if juiceLayer then
						local survivorPos = Juice.CenterOf(survivor, juiceLayer)
						if survivorPos then
							Juice.Ring(juiceLayer, survivorPos, {
								Color = GRAVITY_WELL_COLOR, StartSize = 10, EndSize = 90, Duration = 0.5, Thickness = 3,
							})
						end
					end
					Juice.Punch(Juice.GetScale(survivor), 0.3, 0.35)

					-- Consumed members: bail (stops their own per-frame
					-- homing loop next frame, same guard CollectEffect
					-- relies on), a small burst at their last position, then
					-- gone -- never touched again after this.
					for i = 2, #cluster do
						local obj = cluster[i]
						local objPos = juiceLayer and Juice.CenterOf(obj, juiceLayer)
						obj:SetAttribute("Bail", true)
						removeCollectible(obj)
						obj:Destroy()

						if juiceLayer then
							Juice.Burst(juiceLayer, objPos, {
								Count = 4, Colors = { GRAVITY_WELL_COLOR, Color3.fromRGB(255, 255, 255) },
								Distance = 30, Duration = 0.35, Size = { 2, 5 },
							})
						end
					end
				end
			end
		end
	end

	return fusedAny
end

task.spawn(function()
	while not RebirthShopUpgrades or (player:GetAttribute("rebirthshop_gravitywell") or 0) <= 0 do
		if RebirthShopUpgrades then
			player:GetAttributeChangedSignal("rebirthshop_gravitywell"):Wait()
		else
			task.wait(1)
		end
	end

	gravityWellPill.Visible = true

	while true do
		local level = player:GetAttribute("rebirthshop_gravitywell") or 0
		local data = RebirthShopUpgrades.GetLevelData("rebirthshop_gravitywell", level)

		if not data then
			task.wait(5)
		else
			local total = data.Interval
			local remaining = total

			while remaining > 0 do
				gravityWellPillLabel.Text = ("🌀 %ds"):format(math.ceil(remaining))
				gravityWellPillFill.Size = UDim2.fromScale(math.clamp(1 - (remaining / total), 0, 1), 1)

				local step = math.min(1, remaining)
				task.wait(step)
				remaining -= step
			end

			local currentLevel = player:GetAttribute("rebirthshop_gravitywell") or 0
			local currentData = RebirthShopUpgrades.GetLevelData("rebirthshop_gravitywell", currentLevel)
			if currentData then
				gravityWellPillLabel.Text = "🌀 PULL!"
				gravityWellPillFill.Size = UDim2.fromScale(1, 1)
				Juice.Punch(Juice.GetScale(gravityWellPill), 0.25, 0.3)

				local ok, err = pcall(performGravityWellPulse, currentData)
				if not ok then
					warn("[CursorCollection] Gravity Well errored: " .. tostring(err))
				end
			end
		end
	end
end)
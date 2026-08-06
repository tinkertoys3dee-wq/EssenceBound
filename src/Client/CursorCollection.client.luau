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

local BASE_RING_SIZE = 20 -- diameter before any collection_radius upgrades are applied
local RING_COLOR = Color3.fromRGB(229, 229, 229)
local RING_THICKNESS = 3
local FOLLOW_LERP = 1

-- ============================================================
-- CHARGE CONFIG — the ring has to "fill in" (sweep from empty to a full
-- circle) while orbs sit inside it before it triggers a collection.
-- swift_collection_1/2 (GetCollectionSpeedBonus) shave time off this.
-- essence_magnet_field (HasAutoCollect) skips the charge entirely.
-- ============================================================
local BASE_CHARGE_TIME = 0.9 -- seconds to fill the ring with 0 swift_collection levels
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


local function spawnDustParticle(parent, originPosition, baseZIndex)
	local dust = Instance.new("Frame")
	dust.Name = "CollectDust"
	dust.AnchorPoint = Vector2.new(0.5, 0.5)
	dust.BackgroundColor3 = DUST_COLOR
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

local function CollectEffect(orb)
	if not orb or not orb.Parent then return end
	orb:SetAttribute("Bail", true)

	local essenceValue = orb:GetAttribute("EssenceValue") or 1

	orb.Parent = Destro
	collectionFireable:FireServer(orb:GetAttribute("OrbType"), essenceValue, orb:GetAttribute("IsCrit"), orb:GetAttribute("IsGolden"))
	
	if orb:GetAttribute("OrbType") == "Shadow Essence" then
		local discovered = player:GetAttribute("ShadowEssenceDiscovered") or false
		if not discovered then
			newDiscovery:Fire(orb:GetAttribute("OrbType"),GetEssences.Essences[orb:GetAttribute("OrbType")])
		end
	elseif orb:GetAttribute("OrbType") == "Earth Essence" then
		local discovered = player:GetAttribute("EarthEssenceDiscovered") or false
		if not discovered then
			newDiscovery:Fire(orb:GetAttribute("OrbType"),GetEssences.Essences[orb:GetAttribute("OrbType")])
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
		for i = 1, DUST_COUNT do
			task.delay(math.random() * 0.18, function()
				if container and container.Parent then
					spawnDustParticle(container, dustOrigin, baseZ)
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
	if player:GetAttribute(1907677938) and false then
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

local function updateCollection(ringCenterX, ringCenterY, deltaTime)
	local hasAutoCollect = CollectionUpgrades.HasAutoCollect(player)
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
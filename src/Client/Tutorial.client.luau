--[[
	TutorialLocalScript
	--------------------
	Fully isolated, juiced-up tutorial system. Drop this into
	StarterPlayerScripts (or anywhere client-side) as a LocalScript.
	No other modules required.

	All of the tutorial's own UI (dialogue box, buttons, progress dots,
	mascot badge) is built with SCALE-based Size/Position, so it stays
	correctly proportioned and small on every screen size instead of
	eating up a fixed pixel footprint. Only things that inherently need
	pixel offsets (corner radii, stroke thickness, text size, and the
	highlight ring / orb-demo, which have to line up with an arbitrary
	target frame's actual on-screen pixels) still use offsets -- that's
	normal.

	HOW IT WORKS:
	- Edit the TUTORIAL_STEPS table below.
	- Each step points at a GuiObject (Frame, TextButton, etc.) to highlight,
	  shows a text prompt, and has an "Extra" function slot for anything
	  special that step needs to do (play an animation, wait for a specific
	  event, tween something, etc). Leave Extra as nil/empty and fill it in
	  later per-step -- the script handles that gracefully either way.
	- Any step whose Frame's Name contains "Popup" gets .Visible = true
	  automatically while it's the active step (and hidden again once the
	  tutorial moves past it), so hidden popup menus pop open right on cue.

	STEP FIELDS:
	{
		Frame = <GuiObject>        -- what to point at / highlight (required)
		Text  = "string"           -- instruction text to display (required)
		Extra = function(step, ctx) end  -- OPTIONAL specialized behavior.
		                                  -- Leave nil to do nothing extra.
		                                  -- ctx.SetCleanup(fn) can be used
		                                  -- to register a function that
		                                  -- runs automatically the moment
		                                  -- the tutorial leaves this step
		                                  -- (advance, skip, or finish) --
		                                  -- use it to stop loops / destroy
		                                  -- any demo instances you made.
		AdvanceOn = "Button" | "Extra"   -- OPTIONAL. How the tutorial moves on:
		                                  -- "Button" (default) = player clicks Next.
		                                  -- "Extra" = step only advances when your
		                                  -- Extra function calls ctx.Advance().
	}
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("LoadingDone")

local UpdData = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdateData")
local RequestStarterGift = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestTutorialStarterGift")
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))

-- Cloneable demo orb used by the "collect orbs" tutorial step
local orbTemplate = ReplicatedStorage:WaitForChild("Cloneables"):WaitForChild("OrbClickableTemplate")

-- Forward-declared: actually built in section 2 (UI CONSTRUCTION) below.
-- startFirstCollectionWatch, in section 1b, is defined and referenced by
-- TUTORIAL_STEPS BEFORE section 2 runs -- but it only ever CALLS these at
-- runtime (once the tutorial is already showing), by which point section 2
-- has already assigned them. Declaring the locals here (and assigning,
-- never re-declaring, below) is what lets that closure see the real values
-- instead of silently capturing nil/a stray global.
local dialogueText
local nextButton
local updateProgressDots

--============================================================
-- 1. DEFINE YOUR TUTORIAL STEPS HERE
--============================================================

local main = playerGui:WaitForChild("MainGui")
local essencePopup = playerGui:WaitForChild("EssencePopupUI"):WaitForChild("PopupHolder")
local RebirthPopup = essencePopup:WaitForChild("RebirthPopup")
local ShopPopup = essencePopup:WaitForChild("ShopPopup")
local UpgradesPopup = essencePopup:WaitForChild("UpgradesPopup")
local StatsFrame = main:WaitForChild("Left"):WaitForChild("Detail")
local LargeOrbFrame = main:WaitForChild("Center"):WaitForChild("LargeOrbFolder"):WaitForChild("LargeOrb")

--============================================================
-- 1a. ORB-COLLECT DEMO (used by the Large Orb step's Extra fn)
--============================================================
-- Cheerful color palette (declared early so the demo builder below
-- can use them too -- the rest of the palette is redeclared further
-- down where it originally lived, values match).
local DEMO_COLOR_PRIMARY = Color3.fromRGB(255, 209, 70)
local DEMO_COLOR_ACCENT = Color3.fromRGB(96, 205, 255)

local function getGuiInsetOffset()
	local topInset = GuiService:GetGuiInset()
	return topInset.X, topInset.Y
end

local function getFrameCenter(frame)
	local xinset, yinset = getGuiInsetOffset()
	local pos = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	return Vector2.new(pos.X + size.X / 2 + xinset, pos.Y + size.Y / 2 + yinset)
end

-- Builds the "click the orb + hover over its drop to collect" demo for a
-- target frame. Returns a cleanup() function that stops the loop and
-- destroys everything the demo created -- call it when the tutorial
-- leaves this step.
local function startOrbCollectDemo(targetFrame, screenGui)
	local cancelled = false

	local orbDemoHolder = Instance.new("Frame")
	orbDemoHolder.Name = "OrbDemoHolder"
	orbDemoHolder.BackgroundTransparency = 1
	orbDemoHolder.Size = UDim2.new(1, 0, 1, 0)
	orbDemoHolder.ZIndex = 1005
	orbDemoHolder.Parent = screenGui

	--------------------------------------------------------------
	-- CURSOR -- built as a small rig (halo + shadow + arrow + a
	-- UIScale for the press-bounce) so it reads clearly even over
	-- a busy background instead of just a lone thin arrow icon.
	--------------------------------------------------------------
	local cursorRig = Instance.new("Frame")
	cursorRig.Name = "DemoCursorRig"
	cursorRig.AnchorPoint = Vector2.new(0.12, 0.08) -- roughly the arrow's tip
	cursorRig.BackgroundTransparency = 1
	cursorRig.Size = UDim2.new(0, 64, 0, 64)
	cursorRig.ZIndex = 1008
	cursorRig.Visible = false
	cursorRig.Parent = orbDemoHolder

	local cursorScale = Instance.new("UIScale")
	cursorScale.Scale = 1
	cursorScale.Parent = cursorRig

	-- Soft glowing halo behind the cursor so it pops against any background
	local cursorHalo = Instance.new("ImageLabel")
	cursorHalo.Name = "Halo"
	cursorHalo.BackgroundTransparency = 1
	cursorHalo.Image = "rbxasset://textures/ui/Glow.png"
	cursorHalo.ImageColor3 = DEMO_COLOR_PRIMARY
	cursorHalo.ImageTransparency = 0.35
	cursorHalo.Size = UDim2.new(0, 60, 0, 60)
	cursorHalo.Position = UDim2.new(0, 6, 0, 4)
	cursorHalo.AnchorPoint = Vector2.new(0.5, 0.5)
	cursorHalo.ZIndex = 1007
	cursorHalo.Parent = cursorRig

	local haloPulse = TweenService:Create(
		cursorHalo,
		TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ ImageTransparency = 0.7, Size = UDim2.new(0, 70, 0, 70) }
	)
	haloPulse:Play()

	-- Drop shadow copy for depth/definition
	local cursorShadow = Instance.new("ImageLabel")
	cursorShadow.Name = "Shadow"
	cursorShadow.BackgroundTransparency = 1
	cursorShadow.Image = "rbxasset://textures/ArrowCursor.png"
	cursorShadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
	cursorShadow.ImageTransparency = 0.55
	cursorShadow.Size = UDim2.new(0, 46, 0, 46)
	cursorShadow.Position = UDim2.new(0, 5, 0, 6)
	cursorShadow.ZIndex = 1008
	cursorShadow.Parent = cursorRig

	-- The actual cursor arrow -- bigger and crisper than before, with a
	-- thin bright outline so it's unmistakable
	local demoCursor = Instance.new("ImageLabel")
	demoCursor.Name = "DemoCursor"
	demoCursor.BackgroundTransparency = 1
	demoCursor.Image = "rbxasset://textures/ArrowCursor.png"
	demoCursor.Size = UDim2.new(0, 46, 0, 46)
	demoCursor.Position = UDim2.new(0, 0, 0, 0)
	demoCursor.ZIndex = 1009
	demoCursor.Parent = cursorRig

	local demoCursorStroke = Instance.new("UIStroke")
	demoCursorStroke.Thickness = 1.5
	demoCursorStroke.Color = Color3.fromRGB(255, 255, 255)
	demoCursorStroke.Transparency = 0.15
	demoCursorStroke.Parent = demoCursor

	-- A quick expanding "tap" ripple, fired the moment the cursor lands
	local function playClickRipple(pos)
		local ripple = Instance.new("Frame")
		ripple.Name = "ClickRipple"
		ripple.AnchorPoint = Vector2.new(0.5, 0.5)
		ripple.Position = UDim2.new(0, pos.X, 0, pos.Y)
		ripple.Size = UDim2.new(0, 14, 0, 14)
		ripple.BackgroundTransparency = 1
		ripple.ZIndex = 1006
		ripple.Parent = orbDemoHolder

		local rippleCorner = Instance.new("UICorner")
		rippleCorner.CornerRadius = UDim.new(1, 0)
		rippleCorner.Parent = ripple

		local rippleStroke = Instance.new("UIStroke")
		rippleStroke.Thickness = 3
		rippleStroke.Color = Color3.fromRGB(255, 255, 255)
		rippleStroke.Transparency = 0.1
		rippleStroke.Parent = ripple

		TweenService:Create(ripple, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 70, 0, 70),
		}):Play()
		local fadeTween = TweenService:Create(rippleStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		})
		fadeTween:Play()
		fadeTween.Completed:Wait()
		ripple:Destroy()
	end

	--------------------------------------------------------------
	-- RING -- an outer soft glow + an inner crisp stroke that spins
	-- while it charges, so "collecting" reads as an obvious, glowing
	-- energy fill rather than a single thin outline fading in.
	--------------------------------------------------------------
	local collectRing = Instance.new("Frame")
	collectRing.Name = "CollectRing"
	collectRing.AnchorPoint = Vector2.new(0.5, 0.5)
	collectRing.BackgroundTransparency = 1
	collectRing.Size = UDim2.new(0, 52, 0, 52)
	collectRing.ZIndex = 1007
	collectRing.Visible = false
	collectRing.Parent = orbDemoHolder

	local collectRingCorner = Instance.new("UICorner")
	collectRingCorner.CornerRadius = UDim.new(1, 0)
	collectRingCorner.Parent = collectRing

	local collectRingGlow = Instance.new("ImageLabel")
	collectRingGlow.Name = "RingGlow"
	collectRingGlow.BackgroundTransparency = 1
	collectRingGlow.Image = "rbxasset://textures/ui/Glow.png"
	collectRingGlow.ImageColor3 = DEMO_COLOR_ACCENT
	collectRingGlow.ImageTransparency = 1
	collectRingGlow.Size = UDim2.new(1.9, 0, 1.9, 0)
	collectRingGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	collectRingGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	collectRingGlow.ZIndex = 1006
	collectRingGlow.Parent = collectRing

	local collectRingStroke = Instance.new("UIStroke")
	collectRingStroke.Thickness = 2
	collectRingStroke.Transparency = 1
	collectRingStroke.Color = DEMO_COLOR_PRIMARY
	collectRingStroke.Parent = collectRing

	local collectRingGradient = Instance.new("UIGradient")
	collectRingGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, DEMO_COLOR_PRIMARY),
		ColorSequenceKeypoint.new(0.5, DEMO_COLOR_ACCENT),
		ColorSequenceKeypoint.new(1, DEMO_COLOR_PRIMARY),
	})
	collectRingGradient.Parent = collectRingStroke

	-- Slow continuous spin on the ring's gradient -- gives the
	-- "charging" moment a swirling-energy feel
	task.spawn(function()
		while not cancelled do
			for r = 0, 360, 4 do
				if cancelled then
					break
				end
				collectRingGradient.Rotation = r
				task.wait(0.02)
			end
		end
	end)

	task.spawn(function()
		while not cancelled do
			local ok = pcall(function()
				-- Pick a spot near the target frame to "drop" a demo orb
				local center = getFrameCenter(targetFrame)
				local angle = math.rad(math.random(0, 360))
				local dist = math.random(45, 85)
				local orbPos = center + Vector2.new(math.cos(angle) * dist, math.sin(angle) * dist - 30)

				local orbClone = orbTemplate:Clone()
				-- Strip any scripts the template carries -- we're driving
				-- everything manually for this demo.
				for _, desc in ipairs(orbClone:GetDescendants()) do
					if desc:IsA("Script") or desc:IsA("LocalScript") then
						desc:Destroy()
					end
				end
				orbClone.Name = "DemoOrb"
				orbClone.Parent = orbDemoHolder

				local orbScale = Instance.new("UIScale")
				orbScale.Scale = 1
				orbScale.Parent = orbClone

				local bobbing = true

				if orbClone:IsA("GuiObject") then
					orbClone.AnchorPoint = Vector2.new(0.5, 0.5)
					orbClone.Position = UDim2.new(0, orbPos.X, 0, orbPos.Y)
					orbClone.ZIndex = 1006
					orbClone.Visible = true

					orbScale.Scale = 0
					TweenService:Create(orbScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
						Scale = 1,
					}):Play()

					-- Gentle idle bob while it waits to be collected
					task.spawn(function()
						while bobbing and orbClone.Parent do
							local upTween = TweenService:Create(orbClone, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
								Position = UDim2.new(0, orbPos.X, 0, orbPos.Y - 6),
							})
							upTween:Play()
							upTween.Completed:Wait()
							if not (bobbing and orbClone.Parent) then
								break
							end
							local downTween = TweenService:Create(orbClone, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
								Position = UDim2.new(0, orbPos.X, 0, orbPos.Y),
							})
							downTween:Play()
							downTween.Completed:Wait()
						end
					end)
				end

				if cancelled then
					bobbing = false
					orbClone:Destroy()
					return
				end
				task.wait(0.3)
				if cancelled then
					bobbing = false
					orbClone:Destroy()
					return
				end

				-- Cursor swoops in from an arbitrary nearby point onto the orb
				local startPos = orbPos + Vector2.new(math.random(-110, 110), math.random(90, 140))
				cursorRig.Position = UDim2.new(0, startPos.X, 0, startPos.Y)
				cursorRig.Visible = true
				collectRing.Position = UDim2.new(0, startPos.X, 0, startPos.Y)
				collectRing.Visible = true
				collectRingStroke.Thickness = 2
				collectRingStroke.Transparency = 1
				collectRingGlow.ImageTransparency = 1

				local moveTween = TweenService:Create(cursorRig, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
					Position = UDim2.new(0, orbPos.X, 0, orbPos.Y),
				})
				moveTween:Play()
				moveTween.Completed:Wait()
				if cancelled then
					bobbing = false
					orbClone:Destroy()
					return
				end

				-- Landing "press" bounce + click ripple make the tap read clearly
				TweenService:Create(cursorScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Scale = 0.8,
				}):Play()
				task.wait(0.1)
				TweenService:Create(cursorScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
				task.spawn(playClickRipple, orbPos)

				-- Ring stays glued to the cursor and charges up while hovering
				local ringFollowConn = cursorRig:GetPropertyChangedSignal("Position"):Connect(function()
					collectRing.Position = cursorRig.Position
				end)

				local chargeStrokeTween = TweenService:Create(collectRingStroke, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Thickness = 7,
					Transparency = 0,
				})
				local chargeGlowTween = TweenService:Create(collectRingGlow, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					ImageTransparency = 0.45,
				})
				chargeStrokeTween:Play()
				chargeGlowTween:Play()
				chargeStrokeTween.Completed:Wait()
				ringFollowConn:Disconnect()

				if cancelled then
					bobbing = false
					orbClone:Destroy()
					return
				end

				-- Collected! Stop the idle bob, orb dissipates with a final
				-- pop, ring flashes out, "+1" bounces in and floats up
				bobbing = false
				local dissipateSizeTween = TweenService:Create(orbScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					Scale = 0,
				})
				pcall(function()
					TweenService:Create(orbClone, TweenInfo.new(0.28), { ImageTransparency = 1 }):Play()
				end)
				dissipateSizeTween:Play()

				TweenService:Create(collectRingStroke, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Thickness = 12,
					Transparency = 1,
				}):Play()
				TweenService:Create(collectRingGlow, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					ImageTransparency = 1,
					Size = UDim2.new(2.6, 0, 2.6, 0),
				}):Play()

				local plusOne = Instance.new("TextLabel")
				plusOne.Name = "PlusOneLabel"
				plusOne.BackgroundTransparency = 1
				plusOne.Font = Enum.Font.GothamBold
				plusOne.Text = "+1"
				plusOne.TextColor3 = DEMO_COLOR_PRIMARY
				plusOne.TextStrokeTransparency = 0.2
				plusOne.TextStrokeColor3 = Color3.fromRGB(38, 24, 60)
				plusOne.TextScaled = true
				plusOne.Size = UDim2.new(0, 64, 0, 38)
				plusOne.AnchorPoint = Vector2.new(0.5, 0.5)
				plusOne.Position = UDim2.new(0, orbPos.X, 0, orbPos.Y)
				plusOne.ZIndex = 1010
				plusOne.Parent = orbDemoHolder

				local plusOneScale = Instance.new("UIScale")
				plusOneScale.Scale = 0
				plusOneScale.Parent = plusOne
				TweenService:Create(plusOneScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()

				local plusOneTween = TweenService:Create(plusOne, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(0, orbPos.X, 0, orbPos.Y - 58),
					TextTransparency = 1,
					TextStrokeTransparency = 1,
				})
				task.delay(0.15, function()
					plusOneTween:Play()
				end)

				dissipateSizeTween.Completed:Wait()
				if orbClone and orbClone.Parent then
					orbClone:Destroy()
				end
				task.wait(0.85)
				if plusOne and plusOne.Parent then
					plusOne:Destroy()
				end

				cursorRig.Visible = false
				collectRing.Visible = false
			end)

			if not ok then
				warn("[TutorialLocalScript] Orb collect demo iteration errored.")
			end

			if cancelled then
				break
			end
			task.wait(0.6)
		end
	end)

	local function cleanup()
		cancelled = true
		if orbDemoHolder then
			orbDemoHolder:Destroy()
		end
	end

	return cleanup
end

--============================================================
-- 1b. REAL FIRST-COLLECTION WATCH (used by the Large Orb step's Extra fn)
--============================================================
-- THE reason this step exists at all: of everyone who has ever played,
-- roughly two thirds have never once collected a single Earth Essence --
-- meaning they click the giant orb (which is obvious) but never discover
-- that hovering over what it drops is a SEPARATE, required action. The old
-- version of this step just played a passive animation and let the player
-- hit "Next" whenever, so it was entirely possible to sit through the
-- whole tutorial without ever attempting a real collection yourself.
--
-- This version doesn't advance on its own -- it watches the player's own
-- leaderstats for a REAL collection (the exact same signal the server
-- writes when collectionFireable actually lands, see OrbClickManager's
-- "collected" handler / PlayerDataHandler's Quantity mirror) and only
-- lets the tutorial continue once the player has done it themselves at
-- least once. Escalating hints kick in if they're stuck, and a fallback
-- "Next" button appears after a generous wait so nobody gets hard-walled.
--
-- Watches BOTH essence leaderstats (not just Earth) because orbs are a
-- 50/50 roll between the two (see GetEssence.lua) -- a player who
-- happens to collect a Shadow Essence drop first still just proved they
-- understand the mechanic, which is the actual thing this step is
-- teaching. Returns a cleanup() function, same contract as the demo above.
local function startFirstCollectionWatch(ctx)
	local cancelled = false
	local succeeded = false
	local connections = {}

	local function disconnectAll()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		connections = {}
	end

	local leaderstats = player:WaitForChild("leaderstats")
	local watchedStats = {}
	for _, essence in ipairs(EssenceConfig.Ordered) do
		local stat = leaderstats:WaitForChild(essence.Name)
		table.insert(watchedStats, {
			Stat = stat,
			Baseline = stat:GetAttribute("Quantity") or 0,
		})
	end

	local function onSuccess()
		if cancelled or succeeded then
			return
		end
		succeeded = true
		disconnectAll()

		dialogueText.Text = "🎉  You got it! Click to shatter, hover to collect."
		updateProgressDots(1) -- keep dot 1 lit while the success beat plays

		-- A short celebratory beat before moving on, so the win actually
		-- registers instead of the UI yanking away the moment it happens.
		task.delay(1.3, function()
			if not cancelled then
				ctx.Advance()
			end
		end)
	end

	for _, watched in ipairs(watchedStats) do
		local entry = watched
		table.insert(connections, entry.Stat:GetAttributeChangedSignal("Quantity"):Connect(function()
			if (entry.Stat:GetAttribute("Quantity") or 0) > entry.Baseline then
				onSuccess()
			end
		end))
	end

	-- Escalating hints, then an escape hatch -- generous waits since the
	-- goal is genuine comprehension, not speed, but nobody should ever be
	-- permanently stuck here if something about their input isn't landing.
	task.spawn(function()
		task.wait(14)
		if cancelled or succeeded then
			return
		end
		dialogueText.Text = "🖱️  Hold your cursor still on top of a drop -- clicking alone won't collect it!"

		task.wait(20)
		if cancelled or succeeded then
			return
		end
		dialogueText.Text = "💛  Take your time -- hover over a drop and wait for the ring to fill."

		task.wait(24)
		if cancelled or succeeded then
			return
		end
		nextButton.Visible = true -- fallback: never hard-wall a stuck player
	end)

	return function()
		cancelled = true
		disconnectAll()
	end
end

-- Same fix, same reasoning, as startFirstCollectionWatch above, applied
-- to the Upgrades step: a brand-new player reaching this step has at
-- most collected one or two orbs (a few essence, nowhere near
-- root_awakening's 15-essence cost), so without a gift this step was
-- pure narration -- point at a menu, say what it does, click Next,
-- regardless of whether the player could actually try it. Requests the
-- one-time starter gift the moment this step begins (server-granted,
-- see TutorialStarterGiftService.server.luau -- this only ever ASKS),
-- then watches for the Earth Essence leaderstat to DECREASE, the
-- signature of an actual purchase, to advance. Watching for a decrease
-- rather than trying to detect "which upgrade" keeps this robust to
-- exactly which one the player picks.
local function startFirstUpgradeWatch(ctx)
	local cancelled = false
	local succeeded = false
	local connection = nil

	local function disconnectAll()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	RequestStarterGift:FireServer()

	local earthStat = player:WaitForChild("leaderstats"):WaitForChild("Earth Essence")
	local lastQuantity = earthStat:GetAttribute("Quantity") or 0

	local function onSuccess()
		if cancelled or succeeded then
			return
		end
		succeeded = true
		disconnectAll()

		dialogueText.Text = "⚡  Nice! That's your first upgrade -- your orb just got a little stronger."
		updateProgressDots(2)

		task.delay(1.3, function()
			if not cancelled then
				ctx.Advance()
			end
		end)
	end

	-- Compares each change against the value from the IMMEDIATELY
	-- preceding one (same pattern BiggestGainCelebration.client.luau
	-- uses for the opposite direction) -- lower than last time means a
	-- purchase just happened, regardless of how many increases or
	-- decreases came before it.
	connection = earthStat:GetAttributeChangedSignal("Quantity"):Connect(function()
		local current = earthStat:GetAttribute("Quantity") or 0
		local wasDecrease = current < lastQuantity
		lastQuantity = current

		if wasDecrease then
			onSuccess()
		end
	end)

	-- Same generous-but-never-permanently-stuck shape as the collect
	-- step: hints, then an escape hatch. A shorter fuse than that step's
	-- since "click the glowing menu and buy the first thing" is a much
	-- smaller ask than the hover-to-collect mechanic.
	task.spawn(function()
		task.wait(10)
		if cancelled or succeeded then
			return
		end
		dialogueText.Text = "💰  You've got free essence waiting -- open the UPGRADES menu and buy something!"

		task.wait(14)
		if cancelled or succeeded then
			return
		end
		nextButton.Visible = true -- fallback: never hard-wall a stuck player
	end)

	return function()
		cancelled = true
		disconnectAll()
	end
end

-- Order matters: teach the actual thing the player needs to do (click,
-- hover, collect, watch the energy bar) FIRST, before any menu tour --
-- previously Shop was step 1, so a first-time player's very first guided
-- instruction was a Robux upsell before they'd played at all, and the
-- energy-bar mechanic that gates clicking was never explained anywhere.
local TUTORIAL_STEPS = {
	{
		Frame = LargeOrbFrame,
		Emoji = "🌀",
		-- Kept to 1-2 short sentences on purpose -- the dialogue box is
		-- small and the old, fully-explained version overflowed it.
		Text = "Click the orb, then <font color='#FFFF00'><b>HOVER</b></font> over a drop and hold still to collect it! "
			.. "(On mobile: press and hold.)",
		-- This step doesn't auto-advance on a timer or a button -- it only
		-- moves on once the player has actually collected something for
		-- real (see startFirstCollectionWatch above). That's the fix for the
		-- measured problem: most players who never come back never
		-- collected a single essence, because clicking alone LOOKS like it
		-- did something (the orb pops, drops fly out) but doesn't bank
		-- anything until you hover one of the drops.
		AdvanceOn = "Extra",
		Extra = function(step, ctx)
			local cleanupDemo = startOrbCollectDemo(step.Frame, ctx.ScreenGui)
			local cleanupWatch = startFirstCollectionWatch(ctx)
			ctx.SetCleanup(function()
				cleanupDemo()
				cleanupWatch()
			end)
		end,
	},
	{
		Frame = UpgradesPopup,
		Emoji = "⚡",
		Text = "Spend your essence in the UPGRADES menu to level up your power!",
		-- Same fix as the Large Orb step: don't just narrate the menu,
		-- make sure the player actually buys something (see
		-- startFirstUpgradeWatch above, which also grants the one-time
		-- starter gift so there's something to spend in the first place).
		AdvanceOn = "Extra",
		Extra = function(step, ctx)
			local cleanupWatch = startFirstUpgradeWatch(ctx)
			ctx.SetCleanup(cleanupWatch)
		end,
	},
	{
		Frame = RebirthPopup,
		Emoji = "🔥",
		Text = "Feeling strong? REBIRTH to reset your progress for a permanent essence boost!",
		Extra = nil,
	},
	{
		Frame = StatsFrame,
		Emoji = "📊",
		Text = "Track everything you've earned in your STATS menu!",
		Extra = nil,
	},
	{
		Frame = ShopPopup,
		Emoji = "💎",
		Text = "SHOP shows exact permanent perks and repeatable boosts with live Robux prices. Purchases are always optional!",
		Extra = nil,
	},
}

--============================================================
-- 2. TUTORIAL UI CONSTRUCTION (no need to edit below this line)
--============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TutorialGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 1000
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- Cheerful color palette
local COLOR_PRIMARY = Color3.fromRGB(255, 209, 70)   -- sunny gold
local COLOR_SECONDARY = Color3.fromRGB(255, 105, 180) -- bubblegum pink
local COLOR_ACCENT = Color3.fromRGB(96, 205, 255)     -- sky blue
local COLOR_BG = Color3.fromRGB(38, 24, 60)           -- deep purple

--------------------------------------------------------------
-- Glowing, pulsing highlight ring around the target frame
-- (positioned in pixel offsets on purpose -- it has to match an
-- arbitrary target GuiObject's real AbsolutePosition/AbsoluteSize)
--------------------------------------------------------------
local highlight = Instance.new("Frame")
highlight.Name = "Highlight"
highlight.BackgroundTransparency = 1
highlight.BorderSizePixel = 0
highlight.ZIndex = 999
highlight.Visible = false
highlight.Parent = screenGui

local highlightStroke = Instance.new("UIStroke")
highlightStroke.Thickness = 4
highlightStroke.Color = COLOR_PRIMARY
highlightStroke.Parent = highlight

local highlightCorner = Instance.new("UICorner")
highlightCorner.CornerRadius = UDim.new(0, 12)
highlightCorner.Parent = highlight

-- A soft glow behind the stroke for extra pop
local highlightGlow = Instance.new("ImageLabel")
highlightGlow.Name = "Glow"
highlightGlow.BackgroundTransparency = 1
highlightGlow.Image = "rbxasset://textures/ui/Glow.png"
highlightGlow.ImageColor3 = COLOR_PRIMARY
highlightGlow.ImageTransparency = 0.4
highlightGlow.Size = UDim2.new(1.6, 0, 1.6, 0)
highlightGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
highlightGlow.AnchorPoint = Vector2.new(0.5, 0.5)
highlightGlow.ZIndex = 998
highlightGlow.Parent = highlight

local highlightPulseTween = TweenService:Create(
	highlightStroke,
	TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Thickness = 7 }
)
highlightPulseTween:Play()

local glowPulseTween = TweenService:Create(
	highlightGlow,
	TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ ImageTransparency = 0.75 }
)
glowPulseTween:Play()

--------------------------------------------------------------
-- Sparkle particles that twinkle around the highlighted frame
--------------------------------------------------------------
local sparkleHolder = Instance.new("Frame")
sparkleHolder.Name = "Sparkles"
sparkleHolder.BackgroundTransparency = 1
sparkleHolder.Size = UDim2.new(1, 0, 1, 0)
sparkleHolder.ZIndex = 999
sparkleHolder.Parent = highlight

local SPARKLE_COLORS = { COLOR_PRIMARY, COLOR_SECONDARY, COLOR_ACCENT }

local function spawnSparkle()
	if not highlight.Visible then
		return
	end

	local sparkle = Instance.new("TextLabel")
	sparkle.BackgroundTransparency = 1
	sparkle.Text = "✦"
	sparkle.Font = Enum.Font.GothamBold
	sparkle.TextSize = math.random(10, 18)
	sparkle.TextColor3 = SPARKLE_COLORS[math.random(1, #SPARKLE_COLORS)]
	sparkle.Size = UDim2.new(0.08, 0, 0.08, 0)
	sparkle.AnchorPoint = Vector2.new(0.5, 0.5)
	sparkle.Position = UDim2.new(math.random(-10, 110) / 100, 0, math.random(-10, 110) / 100, 0)
	sparkle.ZIndex = 999
	sparkle.Parent = sparkleHolder

	local upTween = TweenService:Create(sparkle, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	})
	sparkle.TextTransparency = 1
	upTween:Play()

	task.delay(0.35, function()
		local outTween = TweenService:Create(sparkle, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			TextTransparency = 1,
			Position = sparkle.Position + UDim2.new(0, 0, -0.15, 0),
		})
		outTween:Play()
		outTween.Completed:Wait()
		sparkle:Destroy()
	end)
end

task.spawn(function()
	while true do
		task.wait(math.random(15, 35) / 100)
		spawnSparkle()
	end
end)

--------------------------------------------------------------
-- Dialogue box with mascot emoji, instruction text, progress dots
-- Kept compact + scale-based so it never covers up the game UI.
--------------------------------------------------------------
local dialogueScale = Instance.new("UIScale")
dialogueScale.Scale = 0

local dialogueFrame = Instance.new("Frame")
dialogueFrame.Name = "DialogueFrame"
dialogueFrame.AnchorPoint = Vector2.new(0.5, 1)
dialogueFrame.Position = UDim2.new(0.5, 0, 0.95, 0)
-- Fill most of a narrow phone while capping at a comfortable desktop
-- width. The previous 40%-wide box became only ~130px wide on phones,
-- forcing the mascot, copy, and two controls into one another.
dialogueFrame.Size = UDim2.new(0.9, 0, 0.18, 0)
dialogueFrame.BackgroundColor3 = COLOR_BG
dialogueFrame.BorderSizePixel = 0
dialogueFrame.ZIndex = 1000
dialogueFrame.Visible = false
dialogueFrame.Parent = screenGui
dialogueScale.Parent = dialogueFrame

local dialogueSizeConstraint = Instance.new("UISizeConstraint")
dialogueSizeConstraint.MaxSize = Vector2.new(680, 180)
dialogueSizeConstraint.Parent = dialogueFrame

local dialogueCorner = Instance.new("UICorner")
dialogueCorner.CornerRadius = UDim.new(0, 20)
dialogueCorner.Parent = dialogueFrame

local dialogueStroke = Instance.new("UIStroke")
dialogueStroke.Thickness = 3
dialogueStroke.Color = COLOR_PRIMARY
dialogueStroke.Parent = dialogueFrame

local dialogueGradient = Instance.new("UIGradient")
dialogueGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(58, 38, 90)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(45, 28, 74)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(58, 38, 90)),
})
dialogueGradient.Rotation = 0
dialogueGradient.Parent = dialogueFrame

task.spawn(function()
	while true do
		for r = 0, 360, 2 do
			dialogueGradient.Rotation = r
			task.wait(0.03)
		end
	end
end)

-- Bouncy mascot emoji badge in the corner (kept perfectly circular via
-- an aspect ratio constraint, sized purely from scale)
local mascotBadge = Instance.new("Frame")
mascotBadge.Name = "MascotBadge"
mascotBadge.AnchorPoint = Vector2.new(0.5, 0.5)
mascotBadge.Position = UDim2.new(0.11, 0, 0.5, 0)
mascotBadge.Size = UDim2.new(0, 0, 0.62, 0)
mascotBadge.BackgroundColor3 = COLOR_SECONDARY
mascotBadge.ZIndex = 1002
mascotBadge.Parent = dialogueFrame

local mascotAspect = Instance.new("UIAspectRatioConstraint")
mascotAspect.AspectRatio = 1
mascotAspect.DominantAxis = Enum.DominantAxis.Height
mascotAspect.Parent = mascotBadge

local mascotCorner = Instance.new("UICorner")
mascotCorner.CornerRadius = UDim.new(1, 0)
mascotCorner.Parent = mascotBadge

local mascotStroke = Instance.new("UIStroke")
mascotStroke.Thickness = 3
mascotStroke.Color = Color3.fromRGB(255, 255, 255)
mascotStroke.Parent = mascotBadge

local mascotLabel = Instance.new("TextLabel")
mascotLabel.BackgroundTransparency = 1
mascotLabel.Size = UDim2.new(1, 0, 1, 0)
mascotLabel.Font = Enum.Font.GothamBold
mascotLabel.TextScaled = true
mascotLabel.Text = "✨"
mascotLabel.ZIndex = 1003
mascotLabel.Parent = mascotBadge

task.spawn(function()
	while true do
		local upTween = TweenService:Create(mascotBadge, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = UDim2.new(0.11, 0, 0.44, 0),
			Rotation = 8,
		})
		upTween:Play()
		upTween.Completed:Wait()
		local downTween = TweenService:Create(mascotBadge, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = UDim2.new(0.11, 0, 0.5, 0),
			Rotation = -8,
		})
		downTween:Play()
		downTween.Completed:Wait()
	end
end)

dialogueText = Instance.new("TextLabel")
dialogueText.Name = "DialogueText"
dialogueText.BackgroundTransparency = 1
dialogueText.Position = UDim2.new(0.23, 8, 0.32, 0)
dialogueText.Size = UDim2.new(0.54, -16, 0.6, 0)
dialogueText.Font = Enum.Font.GothamBold
dialogueText.TextScaled = true
dialogueText.RichText = true
dialogueText.TextColor3 = Color3.fromRGB(255, 255, 255)
dialogueText.TextWrapped = true
dialogueText.TextXAlignment = Enum.TextXAlignment.Left
dialogueText.TextYAlignment = Enum.TextYAlignment.Top
dialogueText.ZIndex = 1001
dialogueText.Parent = dialogueFrame

-- Progress dots along the top so kids can see how far along they are
local progressHolder = Instance.new("Frame")
progressHolder.Name = "ProgressHolder"
progressHolder.BackgroundTransparency = 1
progressHolder.Position = UDim2.new(0.22, 0, 0.08, 0)
progressHolder.Size = UDim2.new(0.4, 0, 0.16, 0)
progressHolder.ZIndex = 1002
progressHolder.Parent = dialogueFrame

local function buildProgressDots(total)
	progressHolder:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.04, 0, 0, 0)
	layout.Parent = progressHolder

	local dots = {}
	for i = 1, total do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.new(0, 0, 1, 0)
		dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		dot.BackgroundTransparency = 0.7
		dot.ZIndex = 1002
		dot.Parent = progressHolder

		local dotAspect = Instance.new("UIAspectRatioConstraint")
		dotAspect.AspectRatio = 1
		dotAspect.DominantAxis = Enum.DominantAxis.Height
		dotAspect.Parent = dot

		local dotCorner = Instance.new("UICorner")
		dotCorner.CornerRadius = UDim.new(1, 0)
		dotCorner.Parent = dot

		dots[i] = dot
	end
	return dots
end

local progressDots = buildProgressDots(#TUTORIAL_STEPS)

function updateProgressDots(index)
	for i, dot in ipairs(progressDots) do
		local targetColor = (i <= index) and COLOR_PRIMARY or Color3.fromRGB(255, 255, 255)
		local targetTransparency = (i <= index) and 0 or 0.7
		local targetSize = (i == index) and UDim2.new(0, 0, 1.25, 0) or UDim2.new(0, 0, 1, 0)
		TweenService:Create(dot, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			BackgroundColor3 = targetColor,
			BackgroundTransparency = targetTransparency,
			Size = targetSize,
		}):Play()
	end
end

--------------------------------------------------------------
-- Buttons with bouncy hover feedback (scale-based sizing)
--------------------------------------------------------------
local function makeBouncyButton(button)
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Scale = 0.92 }):Play()
	end)
end

nextButton = Instance.new("TextButton")
nextButton.Name = "NextButton"
nextButton.AnchorPoint = Vector2.new(1, 1)
nextButton.Position = UDim2.new(0.98, 0, 0.86, 0)
nextButton.Size = UDim2.new(0.18, 0, 0.32, 0)
nextButton.BackgroundColor3 = COLOR_PRIMARY
nextButton.Font = Enum.Font.GothamBold
nextButton.TextScaled = true
nextButton.TextColor3 = COLOR_BG
nextButton.Text = "Next ➜"
nextButton.ZIndex = 1001
nextButton.Parent = dialogueFrame

local nextTextPadding = Instance.new("UIPadding")
nextTextPadding.PaddingLeft = UDim.new(0, 8)
nextTextPadding.PaddingRight = UDim.new(0, 8)
nextTextPadding.Parent = nextButton

local nextButtonPadding = Instance.new("UITextSizeConstraint")
nextButtonPadding.MaxTextSize = 18
nextButtonPadding.Parent = nextButton

local nextButtonCorner = Instance.new("UICorner")
nextButtonCorner.CornerRadius = UDim.new(1, 0)
nextButtonCorner.Parent = nextButton

local nextButtonStroke = Instance.new("UIStroke")
nextButtonStroke.Thickness = 2
nextButtonStroke.Color = Color3.fromRGB(255, 255, 255)
nextButtonStroke.Parent = nextButton

makeBouncyButton(nextButton)

local skipButton = Instance.new("TextButton")
skipButton.Name = "SkipButton"
skipButton.AnchorPoint = Vector2.new(0, 1)
skipButton.Position = UDim2.new(0.03, 0, 0.86, 0)
skipButton.Size = UDim2.new(0.17, 0, 0.32, 0)
skipButton.BackgroundColor3 = Color3.fromRGB(70, 55, 95)
skipButton.Font = Enum.Font.GothamBold
skipButton.TextScaled = true
skipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
skipButton.Text = "Skip"
skipButton.ZIndex = 1001
skipButton.Parent = dialogueFrame

local skipTextPadding = Instance.new("UIPadding")
skipTextPadding.PaddingLeft = UDim.new(0, 8)
skipTextPadding.PaddingRight = UDim.new(0, 8)
skipTextPadding.Parent = skipButton

local skipButtonPadding = Instance.new("UITextSizeConstraint")
skipButtonPadding.MaxTextSize = 15
skipButtonPadding.Parent = skipButton

local skipButtonCorner = Instance.new("UICorner")
skipButtonCorner.CornerRadius = UDim.new(1, 0)
skipButtonCorner.Parent = skipButton

makeBouncyButton(skipButton)

--------------------------------------------------------------
-- Confetti burst for when the tutorial wraps up
--------------------------------------------------------------
local function burstConfetti()
	local confettiHolder = Instance.new("Frame")
	confettiHolder.BackgroundTransparency = 1
	confettiHolder.Size = UDim2.new(1, 0, 1, 0)
	confettiHolder.ZIndex = 1050
	confettiHolder.Parent = screenGui

	for i = 1, 30 do
		local piece = Instance.new("Frame")
		piece.Size = UDim2.new(math.random(4, 9) / 1000, 0, math.random(6, 12) / 1000, 0)
		piece.Position = UDim2.new(0.5, 0, 0.9, 0)
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.BackgroundColor3 = SPARKLE_COLORS[math.random(1, #SPARKLE_COLORS)]
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 1050
		piece.Parent = confettiHolder

		local pieceCorner = Instance.new("UICorner")
		pieceCorner.CornerRadius = UDim.new(0, 3)
		pieceCorner.Parent = piece

		local angle = math.rad(math.random(0, 360))
		local distance = math.random(150, 400) / 1000
		local targetPos = UDim2.new(0.5, 0, 0.9, 0) + UDim2.new(math.cos(angle) * distance, 0, math.sin(angle) * distance - 0.2, 0)

		local tween = TweenService:Create(piece, TweenInfo.new(math.random(80, 140) / 100, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = targetPos,
			BackgroundTransparency = 1,
			Rotation = piece.Rotation + math.random(180, 540),
		})
		tween:Play()
	end

	task.delay(1.5, function()
		confettiHolder:Destroy()
	end)
end

--============================================================
-- 3. TUTORIAL RUNNER LOGIC
--============================================================

local currentStepIndex = 0
local currentConnection = nil
local currentPopupFrame = nil
local currentStepCleanup = nil
local advanceSignal = Instance.new("BindableEvent")

local function isPopupFrame(frame)
	return frame ~= nil and frame.Name:find("Popup") ~= nil
end

local function positionHighlight(frame)
	local absPos = frame.AbsolutePosition
	local absSize = frame.AbsoluteSize
	local padding = 10

	local xinset, yinset = getGuiInsetOffset()

	highlight.Position = UDim2.new(0, absPos.X - padding + xinset, 0, absPos.Y - padding + yinset)
	highlight.Size = UDim2.new(0, absSize.X + padding * 2, 0, absSize.Y + padding * 2)
	highlight.Visible = true
end

local function clearStepConnection()
	if currentConnection then
		currentConnection:Disconnect()
		currentConnection = nil
	end
end

local function runStepCleanup()
	if currentStepCleanup then
		local fn = currentStepCleanup
		currentStepCleanup = nil
		local ok, err = pcall(fn)
		if not ok then
			warn("[TutorialLocalScript] Step cleanup errored: " .. tostring(err))
		end
	end
end

local function hideCurrentPopup()
	if currentPopupFrame then
		currentPopupFrame.Visible = false
		currentPopupFrame = nil
	end
end

local function playDialogueIntro()
	dialogueFrame.Visible = true
	dialogueScale.Scale = 0
	TweenService:Create(dialogueScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function goToStep(index)
	-- Whatever the previous step registered via ctx.SetCleanup runs
	-- before we touch anything else (covers normal advance, and also
	-- the "tutorial finished" path below since it flows through here).
	runStepCleanup()
	clearStepConnection()

	local step = TUTORIAL_STEPS[index]
	if not step then
		-- Tutorial finished! Celebrate a little.
		hideCurrentPopup()
		highlight.Visible = false
		local outTween = TweenService:Create(dialogueScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
		outTween:Play()
		burstConfetti()
		outTween.Completed:Wait()
		dialogueFrame.Visible = false

		UpdData:FireServer(true, "=", "SeenTutorial")
		return
	end

	currentStepIndex = index

	-- Popups get shown automatically, and the previous popup (if different) closes
	if currentPopupFrame and currentPopupFrame ~= step.Frame then
		hideCurrentPopup()
	end
	if isPopupFrame(step.Frame) then
		step.Frame.Visible = true
		currentPopupFrame = step.Frame
	end

	dialogueText.Text = ((step.Emoji and (step.Emoji .. "  ") or "")) .. (step.Text or "")
	updateProgressDots(index)
	playDialogueIntro()

	if step.Frame then
		positionHighlight(step.Frame)
		-- Keep the highlight glued to the frame if it moves/resizes
		currentConnection = step.Frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
			positionHighlight(step.Frame)
		end)
	else
		highlight.Visible = false
	end

	-- Build the context object passed into Extra functions
	local ctx = {
		Advance = function()
			advanceSignal:Fire()
		end,
		SetCleanup = function(fn)
			currentStepCleanup = fn
		end,
		ScreenGui = screenGui,
		Step = step,
		Index = index,
	}

	-- Toggle Next button visibility depending on AdvanceOn mode
	if step.AdvanceOn == "Extra" then
		nextButton.Visible = false
	else
		nextButton.Visible = true
	end

	-- Run the specialized Extra function if one was provided
	if typeof(step.Extra) == "function" then
		local ok, err = pcall(step.Extra, step, ctx)
		if not ok then
			warn("[TutorialLocalScript] Extra function errored on step " .. index .. ": " .. tostring(err))
		end
	end
end

local function advanceTutorial()
	goToStep(currentStepIndex + 1)
end

nextButton.MouseButton1Click:Connect(advanceTutorial)
skipButton.MouseButton1Click:Connect(function()
	runStepCleanup()
	clearStepConnection()
	hideCurrentPopup()
	highlight.Visible = false
	TweenService:Create(dialogueScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
	task.delay(0.25, function()
		dialogueFrame.Visible = false
	end)
	currentStepIndex = #TUTORIAL_STEPS + 1
	-- Skipping is a completed onboarding decision too. Previously only the
	-- final Next button persisted SeenTutorial, so pressing Skip made the
	-- whole tutorial return on every rejoin and also left follow-up newcomer
	-- systems waiting forever for a completion flag that never arrived.
	UpdData:FireServer(true, "=", "SeenTutorial")
end)

advanceSignal.Event:Connect(advanceTutorial)

--============================================================
-- 4. START
--============================================================

local function startTutorial()
	if #TUTORIAL_STEPS == 0 then
		warn("[TutorialLocalScript] No tutorial steps defined yet.")
		return
	end
	goToStep(1)
end

remote.Event:Wait()

if not player:GetAttribute("SeenTutorial") then
	startTutorial()
end

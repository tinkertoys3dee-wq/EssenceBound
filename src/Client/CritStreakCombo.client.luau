--[[
	CritStreakCombo (LocalScript -> StarterPlayerScripts)
	======================================================
	A "COMBO xN!" callout for landing several criticals in a row --
	escalating color and size as the streak climbs, then resets silently
	on the first non-crit (no punishment beat, just no reward beat).

	WHY THIS IS DIFFERENT FROM MOMENTUM / collectStreak
	-------------------------------------------------------
	This game already has two other streak-shaped systems, and this one
	is deliberately not a third copy of either:
		- Momentum (rebirthshop_momentum, in OrbClicker.client.luau) is a
		  CADENCE streak -- how fast you're clicking, independent of luck,
		  and it feeds a real gameplay bonus.
		- collectStreak (in CursorCollection.client.luau) is also a
		  cadence/rhythm thing, purely for audio pitch, reset by a PAUSE
		  in collecting.
		- This one is a LUCK streak: consecutive CRITICAL collections in a
		  row, reset only by a non-crit landing (timing-independent).
		  Purely cosmetic -- crits already pay out correctly server-side
		  (EssenceMultiplier/CriticalsController) whether or not this
		  script even exists.

	HOW IT LEARNS A CRIT LANDED
	------------------------------
	CursorCollection.client.luau fires "CritLanded" (a BindableEvent,
	same pattern as EssenceDiscovered) with the exact same IsCrit flag
	it already reads for its own per-orb effects -- not a new trust
	boundary, just a second listener on information the client already
	had.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MainGui = playerGui:WaitForChild("MainGui")
local Center = MainGui:WaitForChild("Center")
local LargeOrbFolder = Center:WaitForChild("LargeOrbFolder")
local LargeOrb = LargeOrbFolder:WaitForChild("LargeOrb")

local juiceLayer = Juice.GetLayer(playerGui)

-- Owned/created here (matching NewDiscovery.client.luau's ownership of
-- EssenceDiscovered) since this is the only script that ever reads it.
local critLanded = ReplicatedStorage:FindFirstChild("CritLanded")
if not critLanded then
	critLanded = Instance.new("BindableEvent")
	critLanded.Name = "CritLanded"
	critLanded.Parent = ReplicatedStorage
end

-- =========================================================================
-- ESCALATION TABLE
-- =========================================================================
-- Sorted ascending. Each entry is the streak length that triggers it --
-- only announced once per threshold crossed, not on every crit past it,
-- so a long streak doesn't spam a callout on every single collection.

local TIERS = {
	{ Streak = 3,  Label = "COMBO",      Color = Color3.fromRGB(255, 170, 60),  TextSize = 26 },
	{ Streak = 5,  Label = "MEGA COMBO", Color = Color3.fromRGB(255, 110, 60),  TextSize = 30 },
	{ Streak = 8,  Label = "UNSTOPPABLE", Color = Color3.fromRGB(230, 70, 180), TextSize = 34 },
	{ Streak = 12, Label = "GODLIKE",    Color = Color3.fromRGB(150, 90, 255),  TextSize = 38 },
	{ Streak = 20, Label = "LEGENDARY",  Color = Color3.fromRGB(255, 215, 80),  TextSize = 44 },
}

-- =========================================================================
-- STATE
-- =========================================================================

local consecutiveCrits = 0
local lastAnnouncedStreak = 0

local function findNewestCrossedTier(streak: number, lastAnnounced: number)
	local crossed = nil
	for _, tier in ipairs(TIERS) do
		if streak >= tier.Streak and tier.Streak > lastAnnounced then
			crossed = tier
		end
	end
	return crossed
end

local function announce(tier)
	if not juiceLayer then
		return
	end

	local center = Juice.CenterOf(LargeOrb, juiceLayer)
	if not center then
		return
	end

	local text = ("%s x%d!"):format(tier.Label, consecutiveCrits)

	Juice.FloatText(juiceLayer, center, text, {
		Color = tier.Color,
		Duration = 1.1,
		Rise = 100,
		TextSize = tier.TextSize,
	})

	Juice.Burst(juiceLayer, center, {
		Count = 10 + consecutiveCrits,
		Colors = { tier.Color, Color3.fromRGB(255, 255, 255) },
		Distance = 90 + consecutiveCrits * 4,
		Duration = 0.6,
		Size = { 4, 9 },
		ZIndex = 200,
	})
end

-- =========================================================================
-- TRIGGER
-- =========================================================================

critLanded.Event:Connect(function(isCrit: boolean)
	if not isCrit then
		-- Silent reset on purpose -- celebrating streaks, not calling
		-- attention to them ending, matches how this codebase's other
		-- streak systems (Momentum) already just quietly zero out.
		consecutiveCrits = 0
		lastAnnouncedStreak = 0
		return
	end

	consecutiveCrits += 1

	local tier = findNewestCrossedTier(consecutiveCrits, lastAnnouncedStreak)
	if tier then
		lastAnnouncedStreak = tier.Streak
		announce(tier)
	end
end)

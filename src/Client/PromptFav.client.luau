--[[
	PromptFav LocalScript
	----------------------
	Was an unconditional `while true do ... task.wait(300) end` loop that
	re-prompted PromptSetFavorite every 5 minutes for the player's ENTIRE
	session, with no memory of whether they'd already answered it -- the
	exact kind of repeat-nag pattern that trains players to dismiss (or
	rage-quit over) a prompt instead of engaging with it, which actively
	works against this game's own retention goals. Every other one-time
	prompt in this codebase (the tutorial, the first-crit guarantee) is
	gated behind a persisted "Seen___" flag so it only ever happens once,
	ever, across rejoins included -- this now follows that same pattern.

	Note for whoever next touches this: AvatarEditorService:PromptSetFavorite
	expects an Enum.AvatarItemType (Asset/Bundle), i.e. it's built for
	favoriting a CATALOG item, not the running experience itself -- passing
	game.PlaceId here may not actually be the correct call for "favorite this
	game." Left as-is since fixing the underlying call needs a Studio test
	this environment can't do; the fix here is scoped to the nag-loop
	anti-pattern, which is a real problem regardless of whether the
	underlying prompt itself is a no-op or actually shows something.
]]

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UpdData = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpdateData")
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

-- Give them a real chance to play first -- asking in the first few seconds,
-- before they know if they even like the game, is the fastest way to get
-- an instant "no" that can never be asked again.
task.wait(300)

if player:GetAttribute("SeenFavoritePrompt") then
	return
end

-- Minute five is now the new player's 2x Awakening Rush, followed by the
-- eight-minute convergence finale. A platform prompt on top of either beat
-- would interrupt the exact session arc this prompt is meant to help retain.
-- Existing/returning players keep the original five-minute timing; only an
-- eligible, unfinished newcomer waits for the journey handoff plus a short
-- breathing gap (also separates this from the post-finale shop spotlight).
local waitedForJourney = false
while player:GetAttribute("FirstJourneyEligible") == true
	and player:GetAttribute("FirstJourneyCompleted") ~= true
do
	waitedForJourney = true
	task.wait(5)
end
if waitedForJourney then
	task.wait(45)
end

-- This is a Roblox-native prompt, so it cannot participate in the custom UI
-- queue directly. At minimum, require a stable quiet window before invoking
-- it; if the session stays busy, skip the optional prompt entirely.
local clearSince = nil
local clearDeadline = os.clock() + 120
while os.clock() < clearDeadline do
	if not PresentationCoordinator.HasPendingPresentation() then
		clearSince = clearSince or os.clock()
		if os.clock() - clearSince >= 1.5 then
			break
		end
	else
		clearSince = nil
	end
	task.wait(0.1)
end
if not clearSince or os.clock() - clearSince < 1.5 then
	-- A session busy for another two minutes has already supplied plenty of
	-- engagement beats. Treat this optional nudge as consumed rather than
	-- retrying it on a later join and surprising the player then.
	UpdData:FireServer(true, "=", "SeenFavoritePrompt")
	return
end

local promptLease = PresentationCoordinator.Acquire("FavoritePrompt", {
	Priority = 18,
	QuietAfter = 1,
})
if not promptLease then
	return
end

local promptOpened = pcall(function()
	AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
end)

-- Roblox owns the native prompt and exposes no custom frame for this queue to
-- observe. Reserve a short response window so the next automatic card cannot
-- appear beneath it; manual game panels are blocked by the same lease.
if promptOpened then
	task.wait(8)
end
PresentationCoordinator.Release(promptLease, 1)

-- Marked seen regardless of pcall success -- a broken/no-op call should
-- fail (and stay failed) silently, not retry forever every 5 minutes.
UpdData:FireServer(true, "=", "SeenFavoritePrompt")

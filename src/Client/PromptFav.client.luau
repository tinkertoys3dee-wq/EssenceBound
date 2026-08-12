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

pcall(function()
	AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
end)

-- Marked seen regardless of pcall success -- a broken/no-op call should
-- fail (and stay failed) silently, not retry forever every 5 minutes.
UpdData:FireServer(true, "=", "SeenFavoritePrompt")

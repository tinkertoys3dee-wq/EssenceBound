--[[
	BadgeCelebration (LocalScript -> StarterPlayerScripts)
	=======================================================
	Roblox's own badge toast is small, generic, and easy to miss entirely
	if you're mid-click when it fires. This adds an unmissable full-screen
	"Achievement Unlocked" moment the instant any of the 13 badges is
	actually EARNED, using the same name/icon data the Achievements panel
	already displays.

	Pure client-side and read-only: every badge grant already mirrors onto
	a player Attribute named after its numeric id (see every
	BS:AwardBadgeAsync call site, mapped in AchievementsConfig's own
	comment block), so this only ever watches attributes -- it never
	grants or trusts anything itself.

	GRACE PERIOD: PlayerDataHandler mirrors every ALREADY-earned badge
	onto its attribute right after a player's data loads (so returning
	players see correct state) -- without a settle window, that join-time
	mirroring would look identical to a fresh earn, and a returning player
	with several badges would get a wall of "Achievement Unlocked" toasts
	the moment they log in. Same problem the essence-milestone celebration
	system (UIManagement.client.luau) already solves by seeding its
	"highest passed" state from the starting balance before it starts
	celebrating -- this uses the same shape of fix.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementsConfig = require(ReplicatedStorage:WaitForChild("AchievementsConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local BADGE_COLOR = Color3.fromRGB(255, 205, 90)
local SETTLE_SECONDS = 4

local knownEarned = {}
local celebrationPending = false

local function snapshotEarned()
	for _, def in ipairs(AchievementsConfig.Badges) do
		knownEarned[def.Id] = player:GetAttribute(def.Id) == true
	end
end

local function celebrate(def)
	if not juiceLayer then
		return
	end
	-- Badges are already persisted and visible in Achievements. If onboarding
	-- or another badge has reserved the foreground, drop this optional flourish
	-- instead of building a celebration backlog.
	if PresentationCoordinator.HasPendingPresentation() then
		return
	end
	local lease = PresentationCoordinator.Acquire("BadgeCelebration", {
		Priority = 52,
		QuietAfter = 0.55,
	})
	if not lease then
		return
	end

	local center = UDim2.fromScale(0.5, 0.22)

	Juice.Flash(juiceLayer, { Color = BADGE_COLOR, Peak = 0.35, Duration = 0.5 })

	Juice.Ring(juiceLayer, center, {
		Color = BADGE_COLOR, StartSize = 20, EndSize = 220, Duration = 0.7, Thickness = 4,
	})
	Juice.Burst(juiceLayer, center, {
		Count = 18,
		Colors = { BADGE_COLOR, Color3.fromRGB(255, 255, 255) },
		Distance = 200,
		Duration = 0.8,
		Size = { 5, 11 },
	})

	Juice.FloatText(juiceLayer, center, "🏅 ACHIEVEMENT UNLOCKED", {
		Color = BADGE_COLOR,
		Duration = 0.55,
		Rise = 0,
		TextSize = 22,
	})

	task.delay(0.15, function()
		Juice.FloatText(juiceLayer, center + UDim2.fromScale(0, 0.06), def.Icon .. "  " .. def.Name, {
			Color = Color3.fromRGB(255, 255, 255),
			Duration = 1.6,
			Rise = 60,
			TextSize = 30,
		})
	end)

	local sound = Juice.FindSound("SFX/UI/UIPop")
	if sound then
		Juice.PlaySound(sound, { Pitch = 1.3, Volume = 0.55 })
		task.delay(0.12, function()
			Juice.PlaySound(sound, { Pitch = 1.6, Volume = 0.5 })
		end)
	end

	task.wait(1.9)
	PresentationCoordinator.Release(lease, 0.55)
end

snapshotEarned()

task.delay(SETTLE_SECONDS, function()
	-- Catch anything that replicated in during the grace window too, so
	-- it's never mistaken for a fresh earn once watching starts below.
	snapshotEarned()

	for _, def in ipairs(AchievementsConfig.Badges) do
		player:GetAttributeChangedSignal(def.Id):Connect(function()
			if knownEarned[def.Id] then
				return
			end
			if player:GetAttribute(def.Id) == true then
				knownEarned[def.Id] = true
				-- A single reward can cross several badge thresholds at once. The
				-- Achievements panel retains all of them; one foreground flourish is
				-- enough and avoids turning the earn into a toast sequence.
				if celebrationPending or PresentationCoordinator.HasPendingPresentation() then
					return
				end
				celebrationPending = true
				task.spawn(function()
					local ok, err = xpcall(function()
						celebrate(def)
					end, debug.traceback)
					celebrationPending = false
					if not ok then
						PresentationCoordinator.ForceRelease("BadgeCelebration", 0.55)
						warn("[BadgeCelebration] Presentation failed: " .. tostring(err))
					end
				end)
			end
		end)
	end
end)

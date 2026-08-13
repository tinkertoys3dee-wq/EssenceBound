--[[
	StormServerInit (Script, place in ServerScriptService)
	--------------------------------------------------------
	Minimal wiring example for StormController. Swap GetPlayerData for
	however you actually load/save playerData (ProfileService, etc) -
	this stub is just here so the module has something driving it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StormController = require(script.Parent:WaitForChild("StormController")) -- adjust path
local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EssenceStormEvent = Remotes:WaitForChild("EssenceStorm")

-- Add this RemoteEvent alongside your existing ones (ClickOrb, Return, etc)
local ManualStormSummon = Remotes:FindFirstChild("ManualStormSummon")
if not ManualStormSummon then
	ManualStormSummon = Instance.new("RemoteEvent")
	ManualStormSummon.Name = "ManualStormSummon"
	ManualStormSummon.Parent = Remotes
end

-- STUB: replace with your real data source (e.g. ProfileService profile.Data)
local datas = {
	
}
local function GetPlayerData(player)
	local data = require(player:WaitForChild("PlayerData"))
	return data
end

local function onPlayerAdded(player)
	local controller = StormController.new(player, GetPlayerData, EssenceStormEvent)
	controller:Start()
end

Players.PlayerAdded:Connect(onPlayerAdded)

Players.PlayerRemoving:Connect(function(player)
	local controller = StormController.Get(player)
	if controller then
		controller:Stop()
	end
end)

-- Every other init script in this codebase (GroupRewardService,
-- PotionTimerService, RebirthShopService, SanctumService,
-- ProgressionService, LeaderboardService, WheelService,
-- AchievementsService, ProductPurchaseHandler) also loops over
-- Players:GetPlayers() to catch anyone already in the server -- this one
-- didn't. In live play that rarely matters (joins almost always land after
-- server scripts finish starting), but a Studio multi-client playtest can
-- easily have a couple of test players already registered before this
-- script's PlayerAdded connection above is made, and without this loop
-- they'd silently never get a StormController for the rest of the session
-- -- no automatic storms, and ManualStormSummon would just do nothing.
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

ManualStormSummon.OnServerEvent:Connect(function(player)
	local controller = StormController.Get(player)
	if controller then
		local success, reason = controller:TryManualSummon()
		if success then
			return
		end

		if reason == "OnCooldown" then
			local remaining = math.max(0, tonumber(player:GetAttribute("ManualStormCooldownRemaining")) or 0)
			NotificationService.Send(player, {
				Kind = "Warning",
				Title = "Storm Focus Recharging",
				Message = ("Manual summoning is ready again in %d:%02d."):format(
					math.floor(remaining / 60),
					math.floor(remaining % 60)
				),
				Icon = "⚡",
				Key = "manual-storm-cooldown",
			})
		elseif reason == "StormAlreadyActive" then
			NotificationService.Send(player, {
				Kind = "Info",
				Title = "Storm Already Active",
				Message = "Ride this storm before summoning another one.",
				Icon = "⚡",
				Key = "manual-storm-active",
			})
		elseif reason == "NotUnlocked" then
			NotificationService.Send(player, {
				Kind = "Info",
				Title = "Summoning Locked",
				Message = "Unlock Manual Storm Summon in the upgrade tree first.",
				Icon = "◇",
				Key = "manual-storm-locked",
			})
		end
	else
		NotificationService.Send(player, {
			Kind = "Error",
			Title = "Storms Still Loading",
			Message = "Your storm controller is still waking up. Try again in a moment.",
			Key = "manual-storm-loading",
		})
	end
end)

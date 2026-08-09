--[[
	IdleService (Server Script - put under ServerScriptService)
	------------------------------------------------------------
	Runs the parts of the "Passive" branch that need something to actually
	happen over time, rather than just being read as a modifier.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local IdleUpgrades = require(ReplicatedStorage:WaitForChild("IdleUpgrades"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local GroupRewardConfig = require(ReplicatedStorage:WaitForChild("GroupRewardConfig"))
local EPMService = require(game:GetService("ServerScriptService"):WaitForChild("EPMService"))

local Events = ReplicatedStorage:WaitForChild("Remotes")
local OfflineEarningsEvent = Events:FindFirstChild("OfflineEssenceReward")

local OFFLINE_HARVEST_CAP_SECONDS = 8 * 60 * 60 -- cap offline earnings at 8 hours; tune to taste
local PASSIVE_CURRENCY_ID = "EarthEssence" -- matches BaseCost keys in TreeUpgrades

-- ===================== COMEBACK BONUS (lapsed-player win-back) =====================
-- The offline-earnings calc above caps at OFFLINE_HARVEST_CAP_SECONDS (8h),
-- which is correct for THAT purpose (nobody should out-earn active play by
-- idling), but it means an 8-hour absence and a 3-week absence produce the
-- EXACT same "welcome back" -- no acknowledgment at all that someone who
-- actually lapsed came back. This is a separate, flat bonus specifically
-- for real absences, using the UNCAPPED time away, folded into the same
-- Welcome Back popup as an extra line rather than a second competing UI.
-- Sorted longest-first so the loop below can just take the first match.
local COMEBACK_TIERS = {
	{ MinSeconds = 14 * 24 * 60 * 60, BaseReward = 8000 }, -- 14+ days
	{ MinSeconds = 7 * 24 * 60 * 60, BaseReward = 3500 },  -- 7-14 days
	{ MinSeconds = 3 * 24 * 60 * 60, BaseReward = 1200 },  -- 3-7 days
	{ MinSeconds = 1 * 24 * 60 * 60, BaseReward = 300 },   -- 1-3 days
}
local COMEBACK_DISPLAY_KEY = "🎉 Welcome Back Bonus"

local function getComebackBonus(realSecondsAway, rebirths)
	for _, tier in ipairs(COMEBACK_TIERS) do
		if realSecondsAway >= tier.MinSeconds then
			return ProgressionConfig.ScaleReward(tier.BaseReward, rebirths)
		end
	end
	return 0
end

-- ===================== ESSENCE DEPOSIT HELPER =====================

local function AddEssence(player, currencyId, amount)
	if amount <= 0 then return end

	local playerDataModule = player:FindFirstChild("PlayerData")
	if not playerDataModule then return end
	local ok, data = pcall(require, playerDataModule)
	if not ok or not data or not data.Essences or not data.Essences[currencyId] then
		return
	end

	local essence = data.Essences[currencyId]
	essence.Quantity += amount

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local stat = leaderstats:FindFirstChild(essence.DisplayName)
		if stat then
			stat:SetAttribute("Quantity", essence.Quantity)
		end
	end
end

-- ===================== idle_drips_1/2: PASSIVE INCOME LOOP =====================

local function RunPassiveIncomeLoop()
	while true do
		local waitTime = 1 
		task.wait(waitTime)

		for _, player in ipairs(Players:GetPlayers()) do
			local perSecond = IdleUpgrades.GetPassiveEssencePerSecond(player)
			if perSecond > 0 then
				local multiplier = 1
				local multiplierModule = ReplicatedStorage:FindFirstChild("EssenceMultiplier") 
				if multiplierModule then
					local ok, mult = pcall(function()
						return require(multiplierModule).CalculateMultiplier(player,false)
					end)
					if ok and mult then
						multiplier = mult
					end
				end
				AddEssence(player, PASSIVE_CURRENCY_ID, perSecond * waitTime * multiplier)
			end
		end
	end
end

-- automation_core ("the orb periodically fires on its own") is NOT
-- implemented here despite the name of this section header that used to
-- be above this comment -- the real, working implementation lives
-- client-side in OrbClicker.client.luau (search HasAutomationCore /
-- "automation_core"), which actually fires ClickOrbEvent on a randomized
-- interval and applies every upgrade a real click would. What used to be
-- here was a dead server-side loop from an earlier, abandoned attempt:
-- its body was a commented-out call to `OrbController`, a variable never
-- even required in this file, so it could never have run. Removed --
-- IdleUpgrades.HasAutomationCore is still used by the real (client-side)
-- implementation, just not from here.

-- ===================== offline_harvest_1/2: REJOIN LUMP SUM =====================

local function GrantOfflineEarnings(player)
	task.wait(5)
	local playerDataModule = player:FindFirstChild("PlayerData")
	if not playerDataModule then return end
	local ok, data = pcall(require, playerDataModule)
	
	if not ok or not data then return end

	local lastLeave = data.LastLeaveTime
	if not lastLeave or lastLeave <= 0 then return end -- first-ever session, nothing to grant

	local secondsAway = math.clamp(os.time() - lastLeave, 0, OFFLINE_HARVEST_CAP_SECONDS)
	local minutesOffline = math.floor(secondsAway / 60)
	if minutesOffline <= 0 then return end

	-- 1. Base Gamepass Multiplier
	local basePercent = 0.1
	pcall(function()
		if MarketplaceService:UserOwnsGamePassAsync(player.UserId, 1907863864) then
			basePercent = 0.5
		end
	end)

	-- 2. Offline Upgrade Multiplier (added to base percent)
	local upgradePercent = IdleUpgrades.GetOfflineEarningsPercent(player)
	local finalOfflinePercent = basePercent + (upgradePercent or 0)
	local memberOfflineMultiplier = player:GetAttribute("GroupMember") == true
		and GroupRewardConfig.OfflineEarningsMultiplier
		or 1

	-- 3. Global Essence Multiplier
	local globalMultiplier = 1
	local essenceMulti = ReplicatedStorage:FindFirstChild("EssenceMultiplier")
	if essenceMulti then
		pcall(function()
			globalMultiplier = require(essenceMulti).CalculateMultiplier(player, false)
		end)
	end

	local totalEarnedDisplay = 0

	-- Loop through ALL essences and grant rewards using saved EPM
	local rewards = {}
	for essenceId, dict in pairs(data.Essences) do
		if dict.Discovered == true then
			local epm = dict.savedEPM or 0
			if epm > 0 then
				local offlineReward = math.floor(
					epm * minutesOffline * globalMultiplier * finalOfflinePercent * memberOfflineMultiplier
				)

				if offlineReward > 0 then
					AddEssence(player, essenceId, offlineReward)

					-- Track global gathered stats
					if data.TotalEssenceGathered then
						data.TotalEssenceGathered += offlineReward
					else
						data.TotalEssenceGathered = offlineReward
					end

					totalEarnedDisplay += offlineReward

					rewards[essenceId] = offlineReward
				end
			end
		end
	end

	-- Comeback bonus: uses the REAL (uncapped) time away, not the 8-hour
	-- `secondsAway` above, since the whole point is to recognize absences
	-- the offline-earnings cap deliberately doesn't reward further.
	local realSecondsAway = math.max(0, os.time() - lastLeave)
	local comebackBonus = getComebackBonus(realSecondsAway, data.Rebirths)
	if comebackBonus > 0 then
		AddEssence(player, PASSIVE_CURRENCY_ID, comebackBonus)
		data.TotalEssenceGathered = (data.TotalEssenceGathered or 0) + comebackBonus
		totalEarnedDisplay += comebackBonus
		rewards[COMEBACK_DISPLAY_KEY] = comebackBonus
	end

	-- Offline earnings are a pre-session lump sum, not active production.
	-- Resnapshot all balances only after every offline/comeback award has been
	-- deposited so the EPM window begins from the exact post-grant state.
	if totalEarnedDisplay > 0 then
		EPMService.resetBaseline(player)
	end

	-- Fire client event if rewards were granted
	if OfflineEarningsEvent and totalEarnedDisplay > 0 then
		OfflineEarningsEvent:FireClient(player, rewards, secondsAway)
	end
end

-- ===================== LIFECYCLE =====================

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		GrantOfflineEarnings(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local playerDataModule = player:FindFirstChild("PlayerData")
	if playerDataModule then
		local ok, data = pcall(require, playerDataModule)
		if ok and data then
			data.LastLeaveTime = os.time()
		end
	end
end)

task.spawn(RunPassiveIncomeLoop)

--[[
	IdleService (Server Script - put under ServerScriptService)
	------------------------------------------------------------
	Runs the parts of the "Passive" branch that need something to actually
	happen over time, rather than just being read as a modifier.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))
local IdleUpgrades = require(ReplicatedStorage:WaitForChild("IdleUpgrades"))

local Events = ReplicatedStorage:WaitForChild("Remotes")
local OfflineEarningsEvent = Events:FindFirstChild("OfflineEssenceReward")

local OFFLINE_HARVEST_CAP_SECONDS = 8 * 60 * 60 -- cap offline earnings at 8 hours; tune to taste
local AUTOMATION_CLICK_INTERVAL = 2 -- seconds between automation_core auto-clicks; tune to taste
local PASSIVE_CURRENCY_ID = "EarthEssence" -- matches BaseCost keys in TreeUpgrades

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

-- ===================== automation_core: AUTO-CLICK LOOP =====================

local automationThreads = {}

local function StartAutomationFor(player)
	if automationThreads[player] then return end
	automationThreads[player] = task.spawn(function()
		while player.Parent do
			task.wait(AUTOMATION_CLICK_INTERVAL)
			if IdleUpgrades.HasAutomationCore(player) then
				-- OrbController.ResolveClick(player) 
			end
		end
	end)
end

local function StopAutomationFor(player)
	local thread = automationThreads[player]
	if thread then
		task.cancel(thread)
		automationThreads[player] = nil
	end
end

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
				local offlineReward = math.floor(epm * minutesOffline * globalMultiplier * finalOfflinePercent)

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

	-- Fire client event if rewards were granted
	if OfflineEarningsEvent and totalEarnedDisplay > 0 then
		OfflineEarningsEvent:FireClient(player, rewards, secondsAway)
	end
end

-- ===================== LIFECYCLE =====================

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		GrantOfflineEarnings(player)
		StartAutomationFor(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	StopAutomationFor(player)
	local playerDataModule = player:FindFirstChild("PlayerData")
	if playerDataModule then
		local ok, data = pcall(require, playerDataModule)
		if ok and data then
			data.LastLeaveTime = os.time()
		end
	end
end)

task.spawn(RunPassiveIncomeLoop)
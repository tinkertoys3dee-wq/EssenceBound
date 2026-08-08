--[[
	ProgressionService (Script -> ServerScriptService)
	==================================================
	Server-authoritative engine for the three retention systems defined in
	ReplicatedStorage.ProgressionConfig:

		1. Daily login streak rewards
		2. Daily quests (3 shared goals, rotating each UTC day)
		3. Playtime chests (session-length rewards)

	DESIGN: PURELY ADDITIVE
	------------------------
	This script does not modify any existing gameplay system. It observes
	them instead:

		- Clicks / orb collections are counted by attaching ADDITIONAL
		  OnServerEvent listeners to the existing ClickOrb and Collection
		  remotes. Roblox fires every connected listener, so OrbClickManager
		  keeps working exactly as before and neither script knows about
		  the other.
		- Essence earned is measured from the Earth Essence leaderstat's
		  own Quantity attribute changing.
		- Upgrade purchases and rebirths are read from the player
		  attributes those systems already set.

	That means this file can be deleted wholesale and the game returns to
	its previous behavior with no dangling references.

	TRUST BOUNDARY
	---------------
	Orb/click counts come from client-fired remotes, which an exploiter
	could spam -- exactly as they could before this script existed, since
	those same remotes already grant currency. Quest progress is therefore
	no more trusted than the existing economy, and deliberately no less:
	rewards here are modest, counted per-event (never using a
	client-supplied amount), and rate-limited below. All actual granting
	happens here on the server; the client can only ever ask to claim.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))

-- =========================================================================
-- REMOTES
-- =========================================================================
-- Created here rather than expected to exist in the place file, so this
-- system is fully self-contained and works on a fresh sync.

local function ensureRemote(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end

	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("ProgressionRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "ProgressionRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local SyncRemote = ensureRemote(remotesFolder, "RemoteEvent", "ProgressionSync")
local ClaimDailyRemote = ensureRemote(remotesFolder, "RemoteEvent", "ClaimDaily")
local ClaimQuestRemote = ensureRemote(remotesFolder, "RemoteEvent", "ClaimQuest")
local ClaimChestRemote = ensureRemote(remotesFolder, "RemoteEvent", "ClaimChest")
local ToastRemote = ensureRemote(remotesFolder, "RemoteEvent", "RewardToast")
local RedeemCodeFunction = ensureRemote(remotesFolder, "RemoteFunction", "RedeemCode")

-- =========================================================================
-- PROMO CODES
-- =========================================================================
-- Deliberately defined HERE, on the server, rather than in the shared
-- ProgressionConfig: anything in ReplicatedStorage can be read by an
-- exploiter, so codes kept there could be datamined and redeemed before
-- they were ever announced. Only the redemption result crosses the wire.
--
-- TO ADD A CODE: add an entry below and publish the game. Codes are
-- matched case-insensitively (input is upper-cased before lookup), so
-- write the keys in caps here.
--
-- Rewards scale with the player's rebirth count like every other reward
-- in this file, so a code stays worth redeeming for an established
-- player without being game-breaking for a brand new one.

local CODES = {
	["LAUNCH"] = { Essence = 5000, Label = "Launch Gift" },
	["WELCOME"] = { Essence = 2500, Label = "Welcome Gift" },
	["ESSENCE"] = { Essence = 3500, Label = "Essence Cache" },
	["ORBHUNTER"] = { Essence = 6000, Label = "Orb Hunter" },
	["BOOSTME"] = {
		Essence = 2000,
		Label = "Boost Code",
		Potion = { Effect = "EssenceX15", Duration = 20 * 60 },
		PotionLabel = "+ 1.5x Essence (20 min)",
	},
}

local MAX_CODE_LENGTH = 32

-- =========================================================================
-- SESSION STATE (in memory only -- nothing here needs to survive a rejoin)
-- =========================================================================

local sessionStart = {}      -- [player] = os.clock() at join
local chestsClaimed = {}     -- [player] = number of chests claimed this session
local lastKnownEssence = {}  -- [player] = last observed Earth Essence total
local lastUpgradeLevels = {} -- [player] = { [upgradeId] = level }
local lastRebirths = {}      -- [player] = number
local claimDebounce = {}     -- [player] = os.clock() of last claim action

local CLAIM_DEBOUNCE_SECONDS = 0.35

-- Rate limit on stat counting, so a spamming client can't inflate quest
-- progress far faster than legitimate play allows.
local statBudget = {}        -- [player] = { [stat] = { count, windowStart } }
local STAT_WINDOW_SECONDS = 1
local STAT_MAX_PER_WINDOW = {
	[ProgressionConfig.Stats.Clicks] = 25,
	[ProgressionConfig.Stats.OrbsCollected] = 60,
	[ProgressionConfig.Stats.CriticalOrbs] = 60,
}

-- =========================================================================
-- HELPERS
-- =========================================================================

local function getData(player)
	local module = player:FindFirstChild("PlayerData")
	if not module then
		return nil
	end

	local ok, data = pcall(require, module)
	if not ok or type(data) ~= "table" then
		return nil
	end
	return data
end

-- Guarantees the Progression sub-table exists and is shaped correctly,
-- even for a save written before this system existed.
local function getProgression(player)
	local data = getData(player)
	if not data then
		return nil, nil
	end

	local progression = data.Progression
	if type(progression) ~= "table" then
		progression = {}
		data.Progression = progression
	end

	progression.LastClaimDay = tonumber(progression.LastClaimDay) or 0
	progression.Streak = tonumber(progression.Streak) or 0
	progression.BestStreak = tonumber(progression.BestStreak) or 0
	progression.QuestDay = tonumber(progression.QuestDay) or 0
	progression.QuestRebirths = tonumber(progression.QuestRebirths) or 0
	progression.TotalQuestsCompleted = tonumber(progression.TotalQuestsCompleted) or 0
	progression.TotalDailiesClaimed = tonumber(progression.TotalDailiesClaimed) or 0
	progression.StreakFreezes = tonumber(progression.StreakFreezes) or 0

	if type(progression.QuestProgress) ~= "table" then
		progression.QuestProgress = {}
	end
	if type(progression.QuestClaimed) ~= "table" then
		progression.QuestClaimed = {}
	end
	-- Keyed by code string. Unlike quest progress, stale keys here are
	-- exactly what we want: a redeemed code must stay redeemed forever.
	if type(progression.RedeemedCodes) ~= "table" then
		progression.RedeemedCodes = {}
	end

	return progression, data
end

local function getRebirths(player)
	return tonumber(player:GetAttribute("Rebirths")) or 0
end

local function getEssenceStat(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end
	return leaderstats:FindFirstChild("Earth Essence")
end

-- The one place rewards are actually paid out.
--
-- lastKnownEssence is updated to the post-grant total BEFORE writing the
-- attribute. The essence-earned tracker works on deltas against that
-- value, so this makes a reward net to a zero delta and keeps rewards
-- from feeding the "earn N essence" quest they might themselves complete.
-- Doing it before the write (rather than after) is deliberate: it's
-- correct whether Roblox delivers the attribute signal immediately or
-- defers it to the end of the frame.
local function grantEssence(player, amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false
	end

	local stat = getEssenceStat(player)
	if not stat then
		return false
	end

	local current = tonumber(stat:GetAttribute("Quantity")) or 0
	local newTotal = current + amount

	lastKnownEssence[player] = newTotal
	stat:SetAttribute("Quantity", newTotal)

	local data = getData(player)
	if data then
		data.TotalEssenceGathered = (tonumber(data.TotalEssenceGathered) or 0) + amount
	end

	return true
end

local function grantPotion(player, potion)
	if not potion or not potion.Effect then
		return
	end

	-- Wrapped: the potion system living elsewhere must never be able to
	-- take down a reward payout that has already been committed.
	pcall(function()
		local moduleScript = ServerScriptService:FindFirstChild("PotionTimerService")
		if not moduleScript then
			return
		end
		local PotionTimerService = require(moduleScript)
		PotionTimerService.ApplyPotion(player, potion.Effect, potion.Duration or 600)
	end)
end

local function toast(player, icon, title, subtitle)
	ToastRemote:FireClient(player, {
		Icon = icon,
		Title = title,
		Subtitle = subtitle,
	})
end

local function passesDebounce(player)
	local now = os.clock()
	local last = claimDebounce[player]
	if last and (now - last) < CLAIM_DEBOUNCE_SECONDS then
		return false
	end
	claimDebounce[player] = now
	return true
end

-- =========================================================================
-- QUEST STATE
-- =========================================================================

-- Rolls today's quests if the stored day is stale. Progress and claim
-- flags are stored by SLOT INDEX rather than quest id: the save merge
-- only overwrites keys present in the new data, so fixed slots that are
-- always rewritten can't leave stale per-quest-id progress behind to be
-- picked up weeks later when a quest rotates back around.
local function refreshQuests(player, progression)
	local today = ProgressionConfig.GetDayNumber()
	if progression.QuestDay == today then
		return false
	end

	progression.QuestDay = today
	progression.QuestRebirths = getRebirths(player)

	local progress, claimed = {}, {}
	for slot = 1, ProgressionConfig.QuestsPerDay do
		progress[slot] = 0
		claimed[slot] = false
	end
	progression.QuestProgress = progress
	progression.QuestClaimed = claimed

	return true
end

-- Quests are generated from the rebirth count captured when the day
-- rolled, not the live one, so rebirthing midway through a day can't
-- move a target the player is already partway toward.
local function getTodaysQuests(progression)
	return ProgressionConfig.GetQuestsForDay(progression.QuestDay, progression.QuestRebirths)
end

-- =========================================================================
-- CLIENT SYNC
-- =========================================================================

local function buildChestState(player)
	local claimed = chestsClaimed[player] or 0
	local elapsed = 0
	if sessionStart[player] then
		elapsed = os.clock() - sessionStart[player]
	end

	local nextChest = ProgressionConfig.GetChest(claimed + 1)

	return {
		Claimed = claimed,
		Elapsed = math.floor(elapsed),
		NextIndex = claimed + 1,
		NextAt = nextChest.Seconds,
		NextEssence = ProgressionConfig.ScaleReward(nextChest.Essence, getRebirths(player)),
		NextIcon = nextChest.Icon,
		NextTitle = nextChest.Title,
		Ready = elapsed >= nextChest.Seconds,
	}
end

local function pushState(player)
	local progression = getProgression(player)
	if not progression then
		return
	end

	local today = ProgressionConfig.GetDayNumber()
	local quests = getTodaysQuests(progression)

	local questState = {}
	for slot, quest in ipairs(quests) do
		questState[slot] = {
			Slot = slot,
			Icon = quest.Icon,
			Title = quest.Title,
			Description = quest.Description,
			Target = quest.Target,
			Reward = quest.Reward,
			Progress = math.min(tonumber(progression.QuestProgress[slot]) or 0, quest.Target),
			Claimed = progression.QuestClaimed[slot] == true,
		}
	end

	-- A streak is "claimable today" if they haven't already claimed today.
	local canClaimDaily = progression.LastClaimDay ~= today
	-- What they'd be claiming: continuing the streak if yesterday was the
	-- last claim (or the day before, if a banked freeze would cover the
	-- gap -- kept in sync with the claim handler's own condition below so
	-- this preview never shows something the claim itself wouldn't
	-- actually do), otherwise starting fresh at day 1.
	local pendingStreak = 1
	if progression.LastClaimDay == today then
		pendingStreak = math.max(1, progression.Streak)
	elseif progression.LastClaimDay == today - 1 then
		pendingStreak = progression.Streak + 1
	elseif progression.LastClaimDay == today - 2 and progression.StreakFreezes > 0 then
		pendingStreak = progression.Streak + 1
	end

	SyncRemote:FireClient(player, {
		Daily = {
			CanClaim = canClaimDaily,
			Streak = progression.Streak,
			BestStreak = progression.BestStreak,
			PendingStreak = pendingStreak,
			StreakFreezes = progression.StreakFreezes,
			SecondsUntilReset = ProgressionConfig.GetSecondsUntilNextDay(),
		},
		Quests = questState,
		Chest = buildChestState(player),
		Rebirths = getRebirths(player),
	})
end

-- Quest progress changes on nearly every orb collected, and firing a
-- remote per change would mean dozens of state pushes per second per
-- player during normal play. Progress updates therefore mark the player
-- dirty and a single flush loop coalesces them into at most one push per
-- interval. Claims still push immediately, since those need to feel
-- instant.
local pendingPush = {}

local function requestPush(player)
	pendingPush[player] = true
end

task.spawn(function()
	while true do
		task.wait(0.5)

		for player in pairs(pendingPush) do
			pendingPush[player] = nil
			if player.Parent then
				local ok, err = pcall(pushState, player)
				if not ok then
					warn("ProgressionService: state push failed: " .. tostring(err))
				end
			end
		end
	end
end)

-- =========================================================================
-- STAT TRACKING
-- =========================================================================

local function withinBudget(player, stat, amount)
	local cap = STAT_MAX_PER_WINDOW[stat]
	if not cap then
		return true
	end

	local budgets = statBudget[player]
	if not budgets then
		return true
	end

	local now = os.clock()
	local entry = budgets[stat]
	if not entry or (now - entry.WindowStart) >= STAT_WINDOW_SECONDS then
		budgets[stat] = { Count = amount, WindowStart = now }
		return true
	end

	if entry.Count >= cap then
		return false
	end

	entry.Count += amount
	return true
end

local function addStat(player, stat, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return
	end

	if not withinBudget(player, stat, amount) then
		return
	end

	local progression = getProgression(player)
	if not progression then
		return
	end

	refreshQuests(player, progression)

	local quests = getTodaysQuests(progression)
	local changed = false

	for slot, quest in ipairs(quests) do
		if quest.Stat == stat and progression.QuestClaimed[slot] ~= true then
			local current = tonumber(progression.QuestProgress[slot]) or 0
			if current < quest.Target then
				local updated = math.min(current + amount, quest.Target)
				progression.QuestProgress[slot] = updated
				changed = true

				-- Announce the moment a quest becomes claimable, so the
				-- player gets a clear "go claim this" beat rather than
				-- having to notice a bar quietly fill.
				if updated >= quest.Target then
					toast(player, quest.Icon, "Quest Complete!", quest.Title .. " -- claim your reward")
				end
			end
		end
	end

	if changed then
		requestPush(player)
	end
end

-- =========================================================================
-- CLAIM HANDLERS
-- =========================================================================

ClaimDailyRemote.OnServerEvent:Connect(function(player)
	if not passesDebounce(player) then
		return
	end

	local progression = getProgression(player)
	if not progression then
		return
	end

	local today = ProgressionConfig.GetDayNumber()
	if progression.LastClaimDay == today then
		return -- already claimed today
	end

	-- Consecutive day continues the streak. Exactly one missed day still
	-- continues it if a freeze is banked -- see ProgressionConfig's
	-- "STREAK FREEZES" note for why this stays consistent with the
	-- existing "deliberately gentle" design rather than working against
	-- it. Two or more missed days is still a full reset regardless: a
	-- freeze forgives one bad day, not an extended absence.
	local usedFreeze = false
	if progression.LastClaimDay == today - 1 then
		progression.Streak += 1
	elseif progression.LastClaimDay == today - 2 and progression.StreakFreezes > 0 then
		progression.StreakFreezes -= 1
		progression.Streak += 1
		usedFreeze = true
	else
		progression.Streak = 1
	end

	progression.LastClaimDay = today
	progression.BestStreak = math.max(progression.BestStreak, progression.Streak)
	progression.TotalDailiesClaimed += 1

	-- Earned automatically, same cadence as the day-7 "standout" reward
	-- (every 7/14/21/... days of streak) -- capped so this stays a safety
	-- net for one bad day rather than unlimited insurance.
	local earnedFreeze = false
	if progression.Streak % ProgressionConfig.StreakFreezeEveryNDays == 0
		and progression.StreakFreezes < ProgressionConfig.MaxStreakFreezes
	then
		progression.StreakFreezes += 1
		earnedFreeze = true
	end

	local reward = ProgressionConfig.GetDailyRewardForStreak(progression.Streak)
	local essence = ProgressionConfig.ScaleReward(reward.Essence, getRebirths(player))

	grantEssence(player, essence)
	if reward.Potion then
		grantPotion(player, reward.Potion)
	end

	local subtitle = ("+%s Essence"):format(ProgressionConfig.FormatNumber(essence))
	if reward.PotionLabel then
		subtitle ..= "  " .. reward.PotionLabel
	end
	if earnedFreeze then
		subtitle ..= "  +1 🛡️ Streak Freeze"
	end

	local title = ("Day %d Streak!"):format(progression.Streak)
	if usedFreeze then
		title = "🛡️ Streak Saved -- " .. title
	end
	toast(player, reward.Icon, title, subtitle)

	pushState(player)
end)

ClaimQuestRemote.OnServerEvent:Connect(function(player, slot)
	if not passesDebounce(player) then
		return
	end

	slot = tonumber(slot)
	if not slot or slot < 1 or slot > ProgressionConfig.QuestsPerDay or slot ~= math.floor(slot) then
		return
	end

	local progression = getProgression(player)
	if not progression then
		return
	end

	refreshQuests(player, progression)

	local quests = getTodaysQuests(progression)
	local quest = quests[slot]
	if not quest then
		return
	end

	if progression.QuestClaimed[slot] == true then
		return
	end

	local progress = tonumber(progression.QuestProgress[slot]) or 0
	if progress < quest.Target then
		return -- not actually complete; client asked for something it can't have
	end

	progression.QuestClaimed[slot] = true
	progression.TotalQuestsCompleted += 1

	grantEssence(player, quest.Reward)
	toast(player, quest.Icon, quest.Title, ("+%s Essence"):format(ProgressionConfig.FormatNumber(quest.Reward)))

	pushState(player)
end)

ClaimChestRemote.OnServerEvent:Connect(function(player)
	if not passesDebounce(player) then
		return
	end

	if not sessionStart[player] then
		return
	end

	local claimed = chestsClaimed[player] or 0
	local chest = ProgressionConfig.GetChest(claimed + 1)
	local elapsed = os.clock() - sessionStart[player]

	if elapsed < chest.Seconds then
		return -- not earned yet
	end

	chestsClaimed[player] = claimed + 1

	local essence = ProgressionConfig.ScaleReward(chest.Essence, getRebirths(player))
	grantEssence(player, essence)
	if chest.Potion then
		grantPotion(player, chest.Potion)
	end

	local subtitle = ("+%s Essence"):format(ProgressionConfig.FormatNumber(essence))
	if chest.PotionLabel then
		subtitle ..= "  " .. chest.PotionLabel
	end
	toast(player, chest.Icon, chest.Title, subtitle)

	pushState(player)
end)

-- Redemption is a RemoteFunction because the player needs to be told
-- *why* a code failed (wrong / already used) rather than having nothing
-- happen. Returns: (success: boolean, message: string).
local codeAttemptAt = {} -- [player] = os.clock() of last attempt
local CODE_ATTEMPT_COOLDOWN = 1.5

RedeemCodeFunction.OnServerInvoke = function(player, rawCode)
	-- Throttled per player: without this, a client could brute-force the
	-- code list by firing guesses in a tight loop.
	local now = os.clock()
	local last = codeAttemptAt[player]
	if last and (now - last) < CODE_ATTEMPT_COOLDOWN then
		return false, "Slow down a moment..."
	end
	codeAttemptAt[player] = now

	if type(rawCode) ~= "string" then
		return false, "Enter a code."
	end

	-- Trim, cap length before any further work, and normalize case.
	local code = rawCode:gsub("^%s+", ""):gsub("%s+$", "")
	if #code == 0 then
		return false, "Enter a code."
	end
	if #code > MAX_CODE_LENGTH then
		return false, "That's not a valid code."
	end
	code = code:upper()

	local definition = CODES[code]
	if not definition then
		return false, "That code isn't valid."
	end

	local progression = getProgression(player)
	if not progression then
		return false, "Still loading -- try again in a moment."
	end

	if progression.RedeemedCodes[code] then
		return false, "You've already used that code!"
	end

	progression.RedeemedCodes[code] = true

	local essence = ProgressionConfig.ScaleReward(definition.Essence or 0, getRebirths(player))
	grantEssence(player, essence)
	if definition.Potion then
		grantPotion(player, definition.Potion)
	end

	local subtitle = ("+%s Essence"):format(ProgressionConfig.FormatNumber(essence))
	if definition.PotionLabel then
		subtitle ..= "  " .. definition.PotionLabel
	end
	toast(player, "🎟️", definition.Label or "Code Redeemed!", subtitle)

	pushState(player)

	return true, ("Redeemed: %s"):format(definition.Label or code)
end

-- =========================================================================
-- OBSERVERS ON EXISTING SYSTEMS
-- =========================================================================
-- Everything below attaches to remotes/attributes that already exist.
-- Nothing here is required for those systems to keep functioning.

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not remotes then
		warn("ProgressionService: Remotes folder never appeared; click/collect quests will not track.")
		return
	end

	local clickOrb = remotes:WaitForChild("ClickOrb", 30)
	if clickOrb then
		clickOrb.OnServerEvent:Connect(function(player)
			addStat(player, ProgressionConfig.Stats.Clicks, 1)
		end)
	end

	local collection = remotes:WaitForChild("Collection", 30)
	if collection then
		-- Counted as one orb per event rather than using the client's
		-- quantity value, so quest progress can't be inflated by a
		-- forged amount even though the economy itself trusts it.
		collection.OnServerEvent:Connect(function(player, _orbName, _quantity, crit)
			addStat(player, ProgressionConfig.Stats.OrbsCollected, 1)
			if crit then
				addStat(player, ProgressionConfig.Stats.CriticalOrbs, 1)
			end
		end)
	end
end)

local function watchPlayerProgress(player)
	-- Essence earned: measured as positive deltas on the leaderstat the
	-- economy already maintains.
	task.spawn(function()
		local stat = nil
		local deadline = os.clock() + 30
		while os.clock() < deadline do
			stat = getEssenceStat(player)
			if stat or not player.Parent then
				break
			end
			task.wait(0.5)
		end

		if not stat or not player.Parent then
			return
		end

		lastKnownEssence[player] = tonumber(stat:GetAttribute("Quantity")) or 0

		stat:GetAttributeChangedSignal("Quantity"):Connect(function()
			local current = tonumber(stat:GetAttribute("Quantity")) or 0
			local previous = lastKnownEssence[player] or current
			lastKnownEssence[player] = current

			local delta = current - previous
			if delta > 0 then
				addStat(player, ProgressionConfig.Stats.EssenceEarned, delta)
			end
		end)
	end)

	-- Upgrades bought / rebirths: both systems already mirror their state
	-- onto player attributes, so watching those needs no hooks in them.
	lastRebirths[player] = getRebirths(player)
	lastUpgradeLevels[player] = {}

	player.AttributeChanged:Connect(function(attribute)
		if attribute == "Rebirths" then
			local current = getRebirths(player)
			local previous = lastRebirths[player] or current
			lastRebirths[player] = current
			if current > previous then
				addStat(player, ProgressionConfig.Stats.Rebirths, current - previous)
			end
			return
		end

		local upgradeDef = TreeUpgrades.ById and TreeUpgrades.ById[attribute]
		if not upgradeDef then
			return
		end

		local levels = lastUpgradeLevels[player]
		if not levels then
			return
		end

		local current = tonumber(player:GetAttribute(attribute)) or 0
		local previous = levels[attribute] or 0
		levels[attribute] = current

		-- Only counts increases: a rebirth zeroes every upgrade attribute,
		-- and that must not register as "bought" or read as negative.
		if current > previous then
			addStat(player, ProgressionConfig.Stats.UpgradesBought, current - previous)
		end
	end)
end

-- =========================================================================
-- PLAYTIME CHEST TICK
-- =========================================================================
-- Pushes state on a slow loop so the client's countdown stays honest and
-- a chest becoming ready is noticed without the client being trusted to
-- decide when that happened.

task.spawn(function()
	while true do
		task.wait(5)

		for _, player in ipairs(Players:GetPlayers()) do
			if sessionStart[player] then
				local chestState = buildChestState(player)
				-- Only resync while a chest is pending or newly ready --
				-- no point pushing state to someone with nothing changing.
				if chestState.Ready then
					pushState(player)
				end
			end
		end
	end
end)

-- =========================================================================
-- LIFECYCLE
-- =========================================================================

local function onPlayerAdded(player)
	sessionStart[player] = os.clock()
	chestsClaimed[player] = 0
	statBudget[player] = {}

	-- PlayerData is created by PlayerDataHandler on its own PlayerAdded
	-- connection, so it may not exist for a moment yet.
	task.spawn(function()
		local dataModule = player:WaitForChild("PlayerData", 30)
		if not dataModule or not player.Parent then
			return
		end

		local progression = getProgression(player)
		if not progression then
			return
		end

		refreshQuests(player, progression)
		watchPlayerProgress(player)

		-- Small delay so the client's UI scripts have loaded and are
		-- listening before the first state arrives.
		task.wait(1)
		if player.Parent then
			pushState(player)
		end
	end)
end

local function onPlayerRemoving(player)
	sessionStart[player] = nil
	chestsClaimed[player] = nil
	lastKnownEssence[player] = nil
	lastUpgradeLevels[player] = nil
	lastRebirths[player] = nil
	claimDebounce[player] = nil
	statBudget[player] = nil
	codeAttemptAt[player] = nil
	pendingPush[player] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Covers a Studio script reload with players already in the world.
for _, existing in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existing)
end

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local market = game:GetService("MarketplaceService")
local EPMService = require(game:GetService("ServerScriptService"):WaitForChild("EPMService"))
-- ======
-- Format
-- ======

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

local essenceMulti = require(game:GetService("ReplicatedStorage"):WaitForChild("EssenceMultiplier"))

-- ============================================================
-- CONFIG
-- ============================================================
local DATASTORE_NAME = "PlayerData_v1" 
local AUTOSAVE_INTERVAL = 120 
local MAX_RETRIES = 5
local RETRY_BACKOFF = 2 

local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
local templateModule = ServerStorage:WaitForChild("DefaultPlayerData")

-- ============================================================
-- INTERNAL STATE
-- ============================================================
local sessionStartTime = {} 
local saveLocks = {}        

-- ============================================================
-- RETRY WRAPPER
-- ============================================================
local function withRetries(fn, ...)
	local args = { ... }
	local lastErr

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(fn, table.unpack(args))
		if ok then
			return true, result
		end

		lastErr = result
		warn(("PlayerDataHandler: attempt %d/%d failed: %s"):format(attempt, MAX_RETRIES, tostring(result)))

		if attempt < MAX_RETRIES then
			task.wait(RETRY_BACKOFF * attempt)
		end
	end

	return false, lastErr
end

-- ============================================================
-- MERGE
-- ============================================================
local function applySavedData(target, saved)
	for key, savedValue in pairs(saved) do
		if type(savedValue) == "table" and type(target[key]) == "table" then
			applySavedData(target[key], savedValue)
		else
			target[key] = savedValue
		end
	end
end

-- ============================================================
-- LOAD
-- ============================================================
local BS = game:GetService("BadgeService")
local RP = game:GetService("ReplicatedStorage")
local NewPlayerLuckConfig = require(RP:WaitForChild("NewPlayerLuckConfig"))
local ZonesConfig = require(RP:WaitForChild("ZonesConfig"))
local function loadPlayerData(player)
	local clone = templateModule:Clone()
	clone.Name = "PlayerData"
	clone.Parent = player

	local playerFolder = Instance.new("Folder")
	playerFolder.Name = player.UserId
	playerFolder.Parent = RP:WaitForChild("PlayerOrbs")

	local health = Instance.new("IntValue")
	health.Name = "Health"
	health.Value = 100
	health.Parent = playerFolder

	local maxHealth = Instance.new("IntValue")
	maxHealth.Name = "MaxHealth"
	maxHealth.Value = 100
	maxHealth.Parent = playerFolder

	local data = require(clone) 

	local key = "Player_" .. player.UserId
	local success, result = withRetries(function()
		return playerDataStore:GetAsync(key)
	end)

	-- Only a fetch that SUCCEEDED and found nothing counts as "brand new"
	-- below -- a fetch that FAILED (transient DataStore error) must never
	-- be treated as a fresh account, or a returning player with real
	-- progress could get misidentified as new on top of everything else
	-- going wrong that attempt.
	local isBrandNewPlayer = false
	if success and result then
		applySavedData(data, result)
	elseif not success then
		warn("PlayerDataHandler: failed to load data for " .. player.Name .. " after retries.")
	else
		isBrandNewPlayer = true
	end

	-- Stamped once, only for a genuinely first-ever join -- see
	-- NewPlayerLuckConfig for what this drives. This can't just check "is
	-- data.FirstJoinAt still 0" instead of tracking isBrandNewPlayer above:
	-- an existing save that predates this field has FirstJoinAt sitting at
	-- the template's default 0 too (nothing in saved data would have
	-- overwritten it), which would misidentify every already-existing
	-- player as brand new the first time each of their saves loads after
	-- this shipped.
	if isBrandNewPlayer then
		data.FirstJoinAt = os.time()
	end

	-- OFFLINE HARVEST LOGIC REMOVED HERE --

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local EarthEssence = Instance.new("StringValue")
	EarthEssence.Name = "Earth Essence"

	EarthEssence.Value = formatNumber(data.Essences.EarthEssence.Quantity)
	EarthEssence:SetAttribute("Quantity", data.Essences.EarthEssence.Quantity)
	EarthEssence.Parent = leaderstats
	
	local ShadowEssence = Instance.new("StringValue")
	ShadowEssence.Name = "Shadow Essence"

	ShadowEssence.Value = formatNumber(data.Essences["Shadow Essence"].Quantity)
	ShadowEssence:SetAttribute("Quantity", data.Essences["Shadow Essence"].Quantity)
	ShadowEssence.Parent = leaderstats

	player:SetAttribute("ShadowEssence", data.Essences["Shadow Essence"].Quantity)
	player:SetAttribute("EarthEssence", data.Essences.EarthEssence.Quantity)

	-- ===== LIFETIME SHADOW ESSENCE =====
	-- Migration for saves written before this field existed: a lifetime
	-- total behind the current balance is raised to match, so nobody loses
	-- multiplier the first time they load after this shipped.
	data.LifetimeShadowEssence = math.max(
		tonumber(data.LifetimeShadowEssence) or 0,
		tonumber(data.Essences["Shadow Essence"].Quantity) or 0
	)
	player:SetAttribute("ShadowEssenceLifetime", data.LifetimeShadowEssence)

	-- Tracks deltas so only genuine INCOME counts toward the lifetime
	-- total -- spending in the Shadow Sanctum must not reduce it.
	local lastShadowQuantity = tonumber(data.Essences["Shadow Essence"].Quantity) or 0

	-- Mirror Sanctum levels onto attributes. The systems those upgrades
	-- affect (EssenceOrbController, CollectionUpgrades, EssenceMultiplier)
	-- read the attribute directly, the same way they already do for the
	-- TreeUpgrades ids.
	if type(data.SanctumUpgrades) ~= "table" then
		data.SanctumUpgrades = {}
	end
	for upgradeId, level in pairs(data.SanctumUpgrades) do
		player:SetAttribute(upgradeId, level)
	end
	
	player:SetAttribute("ShadowEssenceDiscovered", data.Essences["Shadow Essence"].Discovered)
	player:SetAttribute("EarthEssenceDiscovered", data.Essences.EarthEssence.Discovered)
	
	EarthEssence.AttributeChanged:Connect(function(attribute)
		if attribute == "Quantity" then
			data.Essences.EarthEssence.Quantity = EarthEssence:GetAttribute("Quantity")
			
			if not player:GetAttribute("4008378896042305") and data.Essences.EarthEssence.Quantity >= 500 then
				player:SetAttribute("4008378896042305", true)
				data.Badges[4008378896042305] = true
				BS:AwardBadgeAsync(player.UserId,4008378896042305)
			end
			
			if not player:GetAttribute("1189564550645111") and data.Essences.EarthEssence.Quantity >= 100000 then
				player:SetAttribute("1189564550645111", true)
				data.Badges[1189564550645111] = true
				BS:AwardBadgeAsync(player.UserId,1189564550645111)
			end
			
			if not player:GetAttribute("4077164450257078") and data.Essences.EarthEssence.Quantity >= 1000000 then
				player:SetAttribute("4077164450257078", true)
				data.Badges[4077164450257078] = true
				BS:AwardBadgeAsync(player.UserId,4077164450257078)
			end
			
			EarthEssence.Value = formatNumber(data.Essences.EarthEssence.Quantity)

			if data.Essences.EarthEssence.Discovered == false then
				player:SetAttribute("EarthEssenceDiscovered",true)
				data.Essences.EarthEssence.Discovered = true

				local V = player:FindFirstChild(data.Essences.EarthEssence.DisplayName)
				if V then V.Value = true end

				local HighestDiscovered = nil
				local previousRarity = -1
				local discoveries = 0 

				for essenceName, values in pairs(data.Essences) do
					if values.Discovered then
						discoveries += 1
						if values.Rarity > previousRarity then
							previousRarity = values.Rarity
							HighestDiscovered = values.DisplayName
						end
					end
				end

				if HighestDiscovered then
					data.RarestEssence = HighestDiscovered
					data.UniqueEssences = discoveries
					-- Mirrors into an attribute (like Rebirths/RebirthCurrency
					-- already do) so the "Rarest Essence" leaderstat below can
					-- listen for changes instead of only ever reading the
					-- value once at join -- same stale-leaderstat bug class.
					player:SetAttribute("RarestEssence", HighestDiscovered)
				end
			end
		end
	end)
	
	ShadowEssence.AttributeChanged:Connect(function(attribute)
		if attribute == "Quantity" then
			data.Essences["Shadow Essence"].Quantity = ShadowEssence:GetAttribute("Quantity")
			player:SetAttribute("ShadowEssence", ShadowEssence:GetAttribute("Quantity"))
			ShadowEssence.Value = formatNumber(data.Essences["Shadow Essence"].Quantity)

			-- Only count increases toward the lifetime total. A decrease is
			-- the player spending in the Sanctum, which must never claw back
			-- the multiplier they already earned.
			local current = tonumber(ShadowEssence:GetAttribute("Quantity")) or 0
			local gained = current - lastShadowQuantity
			lastShadowQuantity = current

			if gained > 0 then
				data.LifetimeShadowEssence = (tonumber(data.LifetimeShadowEssence) or 0) + gained
				player:SetAttribute("ShadowEssenceLifetime", data.LifetimeShadowEssence)
			end

			if data.Essences["Shadow Essence"].Discovered == false then
				player:SetAttribute("ShadowEssenceDiscovered",true)
				data.Essences["Shadow Essence"].Discovered = true

				local V = player:FindFirstChild(data.Essences["Shadow Essence"].DisplayName)
				if V then V.Value = true end

				local HighestDiscovered = nil
				local previousRarity = -1
				local discoveries = 0 

				for essenceName, values in pairs(data.Essences) do
					if values.Discovered then
						discoveries += 1
						if values.Rarity > previousRarity then
							previousRarity = values.Rarity
							HighestDiscovered = values.DisplayName
						end
					end
				end

				if HighestDiscovered then
					data.RarestEssence = HighestDiscovered
					data.UniqueEssences = discoveries
					-- Mirrors into an attribute (like Rebirths/RebirthCurrency
					-- already do) so the "Rarest Essence" leaderstat below can
					-- listen for changes instead of only ever reading the
					-- value once at join -- same stale-leaderstat bug class.
					player:SetAttribute("RarestEssence", HighestDiscovered)
				end
			end
		end
	end)
	
	for value, activated in pairs(data.HollowedMilestones) do
		player:SetAttribute(value,activated)
	end
	
	local rarestEssence = Instance.new("StringValue")
	rarestEssence.Name = "Rarest Essence"
	rarestEssence.Value = data.RarestEssence or ""
	rarestEssence.Parent = leaderstats

	-- Was set once above and never again -- a player who discovers a
	-- rarer essence type mid-session (data.RarestEssence updates
	-- correctly, see the discovery blocks above) never saw it reflected
	-- here. Same mirror pattern as Rebirths/Prestige Shards.
	player:GetAttributeChangedSignal("RarestEssence"):Connect(function()
		rarestEssence.Value = tostring(player:GetAttribute("RarestEssence") or "")
	end)

	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Value = data.Rebirths or 0
	rebirths.Parent = leaderstats

	-- Was set once here and never again -- RebirthHandler.luau's
	-- PerformRebirth updates player:GetAttribute("Rebirths") correctly
	-- (everything server-side reads that live), but nothing mirrored it
	-- back into this leaderstat's .Value, so the Roblox player list kept
	-- showing whatever rebirth count a player joined with even after they
	-- rebirthed several more times in the same session. Same mirror
	-- pattern as the Prestige Shards leaderstat just below.
	player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		rebirths.Value = tonumber(player:GetAttribute("Rebirths")) or 0
	end)

	-- ===== PRESTIGE SHARDS (RebirthCurrency) =====
	-- The attribute itself (not this leaderstat) is the source of truth --
	-- RebirthHandler.luau's PerformRebirth, and the Prestige Shop's own
	-- purchase/reward code, all read and write player:GetAttribute
	-- ("RebirthCurrency") directly. This leaderstat is a pure DISPLAY
	-- mirror driven by the attribute, so every future call site that
	-- changes the balance gets a correct display for free instead of
	-- needing to remember to also touch a leaderstat.
	--
	-- Previously nothing ever initialized this attribute at join -- it was
	-- only ever set the moment a player performed their NEXT rebirth this
	-- session, so a returning player with an already-nonzero balance saw
	-- nothing (attribute nil, shop balance reading 0) until they rebirthed
	-- again. Same bug shape as the Sanctum "stuck showing 0" issue.
	local rebirthCurrency = Instance.new("IntValue")
	rebirthCurrency.Name = "Prestige Shards"
	rebirthCurrency.Value = tonumber(data.RebirthCurrency) or 0
	rebirthCurrency.Parent = leaderstats

	player:SetAttribute("RebirthCurrency", tonumber(data.RebirthCurrency) or 0)
	player:GetAttributeChangedSignal("RebirthCurrency"):Connect(function()
		local value = tonumber(player:GetAttribute("RebirthCurrency")) or 0
		data.RebirthCurrency = value
		rebirthCurrency.Value = value
	end)

	-- Mirror Prestige Shop levels onto attributes, same reasoning as the
	-- SanctumUpgrades mirror above: the systems those upgrades affect
	-- (EssenceMultiplier, EssenceOrbController, OrbClickManager,
	-- CursorCollection, RebirthHandler) all read the attribute directly.
	if type(data.RebirthShopUpgrades) ~= "table" then
		data.RebirthShopUpgrades = {}
	end
	for upgradeId, level in pairs(data.RebirthShopUpgrades) do
		player:SetAttribute(upgradeId, level)
	end

	for _, value in pairs(data.Essences) do
		local discovered = value.Discovered
		local V = Instance.new("BoolValue")
		V.Value = discovered
		V.Name = value.DisplayName
		V.Parent = player
	end

	for name, value in pairs(data.Settings) do
		player:SetAttribute(string.gsub(name, "%s", ""), value)
	end

	for id, owned in pairs(data.Gamepasses) do
		player:SetAttribute(tonumber(id), owned.Owned)
	end
	
	-- CriticalsController and NewPlayerLuckIndicator.client.luau both read
	-- this directly (never data.FirstJoinAt, which they can't reach) --
	-- nil while ineligible or expired, a real future timestamp for the
	-- first 24 hours after a genuinely brand-new save's first join.
	player:SetAttribute("NewPlayerLuckExpiresAt", NewPlayerLuckConfig.GetExpiresAt(data.FirstJoinAt))

	-- Zones: mirror the current zone id + each PAID zone's unlock flag
	-- onto attributes. GetEssence.luau's roll runs client-side on every
	-- orb spawn and needs this readable without a remote round trip, same
	-- reasoning as every other per-system mirror above. earth_zone is
	-- never mirrored as its own unlock flag -- ZonesConfig.IsZoneUnlocked
	-- already treats a free (UnlockCost <= 0) zone as unconditionally
	-- unlocked regardless of what's saved, so there's nothing to check.
	if type(data.Zones) ~= "table" then
		data.Zones = { Current = "earth_zone", Unlocked = {} }
	end
	if type(data.Zones.Unlocked) ~= "table" then
		data.Zones.Unlocked = {}
	end

	player:SetAttribute("CurrentZoneId", tostring(data.Zones.Current or "earth_zone"))
	for _, zone in ipairs(ZonesConfig.Zones) do
		if zone.UnlockCost > 0 then
			player:SetAttribute(ZonesConfig.UnlockedAttributeName(zone.Id), data.Zones.Unlocked[zone.Id] == true)
		end
	end

	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("SeenTutorial", data.SeenTutorial)
	player:SetAttribute("SeenFirstCrit", data.SeenFirstCrit)
	player:SetAttribute("SeenFavoritePrompt", data.SeenFavoritePrompt)
	player:SetAttribute("SeenWhatsNewVersion", tonumber(data.SeenWhatsNewVersion) or 0)
	
	for name, level in pairs(data.Upgrades) do
		player:SetAttribute(name, level)
	end
	
	for ID, has in pairs(data.Badges) do
		player:SetAttribute(ID, has)
	end
	
	if not player:GetAttribute("1219109424164715") then
		player:SetAttribute("1219109424164715", true)
		BS:AwardBadgeAsync(player.UserId,1219109424164715)
	end
	
	local SE = {}
	local savedEPM = {}
	
	for essence, dict in pairs(data.Essences) do
		SE[essence] = dict.Quantity
		local temp = dict.savedEPM
		if not temp or temp == 0 then 
			temp = 50
		end
		savedEPM[essence] = temp
	end

	EPMService.ActiveSessions[player.UserId] = {
		JoinTime = os.time(),
		StartingEssences = SE,
		SavedEPM = savedEPM
	}
	sessionStartTime[player.UserId] = os.clock()
end

-- ============================================================
-- SAVE
-- ============================================================
local function savePlayerData(player, isFinalSave)
	local clone = player:FindFirstChild("PlayerData")
	if not clone then return end 

	local userId = player.UserId
	if saveLocks[userId] then return end
	saveLocks[userId] = true

	local data = require(clone) 

	local session = EPMService.ActiveSessions[player.UserId]
	local EPMs = {}
	if session then
		EPMs = EPMService.getEPM(player)
	end	

	if EPMs then
		for essence, EPM in pairs(EPMs) do
			if data.Essences[essence] then
				data.Essences[essence].savedEPM = EPM
			end
		end
	end

	data.LastLeaveTime = os.time()

	if sessionStartTime[userId] then
		data.PlayTime = (data.PlayTime or 0) + (os.clock() - sessionStartTime[userId])
		sessionStartTime[userId] = os.clock()
	end

	local key = "Player_" .. userId
	local success, err = withRetries(function()
		return playerDataStore:UpdateAsync(key, function(oldData)
			oldData = oldData or {}
			applySavedData(oldData, data) 
			return oldData
		end)
	end)

	EPMService.ActiveSessions[player.UserId] = nil
	saveLocks[userId] = nil

	if not success then
		warn("PlayerDataHandler: FAILED to save data for " .. player.Name .. " (" .. userId .. "): " .. tostring(err))
	elseif isFinalSave then
		print("PlayerDataHandler: final save complete for " .. player.Name)
	end
end

-- ============================================================
-- PLAYER LIFECYCLE
-- ============================================================
Players.PlayerAdded:Connect(loadPlayerData)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player, true)
	sessionStartTime[player.UserId] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() then return end

	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then return end

	for _, player in ipairs(players) do
		task.spawn(function()
			savePlayerData(player, true)

			-- savePlayerData no-ops immediately if a save for this player
			-- was ALREADY in flight (saveLocks -- see its own comment) --
			-- almost always another autosave. Normally that's fine, since
			-- another one runs in 2 minutes regardless. Here it isn't: if
			-- this callback moved on believing the player is saved while
			-- that pre-existing save is still actually running, it can get
			-- killed by the process terminating right after BindToClose
			-- returns, silently losing whatever it hadn't written yet.
			-- Wait for it to actually finish before counting this player
			-- as done. Capped so one stuck lock can't hang every other
			-- player's own wait below it.
			local userId = player.UserId
			local lockWaited = 0
			while saveLocks[userId] and lockWaited < 20 do
				task.wait(0.5)
				lockWaited += 0.5
			end

			remaining -= 1
		end)
	end

	local waited = 0
	while remaining > 0 and waited < 25 do
		task.wait(1)
		waited += 1
	end
end)

-- ============================================================
-- AUTOSAVE
-- ============================================================
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if player:FindFirstChild("PlayerData") then
				task.spawn(savePlayerData, player, false)
			end
		end
	end
end)
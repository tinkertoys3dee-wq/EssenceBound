--[[
	ZoneService (Script -> ServerScriptService)
	===============================================
	Server-authoritative Zones: the client can only ever ASK to unlock or
	switch to a zone (see ZonesConfig for what a zone actually is and
	ZonePanel.client.luau for the picker UI) -- this validates the request,
	deducts every configured essence cost for an unlock (same leaderstat-Quantity-attribute
	pattern TreeUpgrades.PurchaseUpgrade already uses for every other
	purchase in the game), and is the only thing that actually flips
	CurrentZoneId or a zone's unlock flag.

	Switching between zones you already own is free and unlimited -- only
	the FIRST unlock ever costs anything. Unlocking a zone also switches
	you to it immediately (you almost certainly want to go there right
	after paying for it); ZonePanel plays its travel animation off the
	result of either call, never optimistically before the server confirms.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZonesConfig = require(ReplicatedStorage:WaitForChild("ZonesConfig"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))

-- =========================================================================
-- REMOTES
-- =========================================================================

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

local remotesFolder = ReplicatedStorage:FindFirstChild("ZoneRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "ZoneRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

local UnlockZoneFunction = ensureRemote(remotesFolder, "RemoteFunction", "UnlockZone")
local SwitchZoneFunction = ensureRemote(remotesFolder, "RemoteFunction", "SwitchZone")

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

-- Guarantees the Zones sub-table exists and is shaped correctly, even for
-- a save written before this system existed -- same reasoning as
-- WheelService's getWheel.
local function getZones(player)
	local data = getData(player)
	if not data then
		return nil, nil
	end

	local zones = data.Zones
	if type(zones) ~= "table" then
		zones = {}
		data.Zones = zones
	end
	if type(zones.Unlocked) ~= "table" then
		zones.Unlocked = {}
	end
	if type(zones.Current) ~= "string" or not ZonesConfig.GetZoneById(zones.Current) then
		zones.Current = ZonesConfig.Zones[1].Id
	end

	return zones, data
end

-- Applies a confirmed zone switch to both the save and the attribute
-- ZonesConfig/GetEssence/the client all actually read.
local function setCurrentZone(player, zones, zoneId)
	zones.Current = zoneId
	player:SetAttribute("CurrentZoneId", zoneId)
end

-- =========================================================================
-- UNLOCK
-- =========================================================================

-- Returns (success: boolean, message: string?, result: table?) -- same
-- convention as WheelService's SpinFunction.
UnlockZoneFunction.OnServerInvoke = function(player, zoneId)
	local zone = ZonesConfig.GetZoneById(zoneId)
	if not zone then
		return false, "That zone doesn't exist."
	end

	local unlockCosts = ZonesConfig.GetUnlockCosts(zone)
	if not next(unlockCosts) then
		return false, "This zone is already unlocked."
	end

	local rebirths = tonumber(player:GetAttribute("Rebirths")) or 0
	if rebirths < (tonumber(zone.RebirthRequired) or 0) then
		return false, ("Reach Rebirth %d first."):format(zone.RebirthRequired)
	end

	local zones = getZones(player)
	if not zones then
		return false, "Still loading -- try again in a moment."
	end

	if zones.Unlocked[zoneId] == true then
		return false, "You already own this zone."
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false, "Still loading -- try again in a moment."
	end

	-- Validate the complete mixed cost before touching a balance, then
	-- deduct as one transaction. A missing/short second currency can never
	-- leave the first one partially spent.
	local deductions = {}
	for currencyKey, amount in pairs(unlockCosts) do
		local definition = EssenceConfig.Get(currencyKey)
		local stat = definition and leaderstats:FindFirstChild(definition.Name)
		if not stat then
			return false, "Still loading -- try again in a moment."
		end
		local current = tonumber(stat:GetAttribute("Quantity")) or 0
		if current < amount then
			return false, ("Not enough %s."):format(definition.Name)
		end
		table.insert(deductions, { Stat = stat, NewQuantity = current - amount })
	end

	for _, deduction in ipairs(deductions) do
		deduction.Stat:SetAttribute("Quantity", deduction.NewQuantity)
	end

	zones.Unlocked[zoneId] = true
	player:SetAttribute(ZonesConfig.UnlockedAttributeName(zoneId), true)

	-- You just paid to get here -- take them there immediately rather
	-- than making a second click do it.
	setCurrentZone(player, zones, zoneId)

	return true, nil, { ZoneId = zoneId }
end

-- =========================================================================
-- SWITCH
-- =========================================================================

SwitchZoneFunction.OnServerInvoke = function(player, zoneId)
	local zone = ZonesConfig.GetZoneById(zoneId)
	if not zone then
		return false, "That zone doesn't exist."
	end

	local zones = getZones(player)
	if not zones then
		return false, "Still loading -- try again in a moment."
	end

	if not ZonesConfig.IsZoneUnlocked(player, zoneId) then
		return false, "Unlock this zone first."
	end

	if zones.Current == zoneId then
		return false, "You're already there."
	end

	setCurrentZone(player, zones, zoneId)

	return true, nil, { ZoneId = zoneId }
end

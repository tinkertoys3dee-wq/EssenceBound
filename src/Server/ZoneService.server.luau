--[[
	ZoneService (Script -> ServerScriptService)
	===============================================
	Server-authoritative Zones: the client can only ever ASK to unlock or
	switch to a zone (see ZonesConfig for what a zone actually is and
	ZonePanel.client.luau for the picker UI) -- this validates the request,
	deducts Earth Essence for an unlock (same leaderstat-Quantity-attribute
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

	if zone.UnlockCost <= 0 then
		return false, "This zone is already unlocked."
	end

	local zones = getZones(player)
	if not zones then
		return false, "Still loading -- try again in a moment."
	end

	if zones.Unlocked[zoneId] == true then
		return false, "You already own this zone."
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild("Earth Essence")
	if not stat then
		return false, "Still loading -- try again in a moment."
	end

	local current = tonumber(stat:GetAttribute("Quantity")) or 0
	if current < zone.UnlockCost then
		return false, "Not enough Earth Essence."
	end

	stat:SetAttribute("Quantity", current - zone.UnlockCost)

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

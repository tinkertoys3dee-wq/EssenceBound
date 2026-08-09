-- Server-authoritative state for Resonance. OrbClickManager calls
-- ProcessCollection only after its normal payload validation succeeds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ResonanceConfig"))
local Service = {}
local states = {}

local folder = ReplicatedStorage:FindFirstChild("ResonanceRemotes") or Instance.new("Folder")
folder.Name = "ResonanceRemotes"
folder.Parent = ReplicatedStorage

local sync = folder:FindFirstChild("Sync") or Instance.new("RemoteEvent")
sync.Name = "Sync"
sync.Parent = folder
local activate = folder:FindFirstChild("Activate") or Instance.new("RemoteEvent")
activate.Name = "Activate"
activate.Parent = folder
local requestSnapshot = folder:FindFirstChild("RequestSnapshot") or Instance.new("RemoteFunction")
requestSnapshot.Name = "RequestSnapshot"
requestSnapshot.Parent = folder

local function getData(player)
	local module = player:FindFirstChild("PlayerData")
	if not module then
		return nil
	end
	local ok, data = pcall(require, module)
	return ok and data or nil
end

local function getPersistent(player)
	local data = getData(player)
	if not data then
		return nil
	end
	if type(data.Resonance) ~= "table" then
		data.Resonance = {}
	end
	local value = data.Resonance
	value.MasteryLevel = math.clamp(math.floor(tonumber(value.MasteryLevel) or 0), 0, Config.Mastery.MaxLevel)
	value.MasteryXP = math.max(0, math.floor(tonumber(value.MasteryXP) or 0))
	value.LifetimeAlternations = math.max(0, math.floor(tonumber(value.LifetimeAlternations) or 0))
	value.BestHarmony = math.max(0, math.floor(tonumber(value.BestHarmony) or 0))
	value.OverdrivesActivated = math.max(0, math.floor(tonumber(value.OverdrivesActivated) or 0))
	return value
end

local function stateFor(player)
	local state = states[player]
	if not state then
		state = {
			Harmony = 0,
			Pulse = 0,
			LastType = nil,
			LastAt = 0,
			HarmonyGeneration = 0,
			OverdriveUntil = 0,
			LastActivation = 0,
		}
		states[player] = state
	end
	return state
end

local function snapshot(player)
	local state = stateFor(player)
	local persistent = getPersistent(player)
	return {
		Harmony = state.Harmony,
		Pulse = state.Pulse,
		OverdriveRemaining = math.max(0, state.OverdriveUntil - workspace:GetServerTimeNow()),
		MasteryLevel = persistent and persistent.MasteryLevel or 0,
		MasteryXP = persistent and persistent.MasteryXP or 0,
		MasteryNeeded = Config.XPForLevel((persistent and persistent.MasteryLevel or 0) + 1),
		BestHarmony = persistent and persistent.BestHarmony or 0,
		OverdrivesActivated = persistent and persistent.OverdrivesActivated or 0,
	}
end

local function send(player)
	if player.Parent then
		sync:FireClient(player, snapshot(player))
	end
end

local function addMastery(player, amount)
	local persistent = getPersistent(player)
	if not persistent or persistent.MasteryLevel >= Config.Mastery.MaxLevel then
		return
	end
	persistent.MasteryXP += amount
	while persistent.MasteryLevel < Config.Mastery.MaxLevel do
		local needed = Config.XPForLevel(persistent.MasteryLevel + 1)
		if persistent.MasteryXP < needed then
			break
		end
		persistent.MasteryXP -= needed
		persistent.MasteryLevel += 1
	end
	player:SetAttribute("ResonanceMasteryLevel", persistent.MasteryLevel)
end

function Service.ProcessCollection(player, orbType, isCritical)
	local now = workspace:GetServerTimeNow()
	local state = stateFor(player)
	local persistent = getPersistent(player)

	if now - state.LastAt > Config.ComboWindow then
		state.Harmony = 0
	end
	if state.LastType and state.LastType ~= orbType then
		state.Harmony = math.min(Config.MaxHarmony, state.Harmony + 1)
		if persistent then
			persistent.LifetimeAlternations += 1
			persistent.BestHarmony = math.max(persistent.BestHarmony, state.Harmony)
		end
	elseif state.LastType == orbType then
		state.Harmony = 0
	end
	state.LastType, state.LastAt = orbType, now
	state.HarmonyGeneration += 1
	local harmonyGeneration = state.HarmonyGeneration

	-- The multiplier attribute must expire even if this player stops
	-- collecting. Without a server timer, Harmony remained active forever and
	-- incorrectly boosted idle earnings. The generation token makes each
	-- player's latest collection supersede only their own older timer.
	task.delay(Config.ComboWindow, function()
		local current = states[player]
		if not current or current.HarmonyGeneration ~= harmonyGeneration then
			return
		end
		current.Harmony = 0
		current.LastType = nil
		if player.Parent then
			player:SetAttribute("ResonanceHarmony", 0)
			send(player)
		end
	end)

	if state.OverdriveUntil > now then
		state.OverdriveUntil =
			math.min(now + Config.MaxOverdriveSeconds, state.OverdriveUntil + Config.ExtensionPerCollection)
	else
		state.Pulse = math.min(
			Config.PulseRequired,
			state.Pulse + Config.PulsePerCollection + (isCritical and Config.PulsePerCritical or 0)
		)
	end

	addMastery(player, Config.Mastery.BaseXP + (isCritical and Config.Mastery.CriticalXP or 0))
	player:SetAttribute("ResonanceHarmony", state.Harmony)
	player:SetAttribute("ResonanceActive", state.OverdriveUntil > now)
	send(player)
end

activate.OnServerEvent:Connect(function(player)
	local state = stateFor(player)
	local now = workspace:GetServerTimeNow()
	if state.Pulse < Config.PulseRequired or state.OverdriveUntil > now or now - state.LastActivation < 1 then
		return
	end
	state.LastActivation = now
	state.Pulse = 0
	state.OverdriveUntil = now + Config.OverdriveSeconds
	local persistent = getPersistent(player)
	if persistent then
		persistent.OverdrivesActivated += 1
	end
	player:SetAttribute("ResonanceActive", true)
	send(player)
	task.spawn(function()
		-- Collections can extend the deadline, so re-read it after every sleep
		-- rather than scheduling one stale timer at activation time.
		while player.Parent do
			local current = states[player]
			if not current then
				return
			end
			local remaining = current.OverdriveUntil - workspace:GetServerTimeNow()
			if remaining <= 0 then
				break
			end
			task.wait(math.min(remaining, 1))
		end
		if player.Parent then
			player:SetAttribute("ResonanceActive", false)
			send(player)
		end
	end)
end)

-- A RemoteFunction avoids the PlayerAdded/LocalScript startup race: an
-- initial RemoteEvent can fire before the client has connected its listener.
-- No client input is accepted and snapshots are scoped to the invoking
-- player, so one player can never query another player's session state.
requestSnapshot.OnServerInvoke = function(player)
	return snapshot(player)
end

local function initializePlayer(player)
	task.spawn(function()
		player:WaitForChild("PlayerData", 30)
		local persistent = getPersistent(player)
		player:SetAttribute("ResonanceMasteryLevel", persistent and persistent.MasteryLevel or 0)
		player:SetAttribute("ResonanceHarmony", 0)
		player:SetAttribute("ResonanceActive", false)
		send(player)
	end)
end

Players.PlayerAdded:Connect(initializePlayer)
for _, player in Players:GetPlayers() do
	initializePlayer(player)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

return Service

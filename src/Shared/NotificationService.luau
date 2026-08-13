--[[
	NotificationService (ModuleScript -> ReplicatedStorage)
	========================================================
	One small API for every piece of actionable player feedback. Client
	scripts can push immediate local messages; server scripts can send the
	authoritative reason a request was denied. NotificationController owns
	the presentation, queueing and duplicate merging.

	The server never listens to this RemoteEvent. That is deliberate: a
	client can display its own cosmetic message, but it cannot ask the
	server to broadcast arbitrary text to anyone else.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NotificationService = {}

local FOLDER_NAME = "NotificationRemotes"
local REMOTE_NAME = "PushNotification"
local VALID_KINDS = {
	Info = true,
	Success = true,
	Warning = true,
	Error = true,
}
local DEFAULT_TITLES = {
	Info = "Heads Up",
	Success = "Success",
	Warning = "Not Yet",
	Error = "Something Went Wrong",
}
local DEFAULT_ICONS = {
	Info = "i",
	Success = "✓",
	Warning = "!",
	Error = "×",
}
local DEFAULT_PRIORITIES = {
	Info = 1,
	Success = 2,
	Warning = 3,
	Error = 4,
}

local localEvent = RunService:IsClient() and Instance.new("BindableEvent") or nil
local serverLastSent = setmetatable({}, { __mode = "k" })

local function truncate(value, limit)
	local result = tostring(value or "")
	if #result <= limit then
		return result
	end
	local cutAt = math.max(0, limit - 3)
	-- Limits are byte-based for network predictability, but never cut in
	-- the middle of an emoji/multibyte UTF-8 character.
	while cutAt > 0 do
		local byte = string.byte(result, cutAt)
		if not byte or byte < 128 or byte >= 192 then
			break
		end
		cutAt -= 1
	end
	return string.sub(result, 1, cutAt) .. "..."
end

local function copyOptions(options)
	local result = {}
	if type(options) == "table" then
		for key, value in pairs(options) do
			result[key] = value
		end
	end
	return result
end

local function normalize(messageOrPayload, options)
	local payload = copyOptions(options)
	if type(messageOrPayload) == "table" then
		for key, value in pairs(messageOrPayload) do
			payload[key] = value
		end
	else
		payload.Message = messageOrPayload
	end

	local requestedKind = tostring(payload.Kind or "Info")
	local kind = string.upper(string.sub(requestedKind, 1, 1)) .. string.lower(string.sub(requestedKind, 2))
	if not VALID_KINDS[kind] then
		kind = "Info"
	end

	local message = truncate(payload.Message, 220)
	if message == "" then
		message = "Something changed."
	end

	local title = truncate(payload.Title or DEFAULT_TITLES[kind], 56)
	local icon = truncate(payload.Icon or DEFAULT_ICONS[kind], 8)
	local duration = math.clamp(tonumber(payload.Duration) or (kind == "Error" and 4.5 or 3.6), 1.5, 8)
	local key = truncate(payload.Key or (kind .. ":" .. title .. ":" .. message), 120)
	local priority = math.clamp(math.floor(tonumber(payload.Priority) or DEFAULT_PRIORITIES[kind]), 1, 5)

	return {
		Kind = kind,
		Title = title,
		Message = message,
		Icon = icon,
		Duration = duration,
		Key = key,
		Priority = priority,
	}
end

local function ensureRemote()
	if not RunService:IsServer() then
		return nil
	end

	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	local remote = folder:FindFirstChild(REMOTE_NAME)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = folder
	end
	return remote
end

-- Immediate, client-only feedback. Use this for a local gate the client can
-- already see (a cooldown label, a completed quest, an unopened panel).
function NotificationService.Push(messageOrPayload, options)
	if not localEvent then
		return false
	end
	localEvent:Fire(normalize(messageOrPayload, options))
	return true
end

function NotificationService.GetSignal()
	return localEvent and localEvent.Event or nil
end

-- Server-authoritative feedback. A short per-key throttle protects the
-- player's screen if an exploiter or a stuck button fires a request loop.
function NotificationService.Send(player, messageOrPayload, options)
	if not RunService:IsServer() or not player or not player:IsA("Player") then
		return false
	end

	local payload = normalize(messageOrPayload, options)
	local cooldown = 0.65
	if type(options) == "table" and tonumber(options.Cooldown) then
		cooldown = math.clamp(tonumber(options.Cooldown), 0, 10)
	elseif type(messageOrPayload) == "table" and tonumber(messageOrPayload.Cooldown) then
		cooldown = math.clamp(tonumber(messageOrPayload.Cooldown), 0, 10)
	end

	local now = os.clock()
	local sentForPlayer = serverLastSent[player]
	if not sentForPlayer then
		sentForPlayer = {}
		serverLastSent[player] = sentForPlayer
	end
	if sentForPlayer[payload.Key] and now - sentForPlayer[payload.Key] < cooldown then
		return false
	end
	sentForPlayer[payload.Key] = now

	local remote = ensureRemote()
	if not remote then
		return false
	end
	remote:FireClient(player, payload)
	return true
end

function NotificationService.SendAll(messageOrPayload, options)
	if not RunService:IsServer() then
		return false
	end
	for _, player in ipairs(Players:GetPlayers()) do
		NotificationService.Send(player, messageOrPayload, options)
	end
	return true
end

local function pushKind(kind, message, options)
	local merged = copyOptions(options)
	merged.Kind = kind
	return NotificationService.Push(message, merged)
end

function NotificationService.Info(message, options)
	return pushKind("Info", message, options)
end

function NotificationService.Success(message, options)
	return pushKind("Success", message, options)
end

function NotificationService.Warning(message, options)
	return pushKind("Warning", message, options)
end

function NotificationService.Error(message, options)
	return pushKind("Error", message, options)
end

-- Requiring the module from NotificationBootstrap guarantees the remote is
-- available before any gameplay service needs to send its first message.
if RunService:IsServer() then
	ensureRemote()
end

return NotificationService

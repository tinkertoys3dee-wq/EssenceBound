--[[
	PresentationCoordinator (ModuleScript -> ReplicatedStorage)
	============================================================
	One client-side queue for every automatic presentation that temporarily
	competes for the player's attention. Individual systems used to maintain
	their own queues, which prevented duplicates inside one feature but still
	allowed Tutorial, Offline Rewards, discoveries, badges, Daily Rewards and
	Hollowed One encounters to appear on top of one another.

	Acquire() yields until this presentation owns the single foreground slot.
	Release() opens that slot after a short quiet gap. Priority only chooses
	which already-waiting request goes next; an active presentation is never
	preempted, so player-controlled dialogs cannot be torn away mid-action.

	This module is intentionally presentation-only. It never gates rewards,
	progression, purchases or server events.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not player then
	error("PresentationCoordinator can only be required by a LocalScript")
end

local playerGui = player:WaitForChild("PlayerGui")

-- All LocalScripts on a client must share the same queue even if Roblox
-- evaluates this ModuleScript concurrently during startup. Reuse the first
-- coordinator cached in this client environment.
local cached = rawget(_G, "EssencePresentationCoordinator")
if type(cached) == "table" then
	return cached
end

local Coordinator = {}
rawset(_G, "EssencePresentationCoordinator", Coordinator)

local DEFAULT_QUIET_AFTER = 0.55
-- Readiness is session-lifecycle state, not something to inherit from a
-- recycled PlayerGui attribute. LoadingScreen (or the development fallback)
-- is the only component allowed to open the first foreground slot.
local ready = false
playerGui:SetAttribute("PresentationReady", false)
local activeRequest = nil
local queue = {}
local requestSequence = 0
local nextGrantAt = 0
local pumpVersion = 0
local loadingScreenSeen = false

local changedSignal = Instance.new("BindableEvent")
Coordinator.Changed = changedSignal.Event
local pump
local schedulePump

local function activeOwner()
	return activeRequest and activeRequest.Owner or nil
end

local function publishState()
	playerGui:SetAttribute("PresentationOwner", activeOwner())
	playerGui:SetAttribute("PresentationQueueDepth", #queue)
	changedSignal:Fire(activeOwner(), #queue, ready)
end

local function sortQueue()
	table.sort(queue, function(a, b)
		if a.Priority == b.Priority then
			return a.Sequence < b.Sequence
		end
		return a.Priority > b.Priority
	end)
end

local function isEffectivelyVisible(guiObject, screenGui)
	if not screenGui.Enabled or not guiObject.Visible then
		return false
	end

	local ancestor = guiObject.Parent
	while ancestor and ancestor ~= screenGui do
		if ancestor:IsA("GuiObject") and not ancestor.Visible then
			return false
		end
		ancestor = ancestor.Parent
	end
	return true
end

-- Player-opened panels are not queue requests, but they still deserve the
-- same no-overlap guarantee. A name such as "Backdrop" is far too broad to
-- decide that by itself: the live place also contains decorative, always-on
-- backdrops that are not modals. We may track name-matched objects so existing
-- instances can opt in after parenting, but only the explicit
-- PresentationModal attribute is authoritative in hasVisibleModal().
local modalCandidates = {}

local function notifyModalStateChanged()
	-- Consumers query HasPendingPresentation() when Changed fires, so manual
	-- backdrop visibility participates in the same foreground state as queued
	-- automatic work. Also wake the pump immediately when a closing animation
	-- finally removes its last visible blocker.
	publishState()
	if schedulePump then
		schedulePump()
	end
end

local function trackModalCandidate(instance)
	if
		instance:IsA("GuiObject")
		and (instance.Name == "Backdrop" or instance:GetAttribute("PresentationModal") == true)
		and not modalCandidates[instance]
	then
		local record = { Connections = {} }
		modalCandidates[instance] = record

		local function observe(signal)
			table.insert(record.Connections, signal:Connect(notifyModalStateChanged))
		end

		observe(instance:GetPropertyChangedSignal("Visible"))
		observe(instance:GetPropertyChangedSignal("Active"))
		local ancestor = instance.Parent
		while ancestor and ancestor ~= playerGui do
			if ancestor:IsA("GuiObject") then
				observe(ancestor:GetPropertyChangedSignal("Visible"))
			elseif ancestor:IsA("ScreenGui") then
				observe(ancestor:GetPropertyChangedSignal("Enabled"))
			end
			ancestor = ancestor.Parent
		end
		notifyModalStateChanged()
	end
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	trackModalCandidate(descendant)
end
playerGui.DescendantAdded:Connect(trackModalCandidate)
playerGui.DescendantRemoving:Connect(function(descendant)
	local record = modalCandidates[descendant]
	if record then
		for _, connection in ipairs(record.Connections) do
			connection:Disconnect()
		end
		modalCandidates[descendant] = nil
		notifyModalStateChanged()
	end
end)

local function hasVisibleModal()
	for descendant in pairs(modalCandidates) do
		if not descendant.Parent then
			modalCandidates[descendant] = nil
			continue
		end
		local screenGui = descendant:FindFirstAncestorOfClass("ScreenGui")
		if
			screenGui
			and descendant:GetAttribute("PresentationModal") == true
			and isEffectivelyVisible(descendant, screenGui)
		then
			return true
		end
	end
	return false
end

schedulePump = function(delaySeconds: number?)
	pumpVersion += 1
	local version = pumpVersion
	task.delay(math.max(0, tonumber(delaySeconds) or 0), function()
		if version == pumpVersion then
			pump()
		end
	end)
end

pump = function()
	if not ready or activeRequest or #queue == 0 then
		return
	end

	-- Never place an automatic presentation over a panel the player opened
	-- themselves. Polling is intentionally low-frequency and only runs while
	-- there is queued work waiting behind a visible modal.
	if hasVisibleModal() then
		schedulePump(0.25)
		return
	end

	local remainingQuiet = nextGrantAt - os.clock()
	if remainingQuiet > 0 then
		schedulePump(remainingQuiet)
		return
	end

	sortQueue()
	local request = table.remove(queue, 1)
	while request and request.Cancelled do
		request.Signal:Fire(nil)
		request = table.remove(queue, 1)
	end
	if not request then
		publishState()
		return
	end

	local token = {
		Owner = request.Owner,
		QuietAfter = request.QuietAfter,
		Released = false,
	}
	request.Token = token
	activeRequest = request
	publishState()
	request.Signal:Fire(token)
end

function Coordinator.Acquire(owner: string, options)
	assert(type(owner) == "string" and owner ~= "", "Acquire requires a non-empty owner name")
	options = options or {}

	requestSequence += 1
	local signal = Instance.new("BindableEvent")
	local request = {
		Owner = owner,
		Priority = tonumber(options.Priority) or 0,
		QuietAfter = math.max(0, tonumber(options.QuietAfter) or DEFAULT_QUIET_AFTER),
		Sequence = requestSequence,
		Signal = signal,
		Cancelled = false,
	}
	table.insert(queue, request)
	publishState()

	-- Deferred pumping guarantees Event:Wait is listening before a grant can
	-- fire, including the common empty-queue/immediately-ready case.
	schedulePump()
	local token = signal.Event:Wait()
	signal:Destroy()
	return token
end

function Coordinator.Release(token, quietAfter: number?)
	if type(token) ~= "table" or token.Released then
		return false
	end
	if not activeRequest or activeRequest.Token ~= token then
		return false
	end

	token.Released = true
	activeRequest = nil
	nextGrantAt = os.clock() + math.max(0, tonumber(quietAfter) or token.QuietAfter or DEFAULT_QUIET_AFTER)
	publishState()
	schedulePump(math.max(0, nextGrantAt - os.clock()))
	return true
end

function Coordinator.CancelQueued(owner: string)
	local cancelled = 0
	for _, request in ipairs(queue) do
		if request.Owner == owner and not request.Cancelled then
			request.Cancelled = true
			cancelled += 1
		end
	end
	if cancelled > 0 then
		schedulePump()
	end
	return cancelled
end

-- Error-recovery only: lets a presentation release by owner when an
-- exception prevented its normal token-based cleanup from running.
function Coordinator.ForceRelease(owner: string, quietAfter: number?): boolean
	if not activeRequest or activeRequest.Owner ~= owner then
		return false
	end
	local token = activeRequest.Token
	return Coordinator.Release(token, quietAfter)
end

function Coordinator.IsBusy(): boolean
	return activeRequest ~= nil
end

function Coordinator.HasPendingPresentation(): boolean
	return not ready or activeRequest ~= nil or #queue > 0 or hasVisibleModal()
end

function Coordinator.HasVisibleModal(): boolean
	return hasVisibleModal()
end

function Coordinator.GetOwner(): string?
	return activeOwner()
end

function Coordinator.GetQueueDepth(): number
	return #queue
end

-- Manual panels do not need to join the automatic presentation queue, but
-- they must respect whatever currently owns the foreground and any other
-- player-opened modal. `allowedOwner` is deliberately narrow: Tutorial may
-- open Upgrades as part of its guided step, and an automatic panel may open
-- its own modal after acquiring the matching lease.
function Coordinator.CanOpenModal(allowedOwner: string?): boolean
	if not ready then
		-- A destroyed loading layer is stronger evidence than a missed boolean
		-- handoff. Recover immediately on the first real button press instead of
		-- making every menu wait for the slower development watchdog below.
		if playerGui:FindFirstChild("LoadingScreen") then
			return false
		end
		Coordinator.SetReady(true)
	end
	local owner = activeOwner()
	if owner ~= nil and owner ~= allowedOwner then
		return false
	end
	return not hasVisibleModal()
end

function Coordinator.SetReady(value: boolean?)
	ready = value ~= false
	playerGui:SetAttribute("PresentationReady", ready)
	if ready then
		schedulePump()
	else
		-- Invalidate any delayed grant that was scheduled before a loading
		-- layer took ownership of startup readiness.
		pumpVersion += 1
	end
	publishState()
end

function Coordinator.WaitUntilReady(timeoutSeconds: number?): boolean
	local deadline = timeoutSeconds and (os.clock() + timeoutSeconds) or math.huge
	while not ready and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	return ready
end

function Coordinator.WaitUntilIdle(quietSeconds: number?, timeoutSeconds: number?): boolean
	local requiredQuiet = math.max(0, tonumber(quietSeconds) or 0)
	local deadline = timeoutSeconds and (os.clock() + timeoutSeconds) or math.huge
	local idleSince = nil

	while os.clock() < deadline do
		if ready and not activeRequest and #queue == 0 and not hasVisibleModal() then
			idleSince = idleSince or os.clock()
			if os.clock() - idleSince >= requiredQuiet then
				return true
			end
		else
			idleSince = nil
		end
		RunService.Heartbeat:Wait()
	end
	return false
end

playerGui:GetAttributeChangedSignal("PresentationReady"):Connect(function()
	local attributeReady = playerGui:GetAttribute("PresentationReady") == true
	if ready ~= attributeReady then
		ready = attributeReady
		if ready then
			schedulePump()
		else
			pumpVersion += 1
		end
		publishState()
	end
end)

-- Recovery for development places that omit LoadingScreen.client entirely.
-- The grace period prevents a normal startup-order race from marking the
-- queue ready before LoadingScreen has had a chance to parent its GUI.
task.spawn(function()
	local startedAt = os.clock()
	local loadingScreenGoneAt = nil
	while playerGui.Parent and not ready do
		local loadingScreen = playerGui:FindFirstChild("LoadingScreen")
		if loadingScreen then
			loadingScreenSeen = true
			loadingScreenGoneAt = nil
		end
		if loadingScreenSeen then
			-- LoadingScreen owns the exact transition during normal startup. If
			-- that script is removed after building its GUI but errors before its
			-- final SetReady call, recover instead of leaving every queued system
			-- blocked for the rest of the session.
			if not loadingScreen then
				loadingScreenGoneAt = loadingScreenGoneAt or os.clock()
				if os.clock() - loadingScreenGoneAt >= 1 then
					Coordinator.SetReady(true)
					break
				end
			end
			task.wait(0.25)
			continue
		end
		if os.clock() - startedAt >= 8 then
			Coordinator.SetReady(true)
			break
		end
		task.wait(0.25)
	end
end)

publishState()

return Coordinator

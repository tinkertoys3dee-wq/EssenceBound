--[[
	EssenceDiscoveryPopup (LocalScript)

	Drop this into StarterPlayerScripts (or StarterGui).

	Usage from wherever you hook up your discovery event:

		local module = require(path.to.this.module) -- if you convert this to a ModuleScript
		module.Show("Shadow Essence", "1 in 50")

	As written below, this is a standalone LocalScript that exposes a
	global-ish function via a BindableEvent, so any other LocalScript
	can fire it without needing to require anything:

		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		ReplicatedStorage:WaitForChild("EssenceDiscovered"):Fire("Shadow Essence", "1 in 50")

	Fill in essence name + odds text wherever you fire that event.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local EssenceVisuals = require(ReplicatedStorage:WaitForChild("EssenceVisuals"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- Config
-- ============================================================

local POPUP_HOLD_TIME = 2.5      -- seconds fully visible before it starts leaving
local TWEEN_IN_TIME = 0.45
local TWEEN_OUT_TIME = 0.35
local MAX_QUEUED_DISCOVERIES = 2
local DISCOVERY_MAX_AGE = 20

-- ============================================================
-- Event other scripts fire to trigger this popup
-- ============================================================

local discoveredEvent = ReplicatedStorage:FindFirstChild("EssenceDiscovered")
if not discoveredEvent then
	discoveredEvent = Instance.new("BindableEvent")
	discoveredEvent.Name = "EssenceDiscovered"
	discoveredEvent.Parent = ReplicatedStorage
end

-- ============================================================
-- Build the ScreenGui
-- ============================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EssenceDiscoveryGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = playerGui

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, -140) -- starts above screen
-- Use the available viewport on narrow phones, but retain the authored
-- 340px card on larger screens. A fixed 340px width used to push both
-- rounded sides off-screen on small/mobile emulators.
card.Size = UDim2.new(0.9, 0, 0, 110)
card.BackgroundColor3 = Color3.fromRGB(18, 14, 26)
card.BorderSizePixel = 0
card.Parent = screenGui

local cardSizeConstraint = Instance.new("UISizeConstraint")
cardSizeConstraint.MaxSize = Vector2.new(340, 110)
cardSizeConstraint.Parent = card

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 14)
cardCorner.Parent = card

local cardStroke = Instance.new("UIStroke")
cardStroke.Thickness = 1.5
cardStroke.Color = Color3.fromRGB(120, 60, 200)
cardStroke.Transparency = 0.3
cardStroke.Parent = card

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 18, 42)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 8, 18)),
})
gradient.Rotation = 90
gradient.Parent = card

-- soft glow behind the card
local glow = Instance.new("ImageLabel")
glow.Name = "Glow"
glow.AnchorPoint = Vector2.new(0.5, 0.5)
glow.Position = UDim2.new(0.5, 0, 0.5, 0)
glow.Size = UDim2.new(1, 160, 1, 160)
glow.BackgroundTransparency = 1
glow.Image = "rbxasset://textures/ui/Glow.png"
glow.ImageColor3 = Color3.fromRGB(140, 70, 220)
glow.ImageTransparency = 0.55
glow.ZIndex = 0
glow.Parent = card

local orbPreview = Instance.new("ImageLabel")
orbPreview.Name = "DiscoveredOrb"
orbPreview.AnchorPoint = Vector2.new(0, 0.5)
orbPreview.Position = UDim2.fromScale(0.035, 0.55)
orbPreview.Size = UDim2.fromScale(0.2, 0.62)
orbPreview.BackgroundTransparency = 1
orbPreview.ZIndex = 3
orbPreview.Parent = card
local orbAspect = Instance.new("UIAspectRatioConstraint")
orbAspect.AspectRatio = 1
orbAspect.DominantAxis = Enum.DominantAxis.Height
orbAspect.Parent = orbPreview

-- top label: "New essence discovered!"
local header = Instance.new("TextLabel")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Position = UDim2.new(0.23, 0, 0, 10)
header.Size = UDim2.new(0.73, 0, 0, 22)
header.Font = Enum.Font.GothamBold
header.Text = "NEW ESSENCE DISCOVERED"
header.TextColor3 = Color3.fromRGB(200, 160, 255)
header.TextSize = 14
header.TextXAlignment = Enum.TextXAlignment.Center
header.ZIndex = 2
header.Parent = card

-- essence name (fill this in per-discovery)
local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "EssenceName"
nameLabel.BackgroundTransparency = 1
nameLabel.Position = UDim2.new(0.23, 0, 0, 36)
nameLabel.Size = UDim2.new(0.73, 0, 0, 34)
nameLabel.TextScaled = true
nameLabel.Font = Enum.Font.GothamBlack
nameLabel.Text = "Essence Name"
nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
nameLabel.TextSize = 26
nameLabel.TextXAlignment = Enum.TextXAlignment.Center
nameLabel.ZIndex = 2
nameLabel.Parent = card

local nameSizeConstraint = Instance.new("UITextSizeConstraint")
nameSizeConstraint.MaxTextSize = 26
nameSizeConstraint.MinTextSize = 12
nameSizeConstraint.Parent = nameLabel

-- odds (fill this in per-discovery)
local oddsLabel = Instance.new("TextLabel")
oddsLabel.Name = "Odds"
oddsLabel.BackgroundTransparency = 1
oddsLabel.Position = UDim2.new(0.23, 0, 0, 76)
oddsLabel.Size = UDim2.new(0.73, 0, 0, 22)
oddsLabel.Font = Enum.Font.Gotham
oddsLabel.Text = "Odds: 1 in 1"
oddsLabel.TextColor3 = Color3.fromRGB(170, 170, 180)
oddsLabel.TextSize = 15
oddsLabel.TextXAlignment = Enum.TextXAlignment.Center
oddsLabel.ZIndex = 2
oddsLabel.Parent = card

-- ============================================================
-- Show logic (queued so multiple discoveries don't overlap)
-- ============================================================

local queue = {}
local queuedNames = {}
local isShowing = false

local function playPopup(essenceName, oddsText, queuedAt)
	local lease = PresentationCoordinator.Acquire("EssenceDiscovery", {
		Priority = 55,
		QuietAfter = 1.25,
	})
	if not lease then
		return
	end
	-- The first item leaves this script's local queue while it waits for the
	-- global foreground slot. Re-check its age after that wait too, otherwise
	-- a discovery made under a long tutorial would still replay afterward.
	if os.clock() - (queuedAt or os.clock()) > DISCOVERY_MAX_AGE then
		PresentationCoordinator.Release(lease, 0)
		return
	end

	local definition = EssenceConfig.Get(essenceName) or EssenceConfig.Get("Earth Essence")
	nameLabel.Text = essenceName
	oddsLabel.Text = "Odds: " .. oddsText
	card:SetAttribute("AstralAccentColor", definition.Color)
	cardStroke.Color = definition.Color
	glow.ImageColor3 = definition.Color
	header.TextColor3 = definition.Color:Lerp(Color3.fromRGB(255, 255, 255), 0.28)
	nameLabel.TextColor3 = definition.Color:Lerp(Color3.fromRGB(255, 255, 255), 0.58)
	EssenceVisuals.ApplyToImage(orbPreview, essenceName)

	card.Position = UDim2.new(0.5, 0, 0, -140)
	card.Visible = true

	local tweenIn = TweenService:Create(
		card,
		TweenInfo.new(TWEEN_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, 24) }
	)
	tweenIn:Play()
	tweenIn.Completed:Wait()

	task.wait(POPUP_HOLD_TIME)

	local tweenOut = TweenService:Create(
		card,
		TweenInfo.new(TWEEN_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0.5, 0, 0, -140) }
	)
	tweenOut:Play()
	tweenOut.Completed:Wait()

	card.Visible = false
	PresentationCoordinator.Release(lease, 1.25)
end

local function processQueue()
	if isShowing then
		return
	end
	isShowing = true

	while #queue > 0 do
		local next = table.remove(queue, 1)
		if os.clock() - next.queuedAt > DISCOVERY_MAX_AGE then
			queuedNames[next.name] = nil
			continue
		end
		local ok, err = xpcall(function()
			playPopup(next.name, next.odds, next.queuedAt)
		end, debug.traceback)
		queuedNames[next.name] = nil
		if not ok then
			card.Visible = false
			PresentationCoordinator.ForceRelease("EssenceDiscovery", 1.25)
			warn("[NewDiscovery] Presentation failed: " .. tostring(err))
		end
	end

	isShowing = false
end

local function Show(essenceName, oddsText)
	if type(essenceName) ~= "string" or essenceName == "" or queuedNames[essenceName] then
		return
	end

	-- A lucky burst can discover several essences during Tutorial or another
	-- foreground beat. Their Index entries are already saved server-side, so
	-- showing an old avalanche after the player regains control only creates
	-- clutter. Keep at most two fresh, unique cards waiting behind the active
	-- one and quietly discard stale presentation work.
	if #queue >= MAX_QUEUED_DISCOVERIES then
		return
	end

	queuedNames[essenceName] = true
	table.insert(queue, {
		name = essenceName,
		odds = oddsText or "1 in 1",
		queuedAt = os.clock(),
	})
	processQueue()
end

-- ============================================================
-- Hook up the event
-- ============================================================

discoveredEvent.Event:Connect(function(essenceName, oddsText)
	Show(essenceName, oddsText)
end)

-- Example test call (remove once your real event is hooked up):
-- Show("Shadow Essence", "1 in 50")

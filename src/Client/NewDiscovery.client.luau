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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ============================================================
-- Config
-- ============================================================

local POPUP_HOLD_TIME = 2.5      -- seconds fully visible before it starts leaving
local TWEEN_IN_TIME = 0.45
local TWEEN_OUT_TIME = 0.35

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

-- top label: "New essence discovered!"
local header = Instance.new("TextLabel")
header.Name = "Header"
header.BackgroundTransparency = 1
header.Position = UDim2.new(0, 12, 0, 10)
header.Size = UDim2.new(1, -24, 0, 22)
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
nameLabel.Position = UDim2.new(0, 12, 0, 36)
nameLabel.Size = UDim2.new(1, -24, 0, 34)
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
oddsLabel.Position = UDim2.new(0, 12, 0, 76)
oddsLabel.Size = UDim2.new(1, -24, 0, 22)
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
local isShowing = false

local function playPopup(essenceName, oddsText)
	nameLabel.Text = essenceName
	oddsLabel.Text = "Odds: " .. oddsText

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
end

local function processQueue()
	if isShowing then
		return
	end
	isShowing = true

	while #queue > 0 do
		local next = table.remove(queue, 1)
		playPopup(next.name, next.odds)
	end

	isShowing = false
end

local function Show(essenceName, oddsText)
	table.insert(queue, { name = essenceName, odds = oddsText or "1 in 1" })
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

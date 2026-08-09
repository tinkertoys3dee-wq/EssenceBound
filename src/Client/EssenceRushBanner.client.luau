--[[
	EssenceRushBanner (LocalScript -> StarterPlayerScripts)
	========================================================
	Client-side reaction to EssenceRushService's server-wide timed event:
	an arrival flourish using the same Flash/FloatText/sound language the
	Essence Storm announcement already established (see OrbClicker.client.luau's
	EssenceStormEvent handler), plus a persistent countdown banner for the
	whole event -- unlike a storm, a Rush has no other ongoing visual, so
	"you're currently boosted" needs to stay visible the entire 4 minutes,
	not just flash once at the start.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local juiceLayer = Juice.GetLayer(playerGui)

local remotesFolder = ReplicatedStorage:WaitForChild("EssenceRushRemotes")
local RushRemote = remotesFolder:WaitForChild("EssenceRushEvent")

local RUSH_COLOR = Color3.fromRGB(255, 140, 60)

-- =========================================================================
-- BANNER UI -- sits below the ProgressionHud toast zone (0.055-0.14) so
-- the two can't visually collide if a daily/quest toast happens to land
-- during a Rush.
-- =========================================================================

local HIDDEN_POSITION = UDim2.fromScale(0.5, -0.12)
local VISIBLE_POSITION = UDim2.fromScale(0.5, 0.155)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EssenceRushBanner"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 45
screenGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = HIDDEN_POSITION
-- Scale down with narrow viewports instead of forcing the countdown into
-- a desktop-width pill. The max keeps the banner compact on wide screens.
banner.Size = UDim2.new(0.82, 0, 0, 52)
banner.BackgroundColor3 = Color3.fromRGB(40, 22, 10)
banner.BorderSizePixel = 0
banner.Visible = false
banner.ZIndex = 200
banner.Parent = screenGui

local bannerSizeConstraint = Instance.new("UISizeConstraint")
bannerSizeConstraint.MaxSize = Vector2.new(520, 52)
bannerSizeConstraint.Parent = banner

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(1, 0)
bannerCorner.Parent = banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = RUSH_COLOR
bannerStroke.Thickness = 2.5
bannerStroke.Parent = banner

local bannerGradient = Instance.new("UIGradient")
bannerGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 32, 12)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(36, 18, 8)),
})
bannerGradient.Rotation = 90
bannerGradient.Parent = banner

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBlack
label.Text = "🔥 1.5x ESSENCE RUSH -- 4:00"
label.TextColor3 = Color3.fromRGB(255, 220, 180)
label.TextScaled = true
label.ZIndex = 201
label.Parent = banner

local labelPadding = Instance.new("UIPadding")
labelPadding.PaddingLeft = UDim.new(0, 14)
labelPadding.PaddingRight = UDim.new(0, 14)
labelPadding.Parent = label

local labelSizeConstraint = Instance.new("UITextSizeConstraint")
labelSizeConstraint.MaxTextSize = 20
labelSizeConstraint.Parent = label

-- =========================================================================
-- COUNTDOWN
-- =========================================================================

local countdownThread = nil

local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%d:%02d", m, s)
end

local function hideBanner()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Position = HIDDEN_POSITION,
	}):Play()
	task.delay(0.4, function()
		if not countdownThread then
			banner.Visible = false
		end
	end)
end

local function showBanner(duration)
	if countdownThread then
		task.cancel(countdownThread)
	end

	banner.Visible = true
	banner.Position = HIDDEN_POSITION
	TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = VISIBLE_POSITION,
	}):Play()

	local endsAt = os.clock() + duration
	countdownThread = task.spawn(function()
		while true do
			local remaining = endsAt - os.clock()
			if remaining <= 0 then
				break
			end
			label.Text = "🔥 1.5x ESSENCE RUSH -- " .. formatCountdown(remaining)
			task.wait(1)
		end
		countdownThread = nil
		hideBanner()
	end)
end

-- =========================================================================
-- ARRIVAL FLOURISH (same visual language as the Essence Storm announcement)
-- =========================================================================

local function announceArrival()
	if not juiceLayer then
		return
	end

	Juice.Flash(juiceLayer, { Color = RUSH_COLOR, Peak = 0.4, Duration = 0.6 })
	Juice.FloatText(juiceLayer, UDim2.fromScale(0.5, 0.22), "🔥 ESSENCE RUSH! 🔥", {
		Color = RUSH_COLOR,
		Duration = 1.6,
		Rise = 50,
		TextSize = 36,
	})
	Juice.FloatText(juiceLayer, UDim2.fromScale(0.5, 0.28), "1.5x essence for everyone, right now", {
		Color = Color3.fromRGB(255, 255, 255),
		Duration = 1.8,
		Rise = 40,
		TextSize = 18,
	})

	local sound = Juice.FindSound("SFX/UI/UIPop")
	if sound then
		for i = 0, 2 do
			task.delay(i * 0.1, function()
				Juice.PlaySound(sound, { Pitch = 1.0 + i * 0.25, Volume = 0.6 })
			end)
		end
	end
end

-- =========================================================================
-- SYNC
-- =========================================================================

RushRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Start" then
		payload = payload or {}
		local duration = payload.Duration or 240
		announceArrival()
		showBanner(duration)
	elseif action == "End" then
		hideBanner()
	end
end)

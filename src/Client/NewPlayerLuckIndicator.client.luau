--[[
	NewPlayerLuckIndicator (LocalScript -> StarterPlayerScripts)
	================================================================
	A small badge shown for a brand-new player's first 24 hours (see
	NewPlayerLuckConfig -- the bonus itself lives in CriticalsController,
	entirely server-authoritative; this is purely a readout, same
	relationship FriendBonusIndicator.client.luau has to FriendBonusConfig).

	Deliberately visible and honest about the countdown rather than a
	silent, undisclosed boost: telling a new player plainly "you're extra
	lucky right now, and here's exactly how long that lasts" makes the
	crits that follow land as a confirmed, trustworthy pattern instead of
	something they might not even notice -- and a real, disclosed,
	benefit-only deadline is a legitimate reason to come back today, not
	a manufactured one. Nothing here is taken away when it expires; the
	permanent crit economy underneath is completely unaffected either way.

	Hidden entirely once expired (or for any player who was never
	eligible) -- there's nothing to show and nothing to explain.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local NewPlayerLuckConfig = require(ReplicatedStorage:WaitForChild("NewPlayerLuckConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local THEME = {
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Gold            = Color3.fromRGB(255, 205, 80),
	White           = Color3.fromRGB(255, 255, 255),
}

-- Stacked directly beneath FriendBonusIndicator's own holder (same x=0.985
-- column, which sits at y=0.03 with a height of 0.055 -- see that file's
-- LAYOUT comment for the rest of the right-edge map) so the two never
-- overlap on the rare, genuinely happy occasion a brand-new player already
-- has friends in the server too.
local LAYOUT = {
	HolderAnchor = Vector2.new(1, 0),
	HolderPosition = UDim2.fromScale(0.985, 0.1),
	HolderSize = UDim2.fromScale(0.21, 0.055),
}

local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0.3, 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 1.5, Transparency = transparency or 0.2 }, parent)
end

-- =========================================================================
-- BUILD
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "NewPlayerLuckIndicator",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 42,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local holder = new("Frame", {
	Name = "Holder",
	AnchorPoint = LAYOUT.HolderAnchor,
	Position = LAYOUT.HolderPosition,
	Size = LAYOUT.HolderSize,
	BackgroundTransparency = 1,
	Visible = false,
}, screenGui)

local badge = new("Frame", {
	Name = "Badge",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BackgroundLight,
	BorderSizePixel = 0,
}, holder)
corner(badge, UDim.new(0.28, 0))
stroke(badge, THEME.Gold, 1.5, 0.2)

new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(40, 20, 64), Color3.fromRGB(20, 10, 34)),
	Rotation = 90,
}, badge)

local iconBg = new("Frame", {
	Name = "IconBg",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0.05, 0, 0.5, 0),
	Size = UDim2.new(0, 0, 0.68, 0),
	BackgroundColor3 = THEME.Gold,
}, badge)
corner(iconBg, UDim.new(0.5, 0))
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, iconBg)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🍀",
	TextScaled = true,
}, iconBg)

local percentLbl = new("TextLabel", {
	Name = "Percent",
	Position = UDim2.new(0.27, 0, 0.06, 0),
	Size = UDim2.new(0.68, 0, 0.44, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.Gold,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = ("+%d%% Crit Chance"):format(math.floor(0.5 + 100 * NewPlayerLuckConfig.CritChanceBonus)),
}, badge)
new("UITextSizeConstraint", { MaxTextSize = 16 }, percentLbl)

local subLbl = new("TextLabel", {
	Name = "SubLabel",
	Position = UDim2.new(0.27, 0, 0.52, 0),
	Size = UDim2.new(0.68, 0, 0.4, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	TextColor3 = THEME.White,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
}, badge)
new("UITextSizeConstraint", { MaxTextSize = 13 }, subLbl)

-- Seeded up front for the same reason FriendBonusIndicator seeds its own
-- badge scale: without this, Punch/the reveal tween below could cache a
-- mid-flight scale as "resting" instead of a clean 1.
local badgeScale = Juice.GetScale(badge)
if badgeScale and not badgeScale:GetAttribute("JuiceBaseScale") then
	badgeScale:SetAttribute("JuiceBaseScale", 1)
end

-- =========================================================================
-- UPDATE
-- =========================================================================

local function formatRemaining(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return ("%dh %dm left"):format(hours, minutes)
	elseif minutes > 0 then
		return ("%dm left"):format(minutes)
	end
	return "<1m left"
end

local function getRemainingSeconds()
	local expiresAt = player:GetAttribute("NewPlayerLuckExpiresAt")
	if type(expiresAt) ~= "number" then
		return nil
	end

	local remaining = expiresAt - os.time()
	if remaining <= 0 then
		return nil
	end
	return remaining
end

local shown = false

local function update()
	local remaining = getRemainingSeconds()

	if not remaining then
		if shown then
			shown = false
			holder.Visible = false
		end
		return
	end

	subLbl.Text = ("New Adventurer's Luck -- %s"):format(formatRemaining(remaining))

	if not shown then
		shown = true
		holder.Visible = true
		if badgeScale then
			badgeScale.Scale = 0.6
			TweenService:Create(badgeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	end
end

-- NewPlayerLuckExpiresAt only ever gets set once, at load, by
-- PlayerDataHandler.server.luau's async DataStore fetch -- this listener
-- covers the case where this script starts running before that finishes.
player:GetAttributeChangedSignal("NewPlayerLuckExpiresAt"):Connect(update)
update()

-- Live countdown -- 24 hours of granularity doesn't need per-second
-- updates; once a minute keeps the "Xh Ym left" text honest without
-- wasted work. Runs for the rest of the session; the cost of checking an
-- already-expired timestamp every 30s is negligible, same tradeoff this
-- codebase already makes for its other ambient background loops.
task.spawn(function()
	while true do
		task.wait(30)
		if not player.Parent then
			break
		end
		update()
	end
end)

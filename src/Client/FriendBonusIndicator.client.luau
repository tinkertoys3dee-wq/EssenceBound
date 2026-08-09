--[[
	FriendBonusIndicator (LocalScript -> StarterPlayerScripts)
	=============================================================
	A small badge that appears whenever real Roblox friends are present in
	the same server, showing the live essence bonus they're worth (see
	FriendBonusConfig for the formula, FriendBonusService.server.luau for
	how the FriendsInServer attribute it reads gets computed). Hidden
	entirely at 0 friends -- there's nothing to celebrate and nothing to
	explain in the common case.

	Purely a readout: there's no button here, nothing to click. The bonus
	is already applying server-side via EssenceMultiplier regardless of
	whether this is ever seen.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FriendBonusConfig = require(ReplicatedStorage:WaitForChild("FriendBonusConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local THEME = {
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
}

-- Top-right corner. Every other ambient status widget in this codebase
-- packs the right shortcut rail at x=0.952-0.996 from y=0.213 down to ~0.85
-- (RebirthShop/Sanctum/Leaderboard/Achievements/Daily-Quest-Codes/
-- GroupReward -- see GroupRewardPrompt.client.luau's LAYOUT comment), and
-- the Left panel owns the currency/stats column. y=0.03 sits above all of
-- that with clear room.
local LAYOUT = {
	HolderAnchor = Vector2.new(1, 0),
	HolderPosition = UDim2.fromScale(0.985, 0.03),
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
	Name = "FriendBonusIndicator",
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

-- Plain Frame, not CanvasGroup: nothing here uses GroupTransparency, so
-- there's no reason to pay for group compositing (see Juice.luau's own
-- performance notes -- this game targets phones and low-end laptops).
local badge = new("Frame", {
	Name = "Badge",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BackgroundLight,
	BorderSizePixel = 0,
}, holder)
corner(badge, UDim.new(0.28, 0))
stroke(badge, THEME.Green, 1.5, 0.2)

new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(40, 20, 64), Color3.fromRGB(20, 10, 34)),
	Rotation = 90,
}, badge)

local iconBg = new("Frame", {
	Name = "IconBg",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0.05, 0, 0.5, 0),
	Size = UDim2.new(0, 0, 0.68, 0),
	BackgroundColor3 = THEME.Green,
}, badge)
corner(iconBg, UDim.new(0.5, 0))
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, iconBg)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "👥",
	TextScaled = true,
}, iconBg)

local percentLbl = new("TextLabel", {
	Name = "Percent",
	Position = UDim2.new(0.27, 0, 0.06, 0),
	Size = UDim2.new(0.68, 0, 0.44, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.Green,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "+0% Essence",
}, badge)
new("UITextSizeConstraint", { MaxTextSize = 16 }, percentLbl)

local friendsLbl = new("TextLabel", {
	Name = "FriendsLabel",
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
new("UITextSizeConstraint", { MaxTextSize = 13 }, friendsLbl)

-- Seeded to a known-good base of 1 up front, rather than letting Punch
-- auto-cache it on first call: without this, a second friend joining
-- while the reveal-pop tween (below) is still mid-flight would cache
-- whatever in-between scale it caught as the "resting" value, and every
-- future punch would settle back to that wrong size instead of 1.
local badgeScale = Juice.GetScale(badge)
if badgeScale and not badgeScale:GetAttribute("JuiceBaseScale") then
	badgeScale:SetAttribute("JuiceBaseScale", 1)
end

-- =========================================================================
-- UPDATE
-- =========================================================================

local function friendsText(count)
	if count == 1 then
		return "1 Friend Online"
	end
	return count .. " Friends Online"
end

local function render(count)
	local multiplier = FriendBonusConfig.GetMultiplierFor(count)
	local percent = math.floor((multiplier - 1) * 100 + 0.5)
	percentLbl.Text = ("+%d%% Essence"):format(percent)
	friendsLbl.Text = friendsText(count)
end

local lastCount = 0

local function update()
	local count = math.max(0, math.floor(tonumber(player:GetAttribute("FriendsInServer")) or 0))

	if count <= 0 then
		holder.Visible = false
		lastCount = 0
		return
	end

	render(count)

	if not holder.Visible then
		holder.Visible = true
		if badgeScale then
			badgeScale.Scale = 0.6
			TweenService:Create(badgeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
		end
	elseif count ~= lastCount then
		Juice.Punch(badgeScale, 0.2, 0.22)
	end

	lastCount = count
end

player:GetAttributeChangedSignal("FriendsInServer"):Connect(update)
update()

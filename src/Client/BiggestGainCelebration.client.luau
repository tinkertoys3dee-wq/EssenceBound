--[[
	BiggestGainCelebration (LocalScript -> StarterPlayerScripts)
	================================================================
	Celebrates a session personal best: the single biggest essence
	gain observed since this player joined, beaten by a meaningful
	margin -- not just a marginal +2 over the last one. Distinct from
	UIManagement.client.luau's milestone celebrations, which fire when
	the CUMULATIVE total crosses a round threshold (1K, 10K, ...) -- this
	is about a single COLLECTION EVENT (a lucky crit, a golden storm hit,
	a Wheel jackpot, a big quest reward -- any source) being bigger than
	any other one seen this session, regardless of the running total.

	SESSION-ONLY BY DESIGN
	------------------------
	Not persisted across rejoins. A genuine lifetime record would need
	server-side tracking to be trustworthy for anything beyond this
	player's own screen -- this is intentionally scoped to "the best
	moment of THIS sitting," which needs none of that: it's a pure,
	honest readout of deltas this client already legitimately observes
	on its own leaderstat, never claiming anything beyond what just
	happened on THIS device this session. Nothing here grants currency
	or reads as an achievement elsewhere -- purely a feel-good moment.

	WHY THE MARGIN, NOT JUST "BEAT THE OLD BEST"
	-------------------------------------------------
	Without a minimum improvement over the last best, every player would
	get a stream of "New Best!" toasts for trivially small increments,
	which stops feeling special almost immediately. Requiring a real
	jump keeps every celebration meaning something.

	WHY SETUP WAITS ~7 SECONDS
	------------------------------
	IdleService.server.luau grants offline earnings ~5 seconds after
	join (its own internal task.wait(5)) through the exact same
	leaderstat this script watches. Without this delay, a big offline
	lump sum would fire a "New Best" banner competing with
	RecieveOfflineEarning.client.luau's own dedicated Welcome Back
	popup for the same number, right at the moment a returning player
	is trying to read that popup. Waiting past that window means the
	offline grant is already baked into the starting baseline instead
	of being treated as a trackable "gain."
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Juice = require(ReplicatedStorage:WaitForChild("Juice"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))
local PresentationCoordinator = require(ReplicatedStorage:WaitForChild("PresentationCoordinator"))
local formatNumber = ProgressionConfig.FormatNumber

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local leaderstats = player:WaitForChild("leaderstats")

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

local function tween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

-- =========================================================================
-- BANNER
-- =========================================================================

local BEST_COLOR = Color3.fromRGB(255, 205, 80)

local screenGui = new("ScreenGui", {
	Name = "BiggestGainCelebration",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 65,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local banner = new("Frame", {
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.1),
	Size = UDim2.fromScale(0.48, 0.06),
	BackgroundColor3 = Color3.fromRGB(24, 12, 40),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 300,
}, screenGui)
new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, banner)
local bannerStroke = new("UIStroke", { Color = BEST_COLOR, Thickness = 2.5, Transparency = 1 }, banner)
local bannerScale = new("UIScale", { Scale = 0.7 }, banner)

local bannerLabel = new("TextLabel", {
	Name = "Label",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = BEST_COLOR,
	TextScaled = true,
	ZIndex = 301,
}, banner)
new("UITextSizeConstraint", { MaxTextSize = 22 }, bannerLabel)

-- Token-guarded the same way Juice.CountUp guards concurrent animations:
-- a rapid sequence of new bests (e.g. several big Gravity Well fusions in
-- a row) should just keep resetting to the newest one, with only the
-- LAST one's fade-out timer actually allowed to complete.
local activeBannerToken = 0

local function showBanner(amount, essenceName)
	-- A personal-best banner is optional feedback. Dropping one while the
	-- player is reading onboarding is better than replaying stale celebration
	-- noise after the tutorial or an event ends.
	if PresentationCoordinator.HasPendingPresentation() then
		return
	end
	activeBannerToken += 1
	local myToken = activeBannerToken

	local essence = EssenceConfig.Get(essenceName)
	local glyph = essence and essence.Glyph or "✦"
	bannerLabel.Text = ("🏆 NEW BEST: +%s %s %s"):format(formatNumber(amount), glyph, essenceName)
	if essence then
		bannerLabel.TextColor3 = essence.Color:Lerp(Color3.fromRGB(255, 255, 255), 0.32)
		bannerStroke.Color = essence.Color
	end
	banner.Visible = true
	banner.BackgroundTransparency = 1
	bannerStroke.Transparency = 1
	bannerScale.Scale = 0.7

	-- Back-Out easing already overshoots past 1 before settling, which
	-- gives this its "pop" on its own -- an additional Juice.Punch call
	-- on the same UIScale right after this would read Scale synchronously
	-- (still 0.7 here; tweens animate over subsequent frames, not
	-- instantly) as its "resting" base and fight this tween outright,
	-- leaving the banner stuck smaller than intended.
	tween(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { BackgroundTransparency = 0.15 }):Play()
	tween(bannerStroke, TweenInfo.new(0.25), { Transparency = 0.2 }):Play()
	tween(bannerScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(2.2, function()
		if activeBannerToken ~= myToken then
			return -- superseded by a newer best before this one's timer ran out
		end

		tween(bannerStroke, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		local fadeOut = tween(banner, TweenInfo.new(0.35), { BackgroundTransparency = 1 })
		fadeOut:Play()
		fadeOut.Completed:Connect(function()
			if activeBannerToken == myToken then
				banner.Visible = false
			end
		end)
	end)
end

PresentationCoordinator.Changed:Connect(function()
	local focusReserved = PresentationCoordinator.HasPendingPresentation()
	screenGui.Enabled = not focusReserved
	if focusReserved then
		-- Invalidate its delayed fade callback too, so an interrupted personal
		-- best never reappears as a stale banner between later presentations.
		activeBannerToken += 1
		banner.Visible = false
	end
end)
screenGui.Enabled = not PresentationCoordinator.HasPendingPresentation()

-- =========================================================================
-- TRACKING
-- =========================================================================

local MIN_IMPROVEMENT_RATIO = 1.2 -- a new best must beat the old one by at least 20% to celebrate

-- Currency scales are intentionally incomparable (a late Earth payout may
-- be millions while one Solar find is mythic), so each essence keeps its
-- own personal best. Otherwise a large Earth gain could permanently silence
-- every Solar celebration for the rest of the session.
local sessionBests = {}
local hasBaselines = {}
local lastQuantities = {}

local function onQuantityChanged(stat, essenceName)
	local current = tonumber(stat:GetAttribute("Quantity")) or 0
	local delta = current - (lastQuantities[essenceName] or current)
	lastQuantities[essenceName] = current

	-- Ignores decreases (spending on an upgrade, the Sanctum, etc.) --
	-- only genuine gains count toward a "biggest gain" record.
	if delta <= 0 then
		return
	end

	local previousBest = sessionBests[essenceName] or 0
	if delta > previousBest then
		sessionBests[essenceName] = delta

		if hasBaselines[essenceName] and previousBest > 0 and delta >= previousBest * MIN_IMPROVEMENT_RATIO then
			showBanner(delta, essenceName)
		end
		hasBaselines[essenceName] = true
	end
end

task.spawn(function()
	task.wait(7)
	if not player.Parent then
		return
	end

	for _, essence in ipairs(EssenceConfig.Ordered) do
		local essenceName = essence.Name
		local stat = leaderstats:WaitForChild(essenceName)
		lastQuantities[essenceName] = tonumber(stat:GetAttribute("Quantity")) or 0
		stat:GetAttributeChangedSignal("Quantity"):Connect(function()
			onQuantityChanged(stat, essenceName)
		end)
	end
end)

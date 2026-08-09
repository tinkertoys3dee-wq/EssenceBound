--[[
	WheelPanel (LocalScript -> StarterPlayerScripts)
	===================================================
	Client for the Fortune Wheel (see WheelConfig.luau, WheelService.
	server.luau): a button + panel with an actual spinning wheel, built
	entirely from Frames/UICorner/emoji -- no image assets needed.

	HOW THE WHEEL SPINS WITHOUT A PIE-CHART PRIMITIVE
	------------------------------------------------------
	Roblox UI has no native pie-slice shape. Instead of faking one, this
	arranges all 8 reward badges around a circular "ring" Frame at fixed
	angles (basic trig), then spins the whole RING by tweening its
	Rotation property -- rotating a GuiObject rotates every child
	positioned inside it as one rigid unit, so the badges visually swing
	around exactly like a real wheel, while a separate pointer TextLabel
	stays fixed outside the ring. The server rolls which segment wins
	BEFORE any animation starts (see WheelService) -- this only ever
	computes how far to spin to land on the segment it's already been
	told won; it never decides the outcome.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local WheelConfig = require(ReplicatedStorage:WaitForChild("WheelConfig"))
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild("WheelRemotes", 15)
if not remotesFolder then
	warn("WheelPanel: WheelRemotes never appeared -- Fortune Wheel UI disabled this session.")
	return
end

local SyncRemote = remotesFolder:WaitForChild("WheelSync", 15)
local SpinFunction = remotesFolder:WaitForChild("SpinWheel", 15)
if not SyncRemote or not SpinFunction then
	warn("WheelPanel: WheelSync/SpinWheel never appeared -- Fortune Wheel UI disabled this session.")
	return
end

-- =========================================================================
-- THEME + LAYOUT
-- =========================================================================

local THEME = {
	Background      = Color3.fromRGB(24, 12, 40),
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(146, 136, 160),
	Locked          = Color3.fromRGB(58, 50, 76),
}

-- Bottom-right corner: distinct from the packed right-edge column
-- (RebirthShop/Sanctum/Leaderboard/Achievements/Daily-Quest-Codes/
-- GroupReward and the other shortcuts use x=0.952-0.996, y=0.213-0.8;
-- see GroupRewardPrompt. This bottom-corner button remains below them.
-- client.luau's LAYOUT comment), distinct from FriendBonusIndicator's
-- top-right badge (y=0.03), and distinct from bottom-CENTER where the
-- potion timer HUD and Juice's shared relic bar live.
local LAYOUT = {
	ButtonAnchor = Vector2.new(1, 1),
	ButtonPosition = UDim2.fromScale(0.985, 0.97),
	ButtonSize = UDim2.fromScale(0.068, 0.068),
	PanelSize = UDim2.fromScale(0.42, 0.64),
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
	return new("UICorner", { CornerRadius = radius or UDim.new(0.5, 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color or THEME.Accent, Thickness = thickness or 2, Transparency = transparency or 0 }, parent)
end

local function tween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

-- =========================================================================
-- SCREEN GUI
-- =========================================================================

local screenGui = new("ScreenGui", {
	Name = "WheelPanel",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 60,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- =========================================================================
-- FLOATING BUTTON
-- =========================================================================

local buttonHolder = new("Frame", {
	Name = "ButtonHolder",
	AnchorPoint = LAYOUT.ButtonAnchor,
	Position = LAYOUT.ButtonPosition,
	Size = LAYOUT.ButtonSize,
	BackgroundTransparency = 1,
	ZIndex = 50,
}, screenGui)
new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, buttonHolder)

local wheelButton = new("TextButton", {
	Name = "Button",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BackgroundLight,
	AutoButtonColor = false,
	Text = "",
	ZIndex = 51,
}, buttonHolder)
corner(wheelButton, UDim.new(0.3, 0))
stroke(wheelButton, THEME.Accent, 2.5)

new("TextLabel", {
	Name = "Icon",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "🎡",
	TextScaled = true,
	ZIndex = 52,
}, wheelButton)

-- Small badge that lights up when a spin is actually available (free or
-- ticketed), so the button itself hints "there's something here" instead
-- of the player having to open the panel to find out.
local readyDot = new("Frame", {
	Name = "ReadyDot",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.97, 0.03),
	Size = UDim2.fromScale(0.24, 0.24),
	BackgroundColor3 = THEME.Green,
	Visible = false,
	ZIndex = 53,
}, wheelButton)
corner(readyDot, UDim.new(0.5, 0))
stroke(readyDot, THEME.White, 1.5)

Juice.ButtonFeel(wheelButton, {})

-- =========================================================================
-- PANEL SCAFFOLDING
-- =========================================================================

local backdrop = new("TextButton", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Text = "",
	Visible = false,
	ZIndex = 200,
}, screenGui)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = LAYOUT.PanelSize,
	BackgroundColor3 = THEME.Background,
	Visible = false,
	ZIndex = 201,
}, screenGui)
corner(panel, UDim.new(0.04, 0))
stroke(panel, THEME.Accent, 2.5)
local panelScale = new("UIScale", { Scale = 0.85 }, panel)

new("TextLabel", {
	Name = "Title",
	-- Leave room for the close button and the rounded frame edges. The
	-- full-width label previously let "Fortune Wheel" render underneath
	-- the close button on narrow viewports, visibly clipping the title.
	Position = UDim2.fromScale(0.1, 0.03),
	Size = UDim2.fromScale(0.8, 0.09),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "🎡 Fortune Wheel",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 202,
}, panel)
new("UITextSizeConstraint", { MaxTextSize = 28 }, panel.Title)

new("TextLabel", {
	Name = "Subtitle",
	-- Inset long copy from the frame stroke instead of scaling it all the
	-- way to the panel's outer bounds.
	Position = UDim2.fromScale(0.07, 0.115),
	Size = UDim2.fromScale(0.86, 0.05),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "One free spin daily -- more from collecting essence",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 202,
}, panel)
new("UITextSizeConstraint", { MaxTextSize = 15 }, panel.Subtitle)

local closeButton = new("TextButton", {
	Name = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.97, 0.03),
	Size = UDim2.fromScale(0.07, 0.07),
	BackgroundColor3 = THEME.Locked,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "X",
	TextColor3 = THEME.White,
	TextScaled = true,
	ZIndex = 203,
}, panel)
corner(closeButton, UDim.new(0.3, 0))
Juice.ButtonFeel(closeButton, {})

-- =========================================================================
-- WHEEL VISUAL
-- =========================================================================

local wheelHolder = new("Frame", {
	Name = "WheelHolder",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.19),
	Size = UDim2.fromScale(0.62, 0.62),
	BackgroundTransparency = 1,
	ZIndex = 202,
}, panel)
new("UIAspectRatioConstraint", { AspectRatio = 1 }, wheelHolder)

local wheelBase = new("Frame", {
	Name = "WheelBase",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.BackgroundLight,
	ZIndex = 203,
}, wheelHolder)
corner(wheelBase, UDim.new(0.5, 0))
stroke(wheelBase, THEME.Accent, 3)

-- The part that actually spins. Every badge below is positioned relative
-- to THIS frame's center, so rotating it carries every badge around with
-- it as one rigid assembly -- see the file header for why this is how a
-- wheel gets built without a pie-slice primitive.
local wheelRing = new("Frame", {
	Name = "WheelRing",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 204,
}, wheelBase)

local SEGMENT_COUNT = WheelConfig.SegmentCount
local BADGE_ORBIT_SCALE = 0.35 -- distance from ring-center, as a fraction of the ring's own size
local BADGE_SIZE_SCALE = 0.24

local badges = {}

for index, segment in ipairs(WheelConfig.Segments) do
	-- 0 degrees = top (12 o'clock), increasing CLOCKWISE -- matches
	-- exactly how Roblox's own Rotation property increases, which is
	-- what the spin-angle math below depends on.
	local angleDeg = (index - 1) * (360 / SEGMENT_COUNT)
	local angleRad = math.rad(angleDeg)
	local offsetX = math.sin(angleRad) * BADGE_ORBIT_SCALE
	local offsetY = -math.cos(angleRad) * BADGE_ORBIT_SCALE

	local badge = new("Frame", {
		Name = "Segment" .. index,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5 + offsetX, 0, 0.5 + offsetY, 0),
		Size = UDim2.fromScale(BADGE_SIZE_SCALE, BADGE_SIZE_SCALE),
		BackgroundColor3 = segment.Color,
		ZIndex = 205,
	}, wheelRing)
	corner(badge, UDim.new(0.5, 0))
	stroke(badge, THEME.White, 1.5, 0.4)

	new("TextLabel", {
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = segment.Icon,
		TextScaled = true,
		ZIndex = 206,
	}, badge)

	badges[index] = badge
end

-- Hub covering the ring's own center, purely decorative (keeps the
-- badges reading as spokes around a hub rather than floating dots).
local hub = new("Frame", {
	Name = "Hub",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.22, 0.22),
	BackgroundColor3 = THEME.Background,
	ZIndex = 207,
}, wheelBase)
corner(hub, UDim.new(0.5, 0))
stroke(hub, THEME.Accent, 2)

-- Fixed pointer -- parented to wheelHolder, NOT wheelRing, so it never
-- rotates. Whichever badge ends up directly under this is what won.
new("TextLabel", {
	Name = "Pointer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, -0.07),
	Size = UDim2.fromScale(0.16, 0.16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "▼",
	TextColor3 = THEME.Accent,
	TextScaled = true,
	ZIndex = 208,
}, wheelHolder)

-- =========================================================================
-- SPIN BUTTON + STATUS
-- =========================================================================

local statusLabel = new("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	-- Keep the status in its own row. The spin button begins at y=0.87
	-- (bottom anchored at 0.97 with height 0.10), so the old row ending at
	-- y=0.90 rendered its last three percent underneath the button.
	Position = UDim2.fromScale(0.5, 0.80),
	Size = UDim2.fromScale(0.9, 0.055),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = THEME.Grey,
	TextScaled = true,
	ZIndex = 202,
}, panel)
new("UITextSizeConstraint", { MaxTextSize = 15 }, statusLabel)

local spinButton = new("TextButton", {
	Name = "SpinButton",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromScale(0.5, 0.97),
	Size = UDim2.fromScale(0.5, 0.1),
	BackgroundColor3 = THEME.Green,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBlack,
	Text = "SPIN",
	TextColor3 = THEME.Background,
	TextScaled = true,
	ZIndex = 202,
}, panel)
corner(spinButton, UDim.new(0.3, 0))
stroke(spinButton, THEME.White, 2)
new("UITextSizeConstraint", { MaxTextSize = 24 }, spinButton)
Juice.ButtonFeel(spinButton, {})

-- =========================================================================
-- OPEN / CLOSE
-- =========================================================================

local open = false

local function closePanel()
	if not open then
		return
	end
	open = false

	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
	local outTween = tween(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.85 })
	outTween:Play()
	outTween.Completed:Connect(function()
		if not open then
			panel.Visible = false
			backdrop.Visible = false
		end
	end)
end

local function openPanel()
	if open then
		return
	end
	open = true

	backdrop.Visible = true
	backdrop.BackgroundTransparency = 1
	tween(backdrop, TweenInfo.new(0.2), { BackgroundTransparency = 0.5 }):Play()

	panel.Visible = true
	panelScale.Scale = 0.85
	tween(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

wheelButton.MouseButton1Click:Connect(openPanel)
closeButton.MouseButton1Click:Connect(closePanel)
backdrop.MouseButton1Click:Connect(closePanel)

-- =========================================================================
-- STATE + SPIN RESOLUTION
-- =========================================================================

local wheelState = {
	Tickets = 0,
	CollectionsSinceLastTicket = 0,
	FreeSpinReady = false,
	FreeSpinSecondsRemaining = 0,
}

-- False until the first real WheelSync arrives -- without this gate,
-- refreshStatus would render wheelState's zero-defaults as real data for
-- that brief window (misleadingly showing "Next free spin in 0s" rather
-- than "not loaded yet"). The button itself already defaults safely
-- either way (hasSpin is false on zero-defaults too), this only fixes
-- what the STATUS TEXT claims during that window.
local dataLoaded = false
local spinning = false

local function refreshStatus()
	if not dataLoaded then
		readyDot.Visible = false
		spinButton.Active = false
		spinButton.BackgroundColor3 = THEME.Locked
		spinButton.Text = "LOADING..."
		statusLabel.Text = "Loading your spins..."
		return
	end

	local hasSpin = wheelState.FreeSpinReady or wheelState.Tickets > 0
	readyDot.Visible = hasSpin and not spinning

	spinButton.Active = hasSpin and not spinning
	spinButton.BackgroundColor3 = (hasSpin and not spinning) and THEME.Green or THEME.Locked

	if spinning then
		spinButton.Text = "SPINNING..."
	elseif wheelState.FreeSpinReady then
		spinButton.Text = "FREE SPIN"
	elseif wheelState.Tickets > 0 then
		spinButton.Text = "SPIN (" .. wheelState.Tickets .. " left)"
	else
		spinButton.Text = "NO SPINS YET"
	end

	if spinning then
		return
	end

	if wheelState.FreeSpinReady then
		local toNextTicket = math.max(0, WheelConfig.CollectionsPerTicket - wheelState.CollectionsSinceLastTicket)
		statusLabel.Text = ("🎟️ %d ticket(s) banked  •  %d orbs to next ticket")
			:format(wheelState.Tickets, toNextTicket)
	else
		statusLabel.Text = ("Next free spin in %s  •  🎟️ %d ticket(s) banked")
			:format(ProgressionConfig.FormatDuration(wheelState.FreeSpinSecondsRemaining), wheelState.Tickets)
	end
end

-- Spins the ring to land on segmentIndex, always spinning FORWARD
-- (never snapping backward) and always adding a few extra full turns for
-- the visual. See the file header for why child badges swing around
-- with the ring's own Rotation.
local SPIN_DURATION = 4
local EXTRA_SPINS = 6

local function spinRingTo(segmentIndex, onDone)
	local targetAngle = (segmentIndex - 1) * (360 / SEGMENT_COUNT)
	local targetMod = (360 - targetAngle) % 360

	local currentMod = wheelRing.Rotation % 360
	local forwardDelta = (targetMod - currentMod + 360) % 360
	local finalRotation = wheelRing.Rotation + (EXTRA_SPINS * 360) + forwardDelta

	local spin = tween(wheelRing, TweenInfo.new(SPIN_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Rotation = finalRotation,
	})
	spin:Play()
	spin.Completed:Connect(function()
		if onDone then
			onDone()
		end
	end)
end

local function celebrateResult(segmentIndex, result)
	local badge = badges[segmentIndex]
	local segment = WheelConfig.Segments[segmentIndex]
	if not badge or not segment then
		return
	end

	Juice.Punch(Juice.GetScale(badge), 0.5, 0.4)

	-- Explicit ZIndex on every effect below: they're spawned straight into
	-- `panel` (appropriate, since they're tied to this modal, not general
	-- on-screen ambience -- unlike CursorCollection's use of Juice's
	-- shared full-screen JuiceFX layer), which makes them SIBLINGS of the
	-- panel's own content under Sibling ZIndexBehavior. Juice's own
	-- defaults (50-90) sit well below everything already built in this
	-- panel (202-208) and would render invisibly behind the wheel/panel
	-- background without this.
	local EFFECT_Z = 220

	local center = Juice.CenterOf(hub, panel)
	if center then
		Juice.Burst(panel, center, {
			Count = segment.Id == "jackpot" and 22 or 10,
			Colors = { segment.Color, THEME.White },
			Distance = segment.Id == "jackpot" and 140 or 80,
			Duration = 0.6,
			ZIndex = EFFECT_Z,
		})

		local lines = { ("+%s Essence"):format(ProgressionConfig.FormatNumber(result.Essence or 0)) }
		if result.Shards then
			table.insert(lines, ("+%d Prestige Shard(s)"):format(result.Shards))
		end
		if result.PotionLabel then
			table.insert(lines, result.PotionLabel)
		end

		Juice.FloatText(panel, center, segment.Label .. "!", {
			Color = segment.Color,
			Duration = 1.1,
			Rise = 70,
			TextSize = segment.Id == "jackpot" and 34 or 26,
			ZIndex = EFFECT_Z + 1,
		})

		task.delay(0.25, function()
			Juice.FloatText(panel, center, table.concat(lines, "  •  "), {
				Color = THEME.White,
				Duration = 1.3,
				Rise = 60,
				TextSize = 20,
				ZIndex = EFFECT_Z + 1,
			})
		end)
	end

	if segment.Id == "jackpot" then
		Juice.Flash(panel, { Color = segment.Color, Peak = 0.35, Duration = 0.5, ZIndex = EFFECT_Z + 2 })
	end
end

local function requestSpin()
	if not dataLoaded or spinning then
		return
	end
	if not (wheelState.FreeSpinReady or wheelState.Tickets > 0) then
		return
	end

	spinning = true
	refreshStatus()

	local ok, success, message, result = pcall(function()
		return SpinFunction:InvokeServer()
	end)

	if not ok or not success then
		spinning = false
		refreshStatus()
		if ok and message then
			statusLabel.Text = message
		end
		return
	end

	spinRingTo(result.SegmentIndex, function()
		spinning = false
		celebrateResult(result.SegmentIndex, result)
		refreshStatus()
	end)
end

spinButton.MouseButton1Click:Connect(requestSpin)

-- =========================================================================
-- SYNC
-- =========================================================================

SyncRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	wheelState.Tickets = tonumber(payload.Tickets) or 0
	wheelState.CollectionsSinceLastTicket = tonumber(payload.CollectionsSinceLastTicket) or 0
	wheelState.FreeSpinReady = payload.FreeSpinReady == true
	wheelState.FreeSpinSecondsRemaining = tonumber(payload.FreeSpinSecondsRemaining) or 0
	dataLoaded = true

	refreshStatus()
end)

-- Local per-second ticker so the "next free spin in..." countdown
-- doesn't need a constant stream of server pushes -- same pattern
-- ProgressionHud uses for its own daily-reset countdown.
task.spawn(function()
	while true do
		task.wait(1)
		if not wheelState.FreeSpinReady and wheelState.FreeSpinSecondsRemaining > 0 then
			wheelState.FreeSpinSecondsRemaining -= 1
			if wheelState.FreeSpinSecondsRemaining <= 0 then
				wheelState.FreeSpinReady = true
			end
			if not spinning then
				refreshStatus()
			end
		end
	end
end)

refreshStatus()

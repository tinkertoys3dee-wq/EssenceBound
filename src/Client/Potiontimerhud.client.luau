--[[
    POTION TIMER HUD
    ================
    A stack of live countdown "buff" cards for active potions, driven by
    PotionTimerService on the server. Cards slide/pop in when a potion
    starts, tick down every second, flash red in the final 10 seconds,
    and shrink away when the potion expires.

    Uses the same visual language as the popup menus (dark purple cards,
    gold/green accents, rounded corners, FredokaOne/Gotham fonts) but is
    fully self-contained — it doesn't depend on the popup script being
    loaded first.

    Every Size/Position in this script is Scale-based — nothing is
    anchored to a fixed pixel offset, so it holds up across different
    screen resolutions and aspect ratios.

    PLACEMENT
    ---------
    StarterPlayer > StarterPlayerScripts (LocalScript). Requires
    PotionTimerService + its remotes to already exist on the server side
    (see PotionTimerService.lua / PotionTimerBootstrap.lua).

    REPOSITIONING
    -------------
    Everything under LAYOUT CONFIG below is a scale value — adjust those
    to move/resize the whole stack.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-------------------------------------------------------------------
-- THEME (matches the popup menus)
-------------------------------------------------------------------
local THEME = {
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),
	Green           = Color3.fromRGB(58, 209, 118),
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(146, 136, 160),
	Locked          = Color3.fromRGB(58, 50, 76),
	Red             = Color3.fromRGB(230, 80, 90),
}

-- What each effect looks like in the HUD. Anything not listed here still
-- shows up using DEFAULT_DISPLAY, so new potions "just work" visually.
local EFFECT_DISPLAY = {
	EssenceX15  = {name = "1.5x Essence Boost", icon = "\240\159\159\162", color = THEME.Green},
	LuckBoost  = {name = "Luck Potion",      icon = "\240\159\141\128", color = THEME.Accent},
	SpeedBoost = {name = "Speed Potion",     icon = "\240\159\146\168", color = Color3.fromRGB(90, 160, 230)},
}
local DEFAULT_DISPLAY = {name = nil, icon = "\226\156\168", color = THEME.Accent}

-------------------------------------------------------------------
-- LAYOUT CONFIG (all Scale — no pixels anywhere in this script)
-------------------------------------------------------------------
-- The container is a fixed-scale "canvas" the cards stack inside. It's
-- fully transparent, so its size just defines how much room the stack
-- has to grow into — it doesn't need to (and shouldn't) use
-- AutomaticSize, since that would conflict with cards being sized as a
-- Scale of it (a Scale-sized child can't drive the auto-size of the
-- same parent it's scaled against — that's circular).
local CONTAINER_ANCHOR = Vector2.new(0, 1)              -- anchored at its own bottom-left corner
local CONTAINER_POSITION = UDim2.new(0.265, 0, 0.975, 0)   -- that corner sits at 5% from the left, 80% down the screen
local CONTAINER_SIZE = UDim2.new(0.47, 0, 0.06, 0)      -- room to grow upward from the anchor, on-screen the whole time

local CARD_HEIGHT_SCALE = 1   -- each card's height, as a fraction of the container's height
local CARD_PADDING_SCALE = 0.02  -- gap between cards, as a fraction of the container's height

-------------------------------------------------------------------
-- SMALL HELPERS
-------------------------------------------------------------------
-- radius is a Scale fraction (0–0.5). UICorner's Scale component is
-- relative to the SHORTER side of the object, so 0.5 always yields a
-- perfect circle/pill regardless of the object's actual pixel size.
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, transparency)
	-- NOTE: UIStroke.Thickness has no Scale equivalent in Roblox — it's
	-- always a small pixel value. This is the one unavoidable exception;
	-- values this small (1.5–3.5px) look fine at any resolution.
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

local function tween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

local function formatTime(totalSeconds)
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = totalSeconds % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%02d:%02d", minutes, seconds)
end

-------------------------------------------------------------------
-- SCREEN GUI / CONTAINER
-------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PotionTimerHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 40
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "PotionTimerContainer"
container.AnchorPoint = CONTAINER_ANCHOR
container.Position = CONTAINER_POSITION
container.Size = CONTAINER_SIZE
container.BackgroundTransparency = 1
container.Parent = screenGui

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(CARD_PADDING_SCALE, 0)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom -- newest space grows upward, anchor stays put on screen
listLayout.Parent = container
listLayout.FillDirection = Enum.FillDirection.Horizontal

-------------------------------------------------------------------
-- CARD BUILDER
-------------------------------------------------------------------
local activeCards = {} -- [effectName] = entry table

local function createPotionCard(effectName, info)
	local card = Instance.new("CanvasGroup")
	card.Name = effectName
	card.Size = UDim2.new(.3, 0, CARD_HEIGHT_SCALE, 0)
	card.BackgroundColor3 = THEME.BackgroundLight
	card.BorderSizePixel = 0
	card.Parent = container
	corner(card, 0.25)
	local cardStroke = stroke(card, info.color, 1.5, 0.2)

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(40, 20, 64), Color3.fromRGB(20, 10, 34))
	grad.Rotation = 90
	grad.Parent = card

	-- icon badge: sized by height only, width follows automatically via
	-- the aspect ratio constraint so it's always a perfect circle
	local iconBg = Instance.new("Frame")
	iconBg.AnchorPoint = Vector2.new(0, 0.5)
	iconBg.Position = UDim2.new(0.04, 0, 0.5, 0)
	iconBg.Size = UDim2.new(0, 0, 0.6, 0)
	iconBg.BackgroundColor3 = info.color
	iconBg.Parent = card
	corner(iconBg, 0.5)

	local iconAspect = Instance.new("UIAspectRatioConstraint")
	iconAspect.AspectRatio = 1
	iconAspect.DominantAxis = Enum.DominantAxis.Height
	iconAspect.Parent = iconBg

	local iconLbl = Instance.new("TextLabel")
	iconLbl.Size = UDim2.new(1, 0, 1, 0)
	iconLbl.BackgroundTransparency = 1
	iconLbl.Font = Enum.Font.GothamBold
	iconLbl.TextSize = 20
	iconLbl.TextScaled = true
	iconLbl.Text = info.icon
	iconLbl.Parent = iconBg

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Position = UDim2.new(0.22, 0, 0.08, 0)
	nameLbl.Size = UDim2.new(0.56, 0, 0.4, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 13
	nameLbl.TextScaled = true
	nameLbl.TextColor3 = THEME.White
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
	nameLbl.Text = info.name or effectName
	nameLbl.Parent = card

	local timeLbl = Instance.new("TextLabel")
	timeLbl.AnchorPoint = Vector2.new(1, 0)
	timeLbl.Position = UDim2.new(0.97, 0, 0.08, 0)
	timeLbl.Size = UDim2.new(0.2, 0, 0.4, 0)
	timeLbl.BackgroundTransparency = 1
	timeLbl.Font = Enum.Font.FredokaOne
	timeLbl.TextSize = 14
	timeLbl.TextScaled = true
	timeLbl.TextColor3 = info.color
	timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.Text = "--:--"
	timeLbl.Parent = card

	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.new(0.22, 0, 0.68, 0)
	barBg.Size = UDim2.new(0.74, 0, 0.22, 0)
	barBg.BackgroundColor3 = THEME.Locked
	barBg.Parent = card
	corner(barBg, 0.5)

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = info.color
	barFill.Parent = barBg
	corner(barFill, 0.5)

	local barGrad = Instance.new("UIGradient")
	barGrad.Color = ColorSequence.new(info.color, Color3.new(1, 1, 1):Lerp(info.color, 0.5))
	barGrad.Parent = barFill

	return {
		card = card,
		stroke = cardStroke,
		timeLbl = timeLbl,
		barFill = barFill,
		baseColor = info.color,
		totalDuration = nil,      -- highest remaining-seconds value seen so far (used as the bar's "100%")
		expirationEstimate = nil, -- os.time() this effect is expected to run out
		warning = false,
	}
end

-------------------------------------------------------------------
-- RENDER / UPDATE
-------------------------------------------------------------------
local function renderCard(entry, remaining)
	entry.timeLbl.Text = formatTime(remaining)

	local fraction = 0
	if entry.totalDuration and entry.totalDuration > 0 then
		fraction = math.clamp(remaining / entry.totalDuration, 0, 1)
	end
	entry.barFill.Size = UDim2.new(fraction, 0, 1, 0)

	local urgent = remaining <= 10
	if urgent and not entry.warning then
		entry.warning = true
		task.spawn(function()
			while entry.warning and entry.card.Parent do
				tween(entry.timeLbl, TweenInfo.new(0.4), {TextColor3 = THEME.Red}):Play()
				task.wait(0.4)
				if not (entry.warning and entry.card.Parent) then
					break
				end
				tween(entry.timeLbl, TweenInfo.new(0.4), {TextColor3 = entry.baseColor}):Play()
				task.wait(0.4)
			end
		end)
	elseif not urgent then
		entry.warning = false
	end
end

local function pulseStroke(entry)
	tween(entry.stroke, TweenInfo.new(0.15), {Thickness = 3.5}):Play()
	task.delay(0.15, function()
		if entry.stroke.Parent then
			tween(entry.stroke, TweenInfo.new(0.25), {Thickness = 1.5}):Play()
		end
	end)
end

local function addCard(effectName, remaining)
	local info = EFFECT_DISPLAY[effectName] or DEFAULT_DISPLAY
	local entry = createPotionCard(effectName, info)
	entry.totalDuration = remaining
	entry.expirationEstimate = os.time() + remaining
	activeCards[effectName] = entry

	local card = entry.card
	local targetSize = card.Size
	card.Size = UDim2.new(targetSize.X.Scale, 0, 0, 0) -- start collapsed to zero height
	card.GroupTransparency = 1

	tween(card, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize,
		GroupTransparency = 0,
	}):Play()

	renderCard(entry, remaining)
end

local function updateExistingCard(effectName, remaining)
	local entry = activeCards[effectName]
	if not entry then
		return
	end

	if remaining > (entry.totalDuration or 0) then
		entry.totalDuration = remaining
	end
	entry.expirationEstimate = os.time() + remaining

	renderCard(entry, remaining)
	pulseStroke(entry)
end

local function removeCard(effectName)
	local entry = activeCards[effectName]
	if not entry then
		return
	end
	entry.warning = false
	activeCards[effectName] = nil

	local card = entry.card
	local originalSize = card.Size

	tween(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	}):Play()

	task.delay(0.25, function()
		tween(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Size = UDim2.new(originalSize.X.Scale, 0, 0, 0), -- collapse to zero height
		}):Play()
		task.delay(0.2, function()
			card:Destroy()
		end)
	end)
end

-------------------------------------------------------------------
-- EVENTS
-------------------------------------------------------------------
local remotesFolder = ReplicatedStorage:WaitForChild("PotionRemotes")
local potionUpdated = remotesFolder:WaitForChild("PotionUpdated")
local getActivePotions = remotesFolder:WaitForChild("GetActivePotions")

potionUpdated.OnClientEvent:Connect(function(effectName, remaining, active)
	if active and remaining and remaining > 0 then
		if activeCards[effectName] then
			updateExistingCard(effectName, remaining)
		else
			addCard(effectName, remaining)
		end
	else
		removeCard(effectName)
	end
end)

-- local per-second ticker so cards count down smoothly between server pushes
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.time()
		for effectName, entry in pairs(activeCards) do
			local remaining = entry.expirationEstimate and (entry.expirationEstimate - now) or 0
			if remaining <= 0 then
				removeCard(effectName)
			else
				renderCard(entry, remaining)
			end
		end
	end
end)

-- initial sync so the HUD is correct immediately on join/respawn,
-- without waiting for the next PotionUpdated push
task.spawn(function()
	local ok, snapshot = pcall(function()
		return getActivePotions:InvokeServer()
	end)

	if ok and snapshot then
		for effectName, remaining in pairs(snapshot) do
			if not activeCards[effectName] then
				addCard(effectName, remaining)
			end
		end
	end
end)
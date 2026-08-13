--[[
	GlobalVisualPolish (LocalScript -> StarterPlayerScripts)
	====================================================================
	Brings the authored MainGui / EssencePopupUI and every code-generated
	panel into the same premium visual language as the Prophecy Crystal and
	Fortune Wheel.

	This script is deliberately presentation-only. It never replaces a
	button connection, changes a price, moves a frame, or mutates gameplay
	data. Studio-authored instances keep their exact layout; this layer adds
	trim, depth, glints, card hierarchy and state-aware upgrade-node visuals
	at runtime. DescendantAdded support means rows cloned later receive the
	same finish automatically.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AstralVisuals = require(ReplicatedStorage:WaitForChild("AstralVisuals"))
local TreeUpgrades = require(ReplicatedStorage:WaitForChild("TreeUpgrades"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local T = AstralVisuals.Theme

local SCREEN_ACCENTS = {
	AchievementsPanel = Color3.fromRGB(255, 202, 88),
	LeaderboardPanel = Color3.fromRGB(82, 218, 255),
	RebirthShopPanel = Color3.fromRGB(255, 105, 111),
	SanctumPanel = Color3.fromRGB(195, 111, 255),
	ZonePanel = Color3.fromRGB(87, 190, 255),
	ProgressionHud = Color3.fromRGB(110, 226, 155),
	GroupRewardPrompt = Color3.fromRGB(255, 190, 70),
	WhatsNewPopup = Color3.fromRGB(255, 118, 193),
	OfflineEssenceGui = Color3.fromRGB(84, 217, 255),
	TutorialGui = Color3.fromRGB(255, 190, 72),
	PotionTimerHUD = Color3.fromRGB(188, 112, 255),
	FriendBonusIndicator = Color3.fromRGB(83, 222, 157),
	NewPlayerLuckIndicator = Color3.fromRGB(142, 235, 96),
	MonetizationStore = Color3.fromRGB(76, 226, 144),
	UpgradeTooltipGui = Color3.fromRGB(120, 205, 255),
	EssenceRushBanner = Color3.fromRGB(255, 139, 62),
	EssenceDiscoveryGui = Color3.fromRGB(187, 111, 255),
	BiggestGainCelebration = Color3.fromRGB(255, 205, 80),
	HollowedOneUI = Color3.fromRGB(205, 53, 63),
	ZoneTransition = Color3.fromRGB(85, 194, 255),
}

local POPUP_ACCENTS = {
	UpgradesPopup = Color3.fromRGB(120, 205, 255),
	InventoryPopup = Color3.fromRGB(123, 178, 255),
	IndexPopup = Color3.fromRGB(183, 123, 255),
	RebirthPopup = Color3.fromRGB(255, 104, 111),
	SettingsPopup = Color3.fromRGB(105, 205, 222),
	ShopPopup = Color3.fromRGB(78, 225, 145),
}

local PRIMARY_WORDS = {
	"buy", "claim", "action", "submit", "cta", "join", "verify", "travel", "unlock", "spin", "roll",
}

local CARD_WORDS = {
	"card", "row", "entry", "quest", "day", "offer", "benefit", "milestone", "reward", "balance",
	"stat", "currency", "item", "slot", "pill", "badge", "iconbg", "totalrow", "listcontainer", "toast", "banner",
	"countdown",
}

local HEADING_WORDS = {
	"title", "heading", "eyebrow",
}

local MODAL_ROOT_NAMES = {
	eventframe = true,
	sightingslogframe = true,
}

-- These are effect-only canvases or already have a deliberately separate
-- authored language. Decorating their internals would muddy the visual beat
-- instead of improving a player-facing frame.
local EXCLUDED_SCREENS = {
	AmbientBackground = true,
	LoadingScreen = true,
	WheelPanel = true,
	ProphecyPanel = true,
	EssenceStormVisuals = true,
}

local SKIP_WORDS = {
	"astral", "backdrop", "background", "shadow", "glow", "particle", "mote",
	"divider", "connection", "canvas", "viewport", "holder", "layout", "effect", "veil",
}

local decoratedScreens = setmetatable({}, { __mode = "k" })
local decoratedPopups = setmetatable({}, { __mode = "k" })
local decoratedNodes = setmetatable({}, { __mode = "k" })

local function new(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

local function containsAny(text, words)
	for _, word in ipairs(words) do
		if string.find(text, word, 1, true) then
			return true
		end
	end
	return false
end

local function startsWithAstral(instance)
	return string.sub(string.lower(instance.Name), 1, 6) == "astral"
end

local function screenFor(instance)
	local cursor = instance
	while cursor and cursor ~= playerGui do
		if cursor:IsA("ScreenGui") then
			return cursor
		end
		cursor = cursor.Parent
	end
	return nil
end

local function accentFor(instance, fallback)
	local explicitAccent = instance:GetAttribute("AstralAccentColor")
	if typeof(explicitAccent) == "Color3" then
		return explicitAccent
	end
	local screenGui = screenFor(instance)
	local screenAccent = screenGui and SCREEN_ACCENTS[screenGui.Name]
	return AstralVisuals.GetAccent(instance.Name, screenAccent or fallback or T.Gold)
end

local function actionAccent(button, baseAccent)
	local name = string.lower(button.Name)
	if string.find(name, "close", 1, true) or string.find(name, "skip", 1, true) then
		return T.Red
	end
	if containsAny(name, PRIMARY_WORDS) then
		return T.Green:Lerp(baseAccent, 0.18)
	end
	if string.find(name, "tab", 1, true) then
		return T.Cyan
	end
	return baseAccent
end

local function shouldSkip(instance)
	if startsWithAstral(instance) then
		return true
	end
	return containsAny(string.lower(instance.Name), SKIP_WORDS)
end

local function shouldStyleButton(button)
	if shouldSkip(button) then
		return false
	end
	if button.BackgroundTransparency >= 0.98 then
		local text = button:IsA("TextButton") and button.Text or ""
		local image = button:IsA("ImageButton") and button.Image or ""
		if text == "" and image == "" then
			return false
		end
	end
	return true
end

local function shouldStyleCard(object)
	if shouldSkip(object) then
		return false
	end
	local name = string.lower(object.Name)
	-- Celebration banners are commonly constructed fully transparent and
	-- tweened opaque later, so their initial transparency is not a reason to
	-- miss the one-time decoration pass.
	if name == "banner" then
		return true
	end
	if object.BackgroundTransparency >= 0.99 then
		return false
	end
	if name == "titlebar" or name == "header" or name == "footer" then
		return true
	end
	if containsAny(name, CARD_WORDS) then
		return true
	end
	if object.Parent and object.Parent:IsA("ScrollingFrame") then
		return true
	end
	local screenGui = screenFor(object)
	if screenGui and screenGui.Name == "PotionTimerHUD"
		and object.Parent and object.Parent.Name == "PotionTimerContainer" then
		return true
	end
	return false
end

local function isModalRoot(object, screenGui)
	if not object:IsA("GuiObject") or shouldSkip(object) then
		return false
	end
	local name = string.lower(object.Name)
	if MODAL_ROOT_NAMES[name] then
		return true
	end
	if name == "panel" or name == "popuppanel" or name == "rewardcard" or name == "dialogueframe" then
		return true
	end
	if object.Parent == screenGui and string.sub(name, -5) == "panel" then
		return true
	end
	return false
end

local function styleObject(object, baseAccent)
	if not object or not object.Parent or startsWithAstral(object) then
		return
	end
	local accent = accentFor(object, baseAccent)

	if object:IsA("GuiButton") then
		if shouldStyleButton(object) then
			AstralVisuals.StyleButton(object, actionAccent(object, accent), {
				Thickness = 1.45,
				Transparency = 0.34,
			})
		end
		return
	end

	if not object:IsA("GuiObject") then
		return
	end
	local lowerName = string.lower(object.Name)
	if object:IsA("TextLabel") and containsAny(lowerName, HEADING_WORDS) then
		AstralVisuals.StyleHeading(object, accent)
		return
	end
	if string.find(lowerName, "fill", 1, true) and object:IsA("Frame") then
		AstralVisuals.StyleFill(object, accent)
	elseif shouldStyleCard(object) then
		AstralVisuals.StyleCard(object, accent, {
			Thickness = 1.2,
			Transparency = 0.52,
		})
	end
end

local function styleDescendants(root, accent)
	for _, descendant in ipairs(root:GetDescendants()) do
		styleObject(descendant, accent)
	end
end

local function decorateUpgradeViewport(popup, accent)
	local viewport = popup:FindFirstChild("Viewport", true)
	if not viewport or not viewport:IsA("GuiObject") or viewport:GetAttribute("AstralUpgradeViewport") then
		return
	end
	viewport:SetAttribute("AstralUpgradeViewport", true)
	AstralVisuals.StyleCard(viewport, accent, {
		CornerRadius = UDim.new(0.025, 0),
		Thickness = 2,
		Transparency = 0.18,
		Gradient = false,
	})

	local overlay = new("Frame", {
		Name = "AstralUpgradeHUD",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = 930,
	}, viewport)

	local titlePill = AstralVisuals.CreatePill(overlay, "ConstellationTitle", "✦  ESSENCE CONSTELLATION", accent, {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.018, 0.022),
		Size = UDim2.fromScale(0.3, 0.068),
		ZIndex = 932,
		MaxTextSize = 15,
	})
	local titleScale = new("UIScale", { Scale = 1 }, titlePill)
	TweenService:Create(titleScale, TweenInfo.new(1.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Scale = 1.025,
	}):Play()

	local controlsText = UserInputService.TouchEnabled
		and "DRAG TO EXPLORE  •  PINCH TO ZOOM  •  TAP A NODE FOR DETAILS"
		or "DRAG TO EXPLORE  •  SCROLL TO ZOOM  •  HOVER A NODE FOR DETAILS"
	AstralVisuals.CreatePill(overlay, "Controls", controlsText, T.Gold, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.975),
		Size = UDim2.fromScale(0.58, 0.062),
		ZIndex = 932,
		MaxTextSize = 13,
		TextColor3 = T.GoldLight,
	})

	local zoomPill, zoomLabel = AstralVisuals.CreatePill(overlay, "Zoom", "ZOOM 100%", T.Cyan, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.982, 0.022),
		Size = UDim2.fromScale(0.15, 0.062),
		ZIndex = 932,
		MaxTextSize = 13,
		TextColor3 = T.Cyan,
	})
	zoomPill.BackgroundTransparency = 0.14

	for _, side in ipairs({ 0, 1 }) do
		local edge = new("Frame", {
			Name = side == 0 and "AstralLeftEdge" or "AstralRightEdge",
			AnchorPoint = Vector2.new(side, 0.5),
			Position = UDim2.fromScale(side, 0.5),
			Size = UDim2.fromScale(0.018, 0.82),
			BackgroundColor3 = side == 0 and accent or T.Cyan,
			BackgroundTransparency = 0.52,
			BorderSizePixel = 0,
			Active = false,
			ZIndex = 931,
		}, overlay)
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, edge)
	end

	local canvas = viewport:FindFirstChild("Canvas")
	local canvasScale = canvas and canvas:FindFirstChildWhichIsA("UIScale")
	if canvasScale then
		local function refreshZoom()
			zoomLabel.Text = ("ZOOM %d%%"):format(math.floor(canvasScale.Scale * 100 + 0.5))
		end
		canvasScale:GetPropertyChangedSignal("Scale"):Connect(refreshZoom)
		refreshZoom()
	end
end

local function decoratePopup(popup)
	if decoratedPopups[popup] or not popup:IsA("GuiObject") then
		return
	end
	decoratedPopups[popup] = true
	local accent = POPUP_ACCENTS[popup.Name] or AstralVisuals.GetAccent(popup.Name, T.Gold)
	AstralVisuals.ApplyModal(popup, {
		Accent = accent,
		Thickness = 2.7,
		StrokeTransparency = 0.08,
		StarCount = popup.Name == "UpgradesPopup" and 5 or 8,
		Halo = true,
	})

	local titleBar = popup:FindFirstChild("TitleBar")
	if titleBar and titleBar:IsA("GuiObject") then
		AstralVisuals.StyleCard(titleBar, accent, {
			CornerRadius = UDim.new(0.08, 0),
			Thickness = 1.4,
			Transparency = 0.38,
		})
	end

	local closeButton = titleBar and titleBar:FindFirstChild("CloseButton")
	if closeButton and closeButton:IsA("GuiButton") then
		AstralVisuals.StyleButton(closeButton, T.Red, { Thickness = 1.6, Transparency = 0.16 })
	end

	local content = popup:FindFirstChild("Content")
	if content then
		for _, child in ipairs(content:GetChildren()) do
			if child:IsA("GuiObject") and child.BackgroundTransparency < 0.98 then
				AstralVisuals.StyleCard(child, accent, { Thickness = 1.15, Transparency = 0.56 })
			end
		end
	end

	styleDescendants(popup, accent)
	if popup.Name == "UpgradesPopup" then
		decorateUpgradeViewport(popup, accent)
	end

	popup.DescendantAdded:Connect(function(descendant)
		if startsWithAstral(descendant) then
			return
		end
		task.defer(function()
			if descendant.Parent then
				styleObject(descendant, accent)
			end
		end)
	end)
end

local function decorateEssencePopups(screenGui)
	local holder = screenGui:FindFirstChild("PopupHolder") or screenGui:WaitForChild("PopupHolder", 12)
	if not holder then
		return
	end
	for _, popup in ipairs(holder:GetChildren()) do
		decoratePopup(popup)
	end
	holder.ChildAdded:Connect(function(popup)
		task.defer(decoratePopup, popup)
	end)
end

local function findTrigger(container)
	if container:IsA("GuiButton") then
		return container
	end
	return container:FindFirstChildWhichIsA("GuiButton", true)
end

local function decorateMainGui(mainGui)
	local left = mainGui:FindFirstChild("Left")
	if left then
		local currencies = left:FindFirstChild("Currencys")
		local playerCard = currencies and currencies:FindFirstChild("Player")
		if playerCard and playerCard:IsA("GuiObject") then
			AstralVisuals.StyleCard(playerCard, T.Gold, { Thickness = 2, Transparency = 0.18 })
		end
		local currencyList = currencies and currencies:FindFirstChild("ScrollingFrame")
		if currencyList then
			for _, row in ipairs(currencyList:GetChildren()) do
				if row:IsA("GuiObject") then
					AstralVisuals.StyleCard(row, accentFor(row, T.Green), { Thickness = 1.15, Transparency = 0.58 })
				end
			end
		end

		local playerStats = left:FindFirstChild("Playerstats")
		if playerStats then
			for _, row in ipairs(playerStats:GetChildren()) do
				if row:IsA("GuiObject") then
					AstralVisuals.StyleCard(row, accentFor(row, T.Cyan), { Thickness = 1.1, Transparency = 0.62 })
				end
			end
		end
	end

	local right = mainGui:FindFirstChild("Right")
	local navHolder = right and right:FindFirstChild("Holder")
	if navHolder then
		local function decorateNav(container)
			if not container:IsA("GuiObject") or shouldSkip(container) then
				return
			end
			local accent = accentFor(container, T.Gold)
			AstralVisuals.StyleCard(container, accent, {
				CornerRadius = UDim.new(0.16, 0),
				Thickness = 1.3,
				Transparency = 0.52,
			})
			local trigger = findTrigger(container)
			if trigger then
				AstralVisuals.StyleButton(trigger, accent, {
					Surface = container,
					Thickness = 1.3,
					Transparency = 0.52,
				})
			end
		end
		for _, container in ipairs(navHolder:GetChildren()) do
			decorateNav(container)
		end
		navHolder.ChildAdded:Connect(function(container)
			task.defer(decorateNav, container)
		end)
	end

	local summon = right and right:FindFirstChild("ManualSummonButton", true)
	if summon and summon:IsA("GuiObject") then
		AstralVisuals.StyleCard(summon, T.Pink, { Thickness = 1.6, Transparency = 0.24 })
		local trigger = findTrigger(summon)
		if trigger then
			AstralVisuals.StyleButton(trigger, T.Pink, { Surface = summon, Thickness = 1.6, Transparency = 0.24 })
		end
	end

	mainGui.DescendantAdded:Connect(function(descendant)
		if startsWithAstral(descendant) then
			return
		end
		task.defer(function()
			if descendant.Parent then
				styleObject(descendant, accentFor(descendant, T.Gold))
			end
		end)
	end)
end

local function decorateTooltip(screenGui)
	local tooltip = screenGui:FindFirstChild("Tooltip") or screenGui:WaitForChild("Tooltip", 5)
	-- The tooltip ScreenGui is parented before its visual layers are built.
	-- Waiting for both levels prevents a startup-order race where the global
	-- pass saw the empty ScreenGui once and permanently missed its card.
	local background = tooltip and (tooltip:FindFirstChild("Background") or tooltip:WaitForChild("Background", 5))
	if background and background:IsA("GuiObject") then
		AstralVisuals.ApplyModal(background, {
			Accent = SCREEN_ACCENTS.UpgradeTooltipGui,
			Thickness = 2,
			StrokeTransparency = 0.1,
			StarCount = 4,
			Halo = true,
			Sweep = false,
		})
	end
end

local function decorateProgrammaticScreen(screenGui)
	if decoratedScreens[screenGui] then
		return
	end
	decoratedScreens[screenGui] = true
	local accent = SCREEN_ACCENTS[screenGui.Name] or AstralVisuals.GetAccent(screenGui.Name, T.Gold)

	for _, descendant in ipairs(screenGui:GetDescendants()) do
		if isModalRoot(descendant, screenGui) then
			AstralVisuals.ApplyModal(descendant, {
				Accent = accentFor(descendant, accent),
				Thickness = 2.5,
				StrokeTransparency = 0.1,
				StarCount = 7,
			})
		end
		styleObject(descendant, accent)
	end

	if screenGui.Name == "UpgradeTooltipGui" then
		decorateTooltip(screenGui)
	end

	screenGui.DescendantAdded:Connect(function(descendant)
		if startsWithAstral(descendant) then
			return
		end
		task.defer(function()
			if not descendant.Parent then
				return
			end
			if isModalRoot(descendant, screenGui) then
				AstralVisuals.ApplyModal(descendant, {
					Accent = accentFor(descendant, accent),
					Thickness = 2.5,
					StrokeTransparency = 0.1,
					StarCount = 7,
				})
			end
			styleObject(descendant, accent)
		end)
	end)
end

local function refreshUpgradeNode(node)
	if not node or not node:IsA("GuiObject") then
		return
	end
	local ok, definition = pcall(TreeUpgrades.GetUpgrade, node.Name)
	if not ok or type(definition) ~= "table" then
		return
	end
	local tier = math.max(0, math.floor(tonumber(node:GetAttribute("Tier")) or 0))
	local maxLevel = math.max(1, math.floor(tonumber(definition.MaxLevel) or 1))
	AstralVisuals.StyleUpgradeNode(node, {
		Accent = AstralVisuals.GetBranchAccent(definition.Branch or node:GetAttribute("Category")),
		Locked = node:GetAttribute("Unlocked") == false,
		Buyable = node:GetAttribute("Buyable") == true,
		Maxed = tier >= maxLevel,
		Tier = tier,
	})
end

local function bindUpgradeNode(node)
	if decoratedNodes[node] or not node:IsA("GuiObject") or not node:IsDescendantOf(playerGui) then
		return
	end
	decoratedNodes[node] = true
	refreshUpgradeNode(node)
	node.AttributeChanged:Connect(function(attribute)
		if attribute == "Tier" or attribute == "Unlocked" or attribute == "Buyable" or attribute == "Category" then
			refreshUpgradeNode(node)
		end
	end)
end

for _, node in ipairs(CollectionService:GetTagged("UpgradeNode")) do
	bindUpgradeNode(node)
end
CollectionService:GetInstanceAddedSignal("UpgradeNode"):Connect(bindUpgradeNode)

local function decoratePlayerGuiChild(child)
	if child.Name == "EssencePopupUI" then
		decorateEssencePopups(child)
	elseif child.Name == "MainGui" then
		decorateMainGui(child)
	elseif not EXCLUDED_SCREENS[child.Name] and child:IsA("ScreenGui") then
		decorateProgrammaticScreen(child)
	end
end

for _, child in ipairs(playerGui:GetChildren()) do
	task.defer(decoratePlayerGuiChild, child)
end
playerGui.ChildAdded:Connect(function(child)
	task.defer(decoratePlayerGuiChild, child)
end)

-- A second pass catches screens whose root exists immediately but whose
-- code-built children arrive over the next few frames. DescendantAdded is
-- already live; this simply gives the initial hierarchy a deterministic
-- finishing sweep without a permanent polling loop.
task.delay(2, function()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child.Name == "EssencePopupUI" then
			local holder = child:FindFirstChild("PopupHolder")
			if holder then
				for _, popup in ipairs(holder:GetChildren()) do
					styleDescendants(popup, POPUP_ACCENTS[popup.Name] or T.Gold)
					if popup.Name == "UpgradesPopup" then
						decorateUpgradeViewport(popup, POPUP_ACCENTS.UpgradesPopup)
					end
				end
			end
		elseif child:IsA("ScreenGui") and not EXCLUDED_SCREENS[child.Name] then
			styleDescendants(child, SCREEN_ACCENTS[child.Name] or T.Gold)
		end
	end
end)

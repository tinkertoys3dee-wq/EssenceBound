--[[
	NotificationController (LocalScript -> StarterPlayerScripts)
	============================================================
	Premium, code-built notification stack used by NotificationService.
	Messages merge by key, queue at three visible cards, can be dismissed,
	and animate without blocking gameplay. No authored Studio GUI is needed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local NotificationService = require(ReplicatedStorage:WaitForChild("NotificationService"))
local Juice = require(ReplicatedStorage:WaitForChild("Juice"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PALETTES = {
	Info = {
		Accent = Color3.fromRGB(92, 210, 255),
		Glow = Color3.fromRGB(45, 128, 190),
		Icon = Color3.fromRGB(204, 244, 255),
	},
	Success = {
		Accent = Color3.fromRGB(75, 232, 143),
		Glow = Color3.fromRGB(35, 146, 91),
		Icon = Color3.fromRGB(214, 255, 230),
	},
	Warning = {
		Accent = Color3.fromRGB(255, 190, 66),
		Glow = Color3.fromRGB(190, 105, 35),
		Icon = Color3.fromRGB(255, 239, 185),
	},
	Error = {
		Accent = Color3.fromRGB(255, 91, 116),
		Glow = Color3.fromRGB(178, 42, 75),
		Icon = Color3.fromRGB(255, 220, 226),
	},
}

local function new(className, properties, parent)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(0, 14) }, parent)
end

local function tween(target, info, properties)
	local result = TweenService:Create(target, info, properties)
	result:Play()
	return result
end

local existing = playerGui:FindFirstChild("EssenceNotifications")
if existing then
	existing:Destroy()
end

local screenGui = new("ScreenGui", {
	Name = "EssenceNotifications",
	DisplayOrder = 420,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Global,
}, playerGui)

local host = new("Frame", {
	Name = "Stack",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.145),
	Size = UDim2.new(0.42, 0, 0, 276),
	BackgroundTransparency = 1,
	ZIndex = 420,
}, screenGui)
new("UISizeConstraint", {
	MinSize = Vector2.new(280, 0),
	MaxSize = Vector2.new(520, 276),
}, host)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 8),
}, host)

local activeByKey = {}
local activeCount = 0
local sequence = 0
local pending = {}
local showNext

local function playTone(kind)
	local sound = Juice.FindSound("SFX/UI/UIPop")
	if not sound then
		return
	end
	local pitches = { Info = 1, Success = 1.24, Warning = 0.9, Error = 0.76 }
	Juice.PlaySound(sound, { Pitch = pitches[kind] or 1, Volume = 0.28 })
end

local function dismiss(entry)
	if entry.Closing then
		return
	end
	entry.Closing = true
	entry.ExpiryToken += 1
	if entry.ProgressTween then
		entry.ProgressTween:Cancel()
	end
	if activeByKey[entry.Key] == entry then
		activeByKey[entry.Key] = nil
	end
	activeCount = math.max(0, activeCount - 1)

	tween(entry.Scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.84 })
	local fade = tween(entry.Group, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	})
	fade.Completed:Connect(function()
		if entry.Slot then
			entry.Slot:Destroy()
		end
		showNext()
	end)
end

local function restartTimer(entry, duration)
	entry.ExpiryToken += 1
	local token = entry.ExpiryToken
	if entry.ProgressTween then
		entry.ProgressTween:Cancel()
	end
	entry.Progress.Size = UDim2.fromScale(1, 1)
	entry.ProgressTween = tween(entry.Progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, 1),
	})
	task.delay(duration, function()
		if not entry.Closing and entry.ExpiryToken == token then
			dismiss(entry)
		end
	end)
end

local function createCard(payload)
	sequence += 1
	activeCount += 1
	local palette = PALETTES[payload.Kind] or PALETTES.Info

	local slot = new("Frame", {
		Name = payload.Kind .. "Notification",
		LayoutOrder = sequence,
		Size = UDim2.new(1, 0, 0, 82),
		BackgroundTransparency = 1,
		ZIndex = 421,
	}, host)

	local group = new("CanvasGroup", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 13, 36),
		BackgroundTransparency = 0.03,
		GroupTransparency = 1,
		ClipsDescendants = false,
		ZIndex = 422,
	}, slot)
	corner(group, UDim.new(0, 15))
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 27, 66)),
			ColorSequenceKeypoint.new(0.68, Color3.fromRGB(23, 15, 41)),
			ColorSequenceKeypoint.new(1, palette.Glow:Lerp(Color3.fromRGB(18, 12, 31), 0.72)),
		}),
		Rotation = 8,
	}, group)
	new("UIStroke", {
		Color = palette.Accent,
		Thickness = 2,
		Transparency = 0.16,
	}, group)
	local scale = new("UIScale", { Scale = 0.78 }, group)
	scale:SetAttribute("JuiceBaseScale", 1)

	local shadow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 6),
		Size = UDim2.new(1, 8, 1, 8),
		BackgroundColor3 = palette.Glow,
		BackgroundTransparency = 0.82,
		ZIndex = 421,
	}, slot)
	corner(shadow, UDim.new(0, 18))

	local accent = new("Frame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, 7, 1, 0),
		BackgroundColor3 = palette.Accent,
		BorderSizePixel = 0,
		ZIndex = 424,
	}, group)
	corner(accent, UDim.new(0, 15))
	new("UIGradient", {
		Color = ColorSequence.new(palette.Icon, palette.Accent),
		Rotation = 90,
	}, accent)

	local iconGlow = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 43, 0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		BackgroundColor3 = palette.Glow,
		BackgroundTransparency = 0.5,
		ZIndex = 423,
	}, group)
	corner(iconGlow, UDim.new(1, 0))
	new("UIStroke", { Color = palette.Accent, Thickness = 2, Transparency = 0.22 }, iconGlow)
	local icon = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = payload.Icon,
		TextColor3 = palette.Icon,
		TextScaled = true,
		ZIndex = 425,
	}, iconGlow)
	new("UITextSizeConstraint", { MinTextSize = 15, MaxTextSize = 27 }, icon)

	local title = new("TextLabel", {
		Position = UDim2.new(0, 78, 0, 12),
		Size = UDim2.new(1, -130, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = string.upper(payload.Title),
		TextColor3 = palette.Icon,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 425,
	}, group)

	local message = new("TextLabel", {
		Position = UDim2.new(0, 78, 0, 35),
		Size = UDim2.new(1, -112, 0, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = payload.Message,
		TextColor3 = Color3.fromRGB(231, 224, 242),
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 425,
	}, group)

	local countBadge = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 10),
		Size = UDim2.fromOffset(34, 20),
		BackgroundColor3 = palette.Accent,
		BackgroundTransparency = 0.08,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = Color3.fromRGB(25, 16, 38),
		TextSize = 12,
		Visible = false,
		ZIndex = 427,
	}, group)
	corner(countBadge, UDim.new(1, 0))

	local closeButton = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(24, 24),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.9,
		AutoButtonColor = false,
		Font = Enum.Font.GothamBold,
		Text = "×",
		TextColor3 = Color3.fromRGB(211, 202, 225),
		TextSize = 18,
		ZIndex = 428,
	}, group)
	corner(closeButton, UDim.new(1, 0))

	local progressTrack = new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 15, 1, -5),
		Size = UDim2.new(1, -30, 0, 3),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 0.88,
		ClipsDescendants = true,
		ZIndex = 426,
	}, group)
	corner(progressTrack, UDim.new(1, 0))
	local progress = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = palette.Accent,
		BorderSizePixel = 0,
		ZIndex = 427,
	}, progressTrack)
	corner(progress, UDim.new(1, 0))

	local entry = {
		Key = payload.Key,
		Kind = payload.Kind,
		Slot = slot,
		Group = group,
		Scale = scale,
		Message = message,
		CountBadge = countBadge,
		Progress = progress,
		Count = 1,
		ExpiryToken = 0,
		Closing = false,
	}
	activeByKey[payload.Key] = entry

	closeButton.Activated:Connect(function()
		dismiss(entry)
	end)
	closeButton.MouseEnter:Connect(function()
		tween(closeButton, TweenInfo.new(0.12), { BackgroundTransparency = 0.72, TextColor3 = palette.Icon })
	end)
	closeButton.MouseLeave:Connect(function()
		tween(closeButton, TweenInfo.new(0.12), { BackgroundTransparency = 0.9, TextColor3 = Color3.fromRGB(211, 202, 225) })
	end)

	playTone(payload.Kind)
	tween(group, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 })
	tween(scale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	tween(shadow, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.93 })
	restartTimer(entry, payload.Duration)

	if payload.Kind == "Error" then
		task.delay(0.12, function()
			Juice.Shake(group, 4, 0.22)
		end)
	elseif payload.Kind == "Success" then
		task.delay(0.28, function()
			if scale.Parent then
				Juice.Punch(scale, 0.07, 0.24)
			end
		end)
	end
end

showNext = function()
	while activeCount < 3 and #pending > 0 do
		local payload = table.remove(pending, 1)
		createCard(payload)
	end
end

local function enqueue(payload)
	if type(payload) ~= "table" or type(payload.Message) ~= "string" then
		return
	end

	local duplicate = activeByKey[payload.Key]
	if duplicate and not duplicate.Closing then
		duplicate.Count += 1
		duplicate.Message.Text = payload.Message
		duplicate.CountBadge.Text = "×" .. tostring(duplicate.Count)
		duplicate.CountBadge.Visible = true
		Juice.Punch(duplicate.Scale, 0.09, 0.22)
		if payload.Kind == "Error" or payload.Kind == "Warning" then
			Juice.Shake(duplicate.Group, 3, 0.18)
		end
		restartTimer(duplicate, payload.Duration)
		return
	end

	if activeCount >= 3 then
		for index, queued in ipairs(pending) do
			if queued.Key == payload.Key then
				pending[index] = payload
				return
			end
		end
		table.insert(pending, payload)
		if #pending > 9 then
			table.remove(pending, 1)
		end
		return
	end
	createCard(payload)
end

local localSignal = NotificationService.GetSignal()
if localSignal then
	localSignal:Connect(enqueue)
end

task.spawn(function()
	local remotesFolder = ReplicatedStorage:WaitForChild("NotificationRemotes", 30)
	local remote = remotesFolder and remotesFolder:WaitForChild("PushNotification", 10)
	if not remote then
		warn("NotificationController: server notification remote was not available.")
		return
	end
	remote.OnClientEvent:Connect(enqueue)
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local config = require(ReplicatedStorage:WaitForChild("ResonanceConfig"))
local remotes = ReplicatedStorage:WaitForChild("ResonanceRemotes")
local sync = remotes:WaitForChild("Sync")
local activate = remotes:WaitForChild("Activate")
local requestSnapshot = remotes:WaitForChild("RequestSnapshot")

local gui = Instance.new("ScreenGui")
gui.Name = "ResonanceHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 18
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "ResonanceCard"
card.AnchorPoint = Vector2.new(0.5, 1)
card.Position = UDim2.new(0.5, 0, 1, -18)
card.Size = UDim2.new(0.9, 0, 0, 76)
card.BackgroundColor3 = Color3.fromRGB(18, 17, 31)
card.BackgroundTransparency = 0.08
card.Parent = gui
local sizeConstraint = Instance.new("UISizeConstraint", card)
sizeConstraint.MaxSize = Vector2.new(390, 76)
sizeConstraint.MinSize = Vector2.new(300, 76)
Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
local stroke = Instance.new("UIStroke", card)
stroke.Color = Color3.fromRGB(139, 106, 255)
stroke.Transparency = 0.25

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14, 7)
title.Size = UDim2.new(1, -130, 0, 22)
title.Font = Enum.Font.GothamBold
title.TextColor3 = Color3.fromRGB(230, 222, 255)
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "RESONANCE  •  Alternate Earth / Shadow"
title.Parent = card

local bar = Instance.new("Frame")
bar.Position = UDim2.fromOffset(14, 37)
bar.Size = UDim2.new(1, -132, 0, 18)
bar.BackgroundColor3 = Color3.fromRGB(43, 39, 62)
bar.Parent = card
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromRGB(126, 93, 255)
fill.Parent = bar
Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
local meterText = Instance.new("TextLabel")
meterText.Size = UDim2.fromScale(1, 1)
meterText.BackgroundTransparency = 1
meterText.Font = Enum.Font.GothamBold
meterText.TextColor3 = Color3.new(1, 1, 1)
meterText.TextSize = 12
meterText.Parent = bar

local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(1, 0.5)
button.Position = UDim2.new(1, -10, 0.5, 0)
button.Size = UDim2.fromOffset(105, 50)
button.BackgroundColor3 = Color3.fromRGB(73, 64, 99)
button.TextColor3 = Color3.new(1, 1, 1)
button.Font = Enum.Font.GothamBold
button.TextSize = 14
button.Text = "CHARGING"
button.AutoButtonColor = false
button.Parent = card
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 11)

local current = { Pulse = 0, OverdriveRemaining = 0 }
local receivedAt = 0
button.Activated:Connect(function()
	if current.Pulse >= config.PulseRequired and current.OverdriveRemaining <= 0 then
		activate:FireServer()
	end
end)

local function applySnapshot(data)
	if type(data) ~= "table" then
		return
	end
	current = data
	receivedAt = os.clock()
	local active = data.OverdriveRemaining > 0
	local ratio = active and math.clamp(data.OverdriveRemaining / config.OverdriveSeconds, 0, 1)
		or math.clamp(data.Pulse / config.PulseRequired, 0, 1)
	TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(ratio, 1) }):Play()
	fill.BackgroundColor3 = active and Color3.fromRGB(255, 190, 68) or Color3.fromRGB(126, 93, 255)
	meterText.Text = active and string.format("OVERDRIVE  %.1fs", data.OverdriveRemaining)
		or string.format("PULSE  %d / %d", data.Pulse, config.PulseRequired)
	title.Text = string.format(
		"RESONANCE  •  Harmony %d/%d (x%.2f)  •  Mastery %d",
		data.Harmony,
		config.MaxHarmony,
		config.GetHarmonyMultiplier(data.Harmony),
		data.MasteryLevel
	)
	button.Text = active and "ACTIVE\n2x" or (data.Pulse >= config.PulseRequired and "ACTIVATE" or "CHARGING")
	button.BackgroundColor3 = data.Pulse >= config.PulseRequired and not active and Color3.fromRGB(126, 93, 255)
		or Color3.fromRGB(73, 64, 99)
end

sync.OnClientEvent:Connect(applySnapshot)

-- Request the authoritative initial state after the event listener exists.
-- This works independently for every client and closes the join-order race.
task.spawn(function()
	local ok, data = pcall(function()
		return requestSnapshot:InvokeServer()
	end)
	if ok then
		applySnapshot(data)
	end
end)

-- Keep the active countdown fluid between server snapshots. This is display
-- only; the server owns both the deadline and every multiplier decision.
RunService.RenderStepped:Connect(function()
	if current.OverdriveRemaining <= 0 then
		return
	end
	local remaining = math.max(0, current.OverdriveRemaining - (os.clock() - receivedAt))
	meterText.Text = string.format("OVERDRIVE  %.1fs", remaining)
	fill.Size = UDim2.fromScale(math.clamp(remaining / config.MaxOverdriveSeconds, 0, 1), 1)
	if remaining <= 0 then
		current.OverdriveRemaining = 0
		button.Text = "CHARGING"
		button.BackgroundColor3 = Color3.fromRGB(73, 64, 99)
	end
end)

local button = script.Parent
local player = game:GetService("Players").LocalPlayer
local TweenService = game:GetService("TweenService")

local glowOuter = button:WaitForChild("GlowOuter")
local glowInner = button:WaitForChild("GlowInner")
local bgGradient = button:WaitForChild("BgGradient")
local scaleObj = button:WaitForChild("PressScale")
local icon = button:WaitForChild("Icon")

local READY_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 70, 30)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 45, 10)),
})
local COOLDOWN_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(35, 35, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 20, 24)),
})

-- Idle "breathing" glow + gradient rotation, runs continuously while ready
local pulseUp = TweenService:Create(glowOuter, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.75})
local pulseDown = TweenService:Create(glowOuter, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.92})

task.spawn(function()
	while true do
		if button.Active then
			pulseUp:Play()
			pulseUp.Completed:Wait()
			pulseDown:Play()
			pulseDown.Completed:Wait()
		else
			task.wait(0.5)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.03)
		if button.Active then
			bgGradient.Rotation = (bgGradient.Rotation + 0.6) % 360
		end
	end
end)

local function setReadyLook(isReady)
	bgGradient.Color = isReady and READY_GRADIENT or COOLDOWN_GRADIENT
	glowOuter.Visible = isReady
	glowInner.Visible = isReady
	icon.TextTransparency = isReady and 0 or 0.55
	icon.TextStrokeTransparency = isReady and 0.2 or 0.7
end

button:GetPropertyChangedSignal("Active"):Connect(function()
	setReadyLook(button.Active)
end)
setReadyLook(button.Active)

-- Hover + press feedback (AutoButtonColor is off so we drive this by hand)
button.MouseEnter:Connect(function()
	if not button.Active then return end
	TweenService:Create(scaleObj, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.06}):Play()
	TweenService:Create(button.Border, TweenInfo.new(0.12), {Thickness = 3.5}):Play()
end)

button.MouseLeave:Connect(function()
	TweenService:Create(scaleObj, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1}):Play()
	TweenService:Create(button.Border, TweenInfo.new(0.15), {Thickness = 2.5}):Play()
end)

button.MouseButton1Down:Connect(function()
	if not button.Active then return end
	TweenService:Create(scaleObj, TweenInfo.new(0.08), {Scale = 0.94}):Play()
end)

button.MouseButton1Up:Connect(function()
	if not button.Active then return end
	TweenService:Create(scaleObj, TweenInfo.new(0.1), {Scale = 1.06}):Play()
end)

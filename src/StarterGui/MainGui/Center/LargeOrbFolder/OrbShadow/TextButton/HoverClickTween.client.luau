local TweenService = game:GetService("TweenService")
local button = script.Parent
local uiScale = button.Parent:WaitForChild("UIScale")

-- 0.1 seconds makes the button feel incredibly snappy and responsive
local tweenInfo = TweenInfo.new(
	0.1,                          
	Enum.EasingStyle.Quad,         
	Enum.EasingDirection.Out       
)

-- Define all three states: Normal, Hovered, and Clicked
local hoverTween = TweenService:Create(uiScale, tweenInfo, {Scale = 1.1})  -- Grows to 110%
local normalTween = TweenService:Create(uiScale, tweenInfo, {Scale = 1.0}) -- Returns to 100%
local clickTween = TweenService:Create(uiScale, tweenInfo, {Scale = 0.95}) -- Squishes to 95%

-- Hover Animations
button.MouseEnter:Connect(function()
	hoverTween:Play()
end)

button.MouseLeave:Connect(function()
	normalTween:Play()
end)

-- Click Animations
button.MouseButton1Down:Connect(function()
	clickTween:Play()
end)

button.MouseButton1Up:Connect(function()
	-- If the mouse is still inside the button when released, go back to hover size
	hoverTween:Play()
end)
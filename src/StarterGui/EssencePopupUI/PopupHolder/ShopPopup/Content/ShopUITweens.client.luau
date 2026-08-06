local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


-------------------------------------------------------------------
-- THEME (matched to the dark purple / gold-orange / green look)
-------------------------------------------------------------------
local THEME = {
	Background      = Color3.fromRGB(24, 12, 40),
	BackgroundLight = Color3.fromRGB(36, 19, 58),
	Accent          = Color3.fromRGB(247, 165, 60),   -- gold/orange dividers
	Green           = Color3.fromRGB(58, 209, 118),   -- essence green
	White           = Color3.fromRGB(255, 255, 255),
	Grey            = Color3.fromRGB(146, 136, 160),
	Locked          = Color3.fromRGB(58, 50, 76),
	Red             = Color3.fromRGB(230, 80, 90),
}

local function tween(obj, info, props)
	return TweenService:Create(obj, info, props)
end

-- Generic hover-grow + press-shrink "button feel" animation.
-- parent: if set, this object is tweened/scaled instead of `button` itself
--         (useful when `button` is a transparent overlay sitting on a card/frame).
-- highlight: if true, fades in a UIStroke outline around the tweened object on hover.
local function applyButtonFeel(button, hoverScale, baseColor, hoverColor, parent, highlight, highlightColor)
	hoverScale = hoverScale or 1.05

	local tweener = parent or button
	local baseSize = tweener.Size

	local function scaled(mult)
		return UDim2.new(
			baseSize.X.Scale * mult, baseSize.X.Offset * mult,
			baseSize.Y.Scale * mult, baseSize.Y.Offset * mult
		)
	end

	local highlightStroke
	if highlight then
		highlightStroke = tweener:FindFirstChild("HoverHighlight")
		if not highlightStroke then
			highlightStroke = Instance.new("UIStroke")
			highlightStroke.Name = "HoverHighlight"
			highlightStroke.Thickness = 2
			highlightStroke.Color = highlightColor or THEME.Accent
			highlightStroke.Transparency = 1 -- hidden until hovered
			highlightStroke.Parent = tweener
		end
	end

	button.MouseEnter:Connect(function()
		tween(tweener, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Size = scaled(hoverScale)}):Play()
		if hoverColor then
			tween(tweener, TweenInfo.new(0.15), {BackgroundColor3 = hoverColor}):Play()
		end
		if highlightStroke then
			tween(highlightStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		tween(tweener, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Size = baseSize}):Play()
		if baseColor then
			tween(tweener, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
		end
		if highlightStroke then
			tween(highlightStroke, TweenInfo.new(0.15), {Transparency = 1}):Play()
		end
	end)

	button.MouseButton1Down:Connect(function()
		tween(tweener, TweenInfo.new(0.08), {Size = scaled(hoverScale * 0.9)}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		tween(tweener, TweenInfo.new(0.12), {Size = scaled(hoverScale)}):Play()
	end)
end


local function stroke(parent, color, thickness, transparency)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local function tweenToFrame(scrollingFrame: ScrollingFrame, targetFrame: Frame)
	-- 1. Wait a frame so UI layouts (UIListLayout, etc.) can finish positioning elements
	RunService.Heartbeat:Wait()

	-- 2. Calculate the pixel gap between the scrolling frame's top and the target frame
	local relativeY = targetFrame.AbsolutePosition.Y - scrollingFrame.AbsolutePosition.Y

	-- 3. Determine the final target Y position for the canvas
	local targetScrollY = scrollingFrame.CanvasPosition.Y + relativeY

	-- 4. Clamp the destination so it doesn't try to scroll past the bounds of the canvas
	local maxScroll = scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y
	targetScrollY = math.clamp(targetScrollY, 0, maxScroll)

	-- 5. Set up the tween (0.4 seconds, smooth easing)
	local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(scrollingFrame, tweenInfo, {
		CanvasPosition = Vector2.new(0, targetScrollY)
	})

	-- 6. Play it!
	tween:Play()
end

for _, button in script.Parent:WaitForChild("Tabs"):GetDescendants() do
	if button:IsA("TextButton") then
		applyButtonFeel(button, 1.05)
		button:SetAttribute("Set", true)
		button.MouseButton1Click:Connect(function()
			for _, p in pairs(script.Parent:WaitForChild("Tabs"):GetDescendants()) do
				if p:IsA("TextButton") then
					tween(p, TweenInfo.new(0.15), {BackgroundColor3 = THEME.BackgroundLight}):Play()
				end
			end
			tween(button, TweenInfo.new(0.15), {BackgroundColor3 = THEME.Green}):Play()
			tweenToFrame(script.Parent,script.Parent:FindFirstChild(button.Name))
		end)
		
	end
end
local remote = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("RequestPurchase")

for _, button in script.Parent:GetDescendants() do
	if button:IsA("TextButton") and not button:GetAttribute("Set")then
		applyButtonFeel(button, 1.04, nil, nil, button.Parent, true, THEME.Accent)

		button.MouseButton1Click:Connect(function()
			
			if button.Parent:GetAttribute("Gamepass") then
				remote:FireServer("gamepass", button.Parent.Name)
			elseif button.Parent:GetAttribute("Product") then
				remote:FireServer("product", button.Parent.Name)
			end
			
			-- cosmetic "purchase" feedback only, no real transaction
			local ring = stroke(button.Parent, THEME.White, 3, 0)
			tween(ring, TweenInfo.new(0.4), {Transparency = 1}):Play()
			task.delay(0.4, function()
				if ring then ring:Destroy() end
			end)
		end)
	end
	
end

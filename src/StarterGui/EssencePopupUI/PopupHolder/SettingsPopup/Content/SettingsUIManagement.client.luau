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

local function applyButtonFeel(button, hoverScale, baseColor, hoverColor, parent, highlight, highlightColor)
	hoverScale = hoverScale or 1.05

	local tweener = parent or button
	local UIScale = parent:FindFirstChild("UIScale") 
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
		tween(UIScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Scale = 1.05}):Play()
		if hoverColor then
			tween(tweener, TweenInfo.new(0.15), {BackgroundColor3 = hoverColor}):Play()
		end
		if highlightStroke then
			tween(highlightStroke, TweenInfo.new(0.15), {Transparency = 0}):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		tween(UIScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Scale = 1}):Play()
		if baseColor then
			tween(tweener, TweenInfo.new(0.15), {BackgroundColor3 = baseColor}):Play()
		end
		if highlightStroke then
			tween(highlightStroke, TweenInfo.new(0.15), {Transparency = 1}):Play()
		end
	end)

	button.MouseButton1Down:Connect(function()
		tween(UIScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Scale = .9}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		tween(UIScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Scale = 1}):Play()
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

local presets = {
	["On"] = {
		["BG"] = Color3.fromRGB(58, 209, 118),
		["Dot"] = Color3.fromRGB(255, 255, 255),
		["DotPos"] = UDim2.new(1, -23,0.5, 0),
	},
	["Off"] = {
		["BG"] = Color3.fromRGB(58, 50, 76),
		["Dot"] = Color3.fromRGB(255, 255, 255),
		["DotPos"] = UDim2.new(0, 3,0.5, 0)
	}
}

local deb = false


local UpdateSetting = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("UpdateData")

for _, button in script.Parent:GetDescendants() do
	if button:IsA("TextButton") then
		button.AttributeChanged:Connect(function(Name)
			if Name == "On" then
				if button:GetAttribute("On") then
					if button.Parent.Name == "Music" then
						game.SoundService.Music.Volume = 0.5
					elseif button.Parent.Name == "SFX" then
						game.SoundService.SFX.Volume = 0.5
					end
				elseif not button:GetAttribute("On") then
					if button.Parent.Name == "Music" then
						game.SoundService.Music.Volume = 0
					elseif button.Parent.Name == "SFX" then
						game.SoundService.SFX.Volume = 0
					end
				end
			end
		end)
		applyButtonFeel(button, 1.3, nil, nil, button.Parent, true, THEME.Accent)

		if player:GetAttribute(string.gsub(button.Parent.Name, "%s", "")) then
			button.BackgroundColor3 = presets.On.BG
			button.Frame.Position = presets.On.DotPos
			button:SetAttribute("On", true)
		else
			button.BackgroundColor3 = presets.Off.BG
			button.Frame.Position = presets.Off.DotPos
			button:SetAttribute("On", false)
		end

		button.MouseButton1Click:Connect(function()
			if not deb then
				deb = true
				if button:GetAttribute("On") then
					button:SetAttribute("On", false)
					button.BackgroundColor3 = presets.Off.BG
					button.Frame.Position = presets.Off.DotPos
					
					local Text = button.Parent:FindFirstChild("TextLabel").Text
					
					UpdateSetting:FireServer(false, "=", "Settings", Text)
					task.wait(2)
					deb = false
				else
					button:SetAttribute("On", true)
					button.BackgroundColor3 = presets.On.BG
					button.Frame.Position = presets.On.DotPos
					
					local Text = button.Parent:FindFirstChild("TextLabel").Text

					UpdateSetting:FireServer(true, "=", "Settings", Text)
					task.wait(2)
					deb = false
				end
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


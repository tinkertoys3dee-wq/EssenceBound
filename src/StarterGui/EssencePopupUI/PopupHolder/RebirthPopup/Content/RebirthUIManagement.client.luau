local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local rebithSound = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("UI"):WaitForChild("Rebirth")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Rebirth = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("Rebirth")
local module = require(game:GetService("ReplicatedStorage"):WaitForChild("RebirthEffect"))
local RebirthModule = require(game:GetService("ReplicatedStorage"):WaitForChild("RebirthHandler"))
local Juice = require(game:GetService("ReplicatedStorage"):WaitForChild("Juice"))
local juiceLayer = Juice.GetLayer(playerGui)
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
		if not highlightStroke and not button:GetAttribute("Stroke") then
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

local deb = false

local GUI = playerGui:WaitForChild("RebirthGUI")

local RebirthGui = script.Parent.Parent
local backdrop = RebirthGui.Parent.Parent:FindFirstChild("Backdrop")
for _, button in script.Parent:GetDescendants() do
	if button:IsA("TextButton") then
		local highlight = true
		if button:GetAttribute("NoHighlight") then
			highlight = false
		end
		applyButtonFeel(button, 1.3, nil, nil, button.Parent, true, THEME.Accent)

		button.MouseButton1Click:Connect(function()
			if highlight then
				-- cosmetic "purchase" feedback only, no real transaction
				local ring = stroke(button.Parent, THEME.White, 3, 0)
				tween(ring, TweenInfo.new(0.4), {Transparency = 1}):Play()
				task.delay(0.4, function()
					if ring then ring:Destroy() end
				end)
			end
			
			if button.Name == "Rebirth" then
				if not deb then
					deb = true
					Rebirth:FireServer()
					
					
					task.wait(0.2)
					deb = false
				end
			end
		end)
	end
end

local MILESTONE_COLOR = Color3.fromRGB(255, 165, 60)

-- Milestone rebirths (see RebirthHandler.luau's MILESTONES table -- 1, 5,
-- 10, 25, 50) grant a permanent bonus on top of the normal per-rebirth
-- boost, a genuinely bigger moment than an ordinary rebirth, but until
-- now got the exact same treatment as every other one. Layered AFTER the
-- base RebirthEffect finishes (via handle.Completed below) rather than
-- competing with it for the same screen space.
local function celebrateMilestoneIfAny(rebirthCount)
	local milestone = RebirthModule.GetMilestone(rebirthCount)
	if not milestone or not juiceLayer then
		return
	end

	local center = UDim2.fromScale(0.5, 0.4)

	Juice.Flash(juiceLayer, { Color = MILESTONE_COLOR, Peak = 0.45, Duration = 0.6 })
	Juice.Ring(juiceLayer, center, {
		Color = MILESTONE_COLOR, StartSize = 30, EndSize = 320, Duration = 0.9, Thickness = 5,
	})
	Juice.Burst(juiceLayer, center, {
		Count = 26,
		Colors = { MILESTONE_COLOR, Color3.fromRGB(255, 255, 255) },
		Distance = 260,
		Duration = 1.0,
		Size = { 6, 13 },
	})

	Juice.FloatText(juiceLayer, center, "⭐ MILESTONE: " .. (milestone.title or "Reborn"), {
		Color = MILESTONE_COLOR,
		Duration = 2.0,
		Rise = 90,
		TextSize = 34,
	})

	if milestone.description then
		task.delay(0.2, function()
			Juice.FloatText(juiceLayer, center + UDim2.fromScale(0, 0.1), milestone.description, {
				Color = Color3.fromRGB(255, 255, 255),
				Duration = 2.2,
				Rise = 70,
				TextSize = 18,
			})
		end)
	end

	local sound = Juice.FindSound("SFX/UI/UIPop")
	if sound then
		for i = 0, 3 do
			task.delay(i * 0.08, function()
				Juice.PlaySound(sound, { Pitch = 1.1 + i * 0.18, Volume = 0.55 })
			end)
		end
	end
end

Rebirth.OnClientEvent:Connect(function()
	RebirthGui.Visible = false
	backdrop.Visible = false
	rebithSound:Play()
	local handle = module.Play(GUI, {
		Theme = "Amethyst",
		RebirthCount = player:GetAttribute("Rebirths"),
	})

	handle.Completed:Connect(function()
		print("Rebirth animation done, GUI is clean again")
		celebrateMilestoneIfAny(player:GetAttribute("Rebirths"))
	end)
end)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local largedisplay = script.Parent:WaitForChild("Frame"):WaitForChild("LargeDisplay")
local Orbit1 = largedisplay:WaitForChild("Orbiter1")
local Orbit2 = largedisplay:WaitForChild("Orbiter2")
local orbiters = {Orbit1, Orbit2}

local activeOrbits = {}
local heartbeatConnection

local function updateOrbits(dt)
	local parentAbsPos = largedisplay.AbsolutePosition

	for _, orbit in ipairs(activeOrbits) do
		local centerAbsPos = orbit.center.AbsolutePosition
		local centerAbsSize = orbit.center.AbsoluteSize

		local centerX = (centerAbsPos.X - parentAbsPos.X) + centerAbsSize.X / 2
		local centerY = (centerAbsPos.Y - parentAbsPos.Y) + centerAbsSize.Y / 2

		local radiusX = (centerAbsSize.X / 2) * orbit.radiusScale
		local radiusY = (centerAbsSize.Y / 2) * orbit.radiusScale

		orbit.angle = (orbit.angle + orbit.speed * dt * orbit.direction) % 360
		local radians = math.rad(orbit.angle)

		local x = math.cos(radians) * radiusX
		local y = math.sin(radians) * radiusY

		orbit.image.Position = UDim2.new(0, centerX + x, 0, centerY + y)
	end
end

local function addRandomOrbit(imageId, options)
	options = options or {}

	local center = orbiters[math.random(1, #orbiters)]

	local orbitingImage = Instance.new("ImageLabel")
	orbitingImage.Name = "OrbitingImage"
	orbitingImage.BackgroundTransparency = 1
	orbitingImage.Image = imageId
	
	local size = math.random(10,15)
	orbitingImage.Size = options.Size or UDim2.fromOffset(size, size)
	orbitingImage.AnchorPoint = Vector2.new(0.5, 0.5)
	orbitingImage.ZIndex = 14
	orbitingImage.Parent = largedisplay

	table.insert(activeOrbits, {
		image = orbitingImage,
		center = center,
		angle = math.random(0, 360),
		speed = options.Speed or 60,
		direction = (options.Clockwise ~= false) and 1 or -1,
		radiusScale = options.RadiusScale or 1,
	})

	if not heartbeatConnection then
		heartbeatConnection = RunService.RenderStepped:Connect(updateOrbits)
	end

	return orbitingImage
end

local rebirths = player:GetAttribute("Rebirths") or 0
for i = 1, rebirths do
	addRandomOrbit("rbxassetid://72641569769631", { Speed = math.random(30, 60) })
end

player:GetAttributeChangedSignal("Rebirths"):Connect(function()
	addRandomOrbit("rbxassetid://72641569769631", { Speed = math.random(30, 60) })
end)
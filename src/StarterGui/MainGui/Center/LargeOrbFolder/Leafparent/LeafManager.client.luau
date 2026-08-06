local mainOrb = script.Parent
local angle = 0
local RunService = game:GetService("RunService")
local TweenService= game:GetService("TweenService")
local RP = game:GetService("ReplicatedStorage")
local LeafBase = RP:WaitForChild("Cloneables"):WaitForChild("Leaf")
	
local function cloneleaf()
	local c = LeafBase:Clone()

	-- Pick a random direction (angle) in radians
	local angle = math.random() * math.pi * 2

	-- Determine the minimum distance (just past the orb's edge) 
	-- and add a bit of random extra distance so they aren't in a perfect single file line
	local minRadiusX = mainOrb.Size.X.Scale / .8
	local minRadiusY = mainOrb.Size.Y.Scale / .8
	local randomExtraX = math.random() * 0.05 
	local randomExtraY = math.random() * 0.05

	-- Calculate the X and Y offsets using Cosine and Sine
	local offsetX = math.cos(angle) * (minRadiusX + randomExtraX)
	local offsetY = math.sin(angle) * (minRadiusY + randomExtraY)

	-- Position the leaf relative to the center of the orb
	c.Position = UDim2.new(
		0.5 + offsetX, 0,
		0.5 + offsetY, 0
	)

	-- Since the leaves are inside the orb folder/object, 
	-- make sure their AnchorPoint is set to (0.5, 0.5) so they center perfectly!
	c.AnchorPoint = Vector2.new(0.5, 0.5)

	c.Rotation = math.random(1, 360)
	c.Parent = mainOrb
	
	local baseRotation = c.Rotation

	local fallDuration = math.random(4, 8) 
	local targetPosition = UDim2.new(c.Position.X.Scale, 0, 3, 0) 

	local tweenInfo = TweenInfo.new(
		fallDuration,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out
	)

	local fallTween = TweenService:Create(c, tweenInfo, {
		Position = targetPosition,
		ImageTransparency = 1
	})

	fallTween:Play()

	-- 3. Add the gentle, leaf-like drift and rock
	local waveSpeed = math.random(2, 4) -- How fast it sways
	local waveSize = math.random(15, 35)  -- How many pixels it drifts left/right
	local rockAmount = math.random(15, 25) -- How many degrees it tilts back and forth
	local randomPhase = math.random() * 10 

	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not c or not c.Parent then
			connection:Disconnect()
			return
		end

		-- Calculate the current wave position based on time
		local waveLogic = (os.clock() * waveSpeed) + randomPhase
		local swayOffset = math.sin(waveLogic)

		-- Drift horizontally using the X.Offset (keeps the Tween's Scale)
		c.Position = UDim2.new(c.Position.X.Scale, swayOffset * waveSize, c.Position.Y.Scale, 0)

		-- Rock the rotation gently back and forth instead of spinning endlessly
		c.Rotation = baseRotation + (swayOffset * rockAmount)
	end)

	-- 4. Clean up once they finish falling
	fallTween.Completed:Connect(function()
		connection:Disconnect()
		c:Destroy()
	end)
end

for _,c in pairs(mainOrb:GetChildren()) do
	if c:IsA("ImageLabel") then
		-- 2. Setup the falling and fading animation (Tween)
		local radius = 0.6 + (math.random(0,1) * 0.06) 

		-- 3. Set how fast they orbit around the center
		local orbitSpeed = math.random(1, 2)  / 8

		-- Optional: Makes half the leaves orbit clockwise, and half counter-clockwise
		local direction = (math.random(1, 2) == 1) and 1 or -1
		orbitSpeed = orbitSpeed * direction

		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Parent = mainOrb

		-- 4. Spin them around the center frame-by-frame
		local connection
		local startingAngle = c.Rotation
		connection = RunService.RenderStepped:Connect(function()
			if not c or not c.Parent then
				connection:Disconnect()
				return
			end

			-- Calculate the new angle based on elapsed time
			local currentAngle = startingAngle + (os.clock() * orbitSpeed)

			-- Math to convert the angle into 2D circular X and Y coordinates
			local x = math.cos(currentAngle) * radius
			local y = math.sin(currentAngle) * radius

			-- Position them relative to 0.5 (the dead center of the main orb)
			c.Position = UDim2.new(0.5 + x, 0, 0.5 + y, 0)

			-- Automatically rotates the leaf texture so it faces the direction it is traveling
			c.Rotation = math.deg(currentAngle) + 90 
		end)
	end
end

while true do
	cloneleaf()
	task.wait(2)
end
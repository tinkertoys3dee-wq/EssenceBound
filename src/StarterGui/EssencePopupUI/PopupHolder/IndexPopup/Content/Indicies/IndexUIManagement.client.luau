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

	-- Same fix as SettingsUIManagement.client.luau / ShopUITweens.client.luau's
	-- copies of this exact helper: find-or-create rather than a bare
	-- FindFirstChild, since every hover/press handler below tweens UIScale
	-- directly and a nil target there throws on every interaction.
	local UIScale = tweener:FindFirstChild("UIScale")
	if not UIScale then
		UIScale = Instance.new("UIScale")
		UIScale.Scale = 1
		UIScale.Parent = tweener
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
		-- Was hardcoded to 1.05, ignoring the hoverScale argument every
		-- caller actually passes (1.3 here).
		tween(UIScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {Scale = hoverScale}):Play()
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


for _, button in script.Parent:GetDescendants() do
	if button:IsA("TextButton") then
		applyButtonFeel(button, 1.3, nil, nil, button.Parent, true, THEME.Accent)

		button.MouseButton1Click:Connect(function()
			-- cosmetic "purchase" feedback only, no real transaction
			local ring = stroke(button.Parent, THEME.White, 3, 0)
			tween(ring, TweenInfo.new(0.4), {Transparency = 1}):Play()
			task.delay(0.4, function()
				if ring then ring:Destroy() end
			end)
		end)
	end
end

local PU = game:GetService("ReplicatedStorage"):WaitForChild("Cloneables"):WaitForChild("HoverPopup")
local Data = require(game.ReplicatedStorage:WaitForChild("EssenceDatas"))

local function createTooltip()
	local PUC = PU:Clone()
	return PUC
end
-- Parent the popup to the main ScreenGui so it's not trapped inside a scrolling frame
local screenGui = playerGui:WaitForChild("EssencePopupUI") -- CHANGE THIS to your Gui name
local popup = createTooltip()
popup.Parent = screenGui

-- 2. HOVER LOGIC & MOUSE TRACKING
local hoveredSlot = nil
local renderConnection = nil

-- Function to make the popup follow the mouse
local function updatePopupPosition()
	local mousePos = UserInputService:GetMouseLocation()
	-- Offset it slightly so the mouse cursor doesn't cover the popup
	popup.Position = UDim2.new(0, mousePos.X + 15, 0, mousePos.Y - 15)
end

-- 3. BIND THE SLOTS
-- Assuming your grid slots are inside a frame called "GridContainer"
local gridContainer = script.Parent -- Adjust this path to point to the frame holding your slots

for _, slot in pairs(gridContainer:GetChildren()) do
	if slot:IsA("GuiButton") or slot:IsA("Frame") then

		-- When mouse enters the slot
		slot.MouseEnter:Connect(function()
			hoveredSlot = slot

			-- Was `if slot.Name ~= "Frame" then` -- a blocklist that only
			-- excludes one specific non-essence name, rather than an
			-- allowlist of the essences this actually has data for.
			-- EssenceDatas only defines "Earth Essence"/"Shadow Essence",
			-- so any OTHER non-"Frame" child in this grid would have hit
			-- Data[slot.Name].Rarity on a nil table and errored. Checking
			-- Data[slot.Name] directly is both the real requirement and
			-- self-documenting about what a "valid slot" means here.
			if Data[slot.Name] then
				popup.Title.Text = slot.Name -- E.g., "Water Essence"

				if slot.Name == "Shadow Essence" then
					popup.Description.Text = "Rarity: ".. Data[slot.Name].Rarity.. "\n".. "Discovered: ".. tostring(player:WaitForChild(slot.Name).Value).. "\n\n".. "X^.02 Extra Essence Per Shadow Essence"
				else
					popup.Description.Text = "Rarity: ".. Data[slot.Name].Rarity.. "\n".. "Discovered: ".. tostring(player:WaitForChild(slot.Name).Value)
				end
			end
			-- Update text (You can pull this data from your ModuleScript or attributes!)
		
			-- Show popup and start following mouse
			popup.Visible = true
			if not renderConnection then
				renderConnection = RunService.RenderStepped:Connect(updatePopupPosition)
			end
		end)

		-- When mouse leaves the slot
		slot.MouseLeave:Connect(function()
			if hoveredSlot == slot then
				hoveredSlot = nil
				popup.Visible = false

				-- Stop following mouse to save performance
				if renderConnection then
					renderConnection:Disconnect()
					renderConnection = nil
				end
			end
		end)
	end
end
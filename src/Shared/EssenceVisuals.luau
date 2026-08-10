--[[
	EssenceVisuals
	===============================================================
	Applies an essence's presentation to an ImageLabel/ImageButton. Earth
	and Shadow use their uploaded art. Solar uses a detailed native-Roblox
	orb assembled from UI shapes, matching assets/solar-essence-orb.svg,
	until that SVG is uploaded and EssenceConfig receives an asset id.

	The generated art is a CanvasGroup child, so callers can fade it through
	SetTransparency exactly like an ordinary ImageTransparency tween.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EssenceConfig = require(ReplicatedStorage:WaitForChild("EssenceConfig"))

local EssenceVisuals = {}
local GENERATED_NAME = "GeneratedEssenceOrb"

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

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = radius or UDim.new(1, 0) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
	}, parent)
end

function EssenceVisuals.Clear(target)
	if not target then
		return
	end
	local existing = target:FindFirstChild(GENERATED_NAME)
	if existing then
		existing:Destroy()
	end
end

local function buildSolarOrb(target, options)
	options = options or {}
	local definition = EssenceConfig.Get("Solar Essence")
	local baseZ = options.ZIndex or target.ZIndex + 1

	local group = new("CanvasGroup", {
		Name = GENERATED_NAME,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(options.Scale or 0.96, options.Scale or 0.96),
		BackgroundTransparency = 1,
		GroupTransparency = math.clamp(options.Transparency or 0, 0, 1),
		ZIndex = baseZ,
	}, target)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, group)

	new("ImageLabel", {
		Name = "CoronaGlow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.46, 1.46),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Glow.png",
		ImageColor3 = definition.Color,
		ImageTransparency = 0.3,
		ZIndex = baseZ,
	}, group)

	local rays = new("Frame", {
		Name = "CoronaRays",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = baseZ + 1,
	}, group)
	for index = 1, 12 do
		local longRay = index % 2 == 1
		local ray = new("Frame", {
			Name = "Ray" .. index,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(longRay and 0.035 or 0.022, longRay and 0.49 or 0.43),
			Rotation = (index - 1) * 30,
			BackgroundColor3 = longRay and Color3.fromRGB(255, 222, 103) or Color3.fromRGB(255, 132, 40),
			BackgroundTransparency = longRay and 0.12 or 0.3,
			BorderSizePixel = 0,
			ZIndex = baseZ + 1,
		}, rays)
		corner(ray, UDim.new(1, 0))
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.45, 0.18),
				NumberSequenceKeypoint.new(1, 0),
			}),
		}, ray)
	end

	local outerShell = new("Frame", {
		Name = "OuterShell",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.76, 0.76),
		BackgroundColor3 = definition.DeepColor,
		BorderSizePixel = 0,
		ZIndex = baseZ + 2,
	}, group)
	corner(outerShell)
	stroke(outerShell, Color3.fromRGB(255, 237, 157), 2.2, 0.04)
	new("UIGradient", {
		Rotation = 38,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(109, 26, 19)),
			ColorSequenceKeypoint.new(0.28, Color3.fromRGB(244, 80, 24)),
			ColorSequenceKeypoint.new(0.64, Color3.fromRGB(255, 197, 47)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 244, 180)),
		}),
	}, outerShell)

	local middleCore = new("Frame", {
		Name = "MoltenCore",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.73, 0.73),
		BackgroundColor3 = Color3.fromRGB(255, 167, 37),
		BorderSizePixel = 0,
		ZIndex = baseZ + 3,
	}, outerShell)
	corner(middleCore)
	new("UIGradient", {
		Rotation = 132,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 196)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 211, 76)),
			ColorSequenceKeypoint.new(0.72, Color3.fromRGB(255, 111, 28)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(136, 31, 20)),
		}),
	}, middleCore)

	for index, ringSize in ipairs({ 0.84, 0.61, 0.39 }) do
		local ring = new("Frame", {
			Name = "PlasmaRing" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ringSize, ringSize),
			Rotation = index * 37,
			BackgroundTransparency = 1,
			ZIndex = baseZ + 4,
		}, middleCore)
		corner(ring)
		local ringStroke = stroke(ring, index == 2 and Color3.fromRGB(255, 117, 35) or Color3.fromRGB(255, 245, 181), 1.4, 0.24 + index * 0.12)
		new("UIGradient", {
			Rotation = index * 61,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.04),
				NumberSequenceKeypoint.new(0.45, 0.8),
				NumberSequenceKeypoint.new(1, 0.12),
			}),
		}, ringStroke)
	end

	local starCore = new("TextLabel", {
		Name = "StarCore",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.34, 0.34),
		BackgroundColor3 = Color3.fromRGB(255, 248, 204),
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBlack,
		Text = "✦",
		TextColor3 = Color3.fromRGB(255, 157, 36),
		TextScaled = true,
		TextStrokeColor3 = Color3.fromRGB(255, 244, 181),
		TextStrokeTransparency = 0.24,
		ZIndex = baseZ + 6,
	}, middleCore)
	corner(starCore)
	new("UITextSizeConstraint", { MinTextSize = 8, MaxTextSize = 56 }, starCore)

	local highlight = new("Frame", {
		Name = "Highlight",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.34, 0.29),
		Size = UDim2.fromScale(0.18, 0.1),
		Rotation = -28,
		BackgroundColor3 = Color3.fromRGB(255, 255, 240),
		BackgroundTransparency = 0.16,
		BorderSizePixel = 0,
		ZIndex = baseZ + 7,
	}, outerShell)
	corner(highlight)

	return group
end

function EssenceVisuals.ApplyToImage(target, essenceValue, options)
	if not target or not (target:IsA("ImageLabel") or target:IsA("ImageButton")) then
		return nil
	end

	EssenceVisuals.Clear(target)
	local definition = EssenceConfig.Get(essenceValue)
	if not definition then
		return nil
	end

	if definition.IconImage ~= "" then
		target.Image = definition.IconImage
		return nil
	end

	target.Image = ""
	return buildSolarOrb(target, options)
end

function EssenceVisuals.SetTransparency(target, transparency)
	if not target then
		return
	end
	local value = math.clamp(tonumber(transparency) or 0, 0, 1)
	if target:IsA("ImageLabel") or target:IsA("ImageButton") then
		target.ImageTransparency = value
	end
	local generated = target:FindFirstChild(GENERATED_NAME)
	if generated and generated:IsA("CanvasGroup") then
		generated.GroupTransparency = value
	end
end

return EssenceVisuals

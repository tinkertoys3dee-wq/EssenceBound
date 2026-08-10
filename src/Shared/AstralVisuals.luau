--[[
	AstralVisuals
	===============================================================
	A client presentation toolkit shared by EssenceBound's authored and
	code-built interfaces. It adds depth, animated trim, readable hierarchy
	and tactile feedback without changing the layout or gameplay contract of
	the object it decorates.

	The legacy PopupHolder and MainGui live primarily in Studio rather than
	in this repository, so a runtime toolkit is the only safe way to give
	those real instances the same finish as the Prophecy Crystal and Fortune
	Wheel without replacing their authored positions and content.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AstralVisuals = {}

AstralVisuals.Theme = {
	Void = Color3.fromRGB(6, 5, 16),
	Background = Color3.fromRGB(18, 13, 34),
	Surface = Color3.fromRGB(35, 26, 55),
	SurfaceRaised = Color3.fromRGB(49, 36, 72),
	SurfaceDeep = Color3.fromRGB(12, 10, 27),
	White = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(185, 174, 205),
	Dim = Color3.fromRGB(126, 111, 150),
	Gold = Color3.fromRGB(255, 187, 66),
	GoldLight = Color3.fromRGB(255, 232, 159),
	Orange = Color3.fromRGB(255, 120, 54),
	Green = Color3.fromRGB(76, 226, 148),
	Cyan = Color3.fromRGB(79, 217, 255),
	Blue = Color3.fromRGB(92, 144, 255),
	Purple = Color3.fromRGB(185, 105, 255),
	Pink = Color3.fromRGB(255, 103, 185),
	Red = Color3.fromRGB(246, 92, 105),
}

local T = AstralVisuals.Theme

local ACCENT_RULES = {
	{ "upgrade", Color3.fromRGB(125, 205, 255) },
	{ "achievement", Color3.fromRGB(255, 201, 87) },
	{ "leader", Color3.fromRGB(88, 219, 255) },
	{ "rank", Color3.fromRGB(88, 219, 255) },
	{ "rebirth", Color3.fromRGB(255, 104, 118) },
	{ "prestige", Color3.fromRGB(255, 112, 93) },
	{ "sanctum", Color3.fromRGB(193, 112, 255) },
	{ "zone", Color3.fromRGB(91, 190, 255) },
	{ "quest", Color3.fromRGB(132, 225, 160) },
	{ "daily", Color3.fromRGB(255, 190, 70) },
	{ "code", Color3.fromRGB(94, 226, 210) },
	{ "shop", Color3.fromRGB(89, 226, 147) },
	{ "market", Color3.fromRGB(89, 226, 147) },
	{ "inventory", Color3.fromRGB(125, 183, 255) },
	{ "index", Color3.fromRGB(180, 126, 255) },
	{ "setting", Color3.fromRGB(112, 201, 223) },
	{ "friend", Color3.fromRGB(86, 220, 156) },
	{ "luck", Color3.fromRGB(141, 235, 99) },
	{ "potion", Color3.fromRGB(185, 112, 255) },
	{ "hammer", Color3.fromRGB(255, 139, 70) },
	{ "gravity", Color3.fromRGB(187, 108, 255) },
	{ "laser", Color3.fromRGB(82, 218, 255) },
	{ "eclipse", Color3.fromRGB(168, 98, 255) },
	{ "rush", Color3.fromRGB(255, 139, 62) },
	{ "discovery", Color3.fromRGB(187, 111, 255) },
	{ "offline", Color3.fromRGB(93, 218, 255) },
	{ "tutorial", Color3.fromRGB(255, 188, 75) },
	{ "hollow", Color3.fromRGB(219, 76, 94) },
	{ "reward", Color3.fromRGB(255, 191, 73) },
}

local BRANCH_ACCENTS = {
	Core = Color3.fromRGB(112, 211, 255),
	OrbCore = Color3.fromRGB(255, 154, 78),
	Collection = Color3.fromRGB(244, 209, 92),
	Critical = Color3.fromRGB(240, 92, 105),
	Criticals = Color3.fromRGB(240, 92, 105),
	Storm = Color3.fromRGB(225, 104, 208),
	Rebirth = Color3.fromRGB(87, 191, 230),
	Passive = Color3.fromRGB(75, 215, 183),
	Auto = Color3.fromRGB(75, 215, 183),
	Capstone = Color3.fromRGB(255, 205, 75),
	Ultimate = Color3.fromRGB(255, 205, 75),
}

local animatedGradients = {}
local rotatingObjects = {}
local pulsingObjects = {}
local elapsed = 0
local animationAccumulator = 0

local function alive(instance)
	return instance ~= nil and instance.Parent ~= nil
end

local function visibleInHierarchy(instance)
	local cursor = instance
	while cursor do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end
		if cursor:IsA("ScreenGui") and not cursor.Enabled then
			return false
		end
		cursor = cursor.Parent
	end
	return true
end

if RunService:IsClient() then
	RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		animationAccumulator += dt
		if animationAccumulator < (1 / 30) then
			return
		end
		local animationStep = animationAccumulator
		animationAccumulator = 0

		for index = #animatedGradients, 1, -1 do
			local item = animatedGradients[index]
			if not alive(item.Object) then
				table.remove(animatedGradients, index)
			elseif visibleInHierarchy(item.Object) then
				item.Object.Rotation = (item.Object.Rotation + animationStep * item.Speed) % 360
			end
		end

		for index = #rotatingObjects, 1, -1 do
			local item = rotatingObjects[index]
			if not alive(item.Object) then
				table.remove(rotatingObjects, index)
			elseif visibleInHierarchy(item.Object) then
				local speed = tonumber(item.Object:GetAttribute("AstralRotationSpeed")) or item.Speed
				item.Object.Rotation = (item.Object.Rotation + animationStep * speed) % 360
			end
		end

		for index = #pulsingObjects, 1, -1 do
			local item = pulsingObjects[index]
			if not alive(item.Object) then
				table.remove(pulsingObjects, index)
			elseif visibleInHierarchy(item.Object) then
				local enabled = item.Object:GetAttribute("AstralPulseEnabled") ~= false
				local wave = (math.sin(elapsed * item.Speed + item.Phase) + 1) * 0.5
				local value = enabled and (item.Min + (item.Max - item.Min) * wave) or item.Disabled
				item.Object[item.Property] = value
			end
		end
	end)
end

local function registerGradient(gradient, speed)
	if gradient:GetAttribute("AstralAnimated") then
		return
	end
	gradient:SetAttribute("AstralAnimated", true)
	table.insert(animatedGradients, { Object = gradient, Speed = speed or 8 })
end

local function registerRotation(object, speed)
	if object:GetAttribute("AstralRotator") then
		return
	end
	object:SetAttribute("AstralRotator", true)
	object:SetAttribute("AstralRotationSpeed", speed or 12)
	table.insert(rotatingObjects, { Object = object, Speed = speed or 12 })
end

local function registerPulse(object, property, minimum, maximum, speed, disabled)
	if object:GetAttribute("AstralPulser") then
		return
	end
	object:SetAttribute("AstralPulser", true)
	object:SetAttribute("AstralPulseEnabled", true)
	table.insert(pulsingObjects, {
		Object = object,
		Property = property,
		Min = minimum,
		Max = maximum,
		Speed = speed or 2,
		Phase = math.random() * math.pi * 2,
		Disabled = disabled or maximum,
	})
end

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	if parent then
		object.Parent = parent
	end
	return object
end

function AstralVisuals.GetAccent(name, fallback)
	local normalized = string.lower(tostring(name or ""))
	for _, rule in ipairs(ACCENT_RULES) do
		if string.find(normalized, rule[1], 1, true) then
			return rule[2]
		end
	end
	return fallback or T.Gold
end

function AstralVisuals.GetBranchAccent(branch)
	return BRANCH_ACCENTS[tostring(branch)] or AstralVisuals.GetAccent(branch, T.Cyan)
end

function AstralVisuals.EnsureCorner(target, radius)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	local existing = target:FindFirstChildWhichIsA("UICorner")
	if existing then
		return existing
	end
	return make("UICorner", {
		Name = "AstralCorner",
		CornerRadius = radius or UDim.new(0.08, 0),
	}, target)
end

function AstralVisuals.EnsurePadding(target, horizontal, vertical)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	local existing = target:FindFirstChildWhichIsA("UIPadding")
	if existing then
		return existing
	end
	horizontal = horizontal or UDim.new(0.04, 0)
	vertical = vertical or UDim.new(0.035, 0)
	return make("UIPadding", {
		Name = "AstralPadding",
		PaddingLeft = horizontal,
		PaddingRight = horizontal,
		PaddingTop = vertical,
		PaddingBottom = vertical,
	}, target)
end

function AstralVisuals.EnsureStroke(target, accent, options)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	options = options or {}
	accent = accent or T.Gold

	local existing = target:FindFirstChild("AstralStroke")
	if not existing then
		for _, child in ipairs(target:GetChildren()) do
			if child:IsA("UIStroke") and child.Name ~= "HoverHighlight" then
				existing = child
				break
			end
		end
	end

	local uiStroke = existing or make("UIStroke", { Name = "AstralStroke" }, target)
	uiStroke.Color = accent
	uiStroke.Thickness = math.max(uiStroke.Thickness, options.Thickness or 1.5)
	if options.Transparency ~= nil then
		-- Never make an authored border weaker just because the shared
		-- fallback for newly-created trim is subtle. Callers may strengthen
		-- an existing stroke; only Astral-owned strokes start at the fallback.
		uiStroke.Transparency = existing and math.min(uiStroke.Transparency, options.Transparency)
			or options.Transparency
	elseif not existing then
		uiStroke.Transparency = 0.18
	end
	uiStroke.LineJoinMode = Enum.LineJoinMode.Round

	-- Respect an authored stroke gradient. Roblox only has one meaningful
	-- gradient modifier per stroke; adding a second one can produce an
	-- order-dependent result, so existing art always wins here.
	local flow = uiStroke:FindFirstChild("AstralFlow") or uiStroke:FindFirstChildWhichIsA("UIGradient")
	if not flow then
		flow = make("UIGradient", {
			Name = "AstralFlow",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, accent:Lerp(T.White, 0.42)),
				ColorSequenceKeypoint.new(0.35, accent),
				ColorSequenceKeypoint.new(0.7, accent:Lerp(T.Cyan, 0.3)),
				ColorSequenceKeypoint.new(1, accent:Lerp(T.White, 0.42)),
			}),
			Rotation = 12,
		}, uiStroke)
		registerGradient(flow, options.FlowSpeed or 7)
	end

	return uiStroke
end

function AstralVisuals.EnsureSurfaceGradient(target, accent, options)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	options = options or {}
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("UIGradient") then
			return child
		end
	end

	accent = accent or T.Gold
	local topColor = options.TopColor or T.SurfaceRaised:Lerp(accent, 0.1)
	local middleColor = options.MiddleColor or T.Surface
	local bottomColor = options.BottomColor or T.SurfaceDeep
	return make("UIGradient", {
		Name = "AstralSurfaceGradient",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, topColor),
			ColorSequenceKeypoint.new(0.46, middleColor),
			ColorSequenceKeypoint.new(1, bottomColor),
		}),
		Rotation = options.Rotation or 112,
	}, target)
end

function AstralVisuals.AddHalo(target, accent)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	local existingLink = target:FindFirstChild("AstralHaloLink")
	if existingLink and existingLink:IsA("ObjectValue") and alive(existingLink.Value) then
		return existingLink.Value
	end

	local haloParent = target.Parent
	local parentHasLayout = haloParent and haloParent:FindFirstChildWhichIsA("UIBaseLayout") ~= nil
	if not haloParent or parentHasLayout then
		haloParent = target
	end
	local halo = make("ImageLabel", {
		Name = "AstralHalo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/Glow.png",
		ImageColor3 = accent or T.Gold,
		ImageTransparency = 0.87,
		Active = false,
		ZIndex = math.max(0, target.ZIndex - 1),
	}, haloParent)

	make("ObjectValue", {
		Name = "AstralHaloLink",
		Value = halo,
	}, target)

	local function syncHalo()
		if not alive(target) or not alive(halo) then
			return
		end
		if haloParent == target then
			halo.Position = UDim2.fromScale(0.5, 0.51)
			halo.Size = UDim2.fromScale(1.16, 1.2)
			halo.Visible = true
		else
			local centerX = 0.5 - target.AnchorPoint.X
			local centerY = 0.5 - target.AnchorPoint.Y
			halo.Position = UDim2.new(
				target.Position.X.Scale + target.Size.X.Scale * centerX,
				target.Position.X.Offset + target.Size.X.Offset * centerX,
				target.Position.Y.Scale + target.Size.Y.Scale * centerY + 0.008,
				target.Position.Y.Offset + target.Size.Y.Offset * centerY
			)
			halo.Size = UDim2.new(
				target.Size.X.Scale * 1.16,
				target.Size.X.Offset * 1.16,
				target.Size.Y.Scale * 1.2,
				target.Size.Y.Offset * 1.2
			)
			halo.Rotation = target.Rotation
			halo.Visible = target.Visible
		end
	end

	if haloParent ~= target then
		for _, property in ipairs({ "Position", "Size", "AnchorPoint", "Rotation", "Visible" }) do
			target:GetPropertyChangedSignal(property):Connect(syncHalo)
		end
		target.AncestryChanged:Connect(function(_, parent)
			if parent == nil and alive(halo) then
				halo:Destroy()
			end
		end)
	end
	syncHalo()
	registerPulse(halo, "ImageTransparency", 0.82, 0.91, 1.5, 0.91)
	return halo
end

function AstralVisuals.AddRail(target, accent)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	local existing = target:FindFirstChild("AstralTopRail")
	if existing then
		return existing
	end

	local rail = make("Frame", {
		Name = "AstralTopRail",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.008),
		Size = UDim2.fromScale(0.82, 0.012),
		BackgroundColor3 = accent or T.Gold,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Active = false,
		ZIndex = target.ZIndex + 2,
	}, target)
	AstralVisuals.EnsureCorner(rail, UDim.new(1, 0))
	make("UIGradient", {
		Name = "Fade",
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.35),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.82, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, rail)
	return rail
end

local STAR_POINTS = {
	{ 0.035, 0.18, "✦" }, { 0.12, 0.83, "·" }, { 0.26, 0.08, "✧" },
	{ 0.43, 0.93, "·" }, { 0.61, 0.055, "·" }, { 0.76, 0.9, "✦" },
	{ 0.91, 0.2, "✧" }, { 0.965, 0.69, "·" }, { 0.51, 0.13, "✦" },
	{ 0.18, 0.54, "·" }, { 0.84, 0.49, "·" }, { 0.67, 0.72, "✧" },
}

function AstralVisuals.AddStarfield(target, accent, count)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	local existing = target:FindFirstChild("AstralStarfield")
	if existing then
		return existing
	end

	local field = make("Frame", {
		Name = "AstralStarfield",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = target.ZIndex + 1,
	}, target)
	for index = 1, math.min(count or 7, #STAR_POINTS) do
		local point = STAR_POINTS[index]
		local star = make("TextLabel", {
			Name = "Star" .. index,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(point[1], point[2]),
			Size = UDim2.fromScale(0.03, 0.045),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = point[3],
			TextColor3 = index % 2 == 0 and T.Cyan or (accent or T.GoldLight),
			TextTransparency = 0.75,
			TextScaled = true,
			Active = false,
			ZIndex = target.ZIndex + 1,
		}, field)
		registerPulse(star, "TextTransparency", 0.6, 0.9, 0.7 + index * 0.1, 0.9)
	end
	return field
end

function AstralVisuals.AddCornerGlyphs(target, accent)
	if not target or not target:IsA("GuiObject") or target:FindFirstChild("AstralCornerGlyphs") then
		return
	end
	local holder = make("Frame", {
		Name = "AstralCornerGlyphs",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Active = false,
		ZIndex = target.ZIndex + 2,
	}, target)
	for _, side in ipairs({ 0, 1 }) do
		make("TextLabel", {
			Name = side == 0 and "Left" or "Right",
			AnchorPoint = Vector2.new(side, 0),
			Position = UDim2.fromScale(side == 0 and 0.018 or 0.982, 0.018),
			Size = UDim2.fromScale(0.035, 0.05),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = side == 0 and "⌜" or "⌝",
			TextColor3 = accent or T.Gold,
			TextTransparency = 0.42,
			TextScaled = true,
			Active = false,
			ZIndex = target.ZIndex + 2,
		}, holder)
	end
end

function AstralVisuals.AddRevealSweep(target, accent)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	local existing = target:FindFirstChild("AstralRevealSweep")
	if existing then
		return existing
	end

	local sweep = make("Frame", {
		Name = "AstralRevealSweep",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(-0.2, 0.5),
		Size = UDim2.fromScale(0.12, 1.35),
		BackgroundColor3 = accent or T.GoldLight,
		BackgroundTransparency = 0.93,
		BorderSizePixel = 0,
		Rotation = 14,
		Visible = false,
		Active = false,
		ZIndex = target.ZIndex + 2,
	}, target)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sweep)

	local revealToken = 0
	local function play()
		if not target.Visible or not alive(sweep) then
			return
		end
		revealToken += 1
		local token = revealToken
		sweep.Visible = true
		sweep.Position = UDim2.fromScale(-0.2, 0.5)
		local motion = TweenService:Create(sweep, TweenInfo.new(0.72, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.fromScale(1.2, 0.5),
		})
		motion:Play()
		motion.Completed:Connect(function()
			if alive(sweep) and token == revealToken then
				sweep.Visible = false
			end
		end)
	end

	target:GetPropertyChangedSignal("Visible"):Connect(function()
		if target.Visible then
			play()
		else
			revealToken += 1
			sweep.Visible = false
		end
	end)
	if target.Visible then
		task.defer(play)
	end
	return sweep
end

function AstralVisuals.ApplyModal(target, options)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	options = options or {}
	local accent = options.Accent or AstralVisuals.GetAccent(target.Name)

	if not target:GetAttribute("AstralModalStyled") then
		target:SetAttribute("AstralModalStyled", true)
		target.BorderSizePixel = 0
		if options.Recolor then
			target.BackgroundColor3 = options.BackgroundColor or T.Background
		end
		AstralVisuals.EnsureCorner(target, options.CornerRadius or UDim.new(0.045, 0))
		AstralVisuals.EnsureStroke(target, accent, {
			Thickness = options.Thickness or 2.5,
			Transparency = options.StrokeTransparency or 0.08,
			FlowSpeed = options.FlowSpeed or 6,
		})
		if target.BackgroundTransparency < 0.98 then
			AstralVisuals.EnsureSurfaceGradient(target, accent, options)
		end
		if options.Padding then
			AstralVisuals.EnsurePadding(target, options.Padding, options.VerticalPadding)
		end
		if options.Halo ~= false and not target.ClipsDescendants then
			AstralVisuals.AddHalo(target, accent)
		end
		AstralVisuals.AddRail(target, accent)
		AstralVisuals.AddCornerGlyphs(target, accent)
		if options.Sweep ~= false then
			AstralVisuals.AddRevealSweep(target, accent)
		end
		if options.Stars ~= false then
			AstralVisuals.AddStarfield(target, accent, options.StarCount or 7)
		end
	end

	return target
end

function AstralVisuals.StyleCard(target, accent, options)
	if not target or not target:IsA("GuiObject") then
		return nil
	end
	options = options or {}
	accent = accent or AstralVisuals.GetAccent(target.Name, T.Cyan)
	if target:GetAttribute("AstralCardStyled") then
		return target
	end
	target:SetAttribute("AstralCardStyled", true)
	target.BorderSizePixel = 0
	AstralVisuals.EnsureCorner(target, options.CornerRadius or UDim.new(0.12, 0))
	AstralVisuals.EnsureStroke(target, accent, {
		Thickness = options.Thickness or 1.25,
		Transparency = options.Transparency or 0.48,
		FlowSpeed = options.FlowSpeed or 4,
	})
	if target.BackgroundTransparency < 0.97 and options.Gradient ~= false then
		AstralVisuals.EnsureSurfaceGradient(target, accent, {
			TopColor = target.BackgroundColor3:Lerp(accent, 0.08),
			MiddleColor = target.BackgroundColor3,
			BottomColor = target.BackgroundColor3:Lerp(T.Void, 0.28),
			Rotation = options.Rotation or 118,
		})
	end
	if options.Padding then
		AstralVisuals.EnsurePadding(target, options.Padding, options.VerticalPadding)
	end
	return target
end

local function runSheen(sheen)
	if not alive(sheen) or sheen:GetAttribute("AstralSheenRunning") then
		return
	end
	sheen:SetAttribute("AstralSheenRunning", true)
	sheen.Position = UDim2.fromScale(-0.18, 0.5)
	local motion = TweenService:Create(sheen, TweenInfo.new(0.48, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(1.18, 0.5),
	})
	motion:Play()
	motion.Completed:Connect(function()
		if alive(sheen) then
			sheen:SetAttribute("AstralSheenRunning", nil)
		end
	end)
end

function AstralVisuals.StyleButton(button, accent, options)
	if not button or not button:IsA("GuiButton") then
		return nil
	end
	options = options or {}
	accent = accent or AstralVisuals.GetAccent(button.Name, T.Gold)
	if button:GetAttribute("AstralButtonStyled") then
		return button
	end
	button:SetAttribute("AstralButtonStyled", true)

	local surface = options.Surface
	if not surface or not surface:IsA("GuiObject") then
		surface = button
	end
	AstralVisuals.StyleCard(surface, accent, {
		CornerRadius = options.CornerRadius or UDim.new(0.2, 0),
		Thickness = options.Thickness or 1.5,
		Transparency = options.Transparency or 0.32,
		Gradient = options.Gradient ~= false,
	})
	local uiStroke = AstralVisuals.EnsureStroke(surface, accent, {
		Thickness = options.Thickness or 1.5,
		Transparency = options.Transparency or 0.32,
	})
	local restingStrokeTransparency = uiStroke.Transparency
	local restingStrokeThickness = uiStroke.Thickness

	local sheen = surface:FindFirstChild("AstralSheen")
	if not sheen and surface.BackgroundTransparency < 0.98 then
		sheen = make("Frame", {
			Name = "AstralSheen",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(-0.18, 0.5),
			Size = UDim2.fromScale(0.16, 1.5),
			BackgroundColor3 = T.White,
			BackgroundTransparency = 0.91,
			BorderSizePixel = 0,
			Rotation = 18,
			Active = false,
			ZIndex = surface.ZIndex + 1,
		}, surface)
		make("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, sheen)
	end

	button.MouseEnter:Connect(function()
		if alive(uiStroke) then
			TweenService:Create(uiStroke, TweenInfo.new(0.16), {
				Transparency = 0.02,
				Thickness = restingStrokeThickness + 0.8,
			}):Play()
		end
		if sheen then
			runSheen(sheen)
		end
	end)
	button.MouseLeave:Connect(function()
		if alive(uiStroke) then
			TweenService:Create(uiStroke, TweenInfo.new(0.18), {
				Transparency = restingStrokeTransparency,
				Thickness = restingStrokeThickness,
			}):Play()
		end
	end)
	button.Activated:Connect(function()
		if sheen then
			runSheen(sheen)
		end
		if alive(surface) then
			local ring = make("Frame", {
				Name = "AstralPressRing",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.1, 0.1),
				BackgroundTransparency = 1,
				Active = false,
				ZIndex = surface.ZIndex + 3,
			}, surface)
			AstralVisuals.EnsureCorner(ring, UDim.new(1, 0))
			local ringStroke = AstralVisuals.EnsureStroke(ring, accent, {
				Thickness = 2,
				Transparency = 0.08,
			})
			TweenService:Create(ring, TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = UDim2.fromScale(1.35, 1.35),
			}):Play()
			local fade = TweenService:Create(ringStroke, TweenInfo.new(0.38), { Transparency = 1 })
			fade:Play()
			fade.Completed:Connect(function()
				ring:Destroy()
			end)
		end
	end)

	return button
end

function AstralVisuals.StyleFill(fill, accent)
	if not fill or not fill:IsA("GuiObject") or fill:GetAttribute("AstralFillStyled") then
		return fill
	end
	fill:SetAttribute("AstralFillStyled", true)
	accent = accent or T.Green
	fill.BorderSizePixel = 0
	AstralVisuals.EnsureCorner(fill, UDim.new(1, 0))
	if not fill:FindFirstChildWhichIsA("UIGradient") then
		local gradient = make("UIGradient", {
			Name = "AstralFillFlow",
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, accent:Lerp(T.White, 0.24)),
				ColorSequenceKeypoint.new(0.45, accent),
				ColorSequenceKeypoint.new(1, accent:Lerp(T.Cyan, 0.34)),
			}),
			Rotation = 0,
		}, fill)
		registerGradient(gradient, 12)
	end
	return fill
end

function AstralVisuals.StyleHeading(label, accent, options)
	if not label or not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return nil
	end
	if label:GetAttribute("AstralHeadingStyled") then
		return label
	end
	label:SetAttribute("AstralHeadingStyled", true)
	options = options or {}
	accent = accent or T.Gold

	-- A restrained colored shadow gives headings the engraved/luminous
	-- finish used by the premium panels without changing their font, size,
	-- wrapping, alignment, localization, or text color.
	label.TextStrokeColor3 = T.Void:Lerp(accent, options.AccentMix or 0.22)
	label.TextStrokeTransparency = math.min(
		label.TextStrokeTransparency,
		options.TextStrokeTransparency or 0.62
	)
	return label
end

function AstralVisuals.CreatePill(parent, name, text, accent, properties)
	properties = properties or {}
	local pill = make("Frame", {
		Name = name,
		AnchorPoint = properties.AnchorPoint or Vector2.new(0.5, 0.5),
		Position = properties.Position or UDim2.fromScale(0.5, 0.5),
		Size = properties.Size or UDim2.fromScale(0.3, 0.08),
		BackgroundColor3 = properties.BackgroundColor3 or T.SurfaceDeep,
		BackgroundTransparency = properties.BackgroundTransparency ~= nil and properties.BackgroundTransparency or 0.08,
		Active = false,
		ZIndex = properties.ZIndex or 100,
	}, parent)
	AstralVisuals.StyleCard(pill, accent, {
		CornerRadius = UDim.new(1, 0),
		Thickness = properties.Thickness or 1.4,
		Transparency = properties.StrokeTransparency or 0.25,
	})
	local label = make("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(0.9, 0.72),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = properties.Font or Enum.Font.GothamBlack,
		Text = text or "",
		TextColor3 = properties.TextColor3 or T.White,
		TextScaled = true,
		Active = false,
		ZIndex = (properties.ZIndex or 100) + 1,
	}, pill)
	make("UITextSizeConstraint", {
		MinTextSize = properties.MinTextSize or 7,
		MaxTextSize = properties.MaxTextSize or 14,
	}, label)
	return pill, label
end

function AstralVisuals.StyleUpgradeNode(node, state)
	if not node or not node:IsA("GuiObject") then
		return nil
	end
	state = state or {}
	local accent = state.Accent or T.Cyan

	local glow = node:FindFirstChild("AstralNodeGlow")
	if not glow then
		glow = make("ImageLabel", {
			Name = "AstralNodeGlow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.75, 1.75),
			BackgroundTransparency = 1,
			Image = "rbxasset://textures/particles/smoke_main.dds",
			ImageColor3 = accent,
			ImageTransparency = 0.92,
			Active = false,
			ZIndex = math.max(0, node.ZIndex - 2),
		}, node)
		registerPulse(glow, "ImageTransparency", 0.72, 0.9, 2.4, 0.96)
	end

	local orbit = node:FindFirstChild("AstralNodeOrbit")
	if not orbit then
		orbit = make("ImageLabel", {
			Name = "AstralNodeOrbit",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.32, 1.32),
			BackgroundTransparency = 1,
			Image = "rbxassetid://91692624575395",
			ImageColor3 = accent,
			ImageTransparency = 0.4,
			Active = false,
			ZIndex = math.max(0, node.ZIndex - 1),
		}, node)
		registerRotation(orbit, 9)
	end

	local badge = node:FindFirstChild("AstralNodeState")
	if not badge then
		badge = make("TextLabel", {
			Name = "AstralNodeState",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1.02, -0.02),
			Size = UDim2.fromScale(0.32, 0.32),
			BackgroundColor3 = accent,
			Font = Enum.Font.GothamBlack,
			Text = "+",
			TextColor3 = T.Void,
			TextScaled = true,
			Active = false,
			ZIndex = node.ZIndex + 6,
		}, node)
		AstralVisuals.EnsureCorner(badge, UDim.new(1, 0))
		AstralVisuals.EnsureStroke(badge, T.White, { Thickness = 1.3, Transparency = 0.14 })
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, badge)
		make("UITextSizeConstraint", { MinTextSize = 6, MaxTextSize = 15 }, badge)
	end

	local locked = state.Locked == true
	local buyable = state.Buyable == true and not locked
	local maxed = state.Maxed == true
	local tier = math.max(0, math.floor(tonumber(state.Tier) or 0))
	local displayColor = locked and T.Dim or (maxed and T.GoldLight or accent)

	glow.ImageColor3 = displayColor
	glow:SetAttribute("AstralPulseEnabled", buyable)
	orbit.ImageColor3 = displayColor
	orbit.ImageTransparency = locked and 0.78 or (buyable and 0.12 or 0.42)
	orbit:SetAttribute("AstralRotationSpeed", buyable and 24 or (maxed and 14 or 7))
	badge.BackgroundColor3 = displayColor
	badge.Text = locked and "×" or (maxed and "★" or (buyable and "+" or tostring(tier)))
	badge.TextColor3 = locked and T.White or T.Void
	badge.Visible = locked or buyable or tier > 0 or maxed

	if not node:GetAttribute("AstralNodeHoverBound") then
		node:SetAttribute("AstralNodeHoverBound", true)
		node.MouseEnter:Connect(function()
			if alive(orbit) then
				TweenService:Create(orbit, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(1.5, 1.5),
					ImageTransparency = math.min(orbit.ImageTransparency, 0.08),
				}):Play()
			end
		end)
		node.MouseLeave:Connect(function()
			if alive(orbit) then
				TweenService:Create(orbit, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.fromScale(1.32, 1.32),
					ImageTransparency = node:GetAttribute("Buyable") and 0.12 or (node:GetAttribute("Unlocked") == false and 0.78 or 0.42),
				}):Play()
			end
		end)
	end

	return {
		Glow = glow,
		Orbit = orbit,
		Badge = badge,
	}
end

return AstralVisuals

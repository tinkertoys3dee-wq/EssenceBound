local player = game.Players.LocalPlayer

local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainGui")
local Left = gui:WaitForChild("Left")
local currencys = Left:WaitForChild("Currencys"):WaitForChild("ScrollingFrame")
local RP = game:GetService("ReplicatedStorage")
local EssenceConfig = require(RP:WaitForChild("EssenceConfig"))
local EssenceVisuals = require(RP:WaitForChild("EssenceVisuals"))
local PlayerStats = Left:WaitForChild("Playerstats")


local RarestEssence = PlayerStats:WaitForChild("RarestEssence")
local RarestEssenceText = RarestEssence:WaitForChild("Upgrade Name")

local Rebirths = PlayerStats:WaitForChild("Rebirths")
local RebirthsText = Rebirths:WaitForChild("Upgrade Name")

local EssenceGathered = PlayerStats:WaitForChild("EssenceGathered")
local EssenceGatheredText = EssenceGathered:WaitForChild("Upgrade Name")

local RobuxSpent = PlayerStats:WaitForChild("RobuxSpent")
local RobuxSpentText = RobuxSpent:WaitForChild("Upgrade Name")

local CriticalEssence = PlayerStats:WaitForChild("CriticalEssence")
local CriticalEssenceText = CriticalEssence:WaitForChild("Upgrade Name")

local PlayTime = PlayerStats:WaitForChild("PlayTime")
local PlayTimeText = PlayTime:WaitForChild("Upgrade Name")

local UniqueEssences = PlayerStats:WaitForChild("UniqueEssences")
local UniqueEssencesText = UniqueEssences:WaitForChild("Upgrade Name")

local remotes = RP:WaitForChild("Remotes")
local GetData = remotes:WaitForChild("GetData")

local data = GetData:InvokeServer()
local ABBREVIATIONS = {
	"", "K", "M", "B", "T", "Qd", "Qn", "Sx", "Sp", "Oc", "No"
}

local function formatNumber(value: number): string
	local absValue = math.abs(value)

	if absValue < 1000 then
		-- Round to an integer so floats don't print long decimal tails
		return tostring(math.floor(value + 0.5))
	end

	-- Calculate which abbreviation bucket the number falls into
	local index = math.floor(math.log10(absValue) / 3)
	if index >= #ABBREVIATIONS then
		index = #ABBREVIATIONS - 1
	end

	-- Divide the number down to its abbreviated form (keep the decimal!)
	local shortValue = value / (10 ^ (index * 3))

	-- Format to 2 decimal places (e.g., 1.25M), then trim trailing zeros
	local formatted = string.format("%.2f", shortValue)
	formatted = string.gsub(formatted, "%.?0+$", "")

	return formatted .. ABBREVIATIONS[index + 1]
end

local SessionStartTime = os.clock()

local essenceGui =  player:WaitForChild("PlayerGui"):WaitForChild("EssencePopupUI"):WaitForChild("PopupHolder"):WaitForChild("IndexPopup"):WaitForChild("Content")

local indexes = essenceGui:WaitForChild("Indicies")
local Bar = essenceGui:WaitForChild("Frame")
local Progress = Bar:WaitForChild("TextLabel")
local PBar =  Bar:WaitForChild("Frame"):WaitForChild("Frame")

local function UpdateRobuxSpent()
	-- The server mirrors this attribute immediately after a successful
	-- receipt. Fall back to the periodic data snapshot for older servers.
	local liveAmount = player:GetAttribute("RobuxSpent")
	if liveAmount == nil then
		liveAmount = data.RobuxSpent
	end
	RobuxSpentText.Text = "Robux Spent : " .. tostring(math.max(0, tonumber(liveAmount) or 0))
end

local function UpdateStats()
	local discovered = 0
	local total = 0
	PlayTimeText.Text = "Play Time: "..math.floor(data.PlayTime + (os.clock() - SessionStartTime)).."s"
	RarestEssenceText.Text = "Rarest Essence : "..data.RarestEssence
	RebirthsText.Text = "Rebirths : "..data.Rebirths
	EssenceGatheredText.Text = "Essence Gathered : "..formatNumber(data.TotalEssenceGathered)
	UpdateRobuxSpent()
	CriticalEssenceText.Text = "Critical Essence : "..formatNumber(data.CriticalEssence)
	UniqueEssencesText.Text = "Unique Essences : "..data.UniqueEssences
	
	
	for essence, dict in pairs(data.Essences) do
		total += 1
		if dict.Discovered  then
			discovered += 1
		end
		for index, frame in pairs(indexes:GetChildren()) do
			if frame:IsA("Frame") then
				if frame.Name == dict.DisplayName or essence == frame.Name then
					if 	dict.Discovered then
						frame.Visible = true 
					end
				end
			end
			
		end
	end
	PBar.Size = UDim2.new(discovered / total, 0, 1, 0)
	Progress.Text = "Discovered: " .. discovered .. " / " .. total
end

local leaderstats = player:WaitForChild("leaderstats")
local EarthEsseceleaderstat = leaderstats:WaitForChild("Earth Essence")

local EarthEssenceDisplay = currencys:WaitForChild("Green Essence")
local EarthEssenceDisplayText= EarthEssenceDisplay:WaitForChild("Value")

local ShadowEssenceleaderstat = leaderstats:WaitForChild("Shadow Essence")
local ShadowEssenceDisplay = currencys:WaitForChild("Shadow Essence")
local ShadowEssenceDisplayText= ShadowEssenceDisplay:WaitForChild("Value")

local SolarEssenceleaderstat = leaderstats:WaitForChild("Solar Essence")

-- Solar has no legacy Studio-authored row. Clone Shadow's existing row so
-- the three counters share the exact same dimensions, padding, typography,
-- and alignment; only the icon and Solar palette should differ.
local previousSolarDisplay = currencys:FindFirstChild("Solar Essence")
if previousSolarDisplay then
	previousSolarDisplay:Destroy()
end

local SolarEssenceDisplay = ShadowEssenceDisplay:Clone()
SolarEssenceDisplay.Name = "Solar Essence"
SolarEssenceDisplay.LayoutOrder = ShadowEssenceDisplay.LayoutOrder + 1
SolarEssenceDisplay:SetAttribute("AstralAccentColor", EssenceConfig.GetColor("Solar Essence"))

-- A currency row should be presentation only. If the authored template ever
-- gains a LocalScript, cloning it must not duplicate behavior or connections.
for _, descendant in ipairs(SolarEssenceDisplay:GetDescendants()) do
	if descendant:IsA("LocalScript") or descendant:IsA("Script") then
		descendant:Destroy()
	end
end

SolarEssenceDisplay.Parent = currencys
local SolarEssenceDisplayText = SolarEssenceDisplay:WaitForChild("Value")

local solarColor = EssenceConfig.GetColor("Solar Essence", Color3.fromRGB(255, 196, 64))
local solarHighlight = Color3.fromRGB(255, 235, 142)
SolarEssenceDisplayText.TextColor3 = solarColor
SolarEssenceDisplayText.TextStrokeColor3 = EssenceConfig.Get("Solar Essence").DeepColor

-- UIGradient overrides TextColor3, so recolor any gradient inherited from
-- the Shadow value instead of allowing the Solar number to remain purple.
for _, child in ipairs(SolarEssenceDisplayText:GetChildren()) do
	if child:IsA("UIGradient") then
		child.Color = ColorSequence.new(solarHighlight, solarColor)
	end
end

local function findCurrencyIcon(row)
	local bestIcon = nil
	local bestScore = -math.huge
	local shadowIconId = tostring(EssenceConfig.Get("Shadow Essence").IconAssetId)
	for _, descendant in ipairs(row:GetDescendants()) do
		if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			local lowerName = string.lower(descendant.Name)
			local score = 0
			if string.find(descendant.Image, shadowIconId, 1, true) then score += 100 end
			if string.find(lowerName, "icon", 1, true) then score += 12 end
			if string.find(lowerName, "orb", 1, true) then score += 12 end
			if string.find(lowerName, "essence", 1, true) then score += 6 end
			if descendant.Parent == row then score += 3 end
			if descendant.Image ~= "" then score += 1 end
			if score > bestScore then
				bestScore = score
				bestIcon = descendant
			end
		end
	end
	return bestIcon
end

local solarIcon = findCurrencyIcon(SolarEssenceDisplay)
if solarIcon then
	solarIcon.Name = "Solar Essence Icon"
	solarIcon.ImageColor3 = Color3.new(1, 1, 1)
	solarIcon.ImageRectOffset = Vector2.zero
	solarIcon.ImageRectSize = Vector2.zero
	solarIcon.ScaleType = Enum.ScaleType.Fit
	EssenceVisuals.ApplyToImage(solarIcon, "Solar Essence")
end

-- The authored rail was sized for two currencies. Let its existing layout
-- drive the vertical canvas so the new third row is scrollable on small
-- screens instead of being created correctly but clipped below the fold.
if currencys:FindFirstChildWhichIsA("UIListLayout") or currencys:FindFirstChildWhichIsA("UIGridLayout") then
	if currencys.AutomaticCanvasSize == Enum.AutomaticSize.None then
		currencys.AutomaticCanvasSize = Enum.AutomaticSize.Y
	elseif currencys.AutomaticCanvasSize == Enum.AutomaticSize.X then
		currencys.AutomaticCanvasSize = Enum.AutomaticSize.XY
	end
end

-- =========================================================================
-- CURRENCY DISPLAY
-- =========================================================================
-- Watching the number climb IS the reward loop in an idle game, so these
-- counters roll up to their new value and pop rather than silently
-- snapping. Purely presentational -- the authoritative value is still
-- whatever the server put on the leaderstat, and the label always lands
-- exactly on it.

local Juice = require(RP:WaitForChild("Juice"))
local juiceLayer = Juice.GetLayer(player:WaitForChild("PlayerGui"))

local GAIN_COLOR = Color3.fromRGB(140, 255, 170)
local SPEND_COLOR = Color3.fromRGB(255, 150, 150)

-- =========================================================================
-- MILESTONE CELEBRATIONS
-- =========================================================================
-- Passing 1K, then 10K, then a million is the main long-term progression
-- signal an idle game has, and it was going by completely unmarked -- the
-- number just rolled past with nothing to show a threshold had been
-- crossed. These are cosmetic only; nothing is granted.

local MILESTONES = {
	100, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14,
}

local MILESTONE_COLOR = Color3.fromRGB(255, 225, 130)

-- Highest milestone already passed. Seeded from the player's balance on
-- join WITHOUT celebrating, so a returning player with millions doesn't
-- get every threshold fired at them the moment they log in.
local function highestPassed(value)
	local passed = 0
	for _, threshold in ipairs(MILESTONES) do
		if value >= threshold then
			passed = threshold
		end
	end
	return passed
end

local function celebrateMilestone(threshold, label)
	Juice.PulseColor(label, MILESTONE_COLOR, 0.8)
	Juice.Punch(Juice.GetScale(label), 0.3, 0.5)

	if not juiceLayer then
		return
	end

	local center = Juice.CenterOf(label, juiceLayer)
	if not center then
		return
	end

	Juice.Ring(juiceLayer, center, {
		Color = MILESTONE_COLOR,
		StartSize = 40,
		EndSize = 230,
		Duration = 0.7,
		Thickness = 4,
	})

	Juice.Burst(juiceLayer, center, {
		Count = 20,
		Colors = { MILESTONE_COLOR, Color3.fromRGB(255, 255, 255), GAIN_COLOR },
		Distance = 220,
		Duration = 0.9,
		Size = { 5, 12 },
		ZIndex = 210,
	})

	Juice.FloatText(juiceLayer, center, formatNumber(threshold) .. " ESSENCE!", {
		Color = MILESTONE_COLOR,
		Duration = 1.4,
		Rise = 90,
		TextSize = 32,
	})

	local sound = Juice.FindSound("SFX/UI/UIPop")
	if sound then
		-- A short rising flourish rather than a single blip, so a milestone
		-- is audibly bigger than an ordinary collection.
		for i = 0, 2 do
			task.delay(i * 0.09, function()
				Juice.PlaySound(sound, { Pitch = 1.15 + i * 0.22, Volume = 0.5 })
			end)
		end
	end
end

-- celebrateMilestones: only the primary currency should fire these. Two
-- currencies both announcing thresholds would step on each other and
-- dilute the moment.
local function bindCurrencyDisplay(leaderstat, label, celebrateMilestones)
	local displayed = tonumber(leaderstat:GetAttribute("Quantity")) or 0
	label.Text = formatNumber(displayed)

	local labelScale = Juice.GetScale(label)
	local passedMilestone = highestPassed(displayed)

	leaderstat:GetAttributeChangedSignal("Quantity"):Connect(function()
		local target = tonumber(leaderstat:GetAttribute("Quantity")) or 0

		-- Resume from the value currently on screen, not the last target.
		-- Orbs land several times a second, so without this the counter
		-- would snap to the previous target before each new roll.
		local previous = tonumber(label:GetAttribute("JuiceCurrentValue")) or displayed
		displayed = target

		local delta = target - previous
		if delta == 0 then
			return
		end

		-- Roll the number. Bigger jumps get a slightly longer roll so a
		-- large payout feels substantial, capped so it never lags behind
		-- what the player is doing.
		local magnitude = math.abs(delta) / math.max(1, math.abs(previous))
		local duration = math.clamp(0.25 + magnitude * 0.5, 0.25, 0.8)

		Juice.CountUp(label, previous, target, {
			Duration = duration,
			Formatter = formatNumber,
		})

		if delta > 0 then
			-- A milestone crossing supersedes the ordinary gain pop, so the
			-- two don't fight over the same label's colour and scale.
			local reached = celebrateMilestones and highestPassed(target) or 0
			if reached > passedMilestone then
				passedMilestone = reached
				celebrateMilestone(reached, label)
			else
				Juice.Punch(labelScale, 0.14, 0.24)
				Juice.PulseColor(label, GAIN_COLOR, 0.4)
			end
		else
			-- Spending should read differently from earning, so a
			-- purchase is unmistakable.
			Juice.PulseColor(label, SPEND_COLOR, 0.4)
		end
	end)
end

bindCurrencyDisplay(EarthEsseceleaderstat, EarthEssenceDisplayText, true)
bindCurrencyDisplay(ShadowEssenceleaderstat, ShadowEssenceDisplayText, false)
bindCurrencyDisplay(SolarEssenceleaderstat, SolarEssenceDisplayText, false)

local UpdateTimer = Left:WaitForChild("UpdateTimer")
-- Internal refresh countdown, not something a player needs to see ("Next
-- Update: 43s" reads like debug output, not part of the game).
UpdateTimer.Visible = false

local updateValue = 60

UpdateStats()
player:GetAttributeChangedSignal("RobuxSpent"):Connect(UpdateRobuxSpent)

-- =========================================================================
-- GLOBAL BUTTON FEEL + SOUND
-- =========================================================================
-- Previously this replayed one shared Sound instance at a fixed pitch on
-- every button. Two problems: a single Sound restarts rather than layering,
-- so fast clicks cut each other off, and an identical pitch every time is
-- what makes UI audio grating within a minute. Juice.PlaySound clones per
-- play and jitters the pitch, so clicks layer and stay pleasant.
--
-- It also only ever ran once at startup, so any button created later (the
-- progression panels, dynamically built shop rows) got nothing. The
-- DescendantAdded hook below covers those too.

local clickSound = Juice.FindSound("SFX/UI/UIPop")
local playerGuiRoot = player:WaitForChild("PlayerGui")
local orbArea = gui:FindFirstChild("Center")

local function bindButton(btn)
	if not btn:IsA("GuiButton") then
		return
	end

	-- The great orb runs its own richer, streak-aware click feedback in
	-- OrbClicker -- adding the generic UI blip on top would double it up.
	if orbArea and btn:IsDescendantOf(orbArea) then
		return
	end

	-- Juice.ButtonFeel no-ops on anything already carrying
	-- JuiceFeelApplied, which is how buttons that own a bespoke hover
	-- animation elsewhere opt out of getting a second one.
	Juice.ButtonFeel(btn, {
		HoverScale = 1.05,
		Sound = clickSound,
		PitchRange = { 0.92, 1.08 },
	})
end

for _, btn in ipairs(playerGuiRoot:GetDescendants()) do
	bindButton(btn)
end

playerGuiRoot.DescendantAdded:Connect(bindButton)

while true do
	task.wait(1)
	updateValue -= 1
	UpdateTimer.Text = "Next Update: ("..(updateValue).."s)"
	if updateValue <= 0 then
		updateValue = 60
		data = GetData:InvokeServer()
		UpdateStats()
	end
end

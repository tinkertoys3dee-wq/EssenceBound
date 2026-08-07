local player = game.Players.LocalPlayer

local gui = player:WaitForChild("PlayerGui"):WaitForChild("MainGui")
local Left = gui:WaitForChild("Left")
local currencys = Left:WaitForChild("Currencys"):WaitForChild("ScrollingFrame")
local RP = game:GetService("ReplicatedStorage")
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

local function UpdateStats()
	local discovered = 0
	local total = 0
	PlayTimeText.Text = "Play Time: "..math.floor(data.PlayTime + (os.clock() - SessionStartTime)).."s"
	RarestEssenceText.Text = "Rarest Essence : "..data.RarestEssence
	RebirthsText.Text = "Rebirths : "..data.Rebirths
	EssenceGatheredText.Text = "Essence Gathered : "..formatNumber(data.TotalEssenceGathered)
	RobuxSpentText.Text = "Robux Spent : "..data.RobuxSpent
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

-- =========================================================================
-- CURRENCY DISPLAY
-- =========================================================================
-- Watching the number climb IS the reward loop in an idle game, so these
-- counters roll up to their new value and pop rather than silently
-- snapping. Purely presentational -- the authoritative value is still
-- whatever the server put on the leaderstat, and the label always lands
-- exactly on it.

local Juice = require(RP:WaitForChild("Juice"))

local GAIN_COLOR = Color3.fromRGB(140, 255, 170)
local SPEND_COLOR = Color3.fromRGB(255, 150, 150)

local function bindCurrencyDisplay(leaderstat, label)
	local displayed = tonumber(leaderstat:GetAttribute("Quantity")) or 0
	label.Text = formatNumber(displayed)

	local labelScale = Juice.GetScale(label)

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
			Juice.Punch(labelScale, 0.14, 0.24)
			Juice.PulseColor(label, GAIN_COLOR, 0.4)
		else
			-- Spending should read differently from earning, so a
			-- purchase is unmistakable.
			Juice.PulseColor(label, SPEND_COLOR, 0.4)
		end
	end)
end

bindCurrencyDisplay(EarthEsseceleaderstat, EarthEssenceDisplayText)
bindCurrencyDisplay(ShadowEssenceleaderstat, ShadowEssenceDisplayText)

local UpdateTimer = Left:WaitForChild("UpdateTimer")
-- Internal refresh countdown, not something a player needs to see ("Next
-- Update: 43s" reads like debug output, not part of the game).
UpdateTimer.Visible = false

local updateValue = 60

UpdateStats()

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

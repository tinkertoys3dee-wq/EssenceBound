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

EarthEssenceDisplayText.Text = formatNumber(EarthEsseceleaderstat:GetAttribute("Quantity"))

EarthEsseceleaderstat:GetAttributeChangedSignal("Quantity"):Connect(function()
	EarthEssenceDisplayText.Text = formatNumber(EarthEsseceleaderstat:GetAttribute("Quantity"))
end)

ShadowEssenceDisplayText.Text = formatNumber(ShadowEssenceleaderstat:GetAttribute("Quantity"))

ShadowEssenceleaderstat:GetAttributeChangedSignal("Quantity"):Connect(function()
	ShadowEssenceDisplayText.Text = formatNumber(ShadowEssenceleaderstat:GetAttribute("Quantity"))
end)

local UpdateTimer = Left:WaitForChild("UpdateTimer")
-- Internal refresh countdown, not something a player needs to see ("Next
-- Update: 43s" reads like debug output, not part of the game).
UpdateTimer.Visible = false

local updateValue = 60

UpdateStats()

local clickSound = game:GetService("SoundService"):WaitForChild("SFX"):WaitForChild("UI"):WaitForChild("UIPop")
for _, btn in pairs(player:WaitForChild("PlayerGui"):GetDescendants()) do
	if btn:IsA("TextButton") then
		btn.MouseButton1Click:Connect(function()
			clickSound:Play()
		end)
	end
end

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

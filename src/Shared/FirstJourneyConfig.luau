--[[
	FirstJourneyConfig
	===============================================================
	The first twelve minutes are a compact progression story rather than a
	loose pile of prompts. All goals and rewards are data here so the server
	and HUD cannot disagree about pacing, copy or presentation.

	Every beat requires fresh actions after it becomes active, preventing a
	new player from accidentally completing half the journey at once and then
	waiting on a timer. Minute three begins a personal 2x rush; fresh goals at
	minutes six, eight, ten and eleven sustain the arc through the finale.
]]

local FirstJourneyConfig = {}

FirstJourneyConfig.Version = 2
FirstJourneyConfig.DurationSeconds = 12 * 60
FirstJourneyConfig.RushStartsAt = 3 * 60
FirstJourneyConfig.RushMultiplier = 2
-- Newcomers should understand the core loop before seeing one optional,
-- low-pressure offer. The storefront uses this threshold rather than
-- blocking monetization until the entire journey is over.
FirstJourneyConfig.MonetizationUnlockAt = 6 * 60
FirstJourneyConfig.PostJourneyPotion = {
	Effect = "EssenceX15",
	Duration = 15 * 60,
	Label = "1.5x Essence for 15 minutes",
}

FirstJourneyConfig.Stages = {
	{
		Id = "first_spark",
		Name = "First Spark",
		Icon = "✦",
		GoalType = "Collections",
		Target = 3,
		Objective = "Collect 3 essence orbs",
		Hint = "Move your collection ring over the falling essence.",
		Action = "Orb",
		ActionLabel = "FIND ORBS",
		Reward = { EarthEssence = 75 },
		RewardText = "+75 Earth Essence",
		Accent = Color3.fromRGB(105, 239, 158),
	},
	{
		Id = "resonant_rhythm",
		Name = "Resonant Rhythm",
		Icon = "⚡",
		GoalType = "Clicks",
		Target = 20,
		Objective = "Strike the great orb 20 times",
		Hint = "Rapid clicks build a rhythm and release more fragments.",
		Action = "Orb",
		ActionLabel = "STRIKE ORB",
		Reward = { EarthEssence = 150 },
		RewardText = "+150 Earth Essence",
		Accent = Color3.fromRGB(91, 218, 255),
	},
	{
		Id = "shape_power",
		Name = "Shape Your Power",
		Icon = "↑",
		GoalType = "Upgrades",
		Target = 1,
		Objective = "Purchase any upgrade",
		Hint = "Open Upgrades and choose the first path that fits you.",
		Action = "Upgrades",
		ActionLabel = "OPEN UPGRADES",
		Reward = { EarthEssence = 300 },
		RewardText = "+300 Earth Essence",
		Accent = Color3.fromRGB(130, 255, 128),
	},
	{
		Id = "touch_veil",
		Name = "Touch the Veil",
		Icon = "◐",
		GoalType = "ShadowOrCollections",
		Target = 20,
		Objective = "Discover Shadow Essence or collect 20 more orbs",
		Hint = "Rare essence can appear from any ordinary-looking fragment.",
		Action = "Orb",
		ActionLabel = "HUNT SHADOW",
		Reward = { EarthEssence = 250, ShadowEssence = 20 },
		RewardText = "+250 Earth  •  +20 Shadow",
		Accent = Color3.fromRGB(191, 103, 255),
	},
	{
		Id = "read_current",
		Name = "Read the Current",
		Icon = "◈",
		GoalType = "ProphecyOrCollections",
		Target = 30,
		Objective = "Roll a prophecy or collect 30 more orbs",
		Hint = "The crystal at the top-right can grant a temporary omen.",
		Action = "Prophecy",
		ActionLabel = "READ PROPHECY",
		Reward = { EarthEssence = 500, ShadowEssence = 25 },
		RewardText = "+500 Earth  •  +25 Shadow",
		Accent = Color3.fromRGB(223, 124, 255),
	},
	{
		Id = "awakening_rush",
		Name = "Awakening Rush",
		Icon = "☀",
		GoalType = "RushCollections",
		Target = 25,
		UnlockAt = FirstJourneyConfig.RushStartsAt,
		Objective = "Collect 25 orbs during your 2x rush",
		Hint = "Your bond is surging—every collection is doubled right now.",
		Action = "Orb",
		ActionLabel = "USE 2x RUSH",
		Reward = { EarthEssence = 1000, ShadowEssence = 50 },
		RewardText = "+1,000 Earth  •  +50 Shadow",
		Accent = Color3.fromRGB(255, 177, 66),
	},
	{
		Id = "sustain_surge",
		Name = "Sustain the Surge",
		Icon = "✺",
		GoalType = "Collections",
		Target = 40,
		Objective = "Collect 40 more orbs while the surge is active",
		Hint = "Keep moving the collection ring—rare fragments are worth more.",
		Action = "Orb",
		ActionLabel = "KEEP GATHERING",
		Reward = { EarthEssence = 1300, ShadowEssence = 50 },
		RewardText = "+1,300 Earth  •  +50 Shadow",
		Accent = Color3.fromRGB(255, 194, 84),
	},
	{
		Id = "shatter_limit",
		Name = "Shatter the Limit",
		Icon = "⚡",
		GoalType = "Clicks",
		Target = 100,
		UnlockAt = 6 * 60,
		Objective = "Strike the great orb 100 more times",
		Hint = "A fast rhythm fills the field with fragments for your 2x rush.",
		Action = "Orb",
		ActionLabel = "BUILD A STORM",
		Reward = { EarthEssence = 1750, ShadowEssence = 75 },
		RewardText = "+1,750 Earth  •  +75 Shadow",
		Accent = Color3.fromRGB(90, 222, 255),
	},
	{
		Id = "choose_growth",
		Name = "Choose Your Growth",
		Icon = "↑",
		GoalType = "UpgradesOrCollections",
		Target = 100,
		UpgradeTarget = 2,
		CollectionTarget = 50,
		UnlockAt = 8 * 60,
		Objective = "Buy 2 upgrades or collect 50 more orbs",
		Hint = "Choose a build path—or keep gathering if you want to save.",
		Action = "Upgrades",
		ActionLabel = "CHOOSE A PATH",
		Reward = { EarthEssence = 2500, ShadowEssence = 100, SolarEssence = 3 },
		RewardText = "+2,500 Earth  •  +100 Shadow  •  +3 Solar",
		Accent = Color3.fromRGB(135, 255, 133),
	},
	{
		Id = "resonance_run",
		Name = "Resonance Run",
		Icon = "◈",
		GoalType = "Collections",
		Target = 75,
		UnlockAt = 10 * 60,
		Objective = "Collect 75 more orbs",
		Hint = "Your awakening is close—turn the whole field into momentum.",
		Action = "Orb",
		ActionLabel = "FINISH THE RUN",
		Reward = { EarthEssence = 3500, ShadowEssence = 125 },
		RewardText = "+3,500 Earth  •  +125 Shadow",
		Accent = Color3.fromRGB(219, 121, 255),
	},
	{
		Id = "final_charge",
		Name = "Final Charge",
		Icon = "✧",
		GoalType = "Clicks",
		Target = 120,
		UnlockAt = 11 * 60,
		Objective = "Land 120 final strikes",
		Hint = "One last burst will stabilize the awakened bond.",
		Action = "Orb",
		ActionLabel = "FINAL CHARGE",
		Reward = { EarthEssence = 4500, ShadowEssence = 150, SolarEssence = 5 },
		RewardText = "+4,500 Earth  •  +150 Shadow  •  +5 Solar",
		Accent = Color3.fromRGB(255, 214, 103),
	},
}

FirstJourneyConfig.FinalReward = {
	EarthEssence = 5000,
	ShadowEssence = 200,
	SolarEssence = 10,
}
FirstJourneyConfig.FinalRewardText = "+5,000 Earth  •  +200 Shadow  •  +10 Solar"

function FirstJourneyConfig.GetStage(index)
	return FirstJourneyConfig.Stages[tonumber(index) or 0]
end

function FirstJourneyConfig.GetStageCount()
	return #FirstJourneyConfig.Stages
end

function FirstJourneyConfig.FormatTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

return FirstJourneyConfig

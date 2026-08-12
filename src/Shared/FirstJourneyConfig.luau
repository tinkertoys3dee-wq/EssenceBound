--[[
	FirstJourneyConfig
	===============================================================
	The first eight minutes are a compact progression story rather than a
	loose pile of prompts. All goals and rewards are data here so the server
	and HUD cannot disagree about pacing, copy or presentation.

	The first five beats are action-gated and can move as quickly as a player
	learns. Minute five begins a personal 2x rush; minute eight is the finale.
	Alternative collection goals prevent rare Shadow RNG or an ignored
	Prophecy button from hard-locking onboarding.
]]

local FirstJourneyConfig = {}

FirstJourneyConfig.DurationSeconds = 8 * 60
FirstJourneyConfig.RushStartsAt = 5 * 60
FirstJourneyConfig.RushMultiplier = 2
FirstJourneyConfig.PostJourneyPotion = {
	Effect = "EssenceX15",
	Duration = 10 * 60,
	Label = "1.5x Essence for 10 minutes",
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
		Reward = { EarthEssence = 300 },
		RewardText = "+300 Earth Essence",
		Accent = Color3.fromRGB(130, 255, 128),
	},
	{
		Id = "touch_veil",
		Name = "Touch the Veil",
		Icon = "◐",
		GoalType = "ShadowOrCollections",
		Target = 25,
		Objective = "Discover Shadow Essence or collect 25 total orbs",
		Hint = "Rare essence can appear from any ordinary-looking fragment.",
		Reward = { EarthEssence = 250, ShadowEssence = 20 },
		RewardText = "+250 Earth  •  +20 Shadow",
		Accent = Color3.fromRGB(191, 103, 255),
	},
	{
		Id = "read_current",
		Name = "Read the Current",
		Icon = "◈",
		GoalType = "ProphecyOrCollections",
		Target = 45,
		Objective = "Roll a prophecy or collect 45 total orbs",
		Hint = "The crystal at the top-right can grant a temporary omen.",
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
		Reward = { EarthEssence = 1000, ShadowEssence = 50 },
		RewardText = "+1,000 Earth  •  +50 Shadow",
		Accent = Color3.fromRGB(255, 177, 66),
	},
}

FirstJourneyConfig.FinalReward = {
	EarthEssence = 2500,
	ShadowEssence = 100,
	SolarEssence = 5,
}
FirstJourneyConfig.FinalRewardText = "+2,500 Earth  •  +100 Shadow  •  +5 Solar"

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

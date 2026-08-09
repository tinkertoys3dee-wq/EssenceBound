-- Tuning for the Resonance loop. Collect alternating essence types to build
-- Harmony, fill the Pulse meter, then spend it on a short Overdrive window.
local Config = {}

Config.ComboWindow = 6
Config.MaxHarmony = 12
Config.BonusPerHarmony = 0.08
Config.PulsePerCollection = 8
Config.PulsePerCritical = 6
Config.PulseRequired = 100
Config.OverdriveSeconds = 15
Config.OverdriveMultiplier = 2
Config.ExtensionPerCollection = 0.35
Config.MaxOverdriveSeconds = 22

Config.Mastery = {
	BaseXP = 10,
	CriticalXP = 5,
	MaxLevel = 25,
	PassiveBonusPerLevel = 0.02,
}

function Config.XPForLevel(level)
	level = math.max(1, math.floor(tonumber(level) or 1))
	return 90 + (level - 1) * 55 + math.floor((level - 1) ^ 1.35 * 18)
end

function Config.GetMasteryMultiplier(level)
	return 1 + math.clamp(tonumber(level) or 0, 0, Config.Mastery.MaxLevel) * Config.Mastery.PassiveBonusPerLevel
end

function Config.GetHarmonyMultiplier(stacks)
	return 1 + math.clamp(tonumber(stacks) or 0, 0, Config.MaxHarmony) * Config.BonusPerHarmony
end

return Config

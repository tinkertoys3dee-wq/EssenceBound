--[[
	WhatsNewConfig (ModuleScript -> ReplicatedStorage)
	===================================================
	Pure data for the "What's New" popup: a single incrementing CurrentVersion
	number plus one entry describing everything added since the last bump.

	WHY THIS EXISTS
	-----------------
	This session alone added global leaderboards, an achievements/milestones
	panel, a scheduled Essence Rush event and a comeback bonus for lapsed
	players -- every one of them purely additive, so an already-existing save
	just quietly gained a handful of new side-buttons with zero explanation.
	A returning player who left before any of this shipped has no way to
	learn it's there. This popup is the fix: a short, one-time "here's what's
	new" beat shown once per version bump, to anyone whose saved
	SeenWhatsNewVersion is behind CurrentVersion.

	HOW TO ADD A NEW ENTRY
	------------------------
	Bump CurrentVersion by 1 and replace the Highlights list below with
	whatever shipped since the last bump (keep it short -- 3-5 bullets, each
	one line). Old versions are NOT kept as a history log; a player who was
	behind by several versions just sees the latest Highlights list once and
	is caught fully up in a single popup, rather than replaying a stack of
	old announcements.

	Pure data. No Players, DataStores or Remotes -- safe to require from
	either side, same contract as every other *Config module in this
	codebase.
]]

local WhatsNewConfig = {}

WhatsNewConfig.CurrentVersion = 1

WhatsNewConfig.Title = "What's New"

WhatsNewConfig.Highlights = {
	{ Icon = "🏆", Text = "Global leaderboards -- Top Essence, Top Rebirths, and a weekly essence race that resets every week." },
	{ Icon = "🏅", Text = "An Achievements panel tracking Roblox badges and 10 new Milestones with real essence/Shard rewards." },
	{ Icon = "🌩️", Text = "Essence Rush -- a random server-wide event boosting everyone's essence gain for a few minutes." },
	{ Icon = "🎉", Text = "A Welcome Back bonus for returning after time away -- the longer you were gone, the bigger it is." },
	{ Icon = "🎁", Text = "Daily login streaks, daily quests and playtime chests, if you haven't found the side buttons yet." },
}

return WhatsNewConfig

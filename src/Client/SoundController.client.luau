local Music = game:GetService("SoundService"):WaitForChild("Music")
local EarthMusic = Music:WaitForChild("Earth Essence")
local PresentationCoordinator = require(game:GetService("ReplicatedStorage"):WaitForChild("PresentationCoordinator"))
local tracks = {
	EarthMusic:WaitForChild("Music1"),
	EarthMusic:WaitForChild("Music2"),
	EarthMusic:WaitForChild("Music3"),
}

local lastIndex = nil

local function pickNextTrack()
	if #tracks == 1 then
		return 1
	end
	local index
	repeat
		index = math.random(1, #tracks)
	until index ~= lastIndex
	lastIndex = index
	return index
end

local function playNextTrack()
	local index = pickNextTrack()
	local track = tracks[index]
	track.TimePosition = 0
	track:Play()
	track.Ended:Wait()
end

PresentationCoordinator.WaitUntilReady()

while true do
	playNextTrack()
end

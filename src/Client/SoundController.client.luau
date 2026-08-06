local Music = game:GetService("SoundService"):WaitForChild("Music")
local EarthMusic = Music:WaitForChild("Earth Essence")

local loadingDone = game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("LoadingDone")
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

local LoadingIsDone = false
loadingDone.Event:Connect(function()
	LoadingIsDone = true
end)

while true do
	if LoadingIsDone then
		playNextTrack()
	else
		task.wait(1)
	end
end
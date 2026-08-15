-- DarkForestMusicSystem
-- The one server-owned global playlist for DarkForest1 through 9.
-- Accept either the normal SoundService location or a SoundManager folder.

local SoundService = game:GetService("SoundService")
local ServerStorage = game:GetService("ServerStorage")

local function findTrack(index)
	local candidates = {
		SoundService,
		SoundService:FindFirstChild("SoundManager"),
		ServerStorage:FindFirstChild("SoundManager"),
	}

	for _, parent in ipairs(candidates) do
		if parent then
			local track = parent:FindFirstChild("DarkForest" .. index)
			if track and track:IsA("Sound") then
				return track
			end
		end
	end

	return nil
end

local ambienceTracks = {}
local lastIndex

for index = 1, 9 do
	local track = findTrack(index)
	if track then
		track.Looped = false
		track:Stop()
		table.insert(ambienceTracks, track)
	else
		warn("DarkForestMusicSystem missing DarkForest" .. index .. " under SoundService or SoundManager")
	end
end

if #ambienceTracks == 0 then
	warn("DarkForestMusicSystem: no DarkForest tracks found. Nothing will play.")
	return
end

while true do
	local index
	repeat
		index = math.random(1, #ambienceTracks)
	until #ambienceTracks == 1 or index ~= lastIndex

	lastIndex = index
	local track = ambienceTracks[index]
	track.TimePosition = 0
	track:Play()
	track.Ended:Wait()
end

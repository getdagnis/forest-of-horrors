workspace:WaitForChild("McDonaldsMusicEmitter")
	:WaitForChild("Bubble Pop Party")
	:Play()

local SoundService = game:GetService("SoundService")

local ambienceTracks = {}
local lastIndex

for index = 1, 5 do
	local track = SoundService:WaitForChild("DarkAmbience" .. index)
	track.Looped = false
	track:Stop()
	table.insert(ambienceTracks, track)
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


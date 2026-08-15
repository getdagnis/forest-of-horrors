-- McDonaldsJukebox Server Script

-- Put this Script under ServerScriptService. Put the music Sounds directly
-- inside the emitter, alongside its display Decal.
-- The jukebox keeps the currently selected song looping until the player cycles
-- to another track or silence.

local emitter = workspace:FindFirstChild("McDonaldsMusicEmitter") or workspace:WaitForChild("McDonaldsJukebox")

local clickDetector = emitter:FindFirstChildOfClass("ClickDetector")
if not clickDetector then
	clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 12
	clickDetector.Parent = emitter
end

local tracks = {}
for _, item in emitter:GetChildren() do
	if item:IsA("Sound") then
		item.Looped = false
		item:Stop()
		table.insert(tracks, item)
	end
end

table.sort(tracks, function(first, second)
	return first.Name < second.Name
end)

if #tracks == 0 then
	warn("McDonaldsJukebox found no Sound children in", emitter:GetFullName())
	return
end

local selectedIndex = 0 -- 0 is Silence; 1 through #tracks are the songs.
local activeEndedConnection

local function stopAllTracks()
	for _, track in tracks do
		track:Stop()
		track.TimePosition = 0
	end
end

local function playTrack(index)
	if activeEndedConnection then
		activeEndedConnection:Disconnect()
		activeEndedConnection = nil
	end

	stopAllTracks()
	selectedIndex = index

	if selectedIndex == 0 then
		emitter:SetAttribute("JukeboxTrack", "Silence")
		return
	end

	local track = tracks[selectedIndex]
	emitter:SetAttribute("JukeboxTrack", track.Name)
	track.TimePosition = 0
	track:Play()

	activeEndedConnection = track.Ended:Connect(function()
		if selectedIndex ~= index then return end
		track.TimePosition = 0
		track:Play()
	end)
end

local function selectNextTrack()
	if selectedIndex == 0 then
		playTrack(1)
		return
	end

	if selectedIndex >= #tracks then
		playTrack(0)
		return
	end

	playTrack(selectedIndex + 1)
end

clickDetector.MouseClick:Connect(selectNextTrack)

-- Start on the first song, and keep that song looping until another choice is made.
playTrack(1)

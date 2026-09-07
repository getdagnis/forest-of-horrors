-- Shared client audio warm-up.  Keep the music playlist out of this pass so
-- joining a round does not download long background tracks before they are
-- needed.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local DYNAMIC_SOUND_IDS = {
	"rbxassetid://126040226110628", -- MonsterGun1 ShotSound
	"rbxassetid://138074730724614", -- MonsterGun
	"rbxassetid://131794614393147", -- MonsterBlaster shot
	"rbxassetid://140102991925260", -- MonsterBlaster charge
	"rbxassetid://124307033081669", -- MonsterBlaster cooldown
	"rbxassetid://137787508848769", -- MonsterBlaster depleted
	"rbxassetid://139730692334768", -- MonsterBlaster pickup
}

local started = false
local ready = false
local readyEvent = Instance.new("BindableEvent")
readyEvent.Name = "CriticalAudioReady"
readyEvent.Parent = SoundService

local function isMusicSound(sound)
	local parent = sound.Parent
	while parent and parent ~= SoundService do
		if parent.Name == "Music" then return true end
		parent = parent.Parent
	end
	return false
end

local function collectSounds()
	local sounds = {}
	for _, descendant in ipairs(SoundService:GetDescendants()) do
		if descendant:IsA("Sound") and not isMusicSound(descendant) and descendant.SoundId ~= "" then
			table.insert(sounds, descendant)
		end
	end

	local dynamicFolder = Instance.new("Folder")
	dynamicFolder.Name = "CriticalAudioPreload"
	dynamicFolder.Parent = SoundService
	for index, soundId in ipairs(DYNAMIC_SOUND_IDS) do
		local sound = Instance.new("Sound")
		sound.Name = "Dynamic" .. index
		sound.SoundId = soundId
		sound.Parent = dynamicFolder
		table.insert(sounds, sound)
	end
	return sounds, dynamicFolder
end

local function preloadInstanceSounds(instance)
	local sounds = {}
	if instance:IsA("Sound") then table.insert(sounds, instance) end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Sound") and descendant.SoundId ~= "" then
			table.insert(sounds, descendant)
		end
	end
	if #sounds > 0 then
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync(sounds) end)
		end)
	end
end

local function start()
	if started then return end
	started = true
	local player = Players.LocalPlayer
	if player then
		local function watchContainer(container)
			if not container then return end
			container.ChildAdded:Connect(preloadInstanceSounds)
			for _, child in ipairs(container:GetChildren()) do preloadInstanceSounds(child) end
		end
		watchContainer(player:FindFirstChildOfClass("Backpack"))
		player.CharacterAdded:Connect(watchContainer)
		watchContainer(player.Character)
	end
	task.spawn(function()
		local sounds, dynamicFolder = collectSounds()
		pcall(function()
			ContentProvider:PreloadAsync(sounds)
		end)
		if dynamicFolder.Parent then dynamicFolder:Destroy() end
		ready = true
		SoundService:SetAttribute("CriticalAudioReady", true)
		readyEvent:Fire()
	end)
end

local function waitUntilReady(timeout)
	start()
	if ready then return true end
	local deadline = os.clock() + (timeout or 5)
	while not ready and os.clock() < deadline do
		task.wait()
	end
	return ready
end

return {
	Start = start,
	WaitUntilReady = waitUntilReady,
}

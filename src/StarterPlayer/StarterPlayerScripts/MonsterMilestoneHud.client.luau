-- StarterPlayer > StarterPlayerScripts > MonsterMilestoneHud
-- One large, local presentation cue for each server-approved monster milestone.
-- Add future sounds under SoundService.MonsterMilestoneSounds as `90`, `80`,
-- ... `10` (or `MonsterMilestone90`, etc.). Missing sounds are intentionally
-- silent until the audio files are supplied.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local milestoneEvent = ReplicatedStorage:WaitForChild("MonsterMilestone")
local playerKillMilestoneEvent = ReplicatedStorage:WaitForChild("PlayerKillMilestone")
local secretShaftAnnouncementEvent = ReplicatedStorage:WaitForChild("SecretShaftAnnouncement")
local secretShaftLockedEvent = ReplicatedStorage:WaitForChild("SecretShaftDoorLocked")
local lavaPoolDoorOpenedEvent = ReplicatedStorage:WaitForChild("LavaPoolDoorOpened")
local lavaPoolDoorLockedEvent = ReplicatedStorage:WaitForChild("LavaPoolDoorLocked")
local nightmareEscapeStartedEvent = ReplicatedStorage:WaitForChild("NightmareEscapeStarted")
local roundStartedEvent = ReplicatedStorage:WaitForChild("RoundStarted")
local WELCOME_ACCEPTED_ATTRIBUTE = "NightmareWelcomeAccepted"
local INTRODUCTION_COMPLETE_ATTRIBUTE = "NightmareIntroductionComplete"
local RADAR_CONTACT_COUNT_ATTRIBUTE = "MonsterRadarContactCount"
local DEEPER_MESSAGE_REMAINING_SECONDS = 21 * 60 + 30
local LONG_ANNOUNCEMENT_SECONDS = 5
local ANNOUNCEMENT_FADE_SECONDS = 0.35

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterMilestoneHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
-- This is a sibling ScreenGui to GameFlowHud, so a label ZIndex cannot place
-- it over GameFlowHud's WelcomePanel. A deliberately higher DisplayOrder
-- keeps the two opening lines readable during the 15-second shade fade.
gui.DisplayOrder = 10000
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local activeToken = 0
local announcementBusyUntil = 0
local introductionStarted = false
local currentRoundGeneration = math.max(0, math.floor(tonumber(workspace:GetAttribute("RoundGeneration")) or 0))
local pendingRoundStartedGeneration
local appliedRoundStartedGeneration
local deeperMessagePending = false
local deeperMessageShown = false
local criticalSequenceActive = false
local ROUND_TIME_ANNOUNCEMENTS = {
	{ seconds = 10 * 60, text = "10 minutes left" },
	{ seconds = 5 * 60, text = "5 minutes left" },
	{ seconds = 2 * 60, text = "2 minutes left" },
	{ seconds = 1 * 60, text = "1 minute left" },
}

local function isCurrentGameplayGeneration(generation)
	return tonumber(generation) == currentRoundGeneration
		and currentRoundGeneration == tonumber(workspace:GetAttribute("RoundGeneration"))
		and (workspace:GetAttribute("RoundState") == "Active" or workspace:GetAttribute("RoundState") == "Escape")
end

local function cancelAnnouncements()
	activeToken += 1
	announcementBusyUntil = 0
	deeperMessagePending = false
	criticalSequenceActive = false
	gui.DisplayOrder = 10000
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end
end

local function playMilestoneSound(count)
	local folder = SoundService:FindFirstChild("MonsterMilestoneSounds")
	if not folder then return end
	local sound = folder:FindFirstChild(tostring(count)) or folder:FindFirstChild("MonsterMilestone" .. tostring(count))
	if not sound or not sound:IsA("Sound") then return end
	local clone = sound:Clone()
	clone.Looped = false
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, math.max(3, clone.TimeLength + 1))
end

-- A single local clone lets every player hear the supplied round-time cue
-- without restarting or changing the shared SoundService template.
local function playRemainingSound()
	local sound = SoundService:FindFirstChild("Remaining")
	if not sound or not sound:IsA("Sound") then return end
	local clone = sound:Clone()
	clone.Looped = false
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, math.max(3, clone.TimeLength + 1))
end

local function playSoundServiceCue(name)
	local sound = SoundService:FindFirstChild(name)
	if not sound or not sound:IsA("Sound") then
		warn("[MonsterMilestoneHud] SoundService." .. name .. " is missing")
		return
	end
	local clone = sound:Clone()
	clone.Looped = false
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, math.max(3, clone.TimeLength + 1))
end

-- Match score announcements: restrained white GothamBold with a firm
-- outline. This is deliberately larger for round-level information, not pink
-- or GothamBlack like the retired milestone presentation.
local function showAnnouncement(message, visibleSeconds, isCritical)
	visibleSeconds = tonumber(visibleSeconds) or 2.2
	activeToken += 1
	local token = activeToken
	announcementBusyUntil = os.clock() + visibleSeconds + ANNOUNCEMENT_FADE_SECONDS
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end

	local label = Instance.new("TextLabel")
	label.Name = "RoundAnnouncement"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.42, 0)
	label.Size = isCritical and UDim2.new(0.9, 0, 0, 132) or UDim2.new(0.72, 0, 0, 68)
	label.BackgroundTransparency = 1
	label.Font = isCritical and Enum.Font.GothamBlack or Enum.Font.GothamBold
	label.Text = message
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.TextWrapped = true
	label.TextTransparency = 1
	label.Parent = gui

	TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	task.delay(visibleSeconds, function()
		if token ~= activeToken or not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(ANNOUNCEMENT_FADE_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(label, ANNOUNCEMENT_FADE_SECONDS + 0.05)
	end)
end

local function formatClock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function startNightmareIntroduction(generation)
	if introductionStarted or not isCurrentGameplayGeneration(generation)
		or workspace:GetAttribute("RoundState") ~= "Active"
	then
		return
	end
	introductionStarted = true

	task.spawn(function()
		-- RoundStarted owns the cue. Waiting here preserves the welcome-modal
		-- handoff without treating a local attribute transition as a new round.
		while isCurrentGameplayGeneration(generation)
			and workspace:GetAttribute("RoundState") == "Active"
			and player:GetAttribute(WELCOME_ACCEPTED_ATTRIBUTE) ~= true do
			task.wait(0.1)
		end
		if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
		-- The opening shade is intentionally still fading at this point. Raise
		-- only the introduction announcements above it; GameFlowHud raises itself
		-- higher whenever a result modal appears.
		gui.DisplayOrder = 30000
		showAnnouncement("Remove all monsters from your nightmare...", LONG_ANNOUNCEMENT_SECONDS)
		-- Wait for the first line and its fade, then preserve one full second of
		-- silence before the second line appears.
		task.wait(LONG_ANNOUNCEMENT_SECONDS + ANNOUNCEMENT_FADE_SECONDS + 1)
		if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
		showAnnouncement("Or you will stay in it forever...", LONG_ANNOUNCEMENT_SECONDS)
		-- Unlock difficulty only after the second line and its fade.
		task.wait(LONG_ANNOUNCEMENT_SECONDS + ANNOUNCEMENT_FADE_SECONDS)
		if isCurrentGameplayGeneration(generation) and workspace:GetAttribute("RoundState") == "Active" then
			player:SetAttribute(INTRODUCTION_COMPLETE_ATTRIBUTE, true)
			gui.DisplayOrder = 10000
		end
	end)
end

local function reconcileRoundStart()
	local generation = pendingRoundStartedGeneration
	if not generation or generation == appliedRoundStartedGeneration then return end
	if generation ~= tonumber(workspace:GetAttribute("RoundGeneration"))
		or workspace:GetAttribute("RoundState") ~= "Active"
	then return end

	pendingRoundStartedGeneration = nil
	appliedRoundStartedGeneration = generation
	currentRoundGeneration = generation
	introductionStarted = false
	cancelAnnouncements()
	player:SetAttribute(INTRODUCTION_COMPLETE_ATTRIBUTE, false)
	startNightmareIntroduction(generation)
end

local function observeRoundStart(generation)
	generation = tonumber(generation)
	if not generation or generation < currentRoundGeneration then return end
	pendingRoundStartedGeneration = generation
	reconcileRoundStart()
end

roundStartedEvent.OnClientEvent:Connect(observeRoundStart)
-- The initial RoundStarted can precede this LocalScript. Its replicated
-- generation is the initial server-start signal, not a local welcome trigger.
if workspace:GetAttribute("RoundState") == "Active" then
	observeRoundStart(currentRoundGeneration)
end

milestoneEvent.OnClientEvent:Connect(function(count, generation)
	if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
	if criticalSequenceActive then return end
	playMilestoneSound(count)
	showAnnouncement(string.format("%d monsters left", tonumber(count) or 0))
end)

playerKillMilestoneEvent.OnClientEvent:Connect(function(count, generation)
	if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
	if criticalSequenceActive then return end
	showAnnouncement(string.format("%d monsters killed!", tonumber(count) or 0))
end)

secretShaftAnnouncementEvent.OnClientEvent:Connect(function(generation)
	if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
	if criticalSequenceActive then return end
	local tokenGeneration = currentRoundGeneration
	task.spawn(function()
		showAnnouncement("guard of the secret shaft\nhas been killed!", LONG_ANNOUNCEMENT_SECONDS)
		task.wait(LONG_ANNOUNCEMENT_SECONDS + ANNOUNCEMENT_FADE_SECONDS + 0.3)
		if not criticalSequenceActive
			and isCurrentGameplayGeneration(tokenGeneration)
			and workspace:GetAttribute("RoundState") == "Active"
		then
			showAnnouncement("the secret shaft is now open...", LONG_ANNOUNCEMENT_SECONDS)
		end
	end)
end)

secretShaftLockedEvent.OnClientEvent:Connect(function(generation)
	if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
	if criticalSequenceActive then return end
	showAnnouncement("you must kill the door guardian first", LONG_ANNOUNCEMENT_SECONDS)
end)

lavaPoolDoorLockedEvent.OnClientEvent:Connect(function(generation)
	if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
	if criticalSequenceActive then return end
	showAnnouncement("you must eliminate all monsters first", LONG_ANNOUNCEMENT_SECONDS)
end)

lavaPoolDoorOpenedEvent.OnClientEvent:Connect(function(generation)
	if not isCurrentGameplayGeneration(generation) or workspace:GetAttribute("RoundState") ~= "Active" then return end
	if criticalSequenceActive then return end
	cancelAnnouncements()
	criticalSequenceActive = true
	local sequenceGeneration = currentRoundGeneration
	local clearedIn = formatClock(workspace:GetServerTimeNow() - (tonumber(workspace:GetAttribute("RoundStartedAt")) or workspace:GetServerTimeNow()))
	task.spawn(function()
		playSoundServiceCue("SecretShaftGuard")
			showAnnouncement("all overground monsters are killed\n(" .. clearedIn .. ")", 5, true)
			task.wait(6)
		if not isCurrentGameplayGeneration(sequenceGeneration) or workspace:GetAttribute("RoundState") ~= "Active" then return end
			showAnnouncement("lava pool secret door is now open", 4, true)
			task.wait(5)
		if not isCurrentGameplayGeneration(sequenceGeneration) or workspace:GetAttribute("RoundState") ~= "Active" then return end
		playSoundServiceCue("SuspenseSound")
			showAnnouncement("some deep monsters remain", 4, true)
		task.wait(4 + ANNOUNCEMENT_FADE_SECONDS)
		if isCurrentGameplayGeneration(sequenceGeneration) and workspace:GetAttribute("RoundState") == "Active" then
			criticalSequenceActive = false
		end
	end)
end)

nightmareEscapeStartedEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or not isCurrentGameplayGeneration(data.roundGeneration) then return end
	if criticalSequenceActive then return end
	local generation = currentRoundGeneration
	task.spawn(function()
		showAnnouncement("You got rid of all your monsters\nTime: " .. formatClock(data and data.clearedInSeconds), LONG_ANNOUNCEMENT_SECONDS)
		task.wait(LONG_ANNOUNCEMENT_SECONDS + ANNOUNCEMENT_FADE_SECONDS + 0.5)
		if isCurrentGameplayGeneration(generation) then
			showAnnouncement("Now get to your bedroom fast...", LONG_ANNOUNCEMENT_SECONDS)
		end
	end)
end)

local activeRoundEndsAt
local lastRemainingSeconds
local announcedTimeThresholds = {}
RunService.RenderStepped:Connect(function()
	if workspace:GetAttribute("RoundState") ~= "Active" and workspace:GetAttribute("RoundState") ~= "Escape" then return end
	local roundEndsAt = tonumber(workspace:GetAttribute("RoundEndsAt"))
	if not roundEndsAt then return end

	local remainingSeconds = roundEndsAt - workspace:GetServerTimeNow()
	if activeRoundEndsAt ~= roundEndsAt then
		activeRoundEndsAt = roundEndsAt
		lastRemainingSeconds = remainingSeconds
		announcedTimeThresholds = {}
		deeperMessagePending = false
		deeperMessageShown = false
		return
	end

	-- The escape clock is a navigation deadline, not another combat warning
	-- sequence. Its story announcement arrives through NightmareEscapeStarted.
	if workspace:GetAttribute("RoundState") == "Escape" then
		lastRemainingSeconds = remainingSeconds
		return
	end

	if not deeperMessageShown
		and not criticalSequenceActive
		and remainingSeconds <= DEEPER_MESSAGE_REMAINING_SECONDS
		and player:GetAttribute(WELCOME_ACCEPTED_ATTRIBUTE) == true
	then
		deeperMessagePending = true
	end

	for _, announcement in ipairs(ROUND_TIME_ANNOUNCEMENTS) do
		if criticalSequenceActive then break end
		if not announcedTimeThresholds[announcement.seconds]
			and lastRemainingSeconds > announcement.seconds
			and remainingSeconds <= announcement.seconds
		then
			announcedTimeThresholds[announcement.seconds] = true
			playRemainingSound()
			showAnnouncement(announcement.text)
			break
		end
	end

	-- "Quiet" uses the exact contact count rendered by MonsterRadar, including
	-- its adaptive range and special bomb/guardian contacts. A negative value
	-- means the radar is unavailable (for example while the character is dead).
	-- Time warnings run first so this pending story beat cannot replace one when
	-- both become eligible on the same rendered frame.
	if deeperMessagePending
		and not criticalSequenceActive
		and tonumber(player:GetAttribute(RADAR_CONTACT_COUNT_ATTRIBUTE)) == 0
		and os.clock() >= announcementBusyUntil
	then
		deeperMessagePending = false
		deeperMessageShown = true
		showAnnouncement("Some monsters are deeper than you think...", LONG_ANNOUNCEMENT_SECONDS)
	end
	lastRemainingSeconds = remainingSeconds
end)

workspace:GetAttributeChangedSignal("RoundGeneration"):Connect(function()
	currentRoundGeneration = math.max(0, math.floor(tonumber(workspace:GetAttribute("RoundGeneration")) or 0))
	if pendingRoundStartedGeneration and pendingRoundStartedGeneration < currentRoundGeneration then
		pendingRoundStartedGeneration = nil
	end
	introductionStarted = false
	cancelAnnouncements()
	reconcileRoundStart()
end)

workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
	local state = workspace:GetAttribute("RoundState")
	if state ~= "Active" and state ~= "Escape" then
		cancelAnnouncements()
	end
	reconcileRoundStart()
end)

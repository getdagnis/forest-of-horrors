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
local WELCOME_ACCEPTED_ATTRIBUTE = "NightmareWelcomeAccepted"
local RADAR_CONTACT_COUNT_ATTRIBUTE = "MonsterRadarContactCount"
local DEEPER_MESSAGE_REMAINING_SECONDS = 21 * 60 + 30
local LONG_ANNOUNCEMENT_SECONDS = 5
local ANNOUNCEMENT_FADE_SECONDS = 0.35

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterMilestoneHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
-- Intro and milestone text deliberately sits above GameFlowHud's fading
-- welcome shade after the player accepts the opening modal.
gui.DisplayOrder = 20
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local activeToken = 0
local announcementBusyUntil = 0
local introductionStarted = false
local deeperMessagePending = false
local deeperMessageShown = false
local ROUND_TIME_ANNOUNCEMENTS = {
	{ seconds = 10 * 60, text = "10 minutes left" },
	{ seconds = 5 * 60, text = "5 minutes left" },
	{ seconds = 2 * 60, text = "2 minutes left" },
	{ seconds = 1 * 60, text = "1 minute left" },
}

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

-- Match score announcements: restrained white GothamBold with a firm
-- outline. This is deliberately larger for round-level information, not pink
-- or GothamBlack like the retired milestone presentation.
local function showAnnouncement(message, visibleSeconds)
	visibleSeconds = tonumber(visibleSeconds) or 2.2
	activeToken += 1
	local token = activeToken
	announcementBusyUntil = os.clock() + visibleSeconds + ANNOUNCEMENT_FADE_SECONDS
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end

	local label = Instance.new("TextLabel")
	label.Name = "RoundAnnouncement"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.42, 0)
	label.Size = UDim2.new(0.72, 0, 0, 68)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = message
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = gui

	TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	task.delay(visibleSeconds, function()
		if token ~= activeToken or not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(ANNOUNCEMENT_FADE_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(label, ANNOUNCEMENT_FADE_SECONDS + 0.05)
	end)
end

local function startNightmareIntroduction()
	if introductionStarted or player:GetAttribute(WELCOME_ACCEPTED_ATTRIBUTE) ~= true then return end
	introductionStarted = true

	task.spawn(function()
		showAnnouncement("Remove all monsters from your nightmare...", LONG_ANNOUNCEMENT_SECONDS)
		-- Wait for the first line and its fade, then preserve one full second of
		-- silence before the second line appears.
		task.wait(LONG_ANNOUNCEMENT_SECONDS + ANNOUNCEMENT_FADE_SECONDS + 1)
		showAnnouncement("Or you will stay in it forever...", LONG_ANNOUNCEMENT_SECONDS)
	end)
end

player:GetAttributeChangedSignal(WELCOME_ACCEPTED_ATTRIBUTE):Connect(startNightmareIntroduction)
startNightmareIntroduction()

milestoneEvent.OnClientEvent:Connect(function(count)
	playMilestoneSound(count)
	showAnnouncement(string.format("%d monsters left", tonumber(count) or 0))
end)

playerKillMilestoneEvent.OnClientEvent:Connect(function(count)
	showAnnouncement(string.format("%d monsters killed!", tonumber(count) or 0))
end)

secretShaftAnnouncementEvent.OnClientEvent:Connect(function()
	task.spawn(function()
		showAnnouncement("guard of the secret shaft\nhas been killed!", LONG_ANNOUNCEMENT_SECONDS)
		task.wait(LONG_ANNOUNCEMENT_SECONDS + ANNOUNCEMENT_FADE_SECONDS + 0.3)
		showAnnouncement("the secret shaft is now open...", LONG_ANNOUNCEMENT_SECONDS)
	end)
end)

local activeRoundEndsAt
local lastRemainingSeconds
local announcedTimeThresholds = {}
RunService.RenderStepped:Connect(function()
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

	if not deeperMessageShown
		and remainingSeconds <= DEEPER_MESSAGE_REMAINING_SECONDS
		and player:GetAttribute(WELCOME_ACCEPTED_ATTRIBUTE) == true
	then
		deeperMessagePending = true
	end

	for _, announcement in ipairs(ROUND_TIME_ANNOUNCEMENTS) do
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
		and tonumber(player:GetAttribute(RADAR_CONTACT_COUNT_ATTRIBUTE)) == 0
		and os.clock() >= announcementBusyUntil
	then
		deeperMessagePending = false
		deeperMessageShown = true
		showAnnouncement("Some monsters are deeper than you think...", LONG_ANNOUNCEMENT_SECONDS)
	end
	lastRemainingSeconds = remainingSeconds
end)

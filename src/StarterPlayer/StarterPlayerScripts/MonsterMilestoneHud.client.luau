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

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterMilestoneHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local activeToken = 0
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

-- Match score announcements: restrained pale-yellow GothamBold with a firm
-- outline. This is deliberately larger for round-level information, not pink
-- or GothamBlack like the retired milestone presentation.
local function showAnnouncement(message)
	activeToken += 1
	local token = activeToken
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end

	local label = Instance.new("TextLabel")
	label.Name = "RoundAnnouncement"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.42, 0)
	label.Size = UDim2.new(0.72, 0, 0, 68)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = message
	label.TextColor3 = Color3.fromRGB(255, 238, 150)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = gui

	TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	task.delay(2.2, function()
		if token ~= activeToken or not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(label, 0.4)
	end)
end

milestoneEvent.OnClientEvent:Connect(function(count)
	playMilestoneSound(count)
	showAnnouncement(string.format("%d monsters left", tonumber(count) or 0))
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
		return
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
	lastRemainingSeconds = remainingSeconds
end)

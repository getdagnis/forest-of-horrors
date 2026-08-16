-- One large, local presentation cue for each server-approved monster milestone.
-- Add future sounds under SoundService.MonsterMilestoneSounds as `90`, `80`,
-- ... `10` (or `MonsterMilestone90`, etc.). Missing sounds are intentionally
-- silent until the audio files are supplied.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local milestoneEvent = ReplicatedStorage:WaitForChild("MonsterMilestone")

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterMilestoneHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local activeToken = 0

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

milestoneEvent.OnClientEvent:Connect(function(count)
	activeToken += 1
	local token = activeToken
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end

	local label = Instance.new("TextLabel")
	label.Name = "MonsterMilestone"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.42, 0)
	label.Size = UDim2.new(0.82, 0, 0, 96)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.Text = tostring(count) .. " MONSTERS LEFT!"
	label.TextColor3 = Color3.fromRGB(203, 112, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 7, 53)
	label.TextStrokeTransparency = 0.12
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = gui

	playMilestoneSound(count)
	TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	task.delay(2.2, function()
		if token ~= activeToken or not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(label, 0.4)
	end)
end)

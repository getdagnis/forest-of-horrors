-- Shooter-only multikill presentation. Optional sounds live in
-- SoundService.MultikillSounds as DoubleKill, TripleKill, QuadKill, or MegaKill.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local multikillEvent = ReplicatedStorage:WaitForChild("MultikillAnnouncement")

local gui = Instance.new("ScreenGui")
gui.Name = "MultikillHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local activeToken = 0

local function getTitle(count)
	if count == 2 then return "DOUBLE KILL!", "DoubleKill" end
	if count == 3 then return "TRIPLE KILL!", "TripleKill" end
	if count == 4 then return "QUAD KILL!", "QuadKill" end
	return tostring(count) .. "X MULTIKILL!", "MegaKill"
end

local function playSound(soundName)
	local folder = SoundService:FindFirstChild("MultikillSounds")
	local source = folder and folder:FindFirstChild(soundName)
	if not source or not source:IsA("Sound") then return end
	local sound = source:Clone()
	sound.Looped = false
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(3, sound.TimeLength + 1))
end

multikillEvent.OnClientEvent:Connect(function(count, baseScore, bonus)
	activeToken += 1
	local token = activeToken
	for _, child in ipairs(gui:GetChildren()) do child:Destroy() end
	local title, soundName = getTitle(count)

	local panel = Instance.new("Frame")
	panel.Name = "MultikillAnnouncement"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.54, 0)
	panel.Size = UDim2.new(0, 390, 0, 100)
	panel.BackgroundColor3 = Color3.fromRGB(74, 8, 32)
	panel.BackgroundTransparency = 0.14
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = panel

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -20, 1, -12)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.RichText = true
	label.Text = title .. "\n<b>+" .. tostring(baseScore) .. "</b> SCORE  <b>+" .. tostring(bonus) .. "</b> BONUS"
	label.TextColor3 = Color3.fromRGB(255, 211, 236)
	label.TextStrokeColor3 = Color3.fromRGB(44, 4, 20)
	label.TextStrokeTransparency = 0.18
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = panel

	playSound(soundName)
	TweenService:Create(label, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	task.delay(2.5, function()
		if token ~= activeToken or not panel.Parent then return end
		TweenService:Create(panel, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(panel, 0.35)
	end)
end)

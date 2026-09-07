-- MonsterGunUpgradeHud
-- A compact score-to-upgrade meter shown only while a MonsterGun tier is held.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local POINTS_PER_TIER = 100
local MG3_PROGRESS_BASELINE_ATTRIBUTE = "MonsterGun3ProgressBaseline"
local PROGRESS_ATTRIBUTES = { [1] = "MonsterGun1Points", [2] = "MonsterGun2Points" }
local MG_COLOR = Color3.fromRGB(255, 105, 180)
local EMPTY_COLOR = Color3.fromRGB(74, 25, 52)

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterGunUpgradeHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 100
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "UpgradeMeter"
panel.AnchorPoint = Vector2.new(1, 1)
panel.Position = UDim2.new(1, -24, 1, -72)
panel.Size = UDim2.fromOffset(382, 54)
panel.BackgroundTransparency = 1
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

-- ScoreGui halves its typography and cards in compact/mobile layout. The
-- upgrade meter deliberately follows the same breakpoint and proportion.
local responsiveScale = Instance.new("UIScale")
responsiveScale.Name = "ResponsiveScale"
responsiveScale.Parent = panel

local function updateResponsiveScale()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	responsiveScale.Scale = (viewport.X < 1100 or viewport.Y < 650) and 0.5 or 1
end

local function bindResponsiveScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale)
	end
	updateResponsiveScale()
end

bindResponsiveScale()

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 24)
title.Font = Enum.Font.GothamBold
title.Text = "MONSTERGUN 2 UPGRADE"
title.TextColor3 = MG_COLOR
title.TextSize = 19
title.TextXAlignment = Enum.TextXAlignment.Right
title.Parent = panel

local progressBar = Instance.new("Frame")
progressBar.Name = "ProgressBar"
progressBar.BackgroundColor3 = EMPTY_COLOR
progressBar.BackgroundTransparency = 0.78
progressBar.BorderSizePixel = 0
progressBar.Position = UDim2.fromOffset(0, 31)
progressBar.Size = UDim2.new(1, 0, 0, 18)
progressBar.Parent = panel
local progressStroke = Instance.new("UIStroke")
progressStroke.Color = MG_COLOR
progressStroke.Thickness = 1
progressStroke.Transparency = 0.55
progressStroke.Parent = progressBar
local progressFill = Instance.new("Frame")
progressFill.Name = "Fill"
progressFill.AnchorPoint = Vector2.new(0, 0.5)
progressFill.Position = UDim2.fromScale(0, 0.5)
progressFill.Size = UDim2.fromScale(0, 1)
progressFill.BackgroundColor3 = MG_COLOR
progressFill.BackgroundTransparency = 0.2
progressFill.BorderSizePixel = 0
progressFill.Parent = progressBar

local announcementToken = 0
local function showAnnouncement(text)
	announcementToken += 1
	local token = announcementToken
	local label = Instance.new("TextLabel")
	label.Name = "UpgradeAnnouncement"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.42)
	label.Size = UDim2.new(0.72, 0, 0, 68)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = MG_COLOR
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.TextTransparency = 1
	label.Parent = gui
	TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	task.delay(3, function()
		if token ~= announcementToken or not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		Debris:AddItem(label, 0.4)
	end)
end

local function playAchievementSound()
	local sound = SoundService:FindFirstChild("AchievementUnlock")
	if not sound or not sound:IsA("Sound") then return end
	local clone = sound:Clone()
	clone.Looped = false
	clone.Parent = SoundService
	clone:Play()
	Debris:AddItem(clone, math.max(3, clone.TimeLength + 1))
end

local function isMonsterGunEquipped()
	local character = player.Character
	if not character then return false end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and ({ MonsterGun = true, MonsterGun2 = true, MonsterGun3 = true })[child.Name] then
			return true
		end
	end
	return false
end

local function updateMeter()
	local tier = tonumber(player:GetAttribute("MonsterGunTier")) or 1
	panel.Visible = isMonsterGunEquipped() and tier < 3
	if tier >= 3 then return end
	title.Text = tier == 1 and "MONSTERGUN 2 UPGRADE" or "MONSTERGUN 3 UPGRADE"
	local progressAttribute = PROGRESS_ATTRIBUTES[tier]
	local progress = math.clamp(progressAttribute and (tonumber(player:GetAttribute(progressAttribute)) or 0) or 0, 0, POINTS_PER_TIER)
	progressFill.Size = UDim2.fromScale(progress / POINTS_PER_TIER, 1)
end

local function bindCharacter(character)
	character.ChildAdded:Connect(updateMeter)
	character.ChildRemoved:Connect(updateMeter)
	updateMeter()
end

player:GetAttributeChangedSignal("MonsterGunTier"):Connect(updateMeter)
player:GetAttributeChangedSignal(MG3_PROGRESS_BASELINE_ATTRIBUTE):Connect(updateMeter)
for _, attributeName in pairs(PROGRESS_ATTRIBUTES) do
	player:GetAttributeChangedSignal(attributeName):Connect(updateMeter)
end
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

ReplicatedStorage:WaitForChild("MonsterGunUpgradeUnlocked").OnClientEvent:Connect(function(tier)
	playAchievementSound()
	showAnnouncement("MonsterGun " .. tostring(tier) .. " Unlocked")
	updateMeter()
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local difficultySelectEvent = ReplicatedStorage:WaitForChild("DifficultySelect")
local INTRODUCTION_COMPLETE_ATTRIBUTE = "NightmareIntroductionComplete"

local gui = Instance.new("ScreenGui")
gui.Name = "DifficultySelectorHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 9000
pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
gui.Parent = player:WaitForChild("PlayerGui")

local difficultyButton = Instance.new("TextButton")
difficultyButton.Name = "DifficultyButton"
difficultyButton.AnchorPoint = Vector2.new(0, 1)
difficultyButton.Position = UDim2.new(0, 18, 1, -18)
difficultyButton.Size = UDim2.fromOffset(150, 40)
difficultyButton.BackgroundColor3 = Color3.fromRGB(28, 13, 43)
difficultyButton.BackgroundTransparency = 0.08
difficultyButton.BorderSizePixel = 0
difficultyButton.Font = Enum.Font.GothamBold
difficultyButton.Text = "DIFFICULTY"
difficultyButton.TextColor3 = Color3.fromRGB(246, 235, 255)
difficultyButton.TextSize = 15
difficultyButton.Visible = false
difficultyButton.ZIndex = 1
difficultyButton.Parent = gui
Instance.new("UICorner", difficultyButton).CornerRadius = UDim.new(0, 7)
local difficultyButtonStroke = Instance.new("UIStroke")
difficultyButtonStroke.Color = Color3.fromRGB(134, 70, 201)
difficultyButtonStroke.Transparency = 0.15
difficultyButtonStroke.Parent = difficultyButton

local difficultyShade = Instance.new("Frame")
difficultyShade.Name = "DifficultyShade"
difficultyShade.Size = UDim2.fromScale(1, 1)
difficultyShade.BackgroundColor3 = Color3.fromRGB(2, 0, 7)
difficultyShade.BackgroundTransparency = 0.18
difficultyShade.BorderSizePixel = 0
difficultyShade.Visible = false
difficultyShade.ZIndex = 10
difficultyShade.Parent = gui

local difficultyPanel = Instance.new("Frame")
difficultyPanel.Name = "Panel"
difficultyPanel.AnchorPoint = Vector2.new(0.5, 0.5)
difficultyPanel.Position = UDim2.fromScale(0.5, 0.5)
difficultyPanel.Size = UDim2.new(0.88, 0, 0, 260)
difficultyPanel.SizeConstraint = Enum.SizeConstraint.RelativeXX
difficultyPanel.BackgroundColor3 = Color3.fromRGB(12, 4, 25)
difficultyPanel.BorderSizePixel = 0
difficultyPanel.ZIndex = 11
difficultyPanel.Parent = difficultyShade
Instance.new("UICorner", difficultyPanel).CornerRadius = UDim.new(0, 12)
local panelSizeConstraint = Instance.new("UISizeConstraint")
panelSizeConstraint.MaxSize = Vector2.new(520, 260)
panelSizeConstraint.MinSize = Vector2.new(300, 230)
panelSizeConstraint.Parent = difficultyPanel
local difficultyPanelStroke = Instance.new("UIStroke")
difficultyPanelStroke.Color = Color3.fromRGB(134, 70, 201)
difficultyPanelStroke.Thickness = 2
difficultyPanelStroke.Transparency = 0.18
difficultyPanelStroke.Parent = difficultyPanel

local difficultyTitle = Instance.new("TextLabel")
difficultyTitle.Name = "Title"
difficultyTitle.BackgroundTransparency = 1
difficultyTitle.Position = UDim2.fromOffset(24, 28)
difficultyTitle.Size = UDim2.new(1, -48, 0, 44)
difficultyTitle.Font = Enum.Font.GothamBlack
difficultyTitle.Text = "CHOOSE YOUR NIGHTMARE"
difficultyTitle.TextColor3 = Color3.fromRGB(246, 235, 255)
difficultyTitle.TextScaled = true
difficultyTitle.TextWrapped = true
difficultyTitle.ZIndex = 12
difficultyTitle.Parent = difficultyPanel
local titleSizeConstraint = Instance.new("UITextSizeConstraint")
titleSizeConstraint.MaxTextSize = 25
titleSizeConstraint.MinTextSize = 16
titleSizeConstraint.Parent = difficultyTitle

local difficultyDetail = Instance.new("TextLabel")
difficultyDetail.Name = "Detail"
difficultyDetail.BackgroundTransparency = 1
difficultyDetail.Position = UDim2.fromOffset(24, 78)
difficultyDetail.Size = UDim2.new(1, -48, 0, 40)
difficultyDetail.Font = Enum.Font.Gotham
difficultyDetail.Text = "This choice lasts for the whole server session."
difficultyDetail.TextColor3 = Color3.fromRGB(173, 224, 255)
difficultyDetail.TextSize = 15
difficultyDetail.TextWrapped = true
difficultyDetail.ZIndex = 12
difficultyDetail.Parent = difficultyPanel

local function makeChoice(name, text, color, xScale)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(xScale, 0, 1, -28)
	button.Size = UDim2.new(0.38, 0, 0, 46)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 245, 255)
	button.TextSize = 16
	button.ZIndex = 12
	button.Parent = difficultyPanel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
	return button
end

local easyButton = makeChoice("EasyButton", "EASY", Color3.fromRGB(25, 105, 62), 0.27)
local hardButton = makeChoice("HardButton", "HARD", Color3.fromRGB(100, 28, 65), 0.73)
local choiceOpen = false
local windowOpen = false

local function closeChoice()
	choiceOpen = false
	difficultyShade.Visible = false
end

local function openChoice()
	if not windowOpen or player:GetAttribute("DifficultySelectionLocked") == true then return end
	choiceOpen = true
	difficultyShade.Visible = true
end

local function requestDifficulty(mode)
	if not choiceOpen or player:GetAttribute("DifficultySelectionLocked") == true then return end
	difficultySelectEvent:FireServer(mode)
	windowOpen = false
	difficultyButton.Visible = false
	closeChoice()
end

local function unlockDifficulty()
	if windowOpen or player:GetAttribute("DifficultySelectionLocked") == true then return end
	windowOpen = true
	difficultyButton.Visible = true
	task.delay(90, function()
		if not windowOpen then return end
		windowOpen = false
		difficultyButton.Visible = false
		closeChoice()
	end)
end

difficultyButton.Activated:Connect(openChoice)
easyButton.Activated:Connect(function() requestDifficulty("Easy") end)
hardButton.Activated:Connect(function() requestDifficulty("Hard") end)
player:GetAttributeChangedSignal(INTRODUCTION_COMPLETE_ATTRIBUTE):Connect(function()
	if player:GetAttribute(INTRODUCTION_COMPLETE_ATTRIBUTE) == true then unlockDifficulty() end
end)
player:GetAttributeChangedSignal("DifficultySelectionLocked"):Connect(function()
	if player:GetAttribute("DifficultySelectionLocked") ~= true then return end
	windowOpen = false
	difficultyButton.Visible = false
	closeChoice()
end)
if player:GetAttribute(INTRODUCTION_COMPLETE_ATTRIBUTE) == true then unlockDifficulty() end

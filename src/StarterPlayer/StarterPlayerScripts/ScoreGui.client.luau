local Players = game:GetService("Players")
local player = Players.LocalPlayer
local rs = game:GetService("ReplicatedStorage")
local camera = workspace.CurrentCamera

local scoreEvent = rs:WaitForChild("ScoreUpdate")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
pcall(function()
	screenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
screenGui.Parent = player:WaitForChild("PlayerGui")

local frame = Instance.new("Frame")
frame.Name = "ScoreFrame"
frame.Size = UDim2.new(0, 220, 0, 44)
frame.Position = UDim2.new(0, 12, 0, 70)
frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
frame.BackgroundTransparency = 0.4
frame.BorderSizePixel = 0
frame.Parent = screenGui

local label = Instance.new("TextLabel")
label.Name = "ScoreLabel"
label.Size = UDim2.new(1, 0, 1, 0)
label.BackgroundTransparency = 1
label.Text = player.Name .. ": 0"
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextSize = 18
label.Font = Enum.Font.GothamBold
label.Parent = frame

scoreEvent.OnClientEvent:Connect(function(score)
	label.Text = player.Name .. ": " .. tostring(score)
end)

local recordsButton = Instance.new("TextButton")
recordsButton.Name = "RecordsButton"
recordsButton.Size = UDim2.new(0, 96, 0, 32)
recordsButton.Position = UDim2.new(0, 12, 0, 112)
recordsButton.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
recordsButton.BackgroundTransparency = 0.35
recordsButton.BorderSizePixel = 0
recordsButton.Text = "Records"
recordsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
recordsButton.TextSize = 14
recordsButton.Font = Enum.Font.GothamBold
recordsButton.Visible = false
recordsButton.Parent = screenGui

local recordsFrame = Instance.new("Frame")
recordsFrame.Name = "RecordsFrame"
recordsFrame.Size = UDim2.new(0, 330, 0, 110)
recordsFrame.Position = UDim2.new(0, 12, 0, 120)
recordsFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
recordsFrame.BackgroundTransparency = 0.4
recordsFrame.BorderSizePixel = 0
recordsFrame.Parent = screenGui

local recordsLabel = Instance.new("TextLabel")
recordsLabel.Name = "RecordsLabel"
recordsLabel.Size = UDim2.new(1, -12, 1, -10)
recordsLabel.Position = UDim2.new(0, 6, 0, 5)
recordsLabel.BackgroundTransparency = 1
recordsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
recordsLabel.TextXAlignment = Enum.TextXAlignment.Left
recordsLabel.TextYAlignment = Enum.TextYAlignment.Top
recordsLabel.TextSize = 15
recordsLabel.Font = Enum.Font.Gotham
recordsLabel.Text = "Forest of Horrors records:\nYour best: 0\nServer best: - 0\nForest best ever: - 0"
recordsLabel.Parent = recordsFrame
recordsLabel.RichText = true

local recordsOpen = false

local function isSmallScreen()
	local size = camera.ViewportSize
	return size.X < 800 or size.Y < 500
end

local function applyLayout()
	local small = isSmallScreen()

	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Size = small and UDim2.new(0, 190, 0, 30) or UDim2.new(0, 230, 0, 34)
	frame.Position = UDim2.new(1, -12, 0, 50)
	frame.BackgroundTransparency = 0.28
	label.TextSize = small and 14 or 16
	label.TextXAlignment = Enum.TextXAlignment.Center

	recordsButton.AnchorPoint = Vector2.new(1, 0)
	recordsButton.Size = UDim2.new(0, 92, 0, 28)
	recordsButton.Position = UDim2.new(1, -12, 0, 88)
	recordsButton.TextSize = 13
	recordsButton.Visible = true

	recordsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	recordsFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	recordsFrame.Size = small and UDim2.new(0.86, 0, 0, 132) or UDim2.new(0, 380, 0, 132)
	recordsFrame.Visible = recordsOpen
	recordsLabel.TextSize = small and 16 or 17
end

recordsButton.MouseButton1Click:Connect(function()
	recordsOpen = not recordsOpen
	applyLayout()
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
applyLayout()

local recordsEvent = rs:WaitForChild("RecordsUpdate", 5)
if recordsEvent then
	recordsEvent.OnClientEvent:Connect(function(data)
		recordsLabel.Text =
			"\nGame's Best: <b>" .. tostring(data.serverBestPlayerName) .. " (" .. tostring(data.serverBestScore) .. ")" .. " — spawn " .. tostring(data.serverBestSpawn) ..
			"</b>\nYour Best: <b>" .. tostring(data.personalBestScore) ..
			"</b>\nAll Time Leader: <b>" .. tostring(data.bestEverPlayerName) .. " (" .. tostring(data.bestEverScore) .. ")</b>"
	end)
else
	warn("RecordsUpdate RemoteEvent was not found. Records HUD will stay at 0.")
end

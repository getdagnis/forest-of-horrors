local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local monsterCountEvent = ReplicatedStorage:WaitForChild("MonsterCountUpdate")
local camera = workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "MonsterCounter"
label.AnchorPoint = Vector2.new(1, 1)
label.Position = UDim2.new(1, -24, 1, -24)
label.Size = UDim2.new(0, 260, 0, 42)
label.BackgroundTransparency = 0.35
label.BackgroundColor3 = Color3.fromRGB(134, 13, 59)
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = "Alive monsters: counting..."
label.Parent = gui

local lastCount = nil

local function isSmallScreen()
	local size = camera.ViewportSize
	return size.X < 800 or size.Y < 500
end

local function applyLayout()
	local small = isSmallScreen()

	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -12, 0, 16)
	label.Size = small and UDim2.new(0, 150, 0, 30) or UDim2.new(0, 190, 0, 34)
	label.BackgroundTransparency = 0.28
	label.TextScaled = false
	label.TextSize = small and 14 or 16
	label.Text = lastCount and ("Monsters: " .. tostring(lastCount)) or "Monsters: ..."
end

monsterCountEvent.OnClientEvent:Connect(function(count)
	lastCount = count
	applyLayout()
end)

camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
applyLayout()

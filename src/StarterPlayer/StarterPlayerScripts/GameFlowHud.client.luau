local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local roundCompleteEvent = ReplicatedStorage:WaitForChild("RoundComplete")
local roundRestartedEvent = ReplicatedStorage:WaitForChild("RoundRestarted")
local restartRoundEvent = ReplicatedStorage:WaitForChild("RestartRound")

local gui = Instance.new("ScreenGui")
gui.Name = "GameFlowHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui.Parent = player:WaitForChild("PlayerGui")

local function makePanel(name)
	local shade = Instance.new("Frame")
	shade.Name = name
	shade.Size = UDim2.new(1, 0, 1, 0)
	shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0.82, 0, 0, 260)
	panel.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = shade

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	return shade, panel
end

local welcomeShade, welcomePanel = makePanel("WelcomePanel")

local welcomeText = Instance.new("TextLabel")
welcomeText.BackgroundTransparency = 1
welcomeText.Size = UDim2.new(1, -36, 0, 150)
welcomeText.Position = UDim2.new(0, 18, 0, 28)
welcomeText.Font = Enum.Font.GothamBold
welcomeText.TextColor3 = Color3.fromRGB(255, 255, 255)
welcomeText.TextWrapped = true
welcomeText.TextScaled = true
welcomeText.Text = "Your life's been hard so you took a pill to live in a dream but now you are living in a nightmare."
welcomeText.Parent = welcomePanel

local okButton = Instance.new("TextButton")
okButton.AnchorPoint = Vector2.new(0.5, 1)
okButton.Position = UDim2.new(0.5, 0, 1, -24)
okButton.Size = UDim2.new(0, 120, 0, 44)
okButton.BackgroundColor3 = Color3.fromRGB(208, 18, 90)
okButton.BorderSizePixel = 0
okButton.Font = Enum.Font.GothamBold
okButton.Text = "..."
okButton.TextColor3 = Color3.fromRGB(255, 255, 255)
okButton.TextSize = 24
okButton.Parent = welcomePanel

local okCorner = Instance.new("UICorner")
okCorner.CornerRadius = UDim.new(0, 10)
okCorner.Parent = okButton

okButton.MouseButton1Click:Connect(function()
	welcomeShade.Visible = false
end)

local endShade, endPanel = makePanel("RoundCompletePanel")
endShade.Visible = false

local endTitle = Instance.new("TextLabel")
endTitle.BackgroundTransparency = 1
endTitle.Size = UDim2.new(1, -36, 0, 58)
endTitle.Position = UDim2.new(0, 18, 0, 18)
endTitle.Font = Enum.Font.GothamBlack
endTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
endTitle.TextScaled = true
endTitle.Text = "Round completed"
endTitle.Parent = endPanel

local endMessage = Instance.new("TextLabel")
endMessage.BackgroundTransparency = 1
endMessage.Size = UDim2.new(1, -36, 0, 44)
endMessage.Position = UDim2.new(0, 18, 0, 76)
endMessage.Font = Enum.Font.GothamBold
endMessage.TextColor3 = Color3.fromRGB(255, 238, 150)
endMessage.TextScaled = true
endMessage.Text = "Congrats. The forest is clear."
endMessage.Parent = endPanel

local leaderboard = Instance.new("TextLabel")
leaderboard.BackgroundTransparency = 1
leaderboard.Size = UDim2.new(1, -36, 0, 86)
leaderboard.Position = UDim2.new(0, 18, 0, 126)
leaderboard.Font = Enum.Font.Gotham
leaderboard.TextColor3 = Color3.fromRGB(255, 255, 255)
leaderboard.TextScaled = true
leaderboard.TextXAlignment = Enum.TextXAlignment.Left
leaderboard.TextYAlignment = Enum.TextYAlignment.Top
leaderboard.Text = ""
leaderboard.Parent = endPanel

local restartButton = Instance.new("TextButton")
restartButton.AnchorPoint = Vector2.new(0.5, 1)
restartButton.Position = UDim2.new(0.5, 0, 1, -24)
restartButton.Size = UDim2.new(0, 210, 0, 44)
restartButton.BackgroundColor3 = Color3.fromRGB(208, 18, 90)
restartButton.BorderSizePixel = 0
restartButton.Font = Enum.Font.GothamBold
restartButton.Text = "Continue / Restart"
restartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
restartButton.TextSize = 18
restartButton.Parent = endPanel

local restartCorner = Instance.new("UICorner")
restartCorner.CornerRadius = UDim.new(0, 10)
restartCorner.Parent = restartButton

local function formatLeaderboard(list)
	local lines = {}

	for index, row in ipairs(list or {}) do
		if index > 5 then break end
		table.insert(lines, tostring(index) .. ". " .. tostring(row.name) .. " — " .. tostring(row.score))
	end

	if #lines == 0 then
		return "No scores yet."
	end

	return table.concat(lines, "\n")
end

roundCompleteEvent.OnClientEvent:Connect(function(data)
	restartButton.Text = "Continue / Restart"
	leaderboard.Text = formatLeaderboard(data and data.scoreboard)
	endShade.Visible = true
end)

roundRestartedEvent.OnClientEvent:Connect(function()
	restartButton.Text = "Continue / Restart"
	endShade.Visible = false
end)

restartButton.MouseButton1Click:Connect(function()
	restartButton.Text = "Restarting..."
	restartRoundEvent:FireServer()
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local roundCompleteEvent = ReplicatedStorage:WaitForChild("RoundComplete")
local roundRestartedEvent = ReplicatedStorage:WaitForChild("RoundRestarted")
local restartRoundEvent = ReplicatedStorage:WaitForChild("RestartRound")

-- Wait for the instance-based GameFlowHud ScreenGui that gets cloned from StarterGui into PlayerGui
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GameFlowHud")

local welcomeShade = gui:WaitForChild("WelcomePanel")
local welcomePanel = welcomeShade:WaitForChild("Panel")
local okButton = welcomePanel:WaitForChild("OkButton")

local endShade = gui:WaitForChild("RoundCompletePanel")
local endPanel = endShade:WaitForChild("Panel")
local endTitle = endPanel:WaitForChild("EndTitle")
local endMessage = endPanel:WaitForChild("EndMessage")
local leaderboard = endPanel:WaitForChild("Leaderboard")
local restartButton = endPanel:WaitForChild("RestartButton")

-- Hide the Roblox default backpack/inventory while the welcome panel is visible
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local function closeWelcome()
	if not welcomeShade.Visible then return end
	welcomeShade.Visible = false
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
end

-- Activated covers mouse, touch, gamepad, and keyboard. The input fallback is
-- deliberate: a legacy full-screen GUI above the button must not trap a new
-- player inside the welcome screen.
okButton.Activated:Connect(closeWelcome)
UserInputService.InputBegan:Connect(function(input)
	if not welcomeShade.Visible then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.Return
		or input.KeyCode == Enum.KeyCode.Space
		or input.KeyCode == Enum.KeyCode.Escape
	then
		closeWelcome()
	end
end)

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

local function showRoundFailure(data)
	endTitle.Text = "The nightmare won"
	endMessage.Text = (data and data.message) or "Time ran out. The forest is still hunting."
	leaderboard.Text = formatLeaderboard(data and data.scoreboard)
	restartButton.Text = "Quick Restart"
	endShade.Visible = true
end

roundCompleteEvent.OnClientEvent:Connect(function(data)
	endTitle.Text = "Round completed"
	endMessage.Text = "Congrats. The forest is clear."
	restartButton.Text = "Continue / Restart"
	leaderboard.Text = formatLeaderboard(data and data.scoreboard)
	endShade.Visible = true
end)

-- RoundFailed is created by the server round controller in newer places. Do not
-- block the existing completion HUD in older places where it does not exist yet.
local roundFailedBound = false
local function bindRoundFailed(instance)
	if roundFailedBound or not (instance and instance.Name == "RoundFailed" and instance:IsA("RemoteEvent")) then return end
	roundFailedBound = true
	instance.OnClientEvent:Connect(showRoundFailure)
end
bindRoundFailed(ReplicatedStorage:FindFirstChild("RoundFailed"))
ReplicatedStorage.ChildAdded:Connect(bindRoundFailed)

roundRestartedEvent.OnClientEvent:Connect(function()
	restartButton.Text = "Continue / Restart"
	endShade.Visible = false
end)

restartButton.MouseButton1Click:Connect(function()
	restartButton.Text = "Restarting..."
	restartRoundEvent:FireServer()
end)

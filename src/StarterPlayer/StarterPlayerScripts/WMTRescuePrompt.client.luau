-- Place as StarterPlayer.StarterPlayerScripts.WMTRescuePrompt.
-- The server remains authoritative; this only renders and returns a choice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local rescueEvent = ReplicatedStorage:WaitForChild("WMTRescueOffer")
local rescueResponseEvent = ReplicatedStorage:WaitForChild("WMTRescueResponse")
local petLostEvent = ReplicatedStorage:WaitForChild("WMTGuardianPetLost")

local gui = Instance.new("ScreenGui")
gui.Name = "WMTRescuePrompt"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.64)
panel.Size = UDim2.fromOffset(420, 116)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = gui

local text = Instance.new("TextLabel")
text.Size = UDim2.new(1, 0, 0, 48)
text.Position = UDim2.fromOffset(0, 0)
text.BackgroundTransparency = 1
text.Font = Enum.Font.GothamBold
text.TextColor3 = Color3.fromRGB(230, 255, 180)
text.TextSize = 26
text.Parent = panel

local function makeButton(name, label, position, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = UDim2.fromOffset(150, 38)
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.TextColor3 = color
	button.TextSize = 21
	button.Parent = panel
	return button
end

local accept = makeButton("Accept", "accept", UDim2.fromOffset(48, 62), Color3.fromRGB(190, 255, 75))
local decline = makeButton("NoWay", "no way", UDim2.fromOffset(222, 62), Color3.fromRGB(255, 180, 180))
local offeredGuardian

local lossText = Instance.new("TextLabel")
lossText.Name = "PetLostText"
lossText.AnchorPoint = Vector2.new(0.5, 0.5)
lossText.Position = UDim2.fromScale(0.5, 0.42)
lossText.Size = UDim2.fromOffset(520, 52)
lossText.BackgroundTransparency = 1
lossText.Font = Enum.Font.GothamBold
lossText.Text = "your guardian pet has fallen"
lossText.TextColor3 = Color3.fromRGB(255, 105, 105)
lossText.TextStrokeTransparency = 0.25
lossText.TextSize = 28
lossText.Visible = false
lossText.Parent = gui
local lossToken = 0

local function respond(accepted)
	if not offeredGuardian then return end
	rescueResponseEvent:FireServer(offeredGuardian, accepted)
	offeredGuardian = nil
	panel.Visible = false
end

accept.Activated:Connect(function() respond(true) end)
decline.Activated:Connect(function() respond(false) end)

rescueEvent.OnClientEvent:Connect(function(guardian, message)
	if not guardian or not guardian:IsA("Model") then return end
	offeredGuardian = guardian
	text.Text = typeof(message) == "string" and message or "It wants to be your pet."
	panel.Visible = true
end)

petLostEvent.OnClientEvent:Connect(function()
	lossToken += 1
	local token = lossToken
	lossText.Visible = true
	task.delay(3, function()
		if token == lossToken then lossText.Visible = false end
	end)
end)

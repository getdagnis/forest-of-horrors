-- Place as StarterPlayer.StarterPlayerScripts.WMTRescuePrompt.
-- The server remains authoritative; this only renders and returns a choice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local rescueEvent = ReplicatedStorage:WaitForChild("WMTRescueOffer")
local rescueResponseEvent = ReplicatedStorage:WaitForChild("WMTRescueResponse")

local gui = Instance.new("ScreenGui")
gui.Name = "WMTRescuePrompt"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.64)
panel.Size = UDim2.fromOffset(420, 150)
panel.BackgroundColor3 = Color3.fromRGB(22, 16, 29)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local text = Instance.new("TextLabel")
text.Size = UDim2.new(1, -32, 0, 74)
text.Position = UDim2.fromOffset(16, 12)
text.BackgroundTransparency = 1
text.Font = Enum.Font.GothamBold
text.TextColor3 = Color3.fromRGB(255, 235, 250)
text.TextScaled = true
text.TextWrapped = true
text.Parent = panel

local function makeButton(name, label, position, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = UDim2.fromOffset(176, 42)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextSize = 18
	button.Parent = panel
	Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
	return button
end

local accept = makeButton("Accept", "Accept", UDim2.fromOffset(20, 96), Color3.fromRGB(70, 130, 86))
local decline = makeButton("NoWay", "No way", UDim2.fromOffset(224, 96), Color3.fromRGB(117, 52, 65))
local offeredGuardian

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
	text.Text = typeof(message) == "string" and message or "This weird monster thing wants to become your pet"
	panel.Visible = true
end)

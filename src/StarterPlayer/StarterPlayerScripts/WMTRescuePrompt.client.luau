-- Place as StarterPlayer.StarterPlayerScripts.WMTRescuePrompt.
-- The server remains authoritative; this only renders and returns a choice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local GUARDIAN_COLOR = Color3.fromRGB(220, 240, 210)
local rescueEvent = ReplicatedStorage:WaitForChild("WMTRescueOffer")
local rescueResponseEvent = ReplicatedStorage:WaitForChild("WMTRescueResponse")
local rescueResultEvent = ReplicatedStorage:WaitForChild("WMTRescueResult")
local petLostEvent = ReplicatedStorage:WaitForChild("WMTGuardianPetLost")
local conversationEvent = ReplicatedStorage:WaitForChild("WMTGuardianConversation")
-- Optional while older Studio places are still being updated. This HUD must
-- never hold up the established rescue/trust prompt if the remote is absent.
local guardianStatusEvent = ReplicatedStorage:FindFirstChild("WMTGuardianStatus")

local gui = Instance.new("ScreenGui")
gui.Name = "WMTRescuePrompt"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.fromScale(0.5, 0.42)
panel.Size = UDim2.fromOffset(420, 104)
panel.BackgroundTransparency = 1
panel.Visible = false
panel.Parent = gui

local text = Instance.new("TextLabel")
text.Size = UDim2.new(1, 0, 0, 48)
text.Position = UDim2.fromOffset(0, 0)
text.BackgroundTransparency = 1
text.Font = Enum.Font.GothamBold
text.TextColor3 = GUARDIAN_COLOR
text.TextSize = 28
text.Visible = false -- GuardianAnswer is the one shared message line.
text.Parent = panel

local function makeButton(name, label, position, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = position
	button.Size = UDim2.fromOffset(150, 38)
	button.BackgroundColor3 = Color3.fromRGB(24, 32, 29)
	button.BackgroundTransparency = 0.12
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.TextColor3 = color
	button.TextSize = 18
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = button
	return button
end

local accept = makeButton("Accept", "accept", UDim2.fromOffset(48, 50), Color3.fromRGB(190, 255, 75))
local decline = makeButton("Refuse", "refuse", UDim2.fromOffset(222, 50), Color3.fromRGB(255, 180, 180))
local offeredGuardian
local waitingForAcceptance = false
local offerToken = 0
local CLIENT_OFFER_TIMEOUT = 17

local lossText = Instance.new("TextLabel")
lossText.Name = "PetLostText"
lossText.AnchorPoint = Vector2.new(0.5, 0.5)
lossText.Position = UDim2.fromScale(0.5, 0.42)
lossText.Size = UDim2.fromOffset(520, 52)
lossText.BackgroundTransparency = 1
lossText.Font = Enum.Font.GothamBold
lossText.Text = "your guardian pet has fallen"
lossText.TextColor3 = GUARDIAN_COLOR
lossText.TextStrokeTransparency = 0.25
lossText.TextSize = 28
lossText.Visible = false
lossText.Parent = gui
local lossToken = 0

-- Quiet ritual feedback: deliberately placed above the standard hotbar rather
-- than competing with the larger round announcements in the centre of screen.
local conversation = Instance.new("Frame")
conversation.Name = "GuardianConversation"
conversation.AnchorPoint = Vector2.new(0.5, 1)
conversation.Position = UDim2.fromScale(0.5, 0.84)
conversation.Size = UDim2.fromOffset(260, 34)
conversation.BackgroundTransparency = 1
conversation.Visible = false
conversation.Parent = gui

local conversationText = Instance.new("TextLabel")
conversationText.Name = "Text"
conversationText.Position = UDim2.fromOffset(0, 0)
conversationText.Size = UDim2.new(1, 0, 0, 17)
conversationText.BackgroundTransparency = 1
conversationText.Font = Enum.Font.GothamBold
conversationText.Text = "TALKING"
conversationText.TextColor3 = GUARDIAN_COLOR
conversationText.TextSize = 13
conversationText.TextStrokeTransparency = 0.65
conversationText.Parent = conversation

local bar = Instance.new("Frame")
bar.Name = "ProgressBar"
bar.Position = UDim2.fromOffset(0, 23)
bar.Size = UDim2.new(1, 0, 0, 5)
bar.BackgroundColor3 = GUARDIAN_COLOR
bar.BackgroundTransparency = 0.78
bar.BorderSizePixel = 0
bar.Parent = conversation

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = GUARDIAN_COLOR
fill.BackgroundTransparency = 0.28
fill.BorderSizePixel = 0
fill.Parent = bar

local answerText = Instance.new("TextLabel")
answerText.Name = "GuardianAnswer"
answerText.AnchorPoint = Vector2.new(0.5, 0.5)
answerText.Position = UDim2.fromScale(0.5, 0.42)
answerText.Size = UDim2.new(0.72, 0, 0, 68)
answerText.BackgroundTransparency = 1
answerText.Font = Enum.Font.GothamBold
answerText.TextColor3 = GUARDIAN_COLOR
answerText.TextStrokeTransparency = 0
answerText.TextSize = 28
answerText.TextWrapped = true
answerText.TextTransparency = 1
answerText.Visible = false
answerText.Parent = gui

local conversationGuardian
local conversationStartedAt = 0
local conversationDuration = 0
local answerToken = 0

-- Tactical pet feedback shares the quiet hotbar-adjacent lane, but is a
-- separate label so it cannot interfere with the conversation progress UI.
local statusText = Instance.new("TextLabel")
statusText.Name = "GuardianStatus"
statusText.AnchorPoint = Vector2.new(0.5, 1)
statusText.Position = UDim2.fromScale(0.5, 0.84)
statusText.Size = UDim2.new(0.72, 0, 0, 26)
statusText.BackgroundTransparency = 1
statusText.Font = Enum.Font.GothamBold
statusText.TextColor3 = GUARDIAN_COLOR
statusText.TextStrokeTransparency = 0.72
statusText.TextTransparency = 1
statusText.TextWrapped = true
statusText.Visible = false
statusText.Parent = gui
local statusToken = 0

local function updateStatusTextSize()
	local camera = workspace.CurrentCamera
	local mobile = camera and (camera.ViewportSize.X < 1100 or camera.ViewportSize.Y < 650)
	statusText.TextSize = mobile and 13 or 19
end

local function hideStatus()
	statusToken += 1
	statusText.Visible = false
	statusText.TextTransparency = 1
end

local function statusIsSuppressed()
	return conversation.Visible or panel.Visible or lossText.Visible
end

local function showStatus(message, quoted)
	if statusIsSuppressed() then return end
	statusToken += 1
	local token = statusToken
	statusText.Text = quoted and string.format('"%s"', message) or tostring(message)
	statusText.TextTransparency = 1
	statusText.Visible = true
	TweenService:Create(statusText, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0.08,
	}):Play()
	task.delay(4, function()
		if token ~= statusToken or not statusText.Parent or statusIsSuppressed() then return end
		local fade = TweenService:Create(statusText, TweenInfo.new(0.3), {
			TextTransparency = 1,
		})
		fade:Play()
		fade.Completed:Wait()
		if token == statusToken then statusText.Visible = false end
	end)
end

updateStatusTextSize()
local statusCameraConnection
local function bindStatusCamera(camera)
	if statusCameraConnection then
		statusCameraConnection:Disconnect()
		statusCameraConnection = nil
	end
	if camera then
		statusCameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateStatusTextSize)
	end
end
bindStatusCamera(workspace.CurrentCamera)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	updateStatusTextSize()
	bindStatusCamera(workspace.CurrentCamera)
end)

panel:GetPropertyChangedSignal("Visible"):Connect(function()
	if panel.Visible then hideStatus() end
end)
conversation:GetPropertyChangedSignal("Visible"):Connect(function()
	if conversation.Visible then hideStatus() end
end)
lossText:GetPropertyChangedSignal("Visible"):Connect(function()
	if lossText.Visible then hideStatus() end
end)
player.CharacterAdded:Connect(hideStatus)

local function stopConversation(guardian)
	if guardian and guardian ~= conversationGuardian then return end
	conversationGuardian = nil
	conversation.Visible = false
	fill.Size = UDim2.fromScale(0, 1)
end

local function startConversation(guardian, duration)
	if not guardian or not guardian:IsA("Model") then return end
	if conversationGuardian == guardian and conversation.Visible then return end
	conversationGuardian = guardian
	conversationDuration = math.max(0.1, tonumber(duration) or 10)
	conversationStartedAt = os.clock()
	conversation.Visible = true
	fill.Size = UDim2.fromScale(0, 1)
end

local function hideAnswer()
	answerToken += 1
	answerText.Visible = false
end

local function showAnswer(message, persistent)
	answerToken += 1
	local token = answerToken
	answerText.Text = tostring(message)
	answerText.Visible = true
	answerText.TextTransparency = 1
	answerText.TextStrokeTransparency = 1
	TweenService:Create(answerText, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0,
	}):Play()
	if persistent then return end
	task.delay(2.5, function()
		if token ~= answerToken or not answerText.Parent then return end
		local fade = TweenService:Create(answerText, TweenInfo.new(0.25), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fade:Play()
		fade.Completed:Wait()
		if token == answerToken then answerText.Visible = false end
	end)
end

RunService.RenderStepped:Connect(function()
	if not conversation.Visible or conversationDuration <= 0 then return end
	local progress = math.clamp((os.clock() - conversationStartedAt) / conversationDuration, 0, 1)
	fill.Size = UDim2.fromScale(progress, 1)
end)

local function respond(accepted)
	if not offeredGuardian or waitingForAcceptance then return end
	rescueResponseEvent:FireServer(offeredGuardian, accepted)
	if accepted then
		-- Pet conversion is server-authoritative. Keep the offer visible until its
		-- exact guardian confirms success, rather than looking like an acceptance
		-- succeeded when a stale or invalid offer was rejected.
		waitingForAcceptance = true
		accept.Active = false
	else
		offeredGuardian = nil
		panel.Visible = false
		hideAnswer()
	end
end

local function clearOfferUi(guardian)
	if guardian and guardian ~= offeredGuardian then return end
	offerToken += 1
	offeredGuardian = nil
	waitingForAcceptance = false
	accept.Active = true
	decline.Active = true
	panel.Visible = false
	hideAnswer()
end

accept.Activated:Connect(function() respond(true) end)
decline.Activated:Connect(function() respond(false) end)

rescueEvent.OnClientEvent:Connect(function(guardian, message)
	if not guardian or not guardian:IsA("Model") then return end
	offeredGuardian = guardian
	waitingForAcceptance = false
	accept.Active = true
	text.Text = typeof(message) == "string" and message or "It wants to be your pet."
	panel.Visible = true
	showAnswer(string.format('"%s"', text.Text), true)
	offerToken += 1
	local token = offerToken
	task.delay(CLIENT_OFFER_TIMEOUT, function()
		if token == offerToken and offeredGuardian == guardian then
			clearOfferUi(guardian)
		end
	end)
end)

rescueResultEvent.OnClientEvent:Connect(function(guardian, accepted, reason)
	if guardian ~= offeredGuardian then return end
	clearOfferUi(guardian)
	if not accepted and typeof(reason) == "string" and reason ~= "" then
		showAnswer(reason, false)
	end
end)

player.CharacterAdded:Connect(function()
	clearOfferUi()
end)

petLostEvent.OnClientEvent:Connect(function()
	lossToken += 1
	local token = lossToken
	lossText.Visible = true
	task.delay(3, function()
		if token == lossToken then lossText.Visible = false end
	end)
end)

conversationEvent.OnClientEvent:Connect(function(action, guardian, value, keepConversationVisible)
	if action == "start" and guardian and guardian:IsA("Model") then
		startConversation(guardian, value)
	elseif action == "stop" then
		stopConversation(guardian)
	elseif action == "answer" then
		if not keepConversationVisible then stopConversation(guardian) end
		showAnswer(string.format("\"%s\"", tostring(value)))
	end
end)

local statusBound = false
local function bindStatusEvent(event)
	if statusBound or event.Name ~= "WMTGuardianStatus" or not event:IsA("RemoteEvent") then return end
	statusBound = true
	event.OnClientEvent:Connect(function(_guardianModel, stateName, message)
		-- The guardian model may not be streamed to this client yet; the server is
		-- authoritative for ownership, while this client only accepts display text.
		if typeof(stateName) ~= "string" or typeof(message) ~= "string" or message == "" then return end
		showStatus(message, stateName ~= "Kill")
	end)
end
ReplicatedStorage.ChildAdded:Connect(bindStatusEvent)
if guardianStatusEvent then bindStatusEvent(guardianStatusEvent) end

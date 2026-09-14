-- Place as StarterPlayer.StarterPlayerScripts.WMTRescuePrompt.
-- The server remains authoritative; this only renders and returns a choice.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local GUARDIAN_COLOR = Color3.fromRGB(220, 240, 210)
local rescueEvent = ReplicatedStorage:WaitForChild("WMTRescueOffer")
local rescueResponseEvent = ReplicatedStorage:WaitForChild("WMTRescueResponse")
local rescueResultEvent = ReplicatedStorage:WaitForChild("WMTRescueResult")
local petLostEvent = ReplicatedStorage:WaitForChild("WMTGuardianPetLost")
local conversationEvent = ReplicatedStorage:WaitForChild("WMTGuardianConversation")
local petCommandEvent = ReplicatedStorage:WaitForChild("WMTGuardianPetCommand")
local petCommandResultEvent = ReplicatedStorage:WaitForChild("WMTGuardianPetCommandResult")
-- Optional while older Studio places are still being updated. This HUD must
-- never hold up the established rescue/trust prompt if the remote is absent.
local guardianStatusEvent = ReplicatedStorage:FindFirstChild("WMTGuardianStatus")

local function activeGeneration()
	local generation = workspace:GetAttribute("RoundGeneration")
	return workspace:GetAttribute("RoundState") == "Active" and typeof(generation) == "number" and generation or nil
end

local function isPlayable()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return activeGeneration() ~= nil and player:GetAttribute("EscapedNightmare") ~= true
		and humanoid ~= nil and humanoid.Health > 0
end

local function getRoot(model)
	if not model or not model:IsA("Model") then return nil end
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
end

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
local offeredGeneration
local offeredAttempt
local panelMode
local waitingForAcceptance = false
local offerToken = 0
local commandGuardian
local commandGeneration
local commandWaiting = false
local requestCounter = 0
local pendingPetCommand

local lossText = Instance.new("TextLabel")
lossText.Name = "PetLostText"
lossText.AnchorPoint = Vector2.new(0.5, 0.5)
lossText.Position = UDim2.fromScale(0.5, 0.42)
lossText.Size = UDim2.fromOffset(520, 52)
lossText.BackgroundTransparency = 1
lossText.Font = Enum.Font.GothamBold
lossText.Text = "your guardian pet has fallen!!!"
lossText.TextColor3 = GUARDIAN_COLOR
lossText.TextStrokeTransparency = 0.25
lossText.TextSize = 32
lossText.Visible = false
lossText.Parent = gui
local lossToken = 0

-- Quiet ritual feedback: deliberately placed above the standard hotbar rather
-- than competing with the larger round announcements in the centre of screen.
local conversation = Instance.new("Frame")
conversation.Name = "GuardianConversation"
conversation.AnchorPoint = Vector2.new(0.5, 1)
conversation.Position = UDim2.fromScale(0.5, 0.84)
conversation.Size = UDim2.fromOffset(320, 52)
conversation.BackgroundTransparency = 1
conversation.Visible = false
conversation.Parent = gui

local conversationText = Instance.new("TextLabel")
conversationText.Name = "Text"
conversationText.Position = UDim2.fromOffset(0, 0)
conversationText.Size = UDim2.new(1, 0, 0, 34)
conversationText.BackgroundTransparency = 1
conversationText.Font = Enum.Font.GothamBold
conversationText.Text = "talking"
conversationText.TextColor3 = GUARDIAN_COLOR
conversationText.TextSize = 28
conversationText.TextStrokeTransparency = 0.65
conversationText.Parent = conversation

local bar = Instance.new("Frame")
bar.Name = "ProgressBar"
bar.Position = UDim2.fromOffset(0, 42)
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
local conversationGeneration
local conversationAttempt
local latestAttemptByGuardian = setmetatable({}, { __mode = "k" })
local completedAttemptByGuardian = setmetatable({}, { __mode = "k" })
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
	if not isPlayable() or statusIsSuppressed() then return end
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
	conversationGeneration = nil
	conversationAttempt = nil
	conversation.Visible = false
	fill.Size = UDim2.fromScale(0, 1)
end

local function startConversation(guardian, duration, generation, attemptId)
	if not guardian or not guardian:IsA("Model") or generation ~= activeGeneration() then return end
	answerToken += 1
	answerText.Visible = false
	conversationGuardian = guardian
	conversationGeneration = generation
	conversationAttempt = attemptId
	conversationDuration = math.max(0.1, tonumber(duration) or 7)
	conversationStartedAt = os.clock()
	conversation.Visible = true
	fill.Size = UDim2.fromScale(0, 1)
end

local function hideAnswer()
	answerToken += 1
	answerText.Visible = false
end

local function showAnswer(message, persistent, duration)
	if not isPlayable() then return end
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
	task.delay(duration or 1.25, function()
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

local function acceptAttempt(guardian, attemptId, isStart)
	if typeof(attemptId) ~= "number" then return false end
	if attemptId <= (completedAttemptByGuardian[guardian] or 0) then return false end
	local latest = latestAttemptByGuardian[guardian]
	if latest and (isStart and attemptId <= latest or not isStart and attemptId < latest) then return false end
	if not latest or attemptId > latest then latestAttemptByGuardian[guardian] = attemptId end
	return true
end

RunService.RenderStepped:Connect(function()
	if not conversation.Visible or conversationDuration <= 0 then return end
	local progress = math.clamp((os.clock() - conversationStartedAt) / conversationDuration, 0, 1)
	fill.Size = UDim2.fromScale(progress, 1)
end)

local clearOfferUi
local function respond(accepted)
	if not isPlayable() or panelMode ~= "offer" or not offeredGuardian or waitingForAcceptance then return end
	rescueResponseEvent:FireServer(offeredGuardian, accepted, offeredGeneration, offeredAttempt)
	if accepted then
		-- Pet conversion is server-authoritative. Keep the offer visible until its
		-- exact guardian confirms success, rather than looking like an acceptance
		-- succeeded when a stale or invalid offer was rejected.
		waitingForAcceptance = true
		accept.Active = false
		local guardian, generation, attempt = offeredGuardian, offeredGeneration, offeredAttempt
		task.delay(5, function()
			if panelMode == "offer" and waitingForAcceptance and offeredGuardian == guardian and offeredGeneration == generation and offeredAttempt == attempt then
				clearOfferUi()
				showAnswer("the guardian did not respond. try again", false, 3)
			end
		end)
	else
		-- Keep the attempt until the server acknowledges the refusal too. That
		-- lets its terminal reply be shown rather than disappearing silently.
		waitingForAcceptance = true
		accept.Active = false
		decline.Active = false
		local guardian, generation, attempt = offeredGuardian, offeredGeneration, offeredAttempt
		task.delay(5, function()
			if panelMode == "offer" and waitingForAcceptance and offeredGuardian == guardian and offeredGeneration == generation and offeredAttempt == attempt then
				clearOfferUi()
				showAnswer("the guardian did not respond. try again", false, 3)
			end
		end)
	end
end

clearOfferUi = function(guardian)
	if guardian and guardian ~= offeredGuardian and guardian ~= commandGuardian then return end
	offerToken += 1
	offeredGuardian = nil
	offeredGeneration = nil
	offeredAttempt = nil
	waitingForAcceptance = false
	commandGuardian = nil
	commandGeneration = nil
	commandWaiting = false
	pendingPetCommand = nil
	panelMode = nil
	accept.Active = true
	decline.Active = true
	panel.Visible = false
	ContextActionService:UnbindAction("WMTAcceptGuardianOffer")
	hideAnswer()
end

local function bindAccept()
	ContextActionService:BindActionAtPriority("WMTAcceptGuardianOffer", function(_, inputState)
		if inputState == Enum.UserInputState.Begin and panelMode == "offer" and panel.Visible then
			respond(true)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 1, Enum.KeyCode.E)
end

local function requestPetCommand(guardian, command, generation)
	if not guardian or not generation or pendingPetCommand then return end
	requestCounter += 1
	local request = { guardian = guardian, generation = generation, id = requestCounter, command = command }
	pendingPetCommand = request
	if command ~= "Open" then commandWaiting = true end
	petCommandEvent:FireServer(guardian, command, generation, request.id)
	task.delay(5, function()
		if pendingPetCommand ~= request then return end
		pendingPetCommand = nil
		commandWaiting = false
		if command == "Open" then
			showAnswer("the guardian did not respond. try again", false, 3)
		elseif panelMode == "menu" and commandGuardian == guardian then
			showAnswer("the guardian did not respond. try again", false, 3)
		end
	end)
end

accept.Activated:Connect(function()
	if panelMode == "offer" then
		respond(true)
	elseif panelMode == "menu" and commandGuardian and not commandWaiting then
		requestPetCommand(commandGuardian, "Follow", commandGeneration)
	end
end)
decline.Activated:Connect(function()
	if panelMode == "offer" then
		respond(false)
	elseif panelMode == "menu" and commandGuardian and not commandWaiting then
		requestPetCommand(commandGuardian, "Hunt", commandGeneration)
	end
end)

rescueEvent.OnClientEvent:Connect(function(guardian, message, generation, attemptId)
	if not isPlayable() or not guardian or not guardian:IsA("Model") or generation ~= activeGeneration() then return end
	if not acceptAttempt(guardian, attemptId, false) then return end
	if conversationGuardian == guardian and conversationAttempt and attemptId ~= conversationAttempt then return end
	panelMode = "offer"
	offeredGuardian = guardian
	offeredGeneration = generation
	offeredAttempt = attemptId
	waitingForAcceptance = false
	accept.Text = "accept"
	decline.Text = "refuse"
	accept.Active = true
	text.Text = typeof(message) == "string" and message or "it wants to be your pet"
	panel.Visible = true
	bindAccept()
	showAnswer(string.format('"%s"', text.Text), true)
	offerToken += 1
	local token = offerToken
	task.delay(17, function()
		if token == offerToken and offeredGuardian == guardian and offeredGeneration == generation and offeredAttempt == attemptId then
			clearOfferUi(guardian)
		end
	end)
end)

rescueResultEvent.OnClientEvent:Connect(function(guardian, accepted, reason, generation, attemptId)
	if not isPlayable() or generation ~= activeGeneration() or not acceptAttempt(guardian, attemptId, false) then return end
	local offerMatches = guardian == offeredGuardian and generation == offeredGeneration and attemptId == offeredAttempt
	local conversationMatches = guardian == conversationGuardian and generation == conversationGeneration and attemptId == conversationAttempt
	if not offerMatches and not conversationMatches then return end
	completedAttemptByGuardian[guardian] = attemptId
	if offerMatches then clearOfferUi(guardian) end
	if not accepted and typeof(reason) == "string" and reason ~= "" then
		showAnswer(reason, false, 3)
	end
	if conversationMatches then stopConversation(guardian) end
end)

player.CharacterAdded:Connect(function()
	clearOfferUi()
end)

-- This is intentionally one client-owned prompt, moved only to the nearest
-- owned pet. Its attachment is placed at practical player height: a guardian
-- root can sit far above its feet, making root-to-root six studs unusable.
local petPrompt
local petAttachment
local promptRoot
local promptGuardian
local promptAccumulator = 0
local knownGuardians = {}

local function createPetPrompt()
	petAttachment = Instance.new("Attachment")
	petAttachment.Name = "WMTPetTalkAttachment"
	petPrompt = Instance.new("ProximityPrompt")
	petPrompt.Name = "WMTPetTalkPrompt"
	petPrompt.ActionText = "talk"
	petPrompt.ObjectText = "guardian pet"
	petPrompt.KeyboardKeyCode = Enum.KeyCode.E
	petPrompt.MaxActivationDistance = 6
	petPrompt.RequiresLineOfSight = true
	petPrompt.HoldDuration = 0
	petPrompt.Enabled = false
	petPrompt.Parent = petAttachment
	petPrompt.Triggered:Connect(function()
		if not promptGuardian or not isPlayable() or panel.Visible then return end
		requestPetCommand(promptGuardian, "Open", activeGeneration())
	end)
end
createPetPrompt()

local function getTalkPosition(guardian)
	local root = getRoot(guardian)
	if not root then return nil end
	local humanoid = guardian:FindFirstChildOfClass("Humanoid")
	local offset = (humanoid and humanoid.HipHeight or 0) + root.Size.Y / 2 - 3
	return root.Position - root.CFrame.UpVector * offset, root, offset, humanoid
end

local function trackGuardian(instance)
	if not instance:IsA("Model") then return end
	-- GuardianMonsterSystem initializes this attribute on every guardian, even
	-- while it is false, so non-guardian map models are not retained.
	if instance:GetAttribute("WMTGuardianPet") ~= nil or instance:GetAttribute("WMTGuardianOwnerUserId") ~= nil then
		knownGuardians[instance] = true
		return
	end
	if instance.Name ~= "weird monster thing" then return end
	-- Newly cloned guardians can be parented a moment before initialization.
	-- Watch only that model until either guardian marker is applied.
	instance:GetAttributeChangedSignal("WMTGuardianPet"):Connect(function()
		if instance:GetAttribute("WMTGuardianPet") ~= nil then knownGuardians[instance] = true end
	end)
	instance:GetAttributeChangedSignal("WMTGuardianOwnerUserId"):Connect(function()
		if instance:GetAttribute("WMTGuardianOwnerUserId") ~= nil then knownGuardians[instance] = true end
	end)
end
for _, instance in workspace:GetDescendants() do trackGuardian(instance) end
workspace.DescendantAdded:Connect(trackGuardian)
workspace.DescendantRemoving:Connect(function(instance)
	if instance == promptRoot or instance == petAttachment.Parent then
		-- A destroying rig can already have locked descendant parenting. Replace
		-- only our local prompt rather than trying to rescue a dying Attachment.
		local oldAttachment = petAttachment
		promptRoot = nil
		promptGuardian = nil
		createPetPrompt()
		oldAttachment:Destroy()
	end
	if instance == commandGuardian then clearOfferUi(commandGuardian) end
	if instance:IsA("Model") then knownGuardians[instance] = nil end
end)

local function updatePetPrompt()
	if panelMode == "menu" and commandGuardian then
		local character = player.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		local talkPosition, _, _, guardianHumanoid = getTalkPosition(commandGuardian)
		if not playerRoot or not talkPosition or (guardianHumanoid and guardianHumanoid.Health <= 0)
			or (talkPosition - playerRoot.Position).Magnitude > 6 then
			clearOfferUi(commandGuardian)
		end
	end
	if not isPlayable() or panel.Visible or conversation.Visible or answerText.Visible then
		petPrompt.Enabled = false
		promptGuardian = nil
		return
	end
	local character = player.Character
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not humanoid or humanoid.Health <= 0 then
		petPrompt.Enabled = false
		promptGuardian = nil
		return
	end
	local nearest, nearestDistance
	for guardian in pairs(knownGuardians) do
		if not guardian.Parent then
			knownGuardians[guardian] = nil
		elseif guardian:GetAttribute("WMTGuardianPet") == true and guardian:GetAttribute("WMTGuardianOwnerUserId") == player.UserId then
			local talkPosition, root, offset, guardianHumanoid = getTalkPosition(guardian)
			if talkPosition and root and (not guardianHumanoid or guardianHumanoid.Health > 0) then
				local distance = (talkPosition - playerRoot.Position).Magnitude
				if distance <= 6 and (not nearestDistance or distance < nearestDistance) then
					nearest, nearestDistance = { guardian = guardian, root = root, offset = offset }, distance
				end
			end
		end
	end
	promptGuardian = nearest and nearest.guardian
	if nearest then
		if not petPrompt.Parent then createPetPrompt() end
		promptRoot = nearest.root
		petAttachment.Position = Vector3.new(0, -nearest.offset, 0)
		if petAttachment.Parent ~= promptRoot then petAttachment.Parent = promptRoot end
		petPrompt.Enabled = true
	else
		petPrompt.Enabled = false
		promptRoot = nil
	end
end

RunService.Heartbeat:Connect(function(delta)
	promptAccumulator += delta
	if promptAccumulator >= 0.25 then
		promptAccumulator = 0
		updatePetPrompt()
	end
end)

petCommandResultEvent.OnClientEvent:Connect(function(guardian, succeeded, reason, behavior, generation, requestId)
	if not isPlayable() or generation ~= activeGeneration() then return end
	local pending = pendingPetCommand
	if not pending or pending.id ~= requestId or pending.guardian ~= guardian or pending.generation ~= generation then return end
	pendingPetCommand = nil
	if not succeeded then
		commandWaiting = false
		if typeof(reason) == "string" and reason ~= "" then showAnswer(reason, false, 3) end
		return
	end
	if pending.command == "Open" then
		commandGuardian, commandGeneration = guardian, generation
		panelMode = "menu"
		commandWaiting = false
		accept.Text, decline.Text = "FOLLOW ME", "GO HUNT"
		accept.Active, decline.Active = true, true
		panel.Visible = true
		showAnswer(behavior == "Hunt" and '"i hunt for you"' or '"i follow you"', true)
		return
	end
	if pending.command == "Follow" or pending.command == "Hunt" then
		commandWaiting = false
		clearOfferUi(guardian)
		showAnswer(behavior == "Hunt" and "i will hunt them down for you" or "i will protect you", false)
	end
end)

petLostEvent.OnClientEvent:Connect(function(_guardian, generation)
	if not isPlayable() or generation ~= activeGeneration() then return end
	lossToken += 1
	local token = lossToken
	lossText.Visible = true
	task.delay(3, function()
		if token == lossToken then lossText.Visible = false end
	end)
end)

conversationEvent.OnClientEvent:Connect(function(action, guardian, value, keepConversationVisible, generation, attemptId, persistent)
	if not isPlayable() or generation ~= activeGeneration() then return end
	if action == "start" and guardian and guardian:IsA("Model") then
		if not acceptAttempt(guardian, attemptId, true) then return end
		startConversation(guardian, value, generation, attemptId)
	elseif guardian == conversationGuardian and generation == conversationGeneration and attemptId == conversationAttempt then
		if action == "stop" then
			-- A server answer/offer may immediately follow the progress bar. Retain
			-- the attempt identity so that response cannot be mistaken for stale UI.
			conversation.Visible = false
			fill.Size = UDim2.fromScale(0, 1)
		elseif action == "answer" then
			if not keepConversationVisible then
				conversation.Visible = false
				fill.Size = UDim2.fromScale(0, 1)
			end
			showAnswer(string.format("\"%s\"", tostring(value)), persistent == true, 3)
			if persistent ~= true then
				completedAttemptByGuardian[guardian] = attemptId
				stopConversation(guardian)
			end
		end
	end
end)

local statusBound = false
local function bindStatusEvent(event)
	if statusBound or event.Name ~= "WMTGuardianStatus" or not event:IsA("RemoteEvent") then return end
	statusBound = true
	event.OnClientEvent:Connect(function(_guardianModel, stateName, message, generation)
		-- The guardian model may not be streamed to this client yet; the server is
		-- authoritative for ownership, while this client only accepts display text.
		if not isPlayable() or generation ~= activeGeneration() or typeof(stateName) ~= "string" or typeof(message) ~= "string" or message == "" then return end
		showStatus(message, stateName ~= "Kill")
	end)
end
ReplicatedStorage.ChildAdded:Connect(bindStatusEvent)
if guardianStatusEvent then bindStatusEvent(guardianStatusEvent) end

local function clearForInactive()
	clearOfferUi()
	stopConversation()
	hideAnswer()
	hideStatus()
	petPrompt.Enabled = false
	promptGuardian = nil
	lossToken += 1
	lossText.Visible = false
end

workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
	if not isPlayable() then clearForInactive() end
end)
workspace:GetAttributeChangedSignal("RoundGeneration"):Connect(function()
	clearForInactive()
	table.clear(latestAttemptByGuardian)
	table.clear(completedAttemptByGuardian)
end)
player:GetAttributeChangedSignal("EscapedNightmare"):Connect(function()
	if not isPlayable() then clearForInactive() end
end)
local deathConnection
local function bindCharacterDeath(character)
	if deathConnection then deathConnection:Disconnect(); deathConnection = nil end
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid and character == player.Character then
			deathConnection = humanoid.Died:Connect(clearForInactive)
		end
	end)
end
player.CharacterAdded:Connect(function(character)
	clearForInactive()
	bindCharacterDeath(character)
end)
player.CharacterRemoving:Connect(clearForInactive)
if player.Character then bindCharacterDeath(player.Character) end

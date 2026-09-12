local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI_TEST = true -- Studio-only end-screen preview buttons.

local player = Players.LocalPlayer
local AudioPreloader = require(ReplicatedStorage:WaitForChild("AudioPreloader"))
AudioPreloader.Start()
local WELCOME_ACCEPTED_ATTRIBUTE = "NightmareWelcomeAccepted"
local INTRO_MOVEMENT_LOCK_SECONDS = 9
local gameplayStopped = false

-- Disable only Roblox's local walk/run/jump controls during the opening lines.
-- The character remains fully physical: gravity, animation, camera, damage,
-- world simulation, monsters, and the round clock continue normally.
local playerControls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

local function lockOpeningMovement()
	playerControls:Disable()
	task.delay(INTRO_MOVEMENT_LOCK_SECONDS, function()
		if not gameplayStopped and workspace:GetAttribute("RoundState") == "Active" then
			playerControls:Enable()
		end
	end)
end

local roundCompleteEvent = ReplicatedStorage:WaitForChild("RoundComplete")
local roundStartedEvent = ReplicatedStorage:WaitForChild("RoundStarted")
local restartRoundEvent = ReplicatedStorage:WaitForChild("RestartRound")
local restartFailedEvent = ReplicatedStorage:WaitForChild("RestartFailed")
local nightmareEscapedEvent = ReplicatedStorage:WaitForChild("NightmareEscaped")

-- Wait for the instance-based GameFlowHud ScreenGui that gets cloned from StarterGui into PlayerGui
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GameFlowHud")
-- MonsterMilestoneHud is a sibling ScreenGui at DisplayOrder 10000. Result and
-- welcome modals must always cover it, even if a stale announcement arrives.
gui.DisplayOrder = 20000

local welcomeShade = gui:WaitForChild("WelcomePanel")
local welcomePanel = welcomeShade:WaitForChild("Panel")
local okButton = welcomePanel:WaitForChild("OkButton")
local welcomeShadeTransparency = welcomeShade.BackgroundTransparency
local welcomeClosing = false

local endShade = gui:WaitForChild("RoundCompletePanel")
local endPanel = endShade:WaitForChild("Panel")
local endTitle = endPanel:WaitForChild("EndTitle")
local endMessage = endPanel:WaitForChild("EndMessage")
local leaderboard = endPanel:WaitForChild("Leaderboard")
local restartButton = endPanel:WaitForChild("RestartButton")

-- The portal exit is intentionally independent of the old round-results
-- panel. It is a private, dark ending for the player who made it home.
local escapeShade = Instance.new("Frame")
escapeShade.Name = "NightmareEscapeShade"
escapeShade.Size = UDim2.fromScale(1, 1)
escapeShade.BackgroundColor3 = Color3.fromRGB(2, 0, 7)
escapeShade.BackgroundTransparency = 0.08
escapeShade.BorderSizePixel = 0
escapeShade.Visible = false
escapeShade.ZIndex = 2000
escapeShade.Parent = gui

local escapePanel = Instance.new("Frame")
escapePanel.Name = "EscapePanel"
escapePanel.AnchorPoint = Vector2.new(0.5, 0.5)
escapePanel.Position = UDim2.fromScale(0.5, 0.5)
escapePanel.Size = UDim2.fromOffset(620, 320)
escapePanel.BackgroundColor3 = Color3.fromRGB(12, 4, 25)
escapePanel.BackgroundTransparency = 0.08
escapePanel.BorderSizePixel = 0
escapePanel.ZIndex = 2001
escapePanel.Parent = escapeShade
Instance.new("UICorner", escapePanel).CornerRadius = UDim.new(0, 12)
local escapeStroke = Instance.new("UIStroke")
escapeStroke.Color = Color3.fromRGB(134, 70, 201)
escapeStroke.Transparency = 0.18
escapeStroke.Thickness = 2
escapeStroke.Parent = escapePanel

local escapeTitle = Instance.new("TextLabel")
escapeTitle.Name = "Title"
escapeTitle.BackgroundTransparency = 1
escapeTitle.Position = UDim2.fromOffset(28, 22)
escapeTitle.Size = UDim2.new(1, -56, 0, 94)
escapeTitle.Font = Enum.Font.GothamBlack
escapeTitle.Text = "Congratulations!\nYou got out of this nightmare.\nFor now."
escapeTitle.TextColor3 = Color3.fromRGB(246, 235, 255)
escapeTitle.TextStrokeColor3 = Color3.fromRGB(44, 15, 77)
escapeTitle.TextStrokeTransparency = 0.1
escapeTitle.TextSize = 38
escapeTitle.TextWrapped = true
escapeTitle.TextXAlignment = Enum.TextXAlignment.Center
escapeTitle.TextYAlignment = Enum.TextYAlignment.Center
escapeTitle.ZIndex = 2002
escapeTitle.Parent = escapePanel

local resultName = Instance.new("TextLabel")
resultName.Name = "PlayerName"
resultName.BackgroundTransparency = 1
resultName.Position = UDim2.fromOffset(28, 121)
resultName.Size = UDim2.new(1, -56, 0, 24)
resultName.Font = Enum.Font.GothamBold
resultName.TextColor3 = Color3.fromRGB(246, 235, 255)
resultName.TextSize = 20
resultName.TextXAlignment = Enum.TextXAlignment.Center
resultName.ZIndex = 2002
resultName.Parent = escapePanel

local resultStats = Instance.new("TextLabel")
resultStats.Name = "Stats"
resultStats.BackgroundTransparency = 1
resultStats.Position = UDim2.fromOffset(28, 150)
resultStats.Size = UDim2.new(1, -56, 0, 24)
resultStats.Font = Enum.Font.GothamBold
resultStats.TextColor3 = Color3.fromRGB(209, 174, 255)
resultStats.TextSize = 16
resultStats.TextXAlignment = Enum.TextXAlignment.Center
resultStats.ZIndex = 2002
resultStats.Parent = escapePanel

local resultRecord = Instance.new("TextLabel")
resultRecord.Name = "Record"
resultRecord.BackgroundTransparency = 1
resultRecord.Position = UDim2.fromOffset(28, 179)
resultRecord.Size = UDim2.new(1, -56, 0, 20)
resultRecord.Font = Enum.Font.GothamBold
resultRecord.TextColor3 = Color3.fromRGB(255, 127, 205)
resultRecord.TextSize = 14
resultRecord.TextXAlignment = Enum.TextXAlignment.Center
resultRecord.Visible = false
resultRecord.ZIndex = 2002
resultRecord.Parent = escapePanel

local escapeDetail = Instance.new("TextLabel")
escapeDetail.Name = "Detail"
escapeDetail.BackgroundTransparency = 1
escapeDetail.Position = UDim2.fromOffset(28, 205)
escapeDetail.Size = UDim2.new(1, -56, 0, 28)
escapeDetail.Font = Enum.Font.Gotham
escapeDetail.Text = "For now, the forest is quiet."
escapeDetail.TextColor3 = Color3.fromRGB(173, 224, 255)
escapeDetail.TextSize = 16
escapeDetail.TextXAlignment = Enum.TextXAlignment.Center
escapeDetail.ZIndex = 2002
escapeDetail.Parent = escapePanel

local escapeRestartButton = Instance.new("TextButton")
escapeRestartButton.Name = "WakeUpAgain"
escapeRestartButton.AnchorPoint = Vector2.new(0.5, 0)
escapeRestartButton.Position = UDim2.new(0.5, 0, 1, -55)
escapeRestartButton.Size = UDim2.fromOffset(180, 42)
escapeRestartButton.BackgroundColor3 = Color3.fromRGB(80, 19, 107)
escapeRestartButton.BorderSizePixel = 0
escapeRestartButton.Font = Enum.Font.GothamBold
escapeRestartButton.Text = "WAKE UP AGAIN"
escapeRestartButton.TextColor3 = Color3.fromRGB(255, 245, 255)
escapeRestartButton.TextSize = 14
escapeRestartButton.ZIndex = 2002
escapeRestartButton.Parent = escapePanel
Instance.new("UICorner", escapeRestartButton).CornerRadius = UDim.new(0, 7)

local escapedNightmare = false
local currentRoundGeneration = math.max(0, math.floor(tonumber(workspace:GetAttribute("RoundGeneration")) or 0))
local restartRequestPending = false
local pendingRoundStartedGeneration
local appliedRoundStartedGeneration

local function matchesCurrentGeneration(data)
	local replicatedGeneration = math.floor(tonumber(workspace:GetAttribute("RoundGeneration")) or -1)
	return type(data) == "table"
		and tonumber(data.roundGeneration) == currentRoundGeneration
		and currentRoundGeneration == replicatedGeneration
end

local function setGameplayStopped(stopped)
	if gameplayStopped == stopped then return end
	gameplayStopped = stopped
	if stopped then
		playerControls:Disable()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid:UnequipTools() end
	else
		playerControls:Enable()
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
		end)
	end
end

local function refreshRestartButton()
	if not escapeShade.Visible then return end

	local state = workspace:GetAttribute("RoundState")
	restartButton.Visible = false
	restartButton.Active = false

	-- A player who escaped must not be able to cut short another survivor's
	-- active escape phase. The shared restart control becomes available once
	-- that phase has ended for everyone.
	if state == "Escape" then
		escapeRestartButton.Text = "SURVIVORS ARE ESCAPING"
		escapeRestartButton.Active = false
		return
	end

	if state == "Ended" then
		local restartEndsAt = tonumber(workspace:GetAttribute("ServerRestartEndsAt"))
		if restartEndsAt then
			local remaining = math.max(0, math.ceil(restartEndsAt - workspace:GetServerTimeNow()))
			escapeRestartButton.Text = string.format("RESTARTING IN %d:%02d", math.floor(remaining / 60), remaining % 60)
			escapeRestartButton.Active = false
		else
			escapeRestartButton.Text = restartRequestPending and "RESTARTING SERVER..." or "RESTART GAME"
			escapeRestartButton.Active = not restartRequestPending
		end
	else
		escapeRestartButton.Text = "ROUND UNAVAILABLE"
		escapeRestartButton.Active = false
	end
end

local function resizeEscapePanel()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 700 or viewport.Y < 520
	escapePanel.Size = mobile and UDim2.new(0.88, 0, 0, 280) or UDim2.fromOffset(620, 320)
	escapeTitle.TextSize = mobile and 26 or 38
	resultName.TextSize = mobile and 17 or 20
	resultStats.TextSize = mobile and 12 or 16
	resultRecord.TextSize = mobile and 10 or 14
	escapeDetail.TextSize = mobile and 13 or 16
end

resizeEscapePanel()

local function styleLeaderboard()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 900 or viewport.Y < 600
	-- TextScaled makes a single short row balloon to fill this panel. End-round
	-- scores must stay at a stable reading size regardless of player count.
	leaderboard.TextScaled = false
	leaderboard.TextSize = mobile and 16 or 24
	leaderboard.TextWrapped = true
	leaderboard.TextXAlignment = Enum.TextXAlignment.Left
	leaderboard.TextYAlignment = Enum.TextYAlignment.Top
	local constraint = leaderboard:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MinTextSize = 8
		constraint.MaxTextSize = leaderboard.TextSize
	end
end

styleLeaderboard()

local spawnFlash = gui:FindFirstChild("NewSpawnCyanOverride")
if not spawnFlash then
	spawnFlash = Instance.new("Frame")
	spawnFlash.Name = "NewSpawnCyanOverride"
	spawnFlash.Size = UDim2.fromScale(1, 1)
	spawnFlash.BackgroundColor3 = Color3.fromRGB(81, 219, 255)
	spawnFlash.BackgroundTransparency = 1
	spawnFlash.BorderSizePixel = 0
	spawnFlash.Visible = false
	spawnFlash.ZIndex = 100
	spawnFlash.Parent = gui
end

local function playSound(soundName)
	local source = SoundService:FindFirstChild(soundName, true)
	if not (source and source:IsA("Sound")) then return end
	-- GameIntro is the first critical sound after the welcome modal. Give its
	-- template an explicit preload/loaded check before cloning it; this avoids
	-- the published-client cold-cache race that Studio usually masks.
	if soundName == "GameIntro" then
		pcall(function() ContentProvider:PreloadAsync({ source }) end)
		local deadline = os.clock() + 5
		while not source.IsLoaded and os.clock() < deadline do task.wait() end
	else
		AudioPreloader.WaitUntilReady(5)
	end
	local sound = source:Clone()
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent then sound:Destroy() end
	end)
	-- TimeLength is often still zero in a published server while Roblox streams
	-- the asset. Do not use it as a three-second cleanup deadline; Ended owns
	-- normal cleanup, while this only protects against a failed/looping asset.
	task.delay(30, function()
		if sound.Parent then sound:Destroy() end
	end)
end

local spawnFlashToken = 0
local resultAudioToken = 0

-- Result cues must overlap on the modal's timeline. They intentionally skip
-- the general preloader wait so a long first clip cannot delay its follow-up.
local function playResultSound(soundName)
	local source = SoundService:FindFirstChild(soundName, true)
	if not (source and source:IsA("Sound")) then
		warn("[GameFlowHud] SoundService." .. soundName .. " is missing")
		return
	end
	local sound = source:Clone()
	sound.Looped = false
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		if sound.Parent then sound:Destroy() end
	end)
	task.delay(30, function()
		if sound.Parent then sound:Destroy() end
	end)
end

local function showNewSpawnFlash()
	spawnFlashToken += 1
	local token = spawnFlashToken
	spawnFlash.Visible = true
	spawnFlash.BackgroundTransparency = 1
	TweenService:Create(spawnFlash, TweenInfo.new(0.12), {
		BackgroundTransparency = 0.48,
	}):Play()
	task.delay(0.18, function()
		if token ~= spawnFlashToken or not spawnFlash.Parent then return end
		local fade = TweenService:Create(spawnFlash, TweenInfo.new(0.45), {
			BackgroundTransparency = 1,
		})
		fade:Play()
		fade.Completed:Once(function()
			if token == spawnFlashToken and spawnFlash.Parent then spawnFlash.Visible = false end
		end)
	end)
end

-- Hide the Roblox default backpack/inventory while the welcome panel is visible
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local function closeWelcome()
	if welcomeClosing or not welcomeShade.Visible then return end
	welcomeClosing = true
	-- Keep the welcome shade as a quiet bridge into the two nightmare lines.
	-- Only its modal content closes immediately; the backdrop fades away while
	-- the announcement HUD speaks over it.
	welcomePanel.Visible = false
	welcomeShade.BackgroundTransparency = welcomeShadeTransparency
	lockOpeningMovement()
	playSound("GameIntro")
	-- This local attribute is the one-time handoff to the existing announcement
	-- HUD. StarterPlayerScripts survive character respawns, so the introduction
	-- cannot replay merely because the player starts another life.
	player:SetAttribute(WELCOME_ACCEPTED_ATTRIBUTE, true)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
	local fade = TweenService:Create(welcomeShade, TweenInfo.new(15, Enum.EasingStyle.Linear), {
		BackgroundTransparency = 1,
	})
	fade:Play()
	fade.Completed:Once(function()
		if welcomeShade.Parent then welcomeShade.Visible = false end
	end)
end

-- The first character is the opening life and uses GameIntro after the welcome
-- modal. Every later CharacterAdded is a genuine new spawn after death.
local initialLifeStarted = player.Character ~= nil
player.CharacterAdded:Connect(function()
	if not initialLifeStarted then
		initialLifeStarted = true
		return
	end
	if player:GetAttribute(WELCOME_ACCEPTED_ATTRIBUTE) ~= true then return end
	playSound("NewSpawn")
	showNewSpawnFlash()
end)

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

local function formatElapsed(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function recordText(data)
	local newScore = data and data.newScoreRecord == true
	local newEscape = data and data.newEscapeRecord == true
	if newScore and newEscape then return "THAT'S A NEW SCORE AND ESCAPE-TIME RECORD" end
	if newScore then return "THAT'S A NEW SCORE RECORD" end
	if newEscape then return "THAT'S A NEW ESCAPE-TIME RECORD" end
	return nil
end

local function showResult(data)
	data = data or {}
	if not matchesCurrentGeneration(data) then return end
	setGameplayStopped(true)
	local escaped = data.outcome == "escape"
	resultAudioToken += 1
	local audioToken = resultAudioToken
	if escaped then
		task.spawn(function()
			playResultSound("NightmareEscaped")
		end)
	else
		task.spawn(function()
			playResultSound("NightmareWon")
		end)
		task.delay(2.5, function()
			-- This is tied to the loss modal only; an escaped player never receives
			-- the follow-up warning. It overlaps NightmareWon by design.
			if audioToken == resultAudioToken
				and escapeShade.Visible
				and workspace:GetAttribute("RoundState") == "Ended"
			then
				playResultSound("NotEscaping")
			end
		end)
	end
	-- Keep every result modal above opening/critical announcements, including
	-- a stale announcement that arrives on the same frame as the result.
	gui.DisplayOrder = 40000
	escapedNightmare = escaped
	endShade.Visible = false
	resizeEscapePanel()
	escapeTitle.Text = escaped
		and "Congratulations!\nYou got out of this nightmare.\nFor now."
		or "The nightmare won"
	resultName.Text = tostring(data.playerName or player.Name)
	local stats = string.format(
		"SCORE %d / KILLS %d / DEATHS %d",
		tonumber(data.score) or 0,
		tonumber(data.kills) or 0,
		tonumber(data.deaths) or 0
	)
	if escaped then stats ..= " / TIME " .. formatElapsed(data.elapsedSeconds) end
	resultStats.Text = stats
	local record = recordText(data)
	resultRecord.Text = record or ""
	resultRecord.Visible = record ~= nil
	escapeDetail.Text = (data.message)
		or (escaped and "For now, the forest is quiet." or "Time ran out. The forest is still hunting.")
	escapeDetail.Text ..= "\nRestarting creates a completely fresh server and game."
	refreshRestartButton()
	escapeShade.Visible = true
	refreshRestartButton()
end

local function showRoundFailure(data)
	if escapedNightmare then return end
	data = data or {}
	if not matchesCurrentGeneration(data) then return end
	data.outcome = "timeout"
	showResult(data)
end

roundCompleteEvent.OnClientEvent:Connect(function(data)
	data = data or {}
	if not matchesCurrentGeneration(data) then return end
	data.outcome = "complete"
	data.message = data.message or "Congrats. The forest is clear."
	showResult(data)
end)

local function showEscapedScreen(data)
	data = data or {}
	if not matchesCurrentGeneration(data) then return end
	data.outcome = "escape"
	showResult(data)
end

nightmareEscapedEvent.OnClientEvent:Connect(showEscapedScreen)

-- Studio-only visual previews. They use the real client display functions but
-- never contact the server or alter a published session.
if UI_TEST and RunService:IsStudio() then
	local previewBar = Instance.new("Frame")
	previewBar.Name = "StudioGameFlowPreview"
	previewBar.Position = UDim2.fromOffset(16, 145)
	previewBar.Size = UDim2.fromOffset(330, 42)
	previewBar.BackgroundColor3 = Color3.fromRGB(24, 12, 43)
	previewBar.BorderSizePixel = 0
	previewBar.ZIndex = 1000
	previewBar.Parent = gui
	Instance.new("UICorner", previewBar).CornerRadius = UDim.new(0, 7)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 5)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = previewBar
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 5)
	padding.Parent = previewBar

	local function previewButton(text, width)
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(width, 32)
		button.BackgroundColor3 = Color3.fromRGB(82, 36, 121)
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.Text = text
		button.TextColor3 = Color3.fromRGB(255, 245, 255)
		button.TextSize = 11
		button.ZIndex = 1001
		button.Parent = previewBar
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
		return button
	end

	local timeoutButton = previewButton("TIME ENDED", 112)
	local escapedButton = previewButton("ESCAPED", 96)
	local closeButton = previewButton("CLOSE", 96)

	timeoutButton.Activated:Connect(function()
		welcomeShade.Visible = false
		showRoundFailure({
			roundGeneration = currentRoundGeneration,
			message = "Time ran out. The forest is still hunting.",
			playerName = player.Name,
			score = 42,
			kills = 9,
			deaths = 2,
			newScoreRecord = true,
		})
	end)
	escapedButton.Activated:Connect(function()
		welcomeShade.Visible = false
		showEscapedScreen({
			roundGeneration = currentRoundGeneration,
			playerName = player.Name,
			score = 42,
			kills = 9,
			deaths = 2,
			elapsedSeconds = 43 * 60 + 46,
			newScoreRecord = true,
			newEscapeRecord = true,
		})
	end)
	closeButton.Activated:Connect(function()
			escapedNightmare = false
			endShade.Visible = false
			escapeShade.Visible = false
	end)
end

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

local function reconcileRoundStarted()
	local generation = pendingRoundStartedGeneration
	if not generation or generation == appliedRoundStartedGeneration then return end
	if generation ~= tonumber(workspace:GetAttribute("RoundGeneration"))
		or workspace:GetAttribute("RoundState") ~= "Active"
	then return end

	pendingRoundStartedGeneration = nil
	appliedRoundStartedGeneration = generation
	currentRoundGeneration = generation
	gui.DisplayOrder = 20000
	restartRequestPending = false
	setGameplayStopped(false)
	escapedNightmare = false
	escapeShade.Visible = false
	escapeRestartButton.Active = true
	restartButton.Text = "Continue / Restart"
	endShade.Visible = false
	player:SetAttribute("NightmareIntroductionComplete", false)
end

roundStartedEvent.OnClientEvent:Connect(function(generation)
	generation = tonumber(generation)
	if not generation or generation < currentRoundGeneration then return end
	pendingRoundStartedGeneration = generation
	reconcileRoundStarted()
end)

restartFailedEvent.OnClientEvent:Connect(function(generation, message)
	if tonumber(generation) ~= currentRoundGeneration then return end
	if workspace:GetAttribute("RoundState") ~= "Ended" then return end
	restartRequestPending = false
	escapeDetail.Text = tostring(message or "Restart could not begin. Please try again.")
	refreshRestartButton()
end)

escapeRestartButton.MouseButton1Click:Connect(function()
	if workspace:GetAttribute("RoundState") ~= "Ended" or restartRequestPending then return end
	restartRequestPending = true
	refreshRestartButton()
	restartRoundEvent:FireServer(currentRoundGeneration)
end)

RunService.RenderStepped:Connect(refreshRestartButton)

workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
	local state = workspace:GetAttribute("RoundState")
	restartButton.Visible = false
	restartButton.Active = false
	if state ~= "Active" and state ~= "Escape" then
		setGameplayStopped(true)
	end
	reconcileRoundStarted()
	refreshRestartButton()
end)

workspace:GetAttributeChangedSignal("RoundGeneration"):Connect(function()
	-- The replicated generation can advance during Starting. Only RoundStarted
	-- for that exact Active generation may reopen the local controls or modal.
	currentRoundGeneration = math.max(0, math.floor(tonumber(workspace:GetAttribute("RoundGeneration")) or 0))
	if pendingRoundStartedGeneration and pendingRoundStartedGeneration < currentRoundGeneration then
		pendingRoundStartedGeneration = nil
	end
	reconcileRoundStarted()
end)

local initialRoundState = workspace:GetAttribute("RoundState")
if initialRoundState ~= "Active" and initialRoundState ~= "Escape" then
	setGameplayStopped(true)
end

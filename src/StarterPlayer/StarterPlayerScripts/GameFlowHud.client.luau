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
local INTRO_MOVEMENT_LOCK_SECONDS = 8

-- Disable only Roblox's local walk/run/jump controls during the opening lines.
-- The character remains fully physical: gravity, animation, camera, damage,
-- world simulation, monsters, and the round clock continue normally.
local playerControls = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()

local function lockOpeningMovement()
	playerControls:Disable()
	task.delay(INTRO_MOVEMENT_LOCK_SECONDS, function()
		playerControls:Enable()
	end)
end

local roundCompleteEvent = ReplicatedStorage:WaitForChild("RoundComplete")
local roundRestartedEvent = ReplicatedStorage:WaitForChild("RoundRestarted")
local restartRoundEvent = ReplicatedStorage:WaitForChild("RestartRound")
local nightmareEscapedEvent = ReplicatedStorage:WaitForChild("NightmareEscaped")

-- Wait for the instance-based GameFlowHud ScreenGui that gets cloned from StarterGui into PlayerGui
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GameFlowHud")

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
escapeShade.ZIndex = 200
escapeShade.Parent = gui

local escapePanel = Instance.new("Frame")
escapePanel.Name = "EscapePanel"
escapePanel.AnchorPoint = Vector2.new(0.5, 0.5)
escapePanel.Position = UDim2.fromScale(0.5, 0.5)
escapePanel.Size = UDim2.fromOffset(620, 320)
escapePanel.BackgroundColor3 = Color3.fromRGB(12, 4, 25)
escapePanel.BackgroundTransparency = 0.08
escapePanel.BorderSizePixel = 0
escapePanel.ZIndex = 201
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
escapeTitle.ZIndex = 202
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
resultName.ZIndex = 202
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
resultStats.ZIndex = 202
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
resultRecord.ZIndex = 202
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
escapeDetail.ZIndex = 202
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
escapeRestartButton.ZIndex = 202
escapeRestartButton.Parent = escapePanel
Instance.new("UICorner", escapeRestartButton).CornerRadius = UDim.new(0, 7)

local escapedNightmare = false

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
	local escaped = data.outcome == "escape"
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
	escapeRestartButton.Text = escaped and "WAKE UP AGAIN" or "QUICK RESTART"
	escapeShade.Visible = true
end

local function showRoundFailure(data)
	if escapedNightmare then return end
	data = data or {}
	data.outcome = "timeout"
	showResult(data)
end

roundCompleteEvent.OnClientEvent:Connect(function(data)
	data = data or {}
	data.outcome = "complete"
	data.message = data.message or "Congrats. The forest is clear."
	showResult(data)
end)

local function showEscapedScreen(data)
	data = data or {}
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

roundRestartedEvent.OnClientEvent:Connect(function()
	escapedNightmare = false
	escapeShade.Visible = false
	restartButton.Text = "Continue / Restart"
	endShade.Visible = false
end)

restartButton.MouseButton1Click:Connect(function()
	restartButton.Text = "Restarting..."
	restartRoundEvent:FireServer()
end)

escapeRestartButton.MouseButton1Click:Connect(function()
	escapeRestartButton.Text = "WAKING..."
	restartRoundEvent:FireServer()
end)

local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local AudioPreloader = require(ReplicatedStorage:WaitForChild("AudioPreloader"))
AudioPreloader.Start()
local WELCOME_ACCEPTED_ATTRIBUTE = "NightmareWelcomeAccepted"
local INTRO_MOVEMENT_LOCK_SECONDS = 15

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
escapePanel.Size = UDim2.fromOffset(620, 280)
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
escapeTitle.Position = UDim2.fromOffset(28, 46)
escapeTitle.Size = UDim2.new(1, -56, 0, 102)
escapeTitle.Font = Enum.Font.GothamBlack
escapeTitle.Text = "You escaped the nightmare.\nThis time."
escapeTitle.TextColor3 = Color3.fromRGB(246, 235, 255)
escapeTitle.TextStrokeColor3 = Color3.fromRGB(44, 15, 77)
escapeTitle.TextStrokeTransparency = 0.1
escapeTitle.TextSize = 38
escapeTitle.TextWrapped = true
escapeTitle.TextXAlignment = Enum.TextXAlignment.Center
escapeTitle.TextYAlignment = Enum.TextYAlignment.Center
escapeTitle.ZIndex = 202
escapeTitle.Parent = escapePanel

local escapeDetail = Instance.new("TextLabel")
escapeDetail.Name = "Detail"
escapeDetail.BackgroundTransparency = 1
escapeDetail.Position = UDim2.fromOffset(28, 154)
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
escapeRestartButton.Position = UDim2.new(0.5, 0, 1, -65)
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
	escapePanel.Size = mobile and UDim2.new(0.88, 0, 0, 245) or UDim2.fromOffset(620, 280)
	escapeTitle.TextSize = mobile and 26 or 38
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
	if escapedNightmare then return end
	styleLeaderboard()
	endTitle.Text = "The nightmare won"
	endMessage.Text = (data and data.message) or "Time ran out. The forest is still hunting."
	leaderboard.Text = formatLeaderboard(data and data.scoreboard)
	restartButton.Text = "Quick Restart"
	endShade.Visible = true
end

roundCompleteEvent.OnClientEvent:Connect(function(data)
	styleLeaderboard()
	endTitle.Text = "Round completed"
	endMessage.Text = "Congrats. The forest is clear."
	restartButton.Text = "Continue / Restart"
	leaderboard.Text = formatLeaderboard(data and data.scoreboard)
	endShade.Visible = true
end)

nightmareEscapedEvent.OnClientEvent:Connect(function()
	escapedNightmare = true
	endShade.Visible = false
	resizeEscapePanel()
	escapeShade.Visible = true
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

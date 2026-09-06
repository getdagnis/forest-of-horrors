-- ShieldHud
-- Reads the server-owned ShieldExpiresAt attribute and presents the remaining
-- protection time directly below the local battle radar.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "ShieldStatusHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Name = "ShieldTimer"
label.AnchorPoint = Vector2.new(1, 0)
label.Size = UDim2.fromOffset(152, 28)
label.BackgroundColor3 = Color3.fromRGB(8, 22, 34)
label.BackgroundTransparency = 0.18
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamBold
label.TextColor3 = Color3.fromRGB(152, 233, 255)
label.TextStrokeTransparency = 0.68
label.TextSize = 32
label.Visible = false
label.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 4)
corner.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(86, 187, 225)
stroke.Transparency = 0.5
stroke.Parent = label

local speedLabel = label:Clone()
speedLabel.Name = "SpeedCoilTimer"
speedLabel.TextColor3 = Color3.fromRGB(255, 105, 180)
speedLabel.Parent = gui
local speedStroke = speedLabel:FindFirstChildOfClass("UIStroke")
if speedStroke then speedStroke.Color = Color3.fromRGB(255, 105, 180) end

local warningLabel = Instance.new("TextLabel")
warningLabel.Name = "ShieldExpiryWarning"
warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
warningLabel.Position = UDim2.fromScale(0.5, 0.4)
warningLabel.Size = UDim2.new(0.8, 0, 0, 42)
warningLabel.BackgroundTransparency = 1
warningLabel.Font = Enum.Font.GothamBold
warningLabel.Text = "15 SHIELD SECONDS REMAINING"
warningLabel.TextColor3 = Color3.fromRGB(152, 233, 255)
warningLabel.TextStrokeColor3 = Color3.fromRGB(0, 12, 22)
warningLabel.TextStrokeTransparency = 0.2
warningLabel.TextScaled = true
warningLabel.Visible = false
warningLabel.Parent = gui

local activeExpiry
local lastRemainingSeconds
local warningToken = 0

local function warnShieldExpiry()
	local source = SoundService:FindFirstChild("Remaining")
	if source and source:IsA("Sound") then
		local sound = source:Clone()
		sound.Looped = false
		sound.Parent = SoundService
		sound:Play()
		Debris:AddItem(sound, math.max(3, sound.TimeLength + 1))
	end
	warningToken += 1
	local token = warningToken
	warningLabel.Visible = true
	task.delay(3, function()
		if token == warningToken then warningLabel.Visible = false end
	end)
end

local function placeBelowRadar()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 1100 or viewport.Y < 650
	-- Match ScoreGui's rank value: 32px desktop, 16px compact/mobile.
	label.TextSize = mobile and 16 or 32
	label.Size = mobile and UDim2.fromOffset(152, 28) or UDim2.fromOffset(210, 44)
	speedLabel.TextSize = label.TextSize
	speedLabel.Size = label.Size
	local radarHud = playerGui:FindFirstChild("MonsterRadarHud")
	local radar = radarHud and radarHud:FindFirstChild("Radar")
	local x, y
	if radar and radar:IsA("GuiObject") and radar.AbsoluteSize.Y > 0 then
		x = math.min(radar.AbsolutePosition.X + radar.AbsoluteSize.X, viewport.X - 8)
		y = radar.AbsolutePosition.Y + radar.AbsoluteSize.Y + 8
	else
		-- MonsterRadar can be a frame late during character startup.
		x = viewport.X - 8
		y = 208
	end
	label.Position = UDim2.fromOffset(x, y)
	if speedLabel.Visible then
		local height = mobile and 28 or 44
		speedLabel.Position = UDim2.fromOffset(x, y + (label.Visible and height + 4 or 0))
	end
end

local function update()
	local expiresAt = tonumber(player:GetAttribute("ShieldExpiresAt"))
	local remaining = expiresAt and math.max(0, expiresAt - workspace:GetServerTimeNow()) or 0
	if activeExpiry ~= expiresAt then
		activeExpiry = expiresAt
		lastRemainingSeconds = remaining
	elseif expiresAt and lastRemainingSeconds and lastRemainingSeconds > 15 and remaining <= 15 then
		warnShieldExpiry()
	end
	lastRemainingSeconds = remaining
	label.Visible = remaining > 0
	if not label.Visible then
		activeExpiry = nil
		lastRemainingSeconds = nil
	end
	if label.Visible then
		local totalSeconds = math.ceil(remaining)
		label.Text = string.format("SHIELD  %d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
	end

	local speedRemaining = tonumber(player:GetAttribute("SpeedCoilRemaining")) or 0
	local speedEquipped = player:GetAttribute("SpeedCoilEquipped") == true
	speedLabel.Visible = speedEquipped and speedRemaining > 0
	if speedLabel.Visible then
		local totalSeconds = math.ceil(speedRemaining)
		speedLabel.Text = string.format("SPEED  %d:%02d", math.floor(totalSeconds / 60), totalSeconds % 60)
	end
	if not label.Visible and not speedLabel.Visible then return end
	placeBelowRadar()
end

player:GetAttributeChangedSignal("ShieldExpiresAt"):Connect(update)
player:GetAttributeChangedSignal("SpeedCoilRemaining"):Connect(update)
player:GetAttributeChangedSignal("SpeedCoilEquipped"):Connect(update)
local updateElapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	-- A tenth of a second keeps the timer smooth without adding a per-frame HUD
	-- update to an already busy monster round.
	updateElapsed += deltaTime
	if updateElapsed < 0.1 then return end
	updateElapsed = 0
	update()
end)
update()

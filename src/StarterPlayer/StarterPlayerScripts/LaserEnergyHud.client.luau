-- LaserEnergyHud: quiet reserve feedback plus the temporary Power Box charge bar.
-- The server owns Player.LaserEnergy; this LocalScript only animates that value.

-- The reserve has no accessible player loop in the current round, so do not
-- display a battery state that weapons no longer consume.
local ENABLED = false
if not ENABLED then return end

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local chargeEvent = ReplicatedStorage:WaitForChild("LaserEnergyChargeState")

local MAX_ENERGY = 600
local LOW_ENERGY_RATIO = 0.20
local SHOT_FEEDBACK_DELAY = 0.30
local ENERGY_DEPLETED_SOUND = "rbxassetid://137787508848769"
-- Deliberately matches MonsterBlasterClient's existing cooldown/no-power sound.
local ENERGY_SHUTDOWN_SOUND = "rbxassetid://124307033081669"

local gui = Instance.new("ScreenGui")
gui.Name = "LaserEnergyHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local reserve = Instance.new("Frame")
reserve.Name = "Reserve"
reserve.AnchorPoint = Vector2.new(1, 0)
reserve.BackgroundColor3 = Color3.fromRGB(4, 15, 26)
reserve.BackgroundTransparency = 0.22
reserve.BorderSizePixel = 0
reserve.Parent = gui
Instance.new("UICorner", reserve).CornerRadius = UDim.new(0, 5)
local reserveStroke = Instance.new("UIStroke")
reserveStroke.Color = Color3.fromRGB(57, 87, 107)
reserveStroke.Transparency = 0.45
reserveStroke.Parent = reserve

local reserveFill = Instance.new("Frame")
reserveFill.Name = "Fill"
reserveFill.Size = UDim2.fromScale(1, 1)
reserveFill.BackgroundColor3 = Color3.fromRGB(0, 220, 215)
reserveFill.BorderSizePixel = 0
reserveFill.Parent = reserve
Instance.new("UICorner", reserveFill).CornerRadius = UDim.new(0, 5)

local chargePanel = Instance.new("Frame")
chargePanel.Name = "ChargeProgress"
chargePanel.AnchorPoint = Vector2.new(0.5, 0.5)
chargePanel.Position = UDim2.fromScale(0.5, 0.56)
chargePanel.Size = UDim2.fromOffset(650, 26)
chargePanel.BackgroundColor3 = Color3.fromRGB(2, 21, 29)
chargePanel.BackgroundTransparency = 0.10
chargePanel.BorderSizePixel = 0
chargePanel.Visible = false
chargePanel.Parent = gui
Instance.new("UICorner", chargePanel).CornerRadius = UDim.new(0, 4)

local chargeBolt = Instance.new("TextLabel")
chargeBolt.BackgroundTransparency = 1
chargeBolt.AnchorPoint = Vector2.new(1, 0.5)
chargeBolt.Position = UDim2.new(0, -16, 0.5, 0)
chargeBolt.Size = UDim2.fromOffset(44, 44)
chargeBolt.Font = Enum.Font.GothamBlack
chargeBolt.Text = "ϟ"
chargeBolt.TextColor3 = Color3.fromRGB(0, 230, 224)
chargeBolt.TextSize = 42
chargeBolt.Parent = chargePanel

local chargeFill = Instance.new("Frame")
chargeFill.Name = "Fill"
chargeFill.Size = UDim2.fromScale(0, 1)
chargeFill.BackgroundColor3 = Color3.fromRGB(0, 220, 215)
chargeFill.BorderSizePixel = 0
chargeFill.Parent = chargePanel
Instance.new("UICorner", chargeFill).CornerRadius = UDim.new(0, 4)

local function layout()
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local compact = viewport.X < 1025
	reserve.Position = UDim2.new(1, compact and -12 or -24, 0, compact and 86 or 112)
	reserve.Size = UDim2.fromOffset(compact and 185 or 450, compact and 10 or 16)
	chargePanel.Size = UDim2.fromOffset(math.min(compact and 360 or 650, viewport.X - 90), compact and 18 or 26)
end
layout()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
end

local function playLocalSound(name, soundId)
	local source = SoundService:FindFirstChild(name, true)
	local sound = source and source:IsA("Sound") and source:Clone() or Instance.new("Sound")
	sound.Name = name
	if sound.SoundId == "" then sound.SoundId = soundId end
	sound.Volume = sound.Volume > 0 and sound.Volume or 1
	sound.Parent = gui
	sound:Play()
	Debris:AddItem(sound, 5)
end

local shownEnergy = math.clamp(tonumber(player:GetAttribute("LaserEnergy")) or MAX_ENERGY, 0, MAX_ENERGY)
local charging = false

local function showEnergy(energy, duration)
	shownEnergy = math.clamp(energy, 0, MAX_ENERGY)
	TweenService:Create(reserveFill, TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(shownEnergy / MAX_ENERGY, 1),
	}):Play()
	if charging then
		chargeFill.Size = UDim2.fromScale(shownEnergy / MAX_ENERGY, 1)
	end
end
showEnergy(shownEnergy, 0)

local previousEnergy = shownEnergy
player:GetAttributeChangedSignal("LaserEnergy"):Connect(function()
	local energy = math.clamp(tonumber(player:GetAttribute("LaserEnergy")) or 0, 0, MAX_ENERGY)
	local wasEnergy = previousEnergy
	previousEnergy = energy
	if charging or energy > wasEnergy then
		showEnergy(energy, charging and 0.08 or 0.16)
		return
	end
	if energy >= wasEnergy then return end

	-- Delayed shrink makes each accepted shot visibly register after its beam.
	task.delay(SHOT_FEEDBACK_DELAY, function()
		showEnergy(energy, 0.20)
		if energy <= 0 then
			playLocalSound("EnergyShutdown", ENERGY_SHUTDOWN_SOUND)
		elseif energy / MAX_ENERGY < LOW_ENERGY_RATIO then
			playLocalSound("EnergyDepleted", ENERGY_DEPLETED_SOUND)
		end
	end)
end)

chargeEvent.OnClientEvent:Connect(function(state)
	if state == "Start" then
		charging = true
		chargePanel.Visible = true
		showEnergy(tonumber(player:GetAttribute("LaserEnergy")) or 0, 0)
	elseif state == "Complete" then
		charging = false
		showEnergy(MAX_ENERGY, 0.16)
		task.delay(0.35, function() chargePanel.Visible = false end)
	elseif state == "Cancel" then
		charging = false
		chargePanel.Visible = false
	end
end)

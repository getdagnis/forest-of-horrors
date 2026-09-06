-- SpeedCoilRuntime
-- Active only inside a granted SpeedCoil Tool clone.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local DURATION_SECONDS = 60
local SPEED_BOOST = 20
local SPEED_FOR_SMOKE = 20

local character
local player
local humanoid
local root
local originalSpeed
local timerConnection
local runningConnection
local smoke
local remaining = math.clamp(tonumber(tool:GetAttribute("SpeedCoilRemaining")) or DURATION_SECONDS, 0, DURATION_SECONDS)

local function publish(equipped)
	tool:SetAttribute("SpeedCoilRemaining", remaining)
	tool:SetAttribute("SpeedCoilEquipped", equipped == true)
	if player then
		player:SetAttribute("SpeedCoilRemaining", remaining)
		player:SetAttribute("SpeedCoilEquipped", equipped == true)
	end
end

local function clearSmoke()
	if smoke then
		smoke:Destroy()
		smoke = nil
	end
end

local function stop()
	if timerConnection then timerConnection:Disconnect(); timerConnection = nil end
	if runningConnection then runningConnection:Disconnect(); runningConnection = nil end
	clearSmoke()
	if originalSpeed ~= nil and humanoid and humanoid.Parent and humanoid.Health > 0 then
		humanoid.WalkSpeed = originalSpeed
	end
	originalSpeed = nil
	publish(false)
end

local function playPowerOut()
	local source = SoundService:FindFirstChild("PowerOut")
	if not (source and source:IsA("Sound")) then return end
	local sound = source:Clone()
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 2) + 1)
end

local function start()
	if tool.Parent ~= character or not humanoid or humanoid.Health <= 0 or remaining <= 0 or originalSpeed ~= nil then
		publish(false)
		return
	end
	originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = originalSpeed + SPEED_BOOST
	publish(true)

	runningConnection = humanoid.Running:Connect(function(speed)
		if speed >= SPEED_FOR_SMOKE and root and root.Parent then
			if not smoke then
				smoke = Instance.new("Smoke")
				smoke.Name = "SpeedCoilSmoke"
				smoke.Parent = root
			end
		else
			clearSmoke()
		end
	end)

	timerConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if tool.Parent ~= character or not humanoid.Parent or humanoid.Health <= 0 then
			stop()
			return
		end
		remaining = math.max(0, remaining - deltaTime)
		publish(true)
		if remaining <= 0 then
			playPowerOut()
			stop()
		end
	end)
end

tool:GetAttributeChangedSignal("SpeedCoilRemaining"):Connect(function()
	remaining = math.clamp(tonumber(tool:GetAttribute("SpeedCoilRemaining")) or 0, 0, DURATION_SECONDS)
	if originalSpeed == nil then publish(false) end
end)

tool.Equipped:Connect(function()
	character = tool.Parent
	player = Players:GetPlayerFromCharacter(character)
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	root = character and character:FindFirstChild("HumanoidRootPart")
	local equip = handle:FindFirstChild("Equip")
	if equip and equip:IsA("Sound") then equip:Play() end
	start()
end)

tool.Unequipped:Connect(stop)
tool.AncestryChanged:Connect(function()
	if character and tool.Parent ~= character then stop() end
end)
tool.Destroying:Connect(stop)

tool:SetAttribute("SpeedCoilRemaining", remaining)
tool:SetAttribute("SpeedCoilEquipped", false)

-- Makes each marked PowerSwitch model a physical, cross-platform toggle.
-- The lever moves around its lowest local-X edge, which is the bottom of the
-- imported Switch model in its authored orientation.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SWITCH_NAME = "PowerSwitch"
local LEVER_NAME = "Switch"
local TURN_ON_ANGLE = math.rad(-30)
local TOGGLE_DURATION = 0.22
local ACTIVATION_DISTANCE = 10
local AUTO_OFF_SECONDS = 120

local bound = {}

local function isPowerSwitch(instance)
	return (instance:IsA("Model") or instance:IsA("BasePart"))
		and (instance.Name == SWITCH_NAME or instance:GetAttribute(SWITCH_NAME) == true)
end

local function findLeverModel(powerSwitch)
	for _, child in ipairs(powerSwitch:GetChildren()) do
		if child.Name == LEVER_NAME and child:IsA("Model") then
			return child
		end
	end
	return nil
end

local function findLeverPart(lever)
	return lever:FindFirstChildWhichIsA("BasePart", true)
end

local function findSwitchSound(powerSwitch, soundName)
	for _, child in ipairs(powerSwitch:GetChildren()) do
		if child.Name == soundName and child:IsA("Sound") then
			return child
		end
	end
	return nil
end

local function getOffPivot(lever)
	local value = lever:FindFirstChild("PowerSwitchOffPivot")
	if value and value:IsA("CFrameValue") then return value.Value end

	value = Instance.new("CFrameValue")
	value.Name = "PowerSwitchOffPivot"
	value.Value = lever:GetPivot()
	value.Parent = lever
	return value.Value
end

local function getHingeX(lever, offPivot)
	local value = lever:FindFirstChild("PowerSwitchHingeX")
	if value and value:IsA("NumberValue") then return value.Value end

	local lowestX = math.huge
	for _, part in ipairs(lever:GetDescendants()) do
		if part:IsA("BasePart") then
			local half = part.Size * 0.5
			for _, x in ipairs({ -half.X, half.X }) do
				for _, y in ipairs({ -half.Y, half.Y }) do
					for _, z in ipairs({ -half.Z, half.Z }) do
						local worldPoint = part.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
						lowestX = math.min(lowestX, offPivot:PointToObjectSpace(worldPoint).X)
					end
				end
			end
		end
	end
	if lowestX == math.huge then lowestX = 0 end

	value = Instance.new("NumberValue")
	value.Name = "PowerSwitchHingeX"
	value.Value = lowestX
	value.Parent = lever
	return lowestX
end

local function getOnPivot(offPivot, hingeX)
	return offPivot
		* CFrame.new(hingeX, 0, 0)
		* CFrame.Angles(0, 0, TURN_ON_ANGLE)
		* CFrame.new(-hingeX, 0, 0)
end

local function bindPowerSwitch(powerSwitch)
	if bound[powerSwitch] or not isPowerSwitch(powerSwitch) then return end
	local lever = findLeverModel(powerSwitch)
	local promptPart = lever and findLeverPart(lever)
	if not (lever and promptPart) then
		warn("[PowerSwitch] missing Switch model or a BasePart:", powerSwitch:GetFullName())
		return
	end
	bound[powerSwitch] = true

	local offPivot = getOffPivot(lever)
	local hingeX = getHingeX(lever, offPivot)
	local onPivot = getOnPivot(offPivot, hingeX)
	local state = powerSwitch:GetAttribute("PowerSwitchOn") == true
	lever:PivotTo(state and onPivot or offPivot)

	local prompt = promptPart:FindFirstChild("PowerSwitchPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "PowerSwitchPrompt"
		prompt.ObjectText = "Power Switch"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = ACTIVATION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.ClickablePrompt = true
		prompt.Parent = promptPart
	end

	local pivot = Instance.new("CFrameValue")
	pivot.Value = lever:GetPivot()
	pivot:GetPropertyChangedSignal("Value"):Connect(function()
		if lever.Parent then lever:PivotTo(pivot.Value) end
	end)

	local function updatePrompt()
		prompt.ActionText = state and "Turn off" or "Turn on"
	end
	local autoOffToken = 0
	local busy = false
	local function setState(nextState)
		state = nextState
		powerSwitch:SetAttribute("PowerSwitchOn", state)
		updatePrompt()

		local sound = findSwitchSound(powerSwitch, state and LEVER_NAME or "PowerOff")
		if sound then
			sound:Stop()
			sound.TimePosition = 0
			sound:Play()
		end

		TweenService:Create(pivot, TweenInfo.new(TOGGLE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Value = state and onPivot or offPivot,
		}):Play()
		autoOffToken += 1
		if state then
			local token = autoOffToken
			task.delay(AUTO_OFF_SECONDS, function()
				if token == autoOffToken and state and powerSwitch.Parent then
					setState(false)
				end
			end)
		end
	end
	updatePrompt()

	prompt.Triggered:Connect(function()
		if busy then return end
		busy = true
		setState(not state)
		task.delay(TOGGLE_DURATION, function() busy = false end)
	end)

	warn("[PowerSwitch] ready:", powerSwitch:GetFullName())
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	bindPowerSwitch(instance)
end

Workspace.DescendantAdded:Connect(function(instance)
	task.defer(bindPowerSwitch, instance)
end)

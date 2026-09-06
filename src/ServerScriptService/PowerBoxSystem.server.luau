-- PowerBoxSystem Server Script
-- Generic MonsterBlaster charge stations. A station and a PowerSwitch with the
-- same PowerNetwork string form a pair. Set PowersAllPowerBoxes=true on a
-- switch when it should energize every station instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))

local CHARGE_DURATION = 8.8
local DING_TIME = 8.5
local ACTIVATION_DISTANCE = 12
local BLASTER_NAME = "MonsterBlaster"
local GLOW_COLOR = Color3.fromRGB(62, 169, 255)

local stations = {}
local watchedSwitches = {}

local function isPowerBox(instance)
	return instance:IsA("Model")
		and (instance:GetAttribute("MonsterBlasterPowerBox") == true or instance.Name:sub(1, 8) == "PowerBox")
end

local function isPowerSwitch(instance)
	return (instance:IsA("Model") or instance:IsA("BasePart"))
		and (instance.Name == "PowerSwitch" or instance:GetAttribute("PowerSwitch") == true)
end

local function getNetwork(instance)
	local network = instance:GetAttribute("PowerNetwork")
	return type(network) == "string" and network or ""
end

local function getSound(station, name)
	local sound = station:FindFirstChild(name, true)
	return sound and sound:IsA("Sound") and sound or nil
end

local function findPromptPart(station)
	local explicitPart = station:FindFirstChild("ChargePromptPart", true)
	if explicitPart and explicitPart:IsA("BasePart") then return explicitPart end

	local cover = station:FindFirstChild("Cover", true)
	if cover and cover:IsA("BasePart") then return cover end

	local outerPart = station:FindFirstChild("Part")
	if outerPart and outerPart:IsA("BasePart") then return outerPart end

	return station:FindFirstChildWhichIsA("BasePart", true)
end

local function setStationEffects(station, enabled)
	local effects = station.effects
	if effects then
		for _, descendant in ipairs(effects:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then descendant.Enabled = enabled end
		end
	end

	if station.electricitySfx then
		if enabled then
			if not station.electricitySfx.IsPlaying then station.electricitySfx:Play() end
		else
			station.electricitySfx:Stop()
		end
	end

	for _, descendant in ipairs(station.model:GetDescendants()) do
		if descendant:IsA("Light") then descendant.Enabled = enabled end
	end
end

local function findPlayerBlaster(player)
	for _, container in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		local tool = container and container:FindFirstChild(BLASTER_NAME)
		if tool and tool:IsA("Tool") then return tool end
	end
	return nil
end

local function setBlasterGlow(tool, enabled, glowState)
	if enabled then
		local states = {}
		for _, descendant in ipairs(tool:GetDescendants()) do
			if descendant:IsA("BasePart") then
				states[descendant] = { color = descendant.Color, material = descendant.Material }
				descendant.Color = GLOW_COLOR
				descendant.Material = Enum.Material.Neon
			end
		end
		return states
	end

	for part, visual in pairs(glowState or {}) do
		if part.Parent then
			part.Color = visual.color
			part.Material = visual.material
		end
	end
end

local function isPoweredBySwitch(station)
	if station.model:GetAttribute("AlwaysPowered") == true then return true end
	local network = getNetwork(station.model)
	if network == "" then return false end

	for powerSwitch in pairs(watchedSwitches) do
		if powerSwitch.Parent and powerSwitch:GetAttribute("PowerSwitchOn") == true then
			if powerSwitch:GetAttribute("PowersAllPowerBoxes") == true or getNetwork(powerSwitch) == network then
				return true
			end
		end
	end
	return false
end

local function stopCharge(station, completed)
	local charge = station.charge
	if not charge then return end
	station.charge = nil
	if station.chargeSound then station.chargeSound:Stop() end
	setBlasterGlow(charge.tool, false, charge.glowState)
	if station.prompt.Parent then station.prompt.Enabled = station.powered end
	if not completed then return end

	charge.player:SetAttribute(Config.PLAYER_CHARGE_ATTRIBUTE, Config.MAX_CHARGE_UNITS)
	charge.tool:SetAttribute(Config.CHARGE_ATTRIBUTE, Config.MAX_CHARGE_UNITS)
	if station.successSound then
		station.successSound:Stop()
		station.successSound.TimePosition = 0
		station.successSound:Play()
	end
end

local function setStationPowered(station, powered)
	if station.powered == powered then return end
	station.powered = powered
	station.model:SetAttribute("PowerBoxPowered", powered)
	setStationEffects(station, powered)
	if not powered then stopCharge(station, false) end
	if station.prompt.Parent and not station.charge then station.prompt.Enabled = powered end
end

local function refreshStation(station)
	setStationPowered(station, isPoweredBySwitch(station))
end

local function refreshAllStations()
	for _, station in pairs(stations) do
		if station.model.Parent then refreshStation(station) end
	end
end

local function startCharge(station, player)
	if not station.powered or station.charge then return end
	local tool = findPlayerBlaster(player)
	if not tool then return end

	station.charge = {
		player = player,
		tool = tool,
		glowState = setBlasterGlow(tool, true),
	}
	station.prompt.Enabled = false
	if station.chargeSound then
		station.chargeSound:Stop()
		station.chargeSound.TimePosition = 0
		station.chargeSound:Play()
	end

	task.spawn(function()
		local charge = station.charge
		local startedAt = os.clock()
		local dingPlayed = false
		while station.charge == charge do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not station.powered or not root or not humanoid or humanoid.Health <= 0
				or (root.Position - station.promptPart.Position).Magnitude > ACTIVATION_DISTANCE
			then
				stopCharge(station, false)
				return
			end

			local elapsed = os.clock() - startedAt
			if not dingPlayed and elapsed >= DING_TIME then
				dingPlayed = true
				if station.dingSound then
					station.dingSound:Stop()
					station.dingSound.TimePosition = 0
					station.dingSound:Play()
				end
			end
			if elapsed >= CHARGE_DURATION then
				stopCharge(station, true)
				return
			end
			task.wait(0.05)
		end
	end)
end

local function setupStation(model)
	if stations[model] or not isPowerBox(model) then return end
	local promptPart = findPromptPart(model)
	if not promptPart then
		warn("[PowerBox] no BasePart available for charging prompt:", model:GetFullName())
		return
	end

	local prompt = promptPart:FindFirstChild("MonsterBlasterChargePrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MonsterBlasterChargePrompt"
		prompt.ObjectText = "MonsterBlaster Charger"
		prompt.ActionText = "Charge Blaster"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = ACTIVATION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.ClickablePrompt = true
		prompt.Parent = promptPart
	end

	local effects = model:FindFirstChild("ElectricityEffects", true)
	local station = {
		model = model,
		promptPart = promptPart,
		prompt = prompt,
		effects = effects,
		electricitySfx = effects and effects:FindFirstChild("ElectricitySFX", true) or getSound(model, "ElectricitySFX"),
		chargeSound = getSound(model, "BonusChargeUp"),
		dingSound = getSound(model, "DING"),
		successSound = getSound(model, "ChargeSuccess"),
		powered = nil,
		charge = nil,
	}
	stations[model] = station
	prompt.Triggered:Connect(function(player) startCharge(station, player) end)
	model:GetAttributeChangedSignal("PowerNetwork"):Connect(refreshAllStations)
	model:GetAttributeChangedSignal("AlwaysPowered"):Connect(function() refreshStation(station) end)
	setStationPowered(station, false)
	refreshStation(station)
	warn("[PowerBox] ready:", model:GetFullName())
end

local function watchSwitch(instance)
	if watchedSwitches[instance] or not isPowerSwitch(instance) then return end
	watchedSwitches[instance] = true
	instance:GetAttributeChangedSignal("PowerSwitchOn"):Connect(refreshAllStations)
	instance:GetAttributeChangedSignal("PowerNetwork"):Connect(refreshAllStations)
	instance:GetAttributeChangedSignal("PowersAllPowerBoxes"):Connect(refreshAllStations)
end

local bonuses = Workspace:FindFirstChild("Bonuses")
for _, instance in ipairs(bonuses and bonuses:GetDescendants() or {}) do
	setupStation(instance)
	watchSwitch(instance)
end

for _, instance in ipairs(Workspace:GetChildren()) do
	setupStation(instance)
	watchSwitch(instance)
end

Workspace.DescendantAdded:Connect(function(instance)
	task.defer(function()
		setupStation(instance)
		watchSwitch(instance)
		refreshAllStations()
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	for _, station in pairs(stations) do
		if station.charge and station.charge.player == player then stopCharge(station, false) end
	end
end)

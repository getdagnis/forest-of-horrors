-- RadarTowerSystem: author-owned controls for the single restored pilot tower.
-- The old RadarSeat/RadarScreen hierarchy is visual scenery only. At runtime we
-- create one explicit RadarTowerConsole Part at the legacy display and own its
-- prompt, click target, HUD event, and local-audio anchor from this script.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local PILOT_TOWER_PREFIX = "MGT"
local ACTIVATION_DISTANCE = 16

local event = ReplicatedStorage:FindFirstChild("RadarTowerUse")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "RadarTowerUse"
	event.Parent = ReplicatedStorage
end

local activeSources = {}
local pilotTower
local console

-- The server sees the complete map even when client streaming hides distant
-- monsters. Keep a small registry instead of scanning all Workspace parts for
-- every radar refresh.
local snapshotEvent = ReplicatedStorage:FindFirstChild("RadarTowerSnapshot")
if not snapshotEvent then
	snapshotEvent = Instance.new("RemoteEvent")
	snapshotEvent.Name = "RadarTowerSnapshot"
	snapshotEvent.Parent = ReplicatedStorage
end
local trackedMonsters = {}

local function refreshTrackedMonster(instance)
	if not instance:IsA("Model") then return end
	local tracked = MonsterManager.isRoundTracked(instance)
		and instance:GetAttribute("RoundManagedMonster") == true
		and (
			Workspace:GetAttribute("UndergroundPhaseActive") == true
			or instance:GetAttribute("UndergroundMonster") ~= true
		)
	if tracked then trackedMonsters[instance] = true else trackedMonsters[instance] = nil end
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	if instance:IsA("Model") and MonsterManager.getConfig(instance) then
		refreshTrackedMonster(instance)
		instance:GetAttributeChangedSignal("RoundManagedMonster"):Connect(function()
			refreshTrackedMonster(instance)
		end)
		instance:GetAttributeChangedSignal("RoundTracked"):Connect(function()
			refreshTrackedMonster(instance)
		end)
		instance:GetAttributeChangedSignal("UndergroundMonster"):Connect(function()
			refreshTrackedMonster(instance)
		end)
	end
end
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") and MonsterManager.getConfig(instance) then
		task.defer(refreshTrackedMonster, instance)
		instance:GetAttributeChangedSignal("RoundManagedMonster"):Connect(function()
			refreshTrackedMonster(instance)
		end)
		instance:GetAttributeChangedSignal("RoundTracked"):Connect(function()
			refreshTrackedMonster(instance)
		end)
		instance:GetAttributeChangedSignal("UndergroundMonster"):Connect(function()
			refreshTrackedMonster(instance)
		end)
	end
end)
Workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("Model") then trackedMonsters[instance] = nil end
end)
Workspace:GetAttributeChangedSignal("UndergroundPhaseActive"):Connect(function()
	-- The phase changes once before a restart. Rebuild the bounded contact set
	-- immediately so active tower clients receive the newly relevant monsters.
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") and MonsterManager.getConfig(instance) then
			refreshTrackedMonster(instance)
		end
	end
end)

local function sendRadarSnapshot(player)
	local records = {}
	for instance in pairs(trackedMonsters) do
		if instance.Parent ~= nil then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			local root = MonsterManager.getMonsterRoot(instance)
			if humanoid and humanoid.Health > 0 and root then
				table.insert(records, {
					name = instance.Name,
					position = root.Position,
					guardian = instance.Name == "weird monster thing"
						and instance:GetAttribute("WMTGuardianPet") == true,
					secretShaftGuardian = instance:GetAttribute("SecretShaftDoorGuard") == true,
				})
			end
		end
	end
	snapshotEvent:FireClient(player, records)
end

local function hideRadar(player, source)
	local active = activeSources[player]
	if source and (not active or active.source ~= source) then return end
	activeSources[player] = nil
	event:FireClient(player, false)
	warn("[RadarTower] closed for", player.Name)
end

local function showRadar(player, source, kind)
	if not (player and source and source.Parent) then return end
	activeSources[player] = { source = source, kind = kind }
	event:FireClient(player, true, source.Parent)
	sendRadarSnapshot(player)
	warn("[RadarTower] opened for", player.Name, "via", kind)
end

local function firstDescendant(parent, name, className)
	for _, instance in ipairs(parent:GetDescendants()) do
		if instance.Name == name and (not className or instance:IsA(className)) then
			return instance
		end
	end
	return nil
end

local function disableLegacyRadarScript(displayPart)
	for _, instance in ipairs(displayPart:GetDescendants()) do
		if instance:IsA("Script") and instance.Name == "RadarScript" then
			instance.Disabled = true
			warn("[RadarTower] disabled legacy RadarScript:", instance:GetFullName())
		end
	end
end

local function prepareAudio()
	for _, soundName in ipairs({ "RadarYacht", "RadarLoop" }) do
		local sound = firstDescendant(pilotTower, soundName, "Sound")
		if sound then
			sound.Looped = true
			sound.Playing = false
			warn("[RadarTower] prepared local " .. soundName .. ":", sound:GetFullName())
		else
			warn("[RadarTower] missing " .. soundName)
		end
	end
end

local function createConsole(displayPart)
	local console = pilotTower:FindFirstChild("RadarTowerConsole")
	if console and not console:IsA("BasePart") then
		warn("[RadarTower] RadarTowerConsole exists but is not a BasePart")
		return false
	end
	if not console then
		console = Instance.new("Part")
		console.Name = "RadarTowerConsole"
		console.Size = Vector3.new(3, 3, 0.5)
		console.CFrame = displayPart.CFrame
		console.Anchored = true
		console.CanCollide = false
		console.CanTouch = false
		console.CanQuery = false
		console.Transparency = 1
		console.Parent = pilotTower
		warn("[RadarTower] created author-owned console at:", displayPart:GetFullName())
	end

	-- These runtime attributes are only for the HUD's audio-position lookup.
	pilotTower:SetAttribute("RadarTower", true)
	console:SetAttribute("RadarTowerScreen", true)

	local prompt = console:FindFirstChild("RadarTowerPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RadarTowerPrompt"
		prompt.ActionText = "Use Radar"
		prompt.ObjectText = "Radar Console"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = ACTIVATION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = console
	end
	prompt.Triggered:Connect(function(player)
		showRadar(player, console, "console prompt")
	end)

	local detector = console:FindFirstChild("RadarTowerClick")
	if not detector then
		detector = Instance.new("ClickDetector")
		detector.Name = "RadarTowerClick"
		detector.MaxActivationDistance = ACTIVATION_DISTANCE
		detector.Parent = console
	end
	detector.MouseClick:Connect(function(player)
		showRadar(player, console, "console click")
	end)

	warn("[RadarTower] console ready:", console:GetFullName())
	return true
end

local function bootstrap()
	local towers = {}
	for _, child in ipairs(Workspace:GetChildren()) do
		if string.sub(child.Name, 1, #PILOT_TOWER_PREFIX) == PILOT_TOWER_PREFIX and child:IsA("Model") then
			table.insert(towers, child)
		end
	end

	if #towers == 0 then
		warn("[RadarTower] bootstrap failed: no Workspace models with prefix '" .. PILOT_TOWER_PREFIX .. "' found")
		return
	end

	for _, tower in ipairs(towers) do
		pilotTower = tower

		local cockpit = firstDescendant(pilotTower, "RadarCockpit", "Model")
		local screenModel = cockpit and firstDescendant(cockpit, "RadarScreen", "Model")
		local displayPart = screenModel and screenModel:FindFirstChild("Drag", true)
		if not (displayPart and displayPart:IsA("BasePart")) then
			warn("[RadarTower] bootstrap skipped: RadarCockpit.RadarSystem.RadarScreen.Drag missing in", pilotTower:GetFullName())
			continue
		end

		disableLegacyRadarScript(displayPart)
		prepareAudio()
		createConsole(displayPart)
	end
end

warn("[RadarTower] server started; creating the pilot console")
bootstrap()

event.OnServerEvent:Connect(function(player, enabled)
	if enabled == false then hideRadar(player) end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		for player, active in pairs(activeSources) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local source = active.source
			if not source or not source.Parent or not root
				or (root.Position - source.Position).Magnitude > ACTIVATION_DISTANCE
			then
				hideRadar(player, source)
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(10)
		for player in pairs(activeSources) do
			sendRadarSnapshot(player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeSources[player] = nil
end)

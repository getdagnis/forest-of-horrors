-- TurretCombatClient > StarterPlayerScripts (LocalScript)
--
-- Network bridge for all mounted legacy guns.  The model-local `control`
-- LocalScript may continue to turn the imported model and play its original
-- effects, but it must never be the only path that reports a shot to the
-- authoritative server combat system.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local FIRE_INTERVAL = 0.10
local TURRET_CROSSHAIR = "rbxassetid://138865017"
local TURRET_CURSOR_RANGE = 30

local firing = false
local activeTurret = nil
local nextShotAt = 0
local lastState = ""
local lastSendLogAt = 0
local previousMouseIcon = ""
local crosshairShown = false
local knownTurrets = {}

local function considerTurret(instance)
	if instance:IsA("Model") and instance:GetAttribute("Turret") == true then
		knownTurrets[instance] = true
		instance.Destroying:Once(function() knownTurrets[instance] = nil end)
	end
end

for _, instance in ipairs(workspace:GetDescendants()) do considerTurret(instance) end
workspace.DescendantAdded:Connect(considerTurret)

local function setTurretCrosshair(visible)
	if visible == crosshairShown then return end
	crosshairShown = visible
	if visible then
		previousMouseIcon = mouse.Icon
		mouse.Icon = TURRET_CROSSHAIR
	else
		mouse.Icon = previousMouseIcon
	end
end

local function report(state)
	if state == lastState then return end
	lastState = state
	warn("[TurretCombatClient] " .. state)
	if activeTurret then activeTurret:SetAttribute("TurretClientStatus", state) end
end

local function findTurretFromSeat(seat)
	local current = seat
	while current and current ~= workspace do
		if current:IsA("Model") and current:GetAttribute("Turret") == true then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getSeatedTurret()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not (seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat"))) then return nil end
	return findTurretFromSeat(seat)
end

local function getNearbyMountedTurret()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return nil end
	for instance in pairs(knownTurrets) do
		local seat = instance:FindFirstChild("MachineGunSeat", true)
		if seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat"))
			and (root.Position - seat.Position).Magnitude <= TURRET_CURSOR_RANGE
		then
			return instance
		end
	end
	return nil
end

local function refreshTurret()
	local turret = getSeatedTurret() or getNearbyMountedTurret()
	if turret ~= activeTurret then
		activeTurret = turret
		firing = false
		if turret then
			setTurretCrosshair(true)
			report("ready at " .. turret:GetFullName())
		else
			setTurretCrosshair(false)
			report("not seated at a Turret=true model")
		end
	end
	return turret
end

local function sendShot()
	local turret = refreshTurret()
	if not turret then return end
	local event = ReplicatedStorage:FindFirstChild("TurretShot")
	if not (event and event:IsA("RemoteEvent")) then
		report("TurretShot RemoteEvent is missing")
		return
	end

	local now = os.clock()
	if now < nextShotAt then return end
	nextShotAt = now + FIRE_INTERVAL
	event:FireServer(turret, mouse.Hit.Position)
	turret:SetAttribute("TurretClientLastShotAt", workspace:GetServerTimeNow())
	if now - lastSendLogAt >= 1 then
		lastSendLogAt = now
		report("sent shot to " .. turret.Name)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if not refreshTurret() then return end
	firing = true
	sendShot()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = false end
end)

RunService.RenderStepped:Connect(function()
	refreshTurret()
	if firing then sendShot() end
end)

player.CharacterAdded:Connect(function()
	activeTurret = nil
	firing = false
	setTurretCrosshair(false)
	report("character respawned; waiting for a turret seat")
end)

report("started")

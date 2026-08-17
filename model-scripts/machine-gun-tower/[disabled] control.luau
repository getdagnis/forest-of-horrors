-- control > MountedTurretSeat server Script (disabled LocalScript template)
--
-- This runs only after MountedTurretSeat clones it into the seated player's
-- Character.  It owns client presentation and aiming; TurretCombatSystem owns
-- all authoritative damage, score, and kill credit on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local character = script.Parent
local turretValue = script:WaitForChild("Value")
local turret = turretValue.Value
if not (turret and turret:IsA("Model")) then
	warn("[MountedTurret] controller received no turret Model")
	script:Destroy()
	return
end

local humanoid = character:FindFirstChildOfClass("Humanoid")
-- This explicitly named Seat is the model's only gameplay gunner Seat. Do not
-- pick the first decorative imported Seat from the rest of the tower.
local seat = turret:FindFirstChild("MachineGunSeat", true)
local mouse = player:GetMouse()
local previousMouseIcon = mouse.Icon
-- The imported tower supplied this small yellow aiming reticle.  It is useful
-- here because firing is locked to the mounted gun rather than the handheld
-- weapon crosshair, so restore it while this controller is active.
mouse.Icon = "rbxassetid://138865017"
mouse.TargetFilter = turret

local gunModel = turret:FindFirstChild("gun")
local bodyModel = turret:FindFirstChild("body")
local base = turret:FindFirstChild("base", true)
if not (gunModel and gunModel:IsA("Model") and bodyModel and bodyModel:IsA("Model") and base and base:IsA("BasePart")) then
	warn("[MountedTurret] missing gun/body/base under", turret:GetFullName())
	script:Destroy()
	return
end

local FIRE_INTERVAL = 0.10
local firing = false
local nextShotAt = 0
local round = 1
local alive = true
local warnedMissingBridge = false

local function getBarrel(index)
	local name = index == 1 and "gunpart" or "gunpart2"
	local barrel = gunModel:FindFirstChild(name, true)
	return barrel and barrel:IsA("BasePart") and barrel or nil
end

local function emitNamed(container, name, amount)
	local emitter = container and container:FindFirstChild(name, true)
	if emitter and emitter:IsA("ParticleEmitter") then emitter:Emit(amount) end
end

local function playSound(container, name)
	local sound = container and container:FindFirstChild(name, true)
	if sound and sound:IsA("Sound") then sound:Play() end
end

local function showTracer(origin, target)
	local distance = (target - origin).Magnitude
	if distance < 0.1 then return end
	local tracer = Instance.new("Part")
	tracer.Name = "TurretTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 220, 70)
	tracer.Size = Vector3.new(0.12, 0.12, distance)
	tracer.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.06)
end

local function playMuzzlePresentation(index)
	local effectName = index == 1 and "effect" or "effect2"
	local barrelName = index == 1 and "barrel" or "barrel2"
	local effect = gunModel:FindFirstChild(effectName, true)
	playSound(effect, "bam")
	emitNamed(effect, "ParticleEmitter", 8)
	emitNamed(effect, "smoke", 2)

	-- Retain the original short barrel recoil when the imported Mesh exposes
	-- Offset.  Models without that old Mesh simply skip this cosmetic flourish.
	local barrel = gunModel:FindFirstChild(barrelName, true)
	local mesh = barrel and barrel:FindFirstChildWhichIsA("SpecialMesh")
	if not mesh then return end
	task.spawn(function()
		for step = 0, 8 do
			if not mesh.Parent then return end
			mesh.Offset = Vector3.new(0, -1.6 + step * 0.2, 0)
			RunService.RenderStepped:Wait()
		end
		if mesh.Parent then mesh.Offset = Vector3.zero end
	end)
end

local function sendAuthoritativeShot(aimPoint)
	-- Never wait for the RemoteEvent here.  A missing/disabled server bridge
	-- must not freeze the entire legacy tower's local turn/fire presentation.
	local event = ReplicatedStorage:FindFirstChild("TurretShot")
	if event and event:IsA("RemoteEvent") then
		event:FireServer(turret, aimPoint)
	elseif not warnedMissingBridge then
		warnedMissingBridge = true
		warn("[MountedTurret] TurretShot is missing: TurretCombatSystem is not running on the server")
	end
end

local function fireOneShot()
	if not alive or os.clock() < nextShotAt then return end
	nextShotAt = os.clock() + FIRE_INTERVAL
	local barrel = getBarrel(round)
	if not barrel then return end

	local origin = barrel.Position + barrel.CFrame.LookVector * 5
	local aimPoint = mouse.Hit.Position
	sendAuthoritativeShot(aimPoint)
	showTracer(origin, aimPoint)
	playMuzzlePresentation(round)
	round = round == 1 and 2 or 1
end

local function stop()
	if not alive then return end
	alive = false
	firing = false
	if mouse.TargetFilter == turret then mouse.TargetFilter = nil end
	mouse.Icon = previousMouseIcon
	script:Destroy()
end

mouse.Button1Down:Connect(function()
	if not alive then return end
	firing = true
	while firing and alive do
		fireOneShot()
		task.wait(0.02)
	end
end)
mouse.Button1Up:Connect(function() firing = false end)

if humanoid then humanoid.Died:Connect(stop) end

RunService.RenderStepped:Connect(function()
	if not alive then return end
	if not (seat and seat.Occupant and seat.Occupant.Parent == character) then
		stop()
		return
	end

	local aimPoint = mouse.Hit.Position
	if (aimPoint - base.Position).Magnitude <= 3 then return end
	local gunPivot = gunModel:GetPivot()
	local bodyPivot = bodyModel:GetPivot()
	local flatAim = Vector3.new(aimPoint.X, bodyPivot.Position.Y, aimPoint.Z)
	if (flatAim - bodyPivot.Position).Magnitude < 0.01 then return end

	-- PivotTo is the current model API.  This remains local presentation; the
	-- server independently casts from the actual tower barrel for each shot.
	gunModel:PivotTo(CFrame.lookAt(gunPivot.Position, aimPoint))
	bodyModel:PivotTo(CFrame.lookAt(bodyPivot.Position, flatAim))
end)

-- StarterPlayerScripts > GunClientController

-- Sole local input, HUD, target-lock, and cosmetic-shot controller for the
-- MonsterGun family.  Combat is always validated by MonsterGunDamageSystem.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local MonsterHitFeedback = require(ReplicatedStorage:WaitForChild("MonsterHitFeedback"))
local GunAim = require(ReplicatedStorage:WaitForChild("GunAim"))
local AimConfig = require(ReplicatedStorage:WaitForChild("GunAimConfig"))
local shotVisualEvent = ReplicatedStorage:WaitForChild("GunShotVisual")

local LOCK_ACQUIRE_DISTANCE = AimConfig.LockAcquireDistance
local LOCK_RELEASE_DISTANCE = AimConfig.LockReleaseDistance
local LOCK_CONE_DOT = AimConfig.LockConeDot
local LOCK_REFRESH_SECONDS = AimConfig.LockRefreshSeconds
local DEFAULT_COLORS = {
	MonsterGun = Color3.fromRGB(255, 105, 180),
	MonsterGun2 = Color3.fromRGB(255, 160, 225),
	MonsterGun3 = Color3.fromRGB(255, 230, 255),
}

-- Cosmetic timing only. These linger long enough to colour the nearby scene,
-- but remain well below the regular gun fire interval accumulation threshold.
local GUN_MUZZLE_LIGHT_LIFETIME = 0.12
local GUN_IMPACT_LIGHT_LIFETIME = 0.32
local GUN_BEAM_LIFETIME = 0.2
local MAX_FREE_IMPACT_ENDPOINTS = 64
local knownMonsters = {}
local freeImpactEndpoints = {}
local equippedTool
local activeHud
local lockedMonster
local lockTimer = 0
local activationConnection
local fireGun

local function isActiveRound()
	return workspace:GetAttribute("RoundState") == "Active"
end

local function currentGeneration()
	return workspace:GetAttribute("RoundGeneration")
end

local function getGunName(tool)
	if not tool or not tool:IsA("Tool") then return nil end
	local weaponName = DEFAULT_COLORS[tool.Name] and tool.Name or tool:GetAttribute("WeaponName")
	return DEFAULT_COLORS[weaponName] and weaponName or nil
end

local function getGunColor(tool)
	local configured = tool and tool:GetAttribute("ShotColor")
	if typeof(configured) == "Color3" then return configured end
	return DEFAULT_COLORS[getGunName(tool)] or DEFAULT_COLORS.MonsterGun
end

local function getDisplayPart(model)
	local preferred = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model.PrimaryPart
	if preferred and preferred:IsA("BasePart") then return preferred end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getMonsterFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function trackMonster(instance)
	if instance:IsA("Model") and MonsterManager.getConfig(instance) then
		knownMonsters[instance] = true
	end
end

for _, instance in workspace:GetDescendants() do
	trackMonster(instance)
end
workspace.DescendantAdded:Connect(trackMonster)
workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("Model") then knownMonsters[instance] = nil end
	if lockedMonster == instance then
		lockedMonster = nil
		GunAim.setLockedTarget(nil)
	end
end)

local function hasLineOfSight(tool, model, displayPart)
	if not displayPart then return false end
	local ray = GunAim.getRay(player)
	if not ray then return false end
	local offset = displayPart.Position - ray.Origin
	if offset.Magnitude < 0.01 then return true end
	local result = workspace:Raycast(ray.Origin, offset, GunAim.makeRaycastParams(player.Character, tool))
	return not result or getMonsterFromHit(result.Instance) == model
end

local function isValidLock(tool, model, maxDistance)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = model and MonsterManager.getMonsterHumanoid(model)
	local displayPart = model and getDisplayPart(model)
	if not root or not humanoid or humanoid.Health <= 0 or not displayPart then return false end
	if (displayPart.Position - root.Position).Magnitude > maxDistance then return false end
	return hasLineOfSight(tool, model, displayPart)
end

local function findLockTarget(tool)
	local camera = workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then return nil end

	local nearest, nearestDistance
	for model in pairs(knownMonsters) do
		if not model.Parent then
			knownMonsters[model] = nil
		else
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			local displayPart = getDisplayPart(model)
			if MonsterManager.isWeaponAimAssistTarget(model) and humanoid and humanoid.Health > 0 and displayPart then
				local distance = (displayPart.Position - root.Position).Magnitude
				local cameraOffset = displayPart.Position - camera.CFrame.Position
				if distance <= LOCK_ACQUIRE_DISTANCE and cameraOffset.Magnitude > 0.01
					and camera.CFrame.LookVector:Dot(cameraOffset.Unit) >= LOCK_CONE_DOT
					and (not nearestDistance or distance < nearestDistance)
					and hasLineOfSight(tool, model, displayPart) then
					nearest = model
					nearestDistance = distance
				end
			end
		end
	end
	return nearest
end

local function refreshLock(deltaTime)
	if not isActiveRound() or not equippedTool or not GunAim.isCentered(player) then
		lockedMonster = nil
		lockTimer = 0
		GunAim.setLockedTarget(nil)
		return
	end
	if lockedMonster and not isValidLock(equippedTool, lockedMonster, LOCK_RELEASE_DISTANCE) then
		lockedMonster = nil
	end
	lockTimer += deltaTime
	if not lockedMonster and lockTimer >= LOCK_REFRESH_SECONDS then
		lockTimer = 0
		lockedMonster = findLockTarget(equippedTool)
	end
	GunAim.setLockedTarget(lockedMonster)
end

local function getEquippedGun()
	local character = player.Character
	if not character then return nil end
	for _, item in character:GetChildren() do
		if getGunName(item) then return item end
	end
	return nil
end

local function destroyHud()
	if activeHud then
		activeHud:Destroy()
		activeHud = nil
	end
end

local function applyWeaponCrosshairColor(hud, color)
	local crosshair = hud and hud:FindFirstChild("Crosshair", true)
	if not crosshair or not crosshair:IsA("GuiObject") then return end
	if crosshair:IsA("Frame") then crosshair.BorderColor3 = color end
	for _, item in crosshair:GetDescendants() do
		if item:IsA("Frame") then item.BorderColor3 = color end
	end
end

local function setEquippedTool(tool)
	if equippedTool == tool then return end
	if activationConnection then
		activationConnection:Disconnect()
		activationConnection = nil
	end
	destroyHud()
	equippedTool = tool
	lockedMonster = nil
	lockTimer = 0
	GunAim.setLockedTarget(nil)
	if not tool then
		UserInputService.MouseIconEnabled = true
		return
	end
	-- Only a newly equipped MonsterGun may remove a stale Blaster HUD.  On a
	-- MonsterGun -> MonsterBlaster swap this controller receives `nil`; doing
	-- the cleanup there raced the Blaster's Equipped handler and erased its
	-- freshly rebuilt HUD.
	local staleBlasterHud = player:WaitForChild("PlayerGui"):FindFirstChild("MonsterBlasterWeaponHud")
	if staleBlasterHud then staleBlasterHud:Destroy() end
	activationConnection = tool.Activated:Connect(function()
		if equippedTool == tool and tool.Parent == player.Character then
			fireGun(tool)
		end
	end)

	local sourceHud = tool:FindFirstChild("WeaponHud")
	if sourceHud and sourceHud:IsA("ScreenGui") then
		activeHud = sourceHud:Clone()
		activeHud.Name = "GunWeaponHud"
		activeHud.ResetOnSpawn = false
		local existing = player:WaitForChild("PlayerGui"):FindFirstChild("GunWeaponHud")
		if existing then existing:Destroy() end
		activeHud.Parent = player.PlayerGui
		local ammoHud = activeHud:FindFirstChild("AmmoHud", true)
		if ammoHud and ammoHud:IsA("GuiObject") then ammoHud.Visible = false end
		applyWeaponCrosshairColor(activeHud, DEFAULT_COLORS[tool.Name] or DEFAULT_COLORS.MonsterGun)
	end
	UserInputService.MouseIconEnabled = false
end

local function updateCrosshair()
	if not activeHud then return end
	local crosshair = activeHud:FindFirstChild("Crosshair", true)
	if not crosshair or not crosshair:IsA("GuiObject") then return end

	local point, space = GunAim.getScreenPoint(player)
	if not point then return end
	if space == "viewport" then
		crosshair.Position = UDim2.fromScale(0.5, 0.5)
	else
		crosshair.Position = UDim2.fromOffset(point.X, point.Y)
	end
end


local function playShotSound(tool)
	local sound = tool:FindFirstChild("ShotSound", true)
	if not sound or not sound:IsA("Sound") then
		sound = SoundService:FindFirstChild("FallbackShotSound")
	end
	if sound and sound:IsA("Sound") then sound:Play() end
end

local function getVisibleBeamStart(tool, barrel)
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		-- Legacy MG templates put this attachment at the Barrel's centre. It is
		-- not a visible muzzle, so using it makes rapid MG3 bursts look sideways.
		local minimumTipDistance = math.max(0.15, barrel.Size.Z * 0.25)
		if (muzzle.WorldPosition - barrel.Position).Magnitude >= minimumTipDistance then
			return muzzle, false
		end
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "VisualMuzzle"
	-- Existing MonsterGun barrels use their local -Z face as the visible front.
	attachment.Position = Vector3.new(0, 0, -barrel.Size.Z * 0.5)
	attachment.Parent = barrel
	return attachment, true
end

local function makeImpactEndpoint()
	local part = Instance.new("Part")
	part.Name = "GunBeamEnd"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)

	local attachment = Instance.new("Attachment")
	attachment.Name = "GunBeamEndAttachment"
	attachment.Parent = part

	local light = Instance.new("PointLight")
	light.Name = "GunImpactLight"
	light.Brightness = 12
	light.Range = 24
	light.Shadows = false
	light.Enabled = false
	light.Parent = part

	return { part = part, attachment = attachment, light = light, token = 0 }
end

local function acquireImpactEndpoint(endPosition, color)
	local endpoint = table.remove(freeImpactEndpoints) or makeImpactEndpoint()
	endpoint.token += 1
	endpoint.part.Position = endPosition
	endpoint.light.Color = color
	endpoint.light.Enabled = true
	endpoint.part.Parent = workspace
	return endpoint, endpoint.token
end

local function releaseImpactEndpoint(endpoint, token)
	task.delay(GUN_IMPACT_LIGHT_LIFETIME, function()
		if endpoint.token ~= token then return end
		endpoint.light.Enabled = false
		endpoint.part.Parent = nil
		if #freeImpactEndpoints < MAX_FREE_IMPACT_ENDPOINTS then
			table.insert(freeImpactEndpoints, endpoint)
		else
			endpoint.part:Destroy()
		end
	end)
end

local function renderShot(tool, origin, endPosition, color, hitModel, generation)
	if not isActiveRound() or generation ~= currentGeneration() then return end
	local barrel = tool and (tool:FindFirstChild("Barrel", true) or tool:FindFirstChild("Handle", true))
	if not barrel or not barrel:IsA("BasePart") then return end
	playShotSound(tool)

	local endpoint, endpointToken = acquireImpactEndpoint(endPosition, color)

	local startAttachment, isTemporary = getVisibleBeamStart(tool, barrel)
	local muzzleLight = Instance.new("PointLight")
	muzzleLight.Name = "GunMuzzleLight"
	muzzleLight.Color = color
	muzzleLight.Brightness = 12
	muzzleLight.Range = 16
	muzzleLight.Shadows = false
	muzzleLight.Parent = startAttachment
	Debris:AddItem(muzzleLight, GUN_MUZZLE_LIGHT_LIFETIME)
	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endpoint.attachment
	beam.FaceCamera = true
	beam.Width0 = 0.28
	beam.Width1 = 0.12
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.08)
	beam.Parent = barrel
	Debris:AddItem(beam, GUN_BEAM_LIFETIME)
	if isTemporary then Debris:AddItem(startAttachment, GUN_BEAM_LIFETIME) end
	releaseImpactEndpoint(endpoint, endpointToken)

	if hitModel then
		MonsterHitFeedback.flash(hitModel, color, 0.25, false)
	end
end

fireGun = function(tool)
	if not isActiveRound() or not tool or tool.Parent ~= player.Character then return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	local ancestor = seat
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") and ancestor:GetAttribute("Turret") == true then return end
		ancestor = ancestor.Parent
	end
	local originOffset, direction, target = GunAim.getShotPayload(player, tool)
	local shootEvent = tool:FindFirstChild("ShootEvent")
	if originOffset and direction and shootEvent and shootEvent:IsA("RemoteEvent") then
		shootEvent:FireServer(originOffset, direction, target, currentGeneration())
	end
end

shotVisualEvent.OnClientEvent:Connect(renderShot)

RunService.RenderStepped:Connect(function(deltaTime)
	setEquippedTool(getEquippedGun())
	refreshLock(deltaTime)
	updateCrosshair()
end)

player.CharacterAdded:Connect(function()
	setEquippedTool(nil)
end)

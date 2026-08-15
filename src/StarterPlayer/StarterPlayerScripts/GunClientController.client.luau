-- GunClientController
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

local knownMonsters = {}
local flashStates = {}
local equippedTool
local activeHud
local lockedMonster
local lockTimer = 0
local activationConnection
local fireGun

local function getGunName(tool)
	if not tool or not tool:IsA("Tool") then return nil end
	local weaponName = tool:GetAttribute("WeaponName")
	if type(weaponName) ~= "string" then weaponName = tool.Name end
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
			if humanoid and humanoid.Health > 0 and displayPart then
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
	if not equippedTool or not GunAim.isCentered(player) then
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
	end
	UserInputService.MouseIconEnabled = false
end

local function updateCrosshair()
	if not activeHud then return end
	local crosshair = activeHud:FindFirstChild("Crosshair", true)
	if not crosshair or not crosshair:IsA("GuiObject") then return end

	if lockedMonster then
		local camera = workspace.CurrentCamera
		local displayPart = getDisplayPart(lockedMonster)
		if camera and displayPart then
			local point, visible = camera:WorldToViewportPoint(displayPart.Position)
			if visible then
				crosshair.Position = UDim2.fromOffset(point.X, point.Y)
				return
			end
		end
	end

	if GunAim.isCentered(player) then
		crosshair.Position = UDim2.fromScale(0.5, 0.5)
	else
		local mouse = player:GetMouse()
		crosshair.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	end
end


local function playShotSound(tool)
	local sound = tool:FindFirstChild("ShotSound", true)
	if not sound or not sound:IsA("Sound") then
		sound = SoundService:FindFirstChild("FallbackShotSound")
	end
	if sound and sound:IsA("Sound") then sound:Play() end
end

local function renderShot(tool, origin, endPosition, color, hitModel)
	local barrel = tool and (tool:FindFirstChild("Barrel", true) or tool:FindFirstChild("Handle", true))
	if not barrel or not barrel:IsA("BasePart") then return end
	playShotSound(tool)

	local muzzleLight = Instance.new("PointLight")
	muzzleLight.Name = "GunMuzzleLight"
	muzzleLight.Color = color
	muzzleLight.Brightness = 18
	muzzleLight.Range = 28
	muzzleLight.Shadows = true
	muzzleLight.Parent = barrel
	Debris:AddItem(muzzleLight, 0.12)

	local endPart = Instance.new("Part")
	endPart.Name = "GunBeamEnd"
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endPart.Position = endPosition
	endPart.Parent = workspace

	local hitLight = Instance.new("PointLight")
	hitLight.Color = color
	hitLight.Brightness = 12
	hitLight.Range = 18
	hitLight.Shadows = true
	hitLight.Parent = endPart

	local muzzle = tool:FindFirstChild("Muzzle", true)
	local startAttachment
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		startAttachment = muzzle
	else
		startAttachment = Instance.new("Attachment")
		startAttachment.Position = barrel.CFrame:PointToObjectSpace(origin)
		startAttachment.Parent = barrel
	end
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = endPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.28
	beam.Width1 = 0.12
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(color)
	beam.Transparency = NumberSequence.new(0.08)
	beam.Parent = barrel
	Debris:AddItem(beam, 0.18)
	if startAttachment ~= muzzle then Debris:AddItem(startAttachment, 0.18) end
	Debris:AddItem(endPart, 0.18)

	if hitModel then
		local state = flashStates[hitModel]
		if not state then
			state = { parts = {}, bodyColors = {}, token = 0 }
			flashStates[hitModel] = state
			for _, item in hitModel:GetDescendants() do
				if item:IsA("BasePart") then
					state.parts[item] = { color = item.Color, material = item.Material }
				elseif item:IsA("BodyColors") then
					state.bodyColors[item] = {
						head = item.HeadColor3, leftArm = item.LeftArmColor3, rightArm = item.RightArmColor3,
						leftLeg = item.LeftLegColor3, rightLeg = item.RightLegColor3, torso = item.TorsoColor3,
					}
				end
			end
		end
		for part in pairs(state.parts) do
			if part.Parent then part.Color = color; part.Material = Enum.Material.Neon end
		end
		for bodyColors in pairs(state.bodyColors) do
			if bodyColors.Parent then
				bodyColors.HeadColor3 = color; bodyColors.LeftArmColor3 = color; bodyColors.RightArmColor3 = color
				bodyColors.LeftLegColor3 = color; bodyColors.RightLegColor3 = color; bodyColors.TorsoColor3 = color
			end
		end
		state.token += 1
		local token = state.token
		task.delay(0.25, function()
			if flashStates[hitModel] ~= state or state.token ~= token then return end
			flashStates[hitModel] = nil
			for part, values in pairs(state.parts) do
				if part.Parent then part.Color = values.color; part.Material = values.material end
			end
			for bodyColors, values in pairs(state.bodyColors) do
				if bodyColors.Parent then
					bodyColors.HeadColor3 = values.head; bodyColors.LeftArmColor3 = values.leftArm; bodyColors.RightArmColor3 = values.rightArm
					bodyColors.LeftLegColor3 = values.leftLeg; bodyColors.RightLegColor3 = values.rightLeg; bodyColors.TorsoColor3 = values.torso
				end
			end
		end)
	end
end

fireGun = function(tool)
	if not tool or tool.Parent ~= player.Character then return end
	local originOffset, direction, target = GunAim.getShotPayload(player, tool)
	local shootEvent = tool:FindFirstChild("ShootEvent")
	if originOffset and direction and shootEvent and shootEvent:IsA("RemoteEvent") then
		shootEvent:FireServer(originOffset, direction, target)
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

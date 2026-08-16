-- CameraController StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local AimConfig = require(ReplicatedStorage:WaitForChild("GunAimConfig"))
local AIM_WEAPONS = {
	MonsterGun = true,
	MonsterGun2 = true,
	MonsterGun3 = true,
	MonsterBlaster = true,
}

local SHOULDER_DISTANCE = AimConfig.ShoulderDistance
local SHOULDER_OFFSET = AimConfig.ShoulderOffset
local firstPersonEnabled = false
local shoulderAiming = false
local savedMinZoom
local savedMaxZoom
local savedAutoRotate
local shoulderTransitionId = 0

local function preserveCursorAimPoint(cursorPoint, transitionId)
	-- Roblox's camera controller applies CameraOffset during its camera render
	-- step. Correct after that step so the new centred ray still passes through
	-- the same point that the free mouse cursor selected before RMB was held.
	local framesRemaining = 2
	RunService:UnbindFromRenderStep("PreserveShoulderAimPoint")
	RunService:BindToRenderStep("PreserveShoulderAimPoint", Enum.RenderPriority.Camera.Value + 1, function()
		if transitionId ~= shoulderTransitionId or not shoulderAiming or framesRemaining <= 0 then
			RunService:UnbindFromRenderStep("PreserveShoulderAimPoint")
			return
		end
		local camera = workspace.CurrentCamera
		if camera then
			local offset = cursorPoint - camera.CFrame.Position
			if offset.Magnitude > 0.01 then
				camera.CFrame = CFrame.lookAt(camera.CFrame.Position, cursorPoint)
				camera.Focus = CFrame.new(cursorPoint)
			end
		end
		framesRemaining -= 1
	end)
end

local function getHumanoid()
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function hasEquippedAimWeapon()
	local character = player.Character
	if not character then return false end
	for _, item in character:GetChildren() do
		if item:IsA("Tool") and AIM_WEAPONS[item.Name] then return true end
	end
	return false
end

local function stopShoulderAim()
	if not shoulderAiming then return end
	shoulderTransitionId += 1
	RunService:UnbindFromRenderStep("PreserveShoulderAimPoint")
	shoulderAiming = false
	player:SetAttribute("WeaponShoulderAim", false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if savedMinZoom then player.CameraMinZoomDistance = savedMinZoom end
	if savedMaxZoom then player.CameraMaxZoomDistance = savedMaxZoom end
	savedMinZoom = nil
	savedMaxZoom = nil
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
		if savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate; savedAutoRotate = nil end
	end
end

local function startShoulderAim()
	if firstPersonEnabled or shoulderAiming or not hasEquippedAimWeapon() then return end
	local humanoid = getHumanoid()
	if not humanoid then return end
	local camera = workspace.CurrentCamera
	local mouse = player:GetMouse()
	local cursorRay = camera and camera:ViewportPointToRay(mouse.X, mouse.Y)
	local cursorPoint = cursorRay and (cursorRay.Origin + cursorRay.Direction * AimConfig.Range)
	shoulderTransitionId += 1
	local transitionId = shoulderTransitionId
	shoulderAiming = true
	player:SetAttribute("WeaponShoulderAim", true)
	savedMinZoom = player.CameraMinZoomDistance
	savedMaxZoom = player.CameraMaxZoomDistance
	player.CameraMinZoomDistance = SHOULDER_DISTANCE
	player.CameraMaxZoomDistance = SHOULDER_DISTANCE
	humanoid.CameraOffset = SHOULDER_OFFSET
	savedAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	if cursorPoint then
		preserveCursorAimPoint(cursorPoint, transitionId)
	end
end

local function applyFirstPersonMode()
	stopShoulderAim()
	player.CameraMode = firstPersonEnabled and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	player:SetAttribute("WeaponFirstPerson", firstPersonEnabled)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Z then
		firstPersonEnabled = not firstPersonEnabled
		applyFirstPersonMode()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		startShoulderAim()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		stopShoulderAim()
	end
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		shoulderAiming = false
		savedAutoRotate = nil
		player:SetAttribute("WeaponShoulderAim", false)
		player:SetAttribute("WeaponFirstPerson", firstPersonEnabled)
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		player.CameraMode = firstPersonEnabled and Enum.CameraMode.LockFirstPerson or Enum.CameraMode.Classic
	end)
end)

applyFirstPersonMode()
player:SetAttribute("WeaponShoulderAim", false)
player:SetAttribute("WeaponFirstPerson", firstPersonEnabled)

RunService.RenderStepped:Connect(function()
	if shoulderAiming and not hasEquippedAimWeapon() then
		stopShoulderAim()
		return
	end
	if shoulderAiming then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local camera = workspace.CurrentCamera
		if root and root:IsA("BasePart") and camera then
			local flatDirection = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
			if flatDirection.Magnitude > 0.01 then
				local target = CFrame.lookAt(root.Position, root.Position + flatDirection.Unit)
				root.CFrame = root.CFrame:Lerp(target, math.clamp(AimConfig.AimTurnSpeed / 60, 0, 1))
			end
		end
	end
end)

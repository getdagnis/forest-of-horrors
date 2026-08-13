local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local AIM_WEAPONS = {
	MonsterGun = true,
	MonsterBlaster = true,
}

local SHOULDER_DISTANCE = 7
local SHOULDER_OFFSET = Vector3.new(1.5, 1, 0)
local firstPersonEnabled = false
local shoulderAiming = false
local savedMinZoom
local savedMaxZoom

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
	shoulderAiming = false
	player:SetAttribute("WeaponShoulderAim", false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if savedMinZoom then player.CameraMinZoomDistance = savedMinZoom end
	if savedMaxZoom then player.CameraMaxZoomDistance = savedMaxZoom end
	savedMinZoom = nil
	savedMaxZoom = nil
	local humanoid = getHumanoid()
	if humanoid then humanoid.CameraOffset = Vector3.zero end
end

local function startShoulderAim()
	if firstPersonEnabled or shoulderAiming or not hasEquippedAimWeapon() then return end
	local humanoid = getHumanoid()
	if not humanoid then return end
	shoulderAiming = true
	player:SetAttribute("WeaponShoulderAim", true)
	savedMinZoom = player.CameraMinZoomDistance
	savedMaxZoom = player.CameraMaxZoomDistance
	player.CameraMinZoomDistance = SHOULDER_DISTANCE
	player.CameraMaxZoomDistance = SHOULDER_DISTANCE
	humanoid.CameraOffset = SHOULDER_OFFSET
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
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
	end
end)

-- MonsterBlasterClient. Place inside the canonical MonsterBlaster Tool.
-- Tool.Activated handles mouse, touch, and gamepad with one immediate shot.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")
local Config = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))
local GunAim = require(ReplicatedStorage:WaitForChild("GunAim"))

local GUNSHOT_SOUND = "rbxassetid://131794614393147"
local COOLDOWN_SOUND = "rbxassetid://124307033081669"

-- Client presentation and feel tuning.
local SHOT_VOLUME_MIN = 0.5
local SHOT_VOLUME_POWER_GAIN = 2.5
local SHOT_PITCH_MIN_PERCENT = 95
local SHOT_PITCH_MAX_PERCENT = 105
local DEFAULT_SOUND_VOLUME = 1

local SCREEN_CENTER = 0.5
-- The legacy Crosshair in this marketplace HUD has an old absolute position.
-- Use one fixed, unobtrusive four-line reticle instead of a filled blue dot.
local CROSSHAIR_SIZE = 24
local CROSSHAIR_LINE_LENGTH = 6
local CROSSHAIR_LINE_THICKNESS = 2
local CROSSHAIR_GAP = 3
local CROSSHAIR_Z_INDEX = 10
local GROUND_SURFACE_NORMAL_MIN = 0.45
local GROUND_PREVIEW_THICKNESS = 0.08
local GROUND_PREVIEW_LIFT = 0.06
local GROUND_PREVIEW_TRANSPARENCY = 0.9

local MUZZLE_FLASH_BASE_SIZE = 0.5
local MUZZLE_FLASH_POWER_SIZE_GAIN = 2.5
local MUZZLE_FLASH_FORWARD_OFFSET = 0.6
local MUZZLE_FLASH_LIFETIME = 0.12
-- Restored from the previously successful Blaster implementation (09edc2c).
local MUZZLE_LIGHT_BRIGHTNESS_MIN = 18
local MUZZLE_LIGHT_BRIGHTNESS_GAIN = 18
local MUZZLE_LIGHT_RANGE_MIN = 28
local MUZZLE_LIGHT_RANGE_GAIN = 32
local IMPACT_LIGHT_LIFETIME = 0.24
local IMPACT_LIGHT_BRIGHTNESS_MIN = 12
local IMPACT_LIGHT_BRIGHTNESS_GAIN = 16
local IMPACT_LIGHT_RANGE_MIN = 16
local IMPACT_LIGHT_RANGE_GAIN = 24
local BEAM_END_SIZE = 0.2
local BEAM_WIDTH0_MIN = 0.35
local BEAM_WIDTH0_POWER_GAIN = 1.2
local BEAM_WIDTH1_MIN = 0.18
local BEAM_WIDTH1_POWER_GAIN = 0.65
local BEAM_TRANSPARENCY = 0.08
local BEAM_LIFETIME = 0.24
local coolingDown = false
local cooldownStartedAt = 0
local ambientLoop
local activeHud
local aimCrosshair
local groundPreview
local didWarnMissingHud = false
local didWarnMissingAmbient = false

local function isEquipped()
	return player.Character and tool.Parent == player.Character
end

local function getHandle()
	local handle = tool:FindFirstChild("Handle", true)
	return handle and handle:IsA("BasePart") and handle or nil
end

local function getBarrel()
	local barrel = tool:FindFirstChild("Barrel", true)
	return barrel and barrel:IsA("BasePart") and barrel or getHandle()
end

local function findSound(name)
	local sound = tool:FindFirstChild(name, true)
	return sound and sound:IsA("Sound") and sound or nil
end

local function getOrCreateSound(name, soundId, volume)
	local handle = getHandle()
	if not handle then return nil end
	local sound = handle:FindFirstChild(name)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = soundId
		sound.Volume = volume
		sound.Parent = handle
	end
	return sound
end

local function getPower()
	return Config.SHOT_POWER
end

local function playShotSound(power)
	local sound = getOrCreateSound("GunshotSound", GUNSHOT_SOUND, DEFAULT_SOUND_VOLUME)
	if not sound then return end
	-- A reused Sound keeps its first SoundId unless it is updated explicitly.
	sound.SoundId = GUNSHOT_SOUND
	sound.Volume = SHOT_VOLUME_MIN + (SHOT_VOLUME_POWER_GAIN * power)
	sound.PlaybackSpeed = math.random(SHOT_PITCH_MIN_PERCENT, SHOT_PITCH_MAX_PERCENT) / 100
	sound:Play()
end

local function playCooldownSound()
	local sound = getOrCreateSound("CooldownSound", COOLDOWN_SOUND, DEFAULT_SOUND_VOLUME)
	if sound then sound:Play() end
end

local function cloneWeaponHud()
	local sourceHud = tool:FindFirstChild("WeaponHud")
	if not sourceHud or not sourceHud:IsA("ScreenGui") then
		if not didWarnMissingHud then
			didWarnMissingHud = true
			warn("MonsterBlaster template needs a ScreenGui named WeaponHud:", tool:GetFullName())
		end
		return
	end
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("MonsterBlasterWeaponHud")
	if existing then existing:Destroy() end
	activeHud = sourceHud:Clone()
	activeHud.Name = "MonsterBlasterWeaponHud"
	activeHud.ResetOnSpawn = false
	activeHud.Parent = playerGui

	for _, item in activeHud:GetDescendants() do
		if item.Name == "Crosshair" and item:IsA("GuiObject") then
			item.Visible = false
		end
	end

	aimCrosshair = Instance.new("Frame")
	aimCrosshair.Name = "SimpleBlasterCrosshair"
	aimCrosshair.AnchorPoint = Vector2.new(SCREEN_CENTER, SCREEN_CENTER)
	aimCrosshair.Position = UDim2.fromScale(SCREEN_CENTER, SCREEN_CENTER)
	aimCrosshair.Size = UDim2.fromOffset(CROSSHAIR_SIZE, CROSSHAIR_SIZE)
	aimCrosshair.BackgroundTransparency = 1
	aimCrosshair.ZIndex = CROSSHAIR_Z_INDEX
	aimCrosshair.Parent = activeHud

	local function addLine(name, position, size)
		local line = Instance.new("Frame")
		line.Name = name
		line.Position = position
		line.Size = size
		line.BackgroundColor3 = Config.FLASH_COLOR
		line.BorderSizePixel = 0
		line.ZIndex = CROSSHAIR_Z_INDEX
		line.Parent = aimCrosshair
	end
	addLine("Top", UDim2.new(0.5, -CROSSHAIR_LINE_THICKNESS / 2, 0.5, -CROSSHAIR_GAP - CROSSHAIR_LINE_LENGTH), UDim2.fromOffset(CROSSHAIR_LINE_THICKNESS, CROSSHAIR_LINE_LENGTH))
	addLine("Bottom", UDim2.new(0.5, -CROSSHAIR_LINE_THICKNESS / 2, 0.5, CROSSHAIR_GAP), UDim2.fromOffset(CROSSHAIR_LINE_THICKNESS, CROSSHAIR_LINE_LENGTH))
	addLine("Left", UDim2.new(0.5, -CROSSHAIR_GAP - CROSSHAIR_LINE_LENGTH, 0.5, -CROSSHAIR_LINE_THICKNESS / 2), UDim2.fromOffset(CROSSHAIR_LINE_LENGTH, CROSSHAIR_LINE_THICKNESS))
	addLine("Right", UDim2.new(0.5, CROSSHAIR_GAP, 0.5, -CROSSHAIR_LINE_THICKNESS / 2), UDim2.fromOffset(CROSSHAIR_LINE_LENGTH, CROSSHAIR_LINE_THICKNESS))

end

local function destroyWeaponHud()
	if activeHud then activeHud:Destroy() end
	activeHud = nil
	aimCrosshair = nil
end

local function clearLegacyChargeHud()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local legacyHud = playerGui and playerGui:FindFirstChild("MonsterBlasterChargeHud")
	if legacyHud then legacyHud:Destroy() end
end

local function getAimPayload()
	return GunAim.getShotPayload(player, tool, nil, Config.RANGE)
end

local function raycastFromCamera(direction)
	local ray = GunAim.getRay(player)
	if not ray then return nil end
	return workspace:Raycast(ray.Origin, (direction or ray.Direction) * Config.RANGE,
		GunAim.makeRaycastParams(player.Character, tool))
end

local function getGroundPreview()
	if groundPreview then return groundPreview end
	groundPreview = Instance.new("Part")
	groundPreview.Name = "BlasterGroundPreview"
	groundPreview.Shape = Enum.PartType.Cylinder
	groundPreview.Anchored = true
	groundPreview.CanCollide = false
	groundPreview.CanQuery = false
	groundPreview.CanTouch = false
	groundPreview.CastShadow = false
	groundPreview.Material = Enum.Material.Neon
	groundPreview.Color = Config.FLASH_COLOR
	groundPreview.Transparency = GROUND_PREVIEW_TRANSPARENCY
	groundPreview.Parent = workspace
	return groundPreview
end

local function updateGroundPreview(power)
	if not isEquipped() or not GunAim.shouldShowAimHelpers(player) then
		if groundPreview then groundPreview.Transparency = 1 end
		return
	end
	-- Preview exactly the same camera ray that the focused crosshair represents.
	-- Do not derive this from the held barrel: that can be out of sync with the
	-- camera during shoulder aim and made the indicator stop at the wrong edge.
	local aimRay = GunAim.getRay(player)
	local result = aimRay and raycastFromCamera(aimRay.Direction)
	if not result or result.Normal.Y < GROUND_SURFACE_NORMAL_MIN then
		if groundPreview then groundPreview.Transparency = 1 end
		return
	end
	local radius = Config.shockwaveRadiusForPower(power)
	local preview = getGroundPreview()
	preview.Size = Vector3.new(GROUND_PREVIEW_THICKNESS, radius * 2, radius * 2)
	preview.CFrame = CFrame.new(result.Position + Vector3.new(0, GROUND_PREVIEW_LIFT, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	preview.Transparency = GROUND_PREVIEW_TRANSPARENCY
end

local function destroyGroundPreview()
	if groundPreview then groundPreview:Destroy() end
	groundPreview = nil
end

local function updateCrosshair()
	if not aimCrosshair then return end
	local point, space = GunAim.getScreenPoint(player)
	if not point then return end
	if space == "viewport" then
		aimCrosshair.Position = UDim2.fromScale(SCREEN_CENTER, SCREEN_CENTER)
	else
		aimCrosshair.Position = UDim2.fromOffset(point.X, point.Y)
	end
	for _, line in ipairs(aimCrosshair:GetChildren()) do
		if line:IsA("Frame") then line.BackgroundTransparency = coolingDown and 0.7 or 0 end
	end
end

local function muzzleFlash(power)
	local muzzle, muzzlePosition = GunAim.getMuzzle(tool)
	if not muzzlePosition then return end
	local flash = Instance.new("Part")
	flash.Name = "BlasterMuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	local flashSize = MUZZLE_FLASH_BASE_SIZE + (MUZZLE_FLASH_POWER_SIZE_GAIN * power)
	flash.Size = Vector3.new(flashSize, flashSize, flashSize)
	flash.Material = Enum.Material.Neon
	flash.Color = Config.FLASH_COLOR
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.CFrame = CFrame.new(muzzlePosition)
	flash.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Config.FLASH_COLOR
	light.Brightness = MUZZLE_LIGHT_BRIGHTNESS_MIN + MUZZLE_LIGHT_BRIGHTNESS_GAIN * power
	light.Range = MUZZLE_LIGHT_RANGE_MIN + MUZZLE_LIGHT_RANGE_GAIN * power
	light.Shadows = true
	light.Parent = flash
	Debris:AddItem(flash, MUZZLE_FLASH_LIFETIME)
end

local function makeImpactLight(position, power)
	local emitter = Instance.new("Part")
	emitter.Name = "BlasterImpactLight"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(0.1, 0.1, 0.1)
	emitter.Position = position
	emitter.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = Config.FLASH_COLOR
	light.Brightness = IMPACT_LIGHT_BRIGHTNESS_MIN + IMPACT_LIGHT_BRIGHTNESS_GAIN * power
	light.Range = IMPACT_LIGHT_RANGE_MIN + IMPACT_LIGHT_RANGE_GAIN * power
	light.Shadows = true
	light.Parent = emitter
	Debris:AddItem(emitter, IMPACT_LIGHT_LIFETIME)
end

local function showShotBeam(barrel, endPosition, power)
	local endPart = Instance.new("Part")
	endPart.Name = "BlasterBeamEnd"
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(BEAM_END_SIZE, BEAM_END_SIZE, BEAM_END_SIZE)
	endPart.Position = endPosition
	endPart.Parent = workspace
	local muzzle = tool:FindFirstChild("Muzzle", true)
	local startAttachment = muzzle and muzzle:IsA("Attachment") and muzzle or Instance.new("Attachment")
	if startAttachment.Parent == nil then startAttachment.Parent = barrel end
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = endPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Width0 = math.max(BEAM_WIDTH0_MIN, BEAM_WIDTH0_POWER_GAIN * power)
	beam.Width1 = math.max(BEAM_WIDTH1_MIN, BEAM_WIDTH1_POWER_GAIN * power)
	beam.LightInfluence = 0
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(BEAM_TRANSPARENCY)
	beam.Color = ColorSequence.new(Config.FLASH_COLOR)
	beam.Parent = barrel
	Debris:AddItem(beam, BEAM_LIFETIME)
	if startAttachment ~= muzzle then Debris:AddItem(startAttachment, BEAM_LIFETIME) end
	Debris:AddItem(endPart, BEAM_LIFETIME)
end

local function fireShot()
	if not isEquipped() or coolingDown then return end
	local originOffset, direction, target = getAimPayload()
	if not originOffset or not direction then return end
	local power = getPower()

	local barrel = getBarrel()
	if barrel then
		local aimRay = GunAim.getRay(player)
		if not aimRay then return end
		local result = raycastFromCamera(direction)
		local endPosition = result and result.Position or (aimRay.Origin + direction * Config.RANGE)
		playShotSound(power)
		muzzleFlash(power)
		showShotBeam(barrel, endPosition, power)
		-- Presentation only: restore the punchy local blue world-lighting without
		-- changing the validated server damage or shockwave mechanics.
		makeImpactLight(endPosition, power)
	end
	shootEvent:FireServer(originOffset, direction, target)
	coolingDown = true
	cooldownStartedAt = os.clock()
	task.delay(Config.COOLDOWN, function()
		if os.clock() - cooldownStartedAt >= Config.COOLDOWN then coolingDown = false end
	end)
end

local function resetState()
	coolingDown = false
	destroyGroundPreview()
end

tool.Activated:Connect(function()
	if coolingDown then playCooldownSound() return end
	fireShot()
end)

tool.Equipped:Connect(function()
	clearLegacyChargeHud()
	cloneWeaponHud()
	-- GunClientController owns this for the MonsterGun family.  The Blaster has
	-- its own HUD, so it must hide Roblox's native arrow itself; otherwise the
	-- arrow plus SimpleBlasterCrosshair looks like two competing aim pointers.
	UserInputService.MouseIconEnabled = false
	ambientLoop = findSound("AmbientLoop")
	if not ambientLoop then
		if not didWarnMissingAmbient then
			didWarnMissingAmbient = true
			warn("MonsterBlaster template needs a Sound named AmbientLoop:", tool:GetFullName())
		end
	else
		ambientLoop.Looped = true
		ambientLoop:Play()
	end
end)

tool.Unequipped:Connect(function()
	if ambientLoop then ambientLoop:Stop() end
	ambientLoop = nil
	resetState()
	destroyWeaponHud()
	clearLegacyChargeHud()
	UserInputService.MouseIconEnabled = true
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		if ambientLoop then ambientLoop:Stop() end
		ambientLoop = nil
		resetState()
		destroyWeaponHud()
		clearLegacyChargeHud()
		UserInputService.MouseIconEnabled = true
	end)
end)

RunService.RenderStepped:Connect(function()
	if not isEquipped() then return end
	updateCrosshair()
	updateGroundPreview(getPower())
end)

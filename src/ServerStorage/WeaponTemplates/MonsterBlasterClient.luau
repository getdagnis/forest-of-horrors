-- MonsterBlasterClient. Place inside the canonical MonsterBlaster Tool.
-- Tool.Activated/Deactivated deliberately handle mouse, touch, and gamepad.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")
local chargeEvent = tool:WaitForChild("ChargeEvent")
local Config = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))
local GunAim = require(ReplicatedStorage:WaitForChild("GunAim"))

local WEAK_GUNSHOT_SOUND = "rbxassetid://126040226110628"
local FULL_GUNSHOT_SOUND = "rbxassetid://131794614393147"
local FULL_SOUND_CHARGE_RATIO = 0.88
local CHARGE_SOUND = "rbxassetid://140102991925260"
local COOLDOWN_SOUND = "rbxassetid://124307033081669"

-- Client presentation and feel tuning.
local CHARGE_PULSE_INTERVAL = 0.12
local CHARGE_SOUND_VOLUME = 1.4
local SHOT_VOLUME_MIN = 0.5
local SHOT_VOLUME_POWER_GAIN = 2.5
local SHOT_PITCH_MIN_PERCENT = 95
local SHOT_PITCH_MAX_PERCENT = 105
local DEFAULT_SOUND_VOLUME = 1

local SCREEN_CENTER = 0.5
local HUD_WIDTH = 360
local HUD_HEIGHT = 8
local HUD_BOTTOM_OFFSET = 92
local HUD_LABEL_OFFSET = 102
local HUD_LABEL_WIDTH = 180
local HUD_LABEL_HEIGHT = 22
local HUD_LABEL_TEXT_SIZE = 15
local HUD_BACKGROUND_COLOR = Color3.fromRGB(17, 53, 59)
local HUD_READY_COLOR = Color3.fromRGB(89, 208, 255)
local HUD_LABEL_STROKE_TRANSPARENCY = 0.45

local AIM_CIRCLE_DIAMETER = 30
local AIM_CIRCLE_FILL_TRANSPARENCY = 0.25 -- centre remains barely visible
local AIM_CIRCLE_OUTLINE_TRANSPARENCY = 0.5 -- match monster contour brightness
local AIM_CIRCLE_OUTLINE_THICKNESS = 1.5
local AIM_CIRCLE_Z_INDEX = 10
local AIM_CIRCLE_CORNER_RADIUS = 1
local AIM_DIRECTION_EPSILON = 0.01
local GROUND_SURFACE_NORMAL_MIN = 0.45
local GROUND_PREVIEW_THICKNESS = 0.08
local GROUND_PREVIEW_LIFT = 0.06
local GROUND_PREVIEW_TRANSPARENCY = 0.9

local MUZZLE_FLASH_BASE_SIZE = 0.5
local MUZZLE_FLASH_POWER_SIZE_GAIN = 2.5
local MUZZLE_FLASH_FORWARD_OFFSET = 0.6
local MUZZLE_FLASH_LIFETIME = 0.12
local BEAM_END_SIZE = 0.2
local BEAM_WIDTH0_MIN = 0.35
local BEAM_WIDTH0_POWER_GAIN = 1.2
local BEAM_WIDTH1_MIN = 0.18
local BEAM_WIDTH1_POWER_GAIN = 0.65
local BEAM_TRANSPARENCY = 0.08
local BEAM_LIFETIME = 0.24
local FULL_POWER_VISUAL_THRESHOLD = 0.999

local charging = false
local coolingDown = false
local chargeStartedAt = 0
local cooldownStartedAt = 0
local chargePulseToken = 0
local chargeSound
local ambientLoop
local activeHud
local aimCircle
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

local function getChargeRatio()
	if chargeStartedAt <= 0 then return 0 end
	return math.clamp((os.clock() - chargeStartedAt) / Config.CHARGE_TIME, 0, 1)
end

local function getPower()
	return Config.powerForHoldRatio(getChargeRatio())
end

local function setHandleMaterial(material)
	local handle = getHandle()
	if handle then handle.Material = material end
end

local function startHandlePulse()
	chargePulseToken += 1
	local token = chargePulseToken
	task.spawn(function()
		while charging and token == chargePulseToken do
			setHandleMaterial(Enum.Material.Neon)
			task.wait(CHARGE_PULSE_INTERVAL)
			if not charging or token ~= chargePulseToken then break end
			setHandleMaterial(Enum.Material.Metal)
			task.wait(CHARGE_PULSE_INTERVAL)
		end
	end)
end

local function stopHandlePulse()
	chargePulseToken += 1
	setHandleMaterial(Enum.Material.Metal)
end

local function startChargeSound()
	chargeSound = getOrCreateSound("ChargeSound", CHARGE_SOUND, CHARGE_SOUND_VOLUME)
	if chargeSound then
		chargeSound.Looped = false
		chargeSound.TimePosition = 0
		chargeSound:Play()
	end
end

local function stopChargeSound()
	if chargeSound then chargeSound:Stop() end
end

local function playShotSound(power, chargeRatio)
	local soundId = chargeRatio >= FULL_SOUND_CHARGE_RATIO and FULL_GUNSHOT_SOUND or WEAK_GUNSHOT_SOUND
	local sound = getOrCreateSound("GunshotSound", soundId, DEFAULT_SOUND_VOLUME)
	if not sound then return end
	-- A reused Sound keeps its first SoundId unless it is updated explicitly.
	sound.SoundId = soundId
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

	-- The old HUD may contain a green multi-part crosshair. Hide it completely
	-- and use one self-contained circle inside the same cloned WeaponHud.
	for _, item in activeHud:GetDescendants() do
		if item.Name == "Crosshair" and item:IsA("GuiObject") then
			item.Visible = false
		end
	end

	aimCircle = Instance.new("Frame")
	aimCircle.Name = "BlasterAimCircle"
	aimCircle.AnchorPoint = Vector2.new(SCREEN_CENTER, SCREEN_CENTER)
	aimCircle.Position = UDim2.fromScale(SCREEN_CENTER, SCREEN_CENTER)
	aimCircle.Size = UDim2.fromOffset(AIM_CIRCLE_DIAMETER, AIM_CIRCLE_DIAMETER)
	aimCircle.BackgroundColor3 = Config.FLASH_COLOR
	aimCircle.BackgroundTransparency = AIM_CIRCLE_FILL_TRANSPARENCY
	aimCircle.BorderSizePixel = 0
	aimCircle.ZIndex = AIM_CIRCLE_Z_INDEX
	aimCircle.Parent = activeHud
	local corner = Instance.new("UICorner")
	corner.Name = "BlasterCircleCorner"
	corner.CornerRadius = UDim.new(AIM_CIRCLE_CORNER_RADIUS, 0)
	corner.Parent = aimCircle
	local stroke = Instance.new("UIStroke")
	stroke.Name = "BlasterCircleStroke"
	stroke.Color = Config.FLASH_COLOR
	stroke.Transparency = AIM_CIRCLE_OUTLINE_TRANSPARENCY
	stroke.Thickness = AIM_CIRCLE_OUTLINE_THICKNESS
	stroke.Parent = aimCircle
	UserInputService.MouseIconEnabled = false
end

local function destroyWeaponHud()
	if activeHud then activeHud:Destroy() end
	activeHud = nil
	aimCircle = nil
	UserInputService.MouseIconEnabled = true
end

local function getOrCreateChargeHud()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("MonsterBlasterChargeHud")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "MonsterBlasterChargeHud"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.Parent = playerGui
		local back = Instance.new("Frame")
		back.Name = "ChargeBack"
		back.AnchorPoint = Vector2.new(SCREEN_CENTER, 1)
		back.Position = UDim2.new(SCREEN_CENTER, 0, 1, -HUD_BOTTOM_OFFSET)
		back.Size = UDim2.fromOffset(HUD_WIDTH, HUD_HEIGHT)
		back.BackgroundColor3 = HUD_BACKGROUND_COLOR
		back.BorderSizePixel = 0
		back.Parent = gui
		local fill = Instance.new("Frame")
		fill.Name = "ChargeFill"
		fill.BorderSizePixel = 0
		fill.Parent = back
		local label = Instance.new("TextLabel")
		label.Name = "ChargePercent"
		label.AnchorPoint = Vector2.new(SCREEN_CENTER, 1)
		label.Position = UDim2.new(SCREEN_CENTER, 0, 1, -HUD_LABEL_OFFSET)
		label.Size = UDim2.fromOffset(HUD_LABEL_WIDTH, HUD_LABEL_HEIGHT)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = HUD_LABEL_TEXT_SIZE
		label.TextColor3 = Config.FLASH_COLOR
		label.TextStrokeTransparency = HUD_LABEL_STROKE_TRANSPARENCY
		label.Parent = gui
	end
	return gui
end

local chargeGui = getOrCreateChargeHud()
local chargeBack = chargeGui:WaitForChild("ChargeBack")
local chargeFill = chargeBack:WaitForChild("ChargeFill")
local chargePercent = chargeGui:WaitForChild("ChargePercent")
chargeGui.Enabled = false

local function setChargeHud(enabled, progress, text, fillColor)
	chargeGui.Enabled = enabled
	if not enabled then return end
	chargeFill.Size = UDim2.new(progress, 0, 1, 0)
	chargeFill.BackgroundColor3 = fillColor or HUD_READY_COLOR:Lerp(Config.FLASH_COLOR, progress)
	chargePercent.Text = text
end

local function getAimPayload()
	return GunAim.getShotPayload(player, tool, nil, Config.RANGE)
end

local function raycastFromCamera(direction)
	local ray = GunAim.getRay(player)
	if not ray then return nil end
	return workspace:Raycast(ray.Origin, direction * Config.RANGE, GunAim.makeRaycastParams(player.Character, tool))
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
	local _, direction = getAimPayload()
	local result = direction and raycastFromCamera(direction)
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
	if not aimCircle then return end
	if GunAim.isCentered(player) then
		aimCircle.Position = UDim2.fromScale(SCREEN_CENTER, SCREEN_CENTER)
	else
		local mouse = player:GetMouse()
		aimCircle.Position = UDim2.fromOffset(mouse.X, mouse.Y)
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
	Debris:AddItem(flash, MUZZLE_FLASH_LIFETIME)
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

local function releaseShot()
	if not charging or not isEquipped() then return end
	local chargeRatio = getChargeRatio()
	local power = Config.powerForHoldRatio(chargeRatio)
	local originOffset, direction, target = getAimPayload()
	charging = false
	chargeStartedAt = 0
	stopChargeSound()
	stopHandlePulse()
	if not originOffset or not direction then return end

	local barrel = getBarrel()
	if barrel then
		local aimRay = GunAim.getRay(player)
		if not aimRay then return end
		local result = raycastFromCamera(direction)
		local endPosition = result and result.Position or (aimRay.Origin + direction * Config.RANGE)
		if power >= FULL_POWER_VISUAL_THRESHOLD then endPosition = aimRay.Origin + direction * Config.RANGE end
		playShotSound(power, chargeRatio)
		muzzleFlash(power)
		showShotBeam(barrel, endPosition, power)
	end
	shootEvent:FireServer(originOffset, direction, target)
	coolingDown = true
	cooldownStartedAt = os.clock()
	setChargeHud(true, 0, "READYING", HUD_BACKGROUND_COLOR)
	task.delay(Config.COOLDOWN, function()
		if os.clock() - cooldownStartedAt >= Config.COOLDOWN then coolingDown = false end
	end)
end

local function resetState()
	charging = false
	coolingDown = false
	chargeStartedAt = 0
	stopChargeSound()
	stopHandlePulse()
	destroyGroundPreview()
	setChargeHud(false, 0, "")
end

tool.Activated:Connect(function()
	if not isEquipped() or charging then return end
	if coolingDown then playCooldownSound() return end
	charging = true
	chargeStartedAt = os.clock()
	chargeEvent:FireServer("Begin")
	startChargeSound()
	startHandlePulse()
end)

tool.Deactivated:Connect(releaseShot)

tool.Equipped:Connect(function()
	cloneWeaponHud()
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
	setChargeHud(true, 1, "Ready to charge")
end)

tool.Unequipped:Connect(function()
	if ambientLoop then ambientLoop:Stop() end
	ambientLoop = nil
	resetState()
	destroyWeaponHud()
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		if ambientLoop then ambientLoop:Stop() end
		ambientLoop = nil
		resetState()
		destroyWeaponHud()
	end)
end)

RunService.RenderStepped:Connect(function()
	if not isEquipped() then return end
	local power = charging and getPower() or 0
	if charging then
		setChargeHud(true, power, string.format("POWER %d%%", math.floor(power * 100 + 0.5)))
	elseif coolingDown then
		local progress = math.clamp((os.clock() - cooldownStartedAt) / Config.COOLDOWN, 0, 1)
		setChargeHud(true, progress, "READYING", HUD_BACKGROUND_COLOR:Lerp(HUD_READY_COLOR, progress))
	else
		setChargeHud(true, 1, "Ready to charge")
	end
	updateCrosshair()
	updateGroundPreview(power)
end)

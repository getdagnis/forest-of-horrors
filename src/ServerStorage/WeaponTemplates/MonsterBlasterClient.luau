-- MonsterBlasterClient. Place inside the canonical MonsterBlaster Tool.
-- Tool.Activated/Deactivated deliberately handle mouse, touch, and gamepad.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

-- The legacy Crosshair in this marketplace HUD has an old absolute position.
-- Use one fixed, unobtrusive four-line reticle instead of a filled blue dot.
local CROSSHAIR_SIZE = 24
local CROSSHAIR_LINE_LENGTH = 6
local CROSSHAIR_LINE_THICKNESS = 2
local CROSSHAIR_GAP = 3
local CROSSHAIR_Z_INDEX = 10
local GROUND_SURFACE_NORMAL_MIN = 0.45
local GROUND_PREVIEW_DELAY = 1
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
local FULL_POWER_VISUAL_THRESHOLD = 0.999
local BLASTER_ENERGY_COST = 5

local charging = false
local coolingDown = false
local chargeStartedAt = 0
local cooldownStartedAt = 0
local chargePulseToken = 0
local chargeSound
local ambientLoop
local activeHud
local aimCrosshair
local groundPreview
local groundAimStartedAt
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

local function hasLaserEnergy()
	return (tonumber(player:GetAttribute("LaserEnergy")) or 0) >= BLASTER_ENERGY_COST
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
		groundAimStartedAt = nil
		return
	end
	-- Preview exactly the same camera ray that the focused crosshair represents.
	-- Do not derive this from the held barrel: that can be out of sync with the
	-- camera during shoulder aim and made the indicator stop at the wrong edge.
	local aimRay = GunAim.getRay(player)
	local result = aimRay and raycastFromCamera(aimRay.Direction)
	if not result or result.Normal.Y < GROUND_SURFACE_NORMAL_MIN then
		if groundPreview then groundPreview.Transparency = 1 end
		groundAimStartedAt = nil
		return
	end
	groundAimStartedAt = groundAimStartedAt or os.clock()
	if os.clock() - groundAimStartedAt < GROUND_PREVIEW_DELAY then
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
	if GunAim.isCentered(player) then
		aimCrosshair.Position = UDim2.fromScale(SCREEN_CENTER, SCREEN_CENTER)
	else
		local mouse = player:GetMouse()
		aimCrosshair.Position = UDim2.fromOffset(mouse.X, mouse.Y)
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

local function releaseShot()
	if not charging or not isEquipped() then return end
	local chargeRatio = getChargeRatio()
	local power = Config.powerForHoldRatio(chargeRatio)
	charging = false
	chargeStartedAt = 0
	stopChargeSound()
	stopHandlePulse()
	-- Releasing a tap never spends energy or starts cooldown. A Blaster shot
	-- needs an intentional one-second hold.
	if chargeRatio * Config.CHARGE_TIME < Config.MIN_CHARGE_TIME then
		setChargeHud(true, 0, string.format("HOLD %.1fs", Config.MIN_CHARGE_TIME))
		return
	end
	local originOffset, direction, target = getAimPayload()
	if not originOffset or not direction then return end
	if not hasLaserEnergy() then
		setChargeHud(true, 0, "NO ENERGY", HUD_BACKGROUND_COLOR)
		playCooldownSound()
		return
	end

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
		-- Presentation only: restore the punchy local blue world-lighting without
		-- changing the validated server damage or shockwave mechanics.
		makeImpactLight(endPosition, power)
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
	if not hasLaserEnergy() then
		setChargeHud(true, 0, "NO ENERGY", HUD_BACKGROUND_COLOR)
		playCooldownSound()
		return
	end
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
		local chargeSeconds = getChargeRatio() * Config.CHARGE_TIME
		if chargeSeconds < Config.MIN_CHARGE_TIME then
			setChargeHud(true, chargeSeconds / Config.MIN_CHARGE_TIME,
				string.format("HOLD %.1fs", Config.MIN_CHARGE_TIME))
		else
			setChargeHud(true, power, string.format("POWER %d%%", math.floor(power * 100 + 0.5)))
		end
	elseif coolingDown then
		local progress = math.clamp((os.clock() - cooldownStartedAt) / Config.COOLDOWN, 0, 1)
		setChargeHud(true, progress, "READYING", HUD_BACKGROUND_COLOR:Lerp(HUD_READY_COLOR, progress))
	else
		setChargeHud(true, 1, "Ready to charge")
	end
	updateCrosshair()
	updateGroundPreview(power)
end)

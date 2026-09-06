-- MonsterBlasterClient. Place inside the canonical MonsterBlaster Tool.
-- Tool.Activated/Deactivated handles a short charge on mouse, touch, and gamepad.

local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")
local Config = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))
local GunAim = require(ReplicatedStorage:WaitForChild("GunAim"))
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local GUNSHOT_SOUND = "rbxassetid://131794614393147"
local CHARGE_SOUND = "rbxassetid://140102991925260"
local COOLDOWN_SOUND = "rbxassetid://124307033081669"
local DEPLETED_SOUND = "rbxassetid://137787508848769"
local PICKUP_SOUND = "rbxassetid://139730692334768"

-- Client presentation and feel tuning.
local SHOT_VOLUME_MIN = 0.5
local SHOT_VOLUME_POWER_GAIN = 2.5
local SHOT_PITCH_MIN_PERCENT = 95
local SHOT_PITCH_MAX_PERCENT = 105
local DEFAULT_SOUND_VOLUME = 1
local CHARGE_SOUND_VOLUME = 1.4
local COOLDOWN_SOUND_DURATION = 2.9

local SCREEN_CENTER = 0.5
-- The legacy Crosshair in this marketplace HUD has an old absolute position.
-- Use one fixed, unobtrusive four-line reticle instead of a filled blue dot.
local CROSSHAIR_SIZE = 56
local CROSSHAIR_LINE_LENGTH = 12
local CROSSHAIR_LINE_THICKNESS = 2
local CROSSHAIR_GAP = 3
local CROSSHAIR_Z_INDEX = 10
local CHARGE_HUD_Z_INDEX = 11
local CHARGE_HUD_WIDTH = 382
local CHARGE_HUD_HEIGHT = 58
local CHARGE_HUD_MARGIN = 24
local CHARGE_HUD_BOTTOM_MARGIN = 72
-- ScoreGui uses half-sized cards in its compact/mobile layout. Keep the two
-- weapon meters in that same visual scale rather than letting them dominate
-- a phone screen.
local MOBILE_HUD_SCALE = 0.5
local CHARGE_CELL_GAP = 4
local CHARGE_FULL_COLOR = Color3.fromRGB(94, 220, 255)
local CHARGE_EMPTY_COLOR = Color3.fromRGB(28, 63, 82)
-- The charge cells are deliberately never opaque: a full cell is a quiet
-- cyan glow, with partly charged and empty cells becoming progressively more
-- solid/dark so their state remains readable at a glance.
local CHARGE_FULL_TRANSPARENCY = 0.1
local CHARGE_HALF_TRANSPARENCY = 0.5
local CHARGE_EMPTY_TRANSPARENCY = 0.9
local DEPLETED_MESSAGE_DURATION = 1.6
local GROUND_SURFACE_NORMAL_MIN = 0.45
local GROUND_PREVIEW_THICKNESS = 0.2
local GROUND_PREVIEW_LIFT = 0.06
local GROUND_PREVIEW_TRANSPARENCY = 0.95

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
local BEAM_TRANSPARENCY = 0.1
local BEAM_LIFETIME = 0.36
local PIERCE_RAY_ADVANCE = 0.1
local charging = false
local coolingDown = false
local chargeStartedAt = 0
local cooldownStartedAt = 0
local chargeSound
local ambientLoop
local activeHud
local aimCrosshair
local chargeLevelTitle
local chargeCells = {}
local chargeHudScale
local chargeHudViewportConnection
local depletedMessage
local depletedMessageToken = 0
local depletedSoundToken = 0
local lastChargeUnits
local pickupSoundPlayed = false
local groundPreview
local didWarnMissingHud = false
local didWarnMissingAmbient = false
local fireShot

local function updateChargeHudScale()
	if not chargeHudScale then return end
	local viewport = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local compactHud = viewport.X < 1100 or viewport.Y < 650
	chargeHudScale.Scale = compactHud and MOBILE_HUD_SCALE or 1
end

local function bindChargeHudScale()
	if chargeHudViewportConnection then chargeHudViewportConnection:Disconnect() end
	chargeHudViewportConnection = nil
	local camera = Workspace.CurrentCamera
	if camera then
		chargeHudViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateChargeHudScale)
	end
	updateChargeHudScale()
end

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

local function getChargeProgress()
	if not charging or chargeStartedAt <= 0 then return 0 end
	return math.clamp((os.clock() - chargeStartedAt) / Config.CHARGE_TIME, 0, 1)
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
	if sound then
		-- Repeated clicks during cooldown must give repeated feedback, rather than
		-- silently ignoring input while an earlier click sound is still playing.
		sound:Stop()
		sound.TimePosition = 0
		sound:Play()
	end
end

local function playPickupSound()
	local sound = getOrCreateSound("PickupSound", PICKUP_SOUND, DEFAULT_SOUND_VOLUME)
	if not sound then return end
	sound.SoundId = PICKUP_SOUND
	sound:Stop()
	sound.TimePosition = 0
	sound:Play()
end

local function playDepletedFeedback()
	playCooldownSound()
	-- Preserve the familiar cooldown cue first; the distinct depleted sound
	-- follows only after it has finished.
	depletedSoundToken += 1
	local token = depletedSoundToken
	task.delay(COOLDOWN_SOUND_DURATION, function()
		if token ~= depletedSoundToken or not isEquipped() then return end
		local sound = getOrCreateSound("DepletedSound", DEPLETED_SOUND, DEFAULT_SOUND_VOLUME)
		if not sound then return end
		sound.SoundId = DEPLETED_SOUND
		sound:Stop()
		sound.TimePosition = 0
		sound:Play()
	end)
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

	-- The marketplace HUD contains the old green-digit readout.  This Tool now
	-- owns its small reticle and charge panel, so none of that legacy layout is
	-- allowed to compete with the replacement.
	for _, item in activeHud:GetDescendants() do
		if item:IsA("GuiObject") then item.Visible = false end
	end
	-- A ScreenGui can have a platform-specific origin even when it does not
	-- ignore the Roblox top-bar inset. Measure that real origin instead of
	-- guessing an inset, so cursor aim and the reticle use identical pixels.
	local hudOrigin = Instance.new("Frame")
	hudOrigin.Name = "BlasterHudOrigin"
	hudOrigin.Position = UDim2.fromOffset(0, 0)
	hudOrigin.Size = UDim2.fromOffset(0, 0)
	hudOrigin.BackgroundTransparency = 1
	hudOrigin.BorderSizePixel = 0
	hudOrigin.Active = false
	hudOrigin.Parent = activeHud

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

	local chargePanel = Instance.new("Frame")
	chargePanel.Name = "BlasterChargeLevel"
	chargePanel.AnchorPoint = Vector2.new(1, 1)
	chargePanel.Position = UDim2.new(1, -CHARGE_HUD_MARGIN, 1, -CHARGE_HUD_BOTTOM_MARGIN)
	chargePanel.Size = UDim2.fromOffset(CHARGE_HUD_WIDTH, CHARGE_HUD_HEIGHT)
	chargePanel.BackgroundTransparency = 1
	chargePanel.BorderSizePixel = 0
	chargePanel.ZIndex = CHARGE_HUD_Z_INDEX
	chargePanel.Parent = activeHud
	chargeHudScale = Instance.new("UIScale")
	chargeHudScale.Name = "ResponsiveScale"
	chargeHudScale.Parent = chargePanel
	bindChargeHudScale()

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 0)
	title.Size = UDim2.new(1, 0, 0, 24)
	title.Font = Enum.Font.GothamBold
	title.Text = "CHARGE LEVEL"
	title.TextColor3 = Color3.fromRGB(198, 239, 255)
	title.TextSize = 19
	title.TextXAlignment = Enum.TextXAlignment.Right
	title.ZIndex = CHARGE_HUD_Z_INDEX + 1
	title.Parent = chargePanel
	chargeLevelTitle = title

	local cells = Instance.new("Frame")
	cells.Name = "Cells"
	cells.BackgroundTransparency = 1
	cells.Position = UDim2.fromOffset(0, 30)
	cells.Size = UDim2.new(1, 0, 0, 24)
	cells.ZIndex = CHARGE_HUD_Z_INDEX + 1
	cells.Parent = chargePanel
	local cellWidth = (CHARGE_HUD_WIDTH - (CHARGE_CELL_GAP * 9)) / 10
	for index = 1, 10 do
		local cell = Instance.new("Frame")
		cell.Name = "Cell" .. index
		cell.Position = UDim2.fromOffset((index - 1) * (cellWidth + CHARGE_CELL_GAP), 0)
		cell.Size = UDim2.fromOffset(cellWidth, 24)
		cell.BackgroundColor3 = CHARGE_EMPTY_COLOR
		cell.BackgroundTransparency = CHARGE_EMPTY_TRANSPARENCY
		cell.BorderSizePixel = 0
		cell.ZIndex = CHARGE_HUD_Z_INDEX + 1
		cell.Parent = cells
		local outline = Instance.new("UIStroke")
		outline.Name = "EmptyOutline"
		outline.Color = CHARGE_FULL_COLOR
		outline.Thickness = 1
		outline.Transparency = 0.8
		outline.Enabled = false
		outline.Parent = cell
		chargeCells[index] = cell
	end

end

local function getChargeUnits()
	local value = tonumber(tool:GetAttribute(Config.CHARGE_ATTRIBUTE))
	return math.clamp(math.floor(value or Config.MAX_CHARGE_UNITS), 0, Config.MAX_CHARGE_UNITS)
end

local function updateChargeHud()
	local units = getChargeUnits()
	if chargeLevelTitle then
		chargeLevelTitle.Text = units == 0 and "BLASTER DEPLETED" or "BLASTER CHARGE LEVEL"
	end
	for index, cell in ipairs(chargeCells) do
		-- Drain from the left, leaving the rightmost segments bright beside the
		-- screen edge until the reserve is nearly empty.
		local unitsInCell = math.clamp(units - ((10 - index) * 2), 0, 2)
		cell.BackgroundColor3 = unitsInCell > 0 and CHARGE_FULL_COLOR or CHARGE_EMPTY_COLOR
		cell.BackgroundTransparency = unitsInCell == 2 and CHARGE_FULL_TRANSPARENCY
			or (unitsInCell == 1 and CHARGE_HALF_TRANSPARENCY or CHARGE_EMPTY_TRANSPARENCY)
		local outline = cell:FindFirstChild("EmptyOutline")
		if outline and outline:IsA("UIStroke") then outline.Enabled = unitsInCell < 2 end
	end
end

local function onChargeChanged()
	local units = getChargeUnits()
	if lastChargeUnits and units > lastChargeUnits and isEquipped() then
		playPickupSound()
		pickupSoundPlayed = true
	end
	lastChargeUnits = units
	updateChargeHud()
end

local function showDepletedMessage()
	if not activeHud then return end
	if not depletedMessage then
		depletedMessage = Instance.new("TextLabel")
		depletedMessage.Name = "BlasterDepletedMessage"
		depletedMessage.AnchorPoint = Vector2.new(0.5, 0.5)
		depletedMessage.Position = UDim2.fromScale(0.5, 0.39)
		depletedMessage.Size = UDim2.fromOffset(420, 42)
		depletedMessage.BackgroundTransparency = 1
		depletedMessage.Font = Enum.Font.GothamBold
		depletedMessage.Text = "VISIT A CHARGING STATION"
		depletedMessage.TextColor3 = CHARGE_FULL_COLOR
		depletedMessage.TextSize = 23
		depletedMessage.TextStrokeColor3 = Color3.fromRGB(0, 12, 22)
		depletedMessage.TextStrokeTransparency = 0.25
		depletedMessage.ZIndex = CHARGE_HUD_Z_INDEX + 2
		depletedMessage.Parent = activeHud
	end
	depletedMessageToken += 1
	local token = depletedMessageToken
	depletedMessage.Visible = true
	task.delay(DEPLETED_MESSAGE_DURATION, function()
		if depletedMessage and token == depletedMessageToken then depletedMessage.Visible = false end
	end)
end

local function destroyWeaponHud()
	if chargeHudViewportConnection then chargeHudViewportConnection:Disconnect() end
	chargeHudViewportConnection = nil
	chargeHudScale = nil
	if activeHud then activeHud:Destroy() end
	activeHud = nil
	aimCrosshair = nil
	chargeLevelTitle = nil
	table.clear(chargeCells)
	depletedMessage = nil
end

local function startCharge()
	if not isEquipped() or charging then return end
	if coolingDown then playCooldownSound() return end
	if getChargeUnits() < Config.DIRECT_SHOT_CHARGE_UNITS then
		playDepletedFeedback()
		showDepletedMessage()
		return
	end
	charging = true
	chargeStartedAt = os.clock()
	startChargeSound()
end

local function releaseCharge()
	if not charging then return end
	local heldSeconds = os.clock() - chargeStartedAt
	charging = false
	chargeStartedAt = 0
	stopChargeSound()
	if heldSeconds < Config.CHARGE_TIME then return end
	fireShot()
end

local function bindMobileChargeControl()
	if not UserInputService.TouchEnabled then return end
	ContextActionService:BindAction("MonsterBlasterCharge", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			startCharge()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			releaseCharge()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.UserInputType.Touch)
	ContextActionService:SetTitle("MonsterBlasterCharge", "HOLD CHARGE")
	ContextActionService:SetPosition("MonsterBlasterCharge", UDim2.new(1, -118, 1, -190))
end

local function unbindMobileChargeControl()
	ContextActionService:UnbindAction("MonsterBlasterCharge")
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

local function getMonsterModelFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then return current end
		current = current.Parent
	end
	return nil
end

local function predictedChargeCost(direction)
	local result = raycastFromCamera(direction)
	if result and result.Normal.Y >= GROUND_SURFACE_NORMAL_MIN and not getMonsterModelFromHit(result.Instance) then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if not (model and Players:GetPlayerFromCharacter(model)) then
			return Config.SHOCKWAVE_CHARGE_UNITS
		end
	end
	return Config.DIRECT_SHOT_CHARGE_UNITS
end

local function getPiercingBeamEnd(origin, direction)
	if not Config.PIERCES_MONSTERS then
		local result = raycastFromCamera(direction)
		return result and result.Position or (origin + direction * Config.RANGE)
	end

	local ignored = { player.Character, tool }
	local currentOrigin = origin
	local remainingRange = Config.RANGE
	while remainingRange > 0 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignored
		params.IgnoreWater = true
		local result = workspace:Raycast(currentOrigin, direction * remainingRange, params)
		if not result then return currentOrigin + direction * remainingRange end

		local monster = getMonsterModelFromHit(result.Instance)
		if not monster then return result.Position end
		table.insert(ignored, monster)
		local travelled = (result.Position - currentOrigin).Magnitude
		remainingRange -= travelled + PIERCE_RAY_ADVANCE
		currentOrigin = result.Position + direction * PIERCE_RAY_ADVANCE
	end
	return currentOrigin
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

local function updateGroundPreview(chargeProgress)
	if not charging or not isEquipped() or not GunAim.shouldShowAimHelpers(player) then
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
	local fullRadius = Config.shockwaveRadiusForPower(getPower())
	local radius = math.max(0.5, fullRadius * chargeProgress)
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
		local hudOrigin = activeHud and activeHud:FindFirstChild("BlasterHudOrigin")
		local offset = hudOrigin and hudOrigin.AbsolutePosition or Vector2.zero
		aimCrosshair.Position = UDim2.fromOffset(point.X - offset.X, point.Y - offset.Y)
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

fireShot = function()
	if not isEquipped() then return end
	if coolingDown then
		playCooldownSound()
		return
	end
	local originOffset, direction, target = getAimPayload()
	if not originOffset or not direction then return end
	if getChargeUnits() < predictedChargeCost(direction) then
		playDepletedFeedback()
		showDepletedMessage()
		return
	end
	local power = getPower()

	local barrel = getBarrel()
	if barrel then
		local aimRay = GunAim.getRay(player)
		if not aimRay then return end
		local endPosition = getPiercingBeamEnd(aimRay.Origin, direction)
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
	charging = false
	coolingDown = false
	chargeStartedAt = 0
	stopChargeSound()
	destroyGroundPreview()
end

local function cleanupWeaponState()
	if ambientLoop then ambientLoop:Stop() end
	ambientLoop = nil
	resetState()
	unbindMobileChargeControl()
	depletedSoundToken += 1
	destroyWeaponHud()
	clearLegacyChargeHud()
	UserInputService.MouseIconEnabled = true
end

tool.Activated:Connect(function()
	startCharge()
end)

tool.Deactivated:Connect(function()
	releaseCharge()
end)

tool.Equipped:Connect(function()
	clearLegacyChargeHud()
	cloneWeaponHud()
	lastChargeUnits = getChargeUnits()
	updateChargeHud()
	bindMobileChargeControl()
	if not pickupSoundPlayed and tool:GetAttribute(Config.LOADOUT_CHARGE_ATTRIBUTE) ~= true then
		playPickupSound()
		pickupSoundPlayed = true
	end
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

tool:GetAttributeChangedSignal(Config.CHARGE_ATTRIBUTE):Connect(onChargeChanged)

tool.Unequipped:Connect(function()
	cleanupWeaponState()
end)

player.CharacterAdded:Connect(function()
	task.defer(function()
		cleanupWeaponState()
	end)
end)

-- Roblox can remove a Tool during respawn without firing Unequipped. The
-- ContextActionService button is client-global, so explicitly clean it when
-- this Tool leaves both the Character and Backpack.
tool.AncestryChanged:Connect(function(_, parent)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if parent ~= player.Character and parent ~= backpack then
		cleanupWeaponState()
	end
end)

tool.Destroying:Connect(cleanupWeaponState)

RunService.RenderStepped:Connect(function()
	if not isEquipped() then return end
	-- Other legacy UI can restore this property after Equipped fires. Keep the
	-- native pointer hidden so the Blaster has one unambiguous aim indicator.
	UserInputService.MouseIconEnabled = false
	updateCrosshair()
	updateGroundPreview(getChargeProgress())
end)

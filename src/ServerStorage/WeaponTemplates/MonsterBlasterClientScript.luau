--MonsterBlasterClientScript
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")

local RANGE = 350
local CHARGE_TIME = 5
local COOLDOWN = 2
local COLOR = Color3.fromRGB(62, 169, 255)
local GUNSHOT_SOUND = "rbxassetid://131794614393147"
local CHARGE_SOUND = "rbxassetid://140102991925260"
local COOLDOWN_SOUND = "rbxassetid://108221299985037"

local charging = false
local charged = false
local coolingDown = false
local chargeStartedAt = 0
local cooldownStartedAt = 0
local chargePulseToken = 0
local chargeSoundInstance
local faceToken = 0

local function isEquipped()
	local character = player.Character
	return character and tool.Parent == character
end

local function getHandle()
	local handle = tool:FindFirstChild("Handle")
	return handle and handle:IsA("BasePart") and handle or nil
end

local function getBarrel()
	local barrel = tool:FindFirstChild("Barrel")
	return barrel and barrel:IsA("BasePart") and barrel or getHandle()
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

local function playShotSound(chargeRatio)
	local sound = getOrCreateSound("GunshotSound", GUNSHOT_SOUND, 1)
	if not sound then return end
	sound.Volume = 0.5 + 2.5 * chargeRatio
	sound.PlaybackSpeed = math.random(95, 105) / 100
	sound:Play()
end

local function startChargeSound()
	chargeSoundInstance = getOrCreateSound("ChargeSound", CHARGE_SOUND, 1.4)
	if chargeSoundInstance then
		chargeSoundInstance.Looped = false
		chargeSoundInstance.TimePosition = 0
		chargeSoundInstance:Play()
	end
end

local function stopChargeSound()
	if chargeSoundInstance then chargeSoundInstance:Stop() end
end

local function playCooldownSound()
	local sound = getOrCreateSound("CooldownSound", COOLDOWN_SOUND, 1)
	if sound then sound:Play() end
end

local function setHandleMaterial(material)
	local handle = getHandle()
	if handle then handle.Material = material end
end

local function startHandlePulse()
	chargePulseToken += 1
	local token = chargePulseToken
	task.spawn(function()
		while charging and not charged and token == chargePulseToken do
			setHandleMaterial(Enum.Material.Neon)
			task.wait(0.12)
			setHandleMaterial(Enum.Material.Metal)
			task.wait(0.12)
		end
		if charging and charged and token == chargePulseToken then setHandleMaterial(Enum.Material.Neon) end
	end)
end

local function stopHandlePulse(material)
	chargePulseToken += 1
	setHandleMaterial(material or Enum.Material.Metal)
end

local function getChargeRatio()
	return chargeStartedAt > 0 and math.clamp((os.clock() - chargeStartedAt) / CHARGE_TIME, 0, 1) or 0
end

local playerGui = player:WaitForChild("PlayerGui")
local chargeGui = playerGui:FindFirstChild("MonsterBlasterChargeHud") or Instance.new("ScreenGui")
chargeGui.Name = "MonsterBlasterChargeHud"
chargeGui.ResetOnSpawn = false
chargeGui.IgnoreGuiInset = true
chargeGui.Enabled = false
chargeGui.Parent = playerGui

local chargeBack = chargeGui:FindFirstChild("ChargeBack") or Instance.new("Frame")
chargeBack.Name = "ChargeBack"
chargeBack.AnchorPoint = Vector2.new(0.5, 1)
chargeBack.Position = UDim2.new(0.5, 0, 1, -92)
chargeBack.Size = UDim2.fromOffset(360, 8)
chargeBack.BackgroundColor3 = Color3.fromRGB(17, 53, 59)
chargeBack.BorderSizePixel = 0
chargeBack.Parent = chargeGui

local chargeFill = chargeBack:FindFirstChild("ChargeFill") or Instance.new("Frame")
chargeFill.Name = "ChargeFill"
chargeFill.Size = UDim2.new(0, 0, 1, 0)
chargeFill.BorderSizePixel = 0
chargeFill.Parent = chargeBack

local function resetChargeState()
	charging = false
	charged = false
	coolingDown = false
	chargeStartedAt = 0
	cooldownStartedAt = 0
	stopHandlePulse(Enum.Material.Metal)
	stopChargeSound()
	chargeGui.Enabled = false
end

local function easeOutCubic(value)
	return 1 - ((1 - math.clamp(value, 0, 1)) ^ 3)
end

RunService.RenderStepped:Connect(function()
	if not chargeGui.Enabled then return end
	if not isEquipped() then
		resetChargeState()
		return
	end
	if charging then
		local progress = charged and 1 or easeOutCubic(getChargeRatio())
		chargeFill.Size = UDim2.new(progress, 0, 1, 0)
		chargeFill.BackgroundColor3 = Color3.fromRGB(65, 115, 128):Lerp(Color3.fromRGB(67, 207, 255), progress)
	elseif coolingDown then
		local progress = easeOutCubic((os.clock() - cooldownStartedAt) / COOLDOWN)
		chargeFill.Size = UDim2.new(progress, 0, 1, 0)
		chargeFill.BackgroundColor3 = Color3.fromRGB(17, 53, 59):Lerp(Color3.fromRGB(65, 115, 128), progress)
	else
		chargeFill.Size = UDim2.new(1, 0, 1, 0)
		chargeFill.BackgroundColor3 = Color3.fromRGB(65, 115, 128)
	end
end)

local function muzzleFlash(chargeRatio)
	local barrel = getBarrel()
	if not barrel then return end
	local flash = Instance.new("Part")
	flash.Name = "BlasterMuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5 + 2.5 * chargeRatio, 0.5 + 2.5 * chargeRatio, 0.5 + 2.5 * chargeRatio)
	flash.Material = Enum.Material.Neon
	flash.Color = COLOR
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.CFrame = barrel.CFrame * CFrame.new(0, 0, -barrel.Size.Z / 2 - 0.6)
	flash.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = COLOR
	light.Brightness = 18 + 18 * chargeRatio
	light.Range = 28 + 32 * chargeRatio
	light.Shadows = true
	light.Parent = flash
	Debris:AddItem(flash, 0.12)
end

local function raycast(origin, direction)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, tool }
	params.IgnoreWater = true
	return workspace:Raycast(origin, direction * RANGE, params)
end

local function faceShotDirection(direction)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if not humanoid or not root or humanoid.Health <= 0 or flatDirection.Magnitude < 0.01 then return end

	faceToken += 1
	local token = faceToken
	humanoid.AutoRotate = false
	local yaw = math.atan2(-flatDirection.X, -flatDirection.Z)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)

	task.delay(0.2, function()
		if faceToken == token and humanoid.Parent and humanoid.Health > 0 then
			humanoid.AutoRotate = true
		end
	end)
end

local function showShotBeam(barrel, hitPosition, chargeRatio)
	local endPart = Instance.new("Part")
	endPart.Name = "BlasterBeamEnd"
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(0.2, 0.2, 0.2)
	endPart.Position = hitPosition
	endPart.Parent = workspace

	local hitLight = Instance.new("PointLight")
	hitLight.Color = COLOR
	hitLight.Brightness = 12 + 16 * chargeRatio
	hitLight.Range = 16 + 24 * chargeRatio
	hitLight.Shadows = true
	hitLight.Parent = endPart

	local startAttachment = Instance.new("Attachment")
	startAttachment.Parent = barrel
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Width0 = math.max(0.35, 1.2 * chargeRatio)
	beam.Width1 = math.max(0.18, 0.65 * chargeRatio)
	beam.LightInfluence = 0
	beam.LightEmission = 1
	beam.Transparency = NumberSequence.new(0.08)
	beam.Color = ColorSequence.new(COLOR)
	beam.Parent = barrel

	Debris:AddItem(beam, 0.24)
	Debris:AddItem(startAttachment, 0.24)
	Debris:AddItem(endPart, 0.24)
end

local function fire(mouse, chargeRatio)
	if not isEquipped() or coolingDown then return end
	local barrel = getBarrel()
	if not barrel then return end
	local direction = mouse.Hit.Position - barrel.Position
	if direction.Magnitude < 0.01 then return end
	local unitDirection = direction.Unit
	local result = raycast(barrel.Position, unitDirection)
	local hitPosition = result and result.Position or (barrel.Position + unitDirection * RANGE)

	playShotSound(chargeRatio)
	muzzleFlash(chargeRatio)
	showShotBeam(barrel, hitPosition, chargeRatio)
	faceShotDirection(unitDirection)
	shootEvent:FireServer(result and result.Instance or nil, unitDirection, chargeRatio)

	coolingDown = true
	cooldownStartedAt = os.clock()
	task.delay(COOLDOWN, function() coolingDown = false end)
end

local mouse = player:GetMouse()
mouse.Button1Down:Connect(function()
	if not isEquipped() or charging then return end
	if coolingDown then playCooldownSound() return end
	charging = true
	charged = false
	chargeStartedAt = os.clock()
	startChargeSound()
	startHandlePulse()
	task.delay(CHARGE_TIME, function()
		if charging and isEquipped() then
			charged = true
			stopHandlePulse(Enum.Material.Neon)
		end
	end)
end)

mouse.Button1Up:Connect(function()
	if not charging then return end
	local chargeRatio = getChargeRatio()
	charging = false
	charged = false
	stopChargeSound()
	stopHandlePulse(Enum.Material.Metal)
	fire(mouse, chargeRatio)
end)

tool.Equipped:Connect(function()
	chargeGui.Enabled = true
end)
tool.Unequipped:Connect(function()
	resetChargeState()
end)

player.CharacterAdded:Connect(function()
	task.defer(resetChargeState)
end)

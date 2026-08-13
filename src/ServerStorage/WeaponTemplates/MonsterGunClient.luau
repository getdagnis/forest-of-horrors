local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")

local RANGE = 300
local COLOR = Color3.fromRGB(211, 80, 135)
local GUNSHOT_SOUND = "rbxassetid://138074730724614"

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

local function playSound()
	local handle = getHandle()
	if not handle then return end
	local sound = handle:FindFirstChild("GunshotSound")
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "GunshotSound"
		sound.SoundId = GUNSHOT_SOUND
		sound.Volume = 0.6
		sound.Parent = handle
	end
	sound:Play()
end

local function muzzleFlash()
	local barrel = getBarrel()
	if not barrel then return end
	local flash = Instance.new("Part")
	flash.Name = "MonsterGunMuzzleFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(0.5, 0.5, 0.5)
	flash.Material = Enum.Material.Neon
	flash.Color = COLOR
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.CastShadow = false
	flash.CFrame = barrel.CFrame * CFrame.new(0, 0, -barrel.Size.Z / 2 - 0.4)
	flash.Parent = workspace
	Debris:AddItem(flash, 0.06)
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

local function showShotBeam(barrel, hitPosition)
	local endPart = Instance.new("Part")
	endPart.Name = "MonsterGunBeamEnd"
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.CanQuery = false
	endPart.CanTouch = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endPart.Position = hitPosition
	endPart.Parent = workspace

	local startAttachment = Instance.new("Attachment")
	startAttachment.Parent = barrel
	local endAttachment = Instance.new("Attachment")
	endAttachment.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = startAttachment
	beam.Attachment1 = endAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.18
	beam.Width1 = 0.08
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(COLOR)
	beam.Transparency = NumberSequence.new(0.18)
	beam.Parent = barrel

	Debris:AddItem(beam, 0.12)
	Debris:AddItem(startAttachment, 0.12)
	Debris:AddItem(endPart, 0.12)
end

local mouse = player:GetMouse()

mouse.Button1Down:Connect(function()
	if not isEquipped() then return end
	local barrel = getBarrel()
	if not barrel then return end

	local target = mouse.Hit.Position
	local direction = target - barrel.Position
	if direction.Magnitude < 0.01 then return end
	local unitDirection = direction.Unit
	local result = raycast(barrel.Position, unitDirection)
	local hitPosition = result and result.Position or (barrel.Position + unitDirection * RANGE)

	playSound()
	muzzleFlash()
	showShotBeam(barrel, hitPosition)
	faceShotDirection(unitDirection)
	shootEvent:FireServer(result and result.Instance or nil, unitDirection)
end)
-- ReplicatedStorage.GunAim
-- One client-side aim source for weapon HUDs, contours, and shot remotes.
-- The server still validates every payload before applying combat effects.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("GunAimConfig"))
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local GunAim = {}
local lockedTarget

local function getMonsterModelFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			local humanoid = MonsterManager.getMonsterHumanoid(current)
			return humanoid and humanoid.Health > 0 and current or nil
		end
		current = current.Parent
	end
	return nil
end

function GunAim.isCentered(player)
	return (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
		or GunAim.isFocused(player)
end

-- Desktop helpers are intentional aim feedback, not permanent free-mouse UI.
-- Touch has no RMB, so it keeps the centred helper path until mobile gets its
-- own dedicated combat pass.
function GunAim.isFocused(player)
	return player:GetAttribute("WeaponShoulderAim") == true
		or player:GetAttribute("WeaponFirstPerson") == true
end

function GunAim.shouldShowAimHelpers(player)
	return (UserInputService.TouchEnabled and not UserInputService.MouseEnabled)
		or GunAim.isFocused(player)
end

function GunAim.setLockedTarget(target)
	lockedTarget = target
end

function GunAim.getRay(player, lockedTarget)
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local origin = camera.CFrame.Position
	local aimTarget = lockedTarget or GunAim.getLockedTarget()
	if aimTarget and aimTarget.Parent then
		local targetPart = aimTarget:FindFirstChild("HumanoidRootPart", true)
			or aimTarget:FindFirstChild("Head", true)
			or aimTarget.PrimaryPart
		if targetPart and targetPart:IsA("BasePart") then
			local offset = targetPart.Position - origin
			if offset.Magnitude > 0.01 then return Ray.new(origin, offset.Unit) end
		end
	end
	if GunAim.isCentered(player) then
		local viewport = camera.ViewportSize
		return camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
	end
	local mouse = player:GetMouse()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

function GunAim.getLockedTarget()
	return lockedTarget
end

function GunAim.makeRaycastParams(character, tool)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true
	return params
end

function GunAim.getDirectTarget(player, tool, lockedTarget, range)
	local ray = GunAim.getRay(player, lockedTarget)
	if not ray then return nil, nil, nil end
	local result = workspace:Raycast(ray.Origin, ray.Direction * (range or Config.Range),
		GunAim.makeRaycastParams(player.Character, tool))
	return result and getMonsterModelFromHit(result.Instance) or nil, ray, result
end

function GunAim.getShotPayload(player, tool, lockedTarget, range)
	local ray = GunAim.getRay(player, lockedTarget)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not ray or not root or ray.Direction.Magnitude < 0.01 then return nil end
	local target = GunAim.getDirectTarget(player, tool, lockedTarget, range)
	return ray.Origin - root.Position, ray.Direction.Unit, target
end

function GunAim.getMuzzle(tool)
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		return muzzle, muzzle.WorldPosition
	end
	local barrel = tool:FindFirstChild("Barrel", true) or tool:FindFirstChild("Handle", true)
	if barrel and barrel:IsA("BasePart") then return nil, barrel.Position end
	return nil, nil
end

return GunAim

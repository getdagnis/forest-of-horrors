-- MonsterGunDamageSystem
-- The sole server-side combat owner for the MonsterGun family.  Clients submit
-- camera aim data; the server owns validation, combat raycasts, damage, scoring,
-- and the visual broadcast that every client renders.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local AimConfig = require(ReplicatedStorage:WaitForChild("GunAimConfig"))

local RANGE = AimConfig.Range
local DEFAULT_BURST_DELAY = 0.08
local MIN_FIRE_INTERVAL = 0.08
local HIT_COLOR = Color3.fromRGB(212, 159, 162)

local GUNS = {
	MonsterGun = { damage = 40, color = HIT_COLOR, shots = 1, interval = 0.10 },
	MonsterGun2 = { damage = 60, color = Color3.fromRGB(255, 125, 200), shots = 1, interval = 0.10 },
	MonsterGun3 = { damage = 80, color = Color3.fromRGB(255, 64, 90), shots = 2, interval = 0.18 },
}

local function getOrCreateRemoteEvent(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local shotVisualEvent = getOrCreateRemoteEvent("GunShotVisual")
local damageLabelEvent = getOrCreateRemoteEvent("MonsterDamageLabel")
local contourTargetEvent = getOrCreateRemoteEvent("WeaponContourTarget")

local boundEvents = {}
local lastShotAt = {}
local contourTargets = {}
local warnedMissingMuzzle = {}

local function getGunConfig(tool)
	if not tool:IsA("Tool") then return nil end
	local weaponName = tool:GetAttribute("WeaponName")
	if type(weaponName) ~= "string" then
		weaponName = tool.Name
	end

	local defaults = GUNS[weaponName]
	if not defaults then return nil end

	return {
		weaponName = weaponName,
		damage = math.max(1, tonumber(tool:GetAttribute("Damage")) or defaults.damage),
		color = typeof(tool:GetAttribute("ShotColor")) == "Color3" and tool:GetAttribute("ShotColor") or defaults.color,
		shots = defaults.shots,
		interval = math.max(MIN_FIRE_INTERVAL, tonumber(tool:GetAttribute("FireInterval")) or defaults.interval),
		burstDelay = math.max(0, tonumber(tool:GetAttribute("BurstDelay")) or DEFAULT_BURST_DELAY),
	}
end

local function getMonsterModelFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function makeRaycastParams(character, tool)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true
	return params
end

local function getMuzzlePosition(tool)
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		return muzzle.WorldPosition
	end
	if not warnedMissingMuzzle[tool] then
		warnedMissingMuzzle[tool] = true
		warn("Gun tool has no Muzzle Attachment; using Barrel temporarily:", tool:GetFullName())
	end
	local barrel = tool:FindFirstChild("Barrel", true) or tool:FindFirstChild("Handle", true)
	return barrel and barrel:IsA("BasePart") and barrel.Position or nil
end

local function consumeLaserEnergy(player, amount)
	local energy = math.clamp(tonumber(player:GetAttribute("LaserEnergy")) or 600, 0, 600)
	if energy < amount then return false end
	player:SetAttribute("LaserEnergy", energy - amount)
	return true
end

local function validateCameraOrigin(player, originOffset)
	if typeof(originOffset) ~= "Vector3" or originOffset.Magnitude > AimConfig.MaxCameraOriginOffset then return nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not root or not root:IsA("BasePart") then return nil end
	local origin = root.Position + originOffset
	if head and head:IsA("BasePart") and (origin - head.Position).Magnitude > AimConfig.MaxCameraHeadOffset then return nil end
	return origin
end

local function isDirectTarget(model, cameraOrigin, direction, character, tool)
	if not model or not model:IsA("Model") or not MonsterManager.getConfig(model) then return false end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return false end
	local result = workspace:Raycast(cameraOrigin, direction * RANGE, makeRaycastParams(character, tool))
	return result and getMonsterModelFromHit(result.Instance) == model
end

local function updateContourGrace(player, tool, submittedTarget, cameraOrigin, direction)
	if isDirectTarget(submittedTarget, cameraOrigin, direction, player.Character, tool) then
		contourTargets[player] = { tool = tool, model = submittedTarget, expiresAt = os.clock() + AimConfig.ContourGraceSeconds }
	end
end

local function isVisibleMonster(model, cameraOrigin, character, tool)
	if not model or not MonsterManager.getConfig(model) then return false end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return false end
	local targetPart = model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not targetPart or not targetPart:IsA("BasePart") then return false end
	local offset = targetPart.Position - cameraOrigin
	if offset.Magnitude < 0.01 then return false end
	local result = workspace:Raycast(cameraOrigin, offset, makeRaycastParams(character, tool))
	return result and getMonsterModelFromHit(result.Instance) == model
end

local function getGraceTarget(player, tool, cameraOrigin, direction)
	local cached = contourTargets[player]
	if not cached or cached.tool ~= tool or cached.expiresAt < os.clock() then return nil end
	-- The server previously re-tested the *new* firing ray here, which cancelled
	-- the 0.20s grace the moment a laggy camera moved a pixel. Recheck only real
	-- line-of-sight to the cached contour target, so walls still win.
	return isVisibleMonster(cached.model, cameraOrigin, player.Character, tool) and cached.model or nil
end

contourTargetEvent.OnServerEvent:Connect(function(player, tool, originOffset, direction, target)
	if not getGunConfig(tool) or not isEquippedBy(player, tool) then return end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then return end
	local cameraOrigin = validateCameraOrigin(player, originOffset)
	if not cameraOrigin then return end
	updateContourGrace(player, tool, target, cameraOrigin, direction.Unit)
end)

local function getServerShot(tool, player, cameraOrigin, direction)
	local params = makeRaycastParams(player.Character, tool)
	local result = workspace:Spherecast(cameraOrigin, AimConfig.AimAssistRadius, direction * RANGE, params)
	local endPosition = result and result.Position or (cameraOrigin + direction * RANGE)
	local muzzlePosition = getMuzzlePosition(tool)
	if muzzlePosition then
		local clearance = endPosition - muzzlePosition
		if clearance.Magnitude > 0.01 then
			local shortDistance = math.min(AimConfig.MuzzleClearanceDistance, clearance.Magnitude)
			local blocked = workspace:Raycast(muzzlePosition, clearance.Unit * shortDistance, params)
			if blocked then return muzzlePosition, blocked, blocked.Position, true end
		end
	end
	return muzzlePosition or cameraOrigin, result, endPosition, false
end

local function makeMonsterPink(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Color = HIT_COLOR
			item.Material = Enum.Material.Neon
		end
	end
end

local function disintegrateMonster(model, blastOrigin)
	makeMonsterPink(model)
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") or item:IsA("Weld") or item:IsA("WeldConstraint") then
			item:Destroy()
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.CanTouch = false
			part.Massless = false
			local direction = part.Position - blastOrigin
			if direction.Magnitude < 0.1 then
				direction = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
			end
			part.AssemblyLinearVelocity = direction.Unit * math.random(30, 55) + Vector3.new(0, math.random(15, 35), 0)
		end
	end
end

local function isEquippedBy(player, tool)
	return tool.Parent == player.Character
end

local function resolveShot(player, tool, config, cameraOrigin, direction, graceTarget)
	if not isEquippedBy(player, tool) then return end
	local origin, result, endPosition, muzzleBlocked = getServerShot(tool, player, cameraOrigin, direction)
	if not origin then return end

	local monsterModel = result and getMonsterModelFromHit(result.Instance) or nil
	if not monsterModel and not muzzleBlocked then monsterModel = graceTarget end
	-- Every accepted ray is sent to every client, including misses.  The client
	-- owns only short-lived visuals; no client result can affect combat.
	shotVisualEvent:FireAllClients(tool, origin, endPosition, config.color, monsterModel)
	if not monsterModel then return end

	local humanoid = MonsterManager.getMonsterHumanoid(monsterModel)
	if not humanoid or humanoid.Health <= 0 then return end

	local damage = MonsterManager.getPlayerWeaponDamage(monsterModel, config.damage)
	if damage <= 0 then return end
	local willDie = humanoid.Health <= damage
	MonsterManager.recordPlayerDamage(humanoid, player, damage, config.color)
	if willDie then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		if monsterModel.Name == "BombMonster" then
			MonsterManager.markPermanentKill(humanoid, "MonsterGun")
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		disintegrateMonster(monsterModel, root and root.Position or monsterModel:GetPivot().Position)
	end

	humanoid:TakeDamage(damage)
	if humanoid.Health > 0 then
		damageLabelEvent:FireClient(player, monsterModel, humanoid.Health, humanoid.MaxHealth)
	end
end

local function canFire(tool, interval)
	local now = os.clock()
	local previous = lastShotAt[tool]
	if previous and now - previous < interval then return false end
	lastShotAt[tool] = now
	return true
end

local function bindTool(tool)
	local config = getGunConfig(tool)
	if not config then return end
	local shootEvent = tool:FindFirstChild("ShootEvent")
	if not shootEvent then
		shootEvent = Instance.new("RemoteEvent")
		shootEvent.Name = "ShootEvent"
		shootEvent.Parent = tool
	end
	if not shootEvent:IsA("RemoteEvent") or boundEvents[shootEvent] then return end
	boundEvents[shootEvent] = true

	shootEvent.OnServerEvent:Connect(function(player, originOffset, shotDirection, outlinedTarget)
		local currentConfig = getGunConfig(tool)
		if not currentConfig or not isEquippedBy(player, tool) then return end
		if typeof(shotDirection) ~= "Vector3" or shotDirection.Magnitude < 0.01 then return end
		if not canFire(tool, currentConfig.interval) then return end

		-- The client and server both use the validated camera ray.  The muzzle is
		-- deliberately a visual/clearance origin, not a second aim controller.
		local direction = shotDirection.Unit
		local cameraOrigin = validateCameraOrigin(player, originOffset)
		if not cameraOrigin then return end
		updateContourGrace(player, tool, outlinedTarget, cameraOrigin, direction)
		local graceTarget = getGraceTarget(player, tool, cameraOrigin, direction)
		if not consumeLaserEnergy(player, 1) then return end
		resolveShot(player, tool, currentConfig, cameraOrigin, direction, graceTarget)
		if currentConfig.shots == 2 then
			task.delay(currentConfig.burstDelay, function()
				if not isEquippedBy(player, tool) then return end
				if not consumeLaserEnergy(player, 1) then return end
				resolveShot(player, tool, currentConfig, cameraOrigin, direction, graceTarget)
			end)
		end
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if not parent then lastShotAt[tool] = nil; warnedMissingMuzzle[tool] = nil end
	end)
end

for _, instance in game:GetDescendants() do
	bindTool(instance)
end
game.DescendantAdded:Connect(bindTool)

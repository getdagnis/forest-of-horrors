-- MonsterBlasterServer >> ServerStorage.WeaponTemplates.MonsterBlaster

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")

local function isPlayerInActiveRound(player)
	return player
		and workspace:GetAttribute("RoundState") == "Active"
		and player:GetAttribute("EscapedNightmare") ~= true
end

local function isCurrentGeneration(generation)
	return typeof(generation) == "number" and generation == workspace:GetAttribute("RoundGeneration")
end

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local MonsterHitFeedback = require(ReplicatedStorage:WaitForChild("MonsterHitFeedback"))
local Config = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))
local AimConfig = require(ReplicatedStorage:WaitForChild("GunAimConfig"))

local damageLabelEvent = ReplicatedStorage:FindFirstChild("MonsterDamageLabel")
if not damageLabelEvent then
	damageLabelEvent = Instance.new("RemoteEvent")
	damageLabelEvent.Name = "MonsterDamageLabel"
	damageLabelEvent.Parent = ReplicatedStorage
end

local contourTargetEvent = ReplicatedStorage:FindFirstChild("WeaponContourTarget")
if not contourTargetEvent then
	contourTargetEvent = Instance.new("RemoteEvent")
	contourTargetEvent.Name = "WeaponContourTarget"
	contourTargetEvent.Parent = ReplicatedStorage
end

-- Server gameplay, validation, and replicated-effect tuning.
local PIERCE_RAY_ADVANCE = 0.1
local GROUND_SURFACE_NORMAL_MIN = 0.45
local DIRECTION_EPSILON = 0.01
local MONSTER_FLASH_DURATION = 0.25
local KILL_ILLUMINATION_DURATION = 0.3
local DISINTEGRATION_DIRECTION_EPSILON = 0.1
local DISINTEGRATION_SPEED_MIN = 45
local DISINTEGRATION_SPEED_MAX = 80
local DISINTEGRATION_UPWARD_SPEED_MIN = 25
local DISINTEGRATION_UPWARD_SPEED_MAX = 55
local DEATH_HIGHLIGHT_DURATION = 0.30
local KNOCKBACK_HORIZONTAL_SPEED = 65
local KNOCKBACK_UPWARD_SPEED = 8
local MONSTER_PUSH_DISTANCE = 8
local MONSTER_PUSH_SECONDS = 0.20

local SHOCKWAVE_SOUND_EMITTER_SIZE = 0.1
local SHOCKWAVE_SOUND_LIFETIME = 8
local SHOCKWAVE_CORE_SIZE = 2
local SHOCKWAVE_CORE_FINAL_HEIGHT = 2.5
local SHOCKWAVE_CORE_LIFT = 1
local SHOCKWAVE_CORE_TRANSPARENCY = 0.15
local SHOCKWAVE_LIGHT_BRIGHTNESS = 42
local SHOCKWAVE_CORE_TWEEN_SECONDS = 1.20
local SHOCKWAVE_CORE_LIFETIME = 1.30
local SHOCKWAVE_SEGMENT_COUNT = 30
local SHOCKWAVE_SEGMENT_START_RADIUS = 1.25
local SHOCKWAVE_SEGMENT_LENGTH_EXTRA = 0.7
local SHOCKWAVE_SEGMENT_SIZE = Vector3.new(1.8, 0.7, 1.8)
local SHOCKWAVE_SEGMENT_FINAL_WIDTH = 2.2
local SHOCKWAVE_SEGMENT_TWEEN_SECONDS = 0.70
local SHOCKWAVE_SEGMENT_LIFETIME = 0.80
local playerState = {}
local didWarnMissingShockwave = false
local contourTargets = {}
local didWarnMissingMuzzle = false

local function isEquippedBy(player)
	return tool.Parent == player.Character
end

local function getEquippedPlayer()
	local character = tool.Parent
	return character and character:IsA("Model") and Players:GetPlayerFromCharacter(character) or nil
end

local function getChargeUnits(player)
	local configuredMaximum = Config.MAX_CHARGE_UNITS
	local isRespawnLoadout = player and tool:GetAttribute(Config.LOADOUT_CHARGE_ATTRIBUTE) == true
	local isNewWorldPickup = player
		and not isRespawnLoadout
		and tool:GetAttribute(Config.CHARGE_OWNER_ATTRIBUTE) ~= player.UserId
	local current
	if isNewWorldPickup then
		-- A world pickup is a real recharge event.  Do not reuse a depleted value
		-- left on the player by a previous loadout Tool.
		current = configuredMaximum
	else
		current = tonumber(player and player:GetAttribute(Config.PLAYER_CHARGE_ATTRIBUTE) or tool:GetAttribute(Config.CHARGE_ATTRIBUTE))
		if current == nil then
			current = tonumber(tool:GetAttribute(Config.CHARGE_ATTRIBUTE)) or configuredMaximum
		end
	end
	current = math.clamp(math.floor(current), 0, configuredMaximum)
	if player then
		player:SetAttribute(Config.PLAYER_CHARGE_ATTRIBUTE, current)
		tool:SetAttribute(Config.CHARGE_OWNER_ATTRIBUTE, player.UserId)
	end
	tool:SetAttribute(Config.CHARGE_ATTRIBUTE, current)
	return current
end

local function consumeChargeUnits(player, cost)
	cost = math.max(0, math.floor(tonumber(cost) or 0))
	local current = getChargeUnits(player)
	if current < cost then return false end
	current -= cost
	if player then player:SetAttribute(Config.PLAYER_CHARGE_ATTRIBUTE, current) end
	tool:SetAttribute(Config.CHARGE_ATTRIBUTE, current)
	return true
end

local function isInPlayerInventory()
	local parent = tool.Parent
	return parent and (
		(parent:IsA("Backpack") and parent.Parent and parent.Parent:IsA("Player"))
		or (parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) ~= nil)
	)
end

local function disableLegacyToolScripts()
	for _, item in tool:GetDescendants() do
		if item:IsA("BaseScript") and (
			item.Name == "AnchorScript"
			or item.Name == "GunSpawner"
			or item.Name == "MonsterBlasterGunSpawner"
			or item.Name == "WeaponSpawnSystem"
			or item.Name == "WeaponRuntimeSystem"
			or item.Name == "MonsterGunServer"
		) then
			item.Disabled = true
		end
	end
end

local function hasToolJoint(handle, part)
	for _, item in tool:GetDescendants() do
		if item:IsA("WeldConstraint") or item:IsA("Weld") or item:IsA("Motor6D") then
			if (item.Part0 == handle and item.Part1 == part) or (item.Part0 == part and item.Part1 == handle) then
				return true
			end
		end
	end
	return false
end

local function stabilizeToolAssembly()
	local handle = tool:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		warn("MonsterBlaster needs a BasePart named Handle:", tool:GetFullName())
		return
	end

	-- Roblox moves a picked-up Tool through Backpack before Character. Both are
	-- player inventory: anchoring during that handoff can pull the player back
	-- to the world-spawn CFrame through the Tool welds.
	local held = isInPlayerInventory()
	local usesPromptPickup = tool:FindFirstChild("MonsterBlasterPickupPrompt", true) ~= nil
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			item.Massless = true
			item.CanCollide = false
			item.Anchored = not held
			item.CanTouch = not held and not usesPromptPickup and item == handle
			if item ~= handle and not hasToolJoint(handle, item) then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "MonsterBlasterAssemblyWeld"
				weld.Part0 = handle
				weld.Part1 = item
				weld.Parent = handle
			end
		end
	end
end

local function getMonsterModelFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then return current end
		current = current.Parent
	end
end

local function makeRaycastParams(character, additionalIgnored)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = { character, tool }
	for _, instance in ipairs(additionalIgnored or {}) do
		table.insert(ignored, instance)
	end
	params.FilterDescendantsInstances = ignored
	params.IgnoreWater = true
	return params
end

local function getMuzzlePosition()
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") and muzzle.Parent and muzzle.Parent:IsA("BasePart") then
		return muzzle.WorldPosition
	end
	if not didWarnMissingMuzzle then
		didWarnMissingMuzzle = true
		warn("MonsterBlaster has no Muzzle Attachment; using Barrel temporarily:", tool:GetFullName())
	end
	local barrel = tool:FindFirstChild("Barrel", true) or tool:FindFirstChild("Handle", true)
	return barrel and barrel:IsA("BasePart") and barrel.Position or nil
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

local function isDirectTarget(model, cameraOrigin, direction, player)
	if not model or not model:IsA("Model") or not MonsterManager.getConfig(model) then return false end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return false end
	local result = workspace:Raycast(cameraOrigin, direction * Config.RANGE, makeRaycastParams(player.Character))
	return result and getMonsterModelFromHit(result.Instance) == model
end

local function updateContourGrace(player, target, cameraOrigin, direction)
	if isDirectTarget(target, cameraOrigin, direction, player) then
		contourTargets[player] = { model = target, expiresAt = os.clock() + AimConfig.ContourGraceSeconds }
	end
end

local function isVisibleMonster(model, cameraOrigin, player)
	if not model or not MonsterManager.getConfig(model) then return false end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return false end
	local targetPart = model:FindFirstChild("HumanoidRootPart", true) or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not targetPart or not targetPart:IsA("BasePart") then return false end
	local offset = targetPart.Position - cameraOrigin
	if offset.Magnitude < DIRECTION_EPSILON then return false end
	local result = workspace:Raycast(cameraOrigin, offset, makeRaycastParams(player.Character))
	return result and getMonsterModelFromHit(result.Instance) == model
end

local function getGraceTarget(player, cameraOrigin, direction)
	local cached = contourTargets[player]
	if not cached or cached.expiresAt < os.clock() then return nil end
	return isVisibleMonster(cached.model, cameraOrigin, player) and cached.model or nil
end

contourTargetEvent.OnServerEvent:Connect(function(player, reportedTool, originOffset, direction, target, generation)
	if not isPlayerInActiveRound(player) or not isCurrentGeneration(generation) then return end
	if reportedTool ~= tool or not isEquippedBy(player) then return end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < DIRECTION_EPSILON then return end
	local cameraOrigin = validateCameraOrigin(player, originOffset)
	if not cameraOrigin then return end
	updateContourGrace(player, target, cameraOrigin, direction.Unit)
end)

local function getServerShotResult(player, cameraOrigin, direction)
	local params = makeRaycastParams(player.Character)
	-- Let the exact crosshair ray win. Only an actual miss receives forgiving
	-- Spherecast assistance, which ignores WMTs so a nearby guardian cannot
	-- bend a Blaster shot away from the intended hostile target.
	local result = workspace:Raycast(cameraOrigin, direction * Config.RANGE, params)
	if not result then
		local ignored = {}
		while true do
			result = workspace:Spherecast(cameraOrigin, AimConfig.AimAssistRadius, direction * Config.RANGE,
				makeRaycastParams(player.Character, ignored))
			local candidate = result and getMonsterModelFromHit(result.Instance)
			if not candidate or MonsterManager.isWeaponAimAssistTarget(candidate) then break end
			table.insert(ignored, candidate)
		end
	end
	local endPosition = result and result.Position or (cameraOrigin + direction * Config.RANGE)
	local muzzle = getMuzzlePosition()
	if muzzle then
		local clearance = endPosition - muzzle
		if clearance.Magnitude > DIRECTION_EPSILON then
			local blocked = workspace:Raycast(muzzle, clearance.Unit * math.min(AimConfig.MuzzleClearanceDistance, clearance.Magnitude), params)
			if blocked then return blocked, muzzle, true end
		end
	end
	return result, cameraOrigin, false
end

local function getPiercedMonsterHits(origin, direction, character)
	local hits = {}
	local ignored = { character, tool }
	local currentOrigin = origin
	local remainingRange = Config.RANGE

	while remainingRange > 0 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignored
		params.IgnoreWater = true
		local result = workspace:Raycast(currentOrigin, direction * remainingRange, params)
		if not result then break end

		local monster = getMonsterModelFromHit(result.Instance)
		if not monster then break end -- monsters pierce; map geometry does not
		table.insert(hits, monster)
		table.insert(ignored, monster)

		local travelled = (result.Position - currentOrigin).Magnitude
		remainingRange -= travelled + PIERCE_RAY_ADVANCE
		currentOrigin = result.Position + direction * PIERCE_RAY_ADVANCE
	end

	return hits
end

local function shouldGroundShockwave(result)
	if not result or result.Normal.Y < GROUND_SURFACE_NORMAL_MIN then return false end
	if getMonsterModelFromHit(result.Instance) then return false end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	return not (model and Players:GetPlayerFromCharacter(model))
end

local function disintegrateMonster(model, blastOrigin)
	MonsterHitFeedback.flash(model, Config.FLASH_COLOR, DEATH_HIGHLIGHT_DURATION, false)
	for _, item in model:GetDescendants() do
		-- Imported rigs can be held together by ManualWeld, Glue, Snap, or a
		-- physical constraint. A lethal hit must sever every internal joint.
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then item:Destroy() end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.CanTouch = false
			part.Massless = false
			local direction = part.Position - blastOrigin
			if direction.Magnitude < DISINTEGRATION_DIRECTION_EPSILON then direction = Vector3.new(0, 1, 0) end
			part.AssemblyLinearVelocity = direction.Unit * math.random(DISINTEGRATION_SPEED_MIN, DISINTEGRATION_SPEED_MAX)
				+ Vector3.new(0, math.random(DISINTEGRATION_UPWARD_SPEED_MIN, DISINTEGRATION_UPWARD_SPEED_MAX), 0)
		end
	end
end

local function pushMonsterBack(model, blastOrigin)
	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Torso", true)
	if not root or not root:IsA("BasePart") then return end
	local direction = root.Position - blastOrigin
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < DIRECTION_EPSILON then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "BlasterPushAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "BlasterPush"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 80000
	velocity.VectorVelocity = direction.Unit * (MONSTER_PUSH_DISTANCE / MONSTER_PUSH_SECONDS)
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = root
	Debris:AddItem(velocity, MONSTER_PUSH_SECONDS)
	Debris:AddItem(attachment, MONSTER_PUSH_SECONDS)
end

local function damageMonster(player, model, damage, blastOrigin)
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return end
	-- A bonded guardian may be fighting inside either the direct beam or ground
	-- shockwave. MonsterGun damage remains deliberately reduced through
	-- MonsterManager, but the high-powered Blaster must never hurt or push a pet.
	if model:GetAttribute("WMTGuardianPet") == true then return end
	if model.Name == "BombMonster" and model:GetAttribute("BombWarningActive") == true then return end

	local effectiveDamage = MonsterManager.getPlayerWeaponDamage(model, damage)
	if effectiveDamage <= 0 then return end
	local willDie = humanoid.Health <= effectiveDamage
	MonsterManager.recordPlayerDamage(humanoid, player, effectiveDamage, Config.FLASH_COLOR)
	if model.Name == "Smiler" then
		-- Existing marketplace regeneration must not erase a charged Blaster hit
		-- during the weapon's own charge/cooldown window.
		humanoid:SetAttribute("BlasterRegenLockedUntil", workspace:GetServerTimeNow() + 5)
	end
	-- Every non-bomb Blaster lethal is a high-impact finish, whether caused by
	-- the direct beam or its ground shockwave. Bombs retain their separate
	-- warning/explosion lifecycle rather than becoming ordinary debris.
	local disintegrateOnDeath = willDie and model.Name ~= "BombMonster"
	if disintegrateOnDeath
		and string.sub(model.Name, 1, #"creepyMonster") ~= "creepyMonster"
	then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		-- Death listeners run synchronously from TakeDamage. Break and launch a
		-- confirmed-lethal target first, before corpse safety can neutralise the
		-- dead rig's scripts and physics.
		disintegrateMonster(model, blastOrigin)
	end
	humanoid:TakeDamage(effectiveDamage)
	if humanoid.Health > 0 then pushMonsterBack(model, blastOrigin) end

	if humanoid.Health > 0 then
		damageLabelEvent:FireClient(player, model, humanoid.Health, humanoid.MaxHealth, workspace:GetAttribute("RoundGeneration"))
		MonsterHitFeedback.flash(model, Config.FLASH_COLOR, MONSTER_FLASH_DURATION)
	else
		MonsterHitFeedback.illuminate(model, Config.FLASH_COLOR, KILL_ILLUMINATION_DURATION)
	end
end

local function playShockwaveSound(position)
	local source = tool:FindFirstChild("Shockwave", true)
	if not source or not source:IsA("Sound") then
		if not didWarnMissingShockwave then
			didWarnMissingShockwave = true
			warn("MonsterBlaster template needs a Sound named Shockwave:", tool:GetFullName())
		end
		return
	end

	local emitter = Instance.new("Part")
	emitter.Name = "BlasterShockwaveSound"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(SHOCKWAVE_SOUND_EMITTER_SIZE, SHOCKWAVE_SOUND_EMITTER_SIZE, SHOCKWAVE_SOUND_EMITTER_SIZE)
	emitter.Position = position
	emitter.Parent = workspace

	local sound = source:Clone()
	sound.Looped = false
	sound.Parent = emitter
	sound:Play()
	Debris:AddItem(emitter, SHOCKWAVE_SOUND_LIFETIME)
end

local function makeGroundShockwave(position, power)
	local radius = Config.shockwaveRadiusForPower(power)
	local core = Instance.new("Part")
	core.Name = "BlasterGroundShockwaveCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(SHOCKWAVE_CORE_SIZE, SHOCKWAVE_CORE_SIZE, SHOCKWAVE_CORE_SIZE)
	core.CFrame = CFrame.new(position + Vector3.new(0, SHOCKWAVE_CORE_LIFT, 0))
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Material = Enum.Material.Neon
	core.Color = Config.FLASH_COLOR
	core.Transparency = SHOCKWAVE_CORE_TRANSPARENCY
	core.Parent = workspace

	local coreLight = Instance.new("PointLight")
	coreLight.Color = Config.FLASH_COLOR
	coreLight.Brightness = SHOCKWAVE_LIGHT_BRIGHTNESS
	coreLight.Range = radius * 2
	coreLight.Parent = core
	TweenService:Create(core, TweenInfo.new(SHOCKWAVE_CORE_TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(radius * 2, SHOCKWAVE_CORE_FINAL_HEIGHT, radius * 2), Transparency = 1,
	}):Play()
	TweenService:Create(coreLight, TweenInfo.new(SHOCKWAVE_CORE_TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0, Range = 0,
	}):Play()
	Debris:AddItem(core, SHOCKWAVE_CORE_LIFETIME)

	local segmentLength = (2 * math.pi * radius) / SHOCKWAVE_SEGMENT_COUNT + SHOCKWAVE_SEGMENT_LENGTH_EXTRA
	for index = 1, SHOCKWAVE_SEGMENT_COUNT do
		local angle = (index - 1) / SHOCKWAVE_SEGMENT_COUNT * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local segment = Instance.new("Part")
		segment.Name = "BlasterGroundShockwaveSegment"
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.CastShadow = false
		segment.Material = Enum.Material.Neon
		segment.Color = Config.FLASH_COLOR
		segment.Transparency = 0
		segment.Size = SHOCKWAVE_SEGMENT_SIZE
		segment.CFrame = CFrame.new(position + direction * SHOCKWAVE_SEGMENT_START_RADIUS + Vector3.new(0, SHOCKWAVE_CORE_LIFT, 0)) * CFrame.Angles(0, angle, 0)
		segment.Parent = workspace
		TweenService:Create(segment, TweenInfo.new(SHOCKWAVE_SEGMENT_TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(SHOCKWAVE_SEGMENT_FINAL_WIDTH, SHOCKWAVE_SEGMENT_SIZE.Y, segmentLength),
			CFrame = CFrame.new(position + direction * radius + Vector3.new(0, SHOCKWAVE_CORE_LIFT, 0)) * CFrame.Angles(0, angle, 0),
			Transparency = 1,
		}):Play()
		Debris:AddItem(segment, SHOCKWAVE_SEGMENT_LIFETIME)
	end
end

local function damageGroundShockwave(player, position, power)
	local radius = Config.shockwaveRadiusForPower(power)
	local damage = Config.shockwaveDamageForPower(power)
	local candidates = {}
	local seen = {}
	for _, instance in workspace:GetDescendants() do
		-- A ground shockwave is indiscriminate emergency crowd control for
		-- hostile round contacts, never an accidental way to hurt a calm WMT.
		-- Direct WMT hits retain their separate guardian/trust consequences.
		if instance:IsA("Model")
			and instance.Name ~= "weird monster thing"
			and not seen[instance]
			and MonsterManager.getConfig(instance)
		then
			seen[instance] = true
			local root = instance:FindFirstChild("HumanoidRootPart", true) or instance:FindFirstChild("Head", true)
			local positionToTest = root and root:IsA("BasePart") and root.Position or instance:GetPivot().Position
			local distance = (positionToTest - position).Magnitude
			if distance <= radius then
				table.insert(candidates, {
					model = instance,
					distance = distance,
				})
			end
		end
	end

	-- Resolve the cap deterministically by taking the closest hostile contacts.
	-- This keeps a blast useful in a crowd while requiring additional blasts for
	-- monsters outside the first twelve selected targets.
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	local targetCount = math.min(Config.MAX_SHOCKWAVE_TARGETS, #candidates)
	for index = 1, targetCount do
		damageMonster(player, candidates[index].model, damage, position)
	end
end

local function pushShooterBack(player, direction)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if not root or flatDirection.Magnitude < DIRECTION_EPSILON then return end
	root.AssemblyLinearVelocity += -flatDirection.Unit * KNOCKBACK_HORIZONTAL_SPEED + Vector3.new(0, KNOCKBACK_UPWARD_SPEED, 0)
end

shootEvent.OnServerEvent:Connect(function(player, originOffset, direction, outlinedTarget, generation)
	if not isPlayerInActiveRound(player) or not isCurrentGeneration(generation) then return end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < DIRECTION_EPSILON or not isEquippedBy(player) then return end
	local state = playerState[player] or {}
	local now = os.clock()
	if now - (state.lastShotAt or -math.huge) < Config.COOLDOWN then return end

	local power = Config.SHOT_POWER
	-- Keep hit validation on the camera-selected ray.  Barrel direction can be
	-- temporarily stale while a shoulder camera turns, and must not move a
	-- shockwave or hit point away from the visible crosshair.
	local unitDirection = direction.Unit
	local cameraOrigin = validateCameraOrigin(player, originOffset)
	if not cameraOrigin then return end
	updateContourGrace(player, outlinedTarget, cameraOrigin, unitDirection)
	local graceTarget = getGraceTarget(player, cameraOrigin, unitDirection)
	local serverResult, origin, muzzleBlocked = getServerShotResult(player, cameraOrigin, unitDirection)
	if not origin then return end
	local isShockwave = shouldGroundShockwave(serverResult)
	local chargeCost = isShockwave and Config.SHOCKWAVE_CHARGE_UNITS or Config.DIRECT_SHOT_CHARGE_UNITS
	-- Charge is spent only after the server has accepted an equipped, valid shot
	-- and classified it.  The client HUD is presentation; it cannot grant shots.
	if not consumeChargeUnits(player, chargeCost) then return end
	state.lastShotAt = now
	playerState[player] = state
	pushShooterBack(player, unitDirection)

	if isShockwave then
		makeGroundShockwave(serverResult.Position, power)
		playShockwaveSound(serverResult.Position)
		damageGroundShockwave(player, serverResult.Position, power)
		return
	end

	local target = serverResult and getMonsterModelFromHit(serverResult.Instance)
	if not target and not muzzleBlocked then target = graceTarget end
	if not target then return end
	local damage = Config.damageForPower(power)
	if Config.PIERCES_MONSTERS then
		-- Preserve the forgiving Spherecast/contour target first, then continue
		-- through every monster that the exact camera ray crosses behind it.
		local damaged = { [target] = true }
		damageMonster(player, target, damage, origin)
		for _, monster in ipairs(getPiercedMonsterHits(origin, unitDirection, player.Character)) do
			if not damaged[monster] then
				damaged[monster] = true
				damageMonster(player, monster, damage, origin)
			end
		end
	else
		damageMonster(player, target, damage, origin)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerState[player] = nil
	contourTargets[player] = nil
end)

disableLegacyToolScripts()
getChargeUnits()
stabilizeToolAssembly()
tool.Equipped:Connect(function()
	getChargeUnits(getEquippedPlayer())
	stabilizeToolAssembly()
	task.defer(stabilizeToolAssembly)
end)
tool.AncestryChanged:Connect(function()
	disableLegacyToolScripts()
	stabilizeToolAssembly()
	task.defer(stabilizeToolAssembly)
end)

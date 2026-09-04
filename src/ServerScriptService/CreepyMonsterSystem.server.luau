-- CreepyMonsterSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local PLAYER_AGGRO_RANGE = 260
local ATTACK_RANGE = 5
local PLAYER_HIT_COOLDOWN = 1
local MONSTER_HIT_COOLDOWN = 3
local HUNT_CHECK_MIN = 20
local HUNT_CHECK_MAX = 35
local HUNT_CHANCE = 0.10
local HUNT_DURATION = 5
local UPDATE_INTERVAL = 0.25

local managed = {}
local stabilizedPhysics = {}

-- These marketplace variants have been observed carrying legacy movers that
-- fight Humanoid:MoveTo and launch/teleport the assembly. Yellow is stabilized
-- too even though it is not a configured combat type in this source snapshot.
local function stabilizeCreepyPhysics(model, humanoid, root)
	if model.Name ~= "creepyMonsterOrange" and model.Name ~= "creepyMonsterYellow" then return end
	if stabilizedPhysics[model] then return end
	stabilizedPhysics[model] = true
	for _, item in model:GetDescendants() do
		if item:IsA("BodyMover")
			or item:IsA("LinearVelocity")
			or item:IsA("VectorForce")
			or item:IsA("Torque")
			or item:IsA("AlignPosition")
			or item:IsA("AlignOrientation")
		then
			item:Destroy()
		end
	end
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	root.Anchored = false
	root.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- A narrow server-owned guard catches an outside collision/script injecting
	-- impossible velocity later, without micromanaging ordinary Humanoid walking.
	task.spawn(function()
		while model.Parent and humanoid.Parent and humanoid.Health > 0 do
			root.AssemblyAngularVelocity = Vector3.zero
			local velocity = root.AssemblyLinearVelocity
			if velocity.Y > 35 or velocity.Magnitude > math.max(70, humanoid.WalkSpeed * 4) then
				root.AssemblyLinearVelocity = Vector3.new(0, math.min(0, velocity.Y), 0)
			end
			task.wait(0.5)
		end
		stabilizedPhysics[model] = nil
	end)
end

local function isCreepy(model)
	return model:IsA("Model") and string.sub(model.Name, 1, #"creepyMonster") == "creepyMonster"
		and MonsterManager.getConfig(model) ~= nil
end

local function getRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function disableLegacyScripts(model)
	for _, item in model:GetDescendants() do
		if item:IsA("Script") and (item.Name == "Follow" or item.Name == "Damage Script") then
			item.Disabled = true
		end
	end
end

local function findNearestPlayerRoot(origin)
	local nearestRoot
	local nearestDistance = PLAYER_AGGRO_RANGE

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - origin).Magnitude
			if distance < nearestDistance then
				nearestRoot = root
				nearestDistance = distance
			end
		end
	end

	return nearestRoot
end

-- A guardian pet does not become a general-purpose prey target. Only the
-- specific monster it struck gets this temporary marker, and a nearby player
-- remains the creepy's clearly stronger priority.
local function getGuardianPetRetaliationTarget(model)
	local untilTime = tonumber(model:GetAttribute("WMTGuardianPetRetaliationUntil")) or 0
	if Workspace:GetServerTimeNow() >= untilTime then return nil, nil, nil end

	local marker = model:FindFirstChild("WMTGuardianPetRetaliationTarget")
	local target = marker and marker:IsA("ObjectValue") and marker.Value or nil
	local humanoid = target and MonsterManager.getMonsterHumanoid(target)
	local root = target and getRoot(target)
	if target and target.Parent and target:GetAttribute("WMTGuardianPet") == true
		and humanoid and humanoid.Health > 0 and root
	then
		return target, root, humanoid
	end
	return nil, nil, nil
end

local function findLowerHealthMonster(model, ownHp, origin)
	local nearestModel
	local nearestRoot
	local nearestHumanoid
	local nearestDistance = math.huge

	for _, candidate in Workspace:GetDescendants() do
		if candidate:IsA("Model") and candidate ~= model then
			local config = MonsterManager.getConfig(candidate)
			if config and config.hp < ownHp then
				local humanoid = MonsterManager.getMonsterHumanoid(candidate)
				local root = getRoot(candidate)
				if humanoid and root and humanoid.Health > 0 then
					local distance = (root.Position - origin).Magnitude
					if distance < nearestDistance then
						nearestModel = candidate
						nearestRoot = root
						nearestHumanoid = humanoid
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearestModel, nearestRoot, nearestHumanoid
end

local function setupCreepy(model)
	if not isCreepy(model) or managed[model] then return end

	local humanoid = MonsterManager.getMonsterHumanoid(model)
	local root = getRoot(model)
	local config = MonsterManager.getConfig(model)
	if not humanoid or not root or not config then return end

	disableLegacyScripts(model)
	stabilizeCreepyPhysics(model, humanoid, root)
	managed[model] = true
	model:SetAttribute("CentralCreepyAI", true)

	local state = {
		nextHuntCheck = os.clock() + math.random(HUNT_CHECK_MIN, HUNT_CHECK_MAX),
		huntUntil = 0,
		lastPlayerHit = 0,
		lastMonsterHit = 0,
	}
	local playerDamage = MonsterManager.getDamageToPlayers(model)
	local monsterDamage = MonsterManager.getDamageToMonsters(model)

	task.spawn(function()
		while model.Parent and humanoid.Parent and humanoid.Health > 0 do
			if model.Name == "creepyMonsterOrange" then
				-- A collision should not leave the whole rig spinning or flying after
				-- its legacy movers have been removed.
				root.AssemblyAngularVelocity = Vector3.zero
				if root.AssemblyLinearVelocity.Y > 35 then
					root.AssemblyLinearVelocity = Vector3.new(
						root.AssemblyLinearVelocity.X,
						0,
						root.AssemblyLinearVelocity.Z
					)
				end
			end
			local now = os.clock()
			if now >= state.nextHuntCheck then
				state.nextHuntCheck = now + math.random(HUNT_CHECK_MIN, HUNT_CHECK_MAX)
				if math.random() < HUNT_CHANCE then
					state.huntUntil = now + HUNT_DURATION
				end
			end

			local playerRoot = findNearestPlayerRoot(root.Position)
			local retaliationModel, retaliationRoot, retaliationHumanoid = getGuardianPetRetaliationTarget(model)
			local playerIsCloser = playerRoot and (
				not retaliationRoot
				or (playerRoot.Position - root.Position).Magnitude <= (retaliationRoot.Position - root.Position).Magnitude
			)
			if playerRoot and playerIsCloser then
				humanoid:MoveTo(playerRoot.Position)
				if (playerRoot.Position - root.Position).Magnitude <= ATTACK_RANGE and now - state.lastPlayerHit >= PLAYER_HIT_COOLDOWN then
					local character = playerRoot.Parent
					local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
					if targetHumanoid and targetHumanoid.Health > 0 then
						targetHumanoid:TakeDamage(playerDamage)
						state.lastPlayerHit = now
					end
				end
			elseif retaliationRoot and retaliationHumanoid then
				humanoid:MoveTo(retaliationRoot.Position)
				if (retaliationRoot.Position - root.Position).Magnitude <= ATTACK_RANGE
						and now - state.lastMonsterHit >= MONSTER_HIT_COOLDOWN
				then
					MonsterManager.damageMonsterTarget(retaliationModel, monsterDamage, model)
					state.lastMonsterHit = now
				end
			elseif now < state.huntUntil then
				local huntModel, huntRoot, huntHumanoid = findLowerHealthMonster(model, config.hp, root.Position)
				if huntRoot and huntHumanoid then
					humanoid:MoveTo(huntRoot.Position)
					if (huntRoot.Position - root.Position).Magnitude <= ATTACK_RANGE
						and now - state.lastMonsterHit >= MONSTER_HIT_COOLDOWN
					then
						MonsterManager.damageMonsterTarget(huntModel, monsterDamage, model)
						state.lastMonsterHit = now
					end
				end
			end

			task.wait(UPDATE_INTERVAL)
		end

		managed[model] = nil
	end)
end

for _, item in Workspace:GetDescendants() do
	if item:IsA("Model") then
		local humanoid = item:FindFirstChildOfClass("Humanoid")
		local root = getRoot(item)
		if humanoid and root then stabilizeCreepyPhysics(item, humanoid, root) end
		setupCreepy(item)
	end
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			local humanoid = item:FindFirstChildOfClass("Humanoid")
			local root = getRoot(item)
			if humanoid and root then stabilizeCreepyPhysics(item, humanoid, root) end
			setupCreepy(item)
		end)
	end
end)

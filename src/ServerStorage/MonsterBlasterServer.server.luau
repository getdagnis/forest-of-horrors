-- MonsterBlaster ServerScript
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local MonsterHitFeedback = require(ReplicatedStorage:WaitForChild("MonsterHitFeedback"))

local MIN_DAMAGE = 150
local MAX_DAMAGE = 450
local RANGE = 350
local GROUND_SHOCKWAVE_RADIUS = 20
local GROUND_SHOCKWAVE_DAMAGE = 150
local FLASH_COLOR = Color3.fromRGB(62, 169, 255)
local BOMB_MONSTER_NAME = "Monster"

local function getMonsterModelFromHit(instance)
	local current = instance
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then return current end
		current = current.Parent
	end
end

local function getPiercedMonsterHits(origin, direction, ignoreList)
	local hits, seen = {}, {}
	local currentOrigin, remainingRange = origin, RANGE

	while remainingRange > 0 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList
		params.IgnoreWater = true

		local result = workspace:Raycast(currentOrigin, direction * remainingRange, params)
		if not result then break end
		local monster = getMonsterModelFromHit(result.Instance)
		if monster and not seen[monster] then
			seen[monster] = true
			table.insert(hits, monster)
			table.insert(ignoreList, monster)
		else
			table.insert(ignoreList, result.Instance)
		end

		local travelled = (result.Position - currentOrigin).Magnitude
		remainingRange -= travelled + 0.1
		currentOrigin = result.Position + direction * 0.1
	end

	return hits
end

local function setBodyColors(bodyColors, color)
	bodyColors.HeadColor3 = color
	bodyColors.LeftArmColor3 = color
	bodyColors.RightArmColor3 = color
	bodyColors.LeftLegColor3 = color
	bodyColors.RightLegColor3 = color
	bodyColors.TorsoColor3 = color
end

local function flashMonster(model)
	MonsterHitFeedback.flash(model, FLASH_COLOR, 0.25)
end

local function makeMonsterBlue(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BodyColors") then
			setBodyColors(item, FLASH_COLOR)
		elseif item:IsA("BasePart") then
			item.Color = FLASH_COLOR
			item.Material = Enum.Material.Neon
		elseif item:IsA("Decal") or item:IsA("Texture") then
			item.Transparency = 0.45
		end
	end
end

local function disintegrateMonster(model, blastOrigin)
	makeMonsterBlue(model)
	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") or item:IsA("Weld") or item:IsA("WeldConstraint") then item:Destroy() end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.CanTouch = false
			part.Massless = false
			local direction = part.Position - blastOrigin
			if direction.Magnitude < 0.1 then
				direction = Vector3.new(math.random(-100, 100) / 100, 1, math.random(-100, 100) / 100)
			end
			part.AssemblyLinearVelocity = direction.Unit * math.random(45, 80) + Vector3.new(0, math.random(25, 55), 0)
		end
	end
end

local function getShotOrigin(player)
	local barrel = tool:FindFirstChild("Barrel")
	if barrel and barrel:IsA("BasePart") then return barrel.Position end
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then return handle.Position end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function getServerShotResult(player, shotDirection)
	local character, origin = player.Character, getShotOrigin(player)
	if not character or not origin then return nil end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true
	return workspace:Raycast(origin, shotDirection.Unit * RANGE, params)
end

local function shouldGroundShockwave(result)
	if not result or result.Normal.Y < 0.45 then return false end
	if getMonsterModelFromHit(result.Instance) then return false end
	local model = result.Instance:FindFirstAncestorOfClass("Model")
	return not (model and Players:GetPlayerFromCharacter(model))
end

local function makeGroundShockwave(position)
	local core = Instance.new("Part")
	core.Name = "BlasterGroundShockwaveCore"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2, 2, 2)
	core.CFrame = CFrame.new(position + Vector3.new(0, 1, 0))
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.CastShadow = false
	core.Material = Enum.Material.Neon
	core.Color = FLASH_COLOR
	core.Transparency = 0.15
	core.Parent = workspace

	local coreLight = Instance.new("PointLight")
	coreLight.Color = FLASH_COLOR
	coreLight.Brightness = 28
	coreLight.Range = GROUND_SHOCKWAVE_RADIUS * 1.5
	coreLight.Shadows = true
	coreLight.Parent = core

	TweenService:Create(core, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(GROUND_SHOCKWAVE_RADIUS * 2, 2.5, GROUND_SHOCKWAVE_RADIUS * 2),
		Transparency = 1,
	}):Play()
	TweenService:Create(coreLight, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Range = 0,
	}):Play()
	Debris:AddItem(core, 0.9)

	for wave = 1, 2 do
		task.delay((wave - 1) * 0.22, function()
			local segmentCount = 30
			local startRadius = 1.25
			local endRadius = GROUND_SHOCKWAVE_RADIUS
			local segmentLength = (2 * math.pi * endRadius) / segmentCount + 0.7

			for index = 1, segmentCount do
				local angle = (index - 1) / segmentCount * math.pi * 2
				local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
				local segment = Instance.new("Part")
				segment.Name = "BlasterGroundShockwaveSegment"
				segment.Anchored = true
				segment.CanCollide = false
				segment.CanQuery = false
				segment.CanTouch = false
				segment.CastShadow = false
				segment.Material = Enum.Material.Neon
				segment.Color = FLASH_COLOR
				segment.Transparency = 0.02
				segment.Size = Vector3.new(1.2, 0.7, 1.2)
				segment.CFrame = CFrame.new(position + direction * startRadius + Vector3.new(0, 1, 0)) * CFrame.Angles(0, angle, 0)
				segment.Parent = workspace

				TweenService:Create(segment, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(1.8, 0.7, segmentLength),
					CFrame = CFrame.new(position + direction * endRadius + Vector3.new(0, 1, 0)) * CFrame.Angles(0, angle, 0),
					Transparency = 1,
				}):Play()
				Debris:AddItem(segment, 0.85)
			end
		end)
	end
end

local function markBlasterKillIfNeeded(model, humanoid, damage)
	if model.Name == BOMB_MONSTER_NAME and humanoid.Health <= damage then
		MonsterManager.markPermanentKill(humanoid, "MonsterBlaster")
	end
end

local function damageMonster(player, model, damage, blastOrigin)
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return end
	local willDie = humanoid.Health <= damage
	MonsterManager.recordPlayerDamage(humanoid, player, damage, FLASH_COLOR)
	markBlasterKillIfNeeded(model, humanoid, damage)
	if willDie and (model.Name == "Drooling Zombie" or model.Name == "creepyMonster") then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		disintegrateMonster(model, blastOrigin)
	end
	humanoid:TakeDamage(damage)
	MonsterHitFeedback.showHealth(model, humanoid)
	if not willDie then
		flashMonster(model)
	else
		MonsterHitFeedback.illuminate(model, FLASH_COLOR, 0.3)
	end
end

local function damageGroundShockwave(player, position)
	local damaged = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and not damaged[instance] and MonsterManager.getConfig(instance) then
			damaged[instance] = true
			local root = instance:FindFirstChild("HumanoidRootPart", true) or instance:FindFirstChild("Head", true)
			local targetPosition = root and root:IsA("BasePart") and root.Position or instance:GetPivot().Position
			if (targetPosition - position).Magnitude <= GROUND_SHOCKWAVE_RADIUS then
				damageMonster(player, instance, GROUND_SHOCKWAVE_DAMAGE, position)
			end
		end
	end
end

local function pushShooterBack(player, shotDirection)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local flatDirection = Vector3.new(shotDirection.X, 0, shotDirection.Z)
	if flatDirection.Magnitude < 0.01 then return end
	root.AssemblyLinearVelocity += -flatDirection.Unit * 65 + Vector3.new(0, 8, 0)
end

shootEvent.OnServerEvent:Connect(function(player, clientHitInstance, shotDirection, chargeRatio)
	if typeof(shotDirection) ~= "Vector3" or shotDirection.Magnitude < 0.01 then return end
	local character = player.Character
	if tool.Parent ~= character and tool.Parent ~= player:FindFirstChild("Backpack") then return end

	chargeRatio = math.clamp(tonumber(chargeRatio) or 0, 0, 1)
	local damage = math.floor(MIN_DAMAGE + (MAX_DAMAGE - MIN_DAMAGE) * chargeRatio)
	local serverResult = getServerShotResult(player, shotDirection)
	pushShooterBack(player, shotDirection)

	if shouldGroundShockwave(serverResult) then
		makeGroundShockwave(serverResult.Position)
		damageGroundShockwave(player, serverResult.Position)
		return
	end

	if chargeRatio >= 0.98 then
		local origin = getShotOrigin(player)
		if not origin then return end
		for _, monster in ipairs(getPiercedMonsterHits(origin, shotDirection.Unit, { character, tool })) do
			damageMonster(player, monster, damage, origin)
		end
		return
	end

	local hitInstance = serverResult and serverResult.Instance or clientHitInstance
	local monster = getMonsterModelFromHit(hitInstance)
	if monster then damageMonster(player, monster, damage, getShotOrigin(player) or monster:GetPivot().Position) end
end)

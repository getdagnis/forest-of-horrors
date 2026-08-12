-- MonsterBlaster ServerScript
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local tool = script.Parent
local shootEvent = tool:WaitForChild("ShootEvent")
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local MIN_DAMAGE = 150
local MAX_DAMAGE = 450
local RANGE = 350

local GROUND_SHOCKWAVE_RADIUS = 20
local GROUND_SHOCKWAVE_DAMAGE = 150

local FLASH_COLOR = Color3.fromRGB(62, 169, 255)
local BLASTER_DEATH_COLOR = Color3.fromRGB(62, 169, 255)
local BOMB_MONSTER_NAME = "Monster"

local activeFlashes = {}

local SPECIAL_BLASTER_DEATHS = {
	["Drooling Zombie"] = true,
	["creepyMonster"] = true,
}

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

local function getBombMonsterFromHit(instance)
	local current = instance

	while current do
		if current:IsA("Model") and current:GetAttribute("BombMonster") == true then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function getPiercedMonsterHits(origin, direction, range, ignoreList)
	local hits = {}
	local seen = {}
	local currentOrigin = origin
	local remainingRange = range

	while remainingRange > 0 do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList
		params.IgnoreWater = true

		local result = workspace:Raycast(currentOrigin, direction * remainingRange, params)
		if not result then
			break
		end

		local monsterModel = getMonsterModelFromHit(result.Instance)
		local bombMonster = getBombMonsterFromHit(result.Instance)
		
		if bombMonster and _G.DamageBombMonster then
			_G.DamageBombMonster(bombMonster, MAX_DAMAGE)
			table.insert(ignoreList, bombMonster)
			continue
		end

		if monsterModel then
			if not seen[monsterModel] then
				seen[monsterModel] = true
				table.insert(hits, monsterModel)
			end

			table.insert(ignoreList, monsterModel)
		else
			table.insert(ignoreList, result.Instance)
		end

		local traveled = (result.Position - currentOrigin).Magnitude
		remainingRange -= traveled + 0.1
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
	if activeFlashes[model] then
		return
	end

	local original = {}
	activeFlashes[model] = original

	for _, item in model:GetDescendants() do
		if item:IsA("BodyColors") then
			original[item] = {
				Type = "BodyColors",
				HeadColor3 = item.HeadColor3,
				LeftArmColor3 = item.LeftArmColor3,
				RightArmColor3 = item.RightArmColor3,
				LeftLegColor3 = item.LeftLegColor3,
				RightLegColor3 = item.RightLegColor3,
				TorsoColor3 = item.TorsoColor3,
			}

			setBodyColors(item, FLASH_COLOR)
		elseif item:IsA("BasePart") then
			original[item] = {
				Type = "BasePart",
				Color = item.Color,
				Material = item.Material,
			}

			item.Color = FLASH_COLOR
			item.Material = Enum.Material.Neon
		end
	end

	task.delay(0.12, function()
		local saved = activeFlashes[model]
		activeFlashes[model] = nil

		if not saved then return end

		for item, values in saved do
			if item and item.Parent then
				if values.Type == "BodyColors" then
					item.HeadColor3 = values.HeadColor3
					item.LeftArmColor3 = values.LeftArmColor3
					item.RightArmColor3 = values.RightArmColor3
					item.LeftLegColor3 = values.LeftLegColor3
					item.RightLegColor3 = values.RightLegColor3
					item.TorsoColor3 = values.TorsoColor3
				elseif values.Type == "BasePart" then
					item.Color = values.Color
					item.Material = values.Material
				end
			end
		end
	end)
end

local function makeMonsterBlue(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BodyColors") then
			setBodyColors(item, BLASTER_DEATH_COLOR)
		elseif item:IsA("BasePart") then
			item.Color = BLASTER_DEATH_COLOR
			item.Material = Enum.Material.Neon
		elseif item:IsA("Decal") or item:IsA("Texture") then
			item.Transparency = 0.45
		end
	end
end

local function explodeMonsterParts(model, blastOrigin)
	makeMonsterBlue(model)

	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") or item:IsA("Weld") or item:IsA("WeldConstraint") then
			item:Destroy()
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.Massless = false

			local direction = part.Position - blastOrigin
			if direction.Magnitude < 0.1 then
				direction = Vector3.new(
					math.random(-100, 100) / 100,
					1,
					math.random(-100, 100) / 100
				)
			end

			part.AssemblyLinearVelocity =
				direction.Unit * math.random(45, 80)
				+ Vector3.new(0, math.random(25, 55), 0)

			part.AssemblyAngularVelocity = Vector3.new(
				math.random(-10, 10),
				math.random(-10, 10),
				math.random(-10, 10)
			)
		end
	end
end

local function showHitpoints(model, humanoid)
	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Head", true)
	if not root or not root:IsA("BasePart") then return end

	local gui = model:FindFirstChild("MonsterHealthGui")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "MonsterHealthGui"
		gui.Size = UDim2.new(0, 180, 0, 44)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = model

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end

	gui.Adornee = root
	gui.Enabled = true

	local label = gui:FindFirstChild("Label")
	if label then
		label.Text = math.max(0, math.ceil(humanoid.Health)) .. " / " .. math.ceil(humanoid.MaxHealth)
	end

	task.delay(1.5, function()
		if gui and gui.Parent then
			gui.Enabled = false
		end
	end)
end

local function getShotOrigin(player)
	local barrel = tool:FindFirstChild("Barrel")
	if barrel and barrel:IsA("BasePart") then
		return barrel.Position
	end

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle.Position
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function getServerShotResult(player, shotDirection)
	local character = player.Character
	local origin = getShotOrigin(player)
	if not character or not origin then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true

	return workspace:Raycast(origin, shotDirection.Unit * RANGE, params)
end

local function isPlayerPart(instance)
	local model = instance and instance:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model) ~= nil
end

local function shouldGroundShockwave(result)
	if not result then return false end
	if result.Normal.Y < 0.45 then return false end
	if isPlayerPart(result.Instance) then return false end
	if getMonsterModelFromHit(result.Instance) then return false end
	if getBombMonsterFromHit(result.Instance) then return false end

	return true
end

local function markBlasterKillIfNeeded(model, humanoid, damageAmount)
	if model.Name == BOMB_MONSTER_NAME and humanoid.Health - damageAmount <= 0 then
		MonsterManager.markPermanentKill(humanoid, "MonsterBlaster")
	end
end

local function makeGroundShockwave(position)
	local shockwave = Instance.new("Part")
	shockwave.Name = "BlasterGroundShockwave"
	shockwave.Shape = Enum.PartType.Cylinder
	shockwave.Anchored = true
	shockwave.CanCollide = false
	shockwave.CanQuery = false
	shockwave.CanTouch = false
	shockwave.CastShadow = false
	shockwave.Material = Enum.Material.Neon
	shockwave.Color = FLASH_COLOR
	shockwave.Transparency = 0.25
	shockwave.Size = Vector3.new(1, 0.25, 1)
	shockwave.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0))
	shockwave.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = FLASH_COLOR
	light.Brightness = 10
	light.Range = GROUND_SHOCKWAVE_RADIUS
	light.Parent = shockwave

	TweenService:Create(
		shockwave,
		TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(GROUND_SHOCKWAVE_RADIUS * 2, 0.25, GROUND_SHOCKWAVE_RADIUS * 2),
			Transparency = 1,
		}
	):Play()

	TweenService:Create(
		light,
		TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Brightness = 0,
			Range = GROUND_SHOCKWAVE_RADIUS * 1.3,
		}
	):Play()

	Debris:AddItem(shockwave, 0.55)
end

local function damageGroundShockwave(player, position)
	local damaged = {}

	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and not damaged[instance] and MonsterManager.getConfig(instance) then
			damaged[instance] = true

			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			if humanoid and humanoid.Health > 0 then
				local root = instance:FindFirstChild("HumanoidRootPart", true) or instance:FindFirstChild("Head", true)
				local targetPosition = root and root:IsA("BasePart") and root.Position or instance:GetPivot().Position

				if (targetPosition - position).Magnitude <= GROUND_SHOCKWAVE_RADIUS then
					MonsterManager.recordPlayerDamage(humanoid, player, GROUND_SHOCKWAVE_DAMAGE, FLASH_COLOR)
					markBlasterKillIfNeeded(instance, humanoid, GROUND_SHOCKWAVE_DAMAGE)
					humanoid:TakeDamage(GROUND_SHOCKWAVE_DAMAGE)

					if humanoid.Health > 0 then
						flashMonster(instance)
						showHitpoints(instance, humanoid)
					end
				end
			end
		end
	end
end

local function pushShooterBack(player, shotDirection)
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local direction = Vector3.new(shotDirection.X, 0, shotDirection.Z)

	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
		direction = Vector3.new(direction.X, 0, direction.Z)
	end

	if direction.Magnitude < 0.1 then return end

	root.AssemblyLinearVelocity =
		root.AssemblyLinearVelocity
		+ (-direction.Unit * 65)
		+ Vector3.new(0, 8, 0)
end

shootEvent.OnServerEvent:Connect(function(player, hitInstance, shotDirection, chargeRatio)
	if typeof(shotDirection) ~= "Vector3" then return end
	if shotDirection.Magnitude <= 0 then return end

	chargeRatio = tonumber(chargeRatio) or 0
	chargeRatio = math.clamp(chargeRatio, 0, 1)

	local damage = math.floor(MIN_DAMAGE + ((MAX_DAMAGE - MIN_DAMAGE) * chargeRatio))
	local fullCharge = chargeRatio >= 0.98

	pushShooterBack(player, shotDirection)

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local serverResult = getServerShotResult(player, shotDirection)
	if shouldGroundShockwave(serverResult) then
		makeGroundShockwave(serverResult.Position)
		damageGroundShockwave(player, serverResult.Position)
		return
	end

	local monsterModels = {}

	if fullCharge then
		monsterModels = getPiercedMonsterHits(
			root.Position,
			shotDirection.Unit,
			RANGE,
			{ character, tool }
		)
	else
		if not hitInstance or not hitInstance.Parent then
			return
		end

		local bombMonster = getBombMonsterFromHit(hitInstance)
		if bombMonster and _G.DamageBombMonster then
			_G.DamageBombMonster(bombMonster, damage)
			return
		end

		local monsterModel = getMonsterModelFromHit(hitInstance)
		if monsterModel then
			table.insert(monsterModels, monsterModel)
		end
	end

	for _, monsterModel in monsterModels do
		local target = MonsterManager.getMonsterHumanoid(monsterModel)

		if target and target.Health > 0 then
			local willDie = target.Health - damage <= 0
			local specialDeath = willDie and SPECIAL_BLASTER_DEATHS[monsterModel.Name]

			MonsterManager.recordPlayerDamage(
				target,
				player,
				damage,
				Color3.fromRGB(62, 169, 255)
			)

			if specialDeath then
				target.BreakJointsOnDeath = false
				explodeMonsterParts(monsterModel, root.Position)
			end

			markBlasterKillIfNeeded(monsterModel, target, damage)
			target:TakeDamage(damage)

			if not willDie then
				flashMonster(monsterModel)
				showHitpoints(monsterModel, target)
			end
		end
	end
end)

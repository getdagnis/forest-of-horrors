-- GunCombatSystem
-- The sole server-side combat owner for the MonsterGun family.  Clients submit
-- an aim direction only; the server owns the barrel raycast, damage, scoring,
-- and the visual broadcast that every client renders.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local RANGE = 400
local DEFAULT_BURST_DELAY = 0.08
local MIN_FIRE_INTERVAL = 0.08
local HIT_COLOR = Color3.fromRGB(212, 159, 162)

local GUNS = {
	MonsterGun = { damage = 30, color = HIT_COLOR, shots = 1, interval = 0.10 },
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

local boundEvents = {}
local lastShotAt = {}

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

local function getShotOrigin(tool, player)
	local barrel = tool:FindFirstChild("Barrel", true)
	if barrel and barrel:IsA("BasePart") then return barrel.Position end
	local handle = tool:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then return handle.Position end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function getServerShot(tool, player, direction)
	local origin = getShotOrigin(tool, player)
	if not origin then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, tool }
	params.IgnoreWater = true
	local result = workspace:Raycast(origin, direction.Unit * RANGE, params)
	return origin, result, result and result.Position or (origin + direction.Unit * RANGE)
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

local function resolveShot(player, tool, config, direction)
	if not isEquippedBy(player, tool) then return end
	local origin, result, endPosition = getServerShot(tool, player, direction)
	if not origin then return end

	local monsterModel = result and getMonsterModelFromHit(result.Instance) or nil
	-- Every accepted ray is sent to every client, including misses.  The client
	-- owns only short-lived visuals; no client result can affect combat.
	shotVisualEvent:FireAllClients(tool, origin, endPosition, config.color, monsterModel)
	if not monsterModel then return end

	local humanoid = MonsterManager.getMonsterHumanoid(monsterModel)
	if not humanoid or humanoid.Health <= 0 then return end

	local willDie = humanoid.Health <= config.damage
	MonsterManager.recordPlayerDamage(humanoid, player, config.damage, config.color)
	if willDie then
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		if monsterModel.Name == "BombMonster" then
			MonsterManager.markPermanentKill(humanoid, "MonsterGun")
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		disintegrateMonster(monsterModel, root and root.Position or monsterModel:GetPivot().Position)
	end

	humanoid:TakeDamage(config.damage)
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

	shootEvent.OnServerEvent:Connect(function(player, shotDirection)
		local currentConfig = getGunConfig(tool)
		if not currentConfig or not isEquippedBy(player, tool) then return end
		if typeof(shotDirection) ~= "Vector3" or shotDirection.Magnitude < 0.01 then return end
		if not canFire(tool, currentConfig.interval) then return end

		local direction = shotDirection.Unit
		resolveShot(player, tool, currentConfig, direction)
		if currentConfig.shots == 2 then
			task.delay(currentConfig.burstDelay, function()
				resolveShot(player, tool, currentConfig, direction)
			end)
		end
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if not parent then lastShotAt[tool] = nil end
	end)
end

for _, instance in game:GetDescendants() do
	bindTool(instance)
end
game.DescendantAdded:Connect(bindTool)

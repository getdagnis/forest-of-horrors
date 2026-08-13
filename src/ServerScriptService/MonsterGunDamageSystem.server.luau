-- MonsterGunDamageSystem
-- Sole server-side combat owner for active MonsterGun Tools.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local MonsterHitFeedback = require(ReplicatedStorage:WaitForChild("MonsterHitFeedback"))

local DAMAGE = 20
local RANGE = 300
local FIRE_INTERVAL = 0.1
local HIT_COLOR = Color3.fromRGB(255, 105, 180)

local boundEvents = {}
local lastShotAt = {}

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
	local barrel = tool:FindFirstChild("Barrel")
	if barrel and barrel:IsA("BasePart") then return barrel.Position end
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then return handle.Position end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function getServerHit(tool, player, direction)
	local origin = getShotOrigin(tool, player)
	if not origin then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character, tool }
	params.IgnoreWater = true
	local result = workspace:Raycast(origin, direction.Unit * RANGE, params)
	return result and result.Instance or nil
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

local function canFire(player, tool)
	local now = os.clock()
	local previous = lastShotAt[tool]
	if previous and now - previous < FIRE_INTERVAL then return false end
	lastShotAt[tool] = now
	return true
end

local function bindTool(tool)
	if not tool:IsA("Tool") or tool.Name ~= "MonsterGun" then return end
	local shootEvent = tool:FindFirstChild("ShootEvent")
	if not shootEvent or not shootEvent:IsA("RemoteEvent") or boundEvents[shootEvent] then return end
	boundEvents[shootEvent] = true

	shootEvent.OnServerEvent:Connect(function(player, clientHitInstance, shotDirection)
		if tool.Parent ~= player.Character then return end
		if typeof(shotDirection) ~= "Vector3" or shotDirection.Magnitude < 0.01 then return end
		if not canFire(player, tool) then return end

		-- The server raycast is authoritative.  The client hit is only a short
		-- fallback for a target that moved between client/server physics frames.
		local hitInstance = getServerHit(tool, player, shotDirection)
		local monsterModel = getMonsterModelFromHit(hitInstance)
		if not monsterModel then
			monsterModel = getMonsterModelFromHit(clientHitInstance)
		end
		if not monsterModel then return end

		local humanoid = MonsterManager.getMonsterHumanoid(monsterModel)
		if not humanoid or humanoid.Health <= 0 then return end

		local willDie = humanoid.Health <= DAMAGE
		MonsterManager.recordPlayerDamage(humanoid, player, DAMAGE, HIT_COLOR)
		if willDie then
			humanoid.BreakJointsOnDeath = false
			humanoid.RequiresNeck = false
			if monsterModel.Name == "Monster" then
				MonsterManager.markPermanentKill(humanoid, "MonsterGun")
			end
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			MonsterHitFeedback.illuminate(monsterModel, HIT_COLOR, 0.3)
			disintegrateMonster(monsterModel, root and root.Position or monsterModel:GetPivot().Position)
		end

		humanoid:TakeDamage(DAMAGE)
		MonsterHitFeedback.showHealth(monsterModel, humanoid)
		if not willDie then
			MonsterHitFeedback.flash(monsterModel, HIT_COLOR, 0.25)
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

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local GUARDIAN_NAME = "weird monster thing"
local DAMAGE = 35
local COOLDOWN = 0.8

local guardians = {}
local recentHits = {}

local function isGuardian(model)
	return model:IsA("Model") and model.Name == GUARDIAN_NAME
end

local function isLegPart(part)
	local name = string.lower(part.Name)
	return string.find(name, "leg") ~= nil or string.find(name, "foot") ~= nil
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

local function disablePlayerDamage(model)
	local config = model:FindFirstChild("Configuration")
	if not config then return end

	local attackDamage = config:FindFirstChild("AttackDamage")
	if attackDamage and attackDamage:IsA("NumberValue") then
		attackDamage.Value = 0
	end
end

local function removeOldPerModelGuardianScript(model)
	local oldScript = model:FindFirstChild("GuardianLegDamage")
	if oldScript and oldScript:IsA("Script") then
		oldScript:Destroy()
	end
end

local function damageMonster(guardian, hit)
	local targetModel = getMonsterModelFromHit(hit)
	if not targetModel then return end
	if targetModel == guardian then return end
	if targetModel.Name == GUARDIAN_NAME then return end

	local humanoid = MonsterManager.getMonsterHumanoid(targetModel)
	if not humanoid or humanoid.Health <= 0 then return end
	if recentHits[humanoid] then return end

	recentHits[humanoid] = true
	humanoid:TakeDamage(DAMAGE)

	task.delay(COOLDOWN, function()
		recentHits[humanoid] = nil
	end)
end

local function connectLeg(guardian, part)
	if not part:IsA("BasePart") or not isLegPart(part) then return end

	local state = guardians[guardian]
	if not state or state.parts[part] then return end

	state.parts[part] = true
	part.Touched:Connect(function(hit)
		damageMonster(guardian, hit)
	end)
end

local function setupGuardian(model)
	if not isGuardian(model) or guardians[model] then return end

	guardians[model] = {
		parts = {},
	}

	disablePlayerDamage(model)
	removeOldPerModelGuardianScript(model)

	for _, item in model:GetDescendants() do
		connectLeg(model, item)
	end

	model.DescendantAdded:Connect(function(item)
		task.defer(function()
			connectLeg(model, item)
		end)
	end)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			guardians[model] = nil
		end
	end)
end

for _, item in Workspace:GetDescendants() do
	if item:IsA("Model") then
		setupGuardian(item)
	end
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			setupGuardian(item)
		end)
	end
end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local model = script.Parent

local DAMAGE = 35
local COOLDOWN = 0.8

local recentHits = {}

local function isLegPart(part)
	local name = string.lower(part.Name)

	return string.find(name, "leg") ~= nil
		or string.find(name, "foot") ~= nil
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

local function damageMonster(hit)
	local targetModel = getMonsterModelFromHit(hit)
	if not targetModel then return end
	if targetModel == model then return end
	if targetModel.Name == "weird monster thing" then return end

	local humanoid = MonsterManager.getMonsterHumanoid(targetModel)
	if not humanoid or humanoid.Health <= 0 then return end

	if recentHits[humanoid] then return end
	recentHits[humanoid] = true

	humanoid:TakeDamage(DAMAGE)

	task.delay(COOLDOWN, function()
		recentHits[humanoid] = nil
	end)
end

for _, item in model:GetDescendants() do
	if item:IsA("BasePart") and isLegPart(item) then
		item.Touched:Connect(damageMonster)
	end
end

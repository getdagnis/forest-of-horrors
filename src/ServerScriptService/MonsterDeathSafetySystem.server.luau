local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local connected = {}

local function stopCorpse(model, humanoid)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanTouch = false
		elseif item:IsA("BaseScript") then
			item.Disabled = true
		end
	end
end

local function monitor(model)
	if not model:IsA("Model") or not MonsterManager.getConfig(model) then return end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or connected[humanoid] then return end
	connected[humanoid] = true

	humanoid.Died:Connect(function()
		stopCorpse(model, humanoid)
	end)
end

for _, instance in workspace:GetDescendants() do monitor(instance) end
workspace.DescendantAdded:Connect(monitor)

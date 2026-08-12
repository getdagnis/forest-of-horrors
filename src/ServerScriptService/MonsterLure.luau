-- lure monsters towards the nearest player
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local UPDATE_EVERY = 4
local LURE_RADIUS = 450
local MIN_DISTANCE = 25
local MOVE_OFFSET = 18

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Torso", true)
end

local function getNearestPlayerRoot(monsterRoot)
	local nearestRoot = nil
	local nearestDistance = LURE_RADIUS

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - monsterRoot.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestRoot = root
			end
		end
	end

	return nearestRoot, nearestDistance
end

while true do
	task.wait(UPDATE_EVERY)

	for _, model in Workspace:GetDescendants() do
		if model:IsA("Model") and MonsterManager.getConfig(model) then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			local root = getRoot(model)

			if humanoid and root and humanoid.Health > 0 then
				local playerRoot, distance = getNearestPlayerRoot(root)

				if playerRoot and distance > MIN_DISTANCE then
					local direction = playerRoot.Position - root.Position
					direction = Vector3.new(direction.X, 0, direction.Z)

					if direction.Magnitude > 0.1 then
						local targetPosition = root.Position + direction.Unit * MOVE_OFFSET
						humanoid:MoveTo(targetPosition)
					end
				end
			end
		end
	end
end
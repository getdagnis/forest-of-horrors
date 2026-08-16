-- lure monsters towards the nearest player
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

-- Experiment controls. Keep this Script enabled as an optional global pull,
-- but leave zombies to ZombieAISystem by default so they retain varied goals.
-- Set ENABLED false to park this system without deleting it; set LURE_ZOMBIES
-- true only when deliberately testing the old all-zombies-to-player effect.
local ENABLED = true
local LURE_ZOMBIES = false
local LURE_GUARDIANS = false


-- This is a gentle fallback for otherwise idle monsters, not their combat AI.
-- It wakes every sixteen seconds rather than every frame, but it still scans
-- Workspace: increasing UPDATE_EVERY is the safest way to reduce crowd cost,
-- at the trade-off of slower re-engagement by remote inactive monsters.
local UPDATE_EVERY = 16

-- Only monsters already within this broad radius of a living player receive a
-- small nudge. The current radius keeps the pull local enough to preserve
-- variety; increasing it produces larger, more uniform player-facing crowds.
local LURE_RADIUS = 250

-- Do not override close-range combat/navigation. Within this distance, the
-- monster's own AI should own movement; a larger value leaves more breathing
-- room, while a smaller value lets this fallback compete more often.
local MIN_DISTANCE = 50

-- Each update requests only a short horizontal step. Keeping it small makes
-- the lure a gradual hint instead of visible snapping or a substitute for
-- pathfinding; increasing it can make obstacles and crowding worse.
local MOVE_OFFSET = 12

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
	if not ENABLED then continue end

	for _, model in Workspace:GetDescendants() do
		if model:IsA("Model")
			and MonsterManager.getConfig(model)
			and (LURE_ZOMBIES or model.Name ~= "Drooling Zombie")
			and (LURE_GUARDIANS or model.Name ~= "weird monster thing")
		then
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

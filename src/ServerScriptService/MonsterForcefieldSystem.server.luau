--[[
	Monster Forcefield System
	--------------------------
	Invisible barriers that block ALL non-player humanoids except
	those whitelisted in WHITELISTED_MONSTERS.

	To add more barriers, duplicate any "MonsterForcefield" Part
	and place it anywhere in the Workspace. The script handles the rest.

	After TIME_LIMIT_MINUTES, all barriers are removed.

	Collision groups physically stop recognized monsters at the barriers.
	Never move a model or Workspace to enforce a barrier.
--]]

--======================== CONFIGURATION ========================--

-- After this many minutes, all MonsterForcefield parts are removed
-- and blocked monsters can pass through freely.
local TIME_LIMIT_MINUTES = 15

-- WHITELIST: true = ALLOWED through barriers.
-- Any non-player humanoid NOT listed here is blocked by default.
-- This includes nested sub-models (e.g. "Noob" inside creepyMonster):
-- if any ancestor model is whitelisted, the nested model is allowed too.
local WHITELISTED_MONSTERS = {
	-- ["SomeHarmlessMonster"] = true,
}


--======================== END CONFIGURATION ===================--

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local MonsterManager = require(game:GetService("ReplicatedStorage"):WaitForChild("MonsterManager"))

local GROUP_BLOCKER = "MonsterForcefield"
local GROUP_MONSTER = "BlockedMonster"

-- Collision group setup
PhysicsService:RegisterCollisionGroup(GROUP_BLOCKER)
PhysicsService:RegisterCollisionGroup(GROUP_MONSTER)

-- Blocker does NOT collide with Default (players walk through)
PhysicsService:CollisionGroupSetCollidable(GROUP_BLOCKER, "Default", false)
-- Blocker DOES collide with BlockedMonster (monsters are stopped)
PhysicsService:CollisionGroupSetCollidable(GROUP_BLOCKER, GROUP_MONSTER, true)
-- BlockedMonster still collides with Default (ground, walls, etc.)
PhysicsService:CollisionGroupSetCollidable(GROUP_MONSTER, "Default", true)
-- BlockedMonster collides with itself (monsters don't overlap)
PhysicsService:CollisionGroupSetCollidable(GROUP_MONSTER, GROUP_MONSTER, true)

-- Registries for efficient iteration
local blockedMonsters = {}  -- [model] = true
local forcefieldParts = {}  -- [part] = true

-- Check if a model or any of its ancestors is whitelisted
local function isWhitelisted(model)
	local current = model
	while current and current:IsA("Instance") do
		if current:IsA("Model") and WHITELISTED_MONSTERS[current.Name] then
			return true
		end
		current = current.Parent
	end
	return false
end

-- Check if a model is a player character
local function isPlayerCharacter(model)
	return Players:GetPlayerFromCharacter(model) ~= nil
end

-- Assign only the canonical monster model, including its nested rig.
-- Never promote a model to its parent: Workspace itself inherits Model.
local function blockModel(model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.CollisionGroup ~= GROUP_BLOCKER then
			part.CollisionGroup = GROUP_MONSTER
		end
	end
	blockedMonsters[model] = true
end

-- Decide whether a model should be blocked, and block it if so
local function evaluateModel(model)
	if model == Workspace or not MonsterManager.getConfig(model) then return end
	if not MonsterManager.getMonsterHumanoid(model) then return end
	if isPlayerCharacter(model) then return end
	if isWhitelisted(model) then return end
	blockModel(model)
end

-- For parts added later: check if any ancestor is already in the
-- blockedMonsters registry. This handles nested sub-models (like
-- "Noob" inside creepyMonster) that respawn during gameplay.
local function evaluatePart(part)
	if part.CollisionGroup == GROUP_MONSTER then return end
	if part.CollisionGroup == GROUP_BLOCKER then return end
	local current = part.Parent
	while current do
		if current:IsA("Model") then
			if isPlayerCharacter(current) then return end
			if blockedMonsters[current] then
				part.CollisionGroup = GROUP_MONSTER
				return
			end
			-- Also check if this model has a Humanoid and should be blocked
			if current ~= Workspace and MonsterManager.getConfig(current)
				and MonsterManager.getMonsterHumanoid(current) and not isWhitelisted(current) then
				part.CollisionGroup = GROUP_MONSTER
				return
			end
		end
		current = current.Parent
	end
end

-- Set up all existing models with Humanoids and all barrier parts
for _, desc in ipairs(Workspace:GetDescendants()) do
	if desc:IsA("Model") then
		evaluateModel(desc)
	elseif desc:IsA("BasePart") and desc.Name == "MonsterForcefield" then
		desc.CollisionGroup = GROUP_BLOCKER
		forcefieldParts[desc] = true
	end
end

-- Handle things added during gameplay
Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") then
		evaluateModel(desc)
	elseif desc:IsA("BasePart") then
		if desc.Name == "MonsterForcefield" then
			desc.CollisionGroup = GROUP_BLOCKER
			forcefieldParts[desc] = true
		else
			evaluatePart(desc)
		end
	end
end)

Workspace.DescendantRemoving:Connect(function(desc)
	if desc:IsA("BasePart") and desc.Name == "MonsterForcefield" then
		forcefieldParts[desc] = nil
	elseif desc:IsA("Model") then
		blockedMonsters[desc] = nil
	end
end)

-- Barriers use collision only. No CFrame/PivotTo pushback or safe-position cache.

-- Remove all barriers after the time limit
task.delay(TIME_LIMIT_MINUTES * 60, function()
	for part in pairs(forcefieldParts) do
		if part.Parent then
			part.Parent = nil
		end
	end
	forcefieldParts = {}
	print("[MonsterForcefield] Time limit reached — all barriers removed.")
end)

print("[MonsterForcefield] System initialized. Barriers active for " .. TIME_LIMIT_MINUTES .. " minutes.")

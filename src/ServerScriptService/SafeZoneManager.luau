-- SafeZoneManager: keeps McDonald's and the Donut Store safe from monsters.
-- Monsters cannot ENTER these zones, and any monster already inside at map
-- start cannot EXIT (it is trapped). Works for every monster movement type
-- (custom pathfinding, direct MoveTo, etc.) by monitoring positions and
-- teleporting monsters back to their "home side" of the zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

-- Build safe zones from the two buildings' bounding boxes (XZ footprint).
local SAFE_ZONES = {}
local function buildSafeZones()
	for _, name in ipairs({ "McDonald's", "Donut Store" }) do
		local model = workspace:FindFirstChild(name)
		if model then
			local cf, size = model:GetBoundingBox()
			table.insert(SAFE_ZONES, {
				name = name,
				minX = cf.Position.X - size.X / 2,
				maxX = cf.Position.X + size.X / 2,
				minZ = cf.Position.Z - size.Z / 2,
				maxZ = cf.Position.Z + size.Z / 2,
				center = cf.Position,
			})
		end
	end
end
buildSafeZones()

local function pointInZone(x, z, zone)
	return x >= zone.minX and x <= zone.maxX and z >= zone.minZ and z <= zone.maxZ
end

local function findZone(x, z)
	for _, zone in ipairs(SAFE_ZONES) do
		if pointInZone(x, z, zone) then
			return zone
		end
	end
	return nil
end

-- Find a part we can use to read/move the monster's position.
-- Recursive search so we find root parts nested in sub-models
-- (e.g. creepyMonster's HumanoidRootPart lives inside its "Noob" child).
-- Falls back to any BasePart so models like the bomb "Monster" (which
-- has no standard root part) are still tracked.
local function getRootPart(model)
	return model.PrimaryPart
		or model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Torso", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function isMonster(model)
	return MonsterManager.getConfig(model) ~= nil
end

-- homeZone[model] = the zone the monster belongs to, or false if it belongs outside.
local registered = {}
local homeZone = {}

local function registerMonster(model)
	if registered[model] then return end
	registered[model] = true
	local root = getRootPart(model)
	if not root then
		-- Model may not be fully loaded yet; retry shortly.
		task.delay(1, function()
			if model.Parent then
				local r = getRootPart(model)
				if r then
					homeZone[model] = findZone(r.Position.X, r.Position.Z) or false
				end
			end
		end)
		return
	end
	local p = root.Position
	-- Use `false` sentinel instead of nil so the key stays in the table.
	-- In Lua, t[key] = nil removes the key, which would make the monitor
	-- loop skip monsters that belong outside the safe zone.
	homeZone[model] = findZone(p.X, p.Z) or false
end

local function teleport(model, targetPos)
	local root = getRootPart(model)
	if not root then return end
	-- If the root part is a proper assembly root (PrimaryPart/HRP/Torso/Head),
	-- move it directly so welded assemblies follow. Otherwise use PivotTo
	-- so all parts in the model move together (e.g. bomb Monster model).
	local isProperRoot = root == model.PrimaryPart
		or root.Name == "HumanoidRootPart"
		or root.Name == "Torso"
		or root.Name == "Head"
	if isProperRoot then
		root.CFrame = CFrame.new(targetPos) * (root.CFrame - root.CFrame.Position)
	else
		local pivot = model:GetPivot()
		model:PivotTo(CFrame.new(targetPos) * (pivot - pivot.Position))
	end
end

-- Given a point inside a zone, return a point just outside the nearest edge.
local function pushOutside(x, z, zone)
	local dLeft = x - zone.minX
	local dRight = zone.maxX - x
	local dNear = z - zone.minZ
	local dFar = zone.maxZ - z
	local minD = math.min(dLeft, dRight, dNear, dFar)
	local push = 5
	if minD == dLeft then
		return Vector3.new(zone.minX - push, 0, z)
	elseif minD == dRight then
		return Vector3.new(zone.maxX + push, 0, z)
	elseif minD == dNear then
		return Vector3.new(x, 0, zone.minZ - push)
	else
		return Vector3.new(x, 0, zone.maxZ + push)
	end
end

-- Monitor loop: keep every monster on its home side of the safe zones.
task.spawn(function()
	while true do
		task.wait(0.3)
		for model, home in pairs(homeZone) do
			if model.Parent then
				local root = getRootPart(model)
				if root then
					local p = root.Position
					local zone = findZone(p.X, p.Z)
					if home then
						-- Belongs inside: if it left, teleport it back to its zone center.
						if not zone then
							teleport(model, Vector3.new(home.center.X, p.Y, home.center.Z))
						end
					else
						-- Belongs outside: if it entered, push it back out.
						if zone then
							local out = pushOutside(p.X, p.Z, zone)
							teleport(model, Vector3.new(out.X, p.Y, out.Z))
						end
					end
				end
			end
		end
	end
end)

-- Register monsters already in the world.
for _, desc in ipairs(workspace:GetDescendants()) do
	if desc:IsA("Model") and isMonster(desc) then
		registerMonster(desc)
	end
end

-- Register monsters spawned later.
workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") and isMonster(desc) then
		registerMonster(desc)
	end
end)

-- TeleportSystem
-- Attribute-owned one-way player routes. A matching string connects an
-- entrance to one or more exits regardless of Workspace folder hierarchy:
--   OneWayEntrance = "McDonalds"
--   OneWayExit = "McDonalds"

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TELEPORT_OFFSET = Vector3.new(0, 6, 0)
local CHARACTER_COOLDOWN = 1.5

local entrancesByRoute = {}
local exitsByRoute = {}
local chainedPortsByName = {}
local connectedEntrances = setmetatable({}, { __mode = "k" })
local connectedChainedPorts = setmetatable({}, { __mode = "k" })
local characterCooldowns = setmetatable({}, { __mode = "k" })
local warnedDuplicateRoutes = {}
local warnedMissingChainedDestinations = {}

local function routeAttribute(instance, attributeName)
	local value = instance:GetAttribute(attributeName)
	return typeof(value) == "string" and value ~= "" and value or nil
end

local function getPlayerCharacter(hit)
	local current = hit
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			local root = current:FindFirstChild("HumanoidRootPart")
			if player and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				return current, root
			end
		end
		current = current.Parent
	end
	return nil
end

local function setRouteLights(instance, brightness)
	local root = instance
	local model = instance:FindFirstAncestorOfClass("Model")
	if model then root = model end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("PointLight") then
			TweenService:Create(descendant, TweenInfo.new(0.2), { Brightness = brightness }):Play()
		end
	end
end

local function addRoutePart(registry, route, part)
	if not route or not part:IsA("BasePart") then return end
	local list = registry[route]
	if not list then
		list = {}
		registry[route] = list
	end
	for _, existing in ipairs(list) do
		if existing == part then return end
	end
	table.insert(list, part)
end

local function removeRoutePart(registry, part)
	for route, list in pairs(registry) do
		for index = #list, 1, -1 do
			if list[index] == part or not list[index].Parent then
				table.remove(list, index)
			end
		end
		if #list == 0 then registry[route] = nil end
	end
end

local function nearestExit(route, entrance)
	local exits = exitsByRoute[route]
	if not exits then return nil end
	local best, bestDistance
	for _, exit in ipairs(exits) do
		if exit.Parent then
			local distance = (exit.Position - entrance.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				best = exit
				bestDistance = distance
			end
		end
	end
	if #exits > 1 and not warnedDuplicateRoutes[route] then
		warnedDuplicateRoutes[route] = true
		warn("[TeleportSystem] multiple exits for route; using nearest:", route)
	end
	return best
end

local function connectEntrance(entrance, route)
	if connectedEntrances[entrance] then return end
	connectedEntrances[entrance] = true
	entrance.CanTouch = true
	entrance.CanQuery = true
	entrance.Touched:Connect(function(hit)
		local character, root = getPlayerCharacter(hit)
		if not character or characterCooldowns[character] then return end
		local exit = nearestExit(route, entrance)
		if not exit then
			warn("[TeleportSystem] no exit for route:", route, "entrance:", entrance:GetFullName())
			return
		end

		characterCooldowns[character] = true
		setRouteLights(entrance, 0)
		root.CFrame = exit.CFrame + TELEPORT_OFFSET
		task.delay(CHARACTER_COOLDOWN, function()
			characterCooldowns[character] = nil
			if entrance.Parent then setRouteLights(entrance, 10) end
		end)
	end)
end

local function addChainedPort(source, portName, destinationName, part)
	if not portName or not destinationName or not part:IsA("BasePart") then return end
	local list = chainedPortsByName[portName]
	if not list then
		list = {}
		chainedPortsByName[portName] = list
	end
	for _, existing in ipairs(list) do
		if existing.part == part then return end
	end
	table.insert(list, { part = part, destinationName = destinationName, source = source })
	if connectedChainedPorts[part] then return end
	connectedChainedPorts[part] = true
	part.CanTouch = true
	part.CanQuery = true
	part.Touched:Connect(function(hit)
		local character, root = getPlayerCharacter(hit)
		if not character or characterCooldowns[character] then return end
		local destinationList = chainedPortsByName[destinationName]
		local destination = destinationList and destinationList[1] and destinationList[1].part
		if not destination or not destination.Parent then
			local warningKey = source:GetFullName() .. "->" .. destinationName
			if not warnedMissingChainedDestinations[warningKey] then
				warnedMissingChainedDestinations[warningKey] = true
				warn("[TeleportSystem] missing chained destination:", destinationName, "from:", source:GetFullName())
			end
			return
		end
		characterCooldowns[character] = true
		root.CFrame = destination.CFrame + TELEPORT_OFFSET
		task.delay(CHARACTER_COOLDOWN, function()
			characterCooldowns[character] = nil
		end)
	end)
end

local function configureChainedPort(source, part)
	local portName = routeAttribute(source, "ChainedPort")
	local destinationName = routeAttribute(source, "ChainedPortTo")
	if portName and destinationName then
		addChainedPort(source, portName, destinationName, part)
	end
end

local function configureRoutePart(instance)
	local entranceRoute = routeAttribute(instance, "OneWayEntrance")
	if entranceRoute then
		addRoutePart(entrancesByRoute, entranceRoute, instance)
		connectEntrance(instance, entranceRoute)
	end
	local exitRoute = routeAttribute(instance, "OneWayExit")
	if exitRoute then
		addRoutePart(exitsByRoute, exitRoute, instance)
		instance.CanTouch = false
		instance.CanCollide = false
		instance.CanQuery = true
	end
end

local function representativePart(model)
	if model.PrimaryPart then return model.PrimaryPart end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function inspect(instance)
	if instance:IsA("BaseScript") and instance:IsDescendantOf(Workspace) then
		local folder = instance:FindFirstAncestor("TeleportParts")
		if folder then
			instance.Disabled = true
		end
		return
	end
	if instance:IsA("Model") then
		local part = representativePart(instance)
		if part then
			configureChainedPort(instance, part)
			local entranceRoute = routeAttribute(instance, "OneWayEntrance")
			local exitRoute = routeAttribute(instance, "OneWayExit")
			if entranceRoute then
				addRoutePart(entrancesByRoute, entranceRoute, part)
				connectEntrance(part, entranceRoute)
			end
			if exitRoute then
				addRoutePart(exitsByRoute, exitRoute, part)
				part.CanTouch = false
				part.CanCollide = false
				part.CanQuery = true
			end
		end
	elseif instance:IsA("BasePart") then
		configureChainedPort(instance, instance)
		configureRoutePart(instance)
	end
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	inspect(instance)
end

Workspace.DescendantAdded:Connect(function(instance)
	task.defer(inspect, instance)
end)

Workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("BasePart") then
		removeRoutePart(entrancesByRoute, instance)
		removeRoutePart(exitsByRoute, instance)
		for portName, list in pairs(chainedPortsByName) do
			for index = #list, 1, -1 do
				if list[index].part == instance or not list[index].part.Parent then
					table.remove(list, index)
				end
			end
			if #list == 0 then chainedPortsByName[portName] = nil end
		end
	end
end)

local entranceCount, exitCount = 0, 0
for _, list in pairs(entrancesByRoute) do entranceCount += #list end
for _, list in pairs(exitsByRoute) do exitCount += #list end
warn("[TeleportSystem] attribute routes ready; entrances:", entranceCount, "exits:", exitCount)

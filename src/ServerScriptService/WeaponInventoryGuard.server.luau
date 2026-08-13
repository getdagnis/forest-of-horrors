local Players = game:GetService("Players")

local UNIQUE_WEAPONS = {
	["MonsterGun"] = true,
	["MonsterBlaster"] = true,
	["Light Saber"] = true,
}

local savedWorldLocations = {}
local returning = {}

local function isUniqueWeapon(tool)
	return tool:IsA("Tool") and (UNIQUE_WEAPONS[tool.Name] or tool:GetAttribute("UniquePickupWeapon") == true)
end

local function rememberWorldLocation(tool)
	if isUniqueWeapon(tool) and tool:IsDescendantOf(workspace) and not savedWorldLocations[tool] then
		savedWorldLocations[tool] = { parent = tool.Parent, pivot = tool:GetPivot() }
	end
end

local function playerAlreadyHas(player, candidate)
	local function hasMatchingTool(container)
		if not container then return false end
		for _, item in container:GetChildren() do
			if item ~= candidate and item:IsA("Tool") and item.Name == candidate.Name then
				return true
			end
		end
		return false
	end

	return hasMatchingTool(player.Backpack) or hasMatchingTool(player.Character)
end

local function returnToWorld(tool)
	local location = savedWorldLocations[tool]
	if not location or not location.parent or not location.parent.Parent then return end
	returning[tool] = true
	tool.Parent = location.parent
	tool:PivotTo(location.pivot)
	task.defer(function() returning[tool] = nil end)
end

local function checkTool(player, tool)
	if returning[tool] or not isUniqueWeapon(tool) then return end
	if playerAlreadyHas(player, tool) then returnToWorld(tool) end
end

local function bindPlayer(player)
	player.Backpack.ChildAdded:Connect(function(tool)
		checkTool(player, tool)
	end)
	player.CharacterAdded:Connect(function(character)
		character.ChildAdded:Connect(function(tool)
			checkTool(player, tool)
		end)
	end)
end

for _, instance in workspace:GetDescendants() do rememberWorldLocation(instance) end
workspace.DescendantAdded:Connect(rememberWorldLocation)
Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do bindPlayer(player) end

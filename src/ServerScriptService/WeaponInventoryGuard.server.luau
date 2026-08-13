-- WeaponInventoryGuard
--
-- Roblox completes a Tool pickup by briefly moving the currently equipped Tool
-- to Backpack and equipping the pickup.  For unique weapons, keep the original
-- Tool instance, destroy only that incoming duplicate, and restore the held
-- Tool when the normal pickup sequence has finished.

local Players = game:GetService("Players")

local UNIQUE_WEAPONS = {
	["MonsterGun"] = true,
	["MonsterBlaster"] = true,
	["LightSaber"] = true,
}

local incumbentByPlayer = {}
local boundTools = {}

local function isUniqueWeapon(tool)
	return tool:IsA("Tool") and (UNIQUE_WEAPONS[tool.Name] or tool:GetAttribute("UniquePickupWeapon") == true)
end

local function getPlayerWeaponTable(player)
	local weapons = incumbentByPlayer[player]
	if not weapons then
		weapons = {}
		incumbentByPlayer[player] = weapons
	end
	return weapons
end

local function isHeldByPlayer(player, tool)
	return tool.Parent == player.Character or tool.Parent == player:FindFirstChild("Backpack")
end

local function restoreEquippedWeapon(player, tool)
	if not tool.Parent or tool.Parent ~= player:FindFirstChild("Backpack") then return end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
end

local function rejectIncomingDuplicate(player, incoming, incumbent)
	if incoming == incumbent or not incoming.Parent then return end
	incoming:Destroy()
	task.defer(restoreEquippedWeapon, player, incumbent)
end

local function resolveToolAdded(player, tool)
	if not isUniqueWeapon(tool) or not isHeldByPlayer(player, tool) then return end

	local weapons = getPlayerWeaponTable(player)
	local incumbent = weapons[tool.Name]
	if incumbent and incumbent ~= tool and isHeldByPlayer(player, incumbent) then
		rejectIncomingDuplicate(player, tool, incumbent)
		return
	end

	weapons[tool.Name] = tool
end

local function bindTool(player, tool)
	if not isUniqueWeapon(tool) or boundTools[tool] then return end
	boundTools[tool] = true

	tool.Equipped:Connect(function()
		local weapons = getPlayerWeaponTable(player)
		local incumbent = weapons[tool.Name]
		if incumbent and incumbent ~= tool and isHeldByPlayer(player, incumbent) then
			rejectIncomingDuplicate(player, tool, incumbent)
			return
		end
		weapons[tool.Name] = tool
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		local weapons = incumbentByPlayer[player]
		if weapons and weapons[tool.Name] == tool then
			weapons[tool.Name] = nil
		end
		boundTools[tool] = nil
	end)
end

local function observeTool(player, tool)
	if not isUniqueWeapon(tool) then return end
	bindTool(player, tool)
	-- Wait for Roblox's Character/Backpack transfer to settle before deciding.
	task.defer(resolveToolAdded, player, tool)
end

local function bindPlayer(player)
	local backpack = player:WaitForChild("Backpack")

	local function observeContainer(container)
		for _, tool in container:GetChildren() do
			observeTool(player, tool)
		end
		container.ChildAdded:Connect(function(tool)
			observeTool(player, tool)
		end)
	end

	local function bindCharacter(character)
		-- The Character is scanned first so a currently held Tool is always the
		-- incumbent if this Script starts during an existing Play session.
		for _, tool in character:GetChildren() do
			if isUniqueWeapon(tool) then
				bindTool(player, tool)
				getPlayerWeaponTable(player)[tool.Name] = tool
			end
		end
		character.ChildAdded:Connect(function(tool)
			observeTool(player, tool)
		end)
	end

	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
	observeContainer(backpack)
end

Players.PlayerAdded:Connect(bindPlayer)
Players.PlayerRemoving:Connect(function(player)
	incumbentByPlayer[player] = nil
end)

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end

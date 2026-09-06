-- WeaponInventoryGuard
--
-- Roblox completes a Tool pickup by briefly moving the currently equipped Tool
-- to Backpack and equipping the pickup.  For unique weapons, keep the original
-- Tool instance, destroy only that incoming duplicate, and restore the held
-- Tool when the normal pickup sequence has finished.

local Players = game:GetService("Players")

local UNIQUE_WEAPONS = {
	["MonsterGun"] = true,
	["MonsterGun2"] = true,
	["MonsterGun3"] = true,
	["MonsterBlaster"] = true,
	["LightSaber"] = true,
	["SpeedCoil"] = true,
}
local MONSTER_GUN_TIERS = {
	MonsterGun = 1,
	MonsterGun2 = 2,
	MonsterGun3 = 3,
}
local SPEED_COIL_DURATION_SECONDS = 60

local incumbentByPlayer = {}
local boundTools = {}
local equippedByPlayer = {}

local function isUniqueWeapon(tool)
	if not tool:IsA("Tool") then return false end
	local configuredName = tool:GetAttribute("WeaponName")
	return UNIQUE_WEAPONS[tool.Name]
		or (type(configuredName) == "string" and MONSTER_GUN_TIERS[configuredName] ~= nil)
		or tool:GetAttribute("UniquePickupWeapon") == true
end

local function getMonsterGunTier(tool)
	if not tool or not tool:IsA("Tool") then return nil end
	local weaponName = MONSTER_GUN_TIERS[tool.Name] and tool.Name or tool:GetAttribute("WeaponName")
	return MONSTER_GUN_TIERS[weaponName]
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

local function reconcileSpeedCoils(player)
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character
	local candidates = {}
	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, candidate in ipairs(container:GetChildren()) do
				if candidate:IsA("Tool") and candidate.Name == "SpeedCoil" then
					table.insert(candidates, candidate)
				end
			end
		end
	end
	if #candidates == 0 then return nil end

	local weapons = getPlayerWeaponTable(player)
	local keep = weapons.SpeedCoil
	if not keep or not table.find(candidates, keep) then
		keep = equippedByPlayer[player]
		if not keep or not table.find(candidates, keep) then
			keep = nil
			for _, candidate in ipairs(candidates) do
				if character and candidate.Parent == character then
					keep = candidate
					break
				end
			end
		end
		keep = keep or candidates[1]
	end

	local wasEquipped = equippedByPlayer[player] == keep or (character and keep.Parent == character)
	weapons.SpeedCoil = keep
	if wasEquipped then equippedByPlayer[player] = keep end

	if #candidates > 1 then
		keep:SetAttribute("SpeedCoilRemaining", SPEED_COIL_DURATION_SECONDS)
		local nonce = (tonumber(keep:GetAttribute("SpeedCoilRechargeNonce")) or 0) + 1
		keep:SetAttribute("SpeedCoilRechargeNonce", nonce)
		for _, candidate in ipairs(candidates) do
			if candidate ~= keep then candidate:Destroy() end
		end
		if wasEquipped and keep.Parent == backpack then
			task.delay(0.1, restoreEquippedWeapon, player, keep)
		end
	end
	return keep
end

local function rejectIncomingDuplicate(player, incoming, incumbent)
	if incoming == incumbent or not incoming.Parent then return end
	local wasEquipped = equippedByPlayer[player] == incumbent
	if not wasEquipped and player.Character and incumbent.Parent == player.Character then
		wasEquipped = true
	end
	if incoming.Name == "SpeedCoil" and incumbent.Name == "SpeedCoil" then
		incumbent:SetAttribute("SpeedCoilRemaining", SPEED_COIL_DURATION_SECONDS)
		local nonce = (tonumber(incumbent:GetAttribute("SpeedCoilRechargeNonce")) or 0) + 1
		incumbent:SetAttribute("SpeedCoilRechargeNonce", nonce)
		incoming:Destroy()
		-- A duplicate coil is a recharge, not a new equip. Only restore the
		-- incumbent when Roblox had actually been holding it before the pickup.
		if wasEquipped then
			task.delay(0.1, restoreEquippedWeapon, player, incumbent)
		end
		return
	end
	incoming:Destroy()
	if wasEquipped then
		task.delay(0.1, restoreEquippedWeapon, player, incumbent)
	end
end

local function copyToolProperty(target, source, propertyName)
	local ok, value = pcall(function() return source[propertyName] end)
	if ok then pcall(function() target[propertyName] = value end) end
end

local function promoteToolInPlace(target, incoming)
	-- Roblox's default hotbar has no public slot-index API. Keeping the original
	-- lower-tier Tool instance preserves its existing slot; replace its contents
	-- and identity in place instead of destroying that slot and appending a new
	-- Tool at the end of the bar.
	local preservedShootEvent = target:FindFirstChild("ShootEvent")
	for attributeName in pairs(target:GetAttributes()) do
		target:SetAttribute(attributeName, nil)
	end
	for attributeName, value in pairs(incoming:GetAttributes()) do
		target:SetAttribute(attributeName, value)
	end
	for _, propertyName in ipairs({ "CanBeDropped", "Enabled", "Grip", "ManualActivationOnly", "RequiresHandle", "ToolTip", "TextureId" }) do
		copyToolProperty(target, incoming, propertyName)
	end
	target.Name = incoming.Name
	target:SetAttribute("WeaponName", incoming.Name)
	for _, child in ipairs(target:GetChildren()) do
		if child ~= preservedShootEvent then child:Destroy() end
	end
	for _, child in ipairs(incoming:GetChildren()) do
		if child ~= incoming:FindFirstChild("ShootEvent") then
			child:Clone().Parent = target
		end
	end
	incoming:Destroy()
end

local function resolveToolAdded(player, tool)
	if not isUniqueWeapon(tool) or not isHeldByPlayer(player, tool) then return end
	if tool.Name == "SpeedCoil" then
		reconcileSpeedCoils(player)
		return
	end

	local weapons = getPlayerWeaponTable(player)
	local tier = getMonsterGunTier(tool)
	if tier then
		local incumbent
		local promotionTarget
		local lowerTierTools = {}
		for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
			if container then
				for _, candidate in ipairs(container:GetChildren()) do
					local candidateTier = getMonsterGunTier(candidate)
					if candidate ~= tool and candidateTier then
						if candidateTier >= tier then
							incumbent = candidate
							break
						end
						promotionTarget = promotionTarget or candidate
						table.insert(lowerTierTools, candidate)
					end
				end
			end
			if incumbent then break end
		end
		if incumbent then
			weapons.monsterGun = incumbent
			rejectIncomingDuplicate(player, tool, incumbent)
			return
		end
		if promotionTarget then
			local targetWasInBackpack = promotionTarget.Parent == player:FindFirstChild("Backpack")
			promoteToolInPlace(promotionTarget, tool)
			for _, lowerTierTool in ipairs(lowerTierTools) do
				if lowerTierTool ~= promotionTarget and lowerTierTool.Parent then lowerTierTool:Destroy() end
			end
			weapons.monsterGun = promotionTarget
			-- If the pickup had been equipped, re-equip the same instance so the
			-- higher tier immediately occupies the original lower-tier slot.
			if targetWasInBackpack then
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then humanoid:EquipTool(promotionTarget) end
			end
		else
			weapons.monsterGun = tool
		end
		return
	end

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
		if tool.Name == "SpeedCoil" then
			reconcileSpeedCoils(player)
			return
		end
		equippedByPlayer[player] = tool
		if getMonsterGunTier(tool) then
			resolveToolAdded(player, tool)
			return
		end
		local weapons = getPlayerWeaponTable(player)
		local incumbent = weapons[tool.Name]
		if incumbent and incumbent ~= tool and isHeldByPlayer(player, incumbent) then
			rejectIncomingDuplicate(player, tool, incumbent)
			return
		end
		weapons[tool.Name] = tool
	end)
	tool.Unequipped:Connect(function()
		if equippedByPlayer[player] == tool then
			equippedByPlayer[player] = nil
		end
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if not parent and equippedByPlayer[player] == tool then
			equippedByPlayer[player] = nil
		end
		if parent then return end
		local weapons = incumbentByPlayer[player]
		if weapons then
			if weapons[tool.Name] == tool then weapons[tool.Name] = nil end
			if weapons.monsterGun == tool then weapons.monsterGun = nil end
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
	equippedByPlayer[player] = nil
end)

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end

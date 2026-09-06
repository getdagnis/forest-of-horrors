-- MonsterGunUpgradeSystem
-- Round-score progression for the three MonsterGun tiers. This script promotes
-- the existing Tool in place so every tier stays in its original hotbar slot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local POINTS_PER_TIER = 100
local MG3_PROGRESS_BASELINE_ATTRIBUTE = "MonsterGun3ProgressBaseline"
local MG3_RESET_PENDING_ATTRIBUTE = "MonsterGun3ResetPending"
local TIER_NAMES = {
	[1] = "MonsterGun",
	[2] = "MonsterGun2",
	[3] = "MonsterGun3",
}

local LEGACY_TOOL_SCRIPTS = {
	ClientScript = true,
	Crosshair = true,
	WeaponCrosshairClient = true,
	MonsterGunClient = true,
	AnchorScript = true,
}

local templates = ServerStorage:WaitForChild("WeaponTemplates")

local function getOrCreateEvent(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if event and event:IsA("RemoteEvent") then return event end
	event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local unlockedEvent = getOrCreateEvent("MonsterGunUpgradeUnlocked")

local function getTier(tool)
	if not tool or not tool:IsA("Tool") then return nil end
	-- The visible Tool name is the identity we assign during promotion. Prefer it
	-- over a marketplace template's stale WeaponName attribute: otherwise an
	-- item named MonsterGun3 can be repeatedly mistaken for MG2 after swapping.
	local name = TIER_NAMES[1] == tool.Name or TIER_NAMES[2] == tool.Name or TIER_NAMES[3] == tool.Name
		and tool.Name or tool:GetAttribute("WeaponName")
	for tier, tierName in pairs(TIER_NAMES) do
		if name == tierName then return tier end
	end
	return nil
end

local function getHighestTier(player)
	local highest = 0
	for _, container in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				highest = math.max(highest, getTier(child) or 0)
			end
		end
	end
	return highest
end

local function prepareGun(tool)
	tool.CanBeDropped = false
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BaseScript") and LEGACY_TOOL_SCRIPTS[descendant.Name] then
			descendant.Disabled = true
		end
	end
end

local function findPromotionTarget(player, desiredTier)
	-- Prefer the held Tool, then the Backpack.  Mutating this original instance
	-- is what preserves its Roblox hotbar position (normally slot 1).
	for _, container in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if container then
			local bestCandidate
			local bestTier = 0
			for _, child in ipairs(container:GetChildren()) do
				local childTier = getTier(child)
				if childTier and childTier < desiredTier and childTier > bestTier then
					bestCandidate = child
					bestTier = childTier
				end
			end
			if bestCandidate then return bestCandidate end
		end
	end
	return nil
end

local function promoteToolInPlace(target, incoming)
	local preservedShootEvent = target:FindFirstChild("ShootEvent")
	for attributeName in pairs(target:GetAttributes()) do
		target:SetAttribute(attributeName, nil)
	end
	for attributeName, value in pairs(incoming:GetAttributes()) do
		target:SetAttribute(attributeName, value)
	end
	for _, propertyName in ipairs({ "CanBeDropped", "Enabled", "Grip", "ManualActivationOnly", "RequiresHandle", "ToolTip", "TextureId" }) do
		local ok, value = pcall(function() return incoming[propertyName] end)
		if ok then pcall(function() target[propertyName] = value end) end
	end
	target.Name = incoming.Name
	target:SetAttribute("WeaponName", incoming.Name)
	for _, child in ipairs(target:GetChildren()) do
		if child ~= preservedShootEvent then child:Destroy() end
	end
	for _, child in ipairs(incoming:GetChildren()) do
		if child ~= incoming:FindFirstChild("ShootEvent") then child:Clone().Parent = target end
	end
	incoming:Destroy()
end

local function grantTier(player, tier)
	local template = templates:FindFirstChild(TIER_NAMES[tier])
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not template or not template:IsA("Tool") or not backpack then
		warn("[MonsterGunUpgrade] missing template or Backpack for", player.Name, TIER_NAMES[tier])
		return false
	end

	local upgrade = template:Clone()
	prepareGun(upgrade)
	local promotionTarget = findPromotionTarget(player, tier)
	if promotionTarget then
		promoteToolInPlace(promotionTarget, upgrade)
	else
		upgrade.Parent = backpack
	end
	player:SetAttribute("MonsterGunTier", tier)
	if tier == 2 then
		player:SetAttribute(MG3_PROGRESS_BASELINE_ATTRIBUTE, POINTS_PER_TIER)
	else
		player:SetAttribute(MG3_PROGRESS_BASELINE_ATTRIBUTE, nil)
	end
	unlockedEvent:FireClient(player, tier)
	return true
end

local function refreshPlayer(player)
	local scoreValue = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Score")
	local score = scoreValue and scoreValue.Value or 0
	local detectedTier = getHighestTier(player)
	local savedTier = tonumber(player:GetAttribute("MonsterGunTier")) or 0
	if player:GetAttribute(MG3_RESET_PENDING_ATTRIBUTE) == true then
		-- CharacterAdded owns MG3's intentional one-life reset. Do not let an
		-- inventory transfer in the same spawn moment re-award it.
		return
	end
	if savedTier >= 3 and detectedTier < 3 then
		-- This is not the planned respawn reset. Repair a missing/corrupted MG3
		-- rather than silently dropping to MG1 and replaying both unlocks.
		grantTier(player, 3)
		return
	end
	-- MG2 is persistent across player respawns. If Roblox cleared the Tool
	-- instance before CharacterAdded finished, restore the tier from the saved
	-- attribute instead of allowing the temporary MG1 loadout to downgrade it.
	if savedTier == 2 and detectedTier < 2 then
		grantTier(player, 2)
		return
	end
	local tier = math.max(1, detectedTier)
	player:SetAttribute("MonsterGunTier", tier)

	if tier < 2 and score >= POINTS_PER_TIER then
		grantTier(player, 2)
	elseif tier < 3 then
		local baseline = tonumber(player:GetAttribute(MG3_PROGRESS_BASELINE_ATTRIBUTE)) or POINTS_PER_TIER
		if score >= baseline + POINTS_PER_TIER then
			grantTier(player, 3)
		end
	end
end

local function resetMG3AfterRespawn(player)
	local existingMG2
	for _, container in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if getTier(child) == 2 then existingMG2 = child end
			end
		end
	end

	local reset = player:GetAttribute(MG3_RESET_PENDING_ATTRIBUTE) == true
	for _, container in ipairs({ player.Character, player:FindFirstChildOfClass("Backpack") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if getTier(child) == 3 then
					if existingMG2 then
						child:Destroy()
					else
						local template = templates:FindFirstChild(TIER_NAMES[2])
						if template and template:IsA("Tool") then
							local downgrade = template:Clone()
							prepareGun(downgrade)
							-- Keep the exact same Tool instance and therefore the same hotbar
							-- slot, but restore MG2's contents for the new life.
							promoteToolInPlace(child, downgrade)
							existingMG2 = child
						end
					end
					reset = true
				end
			end
		end
	end
	if reset then
		if not existingMG2 then
			local template = templates:FindFirstChild(TIER_NAMES[2])
			local backpack = player:FindFirstChildOfClass("Backpack")
			if template and template:IsA("Tool") and backpack then
				local restored = template:Clone()
				prepareGun(restored)
				restored.Name = TIER_NAMES[2]
				restored:SetAttribute("WeaponName", TIER_NAMES[2])
				restored.Parent = backpack
			end
		end
		local score = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Score")
		-- Round score intentionally survives a death.  The next 100 points, not
		-- old score, therefore become the new MG3 requirement.
		player:SetAttribute(MG3_PROGRESS_BASELINE_ATTRIBUTE, score and score.Value or 0)
		player:SetAttribute("MonsterGunTier", 2)
		player:SetAttribute(MG3_RESET_PENDING_ATTRIBUTE, nil)
	end
end

local function bindPlayer(player)
	local leaderstats = player:WaitForChild("leaderstats")
	local score = leaderstats:WaitForChild("Score")
	local previousScore = score.Value
	score:GetPropertyChangedSignal("Value"):Connect(function()
		-- A new round resets Score but keeps the earned MG2.  Its MG3 meter must
		-- start from this round's normal 100-point MG2 threshold, not a prior
		-- life's score baseline.
		if score.Value < previousScore and getHighestTier(player) == 2 then
			player:SetAttribute(MG3_PROGRESS_BASELINE_ATTRIBUTE, POINTS_PER_TIER)
		end
		previousScore = score.Value
		refreshPlayer(player)
	end)

	local function watchContainer(container)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then task.defer(refreshPlayer, player) end
		end)
	end

	local backpack = player:WaitForChild("Backpack")
	watchContainer(backpack)
	player.CharacterRemoving:Connect(function()
		if (tonumber(player:GetAttribute("MonsterGunTier")) or 0) >= 3 then
			player:SetAttribute(MG3_RESET_PENDING_ATTRIBUTE, true)
		end
	end)
	player.CharacterAdded:Connect(function(character)
		watchContainer(character)
		task.defer(function()
			resetMG3AfterRespawn(player)
			refreshPlayer(player)
		end)
	end)
	if player.Character then watchContainer(player.Character) end
	task.defer(refreshPlayer, player)
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do bindPlayer(player) end

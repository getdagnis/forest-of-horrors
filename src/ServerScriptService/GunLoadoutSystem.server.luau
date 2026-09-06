-- GunLoadoutSystem
-- Gives each player one template-backed MonsterGun on every character spawn.
-- MG2 and MG3 remain opt-in: set GrantOnSpawn = true on their template when a
-- round should grant them instead of relying on a configured world spawn.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local DEFAULT_LOADOUT = { "MonsterGun"}
local OPTIONAL_LOADOUT = { "LightSaber", "MonsterGun2", "MonsterGun3", "MonsterBlaster" }
local MONSTER_GUN_TIERS = {
	MonsterGun = 1,
	MonsterGun2 = 2,
	MonsterGun3 = 3,
}
local MG3_RESET_PENDING_ATTRIBUTE = "MonsterGun3ResetPending"

local LEGACY_TOOL_SCRIPTS = {
	ClientScript = true,
	Crosshair = true,
	WeaponCrosshairClient = true,
	MonsterGunClient = true,
	AnchorScript = true,
}

local function playerHasNamedTool(player, toolName)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if container and container:FindFirstChild(toolName) then
			return true
		end
	end
	return false
end

local function getMonsterGunTier(tool)
	if not tool or not tool:IsA("Tool") then return nil end
	local weaponName = MONSTER_GUN_TIERS[tool.Name] and tool.Name or tool:GetAttribute("WeaponName")
	return MONSTER_GUN_TIERS[weaponName]
end

local function reconcileMonsterGunTier(player)
	local highestTier = tonumber(player:GetAttribute("MonsterGunTier")) or 0
	local guns = {}
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				local tier = getMonsterGunTier(child)
				if tier then
					highestTier = math.max(highestTier, tier)
					table.insert(guns, { tool = child, tier = tier })
				end
			end
		end
	end
	-- MG3 belongs to one life only. While the upgrade system is carrying out
	-- that intentional reset, do not use a saved/lingering MG3 to delete MG2.
	if player:GetAttribute(MG3_RESET_PENDING_ATTRIBUTE) == true then
		highestTier = math.min(highestTier, 2)
	end

	if highestTier > 1 then
		for _, entry in ipairs(guns) do
			if entry.tier < highestTier and entry.tool.Parent then
				entry.tool:Destroy()
			end
		end
		player:SetAttribute("MonsterGunTier", highestTier)
	end
	return highestTier
end

local function prepareGun(tool)
	tool.CanBeDropped = false
	for _, item in tool:GetDescendants() do
		if item:IsA("BaseScript") and LEGACY_TOOL_SCRIPTS[item.Name] then
			-- The StarterPlayerScripts controller is the only Gun client owner.
			item.Disabled = true
		end
	end
end

local function grantTemplate(player, templateName)
	if playerHasNamedTool(player, templateName) then return end
	local template = templates:FindFirstChild(templateName)
	if not template or not template:IsA("Tool") then
		warn("Missing Gun Tool template in ServerStorage.WeaponTemplates:", templateName)
		return
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end
	local tool = template:Clone()
	if templateName == "MonsterBlaster" then
		-- A respawn loadout is a continuation of the same weapon reserve, unlike
		-- a fresh world pickup which deliberately refills it.
		tool:SetAttribute("BlasterChargeFromLoadout", true)
	end
	prepareGun(tool)
	tool.Parent = backpack
end

local function grantLoadout(player)
	local highestGunTier = reconcileMonsterGunTier(player)
	-- Roblox may not carry the promoted Tool instance through CharacterAdded.
	-- Restore the saved tier directly so an earned MG2 never falls back to MG1.
	if player:GetAttribute(MG3_RESET_PENDING_ATTRIBUTE) == true then highestGunTier = math.min(highestGunTier, 2) end
	local primaryGun = highestGunTier == 2 and "MonsterGun2"
		or highestGunTier >= 3 and "MonsterGun3"
		or "MonsterGun"
	grantTemplate(player, primaryGun)

	for _, templateName in ipairs(OPTIONAL_LOADOUT) do
		local template = templates:FindFirstChild(templateName)
		if template and template:GetAttribute("GrantOnSpawn") == true then
			grantTemplate(player, templateName)
		end
	end
end

local function bindPlayer(player)
	player.CharacterAdded:Connect(function()
		-- Let Roblox finish moving surviving Tools before checking for a copy.
		task.defer(grantLoadout, player)
	end)
	if player.Character then
		task.defer(grantLoadout, player)
	end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do
	bindPlayer(player)
end

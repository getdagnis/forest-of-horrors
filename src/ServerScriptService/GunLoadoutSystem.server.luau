-- GunLoadoutSystem
-- Gives each player one template-backed MonsterGun on every character spawn.
-- MG2 and MG3 remain opt-in: set GrantOnSpawn = true on their template when a
-- round should grant them instead of relying on a configured world spawn.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local DEFAULT_LOADOUT = { "MonsterGun" }
local OPTIONAL_LOADOUT = { "MonsterGun2", "MonsterGun3" }

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
	prepareGun(tool)
	tool.Parent = backpack
end

local function grantLoadout(player)
	for _, templateName in ipairs(DEFAULT_LOADOUT) do
		grantTemplate(player, templateName)
	end

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

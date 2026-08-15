-- StarterPlayerScripts > WeaponTargetContour
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local GunAim = require(ReplicatedStorage:WaitForChild("GunAim"))
local MonsterBlasterConfig = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))

local WEAPON_COLORS = {
	MonsterGun = Color3.fromRGB(255, 105, 180),
	MonsterGun2 = Color3.fromRGB(255, 160, 225),
	MonsterGun3 = Color3.fromRGB(255, 230, 255),
	MonsterBlaster = Color3.fromRGB(62, 169, 255),
}

local highlight = Instance.new("Highlight")
highlight.Name = "LocalWeaponTargetContour"
highlight.FillTransparency = 0.88
highlight.OutlineTransparency = 0
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Enabled = false
highlight.Parent = workspace

local function getEquippedWeapon()
	local character = player.Character
	if not character then return nil end

	for _, item in character:GetChildren() do
		if item:IsA("Tool") and WEAPON_COLORS[item.Name] then
			return item
		end
	end
end

local function getMonsterModelFromHit(instance)
	local current = instance

	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			local humanoid = MonsterManager.getMonsterHumanoid(current)
			if humanoid and humanoid.Health > 0 then
				return current
			end
			return nil
		end
		current = current.Parent
	end
end

RunService.RenderStepped:Connect(function()
	local weapon = getEquippedWeapon()
	if not weapon then
		highlight.Enabled = false
		highlight.Adornee = nil
		return
	end
	if not GunAim.shouldShowAimHelpers(player) then
		highlight.Enabled = false
		highlight.Adornee = nil
		return
	end

	local range = weapon.Name == "MonsterBlaster" and MonsterBlasterConfig.RANGE or nil
	local monster = GunAim.getDirectTarget(player, weapon, nil, range)
	if monster then
		local color = WEAPON_COLORS[weapon.Name]
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.Adornee = monster
		highlight.Enabled = true
	else
		highlight.Enabled = false
		highlight.Adornee = nil
	end
end)

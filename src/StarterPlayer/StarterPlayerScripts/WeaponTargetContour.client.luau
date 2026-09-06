-- StarterPlayerScripts > WeaponTargetContour
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local GunAim = require(ReplicatedStorage:WaitForChild("GunAim"))
local AimConfig = require(ReplicatedStorage:WaitForChild("GunAimConfig"))
local MonsterBlasterConfig = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))
-- Guardian trust is optional to weapon targeting. Do not block the contour
-- loop if the guardian server script is disabled or still creating its remote.
local trustAimEvent = ReplicatedStorage:FindFirstChild("WMTGuardianTrustAim")

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

local lastContourUpdateAt = 0
local lastContourWeapon
local lastContourTarget
local lastTrustAimAt = 0
local lastTrustAimTarget
local TRUST_AIM_UPDATE_INTERVAL = 0.10

local function reportDirectContour(weapon, target)

	local now = os.clock()
	if weapon == lastContourWeapon and target == lastContourTarget
		and now - lastContourUpdateAt < AimConfig.ContourUpdateInterval then
		return
	end
	local event = ReplicatedStorage:FindFirstChild("WeaponContourTarget")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local ray = GunAim.getRay(player)
	if not event or not event:IsA("RemoteEvent") or not root or not ray then return end

	lastContourUpdateAt = now
	lastContourWeapon = weapon
	lastContourTarget = target
	event:FireServer(weapon, ray.Origin - root.Position, ray.Direction.Unit, target)
end

local function reportGuardianTrustAim(weapon, target)
	if target.Name ~= "weird monster thing" or target:GetAttribute("WMTGuardianPet") == true then return end
	if not trustAimEvent or not trustAimEvent.Parent then
		trustAimEvent = ReplicatedStorage:FindFirstChild("WMTGuardianTrustAim")
	end
	if not trustAimEvent or not trustAimEvent:IsA("RemoteEvent") then return end
	local now = os.clock()
	if target == lastTrustAimTarget and now - lastTrustAimAt < TRUST_AIM_UPDATE_INTERVAL then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local ray = GunAim.getRay(player)
	if not root or not ray then return end

	lastTrustAimAt = now
	lastTrustAimTarget = target
	-- The server re-casts this exact camera ray and owns every trust timer. This
	-- pulse exists only while the same direct, visible weapon contour is shown.
	trustAimEvent:FireServer(target, weapon, ray.Origin - root.Position, ray.Direction.Unit)
end

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
		lastContourWeapon = nil
		lastContourTarget = nil
		lastTrustAimTarget = nil
		return
	end
	-- Weapon-ready camera mode is centered for desktop, touch, and focus aim.

	local range = weapon.Name == "MonsterBlaster" and MonsterBlasterConfig.RANGE or nil
	local monster = GunAim.getDirectTarget(player, weapon, nil, range)
	if monster then
		local color = WEAPON_COLORS[weapon.Name]
		highlight.FillColor = color
		highlight.OutlineColor = color
		highlight.Adornee = monster
		highlight.Enabled = true
		reportDirectContour(weapon, monster)
		reportGuardianTrustAim(weapon, monster)
	else
		highlight.Enabled = false
		highlight.Adornee = nil
		lastContourTarget = nil
		lastTrustAimTarget = nil
	end
end)

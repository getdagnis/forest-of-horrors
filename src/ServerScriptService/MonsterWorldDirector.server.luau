-- MonsterWorldDirector: shared-world scene and player-threat authority.
-- Phase 1 deliberately observes and marks the world only. Family AI remains
-- the sole movement owner until its specific adapter is converted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterWorldConfig = require(ReplicatedStorage:WaitForChild("MonsterWorldConfig"))

local THREAT_MODE_ATTRIBUTE = "MonsterThreatMode"
local CENTER_ATTRIBUTE = "MonsterActivityCenter"
local CENTER_ID_ATTRIBUTE = "MonsterCenterId"
local CENTER_PROFILE_ATTRIBUTE = "MonsterCenterProfile"
local CENTER_RADIUS_ATTRIBUTE = "MonsterCenterRadius"

local function configurePlayer(player)
	local mode = MonsterWorldConfig.getThreatMode(player:GetAttribute(THREAT_MODE_ATTRIBUTE))
	player:SetAttribute(THREAT_MODE_ATTRIBUTE, mode)
end

local function describeCenters()
	local count = 0
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:GetAttribute(CENTER_ATTRIBUTE) == true then
			count += 1
			local id = instance:GetAttribute(CENTER_ID_ATTRIBUTE)
			local profile = instance:GetAttribute(CENTER_PROFILE_ATTRIBUTE)
			local radius = tonumber(instance:GetAttribute(CENTER_RADIUS_ATTRIBUTE))
			if type(id) ~= "string" or id == "" then
				warn("[MonsterWorld] centre missing MonsterCenterId:", instance:GetFullName())
			elseif profile ~= "Town" and profile ~= "Bastion" then
				warn("[MonsterWorld] centre " .. id .. " needs MonsterCenterProfile Town or Bastion")
			elseif not radius or radius <= 0 then
				warn("[MonsterWorld] centre " .. id .. " needs a positive MonsterCenterRadius")
			end
		end
	end
	Workspace:SetAttribute("MonsterActivityCenterCount", count)
	warn("[MonsterWorld] phase 1 active; marked activity centres:", count)
end

for _, player in ipairs(Players:GetPlayers()) do
	configurePlayer(player)
end
Players.PlayerAdded:Connect(configurePlayer)

describeCenters()
Workspace.DescendantAdded:Connect(function(instance)
	if instance:GetAttribute(CENTER_ATTRIBUTE) == true then
		describeCenters()
	end
end)

-- Future phases schedule scene intent here. This Script must never move a
-- monster, edit its physics, deal damage, retire it, or change its CFrame.

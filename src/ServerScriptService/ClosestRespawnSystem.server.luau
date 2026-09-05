-- ClosestRespawnSystem
-- After a player dies, let Roblox respawn them at the nearest enabled
-- SpawnLocation that they are eligible to use. Initial joins remain Roblox's
-- normal spawn selection.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function isEligibleSpawn(player, spawn)
	if not spawn.Enabled then return false end
	return spawn.Neutral or spawn.TeamColor == player.TeamColor
end

local function nearestEligibleSpawn(player, deathPosition)
	local nearest
	local nearestDistance = math.huge
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("SpawnLocation") and isEligibleSpawn(player, instance) then
			local distance = (instance.Position - deathPosition).Magnitude
			if distance < nearestDistance then
				nearest = instance
				nearestDistance = distance
			end
		end
	end
	return nearest
end

local function bindCharacter(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end

	humanoid.Died:Connect(function()
		local spawn = nearestEligibleSpawn(player, root.Position)
		-- Clearing the property falls back to Roblox's normal selection if no
		-- enabled spawn is available for this player.
		player.RespawnLocation = spawn
	end)
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)
	if player.Character then bindCharacter(player, player.Character) end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end

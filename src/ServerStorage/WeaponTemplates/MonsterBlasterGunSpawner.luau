-- MonsterBlaster world-pickup respawner.
-- This is a Tool Script: place it in the active MonsterBlaster as `GunSpawner`.

local Players = game:GetService("Players")

local tool = script.Parent
local RESPAWN_DELAY = 12

local spawnCFrame = tool:GetPivot()
local template = tool:Clone()
local originalParent = tool.Parent
local respawnScheduled = false

local function isPickedUp()
	local parent = tool.Parent
	return parent and (
		(parent:IsA("Backpack") and parent.Parent:IsA("Player"))
		or (parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) ~= nil)
	)
end

tool.AncestryChanged:Connect(function()
	if respawnScheduled or not isPickedUp() then return end

	-- WeaponInventoryGuard can reject a later duplicate on this same frame.
	-- Wait until that return has settled before declaring the pickup collected.
	task.defer(function()
		if respawnScheduled or not isPickedUp() then return end

		respawnScheduled = true
		task.delay(RESPAWN_DELAY, function()
			local replacement = template:Clone()
			replacement:PivotTo(spawnCFrame)
			replacement.Parent = originalParent
		end)
	end)
end)

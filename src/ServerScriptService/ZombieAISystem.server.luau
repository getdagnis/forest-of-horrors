local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local ZombieAI = require(ServerStorage:WaitForChild("ROBLOX_ZombieAI"))

local ZOMBIE_NAME = "Drooling Zombie"
local managed = {}

local function disableOldLocalZombieScript(model)
	local oldScript = model:FindFirstChild("Script")

	if oldScript and oldScript:IsA("Script") then
		oldScript.Enabled = false
		oldScript.Disabled = true
	end
end

local function setupZombie(model)
	if not model:IsA("Model") or model.Name ~= ZOMBIE_NAME then return end
	if managed[model] then return end
	if not model:FindFirstChildOfClass("Humanoid") then return end
	if not model:FindFirstChild("HumanoidRootPart") then return end
	if not model:FindFirstChild("Configurations") then return end

	managed[model] = true
	model:SetAttribute("CentralZombieAI", true)
	disableOldLocalZombieScript(model)
	ZombieAI.new(model)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			managed[model] = nil
		end
	end)
end

for _, item in Workspace:GetDescendants() do
	setupZombie(item)
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			setupZombie(item)
		end)
	end
end)

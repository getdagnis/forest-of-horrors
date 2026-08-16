-- RadarTowerSystem: activates map radar consoles marked in the live place.
-- Studio setup: set RadarTower=true on each tower Model (or its console Part)
-- and name the interactable BasePart RadarConsole.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local event = ReplicatedStorage:FindFirstChild("RadarTowerUse")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "RadarTowerUse"
	event.Parent = ReplicatedStorage
end

local activeConsoles = {}

local function isTower(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:GetAttribute("RadarTower") == true then return true end
		current = current.Parent
	end
	return false
end

local function findConsole(instance)
	if instance:IsA("BasePart") and instance.Name == "RadarConsole" then return instance end
	local console = instance:FindFirstChild("RadarConsole", true)
	return console and console:IsA("BasePart") and console or nil
end

local function setupTower(instance)
	if not isTower(instance) then return end
	local console = findConsole(instance)
	if not console or console:GetAttribute("RadarTowerBound") then return end
	console:SetAttribute("RadarTowerBound", true)

	local prompt = console:FindFirstChild("RadarTowerPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RadarTowerPrompt"
		prompt.ActionText = "Use radar"
		prompt.ObjectText = "Radar Tower"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.Parent = console
	end

	prompt.Triggered:Connect(function(player)
		activeConsoles[player] = console
		event:FireClient(player, true)
	end)
end

for _, instance in ipairs(Workspace:GetDescendants()) do setupTower(instance) end
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") or instance:IsA("BasePart") then
		task.defer(function() setupTower(instance) end)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		for player, console in pairs(activeConsoles) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not console.Parent or not root or (root.Position - console.Position).Magnitude > 12 then
				activeConsoles[player] = nil
				event:FireClient(player, false)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeConsoles[player] = nil
end)

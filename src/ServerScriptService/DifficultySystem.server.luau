-- DifficultySystem
-- The server owns the one-time per-player difficulty choice. The replicated
-- Player attributes are the contract consumed by health, loadout, and records.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEFAULT_DIFFICULTY = "Hard"
local difficultySelect = ReplicatedStorage:FindFirstChild("DifficultySelect")
if not difficultySelect then
	difficultySelect = Instance.new("RemoteEvent")
	difficultySelect.Name = "DifficultySelect"
	difficultySelect.Parent = ReplicatedStorage
end

local function initialize(player)
	if player:GetAttribute("Difficulty") == nil then
		player:SetAttribute("Difficulty", DEFAULT_DIFFICULTY)
	end
	if player:GetAttribute("DifficultySelectionLocked") == nil then
		player:SetAttribute("DifficultySelectionLocked", false)
	end
end

Players.PlayerAdded:Connect(initialize)
for _, player in Players:GetPlayers() do initialize(player) end

difficultySelect.OnServerEvent:Connect(function(player, requested)
	if player:GetAttribute("DifficultySelectionLocked") == true then return end
	if requested ~= "Easy" and requested ~= "Hard" then return end

	player:SetAttribute("Difficulty", requested)
	player:SetAttribute("DifficultySelectionLocked", true)
end)

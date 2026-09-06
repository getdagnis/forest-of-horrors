-- SpeedCoilPickupSystem
--
-- World coils are display models, never Tools. This script owns their prompt,
-- grants the one private Tool template, and recharges an existing coil.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local TEMPLATE_FOLDER = "WeaponTemplates"
local TOOL_NAME = "SpeedCoil"
local SPAWNER_NAME = "speed coil spawner"
local PICKUP_PART_NAME = "Handle"
local DURATION_SECONDS = 60
local DEFAULT_RESPAWN_SECONDS = 60

local template = ServerStorage:WaitForChild(TEMPLATE_FOLDER):WaitForChild(TOOL_NAME)
local pickupStates = {}

local function findOwnedCoil(player)
	local choices = {}
	for _, container in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child.Name == TOOL_NAME then
					table.insert(choices, child)
				end
			end
		end
	end
	if #choices == 0 then return nil end

	local keep = choices[1]
	for _, choice in ipairs(choices) do
		if player.Character and choice.Parent == player.Character then
			keep = choice
			break
		end
	end
	-- Clean up copies left by the former touch-Tool system.
	for _, choice in ipairs(choices) do
		if choice ~= keep then choice:Destroy() end
	end
	return keep
end

local function prepareHeldTool(tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	tool:SetAttribute("SpeedCoilRemaining", DURATION_SECONDS)
	tool:SetAttribute("SpeedCoilEquipped", false)
	return tool
end

local function playPickupSound(player)
	local handle = template:FindFirstChild("Handle")
	local source = handle and handle:FindFirstChild("Equip")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (source and source:IsA("Sound") and root) then return end
	local sound = source:Clone()
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 2) + 1)
end

local function grantOrRecharge(player)
	local coil = findOwnedCoil(player)
	if not coil then
		coil = prepareHeldTool(template:Clone())
		coil.Parent = player:WaitForChild("Backpack")
	else
		prepareHeldTool(coil)
		local nonce = (tonumber(coil:GetAttribute("SpeedCoilRechargeNonce")) or 0) + 1
		coil:SetAttribute("SpeedCoilRechargeNonce", nonce)
	end
	playPickupSound(player)
end

local function configurePickup(model)
	if not (model:IsA("Model") and model.Name == SPAWNER_NAME) then return end
	local handle = model:FindFirstChild(PICKUP_PART_NAME)
	if not handle or not handle:IsA("BasePart") then return end

	handle.Anchored = true
	handle.CanCollide = false
	handle.CanTouch = false

	local prompt = handle:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "SpeedCoilPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Speed Coil"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle

	local state = pickupStates[model]
	if state then return end
	state = { available = true, prompt = prompt, transparencies = {} }
	pickupStates[model] = state
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			state.transparencies[descendant] = descendant.Transparency
		end
	end

	local function setAvailable(available)
		state.available = available
		prompt.Enabled = available
		for part, transparency in pairs(state.transparencies) do
			if part.Parent then
				part.Transparency = available and transparency or 1
			end
		end
	end

	prompt.Triggered:Connect(function(player)
		if not state.available then return end
		setAvailable(false)
		grantOrRecharge(player)
		local respawnSeconds = tonumber(model:GetAttribute("SpeedCoilRespawnSeconds")) or DEFAULT_RESPAWN_SECONDS
		task.delay(math.max(1, respawnSeconds), function()
			if model.Parent then setAvailable(true) end
		end)
	end)
end

for _, child in ipairs(Workspace:GetChildren()) do
	configurePickup(child)
end

Workspace.ChildAdded:Connect(configurePickup)

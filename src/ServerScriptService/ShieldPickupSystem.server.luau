-- ShieldPickupSystem
-- Server-authoritative temporary player protection from a world Part named
-- "Shield". The part disappears when collected, returns after 30 seconds,
-- and each pickup grants or refreshes one 60-second ForceField.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SHIELD_PART_NAME = "Shield"
local SHIELD_DURATION_SECONDS = 60
local PICKUP_RESPAWN_SECONDS = 30
local FORCE_FIELD_NAME = "BonusShieldForceField"
local EXPIRES_AT_ATTRIBUTE = "ShieldExpiresAt"

local pickupStates = {}
local shieldTokens = {}

local function getPlayerFromHit(hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 then return nil end
	return player, character
end

local function getPickupState(pickup)
	local state = pickupStates[pickup]
	if state then return state end
	state = {
		available = true,
		parts = {},
		effects = {},
	}
	local descendants = pickup:GetDescendants()
	if pickup:IsA("BasePart") then table.insert(descendants, pickup) end
	for _, instance in ipairs(descendants) do
		if instance:IsA("BasePart") then
			state.parts[instance] = {
				transparency = instance.Transparency,
				canCollide = instance.CanCollide,
				canQuery = instance.CanQuery,
				canTouch = instance.CanTouch,
			}
		elseif instance:IsA("Light") or instance:IsA("ParticleEmitter") or instance:IsA("Trail")
			or instance:IsA("Beam") or instance:IsA("Fire") or instance:IsA("Smoke") or instance:IsA("Sparkles") then
			local ok, enabled = pcall(function() return instance.Enabled end)
			if ok then state.effects[instance] = enabled end
		end
	end
	pickupStates[pickup] = state
	return state
end

local function setPickupVisible(state, visible)
	for part, original in pairs(state.parts) do
		if part.Parent then
			part.Transparency = visible and original.transparency or 1
			part.CanCollide = visible and original.canCollide or false
			part.CanQuery = visible and original.canQuery or false
			part.CanTouch = visible and original.canTouch or false
		end
	end
	for effect, originallyEnabled in pairs(state.effects) do
		if effect.Parent then
			pcall(function() effect.Enabled = visible and originallyEnabled or false end)
		end
	end
end

local function playPickupSound(character)
	local source = SoundService:FindFirstChild("BonusShield", true)
	if not (source and source:IsA("Sound")) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local sound = source:Clone()
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 1)
end

local function clearShield(player, token)
	if shieldTokens[player] ~= token then return end
	shieldTokens[player] = nil
	player:SetAttribute(EXPIRES_AT_ATTRIBUTE, nil)
	local character = player.Character
	local field = character and character:FindFirstChild(FORCE_FIELD_NAME)
	if field then field:Destroy() end
end

local function grantShield(player, character)
	local previous = character:FindFirstChild(FORCE_FIELD_NAME)
	if previous then previous:Destroy() end

	local field = Instance.new("ForceField")
	field.Name = FORCE_FIELD_NAME
	field.Visible = true
	field.Parent = character

	local token = {}
	shieldTokens[player] = token
	player:SetAttribute(EXPIRES_AT_ATTRIBUTE, Workspace:GetServerTimeNow() + SHIELD_DURATION_SECONDS)
	playPickupSound(character)
	task.delay(SHIELD_DURATION_SECONDS, function()
		clearShield(player, token)
	end)
end

local function collectPickup(pickup, state, player, character)
	if not state.available then return end
	state.available = false
	setPickupVisible(state, false)
	grantShield(player, character)

	task.delay(PICKUP_RESPAWN_SECONDS, function()
		if not pickup.Parent then
			pickupStates[pickup] = nil
			return
		end
		state.available = true
		setPickupVisible(state, true)
	end)
end

local function isShieldPickup(instance)
	if not (instance:IsA("BasePart") or instance:IsA("Model")) then return false end
	-- Supports both a simple Part called Shield and the user's imported Shield
	-- Model, which is marked BonusShield in Studio.
	return instance.Name == SHIELD_PART_NAME
		or instance:GetAttribute("ShieldPickup") == true
		or instance:GetAttribute("BonusShield") == true
end

local function setupPickup(pickup)
	if not isShieldPickup(pickup) or pickupStates[pickup] then return end
	local state = getPickupState(pickup)
	for part in pairs(state.parts) do
		part.Touched:Connect(function(hit)
			if not state.available then return end
			local player, character = getPlayerFromHit(hit)
			if player and character then
				collectPickup(pickup, state, player, character)
			end
		end)
	end
end

local function resetPlayerShield(player)
	shieldTokens[player] = nil
	player:SetAttribute(EXPIRES_AT_ATTRIBUTE, nil)
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	setupPickup(instance)
end
Workspace.DescendantAdded:Connect(function(instance)
	task.defer(setupPickup, instance)
end)

local function setupPlayer(player)
	player.CharacterAdded:Connect(function()
		-- The shield belongs to the old character and must never survive death.
		resetPlayerShield(player)
	end)
	if player.Character then resetPlayerShield(player) end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	shieldTokens[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end

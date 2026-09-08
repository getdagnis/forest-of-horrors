-- HealthBonusPickupSystem
-- A world pickup that adds 100 current/max HP for the current character life.
-- The added health is deliberately not regenerated: damage stays damage.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local PICKUP_NAME = "HealthBonus"
local HEALTH_GAIN = 100
local RESPAWN_SECONDS = 60
local HEALTH_COLOR = Color3.fromRGB(80, 255, 80)

local pickupStates = {}
local healthBonusFlashEvent = ReplicatedStorage:FindFirstChild("HealthBonusFlash")
if not healthBonusFlashEvent then
	healthBonusFlashEvent = Instance.new("RemoteEvent")
	healthBonusFlashEvent.Name = "HealthBonusFlash"
	healthBonusFlashEvent.Parent = ReplicatedStorage
end

local function playerFromHit(hit)
	local character = hit and hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 then return nil end
	return player, character, humanoid
end

local function getParts(root)
	local parts = {}
	if root:IsA("BasePart") then table.insert(parts, root) end
	for _, instance in ipairs(root:GetDescendants()) do
		if instance:IsA("BasePart") then table.insert(parts, instance) end
	end
	return parts
end

local function captureState(pickup)
	local state = pickupStates[pickup]
	if state then return state end
	state = { available = true, parts = {}, effects = {} }
	for _, part in ipairs(getParts(pickup)) do
		state.parts[part] = {
			transparency = part.Transparency,
			canCollide = part.CanCollide,
			canQuery = part.CanQuery,
			canTouch = part.CanTouch,
		}
		for _, effect in ipairs(part:GetChildren()) do
			if effect:IsA("Light") or effect:IsA("ParticleEmitter") or effect:IsA("Trail")
				or effect:IsA("Beam") or effect:IsA("Fire") or effect:IsA("Smoke")
				or effect:IsA("Sparkles")
			then
				state.effects[effect] = effect.Enabled
			end
		end
	end
	pickupStates[pickup] = state
	return state
end

local function setVisible(state, visible)
	for part, original in pairs(state.parts) do
		if part.Parent then
			part.Transparency = visible and original.transparency or 1
			part.CanCollide = visible and original.canCollide or false
			part.CanQuery = visible and original.canQuery or false
			part.CanTouch = visible and original.canTouch or false
		end
	end
	for effect, originallyEnabled in pairs(state.effects) do
		if effect.Parent then effect.Enabled = visible and originallyEnabled or false end
	end
end

local function showGain(character, root)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthBonusGainGui"
	gui.Size = UDim2.fromOffset(180, 42)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	gui.Parent = character
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = HEALTH_COLOR
	label.TextStrokeTransparency = 0
	label.Text = "+100 HEALTH"
	label.Parent = gui
	Debris:AddItem(gui, 1.4)
end

local function playSound(character)
	local source = SoundService:FindFirstChild("BonusHealth", true)
	if not (source and source:IsA("Sound")) then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local sound = source:Clone()
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength, 3) + 1)
end

local temporaryHealthControllers = setmetatable({}, { __mode = "k" })

local function installTemporaryHealthCap(humanoid)
	local existing = temporaryHealthControllers[humanoid]
	if existing then return existing end
	local lastHealth = humanoid.Health
	local applyingBonus = false
	humanoid.HealthChanged:Connect(function(health)
		local temporary = math.max(0, humanoid:GetAttribute("TemporaryHealthBonusHP") or 0)
		if humanoid:GetAttribute("TemporaryHealthBonusApplying") then
			lastHealth = health
			return
		end
		local normalMax = math.max(1, humanoid.MaxHealth - temporary)
		if not applyingBonus and health > lastHealth and lastHealth > normalMax then
			-- Normal regeneration may heal to 100%, but not replenish lost bonus HP.
			applyingBonus = true
			humanoid.Health = lastHealth
			applyingBonus = false
			return
		end
		lastHealth = health
	end)
	local beginApplying = function()
		applyingBonus = true
		return function()
			lastHealth = humanoid.Health
			applyingBonus = false
		end
	end
	temporaryHealthControllers[humanoid] = beginApplying
	return beginApplying
end

local function collect(pickup, state, player, character, humanoid)
	if not state.available then return end
	local normalMax = 100
	local totalCap = normalMax + HEALTH_GAIN
	if humanoid.Health >= totalCap then return end

	state.available = false
	setVisible(state, false)
	local finishApplying = installTemporaryHealthCap(humanoid)()
	humanoid:SetAttribute("TemporaryHealthBonusApplying", true)
	local temporaryCapacity = HEALTH_GAIN
	humanoid:SetAttribute("TemporaryHealthBonusHP", temporaryCapacity)
	humanoid.MaxHealth = math.max(humanoid.MaxHealth, totalCap)
	local gained = math.min(HEALTH_GAIN, totalCap - humanoid.Health)
	humanoid.Health = math.min(totalCap, humanoid.Health + gained)
	humanoid:SetAttribute("TemporaryHealthBonusApplying", nil)
	finishApplying()
	showGain(character, humanoid.RootPart or character:FindFirstChild("HumanoidRootPart"), gained)
	playSound(character)
	healthBonusFlashEvent:FireClient(player)

	task.delay(RESPAWN_SECONDS, function()
		if not pickup.Parent then
			pickupStates[pickup] = nil
			return
		end
		state.available = true
		setVisible(state, true)
	end)
end

local function isHealthPickup(instance)
	return (instance:IsA("Model") or instance:IsA("Accessory") or instance:IsA("BasePart"))
		and (instance.Name == PICKUP_NAME
			or instance:GetAttribute("HealthPickup") == true
			or instance:GetAttribute("HealthBonus") == true)
end

local function setupPickup(pickup)
	if not isHealthPickup(pickup) or pickupStates[pickup] then return end
	local state = captureState(pickup)
	for part in pairs(state.parts) do
		part.Touched:Connect(function(hit)
			if not state.available then return end
			local player, character, humanoid = playerFromHit(hit)
			if player then collect(pickup, state, player, character, humanoid) end
		end)
	end
end

for _, instance in ipairs(Workspace:GetDescendants()) do setupPickup(instance) end
Workspace.DescendantAdded:Connect(function(instance) task.defer(setupPickup, instance) end)

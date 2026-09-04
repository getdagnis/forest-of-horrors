-- GuardianMonsterSystem > ServerScriptService

-- Server-owned Weird Monster Thing (WMT) rescue and guardian behaviour.
-- Place as ServerScriptService.GuardianMonsterSystem.  It intentionally does
-- not depend on MonsterSystem so rescue eligibility remains server-validated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local GUARDIAN_NAME = "weird monster thing"
local MONSTER_DAMAGE_COOLDOWN = 0.8
-- Unbonded WMTs only respond after a player actually takes damage. This keeps
-- them from turning every harmless nearby crowd into a permanent monster war.
local HELP_CALL_RANGE = 200
local HELP_CALL_CHANCE = 0.30
local HELP_RESPONSE_SECONDS = 6
local HELP_DEFENSE_RADIUS = 20
local HELP_ARRIVAL_DISTANCE = 12
local FOLLOW_DISTANCE = 7
local OFFER_DISTANCE = 15
local OFFER_TIMEOUT = 20
local THREAT_RADIUS = 15
local SAFE_RADIUS = 50
local PET_ATTACK_RANGE = 20
local PET_ATTACK_COOLDOWN = 0.8
local SHIELD_DURATION = 30
local SHIELD_COOLDOWN = 45
local UPDATE_INTERVAL = 0.25
local GUARDIAN_CORPSE_DISPLAY_TIME = 60 -- battlefield remains; guardians do not respawn here
-- Guardians are resilient living world actors: after escaping combat, they
-- recover a Bomb hit over roughly forty seconds rather than staying crippled.
local GUARDIAN_REGEN_DELAY = 8
local GUARDIAN_REGEN_PER_SECOND = 3

local function getOrCreateRemoteEvent(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if event and event:IsA("RemoteEvent") then
		return event
	end

	event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local rescueEvent = getOrCreateRemoteEvent("WMTRescueOffer")
local rescueResponseEvent = getOrCreateRemoteEvent("WMTRescueResponse")

local guardians = {}

local function getLivingPlayerRoot(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and root or nil
end

local function isGuardian(model)
	return model:IsA("Model") and model.Name == GUARDIAN_NAME
end

local function getRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function getMonsterFromHit(hit)
	local current = hit
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getLivingMonsterHumanoid(model)
	local humanoid = model and MonsterManager.getMonsterHumanoid(model)
	return humanoid and humanoid.Health > 0 and humanoid or nil
end

local function isEligibleMonster(model, guardian)
	return model and model ~= guardian and model.Name ~= GUARDIAN_NAME and getLivingMonsterHumanoid(model) ~= nil
end

local function disablePlayerDamage(model)
	-- Marketplace WMTs use this value; setting it to zero keeps unbonded WMTs
	-- harmless even when their legacy model script is present.
	local config = model:FindFirstChild("Configuration")
	local attackDamage = config and config:FindFirstChild("AttackDamage")
	if attackDamage and attackDamage:IsA("NumberValue") then
		attackDamage.Value = 0
	end
end

local function disableLegacyGuardianScript(model)
	for _, item in model:GetDescendants() do
		-- The marketplace WMT "NPC" script is a complete second AI owner.  It
		-- runs every heartbeat, assumes every target has HumanoidRootPart, and
		-- therefore throws continuously for BombMonster (which deliberately has
		-- only a body/PrimaryPart).  GuardianMonsterSystem now owns movement,
		-- player help, pet following, and monster damage, so all three legacy
		-- behaviour scripts must remain off for a registered WMT.
		if item:IsA("Script") and (
			item.Name == "NPC"
			or item.Name == "GuardianLegDamage"
			or item.Name == "Damage Script"
		) then
			item.Disabled = true
		end
	end
end

local function damageMonster(state, targetModel, amount, cooldown)
	if not isEligibleMonster(targetModel, state.model) then return end
	local targetHumanoid = MonsterManager.getMonsterHumanoid(targetModel)
	local now = os.clock()
	if now - (state.lastMonsterHit[targetHumanoid] or 0) < cooldown then return end

	state.lastMonsterHit[targetHumanoid] = now
	MonsterManager.damageMonsterTarget(targetModel, amount, state.model)
end

local function nearbyMonsters(position, radius, guardian)
	local results = {}
	for _, candidate in Workspace:GetDescendants() do
		if candidate:IsA("Model") and isEligibleMonster(candidate, guardian) then
			local root = getRoot(candidate)
			if root and (root.Position - position).Magnitude <= radius then
				table.insert(results, candidate)
			end
		end
	end
	return results
end

local function ownerIsAlive(state)
	local player = state.owner
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return player and character and humanoid and humanoid.Health > 0 and root and root or nil
end

local function setShield(state, enabled)
	local character = state.owner and state.owner.Character
	if not character then return end
	local forceField = character:FindFirstChild("WMTGuardianShield")
	if enabled then
		if not forceField then
			forceField = Instance.new("ForceField")
			forceField.Name = "WMTGuardianShield"
			forceField.Visible = true
			forceField.Parent = character
		end
	else
		if forceField then forceField:Destroy() end
	end
end

local function clearOffer(state)
	if state.offerConnection then
		state.offerConnection:Disconnect()
		state.offerConnection = nil
	end
	state.offerPlayer = nil
	state.offerDeadline = 0
	state.offerReady = false
	state.model:SetAttribute("WMTOfferReady", false)
end

local function restoreUnbonded(state)
	setShield(state, false)
	state.owner = nil
	state.mode = "unbonded"
	state.humanoid.WalkSpeed = state.unbondedWalkSpeed
	state.shieldEndsAt = 0
	state.shieldAvailableAt = 0
	state.helpPlayer = nil
	state.helpUntil = 0
	state.model:SetAttribute("WMTGuardianOwnerUserId", nil)
	state.model:SetAttribute("WMTGuardianPet", false)
end

local function acceptOffer(state, player)
	if state.mode ~= "offering" or state.offerPlayer ~= player then return end
	local root = ownerIsAlive({ owner = player })
	local guardianRoot = getRoot(state.model)
	if not root or not guardianRoot or not state.offerReady then return end
	if (guardianRoot.Position - root.Position).Magnitude > OFFER_DISTANCE then return end
	if #nearbyMonsters(root.Position, SAFE_RADIUS, state.model) > 0 then return end

	clearOffer(state)
	state.owner = player
	state.mode = "pet"
	state.humanoid.WalkSpeed = math.min(state.unbondedWalkSpeed, 8)
	state.humanoid.MaxHealth = 480
	-- Do not heal: if the WMT was rescued at low health it stays there.
	state.humanoid.Health = math.min(state.humanoid.Health, state.humanoid.MaxHealth)
	state.model:SetAttribute("WMTGuardianOwnerUserId", player.UserId)
	state.model:SetAttribute("WMTGuardianPet", true)
end

local function presentOffer(state, player)
	if state.offerUsed or state.mode ~= "unbonded" or not player then return end
	state.offerUsed = true
	state.mode = "offering"
	state.offerPlayer = player
	state.offerDeadline = os.clock() + OFFER_TIMEOUT
	state.offerReady = false
	state.model:SetAttribute("WMTOfferReady", false)
	state.offerConnection = rescueResponseEvent.OnServerEvent:Connect(function(sender, guardian, accepted)
		if sender ~= player or guardian ~= state.model or typeof(accepted) ~= "boolean" then return end
		if accepted then
			acceptOffer(state, sender)
		else
			clearOffer(state)
			state.mode = "declined"
		end
	end)
end

local function tryOfferFromAttacker(state, attacker)
	if state.offerUsed or state.mode ~= "unbonded" or not attacker then return end
	local humanoid = MonsterManager.getMonsterHumanoid(attacker)
	local attackerId = humanoid and humanoid:GetAttribute("LastAttackerId")
	local player = typeof(attackerId) == "number" and Players:GetPlayerByUserId(attackerId) or nil
	if player then presentOffer(state, player) end
end

local function recordAttacker(state, hit)
	local attacker = getMonsterFromHit(hit)
	if isEligibleMonster(attacker, state.model) then
		state.lastContactAttacker = attacker
		state.lastContactAt = os.clock()
	end
end

local function connectPart(state, part)
	if not part:IsA("BasePart") or state.parts[part] then return end
	state.parts[part] = true
	part.Touched:Connect(function(hit)
		local attacker = getMonsterFromHit(hit)
		if isEligibleMonster(attacker, state.model) then
			recordAttacker(state, hit)
			local playerRoot = getLivingPlayerRoot(state.helpPlayer)
			local attackerRoot = getRoot(attacker)
			if state.mode == "unbonded"
				and os.clock() < (state.helpUntil or 0)
				and playerRoot
				and attackerRoot
				and (attackerRoot.Position - playerRoot.Position).Magnitude <= HELP_DEFENSE_RADIUS
			then
				damageMonster(state, attacker, MonsterManager.getDamageToMonsters(state.model), MONSTER_DAMAGE_COOLDOWN)
			end
		end
	end)
end

local function updateGuardian(state)
	while state.model.Parent and state.humanoid.Parent and state.humanoid.Health > 0 do
		local now = os.clock()
		if now - state.lastDamagedAt >= GUARDIAN_REGEN_DELAY
			and state.humanoid.Health < state.humanoid.MaxHealth
		then
			state.humanoid.Health = math.min(
				state.humanoid.MaxHealth,
				state.humanoid.Health + GUARDIAN_REGEN_PER_SECOND * UPDATE_INTERVAL
			)
		end

		if state.mode == "unbonded" then
			local playerRoot = getLivingPlayerRoot(state.helpPlayer)
			if not playerRoot or now >= (state.helpUntil or 0) then
				state.helpPlayer = nil
				state.helpUntil = 0
			else
				local guardianRoot = getRoot(state.model)
				if guardianRoot and (guardianRoot.Position - playerRoot.Position).Magnitude > HELP_ARRIVAL_DISTANCE then
					state.humanoid:MoveTo(playerRoot.Position)
				end
			end
		elseif state.mode == "offering" then
			local guardianRoot = getRoot(state.model)
			local playerRoot = ownerIsAlive({ owner = state.offerPlayer })
			if not guardianRoot or not playerRoot or now >= state.offerDeadline then
				clearOffer(state)
				state.mode = "declined"
			elseif (guardianRoot.Position - playerRoot.Position).Magnitude > OFFER_DISTANCE then
				state.humanoid:MoveTo(playerRoot.Position)
			elseif #nearbyMonsters(playerRoot.Position, SAFE_RADIUS, state.model) == 0 then
				if not state.offerReady then
					state.offerReady = true
					state.model:SetAttribute("WMTOfferReady", true)
					rescueEvent:FireClient(state.offerPlayer, state.model, "This weird monster thing wants to become your pet")
				end
			end
		elseif state.mode == "pet" then
			local playerRoot = ownerIsAlive(state)
			local guardianRoot = getRoot(state.model)
			if not playerRoot or not guardianRoot then
				restoreUnbonded(state)
			else
				local threats = nearbyMonsters(playerRoot.Position, PET_ATTACK_RANGE, state.model)
				if #threats > 0 then
					local target = threats[1]
					local targetRoot = getRoot(target)
					if targetRoot then
						state.humanoid:MoveTo(targetRoot.Position)
						if (targetRoot.Position - guardianRoot.Position).Magnitude <= 5 then
							damageMonster(state, target, MonsterManager.getDamageToMonsters(state.model), PET_ATTACK_COOLDOWN)
						end
					end
				elseif (guardianRoot.Position - playerRoot.Position).Magnitude > FOLLOW_DISTANCE then
					state.humanoid:MoveTo(playerRoot.Position)
				end

				if now >= state.shieldEndsAt and state.shieldEndsAt > 0 then
					setShield(state, false)
					state.shieldEndsAt = 0
					state.shieldAvailableAt = now + SHIELD_COOLDOWN
				end
				if now >= state.shieldAvailableAt and #nearbyMonsters(playerRoot.Position, THREAT_RADIUS, state.model) >= 3 then
					if math.random() <= 0.40 then
						setShield(state, true)
						state.shieldEndsAt = now + SHIELD_DURATION
					else
						state.shieldAvailableAt = now + 2
					end
				end
			end
		end
		task.wait(UPDATE_INTERVAL)
	end

	clearOffer(state)
	setShield(state, false)
	for _, connection in pairs(state.attackerDeaths) do
		connection:Disconnect()
	end
	guardians[state.model] = nil
end

local function setupGuardian(model)
	if not isGuardian(model) or guardians[model] then return end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	local root = getRoot(model)
	if not humanoid or not root then return end

	-- Guardians deliberately stay outside the round ledger, so MonsterSystem
	-- never reaches MonsterManager.applyHP for them. Their own owner must apply
	-- the intended 320 HP at registration.
	MonsterManager.applyHP(model)
	disablePlayerDamage(model)
	disableLegacyGuardianScript(model)
	local state = {
		model = model,
		humanoid = humanoid,
		mode = "unbonded",
		parts = {},
		lastMonsterHit = {},
		helpPlayer = nil,
		helpUntil = 0,
		offerUsed = false,
		shieldAvailableAt = 0,
		unbondedWalkSpeed = humanoid.WalkSpeed,
		lastDamagedAt = os.clock(),
	}
	guardians[model] = state
	model:SetAttribute("WMTGuardianPet", false)

	for _, item in model:GetDescendants() do connectPart(state, item) end
	model.DescendantAdded:Connect(function(item) task.defer(connectPart, state, item) end)

	-- A rescue is valid only if a monster that physically contacted this WMT
	-- later dies and the authoritative damage ledger identifies the player.
	humanoid.HealthChanged:Connect(function(health)
		if health >= state.lastHealth then state.lastHealth = health return end
		state.lastHealth = health
		state.lastDamagedAt = os.clock()
		local attacker = state.lastContactAttacker
		if attacker and os.clock() - (state.lastContactAt or 0) <= 5 then
			local attackerHumanoid = MonsterManager.getMonsterHumanoid(attacker)
			if attackerHumanoid and not state.attackerDeaths[attackerHumanoid] then
				state.attackerDeaths[attackerHumanoid] = attackerHumanoid.Died:Connect(function()
					tryOfferFromAttacker(state, attacker)
				end)
			end
		end
	end)
	state.lastHealth = humanoid.Health
	state.attackerDeaths = {}
	humanoid.Died:Connect(function()
		-- Guardians are intentionally outside MonsterSystem's respawn ledger.
		-- Keep the defeated body as battlefield evidence for a bounded duration,
		-- then remove it so dead guardians cannot accumulate forever.
		task.delay(GUARDIAN_CORPSE_DISPLAY_TIME, function()
			if model.Parent and humanoid.Health <= 0 then
				model:Destroy()
			end
		end)
	end)
	task.spawn(updateGuardian, state)
end

for _, item in Workspace:GetDescendants() do
	if item:IsA("Model") then setupGuardian(item) end
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then task.defer(setupGuardian, item) end
end)

local function callForHelp(player)
	local playerRoot = getLivingPlayerRoot(player)
	if not playerRoot then return end
	local now = os.clock()
	for _, state in pairs(guardians) do
		if state.mode == "unbonded" then
			local guardianRoot = getRoot(state.model)
			if guardianRoot
				and (guardianRoot.Position - playerRoot.Position).Magnitude <= HELP_CALL_RANGE
				and math.random() <= HELP_CALL_CHANCE
			then
				state.helpPlayer = player
				state.helpUntil = now + HELP_RESPONSE_SECONDS
			end
		end
	end
end

local function monitorPlayerHealth(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local previousHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < previousHealth and previousHealth > 0 then
			callForHelp(player)
		end
		previousHealth = health
	end)
end

local function observePlayer(player)
	if player.Character then monitorPlayerHealth(player, player.Character) end
	player.CharacterAdded:Connect(function(character)
		monitorPlayerHealth(player, character)
	end)
end

for _, player in Players:GetPlayers() do observePlayer(player) end
Players.PlayerAdded:Connect(observePlayer)

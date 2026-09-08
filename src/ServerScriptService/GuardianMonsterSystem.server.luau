-- GuardianMonsterSystem > ServerScriptService

-- Server-owned Weird Monster Thing (WMT) rescue and guardian behaviour.
-- Place as ServerScriptService.GuardianMonsterSystem.  It intentionally does
-- not depend on MonsterSystem so rescue eligibility remains server-validated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Tactics = require(script.Parent:WaitForChild("GuardianTactics"))
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local AimConfig = require(ReplicatedStorage:WaitForChild("GunAimConfig"))

local GUARDIAN_NAME = "weird monster thing"
local MONSTER_DAMAGE_COOLDOWN = 0.8
-- Unbonded WMTs respond when danger enters a player's immediate space, not
-- after the player's fragile character has already lost health.
local HELP_CALL_RANGE = 200
local HELP_CALL_CHANCE = 0.30
local HELP_RESPONSE_SECONDS = 6
local HELP_DEFENSE_RADIUS = 30
local HELP_ARRIVAL_DISTANCE = 12
local HELP_THREAT_RADIUS = 26
local HELP_THREAT_CHECK_INTERVAL = 1
local PET_FOLLOW_TARGET_DISTANCE = 32
local PET_FOLLOW_WALK_SPEED = 10
local PET_MAX_HEALTH = 800
local OFFER_DISTANCE = 15
local OFFER_MIN_PROGRESS = 5
local OFFER_TIMEOUT = 20
local OFFER_RESPONSE_SECONDS = 15
-- Follow MonsterRadar's close-range behaviour, but never let distant search
-- tiers beyond 70 studs prevent the deliberately discoverable pet offer.
local OFFER_RADAR_CLOSE_RANGE = 50
local OFFER_RADAR_CROWD_RANGE = 30
local OFFER_RADAR_NORMAL_RANGE = 50
local OFFER_RADAR_SEARCH_RANGES = { 50, 70 }
local OFFER_RADAR_CROWD_COUNT = 10
local THREAT_RADIUS = 15
local PET_RETALIATION_SECONDS = 12
local PET_COMBAT_ROAR_COOLDOWN = 4.5
local PET_AMBIENT_ROAR_SECONDS = 60
local GANG_JOIN_RADIUS = 75
local GANG_JOIN_CHANCE = 0.70
local GANG_DURATION = 120
local GANG_COOLDOWN = 180
local GANG_INVITATION_RETRY_SECONDS = 30
local GANG_INVITATION_INTERVAL = 4
local OFFER_PROMPT_DELAY = 4
local SHIELD_DURATION = 30
local SHIELD_COOLDOWN = 45
local UPDATE_INTERVAL = 0.25
local GUARDIAN_CORPSE_DISPLAY_TIME = 60 -- battlefield remains; guardians do not respawn here
-- Guardians are resilient living world actors: after escaping combat, they
-- recover a Bomb hit over roughly forty seconds rather than staying crippled.
local GUARDIAN_REGEN_DELAY = 8
local GUARDIAN_REGEN_PER_SECOND = 3
local GUARDIAN_HURT_SOUND_INTERVAL = 3

-- Killing two WMTs in one minute provokes the nearby guardian group. The
-- hostility is specific to the killer and persists for those guardians' lives.
local GUARDIAN_KILLS_TO_PROVOKE = 2 -- two is intended, don't change
local GUARDIAN_KILL_WINDOW_SECONDS = 60
local GUARDIAN_PROVOCATION_RADIUS = 200
-- They are angry but still WMTs: an ominous walk, not a sprinting chase.
local GUARDIAN_HOSTILE_WALK_SPEED = 12
local GUARDIAN_HOSTILE_ATTACK_RANGE = 6
local GUARDIAN_HOSTILE_ATTACK_COOLDOWN = 1

-- A pet is earned through one simple, readable action: keep the weapon ray on
-- an unharmed WMT through a brief silent consideration, then ten visible
-- seconds. Do not add a battle/proximity prerequisite; those hidden gates made
-- the offer effectively impossible to discover.
local TRUST_AIM_SECONDS = 10
-- The guardian first considers the player in silence. Only after this brief
-- beat does the visible ten-second conversation begin.
local TRUST_CONVERSATION_DELAY_SECONDS = 3
-- Wandering WMT movement must not erase almost-complete deliberate aim.
local TRUST_AIM_GRACE_SECONDS = 1.5
local TRUST_RAY_RANGE = 400
local TRUST_AIM_WEAPONS = {
	MonsterGun = true,
	MonsterGun2 = true,
	MonsterGun3 = true,
	MonsterBlaster = true,
}

local PET_BODY_COLOR = Color3.fromRGB(44, 69, 67) -- Earth green
local PET_OUTLINE_COLOR = Color3.fromRGB(190, 255, 75) -- soft lemon green
local PET_OUTLINE_TRANSPARENCY = 0.3

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
local rescueResultEvent = getOrCreateRemoteEvent("WMTRescueResult")
local trustAimEvent = getOrCreateRemoteEvent("WMTGuardianTrustAim")
local petLostEvent = getOrCreateRemoteEvent("WMTGuardianPetLost")
-- Presentation only. The server remains the sole owner of trust progress and
-- the decision to offer a bond.
local conversationEvent = getOrCreateRemoteEvent("WMTGuardianConversation")
local statusEvent = getOrCreateRemoteEvent("WMTGuardianStatus")

local guardians = {}
local guardianKillTimes = {}
local playerThreatActive = {}

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

local function playGuardianSound(model, soundName, fallbackSoundName)
	local source = SoundService:FindFirstChild(soundName)
	if not (source and source:IsA("Sound")) and fallbackSoundName then
		source = SoundService:FindFirstChild(fallbackSoundName)
	end
	if not (source and source:IsA("Sound")) then return false end

	-- The SoundService child is a template. A clone on the guardian makes the
	-- roar/death sound positional and keeps the shared source ready for later use.
	local sound = source:Clone()
	sound.Looped = false
	sound.TimePosition = 0
	sound.Parent = getRoot(model) or SoundService
	sound:Play()
	Debris:AddItem(sound, 10)
	return true
end

local function playPetRoar(state, now, minimumInterval)
	now = now or os.clock()
	if now - (state.lastRoarAt or -math.huge) < (minimumInterval or 0) then return false end
	state.lastRoarAt = now
	return playGuardianSound(state.model, "GuardianRoar")
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
	-- A guardian must never attack a BombMonster: its response is an explosion,
	-- not a normal duel, and an accidental pet-triggered blast would punish the
	-- owner rather than protect them.
	return model
		and model ~= guardian
		and model.Name ~= GUARDIAN_NAME
		and model.Name ~= "BombMonster"
		and MonsterManager.isRoundTracked(model)
		and getLivingMonsterHumanoid(model) ~= nil
end

local function getPetStandOffDestination(playerRoot, guardianRoot)
	local offset = guardianRoot.Position - playerRoot.Position
	offset = Vector3.new(offset.X, 0, offset.Z)
	if offset.Magnitude < 0.01 then
		offset = Vector3.new(playerRoot.CFrame.LookVector.X, 0, playerRoot.CFrame.LookVector.Z)
	end
	if offset.Magnitude < 0.01 then
		offset = Vector3.zAxis
	end
	return playerRoot.Position + offset.Unit * PET_FOLLOW_TARGET_DISTANCE
end

local function setPetAppearance(state, enabled)
	local humanoid = state.humanoid
	if enabled then
		for _, item in state.model:GetDescendants() do
			if item:IsA("BasePart") then
				if state.originalPartColors[item] == nil then
					state.originalPartColors[item] = item.Color
				end
				item.Color = PET_BODY_COLOR
			end
		end

		local outline = state.model:FindFirstChild("WMTGuardianPetOutline")
		if not outline then
			outline = Instance.new("Highlight")
			outline.Name = "WMTGuardianPetOutline"
			outline.Adornee = state.model
			outline.FillTransparency = 1
			outline.OutlineColor = PET_OUTLINE_COLOR
			outline.OutlineTransparency = PET_OUTLINE_TRANSPARENCY
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.Parent = state.model
		end
		outline.Enabled = true
		humanoid.DisplayName = "your guardian pet"
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		humanoid.NameDisplayDistance = 100
		return
	end

	for part, originalColor in pairs(state.originalPartColors) do
		if part.Parent then
			part.Color = originalColor
		end
	end
	local outline = state.model:FindFirstChild("WMTGuardianPetOutline")
	if outline then outline:Destroy() end
	humanoid.DisplayName = state.unbondedDisplayName
	humanoid.DisplayDistanceType = state.unbondedDisplayDistanceType
	humanoid.NameDisplayDistance = state.unbondedNameDisplayDistance
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

-- This is deliberately pet-only. Unbonded WMTs retain their authored calm
-- behaviour; an accepted pet alone is prepared to follow through its Humanoid.
local function preparePetMovement(model, humanoid, root)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = false
		end
	end
	humanoid.AutoRotate = true
	humanoid.PlatformStand = false
	humanoid.Sit = false
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end

local function resetPetPath(state)
	Tactics.reset(state)
end

local function damageMonster(state, targetModel, amount, cooldown)
	if not isEligibleMonster(targetModel, state.model) then return 0 end
	local targetHumanoid = MonsterManager.getMonsterHumanoid(targetModel)
	local now = os.clock()
	if now - (state.lastMonsterHit[targetHumanoid] or -math.huge) < cooldown then return 0 end

	state.lastMonsterHit[targetHumanoid] = now
	local actualDamage = MonsterManager.damageMonsterTarget(targetModel, amount, state.model)
	if state.mode == "pet" or state.mode == "gang" then
		-- The target's own family AI decides whether and how to retaliate. This
		-- marker grants a short response window without making GuardianMonsterSystem
		-- a second movement owner for zombies or creepy monsters.
		local marker = targetModel:FindFirstChild("WMTGuardianPetRetaliationTarget")
		if not marker then
			marker = Instance.new("ObjectValue")
			marker.Name = "WMTGuardianPetRetaliationTarget"
			marker.Parent = targetModel
		end
		marker.Value = state.model
		targetModel:SetAttribute("WMTGuardianPetRetaliationUntil", Workspace:GetServerTimeNow() + PET_RETALIATION_SECONDS)
		if actualDamage > 0 then
			playPetRoar(state, now, PET_COMBAT_ROAR_COOLDOWN)
		end
	end
	return actualDamage
end

-- Share one bounded perception snapshot across pets, gangs and the existing trust checks.
local monsterSnapshot = {}
local nextMonsterSnapshotAt = 0
local function nearbyMonsters(position, radius, guardian)
	local nearby = {}
	local now = os.clock()
	if now >= nextMonsterSnapshotAt then
		nextMonsterSnapshotAt = now + 0.5
		table.clear(monsterSnapshot)
		for _, candidate in Workspace:GetDescendants() do
			if candidate:IsA("Model") and MonsterManager.getConfig(candidate) then
				table.insert(monsterSnapshot, candidate)
			end
		end
	end
	for _, candidate in ipairs(monsterSnapshot) do
		if candidate.Parent and isEligibleMonster(candidate, guardian) then
			local root = getRoot(candidate)
			local distance = root and (root.Position - position).Magnitude or math.huge
			if distance <= radius then
				table.insert(nearby, { model = candidate, distance = distance })
			end
		end
	end
	table.sort(nearby, function(a, b) return a.distance < b.distance end)
	local results = {}
	for _, entry in ipairs(nearby) do table.insert(results, entry.model) end
	return results
end

local function releaseGangMember(state, now)
	state.humanoid.WalkSpeed = state.unbondedWalkSpeed
	state.gangSlot = nil
	state.model:SetAttribute("WMTGuardianGangLeader", nil)
	state.mode = "unbonded"
	state.gangLeader = nil
	state.gangUntil = 0
	state.gangCooldownUntil = now + GANG_COOLDOWN
	state.helpPlayer = nil
	state.helpUntil = 0
	state.combatTarget = nil
	resetPetPath(state)
end

local function inviteNearbyGuardians(leader, now)
	if now - (leader.lastGangInvitationAt or -math.huge) < GANG_INVITATION_INTERVAL then return end
	local leaderRoot = getRoot(leader.model)
	if not leaderRoot then return end
	leader.lastGangInvitationAt = now
	local usedSlots = {}
	local joined = 0
	for _, member in pairs(guardians) do
		if member.mode == "gang" and member.gangLeader == leader and member.humanoid.Health > 0
			and now < (member.gangUntil or 0) then usedSlots[member.gangSlot or 1] = true end
	end

	for _, candidate in pairs(guardians) do
		local candidateRoot = getRoot(candidate.model)
		local busy = now < (candidate.helpUntil or 0) and getLivingPlayerRoot(candidate.helpPlayer) ~= nil
		for player, record in pairs(candidate.trust) do
			if player.Parent and (record.talking or now - (record.lastAimAt or -math.huge) <= TRUST_AIM_GRACE_SECONDS) then
				busy = true
				break
			end
		end
		if candidate ~= leader
			and candidate.mode == "unbonded"
			and not busy -- Never steal an active conversation or ordinary help response.
			and candidate.humanoid.Health > 0
			and candidateRoot
			and now >= (candidate.gangCooldownUntil or 0)
			and now >= (candidate.gangInvitationUntil or 0)
			and (candidateRoot.Position - leaderRoot.Position).Magnitude <= GANG_JOIN_RADIUS
		then
			local slot
			for index = 1, Tactics.Config.GangLimit do
				if not usedSlots[index] then slot = index; break end
			end
			if not slot then break end
			if math.random() <= GANG_JOIN_CHANCE then
				usedSlots[slot] = true
				joined += 1
				candidate.gangSlot = slot
				candidate.model:SetAttribute("WMTGuardianGangLeader", leader.owner.UserId)
				preparePetMovement(candidate.model, candidate.humanoid, candidateRoot)
				candidate.mode = "gang"
				candidate.gangLeader = leader
				candidate.gangUntil = now + GANG_DURATION
				candidate.helpPlayer = nil
				candidate.helpUntil = 0
				candidate.combatTarget = nil
				resetPetPath(candidate)
			else
				-- A decline remains meaningful for a little while instead of becoming
				-- a random roll every guardian update.
				candidate.gangInvitationUntil = now + GANG_INVITATION_RETRY_SECONDS
			end
		end
	end
	return joined
end

local function horizontalDistance(first, second)
	local offset = first - second
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

local function getOfferRadarRange(playerPosition)
	local hostileDistances = {}
	local closeCount = 0
	for _, candidate in Workspace:GetDescendants() do
		if candidate:IsA("Model") and MonsterManager.isRoundTracked(candidate) then
			local root = getRoot(candidate)
			if root and getLivingMonsterHumanoid(candidate) then
				local distance = horizontalDistance(root.Position, playerPosition)
				table.insert(hostileDistances, distance)
				if distance <= OFFER_RADAR_CLOSE_RANGE then closeCount += 1 end
			end
		end
	end

	if closeCount >= OFFER_RADAR_CROWD_COUNT then return OFFER_RADAR_CROWD_RANGE end
	if closeCount > 0 then return OFFER_RADAR_NORMAL_RANGE end
	for _, searchRange in ipairs(OFFER_RADAR_SEARCH_RANGES) do
		for _, distance in ipairs(hostileDistances) do
			if distance <= searchRange then return searchRange end
		end
	end
	return OFFER_RADAR_SEARCH_RANGES[#OFFER_RADAR_SEARCH_RANGES]
end

local function hasHostileMonsterNearby(position, radius, guardian)
	for _, candidate in Workspace:GetDescendants() do
		if candidate:IsA("Model") and candidate ~= guardian then
			local hostile = false
			if candidate.Name == GUARDIAN_NAME then
				local candidateState = guardians[candidate]
				hostile = candidateState ~= nil and candidateState.mode == "hostile"
			elseif candidate.Name ~= "BombMonster" then
				hostile = MonsterManager.isRoundTracked(candidate)
			end
			local root = hostile and getRoot(candidate) or nil
			if root and getLivingMonsterHumanoid(candidate)
				and horizontalDistance(root.Position, position) <= radius
			then
				return true
			end
		end
	end
	return false
end

local function isOfferAreaPeaceful(playerRoot, guardian)
	local radarRange = getOfferRadarRange(playerRoot.Position)
	return not hasHostileMonsterNearby(playerRoot.Position, radarRange, guardian)
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
	state.offerRoarAt = nil
	state.offerPromptAt = nil
	state.model:SetAttribute("WMTOfferReady", false)
end

local function cancelOffer(state, reason)
	local player = state.offerPlayer
	local visible = state.offerReady
	clearOffer(state)
	if visible and player and player.Parent then
		rescueResultEvent:FireClient(player, state.model, false, reason or "the offer ended")
	end
end

local function restoreUnbonded(state)
	resetPetPath(state)
	if state.ownerCharacterConnection then
		state.ownerCharacterConnection:Disconnect()
		state.ownerCharacterConnection = nil
	end
	setShield(state, false)
	setPetAppearance(state, false)
	state.owner = nil
	state.mode = "unbonded"
	state.humanoid.WalkSpeed = state.unbondedWalkSpeed
	state.shieldEndsAt = 0
	state.shieldAvailableAt = 0
	state.helpPlayer = nil
	state.helpUntil = 0
	state.hostilePlayer = nil
	state.model:SetAttribute("WMTGuardianOwnerUserId", nil)
	state.model:SetAttribute("WMTGuardianPet", false)
	state.model:SetAttribute("WMTGuardianHostileUserId", nil)
end

local function makeHostile(state, player)
	if state.mode == "hostile" or not player or not player.Parent then return end
	resetPetPath(state)

	-- A nearby pet witnesses the guardian killings too: it abandons its owner
	-- before joining the local retaliation, so it cannot continue shielding them.
	clearOffer(state)
	if state.ownerCharacterConnection then
		state.ownerCharacterConnection:Disconnect()
		state.ownerCharacterConnection = nil
	end
	setShield(state, false)
	setPetAppearance(state, false)
	state.owner = nil
	state.helpPlayer = nil
	state.helpUntil = 0
	state.mode = "hostile"
	state.hostilePlayer = player
	state.humanoid.WalkSpeed = GUARDIAN_HOSTILE_WALK_SPEED
	state.model:SetAttribute("WMTGuardianOwnerUserId", nil)
	state.model:SetAttribute("WMTGuardianPet", false)
	state.model:SetAttribute("WMTGuardianHostileUserId", player.UserId)
end

local function provokeNearbyGuardians(sourceState, player, position)
	for _, state in pairs(guardians) do
		local root = getRoot(state.model)
		if state ~= sourceState
			and state.humanoid.Health > 0
			and root
			and (root.Position - position).Magnitude <= GUARDIAN_PROVOCATION_RADIUS
		then
			makeHostile(state, player)
		end
	end
end

local function recordGuardianKill(state)
	local attackerId = state.humanoid:GetAttribute("LastAttackerId")
	-- A BombMonster or another NPC can finish a WMT that a player wounded long
	-- ago. That is not a guardian kill by the player and must not provoke them.
	if state.humanoid:GetAttribute("LastMonsterAttacker") then return end
	local player = typeof(attackerId) == "number" and Players:GetPlayerByUserId(attackerId) or nil
	local root = getRoot(state.model)
	if not player or not root then return end

	local now = os.clock()
	local timestamps = guardianKillTimes[player] or {}
	for index = #timestamps, 1, -1 do
		if now - timestamps[index] > GUARDIAN_KILL_WINDOW_SECONDS then
			table.remove(timestamps, index)
		end
	end
	table.insert(timestamps, now)
	guardianKillTimes[player] = timestamps

	if #timestamps == GUARDIAN_KILLS_TO_PROVOKE then
		provokeNearbyGuardians(state, player, root.Position)
	end
end

local function acceptOffer(state, player)
	if state.mode ~= "offering" then return false, "offer is no longer active" end
	if state.offerPlayer ~= player then return false, "offer belongs to another player" end
	local root = ownerIsAlive({ owner = player })
	local guardianRoot = getRoot(state.model)
	if not root then return false, "player is no longer alive" end
	if not guardianRoot or state.humanoid.Health <= 0 then return false, "guardian is no longer alive" end
	if not state.offerReady then return false, "offer prompt is not ready" end
	if not isOfferAreaPeaceful(root, state.model) then return false, "hostile monster entered the offer area" end

	clearOffer(state)
	state.owner = player
	state.mode = "pet"
	-- This is assembly preparation, not repositioning: the guardian still moves
	-- exclusively through its Humanoid.
	preparePetMovement(state.model, state.humanoid, guardianRoot)
	state.humanoid.WalkSpeed = PET_FOLLOW_WALK_SPEED
	state.humanoid.MaxHealth = PET_MAX_HEALTH
	state.humanoid.Health = PET_MAX_HEALTH
	setPetAppearance(state, true)
	state.nextAmbientRoarAt = os.clock() + PET_AMBIENT_ROAR_SECONDS
	state.combatTarget = nil
	resetPetPath(state)
	if state.ownerCharacterConnection then
		state.ownerCharacterConnection:Disconnect()
	end
	state.ownerCharacterConnection = player.CharacterAdded:Connect(function(character)
		-- A respawn replaces the player's root. Throw away the old path so the
		-- next guardian update follows the new character rather than continuing
		-- a former local hunt around the death location.
		task.defer(function()
			if state.mode ~= "pet" or state.owner ~= player or not character.Parent then return end
			resetPetPath(state)
			state.lastOwnerRoot = nil -- Tactics resolves the current character on the next tick.
		end)
	end)
	state.model:SetAttribute("WMTGuardianOwnerUserId", player.UserId)
	state.model:SetAttribute("WMTGuardianPet", true)
	return true
end

local function presentOffer(state, player)
	if state.offerUsed or state.mode ~= "unbonded" or not player then return end
	state.offerUsed = true
	state.mode = "offering"
	state.offerPlayer = player
	state.offerDeadline = os.clock() + OFFER_TIMEOUT
	state.offerReady = false
	state.offerRoarAt = nil
	state.offerPromptAt = nil
	local playerRoot = getLivingPlayerRoot(player)
	local guardianRoot = getRoot(state.model)
	state.offerStartDistance = playerRoot and guardianRoot and (guardianRoot.Position - playerRoot.Position).Magnitude or OFFER_DISTANCE
	-- The guardian normally approaches to 15 studs, but the invitation may appear
	-- once it has made at least five honest studs of progress if terrain blocks a
	-- closer approach.
	state.offerArrivalDistance = math.max(OFFER_DISTANCE, state.offerStartDistance - OFFER_MIN_PROGRESS)
	state.model:SetAttribute("WMTOfferReady", false)
	state.offerConnection = rescueResponseEvent.OnServerEvent:Connect(function(sender, guardian, accepted)
		if sender ~= player or guardian ~= state.model or typeof(accepted) ~= "boolean" then return end
		if accepted then
			local succeeded, reason = acceptOffer(state, sender)
			if succeeded then
				warn(string.format("[GuardianPet] accepted: %s <- %s", sender.Name, state.model:GetFullName()))
			else
				warn(string.format("[GuardianPet] accept rejected for %s: %s", sender.Name, reason or "unknown reason"))
			end
			rescueResultEvent:FireClient(sender, state.model, succeeded, reason)
		else
			clearOffer(state)
			state.mode = "declined"
		end
	end)
end

local function connectPart(state, part)
	if not part:IsA("BasePart") or state.parts[part] then return end
	state.parts[part] = true
	part.Touched:Connect(function(hit)
		local attacker = getMonsterFromHit(hit)
		if isEligibleMonster(attacker, state.model) then
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

local function getTrustRecord(state, player)
	local record = state.trust[player]
	if not record then
		record = { aimSince = nil, lastAimAt = 0, talking = false, blockedUntilAimBreak = false }
		state.trust[player] = record
	end
	return record
end

local function stopConversation(state, player)
	local record = state.trust[player]
	if record and record.talking then
		record.talking = false
		conversationEvent:FireClient(player, "stop", state.model)
	end
end

local function answerConversation(state, player, message, keepConversationVisible)
	if not keepConversationVisible then stopConversation(state, player) end
	conversationEvent:FireClient(player, "answer", state.model, message, keepConversationVisible == true)
end

local function resetTrustAfterPlayerHit(state, player)
	-- The current offer is a promise of trust, so any player damage before the
	-- prompt appears cancels that attempt. Bomb/NPC damage is filtered by the
	-- caller and never reaches this function.
	stopConversation(state, player)
	state.trust[player] = nil
	state.hurtByPlayer = state.hurtByPlayer or {}
	-- A deliberate player wound is permanent for this guardian's remaining life.
	-- NPC and bomb damage never reaches this branch.
	state.hurtByPlayer[player] = true
	if state.mode == "offering" and state.offerPlayer == player and not state.offerReady then
		clearOffer(state)
		state.mode = "unbonded"
		state.offerUsed = false
	end
end

local function updateTrustRitual(state, now)
	if state.mode ~= "unbonded" or state.offerUsed then return end
	local guardianRoot = getRoot(state.model)
	if not guardianRoot then return end

	for _, player in ipairs(Players:GetPlayers()) do
		local record = getTrustRecord(state, player)
		local playerRoot = getLivingPlayerRoot(player)
		if not playerRoot then
			stopConversation(state, player)
			record.aimSince = nil
			record.blockedUntilAimBreak = false
			continue
		end

		if now - record.lastAimAt <= TRUST_AIM_GRACE_SECONDS then
			if record.blockedUntilAimBreak then
				continue
			end
			record.aimSince = record.aimSince or now
			local elapsed = now - record.aimSince
			-- A few quiet seconds make the mechanic discoverable only to players who
			-- deliberately keep their weapon off a guardian, rather than advertising
			-- itself on the first accidental crosshair pass.
			if elapsed < TRUST_CONVERSATION_DELAY_SECONDS then
				continue
			elseif not record.talking then
				record.talking = true
				conversationEvent:FireClient(player, "start", state.model, TRUST_AIM_SECONDS)
			end

			if not isOfferAreaPeaceful(playerRoot, state.model) then
				record.blockedUntilAimBreak = true
				answerConversation(state, player, "they are still near", true)
				task.delay(2.5, function()
					if record.blockedUntilAimBreak then stopConversation(state, player) end
				end)
			elseif elapsed >= TRUST_CONVERSATION_DELAY_SECONDS + TRUST_AIM_SECONDS then
				if state.hurtByPlayer and state.hurtByPlayer[player] then
					record.blockedUntilAimBreak = true
					answerConversation(state, player, "you hurt me before")
				else
					stopConversation(state, player)
					presentOffer(state, player)
				end
				return
			end
		else
			stopConversation(state, player)
			record.aimSince = nil
			record.blockedUntilAimBreak = false
		end
	end
end

local function validateTrustAim(player, state, tool, originOffset, direction)
	local acceptingAim = state.mode == "unbonded" and not state.offerUsed
		or state.mode == "offering" and state.offerPlayer == player and not state.offerReady
	if not acceptingAim then return false end
	if not tool or not tool:IsA("Tool") or tool.Parent ~= player.Character or not TRUST_AIM_WEAPONS[tool.Name] then
		return false
	end
	if typeof(originOffset) ~= "Vector3" or originOffset.Magnitude > AimConfig.MaxCameraOriginOffset then return false end
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then return false end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not root or not root:IsA("BasePart") then return false end
	local cameraOrigin = root.Position + originOffset
	if head and head:IsA("BasePart") and (cameraOrigin - head.Position).Magnitude > AimConfig.MaxCameraHeadOffset then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, tool }
	params.IgnoreWater = true
	local result = Workspace:Raycast(cameraOrigin, direction.Unit * TRUST_RAY_RANGE, params)
	return result and getMonsterFromHit(result.Instance) == state.model or false
end

trustAimEvent.OnServerEvent:Connect(function(player, guardian, tool, originOffset, direction)
	local state = guardians[guardian]
	if not state or not validateTrustAim(player, state, tool, originOffset, direction) then return end
	getTrustRecord(state, player).lastAimAt = os.clock()
end)

local tacticsAPI = {
	root = getRoot, humanoid = getLivingMonsterHumanoid, ownerRoot = getLivingPlayerRoot,
	config = MonsterManager.getConfig, eligible = isEligibleMonster, nearby = nearbyMonsters, damage = damageMonster,
	invite = inviteNearbyGuardians, release = releaseGangMember, status = statusEvent,
}

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
			-- Intentional world behaviour: unbonded WMTs may calmly linger around a
			-- player without attacking, fleeing, or being pulled elsewhere. Do not
			-- replace this with a chase/roam rule; the stillness is what makes the
			-- later trust ritual feel earned rather than random.
			updateTrustRitual(state, now)
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
		elseif state.mode == "gang" then
			Tactics.step(state, now, tacticsAPI)
		elseif state.mode == "offering" then
			local guardianRoot = getRoot(state.model)
			local playerRoot = ownerIsAlive({ owner = state.offerPlayer })
			local record = state.offerPlayer and state.trust[state.offerPlayer]
			-- The exact WMT contour must remain selected through its approach and
			-- roar. Once the prompt is visible, the player must be free to move the
			-- pointer onto Accept without that UI action cancelling the offer.
			local contourSelected = state.offerReady
				or (record and now - record.lastAimAt <= TRUST_AIM_GRACE_SECONDS)
			local peaceful = guardianRoot and playerRoot
				and isOfferAreaPeaceful(playerRoot, state.model)
			if not guardianRoot or not playerRoot or now >= state.offerDeadline
				or not contourSelected or not peaceful
			then
				cancelOffer(state, "the guardian changed its mind")
				-- Losing this exact contour or having danger enter the current battle
				-- radar cancels the attempt. The player can deliberately aim again.
				state.mode = "unbonded"
				state.offerUsed = false
				if record then record.aimSince = nil end
			else
				local distance = (guardianRoot.Position - playerRoot.Position).Magnitude
				if not state.offerRoarAt and distance > (state.offerArrivalDistance or OFFER_DISTANCE) then
					state.humanoid:MoveTo(getPetStandOffDestination(playerRoot, guardianRoot):Lerp(playerRoot.Position, 0.53))
				elseif not state.offerRoarAt then
					state.offerRoarAt = now
					state.offerPromptAt = now + OFFER_PROMPT_DELAY
					playPetRoar(state, now, 0)
				elseif now >= state.offerPromptAt and not state.offerReady then
					state.offerReady = true
					-- The approach timeout has done its job. Give the visible decision
					-- its own complete response window instead of using whatever remains.
					state.offerDeadline = now + OFFER_RESPONSE_SECONDS
					state.model:SetAttribute("WMTOfferReady", true)
					warn(string.format("[GuardianPet] offer ready: %s <- %s", state.offerPlayer.Name, state.model:GetFullName()))
					rescueEvent:FireClient(state.offerPlayer, state.model, "It wants to be your pet.")
				end
			end
		elseif state.mode == "pet" then
			if not state.owner or not state.owner.Parent then
				restoreUnbonded(state)
			else
				Tactics.step(state, now, tacticsAPI)
				if now >= state.nextAmbientRoarAt then
					playPetRoar(state, now, PET_COMBAT_ROAR_COOLDOWN)
					state.nextAmbientRoarAt = now + PET_AMBIENT_ROAR_SECONDS
				end
				local playerRoot = getLivingPlayerRoot(state.owner)
				local guardianRoot = getRoot(state.model)
				if state.shieldEndsAt > 0 and (now >= state.shieldEndsAt or not playerRoot) then
					setShield(state, false)
					state.shieldEndsAt = 0
					state.shieldAvailableAt = now + SHIELD_COOLDOWN
				end
				if state.shieldEndsAt <= 0 and playerRoot and guardianRoot and (guardianRoot.Position - playerRoot.Position).Magnitude <= 50
					and now >= state.shieldAvailableAt
					and #nearbyMonsters(playerRoot.Position, THREAT_RADIUS, state.model) >= 3 then
					if math.random() <= 0.40 then
						setShield(state, true)
						state.shieldEndsAt = now + SHIELD_DURATION
					else
						state.shieldAvailableAt = now + 2
					end
				end
			end
		elseif state.mode == "hostile" then
			local playerRoot = getLivingPlayerRoot(state.hostilePlayer)
			local guardianRoot = getRoot(state.model)
			if playerRoot and guardianRoot then
				state.humanoid:MoveTo(playerRoot.Position)
				if (guardianRoot.Position - playerRoot.Position).Magnitude <= GUARDIAN_HOSTILE_ATTACK_RANGE
					and now - (state.lastPlayerHitAt or 0) >= GUARDIAN_HOSTILE_ATTACK_COOLDOWN
				then
					local character = state.hostilePlayer.Character
					local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
					local damage = MonsterManager.getDamageToPlayers(state.model)
					if targetHumanoid and targetHumanoid.Health > 0 and damage > 0 then
						state.lastPlayerHitAt = now
						targetHumanoid:TakeDamage(damage)
					end
				end
			end
		end
		task.wait(UPDATE_INTERVAL)
	end

	resetPetPath(state)
	if state.ownerCharacterConnection then state.ownerCharacterConnection:Disconnect() end
	clearOffer(state)
	setShield(state, false)
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
		trust = {},
		hurtByPlayer = {},
		originalPartColors = {},
		helpPlayer = nil,
		helpUntil = 0,
		offerUsed = false,
		shieldEndsAt = 0,
		shieldAvailableAt = 0,
		unbondedWalkSpeed = humanoid.WalkSpeed,
		unbondedDisplayName = humanoid.DisplayName,
		unbondedDisplayDistanceType = humanoid.DisplayDistanceType,
		unbondedNameDisplayDistance = humanoid.NameDisplayDistance,
		lastDamagedAt = os.clock(),
		lastHurtSoundAt = {},
		hostilePlayer = nil,
		lastPlayerHitAt = 0,
		lastRoarAt = -math.huge,
		nextAmbientRoarAt = math.huge,
		combatTarget = nil,
		gangLeader = nil,
		gangUntil = 0,
		gangCooldownUntil = 0,
		gangInvitationUntil = 0,
		lastGangInvitationAt = -math.huge,
	}
	guardians[model] = state
	-- Agent dimensions reflect this imported rig's collidable body, not a default avatar.
	local feetY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local topY = root.Position.Y + root.Size.Y / 2
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			topY = math.max(topY, part.Position.Y + part.Size.Y / 2)
		end
	end
	state.agentHeight = math.max(7, math.ceil(topY - feetY))
	state.agentRadius = math.max(2.5, root.Size.X / 2, root.Size.Z / 2)
	model:SetAttribute("WMTGuardianPet", false)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			state.originalPartColors[item] = item.Color
		end
	end

	for _, item in model:GetDescendants() do connectPart(state, item) end
	model.DescendantAdded:Connect(function(item) task.defer(connectPart, state, item) end)

	humanoid.HealthChanged:Connect(function(health)
		if health >= state.lastHealth then state.lastHealth = health return end
		state.lastHealth = health
		state.lastDamagedAt = os.clock()
		-- Bombs and all NPC damage are neutral events. They neither cancel a
		-- possible bond nor count as player aggression, even after an earlier
		-- player shot left an attribution attribute on this humanoid.
		if humanoid:GetAttribute("LastMonsterAttacker") then return end
		local attackerId = humanoid:GetAttribute("LastAttackerId")
		local player = typeof(attackerId) == "number" and Players:GetPlayerByUserId(attackerId) or nil
		if player then
			local now = os.clock()
			local lastSoundAt = state.lastHurtSoundAt[player] or -math.huge
			if now - lastSoundAt >= GUARDIAN_HURT_SOUND_INTERVAL then
				state.lastHurtSoundAt[player] = now
				playGuardianSound(model, "GuardianHurt")
			end
			resetTrustAfterPlayerHit(state, player)
		end
	end)
	state.lastHealth = humanoid.Health
	humanoid.Died:Connect(function()
		resetPetPath(state)
		local owner = state.owner
		if state.mode == "pet" and owner and owner.Parent then
			playGuardianSound(model, "GuardianDeath", "GuardianRoar")
			petLostEvent:FireClient(owner)
		end
		recordGuardianKill(state)
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
	if item:IsA("Model") then
		setupGuardian(item)
	end
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			setupGuardian(item)
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	guardianKillTimes[player] = nil
	playerThreatActive[player] = nil
	for _, state in pairs(guardians) do
		state.trust[player] = nil
	end
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

local function monitorPlayerThreat(player, character)
	-- Roll once when a threat enters range. A lingering crowd must not reroll
	-- every second and turn every WMT into a guaranteed bodyguard.
	task.spawn(function()
		while player.Parent and player.Character == character do
			local playerRoot = getLivingPlayerRoot(player)
			local threatened = playerRoot
				and hasHostileMonsterNearby(playerRoot.Position, HELP_THREAT_RADIUS, nil)
			if threatened then
				if not playerThreatActive[player] then
					playerThreatActive[player] = true
					callForHelp(player)
				end
			else
				playerThreatActive[player] = nil
			end
			task.wait(HELP_THREAT_CHECK_INTERVAL)
		end
		playerThreatActive[player] = nil
	end)
end

local function observePlayer(player)
	if player.Character then monitorPlayerThreat(player, player.Character) end
	player.CharacterAdded:Connect(function(character)
		monitorPlayerThreat(player, character)
	end)
end

for _, player in Players:GetPlayers() do observePlayer(player) end
Players.PlayerAdded:Connect(observePlayer)

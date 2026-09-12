-- GuardianMonsterSystem owns this controller and supplies canonical combat helpers.
local Navigation = require(script.Parent:WaitForChild("GuardianNavigation"))
local Workspace = game:GetService("Workspace")
local Tactics = {}
Tactics.Config = {
	FollowDistance = 14, FollowSpeed = 10, CatchupSpeed = 26,
	CombatWalkSpeed = 15, CombatSprintSpeed = 28, SprintCatchupDistance = 50,
	RejoinRange = 200, DefenseRadius = 35, AssistRange = 50,
	AttackRange = 9, AttackHeight = 8, AttackCooldown = 0.65, Damage = 150,
	TargetLock = 2, FailedTargetCooldown = 20, NoHitTimeout = 10,
	OwnerRetrySeconds = 3, GangLimit = 3,
	StuckDistance = 70, StuckSeconds = 30, StuckMovement = 4,
	NoFollowRadius = 4,
}
local C = Tactics.Config
local phrases = {
	Follow = "I'm with you.", Cover = "I'm covering you.", Engage = "Protecting you.",
	Recruit = "Gathering help.", Regroup = "Coming back to you.",
	HoldAndHunt = "I'll wait for you.", Recover = "Finding another way.",
}

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function distance(a, b) return flat(a - b).Magnitude end

local function announce(state, label, now, api)
	state.model:SetAttribute("GuardianState", label)
	-- Retry a suppressed announcement after the global cooldown expires.
	if state.tacticalState == label and state.spokenState == label then return end
	state.tacticalState = label
	-- Only bonded leaders speak; failed routes/target switches cannot flood the HUD.
	state.lastStatus = state.lastStatus or {}
	if state.mode == "pet" and state.owner and state.owner.Parent
		and now >= (state.nextStatusAt or 0) and now - (state.lastStatus[label] or -math.huge) >= 30 then
		state.spokenState = label
		state.nextStatusAt = now + 8
		state.lastStatus[label] = now
		local message = label == "Engage" and state.holdOrigin and "Clearing this area." or phrases[label]
		api.status:FireClient(state.owner, state.model, label, message)
	end
end
Tactics.announce = announce

function Tactics.reset(state)
	Navigation.stop(state)
	state.combatTarget = nil
	state.failedTargets = {}
	state.ownerRetryAt = 0
	state.holdOrigin = nil
	state.recoverUntil = 0
	state.tacticalState = nil
	state.spokenState = nil
	state.escortMoving = false
	state.failedOwnerPosition = nil
	state.model:SetAttribute("GuardianTarget", nil)
	state.model:SetAttribute("GuardianState", nil)
end

local function dropTarget(state, now, blocked)
	local old = state.combatTarget
	if blocked and old then state.failedTargets[old] = now + C.FailedTargetCooldown end
	state.combatTarget = nil
	state.targetPriority = nil
	state.model:SetAttribute("GuardianTarget", nil)
	Navigation.stop(state)
end

local function avoidFailed(state, target, now)
	return (state.failedTargets[target] or 0) > now
end

-- Zombies remain a useful local-clear target, but an escort should never turn
-- into an unnerving perpetual sprint merely to deal with one. Sprint is saved
-- for the genuinely dangerous monsters that can threaten the player quickly.
local function needsCombatSprint(target, api)
	local config = api.config(target)
	return config and config.hp >= 320
end

local function chooseTarget(state, root, ownerRoot, now, api)
	local best, priority, bestDistance
	for _, target in ipairs(api.nearby(ownerRoot.Position, C.AssistRange, state.model)) do
		local tr = api.root(target)
		if tr and not avoidFailed(state, target, now) then
			local fromOwner = distance(tr.Position, ownerRoot.Position)
			local hum = api.humanoid(target)
			local attackedAt = hum and hum:GetAttribute("LastPlayerDamageAt")
			local p
			-- Protect before contact, including zombies approaching from behind.
			if fromOwner <= 12 then
				p = 0
			elseif fromOwner <= C.DefenseRadius then
				p = 1
			elseif hum and hum:GetAttribute("LastAttackerId") == state.owner.UserId
				and type(attackedAt) == "number" and Workspace:GetServerTimeNow() - attackedAt <= 4 then
				p = 2
			end
			-- No independent clearing: only nearby threats or the owner's recent target.
			local d = fromOwner + distance(root.Position, tr.Position) * 0.2
			if p and (not best or p < priority or (p == priority and d < bestDistance)) then
				best, priority, bestDistance = target, p, d
			end
		end
	end
	return best, priority
end

local noFollowZones = {}

local function refreshNoFollowZone(instance)
	if not (instance:IsA("Model") or instance:IsA("BasePart")) then return end
	if instance:GetAttribute("GuardianNoFollow") == true then
		noFollowZones[instance] = true
	else
		noFollowZones[instance] = nil
	end
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	refreshNoFollowZone(instance)
	end
Workspace.DescendantAdded:Connect(function(instance)
	refreshNoFollowZone(instance)
	if instance:IsA("Model") or instance:IsA("BasePart") then
		instance:GetAttributeChangedSignal("GuardianNoFollow"):Connect(function()
			refreshNoFollowZone(instance)
		end)
	end
end)
Workspace.DescendantRemoving:Connect(function(instance)
	noFollowZones[instance] = nil
end)

local function markedAncestor(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:GetAttribute("GuardianNoFollow") == true then return current end
		current = current.Parent
	end
	return nil
end

local function distanceToNoFollowZone(position, zone)
	if zone:IsA("BasePart") then
		local localPosition = zone.CFrame:PointToObjectSpace(position)
		local half = zone.Size * 0.5
		local closest = Vector3.new(
			math.clamp(localPosition.X, -half.X, half.X),
			math.clamp(localPosition.Y, -half.Y, half.Y),
			math.clamp(localPosition.Z, -half.Z, half.Z)
		)
		return (localPosition - closest).Magnitude
	end

	local ok, boxCFrame, boxSize = pcall(function()
		return zone:GetBoundingBox()
	end)
	if not ok then return math.huge end
	local localPosition = boxCFrame:PointToObjectSpace(position)
	local half = boxSize * 0.5
	local closest = Vector3.new(
		math.clamp(localPosition.X, -half.X, half.X),
		math.clamp(localPosition.Y, -half.Y, half.Y),
		math.clamp(localPosition.Z, -half.Z, half.Z)
	)
	return (localPosition - closest).Magnitude
end

local function noFollowZone(instance)
	local marked = markedAncestor(instance)
	if marked then return marked end
	if not instance:IsA("BasePart") then return nil end
	for zone in pairs(noFollowZones) do
		if zone.Parent and distanceToNoFollowZone(instance.Position, zone) <= C.NoFollowRadius then
			return zone
		end
	end
	return nil
end

local function recover(state, root, now, api)
	if not state.recoverUntil or now >= state.recoverUntil then return false end
	announce(state, "Recover", now, api)
	state.humanoid.WalkSpeed = C.FollowSpeed
	if state.recoverDestination then
		Navigation.move(state, root, state.recoverDestination, "recover", now)
	end
	return true
end

local function beginRecovery(state, root, now)
	state.recoverUntil = now + 1.5
	state.recoverDestination = nil
	-- Prefer the last place actually reached, never a position correction.
	if state.safePosition and distance(state.safePosition, root.Position) > 3 then
		state.recoverDestination = state.safePosition
	elseif state.previousSafePosition then
		state.recoverDestination = state.previousSafePosition
	end
end

local function engage(state, target, priority, root, now, api)
	if state.combatTarget ~= target then
		Navigation.stop(state)
		state.combatTarget = target
		state.targetPriority = priority
		state.targetLockUntil = now + C.TargetLock
		state.lastSuccessfulHitAt = now
		state.model:SetAttribute("GuardianTarget", target.Name)
	end
	announce(state, "Engage", now, api)
	local targetRoot = api.root(target)
	if not targetRoot then dropTarget(state, now, false); return end
	local offset = targetRoot.Position - root.Position
	local inRange = flat(offset).Magnitude <= C.AttackRange and math.abs(offset.Y) <= C.AttackHeight
	if inRange and Navigation.clear(state.model, root.Position, targetRoot.Position, target) then
		Navigation.stop(state)
		-- One attack cooldown per guardian, not per enemy: target switching cannot multiply DPS.
		if now >= (state.nextStrikeAt or 0) then
			state.nextStrikeAt = now + C.AttackCooldown
			local dealt = api.damage(state, target, C.Damage, C.AttackCooldown)
			if dealt and dealt > 0 then
				state.lastSuccessfulHitAt = now
				state.model:SetAttribute("GuardianLastHitAt", Workspace:GetServerTimeNow())
			end
		end
	else
		state.humanoid.WalkSpeed = (priority == 0 or priority == 1 or needsCombatSprint(target, api))
			and C.CombatSprintSpeed or C.CombatWalkSpeed
		-- Predict a short intercept, then choose a distinct side of the attack ring.
		local velocity = flat(targetRoot.AssemblyLinearVelocity)
		if velocity.Magnitude > 30 then velocity = velocity.Unit * 30 end
		local lead = velocity * math.min(0.65, flat(offset).Magnitude / math.max(1, state.humanoid.WalkSpeed))
		local side = flat(root.Position - targetRoot.Position)
		if side.Magnitude < 0.1 then side = Vector3.xAxis end
		if state.gangSlot then
			local angle = state.gangSlot * math.pi / 2
			side = Vector3.new(math.cos(angle), 0, math.sin(angle))
		end
		local goal = targetRoot.Position + lead + side.Unit * 5
		local result = Navigation.move(state, root, goal, target, now)
		if result == "failed" then
			dropTarget(state, now, true)
			beginRecovery(state, root, now)
			announce(state, "Regroup", now, api)
			return
		end
	end
	if now - (state.lastSuccessfulHitAt or now) >= C.NoHitTimeout then
		dropTarget(state, now, true)
		beginRecovery(state, root, now)
		announce(state, "Regroup", now, api)
	end
end

function Tactics.step(state, now, api)
	local root = api.root(state.model)
	if not root then return end
	state.failedTargets = state.failedTargets or {}
	for target, untilTime in pairs(state.failedTargets) do
		if not target.Parent or untilTime <= now then state.failedTargets[target] = nil end
	end
	if not state.safePosition or distance(root.Position, state.safePosition) >= 6 then
		state.previousSafePosition = state.safePosition
		state.safePosition = root.Position
	end
	-- Recover a physically seated/fallen rig using Humanoid states, never forces/pivots.
	if state.humanoid.Sit then state.humanoid.Sit = false end
	if state.humanoid.PlatformStand then state.humanoid.PlatformStand = false end
	local hs = state.humanoid:GetState()
	if hs == Enum.HumanoidStateType.FallingDown or hs == Enum.HumanoidStateType.Ragdoll then
		state.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	if state.mode == "gang" then
		local leader = state.gangLeader
		local lr = leader and api.root(leader.model)
		if not leader or leader.mode ~= "pet" or leader.humanoid.Health <= 0 or not lr
			or now >= (state.gangUntil or 0) then api.release(state, now); return end
		if distance(root.Position, lr.Position) > C.RejoinRange then api.release(state, now); return end
		if recover(state, root, now, api) then return end
		local target = leader.combatTarget
		if target and api.eligible(target, state.model) and not avoidFailed(state, target, now) then
			local tr = api.root(target)
			if tr and distance(tr.Position, lr.Position) <= 90 then
				engage(state, target, leader.targetPriority, root, now, api)
				return
			end
		end
		if state.combatTarget then dropTarget(state, now, false) end
		announce(state, leader.tacticalState == "HoldAndHunt" and "HoldAndHunt" or "Cover", now, api)
		local slot = state.gangSlot or 1
		local goal = lr.Position - lr.CFrame.LookVector * (10 + slot * 3)
			+ lr.CFrame.RightVector * (slot == 2 and -9 or 9)
		state.humanoid.WalkSpeed = distance(root.Position, lr.Position) > C.SprintCatchupDistance
			and C.CatchupSpeed or C.FollowSpeed
		if now < (state.ownerRetryAt or 0) then return end
		if Navigation.move(state, root, goal, leader.model, now) == "failed" then
			Navigation.stop(state)
			state.ownerRetryAt = now + C.OwnerRetrySeconds
		end
		return
	end

	local ownerRoot = api.ownerRoot(state.owner)
	if not ownerRoot then
		if state.combatTarget then dropTarget(state, now, false) end
		Navigation.stop(state)
		announce(state, "HoldAndHunt", now, api)
		return -- Bond remains; the new character will be picked up next tick.
	end
	local changedOwner = state.lastOwnerRoot ~= ownerRoot
	if changedOwner then
		Tactics.reset(state)
		state.lastOwnerRoot = ownerRoot
	end
	local ownerDistance = distance(root.Position, ownerRoot.Position)
	-- Stay outside deliberately marked interiors. A guardian is a companion,
	-- not a creature that tries to navigate stairs, rooms, and furniture.
	if noFollowZone(ownerRoot) then
		if state.combatTarget then dropTarget(state, now, false) end
		Navigation.stop(state)
		state.escortMoving = false
		announce(state, "HoldAndHunt", now, api)
		return
	end
	-- A distant guardian must actually be stationary for the full window. Its
	-- recovery remains Humanoid-driven: discard the stale route, jump once, and
	-- walk toward nearby clear ground before retrying the owner route.
	if ownerDistance <= C.StuckDistance then
		state.distantSince = nil
		state.distantAnchorPosition = nil
	elseif not state.distantSince then
		state.distantSince = now
		state.distantAnchorPosition = root.Position
	elseif distance(root.Position, state.distantAnchorPosition or root.Position) > C.StuckMovement then
		state.distantSince = now
		state.distantAnchorPosition = root.Position
	elseif not state.combatTarget and now - state.distantSince >= C.StuckSeconds then
		Navigation.reset(state)
		state.humanoid.Jump = true
		state.recoverDestination = Navigation.findClearFallback(state, root, ownerRoot.Position)
		state.recoverUntil = state.recoverDestination and (now + 6) or 0
		state.ownerRetryAt = 0
		state.failedOwnerPosition = nil
		state.distantSince = now
		state.distantAnchorPosition = root.Position
		announce(state, "Recover", now, api)
	end
	-- A moving owner re-entering the local area is an immediate rejoin opportunity.
	if state.failedOwnerPosition and distance(ownerRoot.Position, state.failedOwnerPosition) >= 24 then
		state.ownerRetryAt = 0
		state.failedOwnerPosition = nil
	end
	-- Distance never cancels the bond or starts an independent hunt.
	state.holdOrigin = nil
	local target, priority = chooseTarget(state, root, ownerRoot, now, api)
	if target then state.recoverUntil = 0 end
	if recover(state, root, now, api) then return end
	if target and ownerDistance <= C.RejoinRange then
		api.invite(state, now)
		engage(state, target, priority, root, now, api)
		return
	elseif state.combatTarget then
		dropTarget(state, now, false)
	end
	if now < (state.ownerRetryAt or 0) then
		Navigation.stop(state)
		announce(state, "Recover", now, api)
		return
	end
	local count = api.invite(state, now) or 0
	if count > 0 then announce(state, "Recruit", now, api) end
	local goal = ownerRoot.Position - ownerRoot.CFrame.LookVector * C.FollowDistance + ownerRoot.CFrame.RightVector * 7
	state.humanoid.WalkSpeed = ownerDistance > C.SprintCatchupDistance
		and C.CatchupSpeed or C.FollowSpeed
	-- Stand comfortably nearby instead of orbiting whenever the player turns.
	local sameLevel = math.abs(root.Position.Y - ownerRoot.Position.Y) < 8
	if ownerDistance > 24 or not sameLevel then state.escortMoving = true end
	if ownerDistance < 18 and sameLevel then state.escortMoving = false end
	if not state.escortMoving then
		Navigation.stop(state)
		announce(state, "Cover", now, api)
		return
	end
	announce(state, ownerDistance > C.SprintCatchupDistance and "Regroup" or "Follow", now, api)
	local result = Navigation.move(state, root, goal, ownerRoot, now)
	if result == "failed" then
		Navigation.stop(state)
		state.ownerRetryAt = now + C.OwnerRetrySeconds
		state.failedOwnerPosition = ownerRoot.Position
		beginRecovery(state, root, now)
		announce(state, "Recover", now, api)
	end
end

return Tactics

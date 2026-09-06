-- GuardianMonsterSystem owns this controller and supplies canonical combat helpers.
local Navigation = require(script.Parent:WaitForChild("GuardianNavigation"))
local Workspace = game:GetService("Workspace")
local Tactics = {}
Tactics.Config = {
	FollowDistance = 14, FollowSpeed = 10, CatchupSpeed = 26,
	CombatWalkSpeed = 15, CombatSprintSpeed = 28, SprintCatchupDistance = 50,
	RejoinRange = 200, DefenseRadius = 30, AssistRange = 65, HuntRadius = 80,
	AttackRange = 9, AttackHeight = 8, AttackCooldown = 0.65, Damage = 150,
	TargetLock = 2, FailedTargetCooldown = 20, NoHitTimeout = 10,
	OwnerRetrySeconds = 8, GangLimit = 3,
}
local C = Tactics.Config
local phrases = {
	Follow = "I'm with you.", Cover = "I'm covering you.", Engage = "Protecting you.",
	Recruit = "Gathering help.", Regroup = "Target lost. Regrouping.",
	HoldAndHunt = "I'll hold this ground.", Recover = "Finding another way.",
}

local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function distance(a, b) return flat(a - b).Magnitude end

local function announce(state, label, now, api)
	state.model:SetAttribute("GuardianState", label)
	if state.tacticalState == label then return end
	state.tacticalState = label
	-- Only bonded leaders speak; failed routes/target switches cannot flood the HUD.
	state.lastStatus = state.lastStatus or {}
	if state.mode == "pet" and state.owner and state.owner.Parent
		and now >= (state.nextStatusAt or 0) and now - (state.lastStatus[label] or -math.huge) >= 30 then
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

local function chooseTarget(state, root, ownerRoot, holding, now, api)
	local origin = holding and state.holdOrigin or ownerRoot.Position
	local radius = holding and C.HuntRadius or C.AssistRange
	local best, priority, bestDistance
	for _, target in ipairs(api.nearby(origin, radius, state.model)) do
		local tr = api.root(target)
		if tr and not avoidFailed(state, target, now) then
			local fromOwner = distance(tr.Position, origin)
			local p = 3
			if not holding then
				local hum = api.humanoid(target)
				local attackedAt = hum and hum:GetAttribute("LastPlayerDamageAt")
				if fromOwner <= 10 then
					p = 0 -- A monster already on the owner overrides a distant assist.
				elseif hum and hum:GetAttribute("LastAttackerId") == state.owner.UserId
					and type(attackedAt) == "number" and Workspace:GetServerTimeNow() - attackedAt <= 4 then
					p = 1
				elseif fromOwner <= C.DefenseRadius then
					p = 2
				elseif fromOwner > 45 then
					continue
				end
			end
			local d = distance(root.Position, tr.Position)
			if not best or p < priority or (p == priority and d < bestDistance) then
				best, priority, bestDistance = target, p, d
			end
		end
	end
	local current = state.combatTarget
	if current and api.eligible(current, state.model) and not avoidFailed(state, current, now) then
		local tr = api.root(current)
		local inLeash = tr and distance(tr.Position, origin) <= radius
		-- Immediate danger always interrupts a faraway assist; it cannot drag the pet away.
		if inLeash and now < (state.targetLockUntil or 0)
			and (not best or priority >= (state.targetPriority or 3)) then
			return current, state.targetPriority
		end
	end
	return best, priority
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
		state.humanoid.WalkSpeed = needsCombatSprint(target, api)
			and C.CombatSprintSpeed or C.CombatWalkSpeed
		-- Predict a short intercept, then choose a distinct side of the attack ring.
		local velocity = flat(targetRoot.AssemblyLinearVelocity)
		if velocity.Magnitude > 30 then velocity = velocity.Unit * 30 end
		local lead = velocity * math.min(0.65, flat(offset).Magnitude / C.CombatSpeed)
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
	-- A moving owner re-entering the local area is an immediate rejoin opportunity.
	if state.failedOwnerPosition and distance(ownerRoot.Position, state.failedOwnerPosition) >= 24 then
		state.ownerRetryAt = 0
		state.failedOwnerPosition = nil
	end
	local holding = ownerDistance > C.RejoinRange or now < (state.ownerRetryAt or 0)
	if holding then state.holdOrigin = state.holdOrigin or root.Position else state.holdOrigin = nil end
	local urgent = not holding and #api.nearby(ownerRoot.Position, C.DefenseRadius, state.model) > 0
	if urgent then state.recoverUntil = 0 end
	if recover(state, root, now, api) then return end

	-- A pet outside escort range must close the gap before starting another chase.
	if not holding and ownerDistance > C.SprintCatchupDistance and not urgent then
		if state.combatTarget then dropTarget(state, now, false) end
	else
		local target, priority = chooseTarget(state, root, ownerRoot, holding, now, api)
		if target then
			-- Recruiting is a bounded local invitation; no movement detour.
			if urgent then api.invite(state, now) end
			engage(state, target, priority, root, now, api)
			return
		elseif state.combatTarget then
			dropTarget(state, now, false)
		end
	end
	if holding then
		Navigation.stop(state)
		announce(state, "HoldAndHunt", now, api)
		api.invite(state, now)
		return
	end
	local count = api.invite(state, now) or 0
	if count > 0 then announce(state, "Recruit", now, api) end
	local goal = ownerRoot.Position - ownerRoot.CFrame.LookVector * C.FollowDistance + ownerRoot.CFrame.RightVector * 7
	state.humanoid.WalkSpeed = ownerDistance > C.SprintCatchupDistance
		and C.CatchupSpeed or C.FollowSpeed
	if distance(root.Position, goal) < 5 and math.abs(root.Position.Y - goal.Y) < 8 then
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
		state.holdOrigin = root.Position
		beginRecovery(state, root, now)
		announce(state, "HoldAndHunt", now, api)
	end
end

return Tactics

-- Run as a temporary ModuleScript in Studio Play, server context.
-- This creates only isolated anchored fixtures and removes them when complete.
return function()
	assert(game:GetService("RunService"):IsRunning(), "Play test only")
	local Tactics = require(game:GetService("ServerScriptService").GuardianTactics)
	local origin = Vector3.new(14000, 1000, 14000)
	local folder = Instance.new("Folder")
	folder.Name = "GuardianHuntIsolatedTest"
	folder.Parent = workspace
	local results = {}
	local function check(name, passed, details)
		table.insert(results, { name = name, passed = passed == true, details = details })
	end
	local function actor(name, position, health)
		local model = Instance.new("Model")
		model.Name = name
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Anchored = true
		root.CanCollide = false
		root.Size = Vector3.new(2, 2, 2)
		root.Position = position
		root.Parent = model
		local humanoid = Instance.new("Humanoid")
		humanoid.RequiresNeck = false
		humanoid.MaxHealth = health or 10000
		humanoid.Health = health or 10000
		humanoid.Parent = model
		model.PrimaryPart = root
		model.Parent = folder
		return model, root, humanoid
	end
	local function apiFor(ownerRoot, candidates, damage)
		return {
			root = function(model) return model and model:FindFirstChild("HumanoidRootPart") end,
			humanoid = function(model) return model and model:FindFirstChildOfClass("Humanoid") end,
			ownerRoot = function() return ownerRoot end,
			eligible = function(model)
				local h = model and model:FindFirstChildOfClass("Humanoid")
				return h ~= nil and h.Health > 0
			end,
			candidates = function() return candidates end,
			config = function() return { hp = 90 } end,
			damage = damage or function() return 1 end,
			invite = function() return 0 end,
			status = { FireClient = function() end },
		}
	end
	local ok, err = xpcall(function()
		local guardian, guardianRoot, guardianHumanoid = actor("Guardian", origin + Vector3.new(100, 0, 0))
		local owner, ownerRoot = actor("Owner", origin, 100)
		local near, nearRoot = actor("Near", origin + Vector3.new(350, 0, 0))
		local far, farRoot = actor("Far", origin + Vector3.new(600, 0, 0))
		local zone = Instance.new("Part")
		zone.Anchored = true
		zone.CanCollide = false
		zone.Size = Vector3.new(10, 10, 10)
		zone.Position = origin + Vector3.new(800, 0, 0)
		zone:SetAttribute("GuardianNoFollow", true)
		zone.Parent = folder
		local forbidden, forbiddenRoot = actor("Forbidden", origin + Vector3.new(808, 0, 0))
		task.wait() -- Deliver the shared zone registry's DescendantAdded callback.
		local state = {
			model = guardian, humanoid = guardianHumanoid, mode = "pet",
			owner = { UserId = -1, Parent = game:GetService("Players") }, petBehavior = "Hunt",
		}
		local api = apiFor(ownerRoot, { near, far, forbidden })
		Tactics.step(state, 0, api)
		check("Remote score chooses farthest-owner target", state.combatTarget == far, state.combatTarget and state.combatTarget.Name)
		check("No-follow target is excluded from hunt selection", state.combatTarget ~= forbidden)
		state.combatTarget = nil
		state.huntSweepCenter = farRoot.Position
		state.huntPhase = "sweep"
		Tactics.step(state, 0.1, api)
		check("Sweep chooses nearest guardian target within 70 studs", state.combatTarget == far, state.combatTarget and state.combatTarget.Name)

		-- The target is acquired once. Moving the owner does not cause a rescore.
		local locked, lockedRoot, lockedHumanoid = actor("Locked", guardianRoot.Position + Vector3.new(7, 0, 0), 10000)
		local alternate, alternateRoot = actor("Alternate", origin + Vector3.new(900, 0, 0), 10000)
		api = apiFor(ownerRoot, { locked, alternate }, function() return 0 end)
		state.huntSweepCenter = nil
		state.huntPhase = nil
		Tactics.reset(state)
		Tactics.step(state, 1, api)
		check("Hunt locks its first selected target", state.combatTarget == alternate, state.combatTarget and state.combatTarget.Name)
		-- A long approach cannot trip the ten-second melee no-hit rule. This
		-- fixture uses synthetic time, so no real actor is moved.
		Tactics.reset(state)
		api = apiFor(ownerRoot, { alternate }, function() return 0 end)
		Tactics.step(state, 20, api) -- acquire
		Tactics.step(state, 21, api) -- begin route
		Tactics.step(state, 32, api) -- more than ten seconds still out of melee
		check("Far travel beyond ten seconds stays locked outside melee", state.combatTarget == alternate and not state.huntRecoveryAttempted)
		-- The selected target above is intentionally remote. Force a close locked
		-- target to exercise melee/no-hit timing without world navigation.
		state.combatTarget = locked
		state.huntTargetLastPosition = lockedRoot.Position
		state.huntProgressAnchor = guardianRoot.Position
		state.huntLastProgressAt = 1
		state.huntRecoveryAttempted = false
		ownerRoot.Position = origin + Vector3.new(1200, 0, 0)
		Tactics.step(state, 2, api)
		check("Owner movement does not replace a living locked target", state.combatTarget == locked)
		Tactics.step(state, 13, api)
		check("Melee no-hit starts one bounded recovery", state.huntRecoveryAttempted == true and state.huntRecoveryUntil == 19)
		-- A real four-stud movement inside the test fixture cancels recovery.
		state.combatTarget = alternate
		state.huntMeleeSince = nil
		state.huntProgressAnchor = guardianRoot.Position
		state.huntRecoveryUntil = 20
		state.huntRecoveryAttempted = true
		guardianRoot.Position += Vector3.new(4, 0, 0)
		Tactics.step(state, 14, api)
		check("Four-stud recovery progress cancels its deadline", state.combatTarget == alternate and state.huntRecoveryUntil == nil)
		guardianRoot.Position -= Vector3.new(4, 0, 0)
		state.combatTarget = locked
		state.huntProgressAnchor = guardianRoot.Position
		state.huntRecoveryUntil = 19
		state.huntRecoveryAttempted = true
		Tactics.step(state, 20, api)
		check("Recovery expiry skips target for the existing cooldown", state.combatTarget == nil and (state.failedTargets[locked] or 0) > 20)

		-- A synchronous kill establishes the original fixed clear centre. Killing
		-- a nearby sweep target must never shift that centre.
		local firstKill, firstRoot, firstHumanoid = actor("FirstKill", guardianRoot.Position + Vector3.new(7, 0, 0), 100)
		local localKill, localRoot, localHumanoid = actor("LocalKill", guardianRoot.Position - Vector3.new(5, 0, 0), 100)
		local function lethalDamage(_, target, amount)
			local h = target:FindFirstChildOfClass("Humanoid")
			local before = h.Health
			h:TakeDamage(amount)
			return before - h.Health
		end
		Tactics.reset(state)
		ownerRoot.Position = origin
		api = apiFor(ownerRoot, { firstKill, localKill }, lethalDamage)
		Tactics.step(state, 40, api)
		Tactics.step(state, 41, api)
		local firstCentre = state.huntSweepCenter
		check("Synchronous hunt kill saves its initial sweep centre", firstCentre == firstRoot.Position)
		Tactics.step(state, 42, api)
		Tactics.step(state, 43, api)
		check("Local sweep kill retains its original 70-stud centre", state.huntSweepCenter == firstCentre and localHumanoid.Health <= 0,
			{ center = tostring(state.huntSweepCenter), original = tostring(firstCentre), hp = localHumanoid.Health,
				target = state.combatTarget and state.combatTarget.Name, strikeAt = state.nextStrikeAt })

		-- Gang members keep using the central combat cadence when their leader is
		-- in Hunt. They follow the leader target rather than picking their own.
		local gangModel, gangRoot, gangHumanoid = actor("GangGuardian", guardianRoot.Position + Vector3.new(30, 0, 0))
		local gangTarget, gangTargetRoot = actor("GangTarget", gangRoot.Position + Vector3.new(7, 0, 0), 10000)
		local gangHits = 0
		local gangApi = apiFor(ownerRoot, { gangTarget }, function()
			gangHits += 1
			return 1
		end)
		gangApi.release = function(member) member.mode = "unbonded" end
		local leader = { model = guardian, humanoid = guardianHumanoid, mode = "pet", combatTarget = gangTarget, targetPriority = "hunt" }
		local member = { model = gangModel, humanoid = gangHumanoid, mode = "gang", gangLeader = leader, gangSlot = 1, gangUntil = 100 }
		Tactics.step(member, 50, gangApi)
		Tactics.step(member, 50.1, gangApi)
		check("Gang Hunt target keeps one guardian cooldown", gangHits == 1 and member.combatTarget == gangTarget, gangHits)

		-- Losing a character pauses hunting but never changes its selected mode.
		Tactics.reset(state)
		state.petBehavior = "Hunt"
		local noOwnerApi = apiFor(nil, { alternate }, function() return 0 end)
		Tactics.step(state, 60, noOwnerApi)
		check("Missing owner pauses without changing Hunt mode", state.petBehavior == "Hunt" and state.combatTarget == nil)
		local replacementOwner, replacementRoot = actor("ReplacementOwner", origin + Vector3.new(10, 0, 0), 100)
		Tactics.step(state, 61, apiFor(replacementRoot, { alternate }, function() return 0 end))
		check("Replacement owner resumes with Hunt mode intact", state.petBehavior == "Hunt")

		Tactics.setBehavior(state, "Hunt")
		state.huntSweepCenter = farRoot.Position
		Tactics.reset(state)
		check("Owner-path reset preserves selected Hunt behavior", state.petBehavior == "Hunt" and state.huntSweepCenter == nil)
		Tactics.setBehavior(state, "Follow")
		check("Follow command clears hunt target without changing pet lifecycle", state.petBehavior == "Follow" and state.mode == "pet" and state.combatTarget == nil)
	end, debug.traceback)
	folder:Destroy()
	if not ok then check("Test harness completed", false, err) end
	return results
end

-- Run as a temporary ModuleScript in Studio Play, server context.
-- Creates only isolated test fixtures. Never repositions existing world actors.
return function()
	assert(game:GetService("RunService"):IsRunning(), "Play test only")
	local ss = game:GetService("ServerScriptService")
	local Tactics = require(ss.GuardianTactics)
	local Nav = require(ss.GuardianNavigation)
	local Manager = require(game.ReplicatedStorage.MonsterManager)
	local origin = Vector3.new(10000, 1000, 10000)
	local folder = Instance.new("Folder")
	folder.Name = "GuardianIsolatedTest"
	folder.Parent = workspace
	local states, results = {}, {}
	local function check(name, condition, details)
		table.insert(results, {name = name, passed = condition == true, details = details})
	end
	local function part(name, pos, size, collide)
		local p = Instance.new("Part")
		p.Name = name; p.Anchored = true; p.CanCollide = collide
		p.Size = size; p.Position = pos; p.Parent = folder
		return p
	end
	part("Floor", origin - Vector3.yAxis, Vector3.new(250, 2, 250), true)
	local original
	for _, m in workspace:GetDescendants() do
		if m:IsA("Model") and m.Name == "weird monster thing" and m:FindFirstChild("HumanoidRootPart") then
			original = m; break
		end
	end
	assert(original, "WMT template missing")
	local function rig(offset)
		local m = original:Clone()
		m.Name = "GuardianTestRig"
		for _, d in m:GetDescendants() do
			if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("BodyMover") then d:Destroy() end
		end
		local h = m:FindFirstChildOfClass("Humanoid")
		local root = m.HumanoidRootPart
		local height = h.HipHeight + root.Size.Y / 2
		local shift = origin + offset + Vector3.yAxis * (height + 0.3) - root.Position
		m:PivotTo(m:GetPivot() + shift) -- Initial spawn, before entering Workspace.
		for _, d in m:GetDescendants() do if d:IsA("BasePart") then d.Anchored = false end end
		h.MaxHealth = 800; h.Health = 800; h.AutoRotate = true; h.Sit = false; h.PlatformStand = false
		m.Parent = folder
		root:SetNetworkOwner(nil)
		local state = { model = m, humanoid = h, mode = "pet", agentHeight = 19, agentRadius = 2.5 }
		table.insert(states, state)
		return state, root
	end
	local function enemy(pos, hp)
		local m = Instance.new("Model"); m.Name = "GuardianTestEnemy"
		local p = Instance.new("Part"); p.Name = "HumanoidRootPart"; p.Anchored = true
		p.CanCollide = false; p.Position = pos; p.Parent = m
		local h = Instance.new("Humanoid"); h.RequiresNeck = false; h.MaxHealth = hp; h.Health = hp; h.Parent = m
		m.Parent = folder
		return m, h
	end
	local owner = {UserId = -999, Parent = game.Players}
	local ownerPart = part("Owner", origin + Vector3.new(40, 3, 0), Vector3.one, false)
	local targets, hits, statuses = {}, 0, 0
	local api = {
		root = function(m) return m and m:FindFirstChild("HumanoidRootPart") end,
		humanoid = function(m) return m and m:FindFirstChildOfClass("Humanoid") end,
		ownerRoot = function() return ownerPart end,
		eligible = function(m) return m.Parent ~= nil and m:FindFirstChildOfClass("Humanoid").Health > 0 end,
		nearby = function(pos, radius)
			local list = {}
			for _, m in targets do
				if m.Parent and m:FindFirstChildOfClass("Humanoid").Health > 0
					and (m.HumanoidRootPart.Position - pos).Magnitude <= radius then table.insert(list, m) end
			end
			return list
		end,
		damage = function(_, target, amount)
			local h = target:FindFirstChildOfClass("Humanoid"); local before = h.Health
			h:TakeDamage(amount); hits += 1; return before - h.Health
		end,
		invite = function() return 0 end,
		release = function(s) s.mode = "unbonded"; Nav.stop(s) end,
		status = {FireClient = function() statuses += 1 end},
	}
	local function run(state, seconds, done)
		local untilTime = os.clock() + seconds
		repeat
			Tactics.step(state, os.clock(), api)
			if done and done() then break end
			task.wait(0.1)
		until os.clock() >= untilTime
	end
	local ok, err = xpcall(function()
		local s, root = rig(Vector3.zero); s.owner = owner
		task.wait(1)
		local start = root.Position
		run(s, 5, function() return s.tacticalState == "Cover" end)
		local function diagnostics(st, r)
			local n=st.navigation
			return {position=tostring(r.Position), speed=st.humanoid.WalkSpeed, hstate=st.humanoid:GetState().Name,
				feet=r.Position.Y-st.humanoid.HipHeight-r.Size.Y/2, target=st.combatTarget and st.combatTarget.Name,
				nav=n and {failures=n.failures,index=n.index,count=n.waypoints and #n.waypoints,
					command=tostring(n.command),reason=n.reason,computing=n.computing}}
		end
		check("Actual tall rig follows owner", (root.Position - start).Magnitude > 15, diagnostics(s, root))
		check("Arrives at escort slot", s.tacticalState == "Cover", s.tacticalState)
		local zombie, hum = enemy(root.Position + Vector3.new(6, -6, 0), 90)
		targets = {zombie}; run(s, 0.3)
		check("One strike kills base zombie at tall-rig height", hum.Health == 0, hum.Health)
		zombie:Destroy() -- Death safety can make corpses collidable; don't overlap the next fixture.
		local z2, h2 = enemy(root.Position + Vector3.new(6, -6, 0), 270)
		targets = {z2}; s.nextStrikeAt = 0
		run(s, 0.3)
		check("Stronger generation survives first strike", h2.Health == 120, {hp=h2.Health,diag=diagnostics(s,root),enemy=tostring(z2.HumanoidRootPart.Position)})
		run(s, 1)
		check("Second cooldown-gated strike finishes target", h2.Health == 0, h2.Health)
		z2:Destroy()
		targets = {}
		local oldOwner = ownerPart
		ownerPart = nil; run(s, 0.2)
		check("Owner death retains bond", s.owner == owner and s.mode == "pet")
		ownerPart = part("RespawnedOwner", root.Position + Vector3.new(-45, -6, 0), Vector3.one, false)
		start = root.Position; run(s, 4)
		check("New character triggers rejoin movement", s.lastOwnerRoot == ownerPart and (root.Position - start).Magnitude > 15)
		ownerPart.Position += Vector3.new(300, 0, 0) -- Test marker, not a living actor.
		run(s, 0.2)
		check("Distant portal departure holds locally", s.tacticalState == "HoldAndHunt")
		local remoteZombie, rh = enemy(root.Position + Vector3.new(6, -6, 0), 90)
		targets = {remoteZombie}; s.nextStrikeAt = 0; run(s, 0.3)
		check("Hunts locally while owner is distant", rh.Health == 0)
		targets = {}
		ownerPart.Position = root.Position + Vector3.new(45, -6, 0)
		run(s, 0.2)
		check("Returning owner resumes escort", s.tacticalState == "Follow" or s.tacticalState == "Regroup")
		Nav.stop(s)
		-- Fresh clone facing a wide glass wall; all hits must remain blocked.
		local blocked, br = rig(Vector3.new(-75, 0, -75)); blocked.owner = owner
		ownerPart.Position = origin + Vector3.new(-75, 3, -85)
		local glass = part("Glass", origin + Vector3.new(-71, 12, -75), Vector3.new(1, 24, 70), true)
		glass.Transparency = 0.7; glass.Material = Enum.Material.Glass
		local behind, bh = enemy(origin + Vector3.new(-67, 3, -75), 90); targets = {behind}
		task.wait(0.5); local before = hits
		run(blocked, 0.2)
		check("Glass blocks melee despite attack range", bh.Health == 90 and hits == before)
		blocked.lastSuccessfulHitAt = os.clock() - 11
		run(blocked, 0.2)
		check("Failed target is excluded instead of endless chase", (blocked.failedTargets[behind] or 0) > os.clock())
		Nav.stop(blocked)
		-- Isolate the path controller: it must go around, not through, glass.
		local startBlocked = br.Position; local goal = origin + Vector3.new(-55, 0, -75)
		blocked.humanoid.WalkSpeed = 28
		local deadline = os.clock() + 12
		local result
		repeat result = Nav.move(blocked, br, goal, "glass-route", os.clock()); task.wait(0.1)
		until result == "arrived" or result == "failed" or os.clock() > deadline
		check("Walks real path around glass", result == "arrived", {result=result,diag=diagnostics(blocked,br)})
		Nav.stop(blocked)
		-- A real moving zombie rig, with only this harness owning its movement.
		local zombieTemplate
		for _, m in workspace:GetDescendants() do
			if m:IsA("Model") and m.Name == "Drooling Zombie" and m:FindFirstChild("HumanoidRootPart")
				and m:FindFirstChildOfClass("Humanoid") and m:FindFirstChildOfClass("Humanoid").Health > 0 then
				zombieTemplate = m; break
			end
		end
		assert(zombieTemplate, "Moving zombie fixture unavailable")
		local runner = zombieTemplate:Clone(); runner.Name = "GuardianTestRunner"
		for _, d in runner:GetDescendants() do
			-- Cloned RepulsionForce is a snapshot of live zombie avoidance, not part of this test.
			if d:IsA("BaseScript") or d:IsA("Sound") or d:IsA("BodyMover") then d:Destroy() end
		end
		local runnerRoot = runner.HumanoidRootPart; local runnerHum = runner:FindFirstChildOfClass("Humanoid")
		local shift = origin + Vector3.new(-30, runnerHum.HipHeight + runnerRoot.Size.Y/2 + 0.3, 50) - runnerRoot.Position
		runner:PivotTo(runner:GetPivot() + shift)
		for _, d in runner:GetDescendants() do if d:IsA("BasePart") then d.Anchored = false end end
		runnerHum.MaxHealth = 90; runnerHum.Health = 90; runnerHum.WalkSpeed = 10
		runner.Parent = folder; runnerRoot:SetNetworkOwner(nil)
		local hunter, hr = rig(Vector3.new(-65, 0, 50)); hunter.owner = owner
		ownerPart.Position = origin + Vector3.new(-500, 3, 50)
		targets = {runner}; task.wait(0.5)
		local runnerStart = runnerRoot.Position
		runnerHum:MoveTo(origin + Vector3.new(90, 0, 50))
		run(hunter, 8, function() return runnerHum.Health <= 0 end)
		check("Intercepts and kills a moving zombie", runnerHum.Health == 0 and (runnerRoot.Position-runnerStart).Magnitude > 3,
			{hp=runnerHum.Health,ran=(runnerRoot.Position-runnerStart).Magnitude,guardian=diagnostics(hunter,hr)})
		Nav.stop(hunter)
		local member = {model = blocked.model, humanoid = blocked.humanoid, mode = "gang", gangLeader = s,
			gangSlot = 1, gangUntil = os.clock() - 1}
		Tactics.step(member, os.clock(), api)
		check("Expired gang member is released", member.mode == "unbonded")
		-- Real canonical damage path, without inserting a round-tracked world monster.
		local canonical = Instance.new("Model"); canonical.Name = "Drooling Zombie"
		local ch = Instance.new("Humanoid"); ch.RequiresNeck = false; ch.MaxHealth = 90; ch.Health = 90; ch.Parent = canonical
		canonical.Parent = game.ServerStorage
		local dealt = Manager.damageMonsterTarget(canonical, 150, s.model)
		check("Canonical monster damage kills 90 HP zombie", dealt == 90 and ch.Health == 0)
		canonical:Destroy()
		check("Status announcements are rate limited", statuses <= 8, statuses)
	end, debug.traceback)
	for _, state in states do Nav.stop(state) end
	folder:Destroy()
	if not ok then check("Test harness completed", false, err) end
	return results
end

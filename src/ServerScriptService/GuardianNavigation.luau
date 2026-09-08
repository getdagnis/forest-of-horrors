-- Used only by GuardianMonsterSystem. All movement is through Humanoid.
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")
local Navigation = {}
local pendingComputations = 0
local MAX_COMPUTATIONS = 3

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function disconnectRoute(nav)
	if nav.blockedConnection then nav.blockedConnection:Disconnect(); nav.blockedConnection = nil end
	if nav.moveConnection then nav.moveConnection:Disconnect(); nav.moveConnection = nil end
	if nav.path then nav.path:Destroy(); nav.path = nil end
	nav.waypoints = nil
	nav.command = nil
	nav.waypointAt = nil
end

function Navigation.reset(state)
	local nav = state.navigation
	if nav then
		nav.cancelled = true
		disconnectRoute(nav)
	end
	state.navigation = nil
end

function Navigation.stop(state)
	Navigation.reset(state)
	if state.humanoid.Parent then state.humanoid:Move(Vector3.zero) end
end

-- Collision-aware ray: transparent glass must still block movement and melee.
function Navigation.clear(model, origin, destination, ignoredTarget)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoredTarget and { model, ignoredTarget } or { model }
	params.RespectCanCollide = true
	return Workspace:Raycast(origin, destination - origin, params) == nil
end

local function canWalkDirect(state, root, destination)
	local feet = root.Position - Vector3.new(0, state.humanoid.HipHeight + root.Size.Y / 2, 0)
	local delta = destination - feet
	if math.abs(delta.Y) > 3 or flat(delta).Magnitude > 45 then return false end
	local side = flat(delta):Cross(Vector3.yAxis)
	if side.Magnitude > 0 then side = side.Unit * 2.5 end
	for _, offset in ipairs({ Vector3.zero, side, -side }) do
		for _, height in ipairs({ 2, state.humanoid.HipHeight + root.Size.Y / 2, (state.agentHeight or 18) - 1 }) do
			local lift = Vector3.new(0, height, 0)
			if not Navigation.clear(state.model, feet + offset + lift, destination + offset + lift) then return false end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { state.model }
	params.RespectCanCollide = true
	-- Sample the corridor so a clear chest-height ray doesn't mean walking off a roof.
	local samples = math.max(1, math.ceil(flat(delta).Magnitude / 4))
	for i = 1, samples do
		local at = feet:Lerp(destination, i / samples)
		local floor = Workspace:Raycast(at + Vector3.new(0, 2, 0), Vector3.new(0, -5, 0), params)
		if not floor or floor.Material == Enum.Material.Water
			or floor.Material == Enum.Material.CrackedLava then return false end
	end
	return true
end

function Navigation.findClearFallback(state, root, towardPosition)
	local toward = flat(towardPosition - root.Position)
	if toward.Magnitude < 0.01 then toward = flat(root.CFrame.LookVector) end
	if toward.Magnitude < 0.01 then toward = Vector3.zAxis end
	toward = toward.Unit
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Exclude
	floorParams.FilterDescendantsInstances = { state.model }
	floorParams.RespectCanCollide = true
	for _, radius in ipairs({ 10, 16 }) do
		for _, angle in ipairs({ 0, math.rad(45), math.rad(-45), math.rad(90), math.rad(-90), math.pi }) do
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(toward)
			local candidate = root.Position + direction * radius
			local ground = Workspace:Raycast(candidate + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), floorParams)
			if ground and ground.Material ~= Enum.Material.Water and ground.Material ~= Enum.Material.CrackedLava
				and canWalkDirect(state, root, ground.Position)
			then
				return ground.Position
			end
		end
	end
	return nil
end

local function fail(nav, now, reason)
	disconnectRoute(nav)
	nav.failures += 1
	nav.retryAt = now + 0.6
	nav.lastProgressAt = now
	nav.reason = reason
	nav.forcePathUntil = now + 4
	if nav.failures >= 2 then nav.failed = true end
end

local function command(state, nav, position, now, jump)
	if jump then state.humanoid.Jump = true end
	if not nav.command or (nav.command - position).Magnitude > 0.5 or now - (nav.commandAt or 0) > 1 then
		nav.command = position
		nav.commandAt = now
		nav.moveFailed = false
		state.humanoid:MoveTo(position)
	end
end

function Navigation.move(state, root, destination, key, now)
	local feet = root.Position - Vector3.new(0, state.humanoid.HipHeight + root.Size.Y / 2, 0)
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Exclude
	floorParams.FilterDescendantsInstances = { state.model }
	-- Do not project an intercept/escort goal onto the target character itself.
	if typeof(key) == "Instance" then
		local ignored = key:IsA("Model") and key or key:FindFirstAncestorOfClass("Model")
		if ignored then floorParams.FilterDescendantsInstances = { state.model, ignored } end
	end
	floorParams.RespectCanCollide = true
	local ground = Workspace:Raycast(destination + Vector3.new(0, 2, 0), Vector3.new(0, -25, 0), floorParams)
	if ground then destination = ground.Position end
	local nav = state.navigation
	if not nav or nav.key ~= key then
		Navigation.reset(state)
		nav = { key = key, failures = 0, retryAt = 0, lastProgressAt = now,
			lastPosition = root.Position, createdAt = now, computedAt = -math.huge }
		state.navigation = nav
	end
	if nav.failed then return "failed", nav.reason end
	if (flat(root.Position - destination)).Magnitude < 2.5 and math.abs(feet.Y - destination.Y) < 3 then
		Navigation.stop(state)
		return "arrived"
	end

	if flat(root.Position - nav.lastPosition).Magnitude > 1.5 then
		nav.lastPosition = root.Position
		nav.lastProgressAt = now
		nav.failures = 0
	end
	if nav.command and (nav.moveFailed or now - nav.lastProgressAt > 2.5 or now - (nav.waypointAt or now) > 6) then
		fail(nav, now, "no movement progress")
		state.humanoid:Move(Vector3.zero)
		return nav.failed and "failed" or "retry"
	end
	if now < nav.retryAt then return "retry" end

	if now >= (nav.forcePathUntil or 0) and canWalkDirect(state, root, destination) then
		-- Keep failure history even if a moving destination changes every tick.
		if nav.path then disconnectRoute(nav) end
		command(state, nav, destination, now, false)
		return "moving"
	end
	if nav.blocked then
		nav.blocked = false
		fail(nav, now, "path blocked")
		return nav.failed and "failed" or "retry"
	end

	local movedGoal = nav.destination and (nav.destination - destination).Magnitude > 8
	if not nav.computing and (not nav.waypoints or (movedGoal and now - nav.computedAt >= 1.25)) then
		if pendingComputations >= MAX_COMPUTATIONS then return "waiting" end
		nav.computing = true
		pendingComputations += 1
		local goal = destination
		task.spawn(function()
			local path
			local ok = pcall(function()
				path = PathfindingService:CreatePath({
					AgentRadius = state.agentRadius or 2.5, AgentHeight = state.agentHeight or 18, AgentCanJump = true,
					WaypointSpacing = 4, Costs = { Water = math.huge, CrackedLava = math.huge },
				})
				path:ComputeAsync(feet + Vector3.new(0, 2, 0), goal + Vector3.new(0, 2, 0))
			end)
			pendingComputations -= 1
			nav.computing = false
			if nav.cancelled or state.navigation ~= nav or not root.Parent or state.humanoid.Health <= 0 then
				if path then path:Destroy() end
				return
			end
			if not ok or not path or path.Status ~= Enum.PathStatus.Success then
				if path then path:Destroy() end
				fail(nav, os.clock(), "no route")
				return
			end
			disconnectRoute(nav)
			nav.path = path
			nav.waypoints = path:GetWaypoints()
			nav.index = math.min(2, #nav.waypoints)
			nav.destination = goal
			nav.computedAt = os.clock()
			nav.waypointAt = os.clock()
			nav.lastProgressAt = os.clock()
			nav.blockedConnection = path.Blocked:Connect(function(index)
				if index >= nav.index then nav.blocked = true end
			end)
			nav.moveConnection = state.humanoid.MoveToFinished:Connect(function(reached)
				if not reached and nav.command then nav.moveFailed = true end
			end)
		end)
	end
	if nav.waypoints then
		local waypoint = nav.waypoints[nav.index]
		if waypoint and flat(root.Position - waypoint.Position).Magnitude <= 2.5
			and math.abs(feet.Y - waypoint.Position.Y) <= 3 then
			nav.index += 1
			nav.waypointAt = now
			waypoint = nav.waypoints[nav.index]
		end
		if waypoint then
			command(state, nav, waypoint.Position, now, waypoint.Action == Enum.PathWaypointAction.Jump)
		else
			disconnectRoute(nav) -- Goal moved; request a fresh path next tick.
		end
	end
	return nav.computing and "waiting" or "moving"
end

return Navigation

-- Zombie navigation owns only Humanoid movement intent. It never corrects a
-- living zombie's position or physics; an unreachable destination is abandoned.
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local PathfindingUtility = {}
local DESTINATION_REFRESH_DISTANCE = 8
local WAYPOINT_REACHED_DISTANCE = 2.5
local PATH_RETRY_DELAY = 0.75
local STUCK_TIMEOUT = 3

local function flatDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

function PathfindingUtility.new()
	local this = {}
	local route = nil

	local function clearRoute()
		if not route then return end
		route.cancelled = true
		if route.blockedConnection then route.blockedConnection:Disconnect() end
		if route.moveConnection then route.moveConnection:Disconnect() end
		if route.path then route.path:Destroy() end
		route = nil
	end

	local function clearPath(state)
		if state.blockedConnection then state.blockedConnection:Disconnect(); state.blockedConnection = nil end
		if state.moveConnection then state.moveConnection:Disconnect(); state.moveConnection = nil end
		if state.path then state.path:Destroy(); state.path = nil end
		state.waypoints = nil
		state.index = nil
	end

	local function projectToFloor(character, destination)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true
		local hit = Workspace:Raycast(destination + Vector3.new(0, 12, 0), Vector3.new(0, -36, 0), params)
		return hit and hit.Position or destination
	end

	local function command(humanoid, state, waypoint)
		if waypoint.Action == Enum.PathWaypointAction.Jump then humanoid.Jump = true end
		if not state.command or (state.command - waypoint.Position).Magnitude > 0.5 then
			state.command = waypoint.Position
			state.commandAt = time()
			state.moveFailed = false
			humanoid:MoveTo(waypoint.Position)
		end
	end

	function this:Abandon()
		clearRoute()
	end

	function this:MoveToTarget(character, destination)
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then return "invalid" end

		destination = projectToFloor(character, destination)
		if flatDistance(root.Position, destination) <= WAYPOINT_REACHED_DISTANCE then
			clearRoute()
			return "arrived"
		end

		local now = time()
		if not route or flatDistance(route.destination, destination) > DESTINATION_REFRESH_DISTANCE then
			clearRoute()
			route = { destination = destination, lastPosition = root.Position, lastProgressAt = now, retryAt = 0 }
		end

		if route.blocked or route.moveFailed or now - route.lastProgressAt >= STUCK_TIMEOUT then
			if route.path then
				-- Drop the blocked path before recomputing. Do not force the zombie
				-- through it with a direct MoveTo or a position correction.
				clearPath(route)
			end
			route.blocked = false
			route.moveFailed = false
			route.command = nil
			route.retryAt = now + PATH_RETRY_DELAY
			route.lastPosition = root.Position
			route.lastProgressAt = now
			humanoid:Move(Vector3.zero)
		end

		if flatDistance(root.Position, route.lastPosition) >= 1.5 then
			route.lastPosition = root.Position
			route.lastProgressAt = now
		end

		if not route.path and now >= route.retryAt then
			local path = PathfindingService:CreatePath({
				AgentRadius = 2.5,
				AgentHeight = 8,
				AgentCanJump = true,
				WaypointSpacing = 4,
			})
			local ok = pcall(function()
				path:ComputeAsync(root.Position + Vector3.new(0, 2, 0), destination + Vector3.new(0, 2, 0))
			end)
			if not ok or path.Status ~= Enum.PathStatus.Success then
				path:Destroy()
				route.retryAt = now + PATH_RETRY_DELAY
				return "blocked"
			end

			route.path = path
			route.waypoints = path:GetWaypoints()
			route.index = math.min(2, #route.waypoints)
			route.blockedConnection = path.Blocked:Connect(function(index)
				if route and index >= (route.index or 1) then route.blocked = true end
			end)
			route.moveConnection = humanoid.MoveToFinished:Connect(function(reached)
				if route and route.command and not reached then route.moveFailed = true end
			end)
		end

		local waypoint = route.waypoints and route.waypoints[route.index]
		if waypoint and flatDistance(root.Position, waypoint.Position) <= WAYPOINT_REACHED_DISTANCE then
			route.index += 1
			waypoint = route.waypoints[route.index]
		end
		if waypoint then
			command(humanoid, route, waypoint)
			return "moving"
		end

		clearRoute()
		return "arrived"
	end

	return this
end

return PathfindingUtility

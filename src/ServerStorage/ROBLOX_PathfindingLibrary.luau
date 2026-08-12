local PathfindingService = game:GetService("PathfindingService")

pcall(function()
	PathfindingService.EmptyCutoff = 0.3
end)

local PathfindingUtility = {}
local TargetOffsetMax = 10
local JumpThreshold = 1.5
local NextPointThreshold = 4

function PathfindingUtility.new()
	local this = {}

	local lastTargetPos = Vector3.new(math.huge, math.huge, math.huge)
	local path = nil
	local currentPointIndex = 1

	function this:MoveToTarget(character, target)
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		if not root or not humanoid then
			return
		end

		local targetOffset = (lastTargetPos - target).Magnitude

		if targetOffset > TargetOffsetMax then
			local startPoint = root.Position
			local humanoidState = humanoid:GetState()

			if humanoidState == Enum.HumanoidStateType.Jumping or humanoidState == Enum.HumanoidStateType.Freefall then
				local ray = Ray.new(root.Position, Vector3.new(0, -100, 0))
				local _, hitPoint = workspace:FindPartOnRay(ray, character)

				if hitPoint then
					startPoint = hitPoint
				end
			end

			local newTarget = target
			local ray = Ray.new(target + Vector3.new(0, -3, 0), Vector3.new(0, -100, 0))
			local _, hitPoint = workspace:FindPartOnRay(ray, character)

			if hitPoint and (hitPoint - target).Magnitude > 4 then
				newTarget = newTarget * Vector3.new(1, 0, 1) + Vector3.new(0, 3, 0)
			end

			path = PathfindingService:ComputeSmoothPathAsync(startPoint, newTarget, 500)
			currentPointIndex = 1
			lastTargetPos = target
		end

		if path then
			local points = path:GetPointCoordinates()

			if currentPointIndex < #points then
				local currentPoint = points[currentPointIndex]
				local distance = (root.Position - currentPoint).Magnitude

				if distance < NextPointThreshold then
					currentPointIndex += 1
				end

				humanoid:MoveTo(points[currentPointIndex])

				if points[currentPointIndex].Y - root.Position.Y > JumpThreshold then
					humanoid.Jump = true
				end
			else
				humanoid:MoveTo(target)
			end
		end
	end

	return this
end

return PathfindingUtility

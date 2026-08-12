local utility = {}

function utility:WideRayCast(start, target, offset, ignoreList)
	local parts = {}
	local direction = target - start

	local ray = Ray.new(start, direction)
	local part = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList)
	if part then table.insert(parts, part) end

	if direction.Magnitude <= 0 then
		return parts
	end

	local side = direction:Cross(Vector3.FromNormalId(Enum.NormalId.Top))
	if side.Magnitude <= 0 then
		return parts
	end

	local offsetVector = offset * side.Unit

	ray = Ray.new(start + offsetVector, direction + offsetVector)
	part = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList)
	if part then table.insert(parts, part) end

	ray = Ray.new(start - offsetVector, direction - offsetVector)
	part = workspace:FindPartOnRayWithIgnoreList(ray, ignoreList)
	if part then table.insert(parts, part) end

	return parts
end

function utility:FindNearestPathPoint(path, point, start)
	local occludePoint = path:CheckOcclusionAsync(point)
	if occludePoint > 0 then
		utility:WideRayCast(start)
	end
end

local maxForce = 15

function utility:GetRepulsionVector(unitPosition, otherUnitsPositions)
	local repulsionVector = Vector3.new(0, 0, 0)

	for _, other in pairs(otherUnitsPositions) do
		local fromOther = unitPosition - other

		if fromOther.Magnitude > 0 then
			fromOther = fromOther.Unit * 1000 / math.pow(fromOther.Magnitude + 1, 2)
			repulsionVector += fromOther
		end
	end

	return repulsionVector * maxForce
end

function utility:GetIdleState(StateMachine)
	local IdleState = StateMachine.NewState()
	IdleState.Name = "Idle"
	IdleState.Action = function() end
	IdleState.Init = function() end
	return IdleState
end

function utility:GetClosestVisibleTarget(npcModel, characters, ignoreList, fieldOfView)
	local npcRoot = npcModel:FindFirstChild("HumanoidRootPart")
	if not npcRoot then return nil end

	local closestTarget = nil
	local closestDistance = math.huge

	for _, character in pairs(characters) do
		local root = character:FindFirstChild("HumanoidRootPart")

		if root then
			local toTarget = root.Position - npcRoot.Position
			local flatTarget = Vector3.new(toTarget.X, 0, toTarget.Z)

			if flatTarget.Magnitude > 0.1 then
				local dot = math.clamp(flatTarget.Unit:Dot(npcRoot.CFrame.LookVector), -1, 1)
				local angle = math.deg(math.acos(dot))

				if angle < fieldOfView then
					local targetRay = Ray.new(npcRoot.Position, toTarget)
					local part = workspace:FindPartOnRayWithIgnoreList(targetRay, ignoreList)

					if part and part:IsDescendantOf(character) and toTarget.Magnitude < closestDistance then
						closestTarget = character
						closestDistance = toTarget.Magnitude
					end
				end
			end
		end
	end

	return closestTarget
end

local function isSpaceEmpty(position)
	local region = Region3.new(position - Vector3.new(2, 2, 2), position + Vector3.new(2, 2, 2))
	return workspace:IsRegion3Empty(region)
end

function utility:FindCloseEmptySpace(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	for _ = 1, 10 do
		local xoff = math.random(5, 10) * (math.random() > 0.5 and 1 or -1)
		local zoff = math.random(5, 10) * (math.random() > 0.5 and 1 or -1)
		local targetPos = Vector3.new(root.Position.X + xoff, root.Position.Y, root.Position.Z + zoff)

		if isSpaceEmpty(targetPos) then
			return targetPos
		end

		targetPos += Vector3.new(0, 4, 0)

		if isSpaceEmpty(targetPos) then
			return targetPos
		end
	end

	return nil
end

return utility

-- AnchorScript for Tool with multiple BaseParts
local tool = script.Parent

local function isEquipped()
	local parent = tool.Parent
	return parent
		and parent:IsA("Model")
		and parent:FindFirstChildOfClass("Humanoid") ~= nil
end

local function isInBackpack()
	local parent = tool.Parent
	return parent and parent:IsA("Backpack")
end

local function updatePhysics()
	local equipped = isEquipped()
	local inBackpack = isInBackpack()
	local sittingInWorkspace = tool:IsDescendantOf(workspace) and not equipped and not inBackpack

	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = sittingInWorkspace
			part.CanCollide = false
			part.Massless = true

			if sittingInWorkspace and part.Name == "Handle" then
				part.CanTouch = true
			else
				part.CanTouch = false
			end
		end
	end
end

tool.AncestryChanged:Connect(updatePhysics)
tool.DescendantAdded:Connect(function(item)
	if item:IsA("BasePart") then
		task.defer(updatePhysics)
	end
end)

updatePhysics()
local humanoidList = {}
local storage = {}
local indices = {}

function humanoidList:GetCurrent()
	return storage
end

local function addHumanoid(instance)
	if not instance:IsA("Humanoid") or indices[instance] then return end

	table.insert(storage, instance)
	indices[instance] = #storage
end

local function removeHumanoid(instance)
	local index = indices[instance]
	if not index then return end

	local lastIndex = #storage
	local lastHumanoid = storage[lastIndex]
	storage[index] = lastHumanoid
	storage[lastIndex] = nil
	indices[instance] = nil

	if lastHumanoid ~= instance then
		indices[lastHumanoid] = index
	end
end

-- Build the initial shared cache once, then maintain the same dense array as
-- Workspace changes. Consumers retain GetCurrent's current-humanoid-list
-- contract without triggering a recursive Workspace scan every three seconds.
for _, instance in ipairs(workspace:GetDescendants()) do
	addHumanoid(instance)
end

workspace.DescendantAdded:Connect(addHumanoid)
workspace.DescendantRemoving:Connect(removeHumanoid)

return humanoidList

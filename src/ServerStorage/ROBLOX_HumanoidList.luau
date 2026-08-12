local humanoidList = {}
local storage = {}

function humanoidList:GetCurrent()
	return storage
end

local function findHumanoids(object, list)
	if object:IsA("Humanoid") then
		table.insert(list, object)
	end

	for _, child in pairs(object:GetChildren()) do
		findHumanoids(child, list)
	end
end

task.spawn(function()
	while true do
		storage = {}
		findHumanoids(workspace, storage)
		task.wait(3)
	end
end)

return humanoidList

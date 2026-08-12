local destroyService = {}
local destroyQueue = {}

function destroyService:AddItem(object, delaySeconds)
	local destroyObject = {
		object = object,
		destroyTime = os.time() + delaySeconds,
	}

	for index, storedObject in pairs(destroyQueue) do
		if destroyQueue[index].destroyTime > destroyObject.destroyTime then
			table.insert(destroyQueue, index, destroyObject)
			return true
		end
	end

	table.insert(destroyQueue, destroyObject)
	return true
end

task.spawn(function()
	while true do
		local now = os.time()

		for _, storedObject in pairs(destroyQueue) do
			if now >= storedObject.destroyTime then
				table.remove(destroyQueue, 1)

				if storedObject.object then
					storedObject.object:Destroy()
				end
			elseif now >= storedObject.destroyTime - 1 then
				if storedObject.object and storedObject.object:IsA("BasePart") then
					storedObject.object.Transparency += 1 / 30
				end
			else
				break
			end
		end

		task.wait()
	end
end)

return destroyService

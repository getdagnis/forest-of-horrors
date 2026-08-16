-- RadarTowerSystem: a seated player immediately receives the full-map radar.
-- Studio setup: set RadarTower=true on each tower Model, or directly on its
-- cockpit Seat/VehicleSeat. No console prompt is required.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local event = ReplicatedStorage:FindFirstChild("RadarTowerUse")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "RadarTowerUse"
	event.Parent = ReplicatedStorage
end

local boundSeats = {}
local playerSeats = {}

local function isTower(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:GetAttribute("RadarTower") == true then return true end
		current = current.Parent
	end
	return false
end

local function playerFromOccupant(occupant)
	local character = occupant and occupant.Parent
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function hidePlayer(player, seat)
	if playerSeats[player] ~= seat then return end
	playerSeats[player] = nil
	event:FireClient(player, false)
end

local function syncSeat(seat)
	local previousPlayer = boundSeats[seat]
	local player = playerFromOccupant(seat.Occupant)
	if previousPlayer and previousPlayer ~= player then
		hidePlayer(previousPlayer, seat)
	end

	boundSeats[seat] = player
	if player then
		local oldSeat = playerSeats[player]
		if oldSeat and oldSeat ~= seat then
			boundSeats[oldSeat] = nil
		end
		playerSeats[player] = seat
		event:FireClient(player, true)
	end
end

local function bindSeat(seat)
	if boundSeats[seat] ~= nil or seat:GetAttribute("RadarTowerBound") then return end
	if not isTower(seat) then return end

	seat:SetAttribute("RadarTowerBound", true)
	boundSeats[seat] = false
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		syncSeat(seat)
	end)
	seat.AncestryChanged:Connect(function(_, parent)
		if parent then return end
		local player = boundSeats[seat]
		if player then hidePlayer(player, seat) end
		boundSeats[seat] = nil
	end)
	task.defer(syncSeat, seat)
end

local function consider(instance)
	if instance:IsA("Seat") or instance:IsA("VehicleSeat") then
		bindSeat(instance)
	end
end

for _, instance in ipairs(Workspace:GetDescendants()) do consider(instance) end
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Seat") or instance:IsA("VehicleSeat") then
		task.defer(consider, instance)
	end
end)

-- Exit hides the overlay while the player remains seated. Re-seat to reopen.
event.OnServerEvent:Connect(function(player, enabled)
	if enabled ~= false then return end
	local seat = playerSeats[player]
	if seat then
		playerSeats[player] = nil
		boundSeats[seat] = false
	end
	event:FireClient(player, false)
end)

Players.PlayerRemoving:Connect(function(player)
	local seat = playerSeats[player]
	if seat then boundSeats[seat] = nil end
	playerSeats[player] = nil
end)

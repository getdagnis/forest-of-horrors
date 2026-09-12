-- RadarEventBus > ServerScriptService


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local event = ReplicatedStorage:FindFirstChild("RadarEvents")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "RadarEvents"
	event.Parent = ReplicatedStorage
end

local RadarEventBus = {}

function RadarEventBus.publish(payload)
	if type(payload) == "string" then
		if payload == "" then return end
		payload = { kind = "message", text = payload }
	end
	if type(payload) ~= "table" then return end
	payload.roundGeneration = tonumber(Workspace:GetAttribute("RoundGeneration")) or 0
	event:FireAllClients(payload)
end

return RadarEventBus

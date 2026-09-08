-- Temporary client-only logger for the McDonald's streaming/pause investigation.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local SAMPLE_INTERVAL = 0.2
local JUMP_DISTANCE = 50

local lastPosition
local elapsed = 0

local function rootPart()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function describeRoot()
	local root = rootPart()
	if not root then return "root=nil" end
	return string.format(
		"pos=(%.1f, %.1f, %.1f) vel=(%.1f, %.1f, %.1f)",
		root.Position.X, root.Position.Y, root.Position.Z,
		root.AssemblyLinearVelocity.X, root.AssemblyLinearVelocity.Y, root.AssemblyLinearVelocity.Z
	)
end

local function log(event)
	warn(string.format("[McDonaldsPauseDiag] %s | %.2f | %s", event, os.clock(), describeRoot()))
end

player:GetPropertyChangedSignal("GameplayPaused"):Connect(function()
	log("GameplayPaused=" .. tostring(player.GameplayPaused))
end)

player.CharacterAdded:Connect(function()
	lastPosition = nil
	log("CharacterAdded")
end)

player.CharacterRemoving:Connect(function()
	log("CharacterRemoving")
	lastPosition = nil
end)

RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < SAMPLE_INTERVAL then return end
	elapsed = 0

	local root = rootPart()
	if not root then
		lastPosition = nil
		return
	end

	local position = root.Position
	if lastPosition then
		local jump = (position - lastPosition).Magnitude
		if jump >= JUMP_DISTANCE then
			log(string.format("POSITION_JUMP distance=%.1f", jump))
		end
	end
	lastPosition = position
end)

log("diagnostics-ready")

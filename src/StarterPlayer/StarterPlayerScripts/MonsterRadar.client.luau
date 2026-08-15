-- MonsterRadar > StarterPlayerScripts Local
-- Local combat radar: no labels, no server work, and no wall-visibility rules.
-- It reports every living canonical monster within RADAR_RANGE around the player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local RADAR_RANGE = 50
local UPDATE_SECONDS = 0.12
local DOT_SIZE = 6
local MAX_DOTS = 96

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterRadarHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
gui.Parent = player:WaitForChild("PlayerGui")

local radar = Instance.new("Frame")
radar.Name = "Radar"
radar.AnchorPoint = Vector2.new(1, 0)
radar.Position = UDim2.new(1, -12, 0, 88)
radar.Size = UDim2.fromOffset(128, 128)
radar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
radar.BackgroundTransparency = 0.8
radar.BorderSizePixel = 0
radar.ClipsDescendants = true
radar.Parent = gui
local radarCorner = Instance.new("UICorner")
radarCorner.CornerRadius = UDim.new(1, 0)
radarCorner.Parent = radar
local radarStroke = Instance.new("UIStroke")
radarStroke.Color = Color3.fromRGB(82, 109, 132)
radarStroke.Transparency = 0.6
radarStroke.Parent = radar

-- Native GUI has no sector primitive. Stacked clipped strips form a real
-- forward fan from the player dot to 12 o'clock without an uploaded asset.
local sector = Instance.new("Folder")
sector.Name = "ForwardSector"
sector.Parent = radar
local SECTOR_STRIPS = 14
for index = 1, SECTOR_STRIPS do
	local progress = index / SECTOR_STRIPS
	local strip = Instance.new("Frame")
	strip.Name = "SectorStrip"
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Position = UDim2.new(0.5, 0, 0.5 - progress * 0.46, 0)
	strip.Size = UDim2.new(progress * 0.64, 0, 0.46 / SECTOR_STRIPS, 1)
	strip.BackgroundColor3 = Color3.fromRGB(105, 185, 230)
	strip.BackgroundTransparency = 0.91
	strip.BorderSizePixel = 0
	strip.ZIndex = 1
	strip.Parent = sector
end

local selfDot = Instance.new("Frame")
selfDot.Name = "PlayerDot"
selfDot.AnchorPoint = Vector2.new(0.5, 0.5)
selfDot.Position = UDim2.fromScale(0.5, 0.5)
selfDot.Size = UDim2.fromOffset(8, 8)
selfDot.BackgroundColor3 = Color3.fromRGB(117, 210, 255)
selfDot.BorderSizePixel = 0
selfDot.ZIndex = 3
selfDot.Parent = radar
local selfCorner = Instance.new("UICorner")
selfCorner.CornerRadius = UDim.new(1, 0)
selfCorner.Parent = selfDot

local dots = {}
for index = 1, MAX_DOTS do
	local dot = Instance.new("Frame")
	dot.Name = "MonsterDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	dot.BackgroundColor3 = Color3.fromRGB(238, 67, 70)
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 2
	dot.Parent = radar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	dots[index] = dot
end

local trackedMonsters = {}
local function track(instance)
	if instance:IsA("Model") and MonsterManager.getConfig(instance) then trackedMonsters[instance] = true end
end
for _, instance in ipairs(workspace:GetDescendants()) do track(instance) end
workspace.DescendantAdded:Connect(track)
workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("Model") then trackedMonsters[instance] = nil end
end)

local function getMonsterPosition(model)
	local part = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model.PrimaryPart
	if part and part:IsA("BasePart") then return part.Position end
	return nil
end

local function updateLayout()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
	local small = viewport.X < 800 or viewport.Y < 500
	radar.Size = UDim2.fromOffset(small and 92 or 128, small and 92 or 128)
	radar.Position = UDim2.new(1, -12, 0, small and 72 or 88)
end

local elapsed = UPDATE_SECONDS
RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < UPDATE_SECONDS then return end
	elapsed = 0
	updateLayout()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then
		for _, dot in ipairs(dots) do dot.Visible = false end
		return
	end

	local shown = 0
	for model in pairs(trackedMonsters) do
		local humanoid = model.Parent and MonsterManager.getMonsterHumanoid(model)
		local position = humanoid and humanoid.Health > 0 and getMonsterPosition(model)
		if position then
			local offset = position - root.Position
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			if flatOffset.Magnitude <= RADAR_RANGE and shown < MAX_DOTS then
				shown += 1
				local localOffset = camera.CFrame:VectorToObjectSpace(flatOffset)
				local scale = 0.43 / RADAR_RANGE
				dots[shown].Position = UDim2.fromScale(0.5 + localOffset.X * scale, 0.5 + localOffset.Z * scale)
				dots[shown].Visible = true
			end
		end
	end
	for index = shown + 1, MAX_DOTS do dots[index].Visible = false end
end)

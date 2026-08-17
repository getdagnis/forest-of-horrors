-- RadarTowerHud: a near-full-screen map while using a marked radar tower.
-- Mark any important Part or Model with radar_detect=true to add a faint,
-- static landmark marker. Workspace.RadarMapMin/RadarMapMax define map bounds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local useEvent = ReplicatedStorage:WaitForChild("RadarTowerUse")

warn("[RadarTowerHud] client started; waiting for RadarTowerUse")

-- Client-only audio preserves the imported ambience without broadcasting it
-- globally from a Sound parented under the old tower Model.
local AMBIENT_RANGE = 110
local AMBIENT_UPDATE_INTERVAL = 0.4

local gui = Instance.new("ScreenGui")
gui.Name = "RadarTowerHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")	
shade.Name = "Shade"
shade.BackgroundColor3 = Color3.fromRGB(1, 7, 16)
shade.BackgroundTransparency = 0.25
shade.Size = UDim2.fromScale(1, 1)
shade.BorderSizePixel = 0
shade.Parent = gui

local panel = Instance.new("Frame")
panel.Name = "MonsterRadar"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromScale(0.92, 0.88)
panel.BackgroundColor3 = Color3.fromRGB(3, 20, 45)
panel.BackgroundTransparency = 0.10
panel.BorderSizePixel = 0
panel.Parent = shade
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(14, 63, 104)
panelStroke.Transparency = 0.15
panelStroke.Thickness = 1
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(34, 16)
title.Size = UDim2.new(1, -220, 0, 72)
title.Font = Enum.Font.GothamBold
title.Text = "Monster Radar"
title.TextColor3 = Color3.fromRGB(246, 249, 255)
title.TextSize = 52
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Center
title.Parent = panel

local close = Instance.new("TextButton")
close.Name = "Exit"
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -34, 0, 16)
close.Size = UDim2.fromOffset(145, 72)
close.BackgroundTransparency = 1
close.Text = "Exit"
close.TextColor3 = Color3.fromRGB(255, 255, 255)
close.TextSize = 52
close.Font = Enum.Font.GothamBold
close.Parent = panel

local plot = Instance.new("Frame")
plot.Name = "Map"
plot.Position = UDim2.fromOffset(34, 104)
plot.Size = UDim2.new(1, -68, 1, -138)
plot.BackgroundColor3 = Color3.fromRGB(3, 15, 38)
plot.BackgroundTransparency = 0.12
plot.BorderSizePixel = 0
plot.ClipsDescendants = true
plot.Parent = panel
local plotStroke = Instance.new("UIStroke")
plotStroke.Color = Color3.fromRGB(243, 25, 111)
plotStroke.Transparency = 0.35
plotStroke.Thickness = 1
plotStroke.Parent = plot

-- The grid is intentionally geographic rather than decorative: it makes a
-- debugging callout such as "two squares north-east of McDonald's" practical.
local GRID_COLUMNS = 17
local GRID_ROWS = 13
for column = 1, GRID_COLUMNS - 1 do
	local line = Instance.new("Frame")
	line.Name = "GridV"
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.fromScale(column / GRID_COLUMNS, 0)
	line.Size = UDim2.new(0, 1, 1, 0)
	line.BackgroundColor3 = Color3.fromRGB(208, 27, 103)
	line.BackgroundTransparency = 0.64
	line.BorderSizePixel = 0
	line.Parent = plot
end
for row = 1, GRID_ROWS - 1 do
	local line = Instance.new("Frame")
	line.Name = "GridH"
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromScale(0, row / GRID_ROWS)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = Color3.fromRGB(208, 27, 103)
	line.BackgroundTransparency = 0.64
	line.BorderSizePixel = 0
	line.Parent = plot
end

local landmarkLayer = Instance.new("Folder")
landmarkLayer.Name = "Landmarks"
landmarkLayer.Parent = plot
local monsterLayer = Instance.new("Folder")
monsterLayer.Name = "Monsters"
monsterLayer.Parent = plot
local playerLayer = Instance.new("Folder")
playerLayer.Name = "OtherPlayers"
playerLayer.Parent = plot

local selfMarker = Instance.new("Frame")
selfMarker.Name = "You"
selfMarker.AnchorPoint = Vector2.new(0.5, 0.5)
selfMarker.Size = UDim2.fromOffset(17, 17)
selfMarker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
selfMarker.BorderSizePixel = 0
selfMarker.Parent = plot
Instance.new("UICorner", selfMarker).CornerRadius = UDim.new(1, 0)
local selfStroke = Instance.new("UIStroke")
selfStroke.Color = Color3.fromRGB(247, 35, 120)
selfStroke.Thickness = 2
selfStroke.Parent = selfMarker

local monsterDots = {}
local playerDots = {}
local landmarkMarkers = {}
local activeRadarLoop

local function mapBounds()
	local min = Workspace:GetAttribute("RadarMapMin")
	local max = Workspace:GetAttribute("RadarMapMax")
	if typeof(min) ~= "Vector3" or typeof(max) ~= "Vector3" then
		min, max = Vector3.new(-1725, 0, -1550), Vector3.new(275, 0, 450)
	end
	return min, max
end

local function mapPosition(worldPosition, min, max)
	local width = math.max(1, max.X - min.X)
	local depth = math.max(1, max.Z - min.Z)
	return UDim2.fromScale(
		math.clamp((worldPosition.X - min.X) / width, 0, 1),
		math.clamp(1 - (worldPosition.Z - min.Z) / depth, 0, 1)
	)
end

local function getMonsterDot(index)
	local dot = monsterDots[index]
	if dot then return dot end
	dot = Instance.new("Frame")
	dot.Name = "Monster"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(11, 11)
	dot.BackgroundColor3 = Color3.fromRGB(223, 27, 87)
	dot.BackgroundTransparency = 0.08
	dot.BorderSizePixel = 0
	dot.Parent = monsterLayer
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	monsterDots[index] = dot
	return dot
end

local function getPlayerDot(index)
	local dot = playerDots[index]
	if dot then return dot end
	dot = Instance.new("Frame")
	dot.Name = "Player"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.BackgroundColor3 = Color3.fromRGB(154, 160, 169)
	dot.BackgroundTransparency = 0.05
	dot.BorderSizePixel = 0
	dot.Parent = playerLayer
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	playerDots[index] = dot
	return dot
end

local function getLandmark(index)
	local marker = landmarkMarkers[index]
	if marker then return marker end
	marker = Instance.new("Frame")
	marker.Name = "Landmark"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Size = UDim2.fromOffset(15, 15)
	marker.BackgroundTransparency = 1
	marker.BorderSizePixel = 0
	marker.Parent = landmarkLayer
	local landmarkStroke = Instance.new("UIStroke")
	landmarkStroke.Color = Color3.fromRGB(95, 205, 220)
	landmarkStroke.Transparency = 0.35
	landmarkStroke.Thickness = 1
	landmarkStroke.Parent = marker
	landmarkMarkers[index] = marker
	return marker
end

local function markerPosition(instance)
	if instance:IsA("BasePart") then return instance.Position end
	if instance:IsA("Model") then return instance:GetPivot().Position end
	return nil
end

local function getTowerScreen(tower)
	if not (tower and tower:IsA("Model")) then return nil end
	for _, instance in ipairs(tower:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("RadarTowerScreen") == true then
			return instance
		end
	end
	return nil
end

local function getTowerSound(tower, soundName)
	local sound = tower and tower:FindFirstChild(soundName, true)
	return sound and sound:IsA("Sound") and sound or nil
end

local function setRadarLoop(tower, enabled)
	if activeRadarLoop then activeRadarLoop:Stop() end
	activeRadarLoop = nil
	if not enabled then return end
	local radarLoop = getTowerSound(tower, "RadarLoop")
	if radarLoop then
		radarLoop:Play()
		activeRadarLoop = radarLoop
	end
end

local refreshElapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	if not gui.Enabled then return end
	refreshElapsed += deltaTime
	if refreshElapsed < 0.35 then return end
	refreshElapsed = 0

	local min, max = mapBounds()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	selfMarker.Visible = root ~= nil
	if root then selfMarker.Position = mapPosition(root.Position, min, max) end

	local monsterCount = 0
	local playerCount = 0
	local landmarkCount = 0
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") and MonsterManager.getConfig(instance) then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			local monsterRoot = instance:FindFirstChild("HumanoidRootPart", true)
			if humanoid and humanoid.Health > 0 and monsterRoot and monsterRoot:IsA("BasePart") then
				monsterCount += 1
				local dot = getMonsterDot(monsterCount)
				dot.Position = mapPosition(monsterRoot.Position, min, max)
				dot.Visible = true
			end
		elseif instance:GetAttribute("radar_detect") == true then
			local position = markerPosition(instance)
			if position then
				landmarkCount += 1
				local marker = getLandmark(landmarkCount)
				marker.Position = mapPosition(position, min, max)
				marker.Visible = true
			end
		end
	end
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local otherCharacter = otherPlayer.Character
			local otherHumanoid = otherCharacter and otherCharacter:FindFirstChildOfClass("Humanoid")
			local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
			if otherHumanoid and otherHumanoid.Health > 0 and otherRoot and otherRoot:IsA("BasePart") then
				playerCount += 1
				local dot = getPlayerDot(playerCount)
				dot.Position = mapPosition(otherRoot.Position, min, max)
				dot.Visible = true
			end
		end
	end
	for index = monsterCount + 1, #monsterDots do monsterDots[index].Visible = false end
	for index = playerCount + 1, #playerDots do playerDots[index].Visible = false end
	for index = landmarkCount + 1, #landmarkMarkers do landmarkMarkers[index].Visible = false end
end)

local ambientElapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	ambientElapsed += deltaTime
	if ambientElapsed < AMBIENT_UPDATE_INTERVAL then return end
	ambientElapsed = 0

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for _, tower in ipairs(Workspace:GetChildren()) do
		if tower:IsA("Model") and tower:GetAttribute("RadarTower") == true then
			local yacht = getTowerSound(tower, "RadarYacht")
			local screen = getTowerScreen(tower)
			if yacht and screen and root and root:IsA("BasePart")
				and (root.Position - screen.Position).Magnitude <= AMBIENT_RANGE
			then
				if not yacht.IsPlaying then yacht:Play() end
			elseif yacht and yacht.IsPlaying then
				yacht:Stop()
			end
		end
	end
end)

local function exitRadar()
	gui.Enabled = false
	setRadarLoop(nil, false)
	useEvent:FireServer(false)
end

close.Activated:Connect(exitRadar)
UserInputService.InputBegan:Connect(function(input, processed)
	if gui.Enabled and not processed and input.KeyCode == Enum.KeyCode.Escape then
		exitRadar()
	end
end)

useEvent.OnClientEvent:Connect(function(enabled, tower)
	gui.Enabled = enabled == true
	setRadarLoop(tower, enabled == true)
	warn("[RadarTowerHud]", enabled == true and "opened" or "closed")
end)

player.CharacterAdded:Connect(function()
	gui.Enabled = false
	setRadarLoop(nil, false)
end)

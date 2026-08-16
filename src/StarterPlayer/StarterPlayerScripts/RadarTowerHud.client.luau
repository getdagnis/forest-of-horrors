-- RadarTowerHud: full-map monster positions while a RadarTower console is used.
-- Set Workspace.RadarMapMin and Workspace.RadarMapMax Vector3 attributes in
-- Studio to fit the actual map. The fallback is centered on McDonald's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local useEvent = ReplicatedStorage:WaitForChild("RadarTowerUse")

local gui = Instance.new("ScreenGui")
gui.Name = "RadarTowerHud"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local shade = Instance.new("Frame")
shade.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
shade.BackgroundTransparency = 0.3
shade.Size = UDim2.fromScale(1, 1)
shade.BorderSizePixel = 0
shade.Parent = gui

local map = Instance.new("Frame")
map.Name = "FullMap"
map.AnchorPoint = Vector2.new(0.5, 0.5)
map.Position = UDim2.fromScale(0.5, 0.5)
map.Size = UDim2.fromOffset(540, 540)
map.BackgroundColor3 = Color3.fromRGB(7, 16, 24)
map.BackgroundTransparency = 0.08
map.BorderSizePixel = 0
map.ClipsDescendants = true
map.Parent = shade
Instance.new("UICorner", map).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(83, 144, 180)
stroke.Transparency = 0.25
stroke.Thickness = 2
stroke.Parent = map

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 12)
title.Size = UDim2.new(1, -36, 0, 30)
title.Font = Enum.Font.GothamBold
title.Text = "RADAR TOWER"
title.TextColor3 = Color3.fromRGB(180, 225, 250)
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = map

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -12, 0, 10)
close.Size = UDim2.fromOffset(42, 32)
close.BackgroundColor3 = Color3.fromRGB(50, 16, 30)
close.Text = "×"
close.TextColor3 = Color3.fromRGB(255, 220, 230)
close.TextSize = 24
close.Font = Enum.Font.GothamBold
close.Parent = map
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 7)
close.Activated:Connect(function() gui.Enabled = false end)

local dotFolder = Instance.new("Folder")
dotFolder.Name = "MonsterDots"
dotFolder.Parent = map
local dots = {}

local function mapBounds()
	local min = Workspace:GetAttribute("RadarMapMin")
	local max = Workspace:GetAttribute("RadarMapMax")
	if typeof(min) ~= "Vector3" or typeof(max) ~= "Vector3" then
		min, max = Vector3.new(-1725, 0, -1550), Vector3.new(275, 0, 450)
	end
	return min, max
end

local function getDot(index)
	local dot = dots[index]
	if dot then return dot end
	dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(7, 7)
	dot.BackgroundColor3 = Color3.fromRGB(235, 62, 70)
	dot.BorderSizePixel = 0
	dot.Parent = dotFolder
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	dots[index] = dot
	return dot
end

local elapsed = 0
RunService.RenderStepped:Connect(function(dt)
	if not gui.Enabled then return end
	elapsed += dt
	if elapsed < 0.5 then return end
	elapsed = 0
	local min, max = mapBounds()
	local width, depth = math.max(1, max.X - min.X), math.max(1, max.Z - min.Z)
	local shown = 0
	for _, model in ipairs(Workspace:GetDescendants()) do
		if model:IsA("Model") and model:GetAttribute("RoundManagedMonster") == true and MonsterManager.getConfig(model) then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			local root = model:FindFirstChild("HumanoidRootPart", true)
			if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
				shown += 1
				local dot = getDot(shown)
				dot.Position = UDim2.fromScale(math.clamp((root.Position.X - min.X) / width, 0, 1), math.clamp(1 - (root.Position.Z - min.Z) / depth, 0, 1))
				dot.Visible = true
			end
		end
	end
	for index = shown + 1, #dots do dots[index].Visible = false end
end)

useEvent.OnClientEvent:Connect(function(enabled)
	gui.Enabled = enabled == true
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local monsterCountEvent = ReplicatedStorage:WaitForChild("MonsterCountUpdate")

local SHOW_AT_COUNT = 20
local MIN_DISTANCE = 50
local MAX_DISTANCE = 250
local UPDATE_EVERY = 0.35

local currentMonsterCount = math.huge
local highlights = {}

local function getCharacter()
	return player.Character
end

local function getMonsterPart(model)
	local part = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)

	if part and part:IsA("BasePart") then
		return part
	end

	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			return item
		end
	end

	return nil
end

local function isAliveMonster(model)
	if not model:IsA("Model") then return false end
	if not MonsterManager.getConfig(model) then return false end

	local humanoid = MonsterManager.getMonsterHumanoid(model)
	return humanoid and humanoid.Health > 0
end

local function getHighlight(model)
	local oldServerHighlight = model:FindFirstChild("MonsterContour")
	if oldServerHighlight and oldServerHighlight:IsA("Highlight") then
		oldServerHighlight.Enabled = false
	end

	local highlight = highlights[model]

	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "LocalMonsterContour"
		highlight.Adornee = model
		highlight.FillColor = Color3.fromRGB(255, 0, 0)
		highlight.OutlineColor = Color3.fromRGB(255, 40, 40)
		highlight.FillTransparency = 0.9
		highlight.OutlineTransparency = 0
		highlight.Enabled = false
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = model
		highlights[model] = highlight
	end

	return highlight
end

local function isBehindObject(monsterModel, monsterPart)
	local camera = Workspace.CurrentCamera
	local character = getCharacter()

	if not camera or not character then
		return false
	end

	local origin = camera.CFrame.Position
	local target = monsterPart.Position
	local direction = target - origin

	if direction.Magnitude <= 0 then
		return false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, monsterModel }
	params.IgnoreWater = true

	local result = Workspace:Raycast(origin, direction, params)
	return result ~= nil
end

local function updateContours()
	local canShowAny = currentMonsterCount <= SHOW_AT_COUNT

	for model, highlight in pairs(highlights) do
		if not model.Parent then
			highlights[model] = nil
		elseif highlight.Parent then
			highlight.Enabled = false
		end
	end

	if not canShowAny then
		return
	end

	local character = getCharacter()
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not playerRoot then return end

	for _, item in Workspace:GetDescendants() do
		if isAliveMonster(item) then
			local part = getMonsterPart(item)

			if part then
				local distance = (part.Position - playerRoot.Position).Magnitude
				local visible = distance >= MIN_DISTANCE
					and distance <= MAX_DISTANCE
					and isBehindObject(item, part)

				getHighlight(item).Enabled = visible
			end
		end
	end
end

monsterCountEvent.OnClientEvent:Connect(function(count)
	currentMonsterCount = tonumber(count) or math.huge
	updateContours()
end)

while true do
	task.wait(UPDATE_EVERY)
	updateContours()
end

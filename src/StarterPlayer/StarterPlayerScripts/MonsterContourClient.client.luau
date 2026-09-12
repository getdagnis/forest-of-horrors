local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local monsterCountEvent = ReplicatedStorage:WaitForChild("MonsterCountUpdate")

local SHOW_AT_COUNT = 50
local MIN_DISTANCE = 50
local MAX_DISTANCE = 200
local UPDATE_EVERY = 0.35

local currentMonsterCount = math.huge
local highlights = {}
local roundMonsterModels = {}
local roundMonsterModelSet = {}
local monsterParts = {}

local function currentGeneration()
	return math.max(0, math.floor(tonumber(Workspace:GetAttribute("RoundGeneration")) or 0))
end

local function isActiveRound()
	return Workspace:GetAttribute("RoundState") == "Active"
end

local function getCharacter()
	return player.Character
end

local function getMonsterPart(model)
	local cached = monsterParts[model]
	if cached and cached.Parent then
		return cached
	end

	local part = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)

	if part and part:IsA("BasePart") then
		monsterParts[model] = part
		return part
	end

	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			monsterParts[model] = item
			return item
		end
	end

	return nil
end

local function cacheRoundMonster(instance)
	if instance:IsA("Model")
		and not roundMonsterModelSet[instance]
		and MonsterManager.isRoundTracked(instance)
	then
		roundMonsterModelSet[instance] = true
		table.insert(roundMonsterModels, instance)
	end
end

local function removeRoundMonster(instance)
	if not roundMonsterModelSet[instance] then return end
	roundMonsterModelSet[instance] = nil
	monsterParts[instance] = nil
	highlights[instance] = nil
	for index = #roundMonsterModels, 1, -1 do
		if roundMonsterModels[index] == instance then
			table.remove(roundMonsterModels, index)
			break
		end
	end
end

local function isAliveMonster(model)
	if not model:IsA("Model") then return false end
	if not MonsterManager.isRoundTracked(model) then return false end

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

local function updateContours()
	local canShowAny = isActiveRound() and currentMonsterCount <= SHOW_AT_COUNT

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

	for _, model in ipairs(roundMonsterModels) do
		if isAliveMonster(model) then
			local part = getMonsterPart(model)

			if part then
				local distance = (part.Position - playerRoot.Position).Magnitude
				-- In the last fifty hostile contacts, use the locator contour only
				-- for the distant 50-200 stud band. Nearby monsters remain visually
				-- clean; guardians stay out because they are not round monsters.
				local visible = distance >= MIN_DISTANCE and distance <= MAX_DISTANCE

				getHighlight(model).Enabled = visible
			end
		end
	end
end

Workspace.DescendantAdded:Connect(cacheRoundMonster)
Workspace.DescendantRemoving:Connect(removeRoundMonster)

-- Build once without blocking the client, then maintain the registry from
-- instance lifecycle events instead of rescanning the entire map.
task.spawn(function()
	for index, instance in ipairs(Workspace:GetDescendants()) do
		cacheRoundMonster(instance)
		if index % 200 == 0 then
			task.wait()
		end
	end
end)

monsterCountEvent.OnClientEvent:Connect(function(count, generation)
	if tonumber(generation) ~= currentGeneration() or not isActiveRound() then return end
	currentMonsterCount = tonumber(count) or math.huge
	updateContours()
end)

Workspace:GetAttributeChangedSignal("RoundState"):Connect(updateContours)
Workspace:GetAttributeChangedSignal("RoundGeneration"):Connect(function()
	currentMonsterCount = math.huge
	updateContours()
end)

while true do
	task.wait(UPDATE_EVERY)
	updateContours()
end

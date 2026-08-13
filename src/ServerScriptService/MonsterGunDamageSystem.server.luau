local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local DAMAGE = 20
local HIT_COLOR = Color3.fromRGB(255, 105, 180)
local boundEvents = {}
local activeFlashes = {}

local function getMonsterModelFromHit(instance)
	local current = instance

	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			return current
		end
		current = current.Parent
	end
end

local function setBodyColors(bodyColors, color)
	bodyColors.HeadColor3 = color
	bodyColors.LeftArmColor3 = color
	bodyColors.RightArmColor3 = color
	bodyColors.LeftLegColor3 = color
	bodyColors.RightLegColor3 = color
	bodyColors.TorsoColor3 = color
end

local function flashMonster(model)
	if activeFlashes[model] then return end

	local original = {}
	activeFlashes[model] = original

	for _, item in model:GetDescendants() do
		if item:IsA("BodyColors") then
			original[item] = {
				type = "BodyColors",
				head = item.HeadColor3,
				leftArm = item.LeftArmColor3,
				rightArm = item.RightArmColor3,
				leftLeg = item.LeftLegColor3,
				rightLeg = item.RightLegColor3,
				torso = item.TorsoColor3,
			}
			setBodyColors(item, HIT_COLOR)
		elseif item:IsA("BasePart") then
			original[item] = { type = "BasePart", color = item.Color, material = item.Material }
			item.Color = HIT_COLOR
			item.Material = Enum.Material.Neon
		end
	end

	task.delay(0.25, function()
		local saved = activeFlashes[model]
		activeFlashes[model] = nil
		if not saved or not model.Parent then return end

		for item, values in pairs(saved) do
			if item.Parent then
				if values.type == "BodyColors" then
					item.HeadColor3 = values.head
					item.LeftArmColor3 = values.leftArm
					item.RightArmColor3 = values.rightArm
					item.LeftLegColor3 = values.leftLeg
					item.RightLegColor3 = values.rightLeg
					item.TorsoColor3 = values.torso
				else
					item.Color = values.color
					item.Material = values.material
				end
			end
		end
	end)
end

local function showHitpoints(model, humanoid)
	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Head", true)
	if not root or not root:IsA("BasePart") then return end

	local gui = model:FindFirstChild("MonsterHealthGui")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "MonsterHealthGui"
		gui.Size = UDim2.fromOffset(180, 44)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = model

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end

	gui.Adornee = root
	gui.Enabled = true
	local label = gui:FindFirstChild("Label")
	if label then
		label.Text = math.max(0, math.ceil(humanoid.Health)) .. " / " .. math.ceil(humanoid.MaxHealth)
	end

	task.delay(1.5, function()
		if gui.Parent then gui.Enabled = false end
	end)
end

local function makeMonsterPink(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BodyColors") then
			setBodyColors(item, HIT_COLOR)
		elseif item:IsA("BasePart") then
			item.Color = HIT_COLOR
			item.Material = Enum.Material.Neon
		end
	end
end

local function disintegrateMonster(model, blastOrigin)
	makeMonsterPink(model)

	for _, item in model:GetDescendants() do
		if item:IsA("Motor6D") or item:IsA("Weld") or item:IsA("WeldConstraint") then
			item:Destroy()
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.CanTouch = false
			part.Massless = false

			local direction = part.Position - blastOrigin
			if direction.Magnitude < 0.1 then
				direction = Vector3.new(math.random(-100, 100) / 100, 1, math.random(-100, 100) / 100)
			end

			part.AssemblyLinearVelocity = direction.Unit * math.random(30, 55) + Vector3.new(0, math.random(15, 35), 0)
		end
	end
end

local function bindTool(tool)
	if not tool:IsA("Tool") or tool.Name ~= "MonsterGun" then return end

	local shootEvent = tool:FindFirstChild("ShootEvent")
	if not shootEvent or not shootEvent:IsA("RemoteEvent") or boundEvents[shootEvent] then return end
	boundEvents[shootEvent] = true

	shootEvent.OnServerEvent:Connect(function(player, hitInstance)
		local character = player.Character
		if tool.Parent ~= character and tool.Parent ~= player:FindFirstChild("Backpack") then return end
		if not hitInstance or not hitInstance.Parent then return end

		local monsterModel = getMonsterModelFromHit(hitInstance)
		if not monsterModel then return end
		local humanoid = MonsterManager.getMonsterHumanoid(monsterModel)
		if not humanoid or humanoid.Health <= 0 then return end

		local willDie = humanoid.Health <= DAMAGE
		MonsterManager.recordPlayerDamage(humanoid, player, DAMAGE, HIT_COLOR)

		if willDie then
			humanoid.BreakJointsOnDeath = false
			humanoid.RequiresNeck = false
			if monsterModel.Name == "Monster" then
				MonsterManager.markPermanentKill(humanoid, "MonsterGun")
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			disintegrateMonster(monsterModel, root and root.Position or monsterModel:GetPivot().Position)
		else
			flashMonster(monsterModel)
		end

		humanoid:TakeDamage(DAMAGE)
		if not willDie then
			showHitpoints(monsterModel, humanoid)
		end
	end)
end

for _, instance in workspace:GetDescendants() do
	bindTool(instance)
end
workspace.DescendantAdded:Connect(bindTool)

local function bindPlayer(player)
	player.CharacterAdded:Connect(function(character)
		for _, instance in character:GetDescendants() do bindTool(instance) end
	end)
	player.Backpack.ChildAdded:Connect(bindTool)
	for _, instance in player.Backpack:GetChildren() do bindTool(instance) end
end

Players.PlayerAdded:Connect(bindPlayer)
for _, player in Players:GetPlayers() do bindPlayer(player) end

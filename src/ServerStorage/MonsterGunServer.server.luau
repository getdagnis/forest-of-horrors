-- Monster Gun Server Script
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")

local shootEvent = script.Parent:WaitForChild("ShootEvent")
local MonsterManager = require(rs:WaitForChild("MonsterManager"))

local DAMAGE = 20
local FLASH_COLOR = Color3.fromRGB(255, 56, 106)
local BOMB_MONSTER_NAME = "Monster"

local function getMonsterModelFromHit(instance)
	local current = instance

	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function flashMonster(model)
	local original = {}

	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			original[item] = {
				Color = item.Color,
				Material = item.Material,
			}

			item.Color = FLASH_COLOR
			item.Material = Enum.Material.Neon
		end
	end

	task.delay(0.1, function()
		for part, values in original do
			if part and part.Parent then
				part.Color = values.Color
				part.Material = values.Material
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
		gui.Size = UDim2.new(0, 160, 0, 40)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = model

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 1, 0)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
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
		if gui and gui.Parent then
			gui.Enabled = false
		end
	end)
end

shootEvent.OnServerEvent:Connect(function(player, hitInstance)
	if not hitInstance or not hitInstance.Parent then return end

	local monsterModel = getMonsterModelFromHit(hitInstance)
	if not monsterModel then return end

	local target = MonsterManager.getMonsterHumanoid(monsterModel)
	if not target or target.Health <= 0 then return end

	MonsterManager.recordPlayerDamage(
		target,
		player,
		DAMAGE,
		Color3.fromRGB(255, 105, 180)
	)

	if monsterModel.Name == BOMB_MONSTER_NAME and target.Health - DAMAGE <= 0 then
		MonsterManager.markPermanentKill(target, "MonsterGun")
	end

	target:TakeDamage(DAMAGE)

	flashMonster(monsterModel)
	showHitpoints(monsterModel, target)
end)

-- MonsterBombSystem

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local Config = require(ReplicatedStorage:WaitForChild("MonsterBombConfig"))

local activeBombs = {}

local function isBombMonster(model)
	return model:IsA("Model") and model.Name == Config.MODEL_NAME
end

local function getWarningSound(model)
	return model:FindFirstChild("WarningSound", true) or model:FindFirstChild("WarningSound1", true)
end

local function makeBlastVisual(position)
	local bubble = Instance.new("Part")
	bubble.Name = "MonsterBlastBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.CastShadow = false
	bubble.Material = Enum.Material.Neon
	bubble.Color = Config.BLAST_COLOR
	bubble.Transparency = 0.5
	bubble.Size = Vector3.new(2, 2, 2)
	bubble.CFrame = CFrame.new(position)
	bubble.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Config.BLAST_COLOR
	light.Brightness = 24
	light.Range = Config.BLAST_RADIUS
	light.Shadows = true
	light.Parent = bubble

	TweenService:Create(
		bubble,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = Vector3.new(Config.BLAST_RADIUS * 2, Config.BLAST_RADIUS * 2, Config.BLAST_RADIUS * 2),
			Transparency = 1,
		}
	):Play()

	TweenService:Create(
		light,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Brightness = 0,
			Range = Config.BLAST_RADIUS * 1.25,
		}
	):Play()

	Debris:AddItem(bubble, 0.7)
end

local function fadeBody(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false

			TweenService:Create(
				item,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			):Play()
		elseif item:IsA("Decal") or item:IsA("Texture") then
			TweenService:Create(
				item,
				TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			):Play()
		end
	end
end

local function damagePlayers(position)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if root and humanoid and humanoid.Health > 0 then
			if (root.Position - position).Magnitude <= Config.BLAST_RADIUS then
				humanoid:TakeDamage(humanoid.MaxHealth * Config.PLAYER_DAMAGE_FRACTION)
			end
		end
	end
end

local function damageMonsters(sourceModel, position)
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model")
			and instance ~= sourceModel
			and not isBombMonster(instance)
			and MonsterManager.getConfig(instance)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)

			if humanoid and humanoid.Health > 0 then
				local root = instance:FindFirstChild("HumanoidRootPart", true)
				local targetPosition = root and root.Position or instance:GetPivot().Position

				if (targetPosition - position).Magnitude <= Config.BLAST_RADIUS then
					humanoid:TakeDamage(Config.MONSTER_DAMAGE)
				end
			end
		end
	end
end

local function setupBomb(model)
	if activeBombs[model] then return end
	if not model:IsA("Model") then return end
	if not isBombMonster(model) then return end

	activeBombs[model] = true

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Name = "Humanoid"
		humanoid.Parent = model
	end

	humanoid.MaxHealth = Config.HEALTH
	humanoid.Health = Config.HEALTH
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	local state = {
		warningActive = false,
		exploded = false,
		basePivot = model:GetPivot(),
	}

	local function explode()
		if state.exploded then return end
		state.exploded = true
		state.warningActive = false

		local position = model:GetPivot().Position

		makeBlastVisual(position)
		damagePlayers(position)
		damageMonsters(model, position)
		fadeBody(model)

		task.delay(0.15, function()
			if humanoid and humanoid.Parent and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end)
	end

	local function playWarning()
		local sound = getWarningSound(model)

		if sound and sound:IsA("Sound") then
			sound.TimePosition = 0
			sound:Play()
		end
	end

	task.spawn(function()
		local startedAt = os.clock()

		while model.Parent and humanoid.Health > 0 and not state.exploded do
			local elapsed = os.clock() - startedAt
			local height = state.warningActive and Config.WARNING_PULSE_HEIGHT or Config.IDLE_PULSE_HEIGHT
			local speed = state.warningActive and Config.WARNING_PULSE_SPEED or Config.IDLE_PULSE_SPEED
			local offset = math.sin(elapsed * speed) * height

			model:PivotTo(state.basePivot * CFrame.new(0, offset, 0))
			task.wait(0.03)
		end
	end)

	task.spawn(function()
		while model.Parent and humanoid.Health > 0 and not state.exploded do
			task.wait(math.random(Config.MIN_WAIT, Config.MAX_WAIT))

			if not model.Parent or humanoid.Health <= 0 or state.exploded then
				break
			end

			state.warningActive = true
			playWarning()

			task.wait(Config.WARNING_TIME)

			if model.Parent and humanoid.Health > 0 and not state.exploded then
				explode()
			end
		end
	end)

	humanoid.Died:Connect(function()
		explode()
	end)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			activeBombs[model] = nil
		end
	end)
end

for _, item in workspace:GetDescendants() do
	if item:IsA("Model") then
		setupBomb(item)
	end
end

workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			setupBomb(item)
		end)
	end
end)

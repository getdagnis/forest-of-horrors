local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local Config = require(ReplicatedStorage:WaitForChild("MonsterBombConfig"))

local activeBombs = {}

local function findNamedDescendant(model, names)
	for _, name in ipairs(names) do
		local item = model:FindFirstChild(name, true)
		if item then
			return item
		end
	end

	return nil
end

local function configureSpatialSound(sound, volume)
	if not sound or not sound:IsA("Sound") then return end

	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = Config.BLAST_RADIUS
	sound.EmitterSize = Config.BLAST_RADIUS / 4
end

local function playSoundByNames(model, names, volume)
	local sound = findNamedDescendant(model, names)

	if sound and sound:IsA("Sound") then
		configureSpatialSound(sound, volume)
		sound.TimePosition = 0
		sound:Play()
	end
end

local function captureOriginalVisuals(model)
	local original = {}

	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			original[item] = {
				Color = item.Color,
				Material = item.Material,
				Transparency = item.Transparency,
			}
		elseif item:IsA("Decal") or item:IsA("Texture") then
			original[item] = {
				Transparency = item.Transparency,
			}
		end
	end

	return original
end

local function applyWarningVisuals(original, alpha)
	for item, values in pairs(original) do
		if item and item.Parent and item:IsA("BasePart") then
			item.Color = values.Color:Lerp(Config.BLAST_COLOR, alpha)
			item.Material = Enum.Material.Neon
		end
	end
end

local function restoreVisuals(original)
	for item, values in pairs(original) do
		if item and item.Parent then
			if item:IsA("BasePart") then
				item.Color = values.Color
				item.Material = values.Material
				item.Transparency = values.Transparency
			elseif item:IsA("Decal") or item:IsA("Texture") then
				item.Transparency = values.Transparency
			end
		end
	end
end

local function makeBlastBubble(position, radius, transparency, lifeTime)
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
	bubble.Transparency = transparency
	bubble.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	bubble.CFrame = CFrame.new(position)
	bubble.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Config.BLAST_COLOR
	light.Brightness = 28
	light.Range = radius
	light.Shadows = true
	light.Parent = bubble

	TweenService:Create(
		bubble,
		TweenInfo.new(lifeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Transparency = 1 }
	):Play()

	TweenService:Create(
		light,
		TweenInfo.new(lifeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			Brightness = 0,
			Range = radius * 1.25,
		}
	):Play()

	Debris:AddItem(bubble, lifeTime + 0.25)
end

local function damagePlayers(position, radius, damaged)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if root and humanoid and humanoid.Health > 0 and not damaged[humanoid] then
			if (root.Position - position).Magnitude <= radius then
				damaged[humanoid] = true
				humanoid:TakeDamage(humanoid.MaxHealth * Config.PLAYER_DAMAGE_FRACTION)
			end
		end
	end
end

local function damageMonsters(sourceModel, position, radius, damaged)
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("Model") and instance ~= sourceModel and MonsterManager.getConfig(instance) then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)

			if humanoid and humanoid.Health > 0 and not damaged[humanoid] then
				local root = instance:FindFirstChild("HumanoidRootPart", true)
				local targetPosition = root and root.Position or instance:GetPivot().Position

				if (targetPosition - position).Magnitude <= radius then
					damaged[humanoid] = true
					humanoid:TakeDamage(Config.MONSTER_DAMAGE)
				end
			end
		end
	end
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

local function setupBomb(model)
	if activeBombs[model] then return end
	if not model:IsA("Model") then return end
	if model.Name ~= Config.MODEL_NAME then return end

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

	for _, sound in model:GetDescendants() do
		if sound:IsA("Sound") then
			if table.find(Config.WARNING_SOUND_NAMES, sound.Name) then
				configureSpatialSound(sound, Config.WARNING_SOUND_VOLUME)
			elseif table.find(Config.BLAST_SOUND_NAMES, sound.Name) then
				configureSpatialSound(sound, Config.BLAST_SOUND_VOLUME)
			end
		end
	end

	local state = {
		warningActive = false,
		exploded = false,
		basePivot = model:GetPivot(),
		originalVisuals = captureOriginalVisuals(model),
	}

	local function explode()
		if state.exploded then return end
		state.exploded = true
		state.warningActive = false

		local position = model:GetPivot().Position
		local damaged = {}
		local stages = math.max(1, Config.BLAST_STAGES)
		local stageTime = Config.BLAST_DURATION / stages

		playSoundByNames(model, Config.BLAST_SOUND_NAMES, Config.BLAST_SOUND_VOLUME)

		for stage = 1, stages do
			local progress = stage / stages
			local radius = Config.BLAST_START_RADIUS + ((Config.BLAST_RADIUS - Config.BLAST_START_RADIUS) * progress)
			local transparency = math.clamp((progress - 0.15) * 0.75, 0, 0.75)
			local lifeTime = math.max(stageTime * 1.4, 0.2)

			makeBlastBubble(position, radius, transparency, lifeTime)
			damagePlayers(position, radius, damaged)
			damageMonsters(model, position, radius, damaged)

			task.wait(stageTime)
		end

		fadeBody(model)

		task.delay(0.15, function()
			if humanoid and humanoid.Parent and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end)
	end

	task.spawn(function()
		local startedAt = os.clock()

		while model.Parent and humanoid.Health > 0 and not state.exploded do
			local elapsed = os.clock() - startedAt
			local height = state.warningActive and Config.WARNING_PULSE_HEIGHT or Config.IDLE_PULSE_HEIGHT
			local speed = state.warningActive and Config.WARNING_PULSE_SPEED or Config.IDLE_PULSE_SPEED
			local offset = math.sin(elapsed * speed) * height

			if state.warningActive then
				local colorAlpha = ((math.sin(elapsed * speed * 2) + 1) / 2) * Config.WARNING_COLOR_BLEND
				applyWarningVisuals(state.originalVisuals, colorAlpha)
			end

			model:PivotTo(state.basePivot * CFrame.new(0, offset, 0))
			task.wait(0.03)
		end

		if model.Parent and not state.exploded then
			restoreVisuals(state.originalVisuals)
		end
	end)

	task.spawn(function()
		while model.Parent and humanoid.Health > 0 and not state.exploded do
			task.wait(math.random(Config.MIN_WAIT, Config.MAX_WAIT))

			if not model.Parent or humanoid.Health <= 0 or state.exploded then
				break
			end

			state.warningActive = true
			playSoundByNames(model, Config.WARNING_SOUND_NAMES, Config.WARNING_SOUND_VOLUME)

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
end

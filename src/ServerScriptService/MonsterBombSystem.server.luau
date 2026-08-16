-- MonsterBombSystem
--
-- Deliberately small state sequence:
-- idle wait -> 10 warning beeps/lights -> one damage call + bomb fade ->
-- one four-second expanding Neon sphere.  Bombs never damage other bombs.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local Config = require(ReplicatedStorage:WaitForChild("MonsterBombConfig"))

local activeBombs = {}

local function isBombMonster(model)
	return model:IsA("Model") and model.Name == Config.MODEL_NAME
end

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function playWarning(model)
	local root = getRoot(model)
	if not root or not root:IsA("BasePart") then return end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://357644762"
	sound.Volume = 10
	sound.PlaybackSpeed = 0.9
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = Config.WARNING_SOUND_RADIUS
	sound.TimePosition = 0
	sound.Parent = root
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)

	local light = Instance.new("PointLight")
	light.Name = "MonsterBombWarningLight"
	light.Color = Config.BLAST_COLOR
	light.Brightness = 20
	light.Range = 36
	light.Shadows = true
	light.Parent = root

	TweenService:Create(light, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Range = 0,
	}):Play()
	Debris:AddItem(light, 0.4)
end

local function playExplosionSound(model, position)
	local source = model:FindFirstChild(Config.EXPLOSION_SOUND_NAME, true)
	if not source or not source:IsA("Sound") then return end

	-- The bomb model may be removed while the sound is playing, so play a clone
	-- from a short-lived invisible world emitter instead.
	local emitter = Instance.new("Part")
	emitter.Name = "MonsterBombExplosionSoundEmitter"
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(0.1, 0.1, 0.1)
	emitter.Position = position
	emitter.Parent = workspace

	local sound = source:Clone()
	sound.Looped = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = Config.EXPLOSION_SOUND_RADIUS
	sound.Volume = 20
	sound.TimePosition = 0
	sound.Parent = emitter
	sound.Ended:Once(function()
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
	sound:Play()

	-- Covers unavailable or malformed assets that never emit Sound.Ended.
	Debris:AddItem(emitter, Config.EXPLOSION_SOUND_LIFETIME)
end

local function makeExplosionVisual(position)
	local sphere = Instance.new("Part")
	sphere.Name = "MonsterBombExplosion"
	sphere.Shape = Enum.PartType.Ball
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanTouch = false
	sphere.CanQuery = false
	sphere.CastShadow = false
	sphere.Material = Enum.Material.Neon
	sphere.Color = Config.BLAST_COLOR
	sphere.Transparency = 0.12
	sphere.Size = Vector3.new(4, 4, 4)
	sphere.CFrame = CFrame.new(position)
	sphere.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = Config.BLAST_COLOR
	light.Brightness = 34
	light.Range = Config.BLAST_RADIUS * 1.2
	light.Shadows = true
	light.Parent = sphere

	TweenService:Create(sphere, TweenInfo.new(Config.BLAST_VISUAL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(Config.BLAST_RADIUS * 2, Config.BLAST_RADIUS * 2, Config.BLAST_RADIUS * 2),
		Transparency = 1,
	}):Play()
	TweenService:Create(light, TweenInfo.new(Config.BLAST_VISUAL_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Range = 0,
	}):Play()

	-- Debris is a useful backstop, but this explicit destroy guarantees that a
	-- completed explosion cannot leave a bright sphere in Workspace indefinitely.
	task.delay(Config.BLAST_VISUAL_DURATION + 0.1, function()
		if sphere.Parent then
			sphere:Destroy()
		end
	end)
	Debris:AddItem(sphere, Config.BLAST_VISUAL_DURATION + 0.1)
end

local function fadeAndRemoveBomb(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			TweenService:Create(item, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		elseif item:IsA("Decal") or item:IsA("Texture") then
			TweenService:Create(item, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			}):Play()
		end
	end
end

local function damagePlayers(position)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and (root.Position - position).Magnitude <= Config.BLAST_RADIUS then
			humanoid:TakeDamage(humanoid.MaxHealth * Config.PLAYER_DAMAGE_FRACTION)
		end
	end
end

local function damageMonsters(sourceModel, position)
	for _, model in workspace:GetDescendants() do
		if model:IsA("Model")
			and model ~= sourceModel
			and not isBombMonster(model)
			and MonsterManager.getConfig(model)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			local root = getRoot(model)
			if humanoid and root and humanoid.Health > 0 and (root.Position - position).Magnitude <= Config.BLAST_RADIUS then
				MonsterManager.damageMonsterTarget(model, Config.MONSTER_DAMAGE)
			end
		end
	end
end

local function setupBomb(model)
	if activeBombs[model] or not isBombMonster(model) then return end
	activeBombs[model] = true

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	humanoid.MaxHealth = Config.HEALTH
	humanoid.Health = Config.HEALTH
	humanoid.BreakJointsOnDeath = false
	-- Keep the same no-name, damaged-only health display used by every monster.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged

	local exploded = false
	local function explode()
		if exploded then return end
		exploded = true

		local root = getRoot(model)
		local position = root and root.Position or model:GetPivot().Position
		makeExplosionVisual(position)
		playExplosionSound(model, position)
		damagePlayers(position)
		damageMonsters(model, position)
		fadeAndRemoveBomb(model)

		-- Mark this as a normal bomb death. MonsterSystem may respawn it; only
		-- MonsterGun/MonsterBlaster set permanent weapon-kill attributes.
		if humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	humanoid.Died:Connect(explode)

	task.spawn(function()
		task.wait(math.random(Config.MIN_WAIT, Config.MAX_WAIT))
		if exploded or not model.Parent or humanoid.Health <= 0 then return end

		for _ = 1, Config.WARNING_TIME do
			if exploded or not model.Parent or humanoid.Health <= 0 then return end
			playWarning(model)
			task.wait(Config.WARNING_BEEP_INTERVAL)
		end

		explode()
	end)

	model.Destroying:Connect(function()
		activeBombs[model] = nil
	end)
end

-- Clear only runtime spheres left by the previous implementation, so a fresh
-- server session never inherits an old permanent-looking explosion visual.
for _, item in workspace:GetDescendants() do
	if item:IsA("BasePart") and item.Name == "MonsterBombExplosion" then
		item:Destroy()
	end
end

for _, item in workspace:GetDescendants() do
	if item:IsA("Model") then setupBomb(item) end
end

workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			if item.Parent then setupBomb(item) end
		end)
	end
end)

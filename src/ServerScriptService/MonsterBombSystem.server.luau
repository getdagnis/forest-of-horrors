-- MonsterBombSystem
--
-- Deliberately small state sequence:
-- idle wait -> one warning countdown announcement/light -> one damage call
-- + bomb fade -> one four-second expanding Neon sphere. Bombs never damage
-- other bombs.

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

-- BombMonster has no model-local Animator. Restore only its original calm
-- float here, relative to the spawn pivot; warning and explosion presentation
-- deliberately stay exactly as they are below.
local function startIdleBob(model, humanoid)
	local active = true
	local basePivot = model:GetPivot()

	task.spawn(function()
		local startedAt = os.clock()
		while active and model.Parent and humanoid.Parent and humanoid.Health > 0 do
			local offset = math.sin((os.clock() - startedAt) * Config.IDLE_PULSE_SPEED) * Config.IDLE_PULSE_HEIGHT
			model:PivotTo(basePivot * CFrame.new(0, offset, 0))
			task.wait(0.03)
		end
	end)

	return function(resetToBase)
		if not active then return end
		active = false
		if resetToBase and model.Parent then
			model:PivotTo(basePivot)
		end
	end
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
	local source = SoundService:FindFirstChild(Config.EXPLOSION_SOUND_TEMPLATE)
	if not (source and source:IsA("Sound")) then
		source = model:FindFirstChild(Config.EXPLOSION_SOUND_NAME, true)
	end
	if not (source and source:IsA("Sound")) then
		source = Instance.new("Sound")
		source.SoundId = Config.EXPLOSION_SOUND_ID
		warn("[MonsterBomb] no explosion sound template found; using fallback asset")
	end
	if source.SoundId == "" then
		source.SoundId = Config.EXPLOSION_SOUND_ID
	end

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
	local killed = 0
	for _, model in workspace:GetDescendants() do
		if model:IsA("Model")
			and model ~= sourceModel
			and not isBombMonster(model)
			and MonsterManager.getConfig(model)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			local root = getRoot(model)
			if humanoid and root and humanoid.Health > 0 and (root.Position - position).Magnitude <= Config.BLAST_RADIUS then
				MonsterManager.damageMonsterTarget(model, Config.MONSTER_DAMAGE, sourceModel)
				if humanoid.Health <= 0 then
					killed += 1
				end
			end
		end
	end
	return killed
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

	local stopIdleBob = startIdleBob(model, humanoid)
	local exploded = false
	local warningActive = false
	local function explode()
		if exploded then return end
		exploded = true
		warningActive = false
		model:SetAttribute("BombWarningActive", false)

		local root = getRoot(model)
		local position = root and root.Position or model:GetPivot().Position
		stopIdleBob()
		makeExplosionVisual(position)
		playExplosionSound(model, position)
		damagePlayers(position)
		damageMonsters(model, position)
		-- Each killed monster publishes its own passive bomb-cause event from
		-- MonsterSystem. Avoid a second aggregate row that obscures the victims.
		fadeAndRemoveBomb(model)

		-- Every bomb death uses the normal lifecycle so a player can deliberately
		-- ignite one to clear a crowd and it can return later as ambient danger.
		if humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end

	local function beginWarning()
		if warningActive or exploded or not model.Parent then return end
		warningActive = true
		model:SetAttribute("BombWarningActive", true)
		stopIdleBob(true)
		playWarning(model)
		task.delay(Config.WARNING_TIME, explode)
	end

	-- A bomb takes four MG1 hits to arm. Player weapons record LastAttackerId
	-- before changing Health, which keeps incidental NPC damage from activating
	-- the warning sequence.
	humanoid.HealthChanged:Connect(function(health)
		local damageTaken = humanoid.MaxHealth - health
		if not warningActive and not exploded
			and damageTaken >= Config.PLAYER_ARM_DAMAGE
			and humanoid:GetAttribute("LastAttackerId")
		then
			beginWarning()
		end
	end)

	humanoid.Died:Connect(function()
		if warningActive then return end
		if humanoid:GetAttribute("LastAttackerId") then
			beginWarning()
		else
			explode()
		end
	end)

	task.spawn(function()
		task.wait(math.random(Config.MIN_WAIT, Config.MAX_WAIT))
		if exploded or not model.Parent or humanoid.Health <= 0 then return end

		-- The imported warning asset is a complete spoken five-to-one countdown,
		-- not a one-second beep. Start it once and let the announcement finish.
		beginWarning()
	end)

	model.Destroying:Connect(function()
		stopIdleBob()
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

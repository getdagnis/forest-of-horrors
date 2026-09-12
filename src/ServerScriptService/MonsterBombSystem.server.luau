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
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local Config = require(ReplicatedStorage:WaitForChild("MonsterBombConfig"))

local activeBombs = {}

local function roundIsActive(generation)
	return Workspace:GetAttribute("RoundState") == "Active"
		and tonumber(Workspace:GetAttribute("RoundGeneration")) == generation
end

local function isBombMonster(model)
	return model:IsA("Model") and model.Name == Config.MODEL_NAME
end

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function getOrCreateWarningLight(model, root)
	local skin = model:FindFirstChild("Skin", true)
	if not (skin and skin:IsA("BasePart")) then
		skin = root
	end
	if not skin then return nil end

	local light = skin:FindFirstChildWhichIsA("PointLight", true)
	if light then return light end

	light = Instance.new("PointLight")
	light.Name = "PointLight"
	light.Parent = skin
	return light
end

local function applyWarningSkin(model)
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") and item.Name == "Skin" then
			item.Color = Config.WARNING_SKIN_COLOR
			item.Material = Enum.Material.Neon
		end
	end
end

local function startWarningPulse(model, generation)
	local root = getRoot(model)
	local light = root and getOrCreateWarningLight(model, root)
	if not light then
		return function() end
	end

	applyWarningSkin(model)
	light.Color = Config.WARNING_LIGHT_COLOR
	light.Shadows = false
	light.Enabled = true
	local active = true
	local startedAt = os.clock()

	task.spawn(function()
		while active and light.Parent and model.Parent and roundIsActive(generation) do
			local phase = (math.sin((os.clock() - startedAt) * math.pi * 2 * Config.WARNING_LIGHT_PULSE_HZ) + 1) * 0.5
			light.Brightness = Config.WARNING_LIGHT_MIN_BRIGHTNESS
				+ (Config.WARNING_LIGHT_MAX_BRIGHTNESS - Config.WARNING_LIGHT_MIN_BRIGHTNESS) * phase
			light.Range = Config.WARNING_LIGHT_MIN_RANGE
				+ (Config.WARNING_LIGHT_MAX_RANGE - Config.WARNING_LIGHT_MIN_RANGE) * phase
			task.wait(0.04)
		end
	end)

	return function()
		active = false
		if light.Parent then
			light.Enabled = false
			light.Brightness = Config.WARNING_LIGHT_MIN_BRIGHTNESS
			light.Range = Config.WARNING_LIGHT_MAX_RANGE
		end
	end
end

local function playWarningSound(model)
	local root = getRoot(model)
	if not root or not root:IsA("BasePart") then return nil end

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
		if sound.Parent then sound:Destroy() end
	end)
	return sound
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
	light.Shadows = false
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

local function damagePlayers(position, generation)
	if not roundIsActive(generation) then return end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 and (root.Position - position).Magnitude <= Config.BLAST_RADIUS then
			humanoid:TakeDamage(humanoid.MaxHealth * Config.PLAYER_DAMAGE_FRACTION)
		end
	end
end

local function damageMonsters(sourceModel, position, generation)
	if not roundIsActive(generation) then return 0 end
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

	local existingWarningLight = getOrCreateWarningLight(model, getRoot(model))
	if existingWarningLight then existingWarningLight.Enabled = false end
	local exploded = false
	local warningActive = false
	local warningGeneration = nil
	local warningSound
	local stopWarningPulse = function() end
	local function stopWarningSound()
		if warningSound and warningSound.Parent then
			warningSound:Stop()
			warningSound:Destroy()
		end
		warningSound = nil
	end
	local function explode()
		if exploded or not warningGeneration or not roundIsActive(warningGeneration) then return end
		exploded = true
		warningActive = false
		model:SetAttribute("BombWarningActive", false)

		local root = getRoot(model)
		local position = root and root.Position or model:GetPivot().Position
		stopWarningPulse()
		stopWarningSound()
		makeExplosionVisual(position)
		playExplosionSound(model, position)
		damagePlayers(position, warningGeneration)
		damageMonsters(model, position, warningGeneration)
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
		local generation = tonumber(Workspace:GetAttribute("RoundGeneration"))
		if warningActive or exploded or not model.Parent or not generation or not roundIsActive(generation) then return end
		warningActive = true
		warningGeneration = generation
		model:SetAttribute("BombWarningActive", true)
		stopWarningPulse = startWarningPulse(model, generation)
		warningSound = playWarningSound(model)
		task.delay(Config.WARNING_TIME, function()
			if roundIsActive(generation) then explode() end
		end)
	end

	-- A bomb takes four MG1 hits to arm. Player weapons record LastAttackerId
	-- before changing Health, which keeps incidental NPC damage from activating
	-- the warning sequence.
	humanoid.HealthChanged:Connect(function(health)
		if Workspace:GetAttribute("RoundState") ~= "Active" then return end
		local damageTaken = humanoid.MaxHealth - health
		if not warningActive and not exploded
			and damageTaken >= Config.PLAYER_ARM_DAMAGE
			and humanoid:GetAttribute("LastAttackerId")
		then
			beginWarning()
		end
	end)

	humanoid.Died:Connect(function()
		if Workspace:GetAttribute("RoundState") ~= "Active" then return end
		if warningActive then return end
		if humanoid:GetAttribute("LastAttackerId") then
			beginWarning()
		else
			-- Non-player deaths retain their immediate blast, but only inside the
			-- currently active round generation.
			warningGeneration = tonumber(Workspace:GetAttribute("RoundGeneration"))
			if warningGeneration then explode() end
		end
	end)

	task.spawn(function()
		task.wait(math.random(Config.MIN_WAIT, Config.MAX_WAIT))
		if exploded or not model.Parent or humanoid.Health <= 0 or Workspace:GetAttribute("RoundState") ~= "Active" then return end

		-- The imported warning asset is a complete spoken five-to-one countdown,
		-- not a one-second beep. Start it once and let the announcement finish.
		beginWarning()
	end)

	model.Destroying:Connect(function()
		stopWarningPulse()
		stopWarningSound()
		activeBombs[model] = nil
	end)

	local roundStateConnection
	roundStateConnection = Workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
		if Workspace:GetAttribute("RoundState") == "Active" then return end
		-- A phase change cancels this warning rather than allowing an old timer to
		-- detonate during the next generation.
		stopWarningPulse()
		stopWarningSound()
		warningActive = false
		warningGeneration = nil
		model:SetAttribute("BombWarningActive", false)
	end)
	model.Destroying:Once(function()
		if roundStateConnection then roundStateConnection:Disconnect() end
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

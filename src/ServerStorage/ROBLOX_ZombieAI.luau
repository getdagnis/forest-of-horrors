local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local HumanoidList = require(ServerStorage:WaitForChild("ROBLOX_HumanoidList"))
local AIUtilities = require(ServerStorage:WaitForChild("ROBLOX_AIUtilities"))

local ZombieAI = {}

local function updateDisplay(display, state)
	task.spawn(function()
		while display.Parent do
			task.wait()

			if state then
				display.Text = state.Name
			end
		end
	end)
end

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(model)
	return model:FindFirstChildOfClass("Humanoid")
end

local function getPlayerCharacterFromHit(hit)
	local current = hit

	while current do
		if current:IsA("Model") and Players:GetPlayerFromCharacter(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

ZombieAI.new = function(model)
	local zombie = {}
	local configTable = model:WaitForChild("Configurations")
	local configs = {}

	local function loadConfig(configName, defaultValue)
		local value = configTable:FindFirstChild(configName)
		configs[configName] = value and value.Value or defaultValue
	end

	loadConfig("AttackRange", 3)
	loadConfig("FieldOfView", 180)
	loadConfig("AggroRange", 200)
	loadConfig("ChanceOfBoredom", 0.5)
	loadConfig("BoredomDuration", 10)
	loadConfig("Damage", 10)
	loadConfig("DamageCooldown", 1)

	local StateMachine = require(ServerStorage:WaitForChild("ROBLOX_StateMachine")).new()
	local PathLib = require(ServerStorage:WaitForChild("ROBLOX_PathfindingLibrary")).new()
	local ZombieTarget = nil
	local ZombieTargetLastLocation = nil
	local lastBored = os.time()

	local IdleState = StateMachine.NewState()
	IdleState.Name = "Idle"
	IdleState.Init = function()
		lastBored = os.time()
	end

	local SearchState = StateMachine.NewState()
	SearchState.Name = "Search"

	local lastMoved = os.time()
	local searchTarget = nil

	SearchState.Action = function()
		local root = getRoot(model)
		if not root then return end

		local now = os.time()

		if now - lastMoved > 2 then
			lastMoved = now
			searchTarget = AIUtilities:FindCloseEmptySpace(model)
		end

		if searchTarget then
			PathLib:MoveToTarget(model, searchTarget)
		end
	end

	SearchState.Init = function()
		lastBored = os.time()
	end

	local PursueState = StateMachine.NewState()
	PursueState.Name = "Pursue"
	PursueState.Action = function()
		local root = getRoot(model)

		if ZombieTarget and root and ZombieTarget:FindFirstChild("HumanoidRootPart") then
			local targetRoot = ZombieTarget.HumanoidRootPart
			local distance = (root.Position - targetRoot.Position).Magnitude

			if distance > configs["AttackRange"] + 5 then
				PathLib:MoveToTarget(model, targetRoot.Position)
			else
				model.Humanoid:MoveTo(targetRoot.Position)
			end
		end
	end

	local AttackState = StateMachine.NewState()
	AttackState.Name = "Attack"

	local lastAttack = os.time()
	local attackTrack = nil
	local animations = model:FindFirstChild("Animations")

	if animations and animations:FindFirstChild("Attack") then
		attackTrack = model.Humanoid:LoadAnimation(animations.Attack)
	end

	AttackState.Action = function()
		if not ZombieTarget or not ZombieTarget:FindFirstChild("HumanoidRootPart") then
			return
		end

		model.Humanoid:MoveTo(ZombieTarget.HumanoidRootPart.Position)

		local now = os.time()
		if attackTrack and now - lastAttack > 3 then
			lastAttack = now
			attackTrack:Play()
		end
	end

	local HuntState = StateMachine.NewState()
	HuntState.Name = "Hunt"
	HuntState.Action = function()
		if ZombieTargetLastLocation then
			PathLib:MoveToTarget(model, ZombieTargetLastLocation)
		end
	end
	HuntState.Init = function()
		lastBored = os.time() + configs["BoredomDuration"] / 2
	end

	local CanSeeTarget = StateMachine.NewCondition()
	CanSeeTarget.Name = "CanSeeTarget"
	CanSeeTarget.Evaluate = function()
		local root = getRoot(model)
		if not root then return false end

		local humanoids = HumanoidList:GetCurrent()
		local ignoredCharacters = { model }
		local playerCharacters = {}

		for _, humanoid in pairs(humanoids) do
			local character = humanoid and humanoid.Parent
			local characterRoot = character and character:FindFirstChild("HumanoidRootPart")

			if character and characterRoot and humanoid.Health > 0 and humanoid.WalkSpeed > 0 then
				local distance = (root.Position - characterRoot.Position).Magnitude

				if distance <= configs["AggroRange"] then
					if Players:GetPlayerFromCharacter(character) then
						table.insert(playerCharacters, character)
					else
						table.insert(ignoredCharacters, character)
					end
				end
			end
		end

		local target = AIUtilities:GetClosestVisibleTarget(model, playerCharacters, ignoredCharacters, configs["FieldOfView"])

		if target then
			ZombieTarget = target
			return true
		end

		return false
	end
	CanSeeTarget.TransitionState = PursueState

	local TargetDead = StateMachine.NewCondition()
	TargetDead.Name = "TargetDead"
	TargetDead.Evaluate = function()
		local humanoid = ZombieTarget and getHumanoid(ZombieTarget)
		return not humanoid or humanoid.Health <= 0
	end
	TargetDead.TransitionState = IdleState

	local lastHealth = model.Humanoid.Health
	local GotDamaged = StateMachine.NewCondition()
	GotDamaged.Name = "GotDamaged"
	GotDamaged.Evaluate = function()
		local currentHealth = model.Humanoid.Health
		local damaged = currentHealth < lastHealth
		lastHealth = currentHealth
		return damaged
	end
	GotDamaged.TransitionState = SearchState

	local GotBored = StateMachine.NewCondition()
	GotBored.Name = "GotBored"
	GotBored.Evaluate = function()
		local now = os.time()

		if now - lastBored > configs["BoredomDuration"] then
			local roll = math.random()

			if roll < configs["ChanceOfBoredom"] then
				lastBored = now
				GotBored.TransitionState = GotBored.TransitionState == SearchState and IdleState or SearchState
				return true
			end
		end

		return false
	end
	GotBored.TransitionState = IdleState

	local LostTarget = StateMachine.NewCondition()
	LostTarget.Name = "LostTarget"
	LostTarget.Evaluate = function()
		return false
	end
	LostTarget.TransitionState = HuntState

	local WithinRange = StateMachine.NewCondition()
	WithinRange.Name = "WithinRange"
	WithinRange.Evaluate = function()
		local root = getRoot(model)
		local targetRoot = ZombieTarget and ZombieTarget:FindFirstChild("HumanoidRootPart")

		if root and targetRoot then
			return (root.Position - targetRoot.Position).Magnitude < configs["AttackRange"]
		end

		return false
	end
	WithinRange.TransitionState = AttackState

	local OutsideRange = StateMachine.NewCondition()
	OutsideRange.Name = "OutsideRange"
	OutsideRange.Evaluate = function()
		local root = getRoot(model)
		local targetRoot = ZombieTarget and ZombieTarget:FindFirstChild("HumanoidRootPart")

		if root and targetRoot then
			return (root.Position - targetRoot.Position).Magnitude > configs["AttackRange"]
		end

		return false
	end
	OutsideRange.TransitionState = PursueState

	table.insert(IdleState.Conditions, CanSeeTarget)
	table.insert(IdleState.Conditions, GotDamaged)
	table.insert(IdleState.Conditions, GotBored)
	table.insert(SearchState.Conditions, GotBored)
	table.insert(SearchState.Conditions, CanSeeTarget)
	table.insert(PursueState.Conditions, LostTarget)
	table.insert(PursueState.Conditions, WithinRange)
	table.insert(PursueState.Conditions, TargetDead)
	table.insert(AttackState.Conditions, OutsideRange)
	table.insert(AttackState.Conditions, TargetDead)
	table.insert(HuntState.Conditions, GotBored)
	table.insert(HuntState.Conditions, CanSeeTarget)

	local canHit = true
	local lastHit = os.time()

	local function handleHit(other)
		if canHit then
			local character = getPlayerCharacterFromHit(other)
			local enemyHumanoid = character and getHumanoid(character)

			if enemyHumanoid and enemyHumanoid.WalkSpeed > 0 and enemyHumanoid.Health > 0 then
				enemyHumanoid:TakeDamage(configs["Damage"])
				canHit = false
			end
		else
			local now = os.time()

			if now - lastHit > configs["DamageCooldown"] then
				lastHit = now
				canHit = true
			end
		end
	end

	local leftArm = model:FindFirstChild("Left Arm")
	local rightArm = model:FindFirstChild("Right Arm")

	if leftArm then leftArm.Touched:Connect(handleHit) end
	if rightArm then rightArm.Touched:Connect(handleHit) end

	task.spawn(function()
		while model.Parent do
			task.wait()

			local root = getRoot(model)
			if not root then continue end

			local humanoids = HumanoidList:GetCurrent()
			local localZombies = {}

			for _, humanoid in pairs(humanoids) do
				local otherModel = humanoid and humanoid.Parent
				local otherRoot = otherModel and otherModel:FindFirstChild("HumanoidRootPart")

				if humanoid ~= model.Humanoid and otherRoot then
					local distance = (root.Position - otherRoot.Position).Magnitude
					if distance <= 2.5 then
						table.insert(localZombies, otherRoot.Position)
					end
				end
			end

			local force = root:FindFirstChild("RepulsionForce")
			if force then
				force.Force = AIUtilities:GetRepulsionVector(root.Position, localZombies)
			end

			local debugConfig = model.Configurations:FindFirstChild("Debug")
			local billboard = model:FindFirstChild("BillboardGui")
			local textLabel = billboard and billboard:FindFirstChild("TextLabel")

			if debugConfig and textLabel then
				textLabel.Visible = debugConfig.Value

				if StateMachine.CurrentState and debugConfig.Value then
					textLabel.Text = StateMachine.CurrentState.Name
				end
			end
		end
	end)

	StateMachine.SwitchState(IdleState)

	zombie.Stop = function()
		StateMachine.SwitchState(nil)
	end

	return zombie
end

return ZombieAI

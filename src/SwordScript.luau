-- SwordScript

Tool = script.Parent
Handle = Tool:WaitForChild("Handle")

function Create(ty)
	return function(data)
		local obj = Instance.new(ty)
		for k, v in pairs(data) do
			if type(k) == 'number' then
				v.Parent = obj
			else
				obj[k] = v
			end
		end
		return obj
	end
end

local BaseUrl = "rbxassetid://"

Players = game:GetService("Players")
Debris = game:GetService("Debris")
ReplicatedStorage = game:GetService("ReplicatedStorage")

MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local FLASH_COLOR = Color3.fromRGB(0, 172, 182)
local SCORE_COLOR = Color3.fromRGB(255, 238, 150)
local PUSH_DISTANCE = 6
local PUSH_TIME = 0.12

DamageValues = {
	BaseDamage = 5,
	SlashDamage = 10,
	LungeDamage = 30
}

--For R15 avatars
Animations = {
	R15Slash = 522635514,
	R15Lunge = 522638767
}

Damage = DamageValues.BaseDamage

Grips = {
	Up = CFrame.Angles(0, 0, -math.pi / 2),
	Out = CFrame.Angles(0, 0, -math.pi / 2)
}

Sounds = {
	Slash = Handle:WaitForChild("SwordSlash"),
	Ignite = Handle:WaitForChild("SwordIgnite")
}

ToolEquipped = false

--For Omega Rainbow Katana thumbnail to display a lot of particles.
for i, v in pairs(Handle:GetChildren()) do
	if v:IsA("ParticleEmitter") then
		v.Rate = 20
	end
end

Tool.Grip = Grips.Up
Tool.Enabled = true

function TagHumanoid(humanoid, player)
	local Creator_Tag = Instance.new("ObjectValue")
	Creator_Tag.Name = "creator"
	Creator_Tag.Value = player
	Debris:AddItem(Creator_Tag, 2)
	Creator_Tag.Parent = humanoid
end

function UntagHumanoid(humanoid)
	for i, v in pairs(humanoid:GetChildren()) do
		if v:IsA("ObjectValue") and v.Name == "creator" then
			v:Destroy()
		end
	end
end

local function getMonsterModelFromHit(hit)
	local current = hit
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local flashing = {}

local function flashMonster(model)
	local state = flashing[model]
	if not state then
		state = { parts = {}, token = 0 }
		flashing[model] = state
		for _, item in model:GetDescendants() do
			if item:IsA("BasePart") then
				state.parts[item] = { color = item.Color, material = item.Material }
			end
		end
	end

	for part in pairs(state.parts) do
		if part.Parent then
			part.Color = FLASH_COLOR
			part.Material = Enum.Material.Neon
		end
	end

	state.token += 1
	local token = state.token
	task.delay(0.1, function()
		if flashing[model] ~= state or state.token ~= token then return end
		flashing[model] = nil
		for part, values in pairs(state.parts) do
			if part.Parent then
				part.Color = values.color
				part.Material = values.material
			end
		end
	end)
end

local function pushMonsterBack(model)
	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Torso", true)
	if not root or not root:IsA("BasePart") or not Torso or not Torso.Parent then return end

	local direction = root.Position - Torso.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.1 then
		direction = Vector3.new(Torso.CFrame.LookVector.X, 0, Torso.CFrame.LookVector.Z)
	end
	if direction.Magnitude < 0.1 then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "LightsaberPushAttachment"
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "LightsaberPush"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 80000
	velocity.VectorVelocity = direction.Unit * (PUSH_DISTANCE / PUSH_TIME)
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = root
	Debris:AddItem(velocity, PUSH_TIME)
	Debris:AddItem(attachment, PUSH_TIME)
end

function Blow(Hit)
	if not Hit or not Hit.Parent or not CheckIfAlive() or not ToolEquipped then
		return
	end
	local RightArm = Character:FindFirstChild("Right Arm") or Character:FindFirstChild("RightHand")
	if not RightArm then
		return
	end
	local RightGrip = RightArm:FindFirstChild("RightGrip")
	if not RightGrip or (RightGrip.Part0 ~= Handle and RightGrip.Part1 ~= Handle) then
		return
	end
	local monsterModel = getMonsterModelFromHit(Hit)
	if not monsterModel then return end
	local monsterHumanoid = MonsterManager.getMonsterHumanoid(monsterModel)
	if not monsterHumanoid or monsterHumanoid.Health <= 0 then return end

	UntagHumanoid(monsterHumanoid)
	TagHumanoid(monsterHumanoid, Player)
	MonsterManager.recordPlayerDamage(monsterHumanoid, Player, Damage, SCORE_COLOR)
	monsterHumanoid:TakeDamage(Damage)
	flashMonster(monsterModel)
	pushMonsterBack(monsterModel)
end


function Attack()
	Damage = DamageValues.SlashDamage
	Sounds.Slash:Play()

	if Humanoid then
		if Humanoid.RigType == Enum.HumanoidRigType.R6 then
			local Anim = Instance.new("StringValue")
			Anim.Name = "toolanim"
			Anim.Value = "Slash"
			Anim.Parent = Tool
		elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
			local Anim = Tool:FindFirstChild("R15Slash")
			if Anim then
				local Track = Humanoid:LoadAnimation(Anim)
				Track:AdjustSpeed(2)
				Track:Play(0)
			end
		end
	end	
end

Tool.Enabled = true

function Activated()
	if not Tool.Enabled or not ToolEquipped or not CheckIfAlive() then
		return
	end
	Tool.Enabled = false
	Attack()
	Damage = DamageValues.BaseDamage
	local SlashAnim = (Tool:FindFirstChild("R15Slash") or Create("Animation"){
		Name = "R15Slash",
		AnimationId = BaseUrl .. Animations.R15Slash,
		Parent = Tool
	})

	local LungeAnim = (Tool:FindFirstChild("R15Lunge") or Create("Animation"){
		Name = "R15Lunge",
		AnimationId = BaseUrl .. Animations.R15Lunge,
		Parent = Tool
	})
	task.delay(0.15, function()
		if Tool.Parent then
			Tool.Enabled = true
		end
	end)
end

function CheckIfAlive()
	return (((Player and Player.Parent and Character and Character.Parent and Humanoid and Humanoid.Parent and Humanoid.Health > 0 and Torso and Torso.Parent) and true) or false)
end

function Equipped()
	Character = Tool.Parent
	Player = Players:GetPlayerFromCharacter(Character)
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	Torso = Character:FindFirstChild("Torso") or Character:FindFirstChild("HumanoidRootPart")
	if not CheckIfAlive() then
		return
	end
	ToolEquipped = true
	Sounds.Ignite:Play()
end

function Unequipped()
	Tool.Grip = Grips.Up
	ToolEquipped = false
end

Tool.Activated:Connect(Activated)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)

for _, part in Tool:GetChildren() do
	if part:IsA("BasePart") then
		part.Touched:Connect(Blow)
	end
end

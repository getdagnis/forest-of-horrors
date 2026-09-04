-- BatScript. Place this Script inside the Baseball Bat Tool.
-- A simple emergency melee weapon: pull back, strike through, recover.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Tool = script.Parent
local Handle = Tool:WaitForChild("Handle")
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

-- Feel tuning: all bat balance and motion values live here.
local DAMAGE_PER_HIT = 60 -- two clean hits kill a zombie
local SWING_COOLDOWN = 0.70 -- recovery between swings
local FOLLOW_THROUGH_SECONDS = 0.45 -- readable but still defensive-speed swing
local STRIKE_SECONDS = 0.20 -- active hit portion of the rotation
-- Intentionally silly emergency-weapon motion: one complete X-axis propeller
-- rotation around the holding hand, starting and ending upright.
local PROPELLER_END_X_DEGREES = 360
local HITBOX_SIZE = Vector3.new(8, 6, 8) -- a useful close-range escape arc
local HITBOX_FORWARD_OFFSET = 3.5 -- starts just ahead of player
local PUSH_DISTANCE = 8 -- create real running room
local PUSH_TIME = 0.20 -- shove duration
local ZOMBIE_STAGGER_SECONDS = 1.10 -- AI pauses before pursuit resumes
local SCORE_COLOR = Color3.fromRGB(255, 238, 150)

local Sounds = {
	Swing = Handle:WaitForChild("Swing"),
	Hit = Handle:WaitForChild("Hit"),
}

local character
local player
local humanoid
local torso
local equipped = false
local swingActive = false
local swingToken = 0
local hitModels = {}
local hitSoundPlayed = false
local restingGrip = Tool.Grip

Tool.Enabled = true

local function checkIfAlive()
	return player and player.Parent
		and character and character.Parent
		and humanoid and humanoid.Parent
		and humanoid.Health > 0
		and torso and torso.Parent
end

local function isStillHeld()
	if not checkIfAlive() or not equipped then return false end
	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	if not rightArm then return false end
	local rightGrip = rightArm:FindFirstChild("RightGrip")
	return rightGrip and (rightGrip.Part0 == Handle or rightGrip.Part1 == Handle)
end

local function tagHumanoid(targetHumanoid)
	for _, child in ipairs(targetHumanoid:GetChildren()) do
		if child:IsA("ObjectValue") and child.Name == "creator" then child:Destroy() end
	end
	local creatorTag = Instance.new("ObjectValue")
	creatorTag.Name = "creator"
	creatorTag.Value = player
	creatorTag.Parent = targetHumanoid
	Debris:AddItem(creatorTag, 2)
end

local function getMonsterModelFromHit(hit)
	local current = hit
	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then return current end
		current = current.Parent
	end
	return nil
end

local function pushMonsterBack(model)
	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Torso", true)
	if not root or not root:IsA("BasePart") or not torso or not torso.Parent then return end

	local direction = root.Position - torso.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.1 then
		direction = Vector3.new(torso.CFrame.LookVector.X, 0, torso.CFrame.LookVector.Z)
	end
	if direction.Magnitude < 0.1 then return end

	local attachment = Instance.new("Attachment")
	attachment.Name = "BatPushAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "BatPush"
	velocity.Attachment0 = attachment
	velocity.MaxForce = 80000
	velocity.VectorVelocity = direction.Unit * (PUSH_DISTANCE / PUSH_TIME)
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.Parent = root
	Debris:AddItem(velocity, PUSH_TIME)
	Debris:AddItem(attachment, PUSH_TIME)
end

local function damageMonster(model)
	if hitModels[model] or not isStillHeld() then return end
	local targetHumanoid = MonsterManager.getMonsterHumanoid(model)
	if not targetHumanoid or targetHumanoid.Health <= 0 then return end

	hitModels[model] = true
	tagHumanoid(targetHumanoid)
	MonsterManager.recordPlayerDamage(targetHumanoid, player, DAMAGE_PER_HIT, SCORE_COLOR)
	-- The knockback alone is cosmetic if the zombie immediately issues another
	-- MoveTo.  Its AI honours this short-lived state and then resumes normally.
	if model.Name == "Drooling Zombie" then
		model:SetAttribute("BatStaggeredUntil", Workspace:GetServerTimeNow() + ZOMBIE_STAGGER_SECONDS)
	end
	targetHumanoid:TakeDamage(DAMAGE_PER_HIT)
	if not hitSoundPlayed then
		hitSoundPlayed = true
		Sounds.Hit:Play()
	end
	pushMonsterBack(model)
end

local function blow(hit)
	if not swingActive or not hit or not hit.Parent then return end
	local monsterModel = getMonsterModelFromHit(hit)
	if monsterModel then damageMonster(monsterModel) end
end

local function scanStrikeArea()
	if not swingActive or not isStillHeld() then return end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { character, Tool }
	overlap.MaxParts = 40
	local hitboxCFrame = torso.CFrame * CFrame.new(0, 0, -HITBOX_FORWARD_OFFSET)
	for _, part in ipairs(Workspace:GetPartBoundsInBox(hitboxCFrame, HITBOX_SIZE, overlap)) do
		local monsterModel = getMonsterModelFromHit(part)
		if monsterModel then damageMonster(monsterModel) end
	end
end

local function spinPropeller(seconds, token)
	local startedAt = os.clock()
	while equipped and token == swingToken do
		local progress = math.clamp((os.clock() - startedAt) / seconds, 0, 1)
		local angle = PROPELLER_END_X_DEGREES * progress
		-- Set each intermediate angle directly. CFrame:Lerp would choose the
		-- shortest path and turn this into a small, ordinary sideways swing.
		Tool.Grip = restingGrip * CFrame.Angles(math.rad(angle), 0, 0)
		if progress >= 1 then return true end
		RunService.Heartbeat:Wait()
	end
	return false
end

local function swing()
	if not Tool.Enabled or not isStillHeld() then return end
	Tool.Enabled = false
	swingToken += 1
	local token = swingToken
	hitModels = {}
	hitSoundPlayed = false
	local startedAt = os.clock()

	Sounds.Swing:Play()
	swingActive = true
	task.spawn(function()
		spinPropeller(FOLLOW_THROUGH_SECONDS, token)
	end)
	local strikeEndsAt = os.clock() + STRIKE_SECONDS
	while os.clock() < strikeEndsAt and equipped and token == swingToken do
		scanStrikeArea()
		RunService.Heartbeat:Wait()
	end
	scanStrikeArea()
	swingActive = false

	local remainingCooldown = SWING_COOLDOWN - (os.clock() - startedAt)
	if remainingCooldown > 0 then task.wait(remainingCooldown) end
	if equipped and token == swingToken then Tool.Enabled = true end
end

Tool.Activated:Connect(swing)

Tool.Equipped:Connect(function()
	character = Tool.Parent
	player = Players:GetPlayerFromCharacter(character)
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	torso = character and (character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart"))
	restingGrip = Tool.Grip
	equipped = checkIfAlive()
end)

Tool.Unequipped:Connect(function()
	equipped = false
	swingActive = false
	swingToken += 1
	Tool.Grip = restingGrip
	Tool.Enabled = true
end)

for _, part in ipairs(Tool:GetDescendants()) do
	if part:IsA("BasePart") then part.Touched:Connect(blow) end
end

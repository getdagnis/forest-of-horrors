local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local connected = {}

local function scatterCreepyCorpse(model)
	if string.sub(model.Name, 1, #"creepyMonster") ~= "creepyMonster" then return end
	if model:GetAttribute("CreepyCorpseScattered") then return end
	model:SetAttribute("CreepyCorpseScattered", true)

	-- Creepy models place their visible mesh beside the nested Noob humanoid
	-- rig. Humanoid.BreakJointsOnDeath only affects that nested rig, leaving the
	-- outer MeshPart frozen. This death-only fallback scatters both layers.
	local originPart = model:FindFirstChild("HumanoidRootPart", true)
	local origin = originPart and originPart:IsA("BasePart") and originPart.Position
		or model:GetPivot().Position
	for _, item in model:GetDescendants() do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
			item:Destroy()
		end
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = true
			part.CanTouch = false
			part.Massless = false
			local direction = part.Position - origin
			if direction.Magnitude < 0.1 then
				direction = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
			end
			part.AssemblyLinearVelocity = direction.Unit * math.random(30, 55)
				+ Vector3.new(0, math.random(15, 35), 0)
			part.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		end
	end
end

local function flashTwice(model)
	local flash = Instance.new("Highlight")
	flash.Name = "MonsterDeathFlash"
	flash.FillColor = Color3.fromRGB(255, 238, 250)
	flash.FillTransparency = 0.08
	flash.OutlineTransparency = 1
	flash.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	flash.Parent = model

	for _ = 1, 2 do
		flash.Enabled = true
		task.wait(0.10)
		flash.Enabled = false
		task.wait(0.08)
	end

	if flash.Parent then flash:Destroy() end
end

local function stopCorpse(model, humanoid)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	scatterCreepyCorpse(model)
	task.spawn(flashTwice, model)

	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			item.CanTouch = false
		elseif item:IsA("BaseScript") then
			item.Disabled = true
		end
	end
end

local function monitor(model)
	if not model:IsA("Model") or not MonsterManager.getConfig(model) then return end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or connected[humanoid] then return end
	connected[humanoid] = true

	humanoid.Died:Connect(function()
		stopCorpse(model, humanoid)
	end)
end

for _, instance in workspace:GetDescendants() do monitor(instance) end
workspace.DescendantAdded:Connect(monitor)

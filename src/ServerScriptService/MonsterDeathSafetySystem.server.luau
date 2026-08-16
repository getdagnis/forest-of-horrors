local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local connected = {}

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

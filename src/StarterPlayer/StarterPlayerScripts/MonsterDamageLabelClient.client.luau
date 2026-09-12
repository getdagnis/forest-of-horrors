-- Private numeric health feedback.  This GUI lives in the local PlayerGui, so
-- only the player whose validated hit caused it can see the current / max text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local damageLabelEvent = ReplicatedStorage:WaitForChild("MonsterDamageLabel")
local labels = {}

local function getDisplayPart(model)
	local preferred = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model.PrimaryPart
	if preferred and preferred:IsA("BasePart") then return preferred end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

damageLabelEvent.OnClientEvent:Connect(function(model, health, maxHealth, generation)
	if workspace:GetAttribute("RoundState") ~= "Active"
		or tonumber(generation) ~= tonumber(workspace:GetAttribute("RoundGeneration"))
	then
		return
	end
	if not model or not model:IsA("Model") or not model.Parent then return end
	local adornee = getDisplayPart(model)
	if not adornee then return end

	local gui = labels[model]
	if not gui or not gui.Parent then
		gui = Instance.new("BillboardGui")
		gui.Name = "PrivateMonsterDamageLabel"
		gui.Size = UDim2.fromOffset(180, 44)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.ResetOnSpawn = false
		gui.Parent = player:WaitForChild("PlayerGui")
		labels[model] = gui

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Parent = gui
	end

	gui.Adornee = adornee
	gui.Enabled = true
	local label = gui:FindFirstChild("Label")
	if not label or not label:IsA("TextLabel") then return end
	label.Text = math.max(0, math.ceil(tonumber(health) or 0)) .. " / " .. math.ceil(tonumber(maxHealth) or 0)
	local token = (gui:GetAttribute("HideToken") or 0) + 1
	gui:SetAttribute("HideToken", token)
	task.delay(1.5, function()
		if gui.Parent and gui:GetAttribute("HideToken") == token then
			gui:Destroy()
			labels[model] = nil
		end
	end)
end)

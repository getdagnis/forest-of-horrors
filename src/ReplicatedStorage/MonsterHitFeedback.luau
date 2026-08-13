local Debris = game:GetService("Debris")

local MonsterHitFeedback = {}

local activeFlashes = {}

local function getDisplayPart(model)
	local preferred = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model.PrimaryPart

	if preferred and preferred:IsA("BasePart") then
		return preferred
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function setBodyColors(bodyColors, color)
	bodyColors.HeadColor3 = color
	bodyColors.LeftArmColor3 = color
	bodyColors.RightArmColor3 = color
	bodyColors.LeftLegColor3 = color
	bodyColors.RightLegColor3 = color
	bodyColors.TorsoColor3 = color
end

function MonsterHitFeedback.illuminate(model, color, duration)
	local adornee = getDisplayPart(model)
	if not adornee then return end

	local light = Instance.new("PointLight")
	light.Name = "MonsterHitImpactLight"
	light.Color = color
	light.Brightness = 12
	light.Range = 20
	light.Shadows = true
	light.Parent = adornee
	Debris:AddItem(light, (duration or 0.25) + 0.05)
end

function MonsterHitFeedback.flash(model, color, duration)
	duration = duration or 0.25

	local state = activeFlashes[model]
	if not state then
		state = {
			parts = {},
			bodyColors = {},
			token = 0,
		}
		activeFlashes[model] = state

		for _, item in model:GetDescendants() do
			if item:IsA("BodyColors") then
				state.bodyColors[item] = {
					head = item.HeadColor3,
					leftArm = item.LeftArmColor3,
					rightArm = item.RightArmColor3,
					leftLeg = item.LeftLegColor3,
					rightLeg = item.RightLegColor3,
					torso = item.TorsoColor3,
				}
			elseif item:IsA("BasePart") then
				state.parts[item] = {
					color = item.Color,
					material = item.Material,
				}
			end
		end
	end

	for bodyColors in pairs(state.bodyColors) do
		if bodyColors.Parent then
			setBodyColors(bodyColors, color)
		end
	end

	for part in pairs(state.parts) do
		if part.Parent then
			part.Color = color
			part.Material = Enum.Material.Neon
		end
	end

	MonsterHitFeedback.illuminate(model, color, duration)

	state.token += 1
	local token = state.token
	task.delay(duration, function()
		if activeFlashes[model] ~= state or state.token ~= token then return end
		activeFlashes[model] = nil

		for bodyColors, values in pairs(state.bodyColors) do
			if bodyColors.Parent then
				bodyColors.HeadColor3 = values.head
				bodyColors.LeftArmColor3 = values.leftArm
				bodyColors.RightArmColor3 = values.rightArm
				bodyColors.LeftLegColor3 = values.leftLeg
				bodyColors.RightLegColor3 = values.rightLeg
				bodyColors.TorsoColor3 = values.torso
			end
		end

		for part, values in pairs(state.parts) do
			if part.Parent then
				part.Color = values.color
				part.Material = values.material
			end
		end
	end)
end

function MonsterHitFeedback.showHealth(model, humanoid, displayHealth)
	local adornee = getDisplayPart(model)
	if not adornee then return end

	local gui = model:FindFirstChild("MonsterHealthGui")
	if not gui then
		gui = Instance.new("BillboardGui")
		gui.Name = "MonsterHealthGui"
		gui.Size = UDim2.fromOffset(180, 44)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = model

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
	if label then
		label.Text = math.max(0, math.ceil(displayHealth == nil and humanoid.Health or displayHealth))
			.. " / " .. math.ceil(humanoid.MaxHealth)
	end

	local token = (gui:GetAttribute("HideToken") or 0) + 1
	gui:SetAttribute("HideToken", token)
	task.delay(1.5, function()
		if gui.Parent and gui:GetAttribute("HideToken") == token then
			gui.Enabled = false
		end
	end)
end

return MonsterHitFeedback

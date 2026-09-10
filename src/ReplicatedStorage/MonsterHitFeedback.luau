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

function MonsterHitFeedback.illuminate(model, color, duration)
	local adornee = getDisplayPart(model)
	if not adornee then return end

	local light = Instance.new("PointLight")
	light.Name = "MonsterHitImpactLight"
	light.Color = color
	light.Brightness = 12
	light.Range = 20
	light.Shadows = false
	light.Parent = adornee
	Debris:AddItem(light, (duration or 0.15) + 0.15)
end

function MonsterHitFeedback.flash(model, color, duration, includeLight)
	duration = duration or 0.15

	local state = activeFlashes[model]
	local highlight = state and state.highlight
	if not highlight or not highlight.Parent then
		highlight = Instance.new("Highlight")
		highlight.Name = "MonsterHitFlash"
		highlight.Adornee = model
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillTransparency = 0.35
		highlight.OutlineTransparency = 0.1
		highlight.Parent = model

		state = { highlight = highlight, token = 0 }
		activeFlashes[model] = state
	end

	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Enabled = true
	if includeLight ~= false then MonsterHitFeedback.illuminate(model, color, duration) end

	state.token += 1
	local token = state.token
	task.delay(duration, function()
		if activeFlashes[model] ~= state or state.token ~= token then return end
		activeFlashes[model] = nil
		if highlight.Parent then highlight:Destroy() end
	end)
end

return MonsterHitFeedback

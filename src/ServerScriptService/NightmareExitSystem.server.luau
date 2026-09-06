-- NightmareExitSystem: the bedroom portal only becomes usable after the
-- shared hunt is cleared. Entering it is an individual player's escape.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PORTAL_ATTRIBUTE = "NightmareExitPortal"
local ESCAPE_ACTIVE_ATTRIBUTE = "NightmareEscapeActive"

local function getOrCreateRemoteEvent(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if event and event:IsA("RemoteEvent") then return event end
	event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local escapedEvent = getOrCreateRemoteEvent("NightmareEscaped")
local portalRecords = setmetatable({}, { __mode = "k" })
local connectedParts = setmetatable({}, { __mode = "k" })

local function getLivingPlayer(hit)
	local current = hit
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(current)
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			if player and humanoid and humanoid.Health > 0 then return player end
		end
		current = current.Parent
	end
	return nil
end

local function setPortalOpen(portal, isOpen)
	local record = portalRecords[portal]
	if not record then return end
	portal:SetAttribute("NightmareExitPortalOpen", isOpen)
	record.highlight.Enabled = isOpen
	for _, effect in ipairs(record.effects) do
		if effect.instance.Parent then
			if effect.kind == "Light" then
				effect.instance.Enabled = isOpen and effect.enabled or false
				effect.instance.Brightness = isOpen and math.max(effect.brightness, 5) or 0
			else
				effect.instance.Enabled = isOpen and effect.enabled or false
			end
		end
	end
end

local function refreshAllPortals()
	local open = Workspace:GetAttribute(ESCAPE_ACTIVE_ATTRIBUTE) == true
	for portal in pairs(portalRecords) do
		if portal.Parent then
			setPortalOpen(portal, open)
		else
			portalRecords[portal] = nil
		end
	end
end

local function connectPortalPart(part)
	if connectedParts[part] then return end
	connectedParts[part] = true
	part.CanTouch = true
	part.Touched:Connect(function(hit)
		if Workspace:GetAttribute(ESCAPE_ACTIVE_ATTRIBUTE) ~= true then return end
		local player = getLivingPlayer(hit)
		if not player or player:GetAttribute("EscapedNightmare") == true then return end

		player:SetAttribute("EscapedNightmare", true)
		escapedEvent:FireClient(player)
	end)
end

local function registerPortal(portal)
	if portalRecords[portal] then return end
	local parts = {}
	if portal:IsA("BasePart") then
		table.insert(parts, portal)
	elseif portal:IsA("Model") then
		for _, descendant in ipairs(portal:GetDescendants()) do
			if descendant:IsA("BasePart") then table.insert(parts, descendant) end
		end
	end
	if #parts == 0 then
		warn("[NightmareExitSystem] portal has no BasePart:", portal:GetFullName())
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "NightmareExitPortalGlow"
	highlight.Adornee = portal
	highlight.FillColor = Color3.fromRGB(69, 220, 255)
	highlight.FillTransparency = 0.72
	highlight.OutlineColor = Color3.fromRGB(202, 129, 255)
	highlight.OutlineTransparency = 0.08
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = portal

	local effects = {}
	for _, descendant in ipairs(portal:GetDescendants()) do
		if descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
			table.insert(effects, { kind = "Light", instance = descendant, enabled = descendant.Enabled, brightness = descendant.Brightness })
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			table.insert(effects, { kind = "Effect", instance = descendant, enabled = descendant.Enabled })
		end
	end

	portalRecords[portal] = { highlight = highlight, effects = effects }
	for _, part in ipairs(parts) do connectPortalPart(part) end
	setPortalOpen(portal, Workspace:GetAttribute(ESCAPE_ACTIVE_ATTRIBUTE) == true)
	warn("[NightmareExitSystem] portal registered:", portal:GetFullName())
end

local function inspect(instance)
	if (instance:IsA("Model") or instance:IsA("BasePart")) and instance:GetAttribute(PORTAL_ATTRIBUTE) == true then
		registerPortal(instance)
	end
end

for _, instance in ipairs(Workspace:GetDescendants()) do inspect(instance) end
Workspace.DescendantAdded:Connect(function(instance)
	task.defer(inspect, instance)
end)
Workspace:GetAttributeChangedSignal(ESCAPE_ACTIVE_ATTRIBUTE):Connect(refreshAllPortals)

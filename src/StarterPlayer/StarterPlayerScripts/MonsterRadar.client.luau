-- MonsterRadar > StarterPlayerScripts Local
-- Local combat radar: no labels, no server work, and no wall-visibility rules.
-- It reports every living canonical monster within RADAR_RANGE around the player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local CLOSE_CROWD_RANGE = 50
local CROWD_RADAR_RANGE = 30
local NORMAL_RADAR_RANGE = 50
local SEARCH_RADAR_RANGES = { 50, 70, 100, 130, 160, 200 }
local MAX_RADAR_RANGE = SEARCH_RADAR_RANGES[#SEARCH_RADAR_RANGES]
local UPDATE_SECONDS = 0.12
local DOT_SIZE = 6
local MAX_DOTS = 96
local PRIORITY_WARNING_RANGE = 80
local MONSTER_DOT_COLOR = Color3.fromRGB(238, 67, 70)
local BOMB_DOT_COLOR = Color3.fromRGB(255, 174, 192)
local PET_DOT_COLOR = Color3.fromRGB(190, 255, 75)
local BOMB_WARNING_PULSE_SPEED = math.pi * 3
local RADAR_CONTACT_COUNT_ATTRIBUTE = "MonsterRadarContactCount"

-- Other local presentation systems may wait for a truly quiet radar window.
-- -1 means the radar cannot currently produce a trustworthy contact count.
player:SetAttribute(RADAR_CONTACT_COUNT_ATTRIBUTE, -1)

local gui = Instance.new("ScreenGui")
gui.Name = "MonsterRadarHud"
gui.ResetOnSpawn = false
-- Deliberately use viewport coordinates: the top-right is clear of CoreGui,
-- and a CoreUISafeInsets offset pushes the radar far too low on tablets.
gui.IgnoreGuiInset = true
local playerGui = player:WaitForChild("PlayerGui")
-- Studio has previously accumulated duplicate active MonsterRadar scripts.
-- Whichever current copy starts last becomes the sole visual owner.
for _, existing in ipairs(playerGui:GetChildren()) do
	if existing.Name == gui.Name then
		existing:Destroy()
	end
end
gui.Parent = playerGui

local radar = Instance.new("Frame")
radar.Name = "Radar"
radar.AnchorPoint = Vector2.new(1, 0)
radar.Position = UDim2.new(1, -12, 0, 62)
radar.Size = UDim2.fromOffset(128, 128)
radar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
radar.BackgroundTransparency = 0.8
radar.BorderSizePixel = 0
radar.ClipsDescendants = true
radar.Parent = gui
local radarCorner = Instance.new("UICorner")
radarCorner.CornerRadius = UDim.new(1, 0)
radarCorner.Parent = radar
local radarStroke = Instance.new("UIStroke")
radarStroke.Color = Color3.fromRGB(82, 109, 132)
radarStroke.Transparency = 0.6
radarStroke.Parent = radar

-- Native GUI has no sector primitive. Stacked clipped strips form a real
-- forward fan from the player dot to 12 o'clock without an uploaded asset.
local sector = Instance.new("Folder")
sector.Name = "ForwardSector"
sector.Parent = radar
local SECTOR_STRIPS = 14
for index = 1, SECTOR_STRIPS do
	local progress = index / SECTOR_STRIPS
	local strip = Instance.new("Frame")
	strip.Name = "SectorStrip"
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Position = UDim2.new(0.5, 0, 0.5 - progress * 0.46, 0)
	strip.Size = UDim2.new(progress * 0.64, 0, 0.46 / SECTOR_STRIPS, 1)
	strip.BackgroundColor3 = Color3.fromRGB(105, 185, 230)
	strip.BackgroundTransparency = 0.91
	strip.BorderSizePixel = 0
	strip.ZIndex = 1
	strip.Parent = sector
end

local selfDot = Instance.new("Frame")
selfDot.Name = "PlayerDot"
selfDot.AnchorPoint = Vector2.new(0.5, 0.5)
selfDot.Position = UDim2.fromScale(0.5, 0.5)
selfDot.Size = UDim2.fromOffset(8, 8)
selfDot.BackgroundColor3 = Color3.fromRGB(117, 210, 255)
selfDot.BorderSizePixel = 0
selfDot.ZIndex = 3
selfDot.Parent = radar
local selfCorner = Instance.new("UICorner")
selfCorner.CornerRadius = UDim.new(1, 0)
selfCorner.Parent = selfDot

-- Only appears when the adaptive search reaches 200 studs without finding a
-- monster. It points to the nearest monster that is still beyond radar range.
local outsideCue = Instance.new("Frame")
outsideCue.Name = "NearestOutsideCue"
outsideCue.AnchorPoint = Vector2.new(0.5, 0.5)
outsideCue.Size = UDim2.fromOffset(16, 3)
outsideCue.BackgroundColor3 = Color3.fromRGB(151, 221, 255)
outsideCue.BackgroundTransparency = 0.08
outsideCue.BorderSizePixel = 0
outsideCue.Visible = false
outsideCue.ZIndex = 3
outsideCue.Parent = radar
local outsideCueCorner = Instance.new("UICorner")
outsideCueCorner.CornerRadius = UDim.new(1, 0)
outsideCueCorner.Parent = outsideCue

local dots = {}
for index = 1, MAX_DOTS do
	local dot = Instance.new("Frame")
	dot.Name = "MonsterDot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(DOT_SIZE, DOT_SIZE)
	dot.BackgroundColor3 = MONSTER_DOT_COLOR
	dot.BorderSizePixel = 0
	dot.Visible = false
	dot.ZIndex = 2
	dot.Parent = radar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = dot
	local ring = Instance.new("UIStroke")
	ring.Name = "ContactRing"
	ring.Color = BOMB_DOT_COLOR
	ring.Thickness = 1.5
	ring.Enabled = false
	ring.Parent = dot

	-- A warning bomb receives a second concentric circle. It lives inside each
	-- pooled contact so switching marker types cannot leave an old ring behind.
	local warningRing = Instance.new("Frame")
	warningRing.Name = "BombWarningRing"
	warningRing.AnchorPoint = Vector2.new(0.5, 0.5)
	warningRing.Position = UDim2.fromScale(0.5, 0.5)
	warningRing.Size = UDim2.fromScale(1.5, 1.5)
	warningRing.BackgroundTransparency = 1
	warningRing.BorderSizePixel = 0
	warningRing.Visible = false
	warningRing.ZIndex = 2
	warningRing.Parent = dot
	local warningCorner = Instance.new("UICorner")
	warningCorner.CornerRadius = UDim.new(1, 0)
	warningCorner.Parent = warningRing
	local warningStroke = Instance.new("UIStroke")
	warningStroke.Name = "WarningStroke"
	warningStroke.Color = BOMB_DOT_COLOR
	warningStroke.Thickness = 1.5
	warningStroke.Parent = warningRing
	dots[index] = dot
end

local trackedMonsters = {}
local radarEntries = {}
local function track(instance)
	if instance:IsA("Model") and MonsterManager.getConfig(instance) then trackedMonsters[instance] = true end
end
for _, instance in ipairs(workspace:GetDescendants()) do track(instance) end
workspace.DescendantAdded:Connect(track)
workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("Model") then
		trackedMonsters[instance] = nil
		radarEntries[instance] = nil
	end
end)

local function getMonsterPosition(model)
	local part = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("Head", true)
		or model.PrimaryPart
	if part and part:IsA("BasePart") then return part.Position end
	return nil
end

local function isPriorityMonster(model)
	return model.Name == "creepyMonster"
		or model.Name == "creepyMonsterOrange"
		or model.Name == "creepyMonsterWhite"
		or model.Name == "Smiler"
		or (model:FindFirstChild("Zombie") and model:FindFirstChild("Zombie"):IsA("Humanoid"))
end

local function playPriorityWarning()
	-- Audio is optional: accept a directly placed sound or a named warning inside
	-- a RadarSounds folder, without creating/depending on a new shared asset.
	local sound = SoundService:FindFirstChild("MonsterRadarWarning")
		or SoundService:FindFirstChild("RadarWarning")
		or (SoundService:FindFirstChild("RadarSounds") and SoundService.RadarSounds:FindFirstChild("Warning"))
	if not (sound and sound:IsA("Sound")) then return end

	local clone = sound:Clone()
	clone.Parent = SoundService
	clone:Play()
	clone.Ended:Connect(function() clone:Destroy() end)
	task.delay(math.max(2, clone.TimeLength + 1), function()
		if clone.Parent then clone:Destroy() end
	end)
end

local function updateLayout()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
	local small = viewport.X < 800 or viewport.Y < 500
	local mobile = viewport.X < 1100 or viewport.Y < 650
	local diameter = mobile and (small and 92 or 128) or 192
	radar.Size = UDim2.fromOffset(diameter, diameter)
	radar.Position = UDim2.new(1, -12, 0, mobile and 72 or 160)
end

local elapsed = UPDATE_SECONDS
RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < UPDATE_SECONDS then return end
	elapsed = 0
	updateLayout()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then
		for _, dot in ipairs(dots) do dot.Visible = false end
		player:SetAttribute(RADAR_CONTACT_COUNT_ATTRIBUTE, -1)
		return
	end

	local livingMonsters = {}
	for model in pairs(trackedMonsters) do
		local humanoid = model.Parent and MonsterManager.getMonsterHumanoid(model)
		local position = humanoid and humanoid.Health > 0 and getMonsterPosition(model)
		if position then
			local offset = position - root.Position
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			table.insert(livingMonsters, {
				model = model,
				offset = flatOffset,
				distance = flatOffset.Magnitude,
				priority = isPriorityMonster(model),
			})
		end
	end

	-- Adaptive range: dense close crowds collapse to 30; a normal local threat
	-- stays at 50; otherwise expand through 70/100/130/160 to 200 studs.
	local closeCount = 0
	local normalCount = 0
	for _, monster in ipairs(livingMonsters) do
		-- WMTs remain visible as outlined red contacts, but they are calm world
		-- actors rather than battle contacts and must not stop the search from
		-- expanding toward actual round monsters.
		if MonsterManager.isRoundTracked(monster.model) and monster.distance <= CLOSE_CROWD_RANGE then
			closeCount += 1
			normalCount += 1
		end
	end
	local radarRange = NORMAL_RADAR_RANGE
	if closeCount >= 10 then
		radarRange = CROWD_RADAR_RANGE
	elseif normalCount == 0 then
		for _, searchRange in ipairs(SEARCH_RADAR_RANGES) do
			radarRange = searchRange
			local found = false
			for _, monster in ipairs(livingMonsters) do
				if MonsterManager.isRoundTracked(monster.model) and monster.distance <= searchRange then
					found = true
					break
				end
			end
			if found then break end
		end
	end

	local shown = 0
	local nearestOutside
	local now = os.clock()
	for _, monster in ipairs(livingMonsters) do
		local entry = radarEntries[monster.model] or {}
		local inRange = monster.distance <= radarRange
		-- Priority threats are tracked early, but the audible warning is emitted
		-- only on the same boundary that makes the contact dot visible. This keeps
		-- the warning and radar direction synchronized.
		entry.priorityDetected = monster.priority and monster.distance <= PRIORITY_WARNING_RANGE
		if monster.priority and inRange and not entry.inRange then
			playPriorityWarning()
		end
		entry.inRange = inRange
		radarEntries[monster.model] = entry

		if inRange and shown < MAX_DOTS then
			shown += 1
			local localOffset = camera.CFrame:VectorToObjectSpace(monster.offset)
			local scale = 0.43 / radarRange
			local dot = dots[shown]
			local bomb = monster.model.Name == "BombMonster"
			local guardian = monster.model.Name == "weird monster thing"
			local pet = guardian and monster.model:GetAttribute("WMTGuardianPet") == true
			local warningBomb = bomb and monster.model:GetAttribute("BombWarningActive") == true
			local pulse = (math.sin(now * BOMB_WARNING_PULSE_SPEED) + 1) * 0.5
			local dotSize = bomb and DOT_SIZE * 2 or (monster.priority and DOT_SIZE * 2 or DOT_SIZE)
			dot.Size = UDim2.fromOffset(dotSize, dotSize)
			dot.BackgroundColor3 = bomb and BOMB_DOT_COLOR or (pet and PET_DOT_COLOR or MONSTER_DOT_COLOR)
			dot.BackgroundTransparency = (bomb or guardian) and 1 or 0
			local ring = dot:FindFirstChild("ContactRing")
			if ring and ring:IsA("UIStroke") then
				ring.Color = bomb and BOMB_DOT_COLOR or (pet and PET_DOT_COLOR or MONSTER_DOT_COLOR)
				ring.Thickness = warningBomb and (1.5 + pulse) or 1.5
				ring.Transparency = warningBomb and (0.4 - pulse * 0.35) or 0
				ring.Enabled = bomb or guardian
			end
			local warningRing = dot:FindFirstChild("BombWarningRing")
			if warningRing and warningRing:IsA("Frame") then
				warningRing.Size = UDim2.fromScale(1.5 + pulse * 0.7, 1.5 + pulse * 0.7)
				warningRing.Visible = warningBomb
				local warningStroke = warningRing:FindFirstChild("WarningStroke")
				if warningStroke and warningStroke:IsA("UIStroke") then
					warningStroke.Transparency = 0.8 - pulse * 0.65
				end
			end
			dot.Position = UDim2.fromScale(0.5 + localOffset.X * scale, 0.5 + localOffset.Z * scale)
			dot.Visible = true
		elseif MonsterManager.isRoundTracked(monster.model)
			and radarRange == MAX_RADAR_RANGE
			and monster.distance > MAX_RADAR_RANGE
			and (not nearestOutside or monster.distance < nearestOutside.distance)
		then
			nearestOutside = monster
		end
	end
	for index = shown + 1, MAX_DOTS do dots[index].Visible = false end
	player:SetAttribute(RADAR_CONTACT_COUNT_ATTRIBUTE, shown)

	if radarRange == MAX_RADAR_RANGE and shown == 0 and nearestOutside then
		local localOffset = camera.CFrame:VectorToObjectSpace(nearestOutside.offset)
		local direction = Vector2.new(localOffset.X, localOffset.Z).Unit
		outsideCue.Position = UDim2.fromScale(0.5 + direction.X * 0.45, 0.5 + direction.Y * 0.45)
		outsideCue.Rotation = math.deg(math.atan2(direction.Y, direction.X))
		outsideCue.Visible = true
	else
		outsideCue.Visible = false
	end
end)

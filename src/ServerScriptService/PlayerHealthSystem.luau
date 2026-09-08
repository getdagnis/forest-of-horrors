-- PlayerHealthSystem

-- PlayerHealthSystem: Sets default player HP to 100 and manages bonus HP from eating BigMacs.
-- Eating a BigMac grants +10 bonus HP (up to 60 bonus, max total 160 HP).
-- BigMacs reappear 30 seconds after being eaten.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local HARD_MAX_HP = 100
local EASY_MAX_HP = 200
local MAX_BONUS_HP = 60
local HP_PER_BURGER = 10
local BIGMAC_RESPAWN_TIME = 30
local LEMON_GREEN = Color3.fromRGB(135, 255, 42)
local HEAL_SOUND_ID = "rbxassetid://3120609559"

local mcdonalds = Workspace:FindFirstChild("McDonald's")
local bigmac = mcdonalds and mcdonalds:FindFirstChild("BigMac")

-- Track whether the BigMac is currently available (not on cooldown)
local bigmacAvailable = bigmac ~= nil
local bigmacOriginalParts = {}

local function getBaseMaxHP(player)
	return player:GetAttribute("Difficulty") == "Easy" and EASY_MAX_HP or HARD_MAX_HP
end

---------------------------------------------------------------------------
-- Player HP setup
---------------------------------------------------------------------------

local function setupCharacter(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Read any persisted bonus HP from the player attribute (survives respawns)
	local bonusHP = player:GetAttribute("BonusHP") or 0

	local maxHealth = getBaseMaxHP(player) + bonusHP
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	-- ScoreGui owns the player's health presentation. Suppress Roblox's
	-- world-space Humanoid bar so it cannot cover the scoreboard/radar.
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	-- Store the bonus on the humanoid too for convenience
	humanoid:SetAttribute("BonusHP", bonusHP)
end

local function applyDifficulty(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local bonusHP = player:GetAttribute("BonusHP") or 0
	humanoid.MaxHealth = getBaseMaxHP(player) + bonusHP
	humanoid.Health = humanoid.MaxHealth
	humanoid:SetAttribute("BonusHP", bonusHP)
end

local function onPlayerAdded(player)
	-- Initialize bonus attribute if not already set
	if not player:GetAttribute("BonusHP") then
		player:SetAttribute("BonusHP", 0)
	end

	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	player:GetAttributeChangedSignal("Difficulty"):Connect(function()
		applyDifficulty(player)
	end)

	-- Handle characters that already exist
	if player.Character then
		setupCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

---------------------------------------------------------------------------
-- BigMac eating system
---------------------------------------------------------------------------

local function isBigMacAvailable()
	return bigmacAvailable and bigmac and bigmac.Parent ~= nil
end

local function forEachBasePart(root, callback)
	if root:IsA("BasePart") then
		callback(root)
	end
	for _, item in root:GetDescendants() do
		if item:IsA("BasePart") then
			callback(item)
		end
	end
end

local function getDisplayPart(root)
	if root:IsA("BasePart") then return root end
	return root.PrimaryPart or root:FindFirstChildWhichIsA("BasePart", true)
end

local function flashSource(source)
	local part = getDisplayPart(source)
	if not part then return end

	local originalColor = part.Color
	local originalMaterial = part.Material
	part.Color = LEMON_GREEN
	part.Material = Enum.Material.Neon

	local light = Instance.new("PointLight")
	light.Color = LEMON_GREEN
	light.Brightness = 16
	light.Range = 20
	light.Shadows = true
	light.Parent = part

	task.delay(0.25, function()
		if part.Parent then
			part.Color = originalColor
			part.Material = originalMaterial
		end
		if light.Parent then light:Destroy() end
	end)
end

local function showHealthGain(character, root, gained)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthGainGui"
	gui.Size = UDim2.fromOffset(150, 40)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	gui.Parent = character

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = LEMON_GREEN
	label.TextStrokeTransparency = 0
	label.Text = "+" .. tostring(gained) .. " health"
	label.Parent = gui
	Debris:AddItem(gui, 1.4)
end

local function hideBigMac()
	if not bigmac then return end
	bigmacAvailable = false
	forEachBasePart(bigmac, function(part)
		if not bigmacOriginalParts[part] then
			bigmacOriginalParts[part] = {
				transparency = part.Transparency,
				canCollide = part.CanCollide,
				canQuery = part.CanQuery,
				canTouch = part.CanTouch,
			}
		end
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end)
end

local function showBigMac()
	if not bigmac then return end
	forEachBasePart(bigmac, function(part)
		local original = bigmacOriginalParts[part]
		if original then
			part.Transparency = original.transparency
			part.CanCollide = original.canCollide
			part.CanQuery = original.canQuery
			part.CanTouch = original.canTouch
		end
	end)
	bigmacAvailable = true
end

local bigmacDebounce = false

local function checkBigMacProximity()
	if not isBigMacAvailable() or bigmacDebounce then return end
	if not bigmac then return end

	local cf, size = bigmac:GetBoundingBox()
	local center = cf.Position
	-- Use a generous detection radius based on the BigMac's bounding box
	local radius = math.max(size.X, size.Y, size.Z) / 2 + 4

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - center).Magnitude
			if distance <= radius then
				bigmacDebounce = true

				-- Grant bonus HP
				local currentBonus = player:GetAttribute("BonusHP") or 0
				if currentBonus >= MAX_BONUS_HP then
					-- Already at max bonus, don't consume the burger
					bigmacDebounce = false
					return
				end

				local newBonus = math.min(currentBonus + HP_PER_BURGER, MAX_BONUS_HP)
				player:SetAttribute("BonusHP", newBonus)
				humanoid:SetAttribute("BonusHP", newBonus)

				-- Increase MaxHealth and heal by the bonus amount gained
				local gained = newBonus - currentBonus
				local baseMaxHP = getBaseMaxHP(player)
				humanoid.MaxHealth = baseMaxHP + newBonus
				humanoid.Health = math.min(humanoid.Health + gained, humanoid.MaxHealth)

				-- Play heal sound
				local root = character:FindFirstChild("HumanoidRootPart")
				if root then
					local sound = Instance.new("Sound")
					sound.SoundId = HEAL_SOUND_ID
					sound.Volume = 0.8
					sound.Parent = root
					sound:Play()
					Debris:AddItem(sound, 3)
				end
				showHealthGain(character, root, gained)
				flashSource(bigmac)

				-- Double flash lemon green on the player
				local existingHighlight = character:FindFirstChild("HealFlashHighlight")
				if existingHighlight then existingHighlight:Destroy() end

	local highlight = Instance.new("Highlight")
				highlight.Name = "HealFlashHighlight"
				highlight.FillColor3 = LEMON_GREEN
				highlight.OutlineColor3 = LEMON_GREEN
				highlight.FillTransparency = 0.3
				highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	local healLight = Instance.new("PointLight")
	healLight.Name = "HealFlashLight"
	healLight.Color = LEMON_GREEN
	healLight.Brightness = 18
	healLight.Range = 20
	healLight.Shadows = true
	healLight.Parent = root

				-- Flash 1: visible
				highlight.FillTransparency = 0.3
				highlight.OutlineTransparency = 0
				task.delay(0.15, function()
					if not highlight.Parent then return end
		-- Gap: invisible
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 1
		healLight.Brightness = 0
					task.delay(0.1, function()
						if not highlight.Parent then return end
		-- Flash 2: visible
		highlight.FillTransparency = 0.3
		highlight.OutlineTransparency = 0
		healLight.Brightness = 18
		task.delay(0.15, function()
			if highlight and highlight.Parent then
				highlight:Destroy()
			end
			if healLight and healLight.Parent then
				healLight:Destroy()
			end
						end)
					end)
				end)

				-- Hide the BigMac and schedule its reappearance
				hideBigMac()

				task.delay(BIGMAC_RESPAWN_TIME, function()
					showBigMac()
				end)

				task.wait(1)
				bigmacDebounce = false
				return
			end
		end
	end
end

-- Proximity check loop (runs every 0.25 seconds)
task.spawn(function()
	while true do
		checkBigMacProximity()
		task.wait(0.25)
	end
end)

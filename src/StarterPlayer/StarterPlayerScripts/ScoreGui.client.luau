-- ScoreGui >> StarterPlayerScripts
-- Compact combat status bar. Detailed standings remain in Roblox's default
-- player list through leaderstats, rather than competing with combat space.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local scoreEvent = ReplicatedStorage:WaitForChild("ScoreUpdate")
local monsterCountEvent = ReplicatedStorage:WaitForChild("MonsterCountUpdate")
local recordsEvent = ReplicatedStorage:WaitForChild("RecordsUpdate")

local currentScore = 0
local currentKills = 0
local monstersLeft = 0
local bestSpawn = 0
local monsterHistory = {}
local roundStartedAt = workspace:GetAttribute("RoundStartedAt") or workspace:GetServerTimeNow()

local gui = Instance.new("ScreenGui")
gui.Name = "CombatStatusHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
pcall(function()
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)
local playerGui = player:WaitForChild("PlayerGui")
gui.Parent = playerGui

local function removeLegacyMonsterHud(instance)
	if instance and instance.Name == "MonsterHud" then instance:Destroy() end
end
removeLegacyMonsterHud(playerGui:FindFirstChild("MonsterHud"))
playerGui.ChildAdded:Connect(removeLegacyMonsterHud)

local bar = Instance.new("Frame")
bar.Name = "CombatStatusBar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 12)
bar.Size = UDim2.new(1, -24, 0, 82)
bar.BackgroundTransparency = 1
bar.Parent = gui

local function makePanel(name, position, size)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Position = position
	panel.Size = size
	panel.BackgroundColor3 = Color3.fromRGB(8, 13, 20)
	panel.BackgroundTransparency = 0.18
	panel.BorderSizePixel = 0
	panel.Parent = bar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(64, 84, 104)
	stroke.Transparency = 0.55
	stroke.Thickness = 1
	stroke.Parent = panel
	return panel
end

local function makeText(parent, name, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeTransparency = 0.72
	label.Parent = parent
	return label
end

local timePanel = makePanel("GameTimePanel", UDim2.new(), UDim2.new())
local healthPanel = makePanel("HealthPanel", UDim2.new(), UDim2.new())
local rankPanel = makePanel("RankPanel", UDim2.new(), UDim2.new())
local monstersPanel = makePanel("MonstersPanel", UDim2.new(), UDim2.new())
local spawnPanel = makePanel("BestSpawnPanel", UDim2.new(), UDim2.new())
rankPanel.BackgroundColor3 = Color3.fromRGB(101, 13, 44)

local timeLabel = makeText(timePanel, "Time", Color3.fromRGB(210, 221, 232))
local healthLabel = makeText(healthPanel, "Health", Color3.fromRGB(220, 245, 255))
local rankLabel = makeText(rankPanel, "Rank", Color3.fromRGB(244, 231, 170))
local monstersLabel = makeText(monstersPanel, "MonstersLeft", Color3.fromRGB(255, 213, 218))
local spawnLabel = makeText(spawnPanel, "BestSpawn", Color3.fromRGB(205, 225, 246))

local function makeCaption(parent, text)
	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.AnchorPoint = Vector2.new(0.5, 1)
	caption.Position = UDim2.new(0.5, 0, 1, -5)
	caption.Size = UDim2.new(1, -10, 0, 17)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Gotham
	caption.TextColor3 = Color3.fromRGB(225, 231, 239)
	caption.TextSize = 13
	caption.TextScaled = false
	caption.TextStrokeTransparency = 0.82
	caption.Text = text
	caption.Parent = parent
	return caption
end

local timeCaption = makeCaption(timePanel, "GAME TIME")
local healthCaption = makeCaption(healthPanel, "HEALTH")
local rankCaption = makeCaption(rankPanel, "")
local monstersCaption = makeCaption(monstersPanel, "MONSTERS (+0)")
local spawnCaption = makeCaption(spawnPanel, "BEST SPAWN")

local function updateLayout()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.zero
	local compact = viewport.X < 1100 or viewport.Y < 650
	local small = viewport.X < 700 or viewport.Y < 430
	local sideWidth = small and 68 or (compact and 80 or 150)
	local rankWidth = small and 120 or (compact and 140 or 200)
	local gap = small and 2 or (compact and 4 or 12)
	local sideHeight = small and 48 or (compact and 54 or 64)
	local rankHeight = small and 58 or (compact and 64 or 82)
	bar.Size = UDim2.new(1, -24, 0, rankHeight)
	rankPanel.AnchorPoint = Vector2.new(0.5, 0)
	rankPanel.Position = UDim2.new(0.5, 0, 0, 0)
	rankPanel.Size = UDim2.fromOffset(rankWidth, rankHeight)
	for _, panel in ipairs({ timePanel, healthPanel, monstersPanel, spawnPanel }) do
		panel.Size = UDim2.fromOffset(sideWidth, sideHeight)
	end
	healthPanel.AnchorPoint = Vector2.new(1, 0.5)
	healthPanel.Position = UDim2.new(0.5, -rankWidth / 2 - gap, 0.5, 0)
	timePanel.AnchorPoint = Vector2.new(1, 0.5)
	timePanel.Position = UDim2.new(0.5, -rankWidth / 2 - gap * 2 - sideWidth, 0.5, 0)
	monstersPanel.AnchorPoint = Vector2.new(0, 0.5)
	monstersPanel.Position = UDim2.new(0.5, rankWidth / 2 + gap, 0.5, 0)
	spawnPanel.AnchorPoint = Vector2.new(0, 0.5)
	spawnPanel.Position = UDim2.new(0.5, rankWidth / 2 + gap * 2 + sideWidth, 0.5, 0)
	for _, label in ipairs({ timeLabel, healthLabel, monstersLabel, spawnLabel }) do
		label.Position = UDim2.new(0, 0, 0, 0)
		label.Size = UDim2.new(1, 0, 1, -18)
		label.TextSize = small and 18 or (compact and 22 or 30)
		label.TextScaled = false
	end
	rankLabel.Position = UDim2.new(0, 0, 0, 2)
	rankLabel.Size = UDim2.new(1, 0, 0, small and 38 or 52)
	rankLabel.TextSize = small and 28 or (compact and 32 or 44)
	rankLabel.TextScaled = false
	for _, caption in ipairs({ timeCaption, healthCaption, monstersCaption, spawnCaption }) do
		caption.TextSize = small and 8 or (compact and 10 or 13)
	end
	rankCaption.TextSize = small and 9 or (compact and 11 or 14)
end

local function ordinal(value)
	local remainder = value % 100
	if remainder >= 11 and remainder <= 13 then return tostring(value) .. "th" end
	local endings = { [1] = "st", [2] = "nd", [3] = "rd" }
	return tostring(value) .. (endings[value % 10] or "th")
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function getRank()
	local entries = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local leaderstats = other:FindFirstChild("leaderstats")
		local score = leaderstats and leaderstats:FindFirstChild("Score")
		table.insert(entries, { player = other, score = score and score.Value or 0 })
	end
	table.sort(entries, function(a, b)
		if a.score == b.score then return a.player.Name < b.player.Name end
		return a.score > b.score
	end)
	for index, entry in ipairs(entries) do
		if entry.player == player then return index end
	end
	return 1
end

local function updateHealth()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local percent = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth * 100, 0, 999) or 0
	healthLabel.Text = percent >= 999 and "999+" or string.format("%d%%", math.floor(percent + 0.5))
	if percent >= 200 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(34, 0, 46)
	elseif percent >= 110 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(0, 53, 89)
	elseif percent >= 86 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(0, 69, 11)
	elseif percent >= 66 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(79, 102, 3)
	elseif percent >= 56 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(159, 161, 41)
	elseif percent >= 36 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(161, 133, 41)
	elseif percent >= 20 then
		healthPanel.BackgroundColor3 = Color3.fromRGB(161, 62, 0)
	else
		healthPanel.BackgroundColor3 = Color3.fromRGB(148, 25, 0)
	end
end

local function bindCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	humanoid.HealthChanged:Connect(updateHealth)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
	updateHealth()
end

scoreEvent.OnClientEvent:Connect(function(score, kills)
	currentScore = tonumber(score) or 0
	currentKills = tonumber(kills) or currentKills
end)
monsterCountEvent.OnClientEvent:Connect(function(count)
	monstersLeft = math.max(0, tonumber(count) or 0)
	table.insert(monsterHistory, { time = workspace:GetServerTimeNow(), count = monstersLeft })
end)
recordsEvent.OnClientEvent:Connect(function(data)
	bestSpawn = tonumber(data and data.serverBestSpawn) or 0
	currentKills = tonumber(data and data.currentKills) or currentKills
end)
workspace:GetAttributeChangedSignal("RoundStartedAt"):Connect(function()
	roundStartedAt = workspace:GetAttribute("RoundStartedAt") or workspace:GetServerTimeNow()
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local uiElapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	uiElapsed += deltaTime
	if uiElapsed < 0.1 then return end
	uiElapsed = 0
	updateLayout()
	timeLabel.Text = formatTime(workspace:GetServerTimeNow() - roundStartedAt)
	rankLabel.Text = ordinal(getRank())
	rankCaption.RichText = true
	rankCaption.Text = "<b>" .. tostring(currentScore) .. "</b> SCORE / " .. tostring(currentKills) .. " KILLS"
	monstersLabel.Text = tostring(monstersLeft)
	local now = workspace:GetServerTimeNow()
	while #monsterHistory > 0 and monsterHistory[1].time < now - 10 do table.remove(monsterHistory, 1) end
	local baseline = monsterHistory[1] and monsterHistory[1].count or monstersLeft
	monstersCaption.Text = string.format("MONSTERS (%+d)", monstersLeft - baseline)
	spawnLabel.Text = tostring(bestSpawn)
end)

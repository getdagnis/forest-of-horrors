-- ScoreGui > StarterPlayerScripts
-- One compact combat HUD. Server events remain authoritative; this client only
-- presents their latest state and safely supports older RecordsUpdate payloads.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

-- Events are grouped inside a short burst window, then remain readable long
-- enough for a player to expand the panel and inspect them.
local EVENT_GROUP_WINDOW_SECONDS = 4
local EVENT_DISPLAY_WINDOW_SECONDS = 24
local MAX_RECENT_EVENTS = 12

-- HUD layout tuning. These positions are pixel offsets from the viewport, not
-- Roblox's top-bar safe area, so the desktop bar can use the clear top-right.
local scorebar_position = {
	desktop = Vector2.new(-24, 24),
	mobile = Vector2.new(-12, 16),
}
local scorepanel_position = {
	desktop = Vector2.new(16, 90),
	mobile = Vector2.new(12, 72),
}
local large_font_size = 16
local details_font_size = 8
local DAMAGE_FLASH_MIN_OPACITY = 0.20
local DAMAGE_FLASH_MAX_OPACITY = 0.45
local FALLBACK_HURT_SOUND_ID = "rbxasset://sounds/uuhhh.wav"
-- Ordinary regeneration arrives as +1 ticks. Only deliberate bonus healing
-- should interrupt combat with a flash/message.
local MIN_REPORTED_HEAL = 5

local player = Players.LocalPlayer

-- ScoreGui is the game's health HUD. Hide Roblox's separate CoreGui health
-- meter so it does not appear over the scoreboard after taking damage.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)
task.defer(function()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
end)

local scoreEvent = ReplicatedStorage:WaitForChild("ScoreUpdate")
local monsterCountEvent = ReplicatedStorage:WaitForChild("MonsterCountUpdate")
local recordsEvent = ReplicatedStorage:WaitForChild("RecordsUpdate")
local radarEvents = ReplicatedStorage:WaitForChild("RadarEvents")
local bestSpawnAnnouncementEvent = ReplicatedStorage:WaitForChild("BestSpawnAnnouncement")

local currentScore, currentKills, monstersLeft, bestSpawn = 0, 0, 0, 0
local monsterHistory, recordRows, allTimeBest = {}, {}, nil

local gui = Instance.new("ScreenGui")
gui.Name = "CombatStatusHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
-- ScreenGui.DisplayOrder controls stacking against other ScreenGuis; child
-- ZIndex only controls stacking inside this HUD. Keep combat beneath flow UI.
gui.DisplayOrder = 0
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local playerGui = player:WaitForChild("PlayerGui")
gui.Parent = playerGui

local function removeLegacyMonsterHud(instance)
	if instance and instance.Name == "MonsterHud" then instance:Destroy() end
end
removeLegacyMonsterHud(playerGui:FindFirstChild("MonsterHud"))
playerGui.ChildAdded:Connect(removeLegacyMonsterHud)

local function newFrame(name, parent, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color or Color3.fromRGB(8, 13, 20)
	frame.BackgroundTransparency = 0.18
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(64, 84, 104)
	stroke.Transparency = 0.55
	stroke.Parent = frame
	return frame
end

local function newText(name, parent, color, font)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBold
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.72
	label.Parent = parent
	return label
end

local bar = Instance.new("Frame")
bar.Name = "CombatStatusBar"
bar.BackgroundTransparency = 1
bar.Parent = gui

local panels = {}
local labels = {}
local captions = {}
local function makeCard(key, caption, color)
	local panel = newFrame(key .. "Panel", bar, color)
	panels[key] = panel
	local label = newText(key, panel, Color3.fromRGB(230, 240, 250))
	label.TextXAlignment = Enum.TextXAlignment.Center
	labels[key] = label
	local captionLabel = newText("Caption", panel, Color3.fromRGB(225, 231, 239), Enum.Font.Gotham)
	captionLabel.Text = caption
	captionLabel.TextXAlignment = Enum.TextXAlignment.Center
	captions[key] = captionLabel
end

makeCard("Time", "REMAINING")
makeCard("Health", "HEALTH")
makeCard("Rank", "", Color3.fromRGB(101, 13, 44))
makeCard("Monsters", "MONSTERS (+0)")
makeCard("Spawn", "BEST SPAWN")
labels.Rank.TextColor3 = Color3.fromRGB(255, 215, 241)
labels.Monsters.TextColor3 = Color3.fromRGB(255, 213, 218)

-- Local-only hit feedback. The overlay does not own health or alter damage.
local damageOverlay = Instance.new("Frame")
damageOverlay.Name = "DamageOverlay"
damageOverlay.Size = UDim2.fromScale(1, 1)
damageOverlay.BackgroundColor3 = Color3.fromRGB(220, 0, 0)
damageOverlay.BackgroundTransparency = 1
damageOverlay.BorderSizePixel = 0
damageOverlay.ZIndex = 20
damageOverlay.Parent = gui
local healFlash = Instance.new("Frame")
healFlash.Name = "HealOverlay"
healFlash.Size = UDim2.fromScale(1, 1)
healFlash.BackgroundColor3 = Color3.fromRGB(32, 255, 118)
healFlash.BackgroundTransparency = 1
healFlash.BorderSizePixel = 0
healFlash.ZIndex = 21
healFlash.Parent = gui
local healText = newText("HealText", gui, Color3.fromRGB(105, 255, 147), Enum.Font.GothamBold)
healText.AnchorPoint = Vector2.new(0.5, 0.5)
healText.Position = UDim2.fromScale(0.5, 0.6)
healText.Size = UDim2.fromOffset(260, 46)
healText.TextSize = large_font_size
healText.Visible = false
healText.ZIndex = 22

-- Uses the same bold, outlined, score-popup treatment as score awards; it is
-- a short-lived celebration, never another persistent HUD card.
local bestSpawnText = newText("BestSpawnAnnouncement", gui, Color3.fromRGB(255, 238, 150), Enum.Font.GothamBold)
bestSpawnText.AnchorPoint = Vector2.new(0.5, 0.5)
bestSpawnText.Position = UDim2.fromScale(0.5, 0.54)
bestSpawnText.Size = UDim2.fromOffset(300, 46)
bestSpawnText.TextScaled = true
bestSpawnText.TextStrokeTransparency = 0
bestSpawnText.TextTransparency = 1
bestSpawnText.Visible = false
bestSpawnText.ZIndex = 22
local bestSpawnAnnouncementToken = 0

local scorePanel = newFrame("Scoreboard", gui, Color3.fromRGB(8, 13, 20))
scorePanel.AnchorPoint = Vector2.new(0, 0)
scorePanel.Position = UDim2.new(0, 12, 0, 106)
scorePanel.Size = UDim2.fromOffset(250, 210)
local scoreboardText = newText("Rows", scorePanel, Color3.fromRGB(232, 238, 246), Enum.Font.Gotham)
scoreboardText.Position = UDim2.fromOffset(10, 29)
scoreboardText.Size = UDim2.new(1, -20, 1, -37)
scoreboardText.TextSize = details_font_size
scoreboardText.TextXAlignment = Enum.TextXAlignment.Left
scoreboardText.TextYAlignment = Enum.TextYAlignment.Top
scoreboardText.RichText = true
local scoreboardTitle = newText("Title", scorePanel, Color3.fromRGB(232, 238, 246), Enum.Font.GothamBold)
scoreboardTitle.Position = UDim2.fromOffset(10, 8)
scoreboardText.Size = UDim2.new(1, -20, 1, -37)
scoreboardTitle.Text = "SCOREBOARD"
scoreboardTitle.TextSize = details_font_size
scoreboardTitle.TextXAlignment = Enum.TextXAlignment.Left

local scoreButton = Instance.new("TextButton")
scoreButton.Name = "ScoreButton"
scoreButton.BackgroundColor3 = Color3.fromRGB(8, 13, 20)
scoreButton.BackgroundTransparency = 0.12
scoreButton.BorderSizePixel = 0
scoreButton.Font = Enum.Font.GothamBold
scoreButton.Text = "SCORE"
scoreButton.TextColor3 = Color3.fromRGB(232, 238, 246)
scoreButton.TextSize = details_font_size
scoreButton.Visible = false
scoreButton.Parent = gui
local scoreButtonCorner = Instance.new("UICorner")
scoreButtonCorner.CornerRadius = UDim.new(0, 4)
scoreButtonCorner.Parent = scoreButton
local scoreButtonStroke = Instance.new("UIStroke")
scoreButtonStroke.Color = Color3.fromRGB(64, 84, 104)
scoreButtonStroke.Transparency = 0.4
scoreButtonStroke.Parent = scoreButton

local eventsText = newText("Events", gui, Color3.fromRGB(232, 238, 246), Enum.Font.Gotham)
eventsText.Position = UDim2.fromOffset(12, 272)
eventsText.Size = UDim2.fromOffset(250, 220)
eventsText.TextSize = details_font_size
eventsText.TextXAlignment = Enum.TextXAlignment.Left
eventsText.TextYAlignment = Enum.TextYAlignment.Top
eventsText.TextWrapped = true
eventsText.RichText = true
eventsText.Visible = false

local recentEvents = {}
local function renderEvents(now)
	while #recentEvents > 0 and recentEvents[1].time < now - EVENT_DISPLAY_WINDOW_SECONDS do
		table.remove(recentEvents, 1)
	end
	if #recentEvents == 0 then
		eventsText.Text = ""
		return
	end
	local lines = {}
	for index = #recentEvents, 1, -1 do
		local entry = recentEvents[index]
		local line = "" .. entry.text
		if entry.actorKind == "player" then line = "<b>" .. line .. "</b>" end
		table.insert(lines, line)
	end
	eventsText.Text = table.concat(lines, "\n")
end

radarEvents.OnClientEvent:Connect(function(message)
	if type(message) == "string" then message = { kind = "message", text = message } end
	if type(message) ~= "table" then return end
	local now = workspace:GetServerTimeNow()
	local kind = message.kind or "message"
	local actor = message.actor
	local actorKind = message.actorKind
	local target = message.target
	local targetPlural = message.targetPlural or (target and target .. "s") or "monsters"
	local existing
	for index = #recentEvents, 1, -1 do
		local candidate = recentEvents[index]
		if now - candidate.time > EVENT_GROUP_WINDOW_SECONDS then break end
		if candidate.kind == kind and candidate.actor == actor and candidate.target == target
			and candidate.cause == message.cause then
			existing = candidate
			break
		end
	end
	if kind == "kill" and existing then
		existing.count += 1
		existing.time = now
		existing.actorKind = actorKind or existing.actorKind
		existing.text = string.format("%s kills %d %s", actor, existing.count, existing.targetPlural)
	elseif (kind == "death" or kind == "respawn" or kind == "retire") and existing then
		existing.count += 1
		existing.time = now
		local verb = kind == "respawn" and "respawn" or (kind == "retire" and "retire" or (existing.cause == "fell" and "stupidly fell off the map" or "die (somehow)"))
		if existing.cause == "bomb" then verb = "died in a monsterbomb explosion" end
		existing.text = string.format("%d %s %s", existing.count, existing.targetPlural, verb)
	else
		local text
		if kind == "kill" then
			text = string.format("%s kills %s", actor, target)
		elseif kind == "death" then
			if message.cause == "bomb" then
				text = string.format("%s died in a monsterbomb explosion", target)
			elseif message.cause == "fell" then
				text = string.format("%s stupidly fell off the map", target)
			else
				text = string.format("%s died somehow", target)
			end
		elseif kind == "respawn" then
			text = string.format("%s respawns", target)
		elseif kind == "retire" then
			text = string.format("%s retires", target)
		else
			text = tostring(message.text or "event")
		end
		table.insert(recentEvents, { kind = kind, actor = actor, actorKind = actorKind, target = target, targetPlural = targetPlural, cause = message.cause, count = 1, text = text, time = now })
	end
	while #recentEvents > MAX_RECENT_EVENTS do table.remove(recentEvents, 1) end
	renderEvents(now)
end)

local compactScoreboard = false
local scoreboardExpanded = false
local compactHudLayout = false
scoreButton.Activated:Connect(function()
	if not compactScoreboard then return end
	scoreboardExpanded = not scoreboardExpanded
	scorePanel.Visible = scoreboardExpanded
	scoreButton.Text = scoreboardExpanded and "HIDE" or "SCORE"
end)

local function cardWidth(key, scale)
	local valueWidth = TextService:GetTextSize(labels[key].Text, large_font_size * scale, labels[key].Font, Vector2.new(1000, 60)).X
	local captionWidth = TextService:GetTextSize(captions[key].Text, details_font_size * scale, captions[key].Font, Vector2.new(1000, 40)).X
	return math.max(64 * scale, math.ceil(math.max(valueWidth, captionWidth) + 16 * scale))
end

local function layout()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 1100 or viewport.Y < 650
	compactHudLayout = true
	local wasCompactScoreboard = compactScoreboard
	compactScoreboard = viewport.X < 1025
	if compactScoreboard and not wasCompactScoreboard then scoreboardExpanded = false end
	if not compactScoreboard then scoreboardExpanded = true end
	local scale = mobile and 1 or 2
	local cardHeight = 36 * scale
	local gap = 6 * scale
	-- The compact mobile card design is the single HUD layout on every device.
	-- Its left-to-right order reads right-to-left as score, spawn, monsters,
	-- remaining time, then health.
	local ordered = { "Health", "Time", "Monsters", "Spawn", "Rank" }
	local widths = {}
	local barWidth = 0
	for _, key in ipairs(ordered) do
		widths[key] = cardWidth(key, scale)
		barWidth += widths[key]
	end
	barWidth += gap * (#ordered - 1)
	local barOffset = mobile and scorebar_position.mobile or scorebar_position.desktop
	bar.AnchorPoint = Vector2.new(1, 0)
	bar.Position = UDim2.new(1, barOffset.X, 0, barOffset.Y)
	bar.Size = UDim2.fromOffset(barWidth, cardHeight)
	for index, key in ipairs(ordered) do
		local width = widths[key]
		local x = 0
		for previous = 1, index - 1 do
			x += widths[ordered[previous]] + gap
		end
		local panel = panels[key]
		panel.Position = UDim2.fromOffset(x, 0)
		panel.Size = UDim2.fromOffset(width, cardHeight)
		local label = labels[key]
		label.Position = UDim2.fromOffset(0, scale)
		label.Size = UDim2.new(1, 0, 1, -15 * scale)
		label.TextSize = large_font_size * scale
		local caption = captions[key]
		caption.Position = UDim2.new(0, 0, 1, -16 * scale)
		caption.Size = UDim2.new(1, 0, 0, 12 * scale)
		caption.TextSize = details_font_size * scale
	end
	local panelOffset = mobile and scorepanel_position.mobile or scorepanel_position.desktop
	scoreButton.Position = UDim2.fromOffset(panelOffset.X, panelOffset.Y)
	scoreButton.Size = UDim2.fromOffset(76, 32)
	scoreButton.TextSize = details_font_size * scale
	scoreButton.Visible = compactScoreboard
	scoreButton.Text = scoreboardExpanded and "HIDE" or "SCORE"
	scorePanel.Visible = not compactScoreboard or scoreboardExpanded
	scorePanel.Position = UDim2.fromOffset(panelOffset.X, panelOffset.Y + (compactScoreboard and 38 or 0))
	scorePanel.Size = UDim2.fromOffset(mobile and 210 or 280, mobile and 110 or 150)
	scoreboardTitle.TextSize = details_font_size * scale
	scoreboardTitle.Size = UDim2.new(1, -20, 0, details_font_size * scale)
	scoreboardText.TextSize = details_font_size * scale
	healText.TextSize = large_font_size * scale
	local eventX = panelOffset.X
	local eventY = panelOffset.Y + scorePanel.Size.Y.Offset + 24
	eventsText.Position = UDim2.fromOffset(eventX, eventY)
	eventsText.Size = UDim2.fromOffset(mobile and 190 or 250, mobile and 150 or 220)
	eventsText.LineHeight = 1.2
	eventsText.Visible = not compactScoreboard
	eventsText.TextSize = details_font_size * scale
end

local function ordinal(value)
	local remainder = value % 100
	if remainder >= 11 and remainder <= 13 then return tostring(value) .. "th" end
	local ending = ({ [1] = "st", [2] = "nd", [3] = "rd" })[value % 10] or "th"
	return tostring(value) .. ending
end

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function getRank()
	local entries = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local stats = other:FindFirstChild("leaderstats")
		local score = stats and stats:FindFirstChild("Score")
		table.insert(entries, { player = other, score = score and score.Value or 0 })
	end
	table.sort(entries, function(a, b) return a.score == b.score and a.player.Name < b.player.Name or a.score > b.score end)
	for index, entry in ipairs(entries) do if entry.player == player then return index end end
	return 1
end

local function updateHealthPanel(humanoid)
	local percent = humanoid.MaxHealth > 0 and math.clamp(humanoid.Health / humanoid.MaxHealth * 100, 0, 999) or 0
	labels.Health.Text = percent >= 999 and "999+" or string.format("%d%%", math.floor(percent + 0.5))
	if percent >= 86 then panels.Health.BackgroundColor3 = Color3.fromRGB(0, 69, 11)
	elseif percent >= 56 then panels.Health.BackgroundColor3 = Color3.fromRGB(159, 161, 41)
	elseif percent >= 20 then panels.Health.BackgroundColor3 = Color3.fromRGB(161, 62, 0)
	else panels.Health.BackgroundColor3 = Color3.fromRGB(148, 25, 0) end
end

local feedbackSerial = 0
local fallbackHurtSound

local function getHurtSound()
	local character = player.Character
	local sound = (character and character:FindFirstChild("PlayerHurt", true))
		or gui:FindFirstChild("PlayerHurt", true)
		or playerGui:FindFirstChild("PlayerHurt", true)
		or SoundService:FindFirstChild("PlayerHurt", true)
	if sound and sound:IsA("Sound") then return sound end

	if not fallbackHurtSound then
		fallbackHurtSound = Instance.new("Sound")
		fallbackHurtSound.Name = "PlayerHurtFallback"
		fallbackHurtSound.SoundId = FALLBACK_HURT_SOUND_ID
		fallbackHurtSound.Volume = 0.45
		fallbackHurtSound.Parent = gui
	end
	return fallbackHurtSound
end

local function showDamage(lossPercent)
	feedbackSerial += 1
	local serial = feedbackSerial
	local opacity = math.clamp(lossPercent / 45, DAMAGE_FLASH_MIN_OPACITY, DAMAGE_FLASH_MAX_OPACITY)
	damageOverlay.BackgroundTransparency = 1 - opacity
	TweenService:Create(damageOverlay, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	local hurtSound = getHurtSound()
	if hurtSound then hurtSound:Play() end
	task.delay(0.4, function() if serial == feedbackSerial then damageOverlay.BackgroundTransparency = 1 end end)
end

local function showHeal(amount)
	feedbackSerial += 1
	local serial = feedbackSerial
	healText.Text = "+" .. tostring(math.floor(amount + 0.5)) .. " HP restored"
	healText.Visible = true
	for index = 1, 2 do
		if serial ~= feedbackSerial then return end
		healFlash.BackgroundTransparency = 0.82
		TweenService:Create(healFlash, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
		task.wait(0.26)
	end
	if serial == feedbackSerial then healText.Visible = false end
end

local function bindCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	local previous = humanoid.Health
	updateHealthPanel(humanoid)
	humanoid.HealthChanged:Connect(function(newHealth)
		local oldHealth = previous
		previous = newHealth
		updateHealthPanel(humanoid)
		if newHealth < oldHealth and oldHealth > 0 then
			showDamage((oldHealth - newHealth) / oldHealth * 100)
		elseif humanoid.Health > 0
			and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
			and newHealth - oldHealth >= MIN_REPORTED_HEAL then
			showHeal(newHealth - oldHealth)
		end
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function() updateHealthPanel(humanoid) end)
end

local function normalizeRows(data)
	local list = data and (data.scoreboard or data.players or data.records)
	if type(list) ~= "table" then return nil end
	local result = {}
	for _, row in ipairs(list) do
		if type(row) == "table" then
			table.insert(result, { name = tostring(row.name or row.playerName or row.player or "-"), score = tonumber(row.score) or 0, kills = tonumber(row.kills) or 0, bestSpawn = tonumber(row.bestSpawn or row.personalBestSpawn or row.spawn) or 0 })
		end
	end
	return result
end

local function formatElapsed(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function renderScoreboard()
	local rows = recordRows
	if #rows == 0 then
		for _, other in ipairs(Players:GetPlayers()) do
			local stats = other:FindFirstChild("leaderstats")
			local score = stats and stats:FindFirstChild("Score")
			local kills = stats and stats:FindFirstChild("Kills")
			table.insert(rows, { name = other.Name, score = score and score.Value or 0, kills = kills and kills.Value or 0, bestSpawn = 0 })
		end
		table.sort(rows, function(a, b) return a.score == b.score and a.name < b.name or a.score > b.score end)
	end
	scoreboardTitle.Text = "SCOREBOARD"
	local lines = {}
	for index, row in ipairs(rows) do
		if index > 8 then break end
		local name = row.name == player.Name and '<font color="rgb(190,175,75)">' .. row.name .. "</font>" or row.name
		table.insert(lines, string.format("<b>%d. %s — %d/%d (%d)</b>", index, name, row.score, row.kills, row.bestSpawn))
	end
	if allTimeBest then table.insert(lines, string.format("\nALL-TIME: %s — %d/%d (%s)", allTimeBest.name, allTimeBest.score, allTimeBest.kills, formatElapsed(allTimeBest.elapsedSeconds))) end
	scoreboardText.Text = table.concat(lines, "\n")
end

scoreEvent.OnClientEvent:Connect(function(score, kills) currentScore, currentKills = tonumber(score) or 0, tonumber(kills) or currentKills end)
bestSpawnAnnouncementEvent.OnClientEvent:Connect(function(points, killCount)
	bestSpawnAnnouncementToken += 1
	local token = bestSpawnAnnouncementToken
	bestSpawnText.Text = string.format("best spawn! %d/%d", tonumber(points) or 0, tonumber(killCount) or 0)
	bestSpawnText.TextTransparency = 1
	bestSpawnText.Visible = true
	TweenService:Create(bestSpawnText, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()

	task.delay(5, function()
		if token ~= bestSpawnAnnouncementToken or not bestSpawnText.Parent then return end
		TweenService:Create(bestSpawnText, TweenInfo.new(0.3), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		task.delay(0.35, function()
			if token == bestSpawnAnnouncementToken and bestSpawnText.Parent then
				bestSpawnText.Visible = false
				bestSpawnText.TextStrokeTransparency = 0
			end
		end)
	end)
end)
monsterCountEvent.OnClientEvent:Connect(function(count)
	monstersLeft = math.max(0, tonumber(count) or 0)
	table.insert(monsterHistory, { time = workspace:GetServerTimeNow(), count = monstersLeft })
end)
recordsEvent.OnClientEvent:Connect(function(data)
	currentScore = tonumber(data and data.currentScore) or currentScore
	currentKills = tonumber(data and data.currentKills) or currentKills
	-- Newer servers send personalBestScore. The fallback keeps older sessions
	-- working, although their historical personalBestSpawn field was a spawn
	-- number rather than a score.
	bestSpawn = tonumber(data and (data.personalBestScore or data.bestSpawn or data.personalBestSpawn)) or bestSpawn
	local normalized = normalizeRows(data)
	if normalized then recordRows = normalized end
	local best = data and (data.bestEver or data.allTimeBest)
	if type(best) == "table" then allTimeBest = { name = tostring(best.playerName or best.name or "-"), score = tonumber(best.score) or 0, kills = tonumber(best.kills) or 0, elapsedSeconds = tonumber(best.elapsedSeconds) or 0 }
	elseif data and data.bestEverScore then allTimeBest = { name = tostring(data.bestEverPlayerName or "-"), score = tonumber(data.bestEverScore) or 0, kills = tonumber(data.bestEverKills) or 0, elapsedSeconds = tonumber(data.bestEverElapsedSeconds) or 0 } end
	renderScoreboard()
end)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then bindCharacter(player.Character) end

local elapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.1 then return end
	elapsed = 0
	local endsAt = tonumber(workspace:GetAttribute("RoundEndsAt"))
	labels.Time.Text = formatTime(endsAt and endsAt - workspace:GetServerTimeNow() or 0)
	labels.Monsters.Text = tostring(monstersLeft)
	local now = workspace:GetServerTimeNow()
	while #monsterHistory > 0 and monsterHistory[1].time < now - 10 do table.remove(monsterHistory, 1) end
	local baseline = monsterHistory[1] and monsterHistory[1].count or monstersLeft
	labels.Spawn.Text = tostring(bestSpawn)
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	-- Shared desktop/mobile content. The best-spawn value remains available in
	-- the expanded scoreboard, not as a competing fifth card concept.
	labels.Rank.Text = ordinal(getRank())
	captions.Rank.RichText = false
	captions.Rank.Text = tostring(currentScore) .. " SCORE"
	captions.Monsters.Text = "MONSTERS LEFT"
	labels.Spawn.Text = string.format("%d (%d)", currentKills, currentScore)
	captions.Spawn.Text = "KILLS (SCORE)"
	layout()
	renderScoreboard()
	renderEvents(now)
end)

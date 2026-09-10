-- MonsterSystem: the SINGLE source of truth for monster HP, scoring, and respawn.
-- All monster logic is centralized here (via MonsterManager) instead of being
-- scattered across per-monster scripts in the world.

local Players = game:GetService("Players")
local ws = game:GetService("Workspace")
local rs = game:GetService("ReplicatedStorage")
local MonsterManager = require(rs:WaitForChild("MonsterManager"))
local MonsterBombConfig = require(rs:WaitForChild("MonsterBombConfig"))
local RadarEventBus = require(rs:WaitForChild("RadarEventBus"))
local SoundService = game:GetService("SoundService")

local scores = {} -- Player -> current score
local kills = {} -- Player -> monsters for which the player earned score
local spawnScores = {} -- Player -> score earned during the current life
local spawnKills = {} -- Player -> kills earned during the current life
local connected = {} -- humanoid -> true (in-memory, so clones re-register)
local spawns = {} -- model -> {template, cframe, livesRemaining} used for respawning in place
local managedMonsters = {} -- model -> true; only these models are allowed into the round count
local roundTemplates = {}

local spawnCounts = {}
local sessionBest = {} -- player -> {score, spawn}
-- Completed lives only. This deliberately stays separate from sessionBest,
-- which updates as a player earns points during their currently active life.
local completedSpawnBest = {} -- player -> {score, kills, spawn}
local serverBest = { score = 0, playerName = "-", spawn = 0 }
local pendingRespawns = 0
local roundComplete = false
local roundFailed = false
local escapeActive = false
local roundGeneration = 0
local announcedMonsterMilestones = {}
local lastBroadcastMonsterCount = nil
local multikillStates = {}

local RESPAWN_TIME = 15 -- seconds before a killed monster respawns
local CORPSE_DISPLAY_TIME = 3 -- separate from respawn time; body remains briefly visible
local RESPAWN_LIVES = 3 -- initial life plus three server-owned replacements
local ROUND_DURATION_SECONDS = 44 * 60 + 45
local ESCAPE_DURATION_SECONDS = 5 * 60
local DEFAULT_MONSTER_MAX_COUNT = 180
local ROUND_STARTED_AT_ATTRIBUTE = "RoundStartedAt"
local ROUND_ENDS_AT_ATTRIBUTE = "RoundEndsAt"
local MONSTER_MAX_COUNT_ATTRIBUTE = "MonsterMaxCount"
local MANAGED_MONSTER_ATTRIBUTE = "RoundManagedMonster"
local LIVES_REMAINING_ATTRIBUTE = "RoundLivesRemaining"
local RESPAWN_LEVEL_ATTRIBUTE = "MonsterRespawnLevel"
local UNDERGROUND_PHASE_ATTRIBUTE = "UndergroundPhaseActive"
local SECRET_SHAFT_OPEN_ATTRIBUTE = "SecretShaftDoorOpen"
local NO_RESPAWN_WINDOW_SECONDS = 10 * 60 -- no respawns in the final 12 minutes

local function isInNoRespawnWindow()
	local endsAt = tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE))
	if not endsAt then return false end
	return ws:GetServerTimeNow() >= endsAt - NO_RESPAWN_WINDOW_SECONDS
end

local function getRespawnTime(model)
	if model.Name == MonsterBombConfig.MODEL_NAME then
		return MonsterBombConfig.RESPAWN_TIME
	end
	return RESPAWN_TIME
end

-- Spawner-owned monsters remain normal killable/countable monsters during the
-- current round, but they never enter the finite round-template or individual
-- respawn pools. This keeps a local generator from multiplying the next round
-- or changing the ordinary population's lifecycle.
local function isSpawnerOwnedMonster(model)
	return model:GetAttribute("NoAutoRespawn") == true
end

-- A kill should matter much more in a small server. Roll once, immediately
-- after an otherwise respawn-eligible death; later joins/leaves cannot change
-- that outcome during the respawn delay.
local function getRespawnChance()
	local playerCount = #Players:GetPlayers()
	if playerCount <= 1 then return 0.25 end
	if playerCount <= 3 then return 0.50 end
	if playerCount >= 10 then return 0.90 end
	return 0.75
end

local function getMonsterMaxCount()
	local configured = tonumber(ws:GetAttribute(MONSTER_MAX_COUNT_ATTRIBUTE))
	if not configured or configured < 1 then
		configured = DEFAULT_MONSTER_MAX_COUNT
		ws:SetAttribute(MONSTER_MAX_COUNT_ATTRIBUTE, configured)
	end

	return math.floor(configured)
end

local function resetRoundClock()
	local now = ws:GetServerTimeNow()
	ws:SetAttribute(ROUND_STARTED_AT_ATTRIBUTE, now)
	ws:SetAttribute(ROUND_ENDS_AT_ATTRIBUTE, now + ROUND_DURATION_SECONDS)
	ws:SetAttribute("RoundActive", true)
	ws:SetAttribute("RoundPhase", "Hunt")
	ws:SetAttribute("NightmareEscapeActive", false)
	ws:SetAttribute("NightmareEscapeEndsAt", nil)
	ws:SetAttribute("NightmareClearElapsedSeconds", nil)
	ws:SetAttribute(UNDERGROUND_PHASE_ATTRIBUTE, false)
	ws:SetAttribute(SECRET_SHAFT_OPEN_ATTRIBUTE, false)
end

getMonsterMaxCount()
if ws:GetAttribute(ROUND_STARTED_AT_ATTRIBUTE) == nil
	or tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE)) == nil
	or tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE)) <= ws:GetServerTimeNow() then
	resetRoundClock()
end
if ws:GetAttribute(UNDERGROUND_PHASE_ATTRIBUTE) == nil then
	ws:SetAttribute(UNDERGROUND_PHASE_ATTRIBUTE, false)
end
if ws:GetAttribute(SECRET_SHAFT_OPEN_ATTRIBUTE) == nil then
	ws:SetAttribute(SECRET_SHAFT_OPEN_ATTRIBUTE, false)
end

local function getOrCreateRemoteEvent(name)
	local event = rs:FindFirstChild(name)
	if event and event:IsA("RemoteEvent") then
		return event
	end

	event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = rs
	return event
end

local scoreEvent = getOrCreateRemoteEvent("ScoreUpdate")
local monsterCountEvent = getOrCreateRemoteEvent("MonsterCountUpdate")
local recordsEvent = getOrCreateRemoteEvent("RecordsUpdate")
local roundCompleteEvent = getOrCreateRemoteEvent("RoundComplete")
local nightmareEscapeStartedEvent = getOrCreateRemoteEvent("NightmareEscapeStarted")
local roundRestartedEvent = getOrCreateRemoteEvent("RoundRestarted")
local roundFailedEvent = getOrCreateRemoteEvent("RoundFailed")
local restartRoundEvent = getOrCreateRemoteEvent("RestartRound")
local monsterMilestoneEvent = getOrCreateRemoteEvent("MonsterMilestone")
local playerKillMilestoneEvent = getOrCreateRemoteEvent("PlayerKillMilestone")
local bestSpawnAnnouncementEvent = getOrCreateRemoteEvent("BestSpawnAnnouncement")
local secretShaftAnnouncementEvent = getOrCreateRemoteEvent("SecretShaftAnnouncement")
local secretShaftLockedEvent = getOrCreateRemoteEvent("SecretShaftDoorLocked")
local lavaPoolDoorOpenedEvent = getOrCreateRemoteEvent("LavaPoolDoorOpened")
local lavaPoolDoorLockedEvent = getOrCreateRemoteEvent("LavaPoolDoorLocked")

local DataStoreService = game:GetService("DataStoreService")
local bestEverStore = DataStoreService:GetDataStore("ForestOfHorrorsBestEver")

local bestEver = {
	score = 0,
	kills = 0,
	elapsedSeconds = 0,
	playerName = "-",
	spawn = 0,
}
local getScoreboard

task.spawn(function()
	local ok, saved = pcall(function()
		return bestEverStore:GetAsync("BestEver")
	end)

	if ok and type(saved) == "table" then
		bestEver = saved
	end
end)


local function fireRecords(player)
	local best = sessionBest[player] or {
		score = 0,
		kills = 0,
		spawn = spawnCounts[player] or 0,
	}

	recordsEvent:FireClient(player, {
		currentScore = scores[player] or 0,
		currentKills = kills[player] or 0,
		currentSpawn = spawnCounts[player] or 0,

		personalBestScore = best.score or 0,
		-- Kept under the legacy field name for clients already reading it. This is
		-- the score achieved in the best spawn, never the numeric spawn count.
		personalBestSpawn = best.score or 0,

		serverBestScore = serverBest.score or 0,
		serverBestPlayerName = serverBest.playerName or "-",
		serverBestSpawn = serverBest.spawn or 0,

		bestEverScore = bestEver.score or 0,
		bestEverKills = bestEver.kills or 0,
		bestEverElapsedSeconds = bestEver.elapsedSeconds or 0,
		bestEverPlayerName = bestEver.playerName or "-",
		bestEverSpawn = bestEver.spawn or 0,
		bestEver = bestEver,
		scoreboard = getScoreboard and getScoreboard() or {},
	})
end

local function broadcastRecords()
	for _, player in Players:GetPlayers() do
		fireRecords(player)
	end
end

local function updateBestEver(player, score, killCount, spawn)
	if player:GetAttribute("Difficulty") == "Easy" then return end
	if score <= (bestEver.score or 0) then return end

	bestEver = {
		score = score,
		kills = killCount,
		elapsedSeconds = math.max(0, math.floor(ws:GetServerTimeNow() - (tonumber(ws:GetAttribute(ROUND_STARTED_AT_ATTRIBUTE)) or ws:GetServerTimeNow()))),
		playerName = player.Name,
		spawn = spawn,
	}

	task.spawn(function()
		pcall(function()
			bestEverStore:SetAsync("BestEver", bestEver)
		end)
	end)
end

local function setupLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local scoreValue = leaderstats:FindFirstChild("Score")
	if not scoreValue then
		scoreValue = Instance.new("IntValue")
		scoreValue.Name = "Score"
		scoreValue.Parent = leaderstats
	end

	scoreValue.Value = scores[player] or 0
	local killsValue = leaderstats:FindFirstChild("Kills")
	if not killsValue then
		killsValue = Instance.new("IntValue")
		killsValue.Name = "Kills"
		killsValue.Parent = leaderstats
	end
	killsValue.Value = kills[player] or 0
	return scoreValue, killsValue
end

local function setLeaderboardStats(player, score, killCount)
	local scoreValue, killsValue = setupLeaderstats(player)
	scoreValue.Value = score
	killsValue.Value = killCount
end

getScoreboard = function()
	local list = {}

	for _, player in Players:GetPlayers() do
		local best = sessionBest[player] or {}
		table.insert(list, {
			name = player.Name,
			difficulty = player:GetAttribute("Difficulty") == "Easy" and "Easy" or "Hard",
			score = scores[player] or 0,
			kills = kills[player] or 0,
			bestSpawn = best.score or 0,
			deaths = math.max(0, (spawnCounts[player] or 0) - 1),
		})
	end

	table.sort(list, function(a, b)
		if a.score == b.score then
			return a.name < b.name
		end

		return a.score > b.score
	end)

	return list
end


-- Disable any per-monster self-respawn scripts so THIS system is the single
-- source of truth for respawning (prevents double respawns / duplicates).
local function disableSelfRespawn(model)
	for _, s in model:GetDescendants() do
		if s:IsA("BaseScript") and (s.Name == "Regen" or s.Name == "Respawn") then
			s.Disabled = true
		end
	end
end

local function getMonsterRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart", true)
	if root and root:IsA("BasePart") then
		return root
	end

	-- Legacy fortress bosses and other marketplace rigs may use Torso/Head or
	-- only a PrimaryPart. Keep lifecycle tracking alive without trusting debris.
	local fallback = model.PrimaryPart
		or model:FindFirstChild("Torso", true)
		or model:FindFirstChild("UpperTorso", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	if fallback and fallback:IsA("BasePart") then
		return fallback
	end

	return nil
end

local function isOutsideMainGround(root)
	if not root or not root:IsA("BasePart") then return false end
	local ground = ws:FindFirstChild("MainGround")
	if not (ground and ground:IsA("BasePart")) then return false end
	local margin = 12
	local position = root.Position
	local halfSize = ground.Size * 0.5
	return position.Y < ground.Position.Y - 20
		or position.X < ground.Position.X - halfSize.X - margin
		or position.X > ground.Position.X + halfSize.X + margin
		or position.Z < ground.Position.Z - halfSize.Z - margin
		or position.Z > ground.Position.Z + halfSize.Z + margin
end

-- Count only living NPCs explicitly registered by this system. Marketplace
-- debris and malformed lookalike models must never hold a round hostage.
local function countLivingMonsters()
	local count = 0

	for model in pairs(managedMonsters) do
		if model.Parent and model:IsDescendantOf(ws) and MonsterManager.isRoundTracked(model) then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			if humanoid and humanoid.Health > 0 and getMonsterRoot(model) then
				count += 1
			end
		end
	end

	return count
end

-- Underground/key monsters remain normal round participants, but are not part
-- of the surface combat total shown in the score HUD. This prevents the HUD
-- from directing players toward monsters that are deliberately hidden from
-- both radars.
local function countLivingSurfaceMonsters()
	local count = 0

	for model in pairs(managedMonsters) do
		if model.Parent
			and model:IsDescendantOf(ws)
			and model:GetAttribute("UndergroundMonster") ~= true
			and MonsterManager.isRoundTracked(model)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			if humanoid and humanoid.Health > 0 and getMonsterRoot(model) then
				count += 1
			end
		end
	end

	return count
end

local function countLivingUndergroundMonsters()
	local count = 0

	for model in pairs(managedMonsters) do
		if model.Parent
			and model:IsDescendantOf(ws)
			and model:GetAttribute("UndergroundMonster") == true
			and MonsterManager.isRoundTracked(model)
		then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			if humanoid and humanoid.Health > 0 and getMonsterRoot(model) then
				count += 1
			end
		end
	end

	return count
end

local beginUndergroundPhase

local function checkRoundComplete(count)
	if roundComplete or roundFailed then return end
	if pendingRespawns > 0 then return end
	if count ~= 0 then return end

	-- Clearing the hostile population is the end of combat, not the end of the
	-- nightmare. Freeze the successful hunt timer and give players one final,
	-- short escape phase to reach the bedroom portal.
	roundComplete = true
	escapeActive = true
	ws:SetAttribute("RoundActive", false)
	ws:SetAttribute("RoundPhase", "Escape")
	ws:SetAttribute("NightmareEscapeActive", true)
	local now = ws:GetServerTimeNow()
	local clearedInSeconds = math.max(0, math.floor(now - (tonumber(ws:GetAttribute(ROUND_STARTED_AT_ATTRIBUTE)) or now)))
	local escapeEndsAt = now + ESCAPE_DURATION_SECONDS
	ws:SetAttribute("NightmareClearElapsedSeconds", clearedInSeconds)
	ws:SetAttribute("NightmareEscapeEndsAt", escapeEndsAt)
	-- ScoreGui reads RoundEndsAt, so this replaces its original hunt timer with
	-- the visible sixty-second escape countdown instead of leaving it at zero.
	ws:SetAttribute(ROUND_ENDS_AT_ATTRIBUTE, escapeEndsAt)
	nightmareEscapeStartedEvent:FireAllClients({
		clearedInSeconds = clearedInSeconds,
		escapeEndsAt = escapeEndsAt,
	})
end

local function announceMonsterMilestone(count)
	local maximum = getMonsterMaxCount()
	-- The first announcement is deliberately delayed until the active count is
	-- below 90% of the configured round capacity, avoiding an opening spam.
	local previous = lastBroadcastMonsterCount
	lastBroadcastMonsterCount = count
	if not previous or count >= previous or count >= maximum * 0.9 then return end

	for milestone = math.floor(maximum / 10) * 10, 10, -10 do
		if not announcedMonsterMilestones[milestone]
			and previous > milestone
			and count <= milestone then
			announcedMonsterMilestones[milestone] = true
			monsterMilestoneEvent:FireAllClients(milestone)
			break
		end
	end
end

local function broadcastMonsterCount()
	local roundCount = countLivingMonsters()
	local surfaceCount = countLivingSurfaceMonsters()
	local undergroundCount = countLivingUndergroundMonsters()

	if not roundComplete
		and not roundFailed
		and pendingRespawns == 0
		and ws:GetAttribute(UNDERGROUND_PHASE_ATTRIBUTE) ~= true
		and surfaceCount == 0
		and undergroundCount > 0
	then
		beginUndergroundPhase()
	end

	local displayedCount = ws:GetAttribute(UNDERGROUND_PHASE_ATTRIBUTE) == true
		and undergroundCount
		or surfaceCount
	announceMonsterMilestone(displayedCount)
	monsterCountEvent:FireAllClients(displayedCount)
	checkRoundComplete(roundCount)
end

local DEFAULT_SCORE_POPUP_COLOR = Color3.fromRGB(255, 238, 150)
local MULTIKILL_WINDOW_SECONDS = 5
local MAJOR_KILL_MIN_HP = 520
local MONSTER_KILL_BONUS = 1
local secretShaftOpened = ws:GetAttribute(SECRET_SHAFT_OPEN_ATTRIBUTE) == true
local lavaPoolDoorOpened = ws:GetAttribute(UNDERGROUND_PHASE_ATTRIBUTE) == true
local secretShaftDoors = {}
local lavaPoolDoors = {}
local PLAYER_KILL_MILESTONES = {
	[50] = true,
	[100] = true,
	[200] = true,
	[300] = true,
	[500] = true,
	[1000] = true,
}

local function showScorePopup(model, awards, color)
	if #awards == 0 then return end

	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Head", true)
	if not root or not root:IsA("BasePart") then return end

	local lines = {}
	local popupHeight = 0

	for _, award in ipairs(awards) do
		local label = award.label
		if not label then
			local player = Players:GetPlayerByUserId(award.userId)
			label = player and player.Name or "Player"
		end
		local isMonsterKill = label == "monster kill"
		local lineHeight = isMonsterKill and 46 or 30
		table.insert(lines, {
			text = "+" .. tostring(award.points) .. " " .. label,
			height = lineHeight,
			isMonsterKill = isMonsterKill,
		})
		popupHeight += lineHeight
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ScorePopupGui"
	gui.Size = UDim2.new(0, 220, 0, math.max(44, popupHeight))
	gui.StudsOffset = Vector3.new(0, 5.4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	gui.Parent = model

	local yOffset = 0
	for index, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = line.isMonsterKill and "MonsterKillBonus" or "Label"
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, yOffset)
		label.Size = UDim2.new(1, 0, 0, line.height)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0
		label.Text = line.text
		label.LayoutOrder = index
		label.Parent = gui
		yOffset += line.height
	end

	task.delay(2, function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end)
end

local function rememberDoor(doors, door, prompt)
	if doors[door] then return doors[door] end

	local record = {
		prompt = prompt,
		promptEnabled = prompt and prompt.Enabled,
		parts = {},
	}
	local function rememberPart(part)
		table.insert(record.parts, {
			part = part,
			transparency = part.Transparency,
			canCollide = part.CanCollide,
			canTouch = part.CanTouch,
			canQuery = part.CanQuery,
		})
	end

	rememberPart(door)
	for _, descendant in ipairs(door:GetDescendants()) do
		if descendant:IsA("BasePart") then
			rememberPart(descendant)
		end
	end
	doors[door] = record
	return record
end

local function setDoorsOpen(doors, isOpen)
	for door, record in pairs(doors) do
		if door.Parent then
			for _, partState in ipairs(record.parts) do
				local part = partState.part
				if part.Parent then
					if isOpen then
						part.Transparency = 1
						part.CanCollide = false
						part.CanTouch = false
						part.CanQuery = false
					else
						part.Transparency = partState.transparency
						part.CanCollide = partState.canCollide
						part.CanTouch = partState.canTouch
						part.CanQuery = partState.canQuery
					end
				end
			end
			if record.prompt and record.prompt.Parent then
				if isOpen then
					record.prompt.Enabled = false
				else
					record.prompt.Enabled = record.promptEnabled
				end
			end
		end
	end
end

local function resetGateDoors()
	secretShaftOpened = false
	lavaPoolDoorOpened = false
	ws:SetAttribute(SECRET_SHAFT_OPEN_ATTRIBUTE, false)
	ws:SetAttribute(UNDERGROUND_PHASE_ATTRIBUTE, false)
	setDoorsOpen(secretShaftDoors, false)
	setDoorsOpen(lavaPoolDoors, false)
end

-- The marked white creepy opens this gate no matter which authoritative damage
-- source kills it. Unlike the old version, the physical door is hidden rather
-- than destroyed so a restarted game can restore its original locked state.
local function openSecretShaftIfGuard(model)
	if secretShaftOpened or model:GetAttribute("SecretShaftDoorGuard") ~= true then return end
	secretShaftOpened = true
	ws:SetAttribute(SECRET_SHAFT_OPEN_ATTRIBUTE, true)
	setDoorsOpen(secretShaftDoors, true)

	local source = SoundService:FindFirstChild("SecretShaftGuard")
	if source and source:IsA("Sound") then
		local sound = source:Clone()
		sound.Looped = false
		sound.Parent = SoundService
		sound:Play()
		game:GetService("Debris"):AddItem(sound, math.max(5, sound.TimeLength + 1))
	else
		warn("[MonsterSystem] SecretShaftGuard sound not found in SoundService")
	end

	secretShaftAnnouncementEvent:FireAllClients()
end

local function bindGateDoors()
	for _, item in ipairs(ws:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == "SecretShaftDoor" and item:GetAttribute("SecretShaftDoor") == true then
			local prompt = item:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
			prompt.ActionText = "Open"
			prompt.ObjectText = "Secret Shaft"
			prompt.HoldDuration = 0.2
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = item
			rememberDoor(secretShaftDoors, item, prompt)
			prompt.Triggered:Connect(function(player)
				if not secretShaftOpened then
					secretShaftLockedEvent:FireClient(player)
				end
			end)
		elseif item:IsA("BasePart") and item.Name == "LavaPoolDoor" and item:GetAttribute("LavaPoolDoor") == true then
			local prompt = item:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
			prompt.ActionText = "Open"
			prompt.ObjectText = "Lava Pool"
			prompt.HoldDuration = 0.2
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = item
			rememberDoor(lavaPoolDoors, item, prompt)
			prompt.Triggered:Connect(function(player)
				if not lavaPoolDoorOpened then
					lavaPoolDoorLockedEvent:FireClient(player)
				end
			end)
		end
	end
end

bindGateDoors()
setDoorsOpen(secretShaftDoors, secretShaftOpened)
setDoorsOpen(lavaPoolDoors, lavaPoolDoorOpened)

beginUndergroundPhase = function()
	if ws:GetAttribute(UNDERGROUND_PHASE_ATTRIBUTE) == true then return end
	lavaPoolDoorOpened = true
	ws:SetAttribute(UNDERGROUND_PHASE_ATTRIBUTE, true)
	setDoorsOpen(lavaPoolDoors, true)
	lavaPoolDoorOpenedEvent:FireAllClients()
end

local function updateScoreRecords(player)
	local currentScore = scores[player] or 0
	local currentSpawnScore = spawnScores[player] or 0
	local currentSpawn = spawnCounts[player] or 1

	if not sessionBest[player] or currentSpawnScore > sessionBest[player].score then
		sessionBest[player] = {
			score = currentSpawnScore,
			spawn = currentSpawn,
		}
	end

	if player:GetAttribute("Difficulty") ~= "Easy" and currentScore > serverBest.score then
		serverBest = {
			score = currentScore,
			playerName = player.Name,
			spawn = currentSpawn,
		}
	end

	updateBestEver(player, currentScore, kills[player] or 0, currentSpawn)
end

local function clearMultikill(player, state, token)
	if multikillStates[player] ~= state or state.token ~= token then return end
	multikillStates[player] = nil
end

local function playMonsterKillAnnouncement(player)
	local source = SoundService:FindFirstChild("MonsterKill")
	if not (source and source:IsA("Sound")) or not player or not player.Parent then return false end

	local sound = source:Clone()
	sound.Looped = false
	sound.Parent = SoundService
	sound:Play()
	game:GetService("Debris"):AddItem(sound, math.max(3, sound.TimeLength + 1))

	-- The sound and bonus are one reward: an actual announcement is always +5.
	scores[player] = (scores[player] or 0) + MONSTER_KILL_BONUS
	spawnScores[player] = (spawnScores[player] or 0) + MONSTER_KILL_BONUS
	setLeaderboardStats(player, scores[player], kills[player] or 0)
	scoreEvent:FireClient(player, scores[player], kills[player] or 0)
	updateScoreRecords(player)
	broadcastRecords()
	return true
end

local function registerMultikillKill(player, isMajorKill)
	local state = multikillStates[player]
	if not state then
		state = { count = 0, token = 0 }
		multikillStates[player] = state
	end
	state.count += 1
	state.token += 1

	-- A three-kill chain announces once and earns its fixed +5. Major kills
	-- announce below instead, even when they close a chain.
	local announced = false
	if state.count == 3 and not isMajorKill then
		announced = playMonsterKillAnnouncement(player)
	end

	local token = state.token
	task.delay(MULTIKILL_WINDOW_SECONDS, function()
		clearMultikill(player, state, token)
	end)
	return announced
end

local function awardScore(player, points, isMajorKill)
	scores[player] = (scores[player] or 0) + points
	kills[player] = (kills[player] or 0) + 1
	spawnScores[player] = (spawnScores[player] or 0) + points
	spawnKills[player] = (spawnKills[player] or 0) + 1
	setLeaderboardStats(player, scores[player], kills[player])
	scoreEvent:FireClient(player, scores[player], kills[player])
	updateScoreRecords(player)
	if PLAYER_KILL_MILESTONES[kills[player]] then
		playerKillMilestoneEvent:FireClient(player, kills[player])
	end
	return registerMultikillKill(player, isMajorKill)
end

-- Award points when a monster dies, then schedule one of its two permitted
-- server-owned resurrections. Permanent weapon kills consume every remaining
-- life, including for bomb monsters.
local function onMonsterKilled(hum, model)
	openSecretShaftIfGuard(model)
	local config = MonsterManager.getConfig(model)
	local shortName = MonsterManager.getShortName(model)
	local pluralShortName = MonsterManager.getPluralShortName(model)
	local eventReported = false
	local fellOffMap = isOutsideMainGround(getMonsterRoot(model))

	if config then
		local awards = MonsterManager.consumeScoreAwards(hum, config.points)
		local popupColor = MonsterManager.getLastScoreColor(hum, DEFAULT_SCORE_POPUP_COLOR)
		local isMajorKill = config.hp >= MAJOR_KILL_MIN_HP
		local awardedAny = false
		local monsterKillAnnounced = false
		local lastAttackerId = hum:GetAttribute("LastAttackerId")
		local announcementPlayer
		local monsterAttacker = hum:GetAttribute("LastMonsterAttacker")
		local monsterAttackCause = hum:GetAttribute("LastMonsterAttackCause")

		for _, award in ipairs(awards) do
			local attacker = Players:GetPlayerByUserId(award.userId)

			if attacker then
				for weaponName, weaponPoints in pairs(award.weaponPoints or {}) do
					if weaponName == "MonsterGun" or weaponName == "MonsterGun2" or weaponName == "MonsterGun3" then
						local progressAttribute = weaponName == "MonsterGun" and "MonsterGun1Points"
							or weaponName == "MonsterGun2" and "MonsterGun2Points"
							or "MonsterGun3Points"
						attacker:SetAttribute(progressAttribute, (tonumber(attacker:GetAttribute(progressAttribute)) or 0) + weaponPoints)
					end
				end
				if awardScore(attacker, award.points, isMajorKill) then
					monsterKillAnnounced = true
				end
				awardedAny = true
				if award.userId == lastAttackerId then
					announcementPlayer = attacker
				elseif not announcementPlayer then
					announcementPlayer = attacker
				end
				RadarEventBus.publish({ kind = "kill", actor = attacker.DisplayName, actorKind = "player", target = shortName, targetPlural = pluralShortName })
				eventReported = true
			end
		end

		if awardedAny then
			if isMajorKill then
				monsterKillAnnounced = playMonsterKillAnnouncement(announcementPlayer) or monsterKillAnnounced
			end
			if monsterKillAnnounced then
				table.insert(awards, { points = MONSTER_KILL_BONUS, label = "monster kill" })
			end
			showScorePopup(model, awards, popupColor)
			broadcastRecords()
		end
		if not eventReported then
			if monsterAttackCause == "bomb" then
				RadarEventBus.publish({ kind = "death", target = shortName, targetPlural = pluralShortName, cause = "bomb" })
			elseif monsterAttacker and monsterAttacker ~= "" then
				RadarEventBus.publish({ kind = "kill", actor = tostring(monsterAttacker), actorKind = "monster", target = shortName, targetPlural = pluralShortName })
			elseif fellOffMap then
				RadarEventBus.publish({ kind = "death", target = shortName, targetPlural = pluralShortName, cause = "fell" })
			else
				RadarEventBus.publish({ kind = "death", target = shortName, targetPlural = pluralShortName, cause = "unattributed" })
			end
		end
	end

	local data = spawns[model]
	-- Spawner-owned families own their own return cycle.  This must win even if
	-- this script registered the model a fraction of a second before the
	-- spawner set NoAutoRespawn, otherwise both systems can create a clone.
	if isSpawnerOwnedMonster(model) then
		spawns[model] = nil
		task.delay(CORPSE_DISPLAY_TIME, function()
			if model.Parent then model:Destroy() end
			broadcastMonsterCount()
			broadcastRecords()
		end)
		return
	end
	if data then
		spawns[model] = nil
		local permanentWeaponKill =
			hum:GetAttribute("PermanentMonsterKill") == true
			or hum:GetAttribute("KilledByMonsterBlaster") == true
			or hum:GetAttribute("KilledByMonsterGun") == true

		-- BombMonster is an ignitable reusable encounter, not a conventional
		-- permanently-destroyed weapon target. This also tolerates an older live
		-- weapon script which may still set one of the generic kill attributes.
		-- Its finite lives are consumed only by normal bomb deaths below.
		if model.Name == MonsterBombConfig.MODEL_NAME then
			permanentWeaponKill = false
		end

		-- Bombs are reusable counter-monsters: their reliable respawn preserves a
		-- way to thin nearby ordinary monsters. Only ordinary round monsters use
		-- the player-count respawn chance below.
		local livesAfterDeath = permanentWeaponKill and 0 or math.max(0, (data.livesRemaining or 1) - 1)
		local willRespawn = livesAfterDeath > 0 and (
			model.Name == MonsterBombConfig.MODEL_NAME
				or math.random() < getRespawnChance()
		)
		if livesAfterDeath == 0 or not willRespawn or roundFailed or roundComplete or isInNoRespawnWindow() or ws:GetAttribute("GameStopped") == true then
			task.delay(CORPSE_DISPLAY_TIME, function()
				if model.Parent then
					model:Destroy()
				end

				broadcastMonsterCount()
				broadcastRecords()
			end)

			return
		end

		pendingRespawns += 1
		local generation = roundGeneration
		task.delay(CORPSE_DISPLAY_TIME, function()
			if model.Parent then
				model:Destroy()
			end
		end)

		task.delay(getRespawnTime(model), function()
			if model.Parent then
				model:Destroy()
			end

			if generation ~= roundGeneration then
				return
			end

			if roundFailed or roundComplete then
				pendingRespawns -= 1
				broadcastMonsterCount()
				broadcastRecords()
				return
			end

			-- This is a replacement for a managed monster that just died, not a new
			-- spawn. The cap must not silently consume one of its remaining lives.
			local clone = data.template:Clone()
			if model.Name ~= MonsterBombConfig.MODEL_NAME then
				local level = math.max(0, math.floor(tonumber(model:GetAttribute(RESPAWN_LEVEL_ATTRIBUTE)) or tonumber(model:GetAttribute("CreepyRespawnLevel")) or 0))
				clone:SetAttribute(RESPAWN_LEVEL_ATTRIBUTE, level + 1)
				if string.sub(model.Name, 1, #"creepyMonster") == "creepyMonster" then
					-- Preserve the legacy per-creepy marker for existing AI/UI code.
					clone:SetAttribute("CreepyRespawnLevel", level + 1)
				end
			end
			clone:SetAttribute("RoundRespawned", true)
			clone:SetAttribute(MANAGED_MONSTER_ATTRIBUTE, true)
			clone:SetAttribute(LIVES_REMAINING_ATTRIBUTE, livesAfterDeath)
			clone:PivotTo(data.cframe)
			clone.Parent = ws
			RadarEventBus.publish({ kind = "respawn", target = shortName, targetPlural = pluralShortName })

			pendingRespawns -= 1
			broadcastMonsterCount()
			broadcastRecords()
		end)
	end
end

local function retireMonster(model, reason)
	if not model or not model.Parent or not managedMonsters[model] then return end
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if not humanoid or humanoid.Health <= 0 then return end
	model:SetAttribute("MonsterRetireRequested", nil)
	model:SetAttribute("MonsterRetirementReason", reason or "InvalidMonster")
	humanoid:SetAttribute("PermanentMonsterKill", true)
	RadarEventBus.publish({ kind = "retire", target = MonsterManager.getShortName(model), targetPlural = MonsterManager.getPluralShortName(model) })
	humanoid.Health = 0
end

-- Set up a monster: apply HP, disable self-respawn, store a template,
-- and connect its Died event (only for real monsters).
local function setupMonster(model)
	local config = MonsterManager.getConfig(model)
	if not config or not MonsterManager.isRoundTracked(model) then return end
	local hum = MonsterManager.getMonsterHumanoid(model)
	if not hum then return end

	MonsterManager.applyHP(model)
	if model.Name ~= MonsterBombConfig.MODEL_NAME then
		-- Respawn level 1 is generation 2: base HP + one more base HP.
		-- Keep bombs on their own fixed finite-lives health lifecycle.
		local respawnLevel = math.max(0, math.floor(tonumber(model:GetAttribute(RESPAWN_LEVEL_ATTRIBUTE)) or 0))
		if respawnLevel == 0 and string.sub(model.Name, 1, #"creepyMonster") == "creepyMonster" then
			respawnLevel = math.max(0, math.floor(tonumber(model:GetAttribute("CreepyRespawnLevel")) or 0))
		end
		if respawnLevel > 0 then
			hum.MaxHealth = hum.MaxHealth * (respawnLevel + 1)
			hum.Health = hum.MaxHealth
		end
	end
	if string.sub(model.Name, 1, #"creepyMonster") == "creepyMonster" then
		local baseSpeed = tonumber(model:GetAttribute("CreepyBaseWalkSpeed")) or hum.WalkSpeed
		model:SetAttribute("CreepyBaseWalkSpeed", baseSpeed)
		local respawnLevel = math.max(0, math.floor(tonumber(model:GetAttribute(RESPAWN_LEVEL_ATTRIBUTE)) or tonumber(model:GetAttribute("CreepyRespawnLevel")) or 0))
		if respawnLevel > 0 then
			hum.WalkSpeed = baseSpeed + respawnLevel
		end
	end
	disableSelfRespawn(model)
	managedMonsters[model] = true
	model:SetAttribute(MANAGED_MONSTER_ATTRIBUTE, true)

	local livesRemaining = tonumber(model:GetAttribute(LIVES_REMAINING_ATTRIBUTE)) or RESPAWN_LIVES
	livesRemaining = math.clamp(math.floor(livesRemaining), 1, RESPAWN_LIVES)
	model:SetAttribute(LIVES_REMAINING_ATTRIBUTE, livesRemaining)

	local spawnerOwned = isSpawnerOwnedMonster(model)
	if not spawnerOwned and not model:GetAttribute("RoundRespawned") then
		table.insert(roundTemplates, {
			template = model:Clone(),
			cframe = model:GetPivot(),
		})
		model:SetAttribute("RoundRespawned", true)
	end

	if not spawnerOwned and not spawns[model] then
		spawns[model] = {
			template = model:Clone(),
			cframe = model:GetPivot(),
			livesRemaining = livesRemaining,
		}
	end

	if not connected[hum] then
		connected[hum] = true
		local lastHealth = hum.Health
		local correctingSmilerRegen = false
		hum.HealthChanged:Connect(function(health)
			if correctingSmilerRegen then
				lastHealth = health
				return
			end
			local lockedUntil = tonumber(hum:GetAttribute("BlasterRegenLockedUntil")) or 0
			if model.Name == "Smiler" and health > lastHealth and ws:GetServerTimeNow() < lockedUntil then
				correctingSmilerRegen = true
				hum.Health = lastHealth
				correctingSmilerRegen = false
				return
			end
			lastHealth = health
		end)
		hum.Died:Connect(function()
			onMonsterKilled(hum, model)
			broadcastMonsterCount()			
		end)
	end
end

local function resetScores()
	for _, player in Players:GetPlayers() do
		player:SetAttribute("EscapedNightmare", false)
		scores[player] = 0
		kills[player] = 0
		spawnScores[player] = 0
		spawnKills[player] = 0
		multikillStates[player] = nil
		setLeaderboardStats(player, 0, 0)
		scoreEvent:FireClient(player, 0, 0)
		fireRecords(player)
	end
end

local function restartRound()
	roundGeneration += 1
	pendingRespawns = 0
	roundComplete = false
	roundFailed = false
	escapeActive = false
	announcedMonsterMilestones = {}
	lastBroadcastMonsterCount = nil
	ws:SetAttribute("GameStopped", false)
	resetRoundClock()
	resetGateDoors()

	for _, instance in ws:GetDescendants() do
		if instance:IsA("Model") and MonsterManager.isRoundTracked(instance) then
			instance:Destroy()
		end
	end

	spawns = {}
	connected = {}
	managedMonsters = {}

	for _, data in ipairs(roundTemplates) do
		if countLivingMonsters() >= getMonsterMaxCount() then
			break
		end

		local clone = data.template:Clone()
		clone:SetAttribute("RoundRespawned", true)
		clone:SetAttribute(MANAGED_MONSTER_ATTRIBUTE, true)
		clone:SetAttribute(LIVES_REMAINING_ATTRIBUTE, RESPAWN_LIVES)
		clone:PivotTo(data.cframe)
		clone.Parent = ws
	end

	resetScores()
	broadcastMonsterCount()
	broadcastRecords()
	roundRestartedEvent:FireAllClients()
end

restartRoundEvent.OnServerEvent:Connect(function(player)
	if ws:GetAttribute("GameStopped") == true then
		restartRound()
		return
	end
	if not roundComplete and not roundFailed then return end
	-- During the escape phase only somebody who has actually entered the portal
	-- may restart the shared round. It prevents an uninvolved player from
	-- cancelling another survivor's escape.
	if escapeActive and player:GetAttribute("EscapedNightmare") ~= true then return end
	restartRound()
end)


-- Handle monsters already in the world
for _, desc in ws:GetDescendants() do
	if desc:IsA("Model") then
		setupMonster(desc)
	end
end

broadcastMonsterCount()
broadcastRecords()

-- Handle monsters added later (spawns, respawns)
ws.DescendantAdded:Connect(function(desc)
	if desc:IsA("Model") then
		setupMonster(desc)
	end
end)

-- The deadline is authoritative server state. Clients render RoundEndsAt but
-- cannot extend a round or trigger its failure.
task.spawn(function()
	while true do
		task.wait(1)
		if ws:GetAttribute("GameStopped") == true then
			-- Game is stopped; do not advance any round logic
		elseif escapeActive then
			local escapeEndsAt = tonumber(ws:GetAttribute("NightmareEscapeEndsAt")) or 0
			if ws:GetServerTimeNow() >= escapeEndsAt then
				escapeActive = false
				roundFailed = true
				ws:SetAttribute("NightmareEscapeActive", false)
				ws:SetAttribute("RoundPhase", "Failed")
				roundFailedEvent:FireAllClients({
					message = "You were too late. The nightmare kept you.",
					scoreboard = getScoreboard(),
					serverBest = serverBest,
					bestEver = bestEver,
				})
				broadcastMonsterCount()
				broadcastRecords()
			end
		elseif not roundComplete and not roundFailed then
			local endsAt = tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE)) or 0
			if ws:GetServerTimeNow() >= endsAt then
				roundFailed = true
				ws:SetAttribute("RoundActive", false)
				ws:SetAttribute("RoundPhase", "Failed")
				roundFailedEvent:FireAllClients({
					roundEndsAt = endsAt,
					scoreboard = getScoreboard(),
					serverBest = serverBest,
					bestEver = bestEver,
				})
				broadcastMonsterCount()
				broadcastRecords()
			end
		end
	end
end)

-- An AI may explicitly request retirement after repeated unreachable-path
-- recovery failures. This owner consumes that signal so the model cannot keep
-- a round alive forever. Rootless managed monsters receive the same safe exit.
task.spawn(function()
	while true do
		task.wait(3)
		if not roundComplete and not roundFailed and ws:GetAttribute("GameStopped") ~= true then
			for model in pairs(managedMonsters) do
				if not model.Parent or not model:IsDescendantOf(ws) then
					managedMonsters[model] = nil
				elseif model:GetAttribute("MonsterRetireRequested") == true then
					retireMonster(model, model:GetAttribute("MonsterRetirementReason"))
				else
					local humanoid = MonsterManager.getMonsterHumanoid(model)
					if humanoid and humanoid.Health > 0 and not getMonsterRoot(model) then
						retireMonster(model, "MissingRootPart")
					end
				end
			end
			broadcastMonsterCount()
		end
	end
end)

-- Initialize round totals once; a character respawn starts a new life without
-- erasing the player's score or kill total for the current game.
local function onPlayerAdded(player)
	player:SetAttribute("EscapedNightmare", false)
	scores[player] = 0
	kills[player] = 0
	spawnScores[player] = 0
	spawnKills[player] = 0
	multikillStates[player] = nil
	spawnCounts[player] = 0
	setupLeaderstats(player)

	player.CharacterAdded:Connect(function()
		-- A "best spawn" is judged only after a life has ended. This prevents an
		-- in-progress run from declaring itself best just because its score rises.
		local completedSpawn = spawnCounts[player] or 0
		if completedSpawn > 0 then
			local completedScore = spawnScores[player] or 0
			local completedKills = spawnKills[player] or 0
			local previousBest = completedSpawnBest[player]
			local isNewBest = not previousBest or completedScore > previousBest.score

			if isNewBest then
				completedSpawnBest[player] = {
					score = completedScore,
					kills = completedKills,
					spawn = completedSpawn,
				}
			end

			-- The first life establishes the personal baseline silently. From the
			-- second completed spawn onward, announce a genuine new points record
			-- when the player begins their next life.
			if completedSpawn >= 2 and isNewBest then
				bestSpawnAnnouncementEvent:FireClient(player, completedScore, completedKills)
			end
		end

		spawnCounts[player] += 1
		-- Scores and kills are the player's totals for this round. Only the
		-- per-life counters reset, so death no longer makes the main HUD read 0/0.
		spawnScores[player] = 0
		spawnKills[player] = 0
		setLeaderboardStats(player, scores[player] or 0, kills[player] or 0)
		scoreEvent:FireClient(player, scores[player] or 0, kills[player] or 0)
		fireRecords(player)
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	multikillStates[player] = nil
	completedSpawnBest[player] = nil
	spawnScores[player] = nil
	spawnKills[player] = nil
end)

-- MonsterSystem: the SINGLE source of truth for monster HP, scoring, and respawn.
-- All monster logic is centralized here (via MonsterManager) instead of being
-- scattered across per-monster scripts in the world.

local Players = game:GetService("Players")
local ws = game:GetService("Workspace")
local rs = game:GetService("ReplicatedStorage")
local MonsterManager = require(rs:WaitForChild("MonsterManager"))

local scores = {} -- Player -> current score
local kills = {} -- Player -> monsters for which the player earned score
local connected = {} -- humanoid -> true (in-memory, so clones re-register)
local spawns = {} -- model -> {template, cframe, livesRemaining} used for respawning in place
local managedMonsters = {} -- model -> true; only these models are allowed into the round count
local roundTemplates = {}

local spawnCounts = {}
local sessionBest = {} -- player -> {score, spawn}
local serverBest = { score = 0, playerName = "-", spawn = 0 }
local pendingRespawns = 0
local roundComplete = false
local roundFailed = false
local roundGeneration = 0
local announcedMonsterMilestones = {}
local lastBroadcastMonsterCount = nil
local multikillStates = {}

local RESPAWN_TIME = 30 -- seconds before a killed monster respawns
local RESPAWN_LIVES = 4 -- original life plus two server-owned resurrections
local ROUND_DURATION_SECONDS = 30 * 60
local DEFAULT_MONSTER_MAX_COUNT = 90
local ROUND_STARTED_AT_ATTRIBUTE = "RoundStartedAt"
local ROUND_ENDS_AT_ATTRIBUTE = "RoundEndsAt"
local MONSTER_MAX_COUNT_ATTRIBUTE = "MonsterMaxCount"
local MANAGED_MONSTER_ATTRIBUTE = "RoundManagedMonster"
local LIVES_REMAINING_ATTRIBUTE = "RoundLivesRemaining"

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
end

getMonsterMaxCount()
if ws:GetAttribute(ROUND_STARTED_AT_ATTRIBUTE) == nil
	or tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE)) == nil
	or tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE)) <= ws:GetServerTimeNow() then
	resetRoundClock()
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
local roundRestartedEvent = getOrCreateRemoteEvent("RoundRestarted")
local roundFailedEvent = getOrCreateRemoteEvent("RoundFailed")
local restartRoundEvent = getOrCreateRemoteEvent("RestartRound")
local monsterMilestoneEvent = getOrCreateRemoteEvent("MonsterMilestone")
local multikillEvent = getOrCreateRemoteEvent("MultikillAnnouncement")

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
			score = scores[player] or 0,
			kills = kills[player] or 0,
			bestSpawn = best.score or 0,
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

	-- BombMonster is an intentional non-rigged model. Its central PrimaryPart
	-- (or first body part in legacy copies) is a valid lifecycle/count anchor;
	-- other monsters still require HumanoidRootPart so broken NPC rigs retire.
	if model.Name == "BombMonster" then
		local fallback = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if fallback and fallback:IsA("BasePart") then
			return fallback
		end
	end

	return nil
end

-- Count only living NPCs explicitly registered by this system. Marketplace
-- debris and malformed lookalike models must never hold a round hostage.
local function countLivingMonsters()
	local count = 0

	for model in pairs(managedMonsters) do
		if model.Parent and model:IsDescendantOf(ws) then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			if humanoid and humanoid.Health > 0 and getMonsterRoot(model) then
				count += 1
			end
		end
	end

	return count
end

local function checkRoundComplete(count)
	if roundComplete or roundFailed then return end
	if pendingRespawns > 0 then return end
	if count ~= 0 then return end

	roundComplete = true
	ws:SetAttribute("RoundActive", false)
	roundCompleteEvent:FireAllClients({
		scoreboard = getScoreboard(),
		serverBest = serverBest,
		bestEver = bestEver,
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
	local count = countLivingMonsters()
	announceMonsterMilestone(count)
	monsterCountEvent:FireAllClients(count)
	checkRoundComplete(count)
end

local DEFAULT_SCORE_POPUP_COLOR = Color3.fromRGB(255, 238, 150)
local MULTIKILL_WINDOW_SECONDS = 5

local function showScorePopup(model, awards, color)
	if #awards == 0 then return end

	local root = model:FindFirstChild("HumanoidRootPart", true) or model:FindFirstChild("Head", true)
	if not root or not root:IsA("BasePart") then return end

	local lines = {}

	for _, award in ipairs(awards) do
		local player = Players:GetPlayerByUserId(award.userId)
		local name = player and player.Name or "Player"
		table.insert(lines, "+" .. tostring(award.points) .. " " .. name)
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "ScorePopupGui"
	gui.Size = UDim2.new(0, 220, 0, math.max(44, #lines * 30))
	gui.StudsOffset = Vector3.new(0, 5.4, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = root
	gui.Parent = model

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = table.concat(lines, "\n")
	label.Parent = gui

	task.delay(2, function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end)
end

local function updateScoreRecords(player)
	local currentScore = scores[player]
	local currentSpawn = spawnCounts[player] or 1

	if not sessionBest[player] or currentScore > sessionBest[player].score then
		sessionBest[player] = {
			score = currentScore,
			spawn = currentSpawn,
		}
	end

	if currentScore > serverBest.score then
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

local function registerMultikillKill(player, points)
	local state = multikillStates[player]
	if not state then
		state = { count = 0, baseScore = 0, token = 0, awardedBonus = 0 }
		multikillStates[player] = state
	end
	state.count += 1
	state.baseScore += points
	state.token += 1

	-- A chain becomes visible and earns its current bonus immediately on its
	-- second kill; subsequent kills update the same five-second chain.
	if state.count >= 2 then
		-- The chain's total bonus equals its kill count. Earlier immediate notices
		-- may already have awarded part of that total, so later kills add only the
		-- difference instead of double-counting a triple as +2 then +3.
		local bonus = state.count
		local bonusDelta = math.max(0, bonus - state.awardedBonus)
		state.awardedBonus = bonus
		scores[player] = (scores[player] or 0) + bonusDelta
		setLeaderboardStats(player, scores[player], kills[player] or 0)
		scoreEvent:FireClient(player, scores[player], kills[player] or 0)
		updateScoreRecords(player)
		broadcastRecords()
		multikillEvent:FireClient(player, state.count, state.baseScore, bonus)
	end

	local token = state.token
	task.delay(MULTIKILL_WINDOW_SECONDS, function()
		clearMultikill(player, state, token)
	end)
end

local function awardScore(player, points)
	scores[player] = (scores[player] or 0) + points
	kills[player] = (kills[player] or 0) + 1
	setLeaderboardStats(player, scores[player], kills[player])
	scoreEvent:FireClient(player, scores[player], kills[player])
	updateScoreRecords(player)
	registerMultikillKill(player, points)
end

-- Award points when a monster dies, then schedule one of its two permitted
-- server-owned resurrections. Permanent weapon kills consume every remaining
-- life, including for bomb monsters.
local function onMonsterKilled(hum, model)
	local config = MonsterManager.getConfig(model)

	if config then
		local awards = MonsterManager.consumeScoreAwards(hum, config.points)
		local popupColor = MonsterManager.getLastScoreColor(hum, DEFAULT_SCORE_POPUP_COLOR)
		local awardedAny = false

		for _, award in ipairs(awards) do
			local attacker = Players:GetPlayerByUserId(award.userId)

			if attacker then
				awardScore(attacker, award.points)
				awardedAny = true
			end
		end

		if awardedAny then
			showScorePopup(model, awards, popupColor)
			broadcastRecords()
		end
	end

	local data = spawns[model]
	if data then
		spawns[model] = nil
		local permanentWeaponKill =
			hum:GetAttribute("PermanentMonsterKill") == true
			or hum:GetAttribute("KilledByMonsterBlaster") == true
			or hum:GetAttribute("KilledByMonsterGun") == true

		local livesAfterDeath = permanentWeaponKill and 0 or math.max(0, (data.livesRemaining or 1) - 1)
		if livesAfterDeath == 0 or roundFailed or roundComplete then
			task.delay(2, function()
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

		task.delay(RESPAWN_TIME, function()
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

			if countLivingMonsters() < getMonsterMaxCount() then
				local clone = data.template:Clone()
				clone:SetAttribute("RoundRespawned", true)
				clone:SetAttribute(MANAGED_MONSTER_ATTRIBUTE, true)
				clone:SetAttribute(LIVES_REMAINING_ATTRIBUTE, livesAfterDeath)
				clone:PivotTo(data.cframe)
				clone.Parent = ws
			end

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
	humanoid.Health = 0
end

-- Set up a monster: apply HP, disable self-respawn, store a template,
-- and connect its Died event (only for real monsters).
local function setupMonster(model)
	local config = MonsterManager.getConfig(model)
	if not config then return end
	local hum = MonsterManager.getMonsterHumanoid(model)
	if not hum then return end

	MonsterManager.applyHP(model)
	disableSelfRespawn(model)
	managedMonsters[model] = true
	model:SetAttribute(MANAGED_MONSTER_ATTRIBUTE, true)

	local livesRemaining = tonumber(model:GetAttribute(LIVES_REMAINING_ATTRIBUTE)) or RESPAWN_LIVES
	livesRemaining = math.clamp(math.floor(livesRemaining), 1, RESPAWN_LIVES)
	model:SetAttribute(LIVES_REMAINING_ATTRIBUTE, livesRemaining)

	if not model:GetAttribute("RoundRespawned") then
		table.insert(roundTemplates, {
			template = model:Clone(),
			cframe = model:GetPivot(),
		})
		model:SetAttribute("RoundRespawned", true)
	end

	if not spawns[model] then
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
		scores[player] = 0
		kills[player] = 0
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
	announcedMonsterMilestones = {}
	lastBroadcastMonsterCount = nil
	resetRoundClock()

	for _, instance in ws:GetDescendants() do
		if instance:IsA("Model") and MonsterManager.getConfig(instance) then
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

restartRoundEvent.OnServerEvent:Connect(function()
	if not roundComplete and not roundFailed then return end
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
		if not roundComplete and not roundFailed then
			local endsAt = tonumber(ws:GetAttribute(ROUND_ENDS_AT_ATTRIBUTE)) or 0
			if ws:GetServerTimeNow() >= endsAt then
				roundFailed = true
				ws:SetAttribute("RoundActive", false)
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
		if not roundComplete and not roundFailed then
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

-- Reset each player's score when they respawn
local function onPlayerAdded(player)
	scores[player] = 0
	kills[player] = 0
	multikillStates[player] = nil
	spawnCounts[player] = 0
	setupLeaderstats(player)

	player.CharacterAdded:Connect(function()
		spawnCounts[player] += 1
		scores[player] = 0
		kills[player] = 0
		setLeaderboardStats(player, 0, 0)
		scoreEvent:FireClient(player, 0, 0)
		fireRecords(player)
	end)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player)
	multikillStates[player] = nil
end)

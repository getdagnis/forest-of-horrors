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
local spawns = {} -- model -> {template, cframe} used for respawning in place
local roundTemplates = {}

local spawnCounts = {}
local sessionBest = {} -- player -> {score, spawn}
local serverBest = { score = 0, playerName = "-", spawn = 0 }
local pendingRespawns = 0
local roundComplete = false

local RESPAWN_TIME = 15 -- seconds before a killed monster respawns
local RESPAWN_CHANCE = 0.8
local MAX_MONSTERS = 90
local BOMB_MONSTER_NAME = "BombMonster"
local ROUND_STARTED_AT_ATTRIBUTE = "RoundStartedAt"

if ws:GetAttribute(ROUND_STARTED_AT_ATTRIBUTE) == nil then
	ws:SetAttribute(ROUND_STARTED_AT_ATTRIBUTE, ws:GetServerTimeNow())
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
local restartRoundEvent = getOrCreateRemoteEvent("RestartRound")

local DataStoreService = game:GetService("DataStoreService")
local bestEverStore = DataStoreService:GetDataStore("ForestOfHorrorsBestEver")

local bestEver = {
	score = 0,
	playerName = "-",
	spawn = 0,
}

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
		personalBestSpawn = best.spawn or 0,

		serverBestScore = serverBest.score or 0,
		serverBestPlayerName = serverBest.playerName or "-",
		serverBestSpawn = serverBest.spawn or 0,

		bestEverScore = bestEver.score or 0,
		bestEverPlayerName = bestEver.playerName or "-",
		bestEverSpawn = bestEver.spawn or 0,
	})
end

local function broadcastRecords()
	for _, player in Players:GetPlayers() do
		fireRecords(player)
	end
end

local function updateBestEver(player, score, spawn)
	if score <= (bestEver.score or 0) then return end

	bestEver = {
		score = score,
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

local function getScoreboard()
	local list = {}

	for _, player in Players:GetPlayers() do
		table.insert(list, {
			name = player.Name,
			score = scores[player] or 0,
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

-- limit max amount of monsters to the constant above
local function countLivingMonsters()
	local count = 0

	for _, instance in ws:GetDescendants() do
		if instance:IsA("Model") and MonsterManager.getConfig(instance) then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			if humanoid and humanoid.Health > 0 then
				count += 1
			end
		end
	end

	return count
end

local function checkRoundComplete(count)
	if roundComplete then return end
	if pendingRespawns > 0 then return end
	if count ~= 0 then return end

	roundComplete = true
	roundCompleteEvent:FireAllClients({
		scoreboard = getScoreboard(),
		serverBest = serverBest,
		bestEver = bestEver,
	})
end

local function broadcastMonsterCount()
	local count = countLivingMonsters()
	monsterCountEvent:FireAllClients(count)
	checkRoundComplete(count)
end

local DEFAULT_SCORE_POPUP_COLOR = Color3.fromRGB(255, 238, 150)

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

local function awardScore(player, points)
	scores[player] = (scores[player] or 0) + points
	kills[player] = (kills[player] or 0) + 1
	setLeaderboardStats(player, scores[player], kills[player])
	scoreEvent:FireClient(player, scores[player], kills[player])

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

	updateBestEver(player, currentScore, currentSpawn)
end

-- Award points when a monster dies, then schedule its respawn in place.
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
		local spawnCount = config and config.respawnCount or 1
		local spawnSpacing = 8
		local isBombMonster = model.Name == BOMB_MONSTER_NAME
		local permanentWeaponKill =
			hum:GetAttribute("PermanentMonsterKill") == true
			or hum:GetAttribute("KilledByMonsterBlaster") == true
			or hum:GetAttribute("KilledByMonsterGun") == true

		if isBombMonster and permanentWeaponKill then
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

		task.delay(RESPAWN_TIME, function()
			if model.Parent then
				model:Destroy()
			end

			if not isBombMonster and math.random() > RESPAWN_CHANCE then
				pendingRespawns -= 1
				broadcastMonsterCount()
				broadcastRecords()
				return
			end

			for index = 1, spawnCount do
				if countLivingMonsters() >= MAX_MONSTERS then
					break
				end

				local clone = data.template:Clone()
				local offset = (index - (spawnCount + 1) / 2) * spawnSpacing

				clone:SetAttribute("RoundRespawned", true)
				clone:PivotTo(data.cframe * CFrame.new(offset, 0, 0))
				clone.Parent = ws
				broadcastMonsterCount()
				broadcastRecords()
			end

			pendingRespawns -= 1
			broadcastMonsterCount()
		end)
	end
end

-- Set up a monster: apply HP, disable self-respawn, store a template,
-- and connect its Died event (only for real monsters).
local function setupMonster(model)
	local config = MonsterManager.getConfig(model)
	if not config then return end
	local hum = MonsterManager.getMonsterHumanoid(model)
	if not hum then return end
	local isBombMonster = model.Name == BOMB_MONSTER_NAME
	-- Timed bombs must return after their own explosion even when their legacy
	-- marketplace model carries NoAutoRespawn. Weapon kills remain permanent in
	-- onMonsterKilled below, so this does not reintroduce killed bomb monsters.
	local shouldAutoRespawn = isBombMonster or not model:GetAttribute("NoAutoRespawn")

	MonsterManager.applyHP(model)
	disableSelfRespawn(model)

	if shouldAutoRespawn and not model:GetAttribute("RoundRespawned") then
		table.insert(roundTemplates, {
			template = model:Clone(),
			cframe = model:GetPivot(),
		})
		model:SetAttribute("RoundRespawned", true)
	end

	if shouldAutoRespawn and not spawns[model] then
		spawns[model] = {
			template = model:Clone(),
			cframe = model:GetPivot(),
		}
	end

	if not connected[hum] then
		connected[hum] = true
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
		setLeaderboardStats(player, 0, 0)
		scoreEvent:FireClient(player, 0, 0)
		fireRecords(player)
	end
end

local function restartRound()
	pendingRespawns = 0
	roundComplete = false
	ws:SetAttribute(ROUND_STARTED_AT_ATTRIBUTE, ws:GetServerTimeNow())

	for _, instance in ws:GetDescendants() do
		if instance:IsA("Model") and MonsterManager.getConfig(instance) then
			instance:Destroy()
		end
	end

	spawns = {}
	connected = {}

	for _, data in ipairs(roundTemplates) do
		if countLivingMonsters() >= MAX_MONSTERS then
			break
		end

		local clone = data.template:Clone()
		clone:SetAttribute("RoundRespawned", true)
		clone:PivotTo(data.cframe)
		clone.Parent = ws
	end

	resetScores()
	broadcastMonsterCount()
	broadcastRecords()
	roundRestartedEvent:FireAllClients()
end

restartRoundEvent.OnServerEvent:Connect(function()
	if not roundComplete then return end
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

-- Reset each player's score when they respawn
local function onPlayerAdded(player)
	scores[player] = 0
	kills[player] = 0
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

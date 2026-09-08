-- ScoreHistorySystem: persistence and presentation data for the scoreboard.
-- It observes MonsterSystem's authoritative leaderstats instead of owning score.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local recordsEvent = ReplicatedStorage:WaitForChild("RecordsUpdate")
local store = DataStoreService:GetDataStore("ForestOfHorrorsScoreHistoryV1")
local leaders = {}
local quickestEscape = { elapsedSeconds = nil, names = {} }
local saveQueued = false

local function sortLeaders()
	table.sort(leaders, function(a, b)
		if a.score == b.score then return a.playerName < b.playerName end
		return a.score > b.score
	end)
	while #leaders > 3 do table.remove(leaders) end
end

local function queueSave()
	if saveQueued then return end
	saveQueued = true
	task.delay(1, function()
		saveQueued = false
		local snapshot = { scoringLeaders = leaders, quickestEscape = quickestEscape }
		pcall(function() store:SetAsync("Records", snapshot) end)
	end)
end

task.spawn(function()
	local ok, saved = pcall(function() return store:GetAsync("Records") end)
	if not ok or type(saved) ~= "table" then return end
	if type(saved.scoringLeaders) == "table" then
		for _, row in ipairs(saved.scoringLeaders) do
			if type(row) == "table" and row.difficulty ~= "Easy" and tostring(row.playerName or "") ~= "" then
				table.insert(leaders, {
					playerName = tostring(row.playerName),
					userId = tonumber(row.userId) or 0,
					score = tonumber(row.score) or 0,
					kills = tonumber(row.kills) or 0,
					elapsedSeconds = tonumber(row.elapsedSeconds) or 0,
					difficulty = row.difficulty == "Easy" and "Easy" or "Hard",
				})
			end
		end
	end
	if type(saved.quickestEscape) == "table" and tonumber(saved.quickestEscape.elapsedSeconds) and type(saved.quickestEscape.names) == "table" then
		quickestEscape.elapsedSeconds = tonumber(saved.quickestEscape.elapsedSeconds)
		for _, name in ipairs(saved.quickestEscape.names) do table.insert(quickestEscape.names, tostring(name)) end
	end
	sortLeaders()
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function() if player.Parent then recordsEvent:FireClient(player, { scoringLeaders = leaders, quickestEscape = quickestEscape }) end end)
	end
end)

local function getStats(player)
	local stats = player:FindFirstChild("leaderstats")
	local score = stats and stats:FindFirstChild("Score")
	local kills = stats and stats:FindFirstChild("Kills")
	return tonumber(score and score.Value) or 0, tonumber(kills and kills.Value) or 0
end

local function currentRows()
	local rows = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local score, kills = getStats(player)
		table.insert(rows, { name = player.Name, difficulty = player:GetAttribute("Difficulty") == "Easy" and "Easy" or "Hard", score = score, kills = kills, deaths = 0, bestSpawn = 0 })
	end
	table.sort(rows, function(a, b) if a.score == b.score then return a.name < b.name end return a.score > b.score end)
	return rows
end

local function publish(player)
	if not player.Parent then return end
	local score, kills = getStats(player)
	recordsEvent:FireClient(player, {
		currentScore = score,
		currentKills = kills,
		scoreboard = currentRows(),
		scoringLeaders = leaders,
		quickestEscape = quickestEscape,
	})
end

local function observeScore(player, value)
	if not value:IsA("IntValue") or value.Name ~= "Score" then return end
	value.Changed:Connect(function()
		if player:GetAttribute("Difficulty") == "Easy" then return end
		local score, kills = getStats(player)
		local existing
		for _, row in ipairs(leaders) do
			if row.userId == player.UserId then existing = row break end
		end
		if not existing then
			existing = { playerName = player.Name, userId = player.UserId, score = 0, kills = 0, elapsedSeconds = 0, difficulty = "Hard" }
			table.insert(leaders, existing)
		end
		if score > existing.score then
			existing.playerName, existing.score, existing.kills = player.Name, score, kills
			existing.difficulty = "Hard"
			existing.elapsedSeconds = math.max(0, math.floor(Workspace:GetServerTimeNow() - (tonumber(Workspace:GetAttribute("RoundStartedAt")) or Workspace:GetServerTimeNow())))
			sortLeaders()
			queueSave()
		end
		for _, other in ipairs(Players:GetPlayers()) do publish(other) end
	end)
end

local function bindPlayer(player)
	local function bindStats(stats)
		local score = stats:FindFirstChild("Score")
		if score then observeScore(player, score) end
		stats.ChildAdded:Connect(function(value) observeScore(player, value) end)
	end
	local stats = player:FindFirstChild("leaderstats")
	if stats then bindStats(stats) end
	player.ChildAdded:Connect(function(child) if child.Name == "leaderstats" then bindStats(child) end end)
	player:GetAttributeChangedSignal("EscapedNightmare"):Connect(function()
		if player:GetAttribute("EscapedNightmare") ~= true then return end
		local elapsed = math.max(0, math.floor(Workspace:GetServerTimeNow() - (tonumber(Workspace:GetAttribute("RoundStartedAt")) or Workspace:GetServerTimeNow())))
		if not quickestEscape.elapsedSeconds or elapsed < quickestEscape.elapsedSeconds then
			quickestEscape.elapsedSeconds, quickestEscape.names = elapsed, { player.Name }
		elseif elapsed == quickestEscape.elapsedSeconds and not table.find(quickestEscape.names, player.Name) then
			table.insert(quickestEscape.names, player.Name)
			table.sort(quickestEscape.names)
		else return end
		queueSave()
		for _, other in ipairs(Players:GetPlayers()) do publish(other) end
	end)
	player:GetAttributeChangedSignal("Difficulty"):Connect(function()
		if player:GetAttribute("Difficulty") ~= "Easy" then return end
		for index = #leaders, 1, -1 do
			if leaders[index].userId == player.UserId then table.remove(leaders, index) end
		end
		sortLeaders()
		queueSave()
		for _, other in ipairs(Players:GetPlayers()) do publish(other) end
	end)
	task.defer(publish, player)
end

for _, player in ipairs(Players:GetPlayers()) do bindPlayer(player) end
Players.PlayerAdded:Connect(bindPlayer)

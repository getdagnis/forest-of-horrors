-- MonsterManager: single source of truth for monster HP and scoring.
-- All monster logic (HP, points, which humanoid is the real one) lives here
-- so every monster instance behaves consistently.

local MonsterManager = {}

-- Monster type configuration: name -> {hp, points}
local MONSTER_CONFIG = {
	["Drooling Zombie"] = { hp = 90, points = 1 },
	["weird monster thing"] = { hp = 160, points = 3 },
	["creepyMonster"] = { hp = 320, points = 5 },
	["creepyMonsterOrange"] = { hp = 420, points = 10 },
	["creepyMonsterWhite"] = { hp = 520, points = 15 },
	["BombMonster"] = { hp = 430, points = 5 },
	["Fouke Monster"] = { hp = 230, points = 3 },
	["Smiler"] = { hp = 800, points = 15 },
	["Brown Skinwalker"] = { hp = 400, points = 5 },
}

-- FortressBosses have ambiguous/empty names but contain a "Zombie" Humanoid child.
local function isFortressBoss(model)
	local zombieHumanoid = model:FindFirstChild("Zombie")
	return zombieHumanoid and zombieHumanoid:IsA("Humanoid")
end

function MonsterManager.getConfig(model)
	local config = MONSTER_CONFIG[model.Name]
	if config then
		return config
	end

	if isFortressBoss(model) then
		return { hp = 800, points = 15 }
	end

	return nil
end

-- Return the {hp, points} config for a monster model, or nil if it isn't a monster.
function MonsterManager.getMonsterHumanoid(model)
	if MONSTER_CONFIG[model.Name] then
		local directHumanoid = model:FindFirstChildOfClass("Humanoid")
		if directHumanoid then
			return directHumanoid
		end

		return model:FindFirstChildWhichIsA("Humanoid", true)
	end

	if isFortressBoss(model) then
		return model:FindFirstChild("Zombie")
	end

	return nil
end


-- Return the canonical Humanoid that represents a monster's health.
-- FortressBosses have TWO humanoids; the "Zombie" is the one that moves and
-- takes damage, so it is the real health pool.


-- Return the Humanoid that represents a monster, given any part of it.
function MonsterManager.getMonsterHumanoidFromHit(instance)
	local current = instance

	while current do
		if current:IsA("Model") and MonsterManager.getConfig(current) then
			local humanoid = MonsterManager.getMonsterHumanoid(current)
			if humanoid then
				return humanoid
			end
		end

		current = current.Parent
	end

	return nil
end

-- Points awarded for killing a monster (0 if not a monster)
function MonsterManager.getPoints(model)
	local config = MonsterManager.getConfig(model)
	return config and config.points or 0
end

function MonsterManager.markPermanentKill(humanoid, sourceName)
	if not humanoid then return end

	humanoid:SetAttribute("PermanentMonsterKill", true)

	if sourceName and sourceName ~= "" then
		humanoid:SetAttribute("KilledBy" .. sourceName, true)
	end
end

-- Apply the configured HP to a monster's canonical humanoid.
-- This is the single place that decides how much HP each monster has.
function MonsterManager.applyHP(model)
	local config = MonsterManager.getConfig(model)
	local hum = MonsterManager.getMonsterHumanoid(model)
	if hum and config then
		hum.MaxHealth = config.hp
		hum.Health = config.hp
		-- Hide names completely. Show Roblox's health bar only after damage; the
		-- private current/max label remains available to the player who hit it.
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 0
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	end
end

-- Random spawn points near McDonald's (center ~(-725, 15, -550))
local SPAWN_POINTS = {
	Vector3.new(-725, 15, -550),
	Vector3.new(-690, 15, -560),
	Vector3.new(-760, 15, -540),
	Vector3.new(-710, 15, -520),
	Vector3.new(-745, 15, -575),
	Vector3.new(-700, 15, -585),
}

function MonsterManager.getSpawnPoint()
	return SPAWN_POINTS[math.random(1, #SPAWN_POINTS)]
end

local damageLog = {}

function MonsterManager.recordPlayerDamage(humanoid, player, requestedDamage, scoreColor)
	if not humanoid or humanoid.Health <= 0 then return end
	if not player or not player:IsA("Player") then return end

	requestedDamage = tonumber(requestedDamage) or 0
	if requestedDamage <= 0 then return end

	local actualDamage = math.min(requestedDamage, humanoid.Health)
	if actualDamage <= 0 then return end

	local log = damageLog[humanoid]
	if not log then
		log = {
			maxHealth = math.max(1, humanoid.MaxHealth),
			players = {},
		}

		damageLog[humanoid] = log
	end

	local userId = player.UserId
	log.players[userId] = (log.players[userId] or 0) + actualDamage

	humanoid:SetAttribute("LastAttackerId", userId)

	if typeof(scoreColor) == "Color3" then
		humanoid:SetAttribute("LastScoreColor", scoreColor)
	end
end

function MonsterManager.consumeScoreAwards(humanoid, totalPoints)
	local awards = {}
	local log = damageLog[humanoid]
	damageLog[humanoid] = nil

	if not log then
		local attackerId = humanoid:GetAttribute("LastAttackerId")
		if attackerId then
			table.insert(awards, {
				userId = attackerId,
				points = totalPoints,
			})
		end

		return awards
	end

	local maxHealth = math.max(1, log.maxHealth or humanoid.MaxHealth)

	for userId, damage in pairs(log.players) do
		local points = math.ceil(totalPoints * (damage / maxHealth))
		points = math.max(1, points)

		table.insert(awards, {
			userId = userId,
			points = points,
			damage = damage,
		})
	end

	table.sort(awards, function(a, b)
		return a.points > b.points
	end)

	return awards
end

function MonsterManager.getLastScoreColor(humanoid, fallbackColor)
	local color = humanoid:GetAttribute("LastScoreColor")

	if typeof(color) == "Color3" then
		return color
	end

	return fallbackColor
end

return MonsterManager

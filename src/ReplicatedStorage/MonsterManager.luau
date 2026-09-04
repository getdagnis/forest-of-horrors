-- MonsterManager: single source of truth for monster HP and scoring.
-- All monster logic (HP, points, which humanoid is the real one) lives here
-- so every monster instance behaves consistently.

local MonsterManager = {}

-- Monster type configuration. HP is the real Humanoid pool; hpVsPlayers and
-- hpVsMonsters express effective HP for those sources (damage is scaled into
-- the one real pool). Keep both equal to hp unless a specific matchup needs a
-- deliberate resistance, rather than creating misleading separate health bars.
local MONSTER_CONFIG = {
	["Drooling Zombie"] = { shortName = "a zombie", pluralShortName = "zombies", hp = 90, hpVsPlayers = 90, hpVsMonsters = 90, points = 1, damageToPlayers = 35, damageToMonsters = 20 },
	-- WMT player damage remains zero: GuardianMonsterSystem owns its special
	-- rescue/pet behaviour and uses this monster-only value when appropriate.
	["weird monster thing"] = { shortName = "a weird monster thing", pluralShortName = "weird monster things", hp = 320, hpVsPlayers = 320, hpVsMonsters = 420, points = 2, damageToPlayers = 35, damageToMonsters = 80, zombieGroupTarget = false, roundTracked = false },
	-- Creepy damage against monsters is intentionally much lower than its player
	-- damage, preserving occasional conflict without NPCs clearing the map.
	["creepyMonster"] = { shortName = "a creepy monster", pluralShortName = "creepy monsters", hp = 320, hpVsPlayers = 320, hpVsMonsters = 320, points = 3, damageToPlayers = 60, damageToMonsters = 30, zombieGroupTarget = true },
	["creepyMonsterOrange"] = { shortName = "an orange creepy monster", pluralShortName = "orange creepy monsters", hp = 420, hpVsPlayers = 420, hpVsMonsters = 420, points = 5, damageToPlayers = 60, damageToMonsters = 10, zombieGroupTarget = false },
	["creepyMonsterWhite"] = { shortName = "a white creepy monster", pluralShortName = "white creepy monsters", hp = 520, hpVsPlayers = 520, hpVsMonsters = 520, points = 7, damageToPlayers = 100, damageToMonsters = 10, zombieGroupTarget = false },
	-- Keep this in lockstep with MonsterBombConfig. MonsterSystem also applies
	-- this value during registration, so a mismatch makes startup order decide
	-- the live health pool.
	["BombMonster"] = { shortName = "a monsterbomb", pluralShortName = "monsterbombs", hp = 200, hpVsPlayers = 200, hpVsMonsters = 200, points = 2, damageToPlayers = 40, damageToMonsters = 40, zombieGroupTarget = false },
	["FortressBoss"] = { shortName = "a forest boss", pluralShortName = "forest bosses", hp = 900, hpVsPlayers = 900, hpVsMonsters = 900, points = 7, damageToPlayers = 80, damageToMonsters = 10, zombieGroupTarget = true },
	["Smiler"] = { shortName = "Smiler", pluralShortName = "Smilers", hp = 800, hpVsPlayers = 800, hpVsMonsters = 800, points = 10, damageToPlayers = 7, damageToMonsters = 30, zombieGroupTarget = false },
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
		return MONSTER_CONFIG.FortressBoss
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

function MonsterManager.getShortName(model)
	local config = MonsterManager.getConfig(model)
	return config and config.shortName or (model and model.Name) or "monster"
end

function MonsterManager.getPluralShortName(model)
	local config = MonsterManager.getConfig(model)
	return config and (config.pluralShortName or (config.shortName .. "s")) or "monsters"
end

function MonsterManager.getDamageToPlayers(model)
	local config = MonsterManager.getConfig(model)
	return config and (config.damageToPlayers or 0) or 0
end

-- Round/radar eligibility is a gameplay contract, not a model-name guess.
-- Guardians are harmless rescue actors until a future hostility state opts them
-- in explicitly (for example by setting RoundTracked=true on the model).
function MonsterManager.isRoundTracked(model)
	local config = MonsterManager.getConfig(model)
	if not config then return false end
	local override = model:GetAttribute("RoundTracked")
	if override ~= nil then return override == true end
	return config.roundTracked ~= false and (config.damageToPlayers or 0) > 0
end

function MonsterManager.getMonsterRoot(model)
	if not model then return nil end
	local root = model:FindFirstChild("HumanoidRootPart", true)
		or model:FindFirstChild("UpperTorso", true)
		or model:FindFirstChild("Head", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	return root and root:IsA("BasePart") and root or nil
end

function MonsterManager.getDamageToMonsters(model)
	local config = MonsterManager.getConfig(model)
	return config and (config.damageToMonsters or 0) or 0
end

function MonsterManager.isZombieGroupTarget(model)
	local config = MonsterManager.getConfig(model)
	return config and config.zombieGroupTarget == true or false
end

-- WMTs remain directly damageable (and a pet ritual still needs a direct
-- contour), but a nearby WMT must never become a forgiving weapon aim-assist
-- target instead of the hostile monster under the player's crosshair.
function MonsterManager.isWeaponAimAssistTarget(model)
	return model ~= nil
		and MonsterManager.getConfig(model) ~= nil
		and model.Name ~= "weird monster thing"
end

local function scaledDamageForTarget(model, requestedDamage, healthField)
	local config = MonsterManager.getConfig(model)
	if not config then return 0 end

	local baseHealth = math.max(1, config.hp or 1)
	local effectiveHealth = math.max(1, config[healthField] or baseHealth)
	return math.max(0, requestedDamage * (baseHealth / effectiveHealth))
end

-- Applies monster-caused damage using the target's configured resistance.
-- No player-credit is recorded here: NPC infighting must never award score.
function MonsterManager.damageMonsterTarget(targetModel, requestedDamage, sourceModel)
	local humanoid = MonsterManager.getMonsterHumanoid(targetModel)
	if not humanoid or humanoid.Health <= 0 then return 0 end

	local actualDamage = math.min(scaledDamageForTarget(targetModel, requestedDamage, "hpVsMonsters"), humanoid.Health)
	if actualDamage > 0 then
		if sourceModel and sourceModel:IsA("Model") then
			-- A new monster/bomb hit supersedes any old player hit. Leaving the
			-- previous player ID here lets later systems mistake neutral damage for
			-- a player attack.
			humanoid:SetAttribute("LastAttackerId", nil)
			humanoid:SetAttribute("LastMonsterAttacker", MonsterManager.getShortName(sourceModel))
			humanoid:SetAttribute("LastMonsterAttackCause", sourceModel.Name == "BombMonster" and "bomb" or "monster")
		end
		humanoid:TakeDamage(actualDamage)
	end
	return actualDamage
end

-- Returns the player weapon damage after target-specific resistance. Callers
-- must use this value for both score attribution and Humanoid:TakeDamage.
function MonsterManager.getPlayerWeaponDamage(targetModel, requestedDamage)
	-- A bonded guardian remains vulnerable to its owner, but only takes half
	-- normal player-weapon damage. Unbonded WMTs retain their existing values.
	if targetModel and targetModel:GetAttribute("WMTGuardianPet") == true then
		requestedDamage = (tonumber(requestedDamage) or 0) * 0.5
	end
	return scaledDamageForTarget(targetModel, requestedDamage, "hpVsPlayers")
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
	humanoid:SetAttribute("LastMonsterAttacker", nil)

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

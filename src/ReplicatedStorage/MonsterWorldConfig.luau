-- MonsterWorldConfig: binding data for the living shared-world ecosystem.
-- It intentionally contains no movement, damage, or respawn code.

local MonsterWorldConfig = {}

MonsterWorldConfig.DEFAULT_THREAT_MODE = "Explorer"
MonsterWorldConfig.THREAT_MODES = {
	Observer = {
		playerTargetWeight = 0.08,
		localRetaliationOnly = true,
	},
	Explorer = {
		playerTargetWeight = 0.80,
		localRetaliationOnly = false,
	},
	Warrior = {
		playerTargetWeight = 1.00,
		localRetaliationOnly = false,
	},
}

MonsterWorldConfig.CENTER_PROFILES = {
	Town = {
		townLifeDuration = NumberRange.new(90, 180),
		migrationDuration = NumberRange.new(30, 80),
		migrationCooldown = NumberRange.new(90, 240),
	},
	Bastion = {
		townLifeDuration = NumberRange.new(90, 180),
		siegeDuration = NumberRange.new(75, 150),
		siegeCooldown = NumberRange.new(240, 420),
	},
}

MonsterWorldConfig.AMBIENT_CONFLICT = {
	duration = NumberRange.new(60, 120),
	zombieParticipationChance = 0.25,
}

function MonsterWorldConfig.getThreatMode(value)
	return MonsterWorldConfig.THREAT_MODES[value] and value or MonsterWorldConfig.DEFAULT_THREAT_MODE
end

return MonsterWorldConfig

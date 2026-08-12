local MonsterBombConfig = {}

MonsterBombConfig.MODEL_NAME = "Monster"

MonsterBombConfig.HEALTH = 400

MonsterBombConfig.MIN_WAIT = 30
MonsterBombConfig.MAX_WAIT = 90
MonsterBombConfig.WARNING_TIME = 5

MonsterBombConfig.BLAST_RADIUS = 100
MonsterBombConfig.MONSTER_DAMAGE = 400
MonsterBombConfig.PLAYER_DAMAGE_FRACTION = 0.5

MonsterBombConfig.IDLE_PULSE_HEIGHT = 12
MonsterBombConfig.IDLE_PULSE_SPEED = 1.6

MonsterBombConfig.WARNING_PULSE_HEIGHT = 18
MonsterBombConfig.WARNING_PULSE_SPEED = 8
MonsterBombConfig.WARNING_COLOR_BLEND = 0.85

MonsterBombConfig.BLAST_COLOR = Color3.fromRGB(255, 0, 255)
MonsterBombConfig.BLAST_STAGES = 6
MonsterBombConfig.BLAST_DURATION = 3
MonsterBombConfig.BLAST_MAIN_DURATION = 1.5
MonsterBombConfig.BLAST_START_RADIUS = 8

MonsterBombConfig.WARNING_SOUND_NAMES = {
	"WarningSound",
	"WarningSound1",
}

MonsterBombConfig.BLAST_SOUND_NAMES = {
	"BlastSound",
	"ExplosionSound",
}

MonsterBombConfig.WARNING_SOUND_VOLUME = 1.4
MonsterBombConfig.BLAST_SOUND_VOLUME = 2.2

return MonsterBombConfig

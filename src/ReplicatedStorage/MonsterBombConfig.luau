-- MonsterBombConfig

local MonsterBombConfig = {}

-- Exact model name recognised as a timed bomb monster.
MonsterBombConfig.MODEL_NAME = "BombMonster"

-- Bomb monster hit points before it is destroyed by a weapon or its own timer.
MonsterBombConfig.HEALTH = 430

-- Random idle time in seconds before the warning countdown starts.
MonsterBombConfig.MIN_WAIT = 120
MonsterBombConfig.MAX_WAIT = 270
-- Length of the final countdown in seconds.
MonsterBombConfig.WARNING_TIME = 10
-- Seconds between each warning beep and warning light pulse.
MonsterBombConfig.WARNING_BEEP_INTERVAL = 1

-- Maximum distance in studs affected by the explosion.
MonsterBombConfig.BLAST_RADIUS = 100
-- Maximum distance in studs at which the warning beep can be heard.
MonsterBombConfig.WARNING_SOUND_RADIUS = 115
-- Maximum distance in studs at which the explosion sound can be heard.
MonsterBombConfig.EXPLOSION_SOUND_RADIUS = 120
-- Sound child name to add to the Monster model for the one-shot explosion audio.
MonsterBombConfig.EXPLOSION_SOUND_NAME = "ExplosionSound"
-- Failsafe lifetime for the temporary world sound emitter in seconds.
MonsterBombConfig.EXPLOSION_SOUND_LIFETIME = 10
-- Flat damage dealt to each eligible non-bomb monster in range.
MonsterBombConfig.MONSTER_DAMAGE = 150
-- Portion of each player target's maximum health removed in range.
MonsterBombConfig.PLAYER_DAMAGE_FRACTION = 0.3

-- Reserved idle bobbing settings for the bomb model's calm state.
MonsterBombConfig.IDLE_PULSE_HEIGHT = 12
MonsterBombConfig.IDLE_PULSE_SPEED = 1.6

-- Reserved warning bobbing settings for the fast countdown state.
MonsterBombConfig.WARNING_PULSE_HEIGHT = 18
MonsterBombConfig.WARNING_PULSE_SPEED = 8

-- Pink colour used by the warning light and expanding explosion visual.
MonsterBombConfig.BLAST_COLOR = Color3.fromRGB(208, 18, 90)
-- Seconds for which the expanding explosion sphere remains visible.
MonsterBombConfig.BLAST_VISUAL_DURATION = 4

return MonsterBombConfig

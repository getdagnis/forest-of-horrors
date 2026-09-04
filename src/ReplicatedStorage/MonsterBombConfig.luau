-- MonsterBombConfig

local MonsterBombConfig = {}

-- Exact model name recognised as a timed bomb monster.
MonsterBombConfig.MODEL_NAME = "BombMonster"

-- Leave enough health after the fourth MG1 hit for the warning to run while
-- the Humanoid is still alive. The actual explosion owns the single death
-- transition, which is what starts MonsterSystem's respawn timer.
MonsterBombConfig.HEALTH = 200
-- Player weapon damage needed to arm a bomb. MG1 deals 40 damage per hit, so
-- this is four deliberate MG1 hits before the existing warning begins.
MonsterBombConfig.PLAYER_ARM_DAMAGE = 160

-- Random idle time in seconds before the warning countdown starts.
MonsterBombConfig.MIN_WAIT = 120
MonsterBombConfig.MAX_WAIT = 270
-- Length of the spoken five-to-one warning announcement in seconds.
MonsterBombConfig.WARNING_TIME = 5.5
-- Time after a bomb dies before its replacement returns. Other monster types
-- continue using MonsterSystem's normal respawn delay.
MonsterBombConfig.RESPAWN_TIME = 30

-- Maximum distance in studs affected by the explosion.
MonsterBombConfig.BLAST_RADIUS = 100
-- Maximum distance in studs at which the warning beep can be heard.
MonsterBombConfig.WARNING_SOUND_RADIUS = 250
-- Maximum distance in studs at which the explosion sound can be heard.
MonsterBombConfig.EXPLOSION_SOUND_RADIUS = 500
-- Preferred SoundService template name. A model child remains a compatibility
-- fallback for older bomb copies.
MonsterBombConfig.EXPLOSION_SOUND_TEMPLATE = "MonsterBombExplosion"
-- Fallback asset used when neither sound template exists in the live place.
MonsterBombConfig.EXPLOSION_SOUND_ID = "rbxassetid://91288569991875"
-- Legacy sound child name on imported bomb models.
MonsterBombConfig.EXPLOSION_SOUND_NAME = "ExplosionSound"
-- Failsafe lifetime for the temporary world sound emitter in seconds.
MonsterBombConfig.EXPLOSION_SOUND_LIFETIME = 10
-- Flat damage dealt to each eligible non-bomb monster in range.
MonsterBombConfig.MONSTER_DAMAGE = 150
-- Portion of each player target's maximum health removed in range.
MonsterBombConfig.PLAYER_DAMAGE_FRACTION = 0.3

-- Calm vertical bobbing settings for the bomb model's idle state.
MonsterBombConfig.IDLE_PULSE_HEIGHT = 12
MonsterBombConfig.IDLE_PULSE_SPEED = 1.6

-- Reserved warning bobbing settings for the fast countdown state.
MonsterBombConfig.WARNING_PULSE_HEIGHT = 18
MonsterBombConfig.WARNING_PULSE_SPEED = 8

-- Pink colour used by the warning light and expanding explosion visual.
MonsterBombConfig.BLAST_COLOR = Color3.fromRGB(208, 18, 90)
-- Active-warning appearance sampled from the authored BombMonster reference.
-- The light stays off while idle, then pulses for the spoken countdown only.
MonsterBombConfig.WARNING_SKIN_COLOR = Color3.fromRGB(89, 34, 89) -- Mulberry
MonsterBombConfig.WARNING_LIGHT_COLOR = Color3.fromRGB(255, 42, 148)
MonsterBombConfig.WARNING_LIGHT_MIN_BRIGHTNESS = 1
MonsterBombConfig.WARNING_LIGHT_MAX_BRIGHTNESS = 8
MonsterBombConfig.WARNING_LIGHT_MIN_RANGE = 36
MonsterBombConfig.WARNING_LIGHT_MAX_RANGE = 66
MonsterBombConfig.WARNING_LIGHT_PULSE_HZ = 2
-- Seconds for which the expanding explosion sphere remains visible.
MonsterBombConfig.BLAST_VISUAL_DURATION = 4

return MonsterBombConfig

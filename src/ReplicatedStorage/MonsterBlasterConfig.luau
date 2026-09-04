-- Shared MonsterBlaster tuning. Both the Tool client and Tool server use this
-- module so its one-press impact is presented and applied consistently.

local MonsterBlasterConfig = {}

MonsterBlasterConfig.COOLDOWN = 2
MonsterBlasterConfig.RANGE = 450
-- The Blaster is a one-press crowd-control weapon.  Its distinction is a
-- strong fixed impact plus cooldown, not a release-timing mini-game.
MonsterBlasterConfig.SHOT_POWER = 0.65

MonsterBlasterConfig.MIN_DAMAGE = 80
MonsterBlasterConfig.MAX_DAMAGE = 420
MonsterBlasterConfig.MIN_SHOCKWAVE_DAMAGE = 60
MonsterBlasterConfig.MAX_SHOCKWAVE_DAMAGE = 160
MonsterBlasterConfig.MIN_SHOCKWAVE_RADIUS = 6
MonsterBlasterConfig.MAX_SHOCKWAVE_RADIUS = 20
MonsterBlasterConfig.FLASH_COLOR = Color3.fromRGB(62, 169, 255)

function MonsterBlasterConfig.damageForPower(power)
	power = math.clamp(tonumber(power) or 0, 0, 1)
	return math.floor(MonsterBlasterConfig.MIN_DAMAGE
		+ ((MonsterBlasterConfig.MAX_DAMAGE - MonsterBlasterConfig.MIN_DAMAGE) * power))
end

function MonsterBlasterConfig.shockwaveDamageForPower(power)
	power = math.clamp(tonumber(power) or 0, 0, 1)
	return math.floor(MonsterBlasterConfig.MIN_SHOCKWAVE_DAMAGE
		+ ((MonsterBlasterConfig.MAX_SHOCKWAVE_DAMAGE - MonsterBlasterConfig.MIN_SHOCKWAVE_DAMAGE) * power))
end

function MonsterBlasterConfig.shockwaveRadiusForPower(power)
	power = math.clamp(tonumber(power) or 0, 0, 1)
	return MonsterBlasterConfig.MIN_SHOCKWAVE_RADIUS
		+ ((MonsterBlasterConfig.MAX_SHOCKWAVE_RADIUS - MonsterBlasterConfig.MIN_SHOCKWAVE_RADIUS) * power)
end

return MonsterBlasterConfig

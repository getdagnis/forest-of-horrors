-- Shared MonsterBlaster tuning. Both the Tool client and Tool server use this
-- module so its short charge and fixed impact are presented and applied consistently.

local MonsterBlasterConfig = {}

MonsterBlasterConfig.COOLDOWN = 2
MonsterBlasterConfig.RANGE = 450
-- Hold briefly, then release. There is no variable-power minigame and no HUD.
MonsterBlasterConfig.CHARGE_TIME = 0.45
-- A completed short charge fires at the configured 600 beam / 300 ground max.
MonsterBlasterConfig.SHOT_POWER = 1
-- Charged shots pass through monsters but still stop at solid map geometry.
MonsterBlasterConfig.PIERCES_MONSTERS = true

MonsterBlasterConfig.MIN_DAMAGE = 80
MonsterBlasterConfig.MAX_DAMAGE = 600
MonsterBlasterConfig.MIN_SHOCKWAVE_DAMAGE = 60
MonsterBlasterConfig.MAX_SHOCKWAVE_DAMAGE = 300
MonsterBlasterConfig.MIN_SHOCKWAVE_RADIUS = 12
MonsterBlasterConfig.MAX_SHOCKWAVE_RADIUS = 40
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

-- Shared MonsterBlaster tuning. Both the Tool client and Tool server use this
-- module so the charge HUD always represents the damage actually requested.

local MonsterBlasterConfig = {}

MonsterBlasterConfig.CHARGE_TIME = 5.2
MonsterBlasterConfig.MIN_CHARGE_TIME = 1
MonsterBlasterConfig.COOLDOWN = 2
MonsterBlasterConfig.RANGE = 450
MonsterBlasterConfig.FULL_CHARGE_TOLERANCE = 0.1

MonsterBlasterConfig.MIN_DAMAGE = 80
MonsterBlasterConfig.MAX_DAMAGE = 420
MonsterBlasterConfig.MIN_SHOCKWAVE_DAMAGE = 60
MonsterBlasterConfig.MAX_SHOCKWAVE_DAMAGE = 160
MonsterBlasterConfig.MIN_SHOCKWAVE_RADIUS = 6
MonsterBlasterConfig.MAX_SHOCKWAVE_RADIUS = 20
MonsterBlasterConfig.FLASH_COLOR = Color3.fromRGB(62, 169, 255)

function MonsterBlasterConfig.powerForHoldRatio(holdRatio)
	-- Energy is paid per valid shot, so each extra moment of holding should give
	-- a predictable, proportional improvement rather than a late-charge tax.
	return math.clamp(tonumber(holdRatio) or 0, 0, 1)
end

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

-- Shared MonsterBlaster tuning. Both the Tool client and Tool server use this
-- module so the charge HUD always represents the damage actually requested.

local MonsterBlasterConfig = {}

MonsterBlasterConfig.CHARGE_TIME = 5.2
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

-- The first 80% of the hold reaches 60% power gradually. The final 1.04s
-- uses an accelerating curve: about 70% at 4.5s, 82% at 4.8s, 90% at 5.0s,
-- then 100% at the full 5.2 seconds.
local EARLY_HOLD_RATIO = 0.80
local EARLY_MAX_POWER = 0.60
local EARLY_GAIN_EXPONENT = 1.8
local LATE_GAIN_EXPONENT = 1.25

function MonsterBlasterConfig.powerForHoldRatio(holdRatio)
	holdRatio = math.clamp(tonumber(holdRatio) or 0, 0, 1)

	if holdRatio < EARLY_HOLD_RATIO then
		local earlyRatio = math.clamp(holdRatio / EARLY_HOLD_RATIO, 0, 1)
		return EARLY_MAX_POWER * (earlyRatio ^ EARLY_GAIN_EXPONENT)
	end

	local lateRatio = math.clamp((holdRatio - EARLY_HOLD_RATIO) / (1 - EARLY_HOLD_RATIO), 0, 1)
	local latePower = (lateRatio ^ LATE_GAIN_EXPONENT)
	return EARLY_MAX_POWER + ((1 - EARLY_MAX_POWER) * latePower)
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

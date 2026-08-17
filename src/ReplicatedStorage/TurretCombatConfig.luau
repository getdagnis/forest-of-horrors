-- TurretCombatConfig
-- Initial mounted-gun tuning. These values are intentionally separate from
-- handheld laser weapons: a player must occupy a fixed exposed tower to use it.

return {
	Damage = 15,
	FireInterval = 0.10,
	Range = 500,
	HitRadius = 0.55,
	-- Fallback hit radius around the legacy controller's Mouse.Hit position.
	-- This imported tower has no trustworthy server-side seat/camera linkage.
	AimAssistRadius = 10,
	MuzzleForwardOffset = 5,
	ShotColor = Color3.fromRGB(255, 220, 70),
	FlashSeconds = 0.12,
}

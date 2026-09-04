-- GunAimConfig
-- Shared aim tuning. Adjust these values only after a fresh Studio Play test.
return {
	Range = 400,
	AimAssistRadius = 1.25,
	ContourGraceSeconds = 0.20,
	ContourUpdateInterval = 0.08,
	MuzzleClearanceDistance = 3,
	-- A weapon may correct a camera ray only a little sideways after it turns the
	-- character.  This prevents beams from leaving a barrel sideways/backwards
	-- in tight interiors while still giving a playable constrained-space fallback.
	BarrelForwardConeDegrees = 22,
	-- Normal third-person cameras sit well behind the character. These bounds
	-- reject remote origins far from the shooter without rejecting normal play.
	MaxCameraOriginOffset = 30,
	MaxCameraHeadOffset = 30,
	ShoulderDistance = 7,
	ShoulderOffset = Vector3.new(1.5, 1, 0),
	-- RMB focus keeps the safe shoulder position but narrows the view enough to
	-- read as an intentional aim zoom instead of the previous 4-degree nudge.
	FocusFieldOfView = 52,
	AimTurnSpeed = 18,
	LockAcquireDistance = 7,
	LockReleaseDistance = 15,
	LockConeDot = 0.94,
	LockRefreshSeconds = 0.1,
	Debug = false,
}

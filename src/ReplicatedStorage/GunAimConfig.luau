-- GunAimConfig
-- Shared aim tuning. Adjust these values only after a fresh Studio Play test.
return {
	Range = 400,
	AimAssistRadius = 1.25,
	ContourGraceSeconds = 0.20,
	MuzzleClearanceDistance = 3,
	-- Normal third-person cameras sit well behind the character. These bounds
	-- reject remote origins far from the shooter without rejecting normal play.
	MaxCameraOriginOffset = 30,
	MaxCameraHeadOffset = 30,
	ShoulderDistance = 7,
	ShoulderOffset = Vector3.new(1.5, 1, 0),
	AimTurnSpeed = 18,
	LockAcquireDistance = 7,
	LockReleaseDistance = 15,
	LockConeDot = 0.94,
	LockRefreshSeconds = 0.1,
	Debug = false,
}

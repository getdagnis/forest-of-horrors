-- NightLightingSystem: Forest of Horrors is always played at night.
-- Lighting is server-owned so every joining player receives the same time.

local Lighting = game:GetService("Lighting")

local NIGHT_CLOCK_TIME = 0 -- midnight
local isApplyingNight = false

local function enforceNight()
	if math.abs(Lighting.ClockTime - NIGHT_CLOCK_TIME) < 0.01 then return end

	isApplyingNight = true
	Lighting.ClockTime = NIGHT_CLOCK_TIME
	isApplyingNight = false
end

enforceNight()

-- Keep the horror setting intact if a legacy day/night script or an imported
-- map model attempts to advance the clock after the round has started.
Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
	if not isApplyingNight then
		enforceNight()
	end
end)

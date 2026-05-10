-- Shared constants for MVP
local Constants = {}

-- Sphere mechanics
Constants.SPHERE_MIN_RADIUS = 5
Constants.SPHERE_MAX_RADIUS = 80
Constants.SPHERE_SCALE_SPEED = 0.15 -- units per second
Constants.MAX_BRIGHTNESS = 2.5 -- Lower ceiling to prevent blinding and light leaking

-- Echolocation noise tiers
Constants.MOVEMENT_NOISE = {
	idle = {
		intensity = 0,
		radius = 0,
		monsterRisk = 0,
	},
	crouch = {
		intensity = 0.18,
		radius = 7,
		monsterRisk = 0.15,
		walkSpeed = 7,
	},
	walk = {
		intensity = 0.45,
		radius = 14,
		monsterRisk = 0.45,
		walkSpeed = 12,
	},
	sprint = {
		intensity = 1.1,
		radius = 30,
		monsterRisk = 1.25,
		walkSpeed = 20,
	},
	jump = {
		intensity = 1.45,
		radius = 36,
		monsterRisk = 1.6,
		duration = 0.45,
	},
}

Constants.VOICE_NOISE = {
	intensityMultiplier = 4,
	radiusMultiplier = 55,
	monsterRiskMultiplier = 1.3,
}

-- Monster AI
Constants.MONSTER_IDLE_RANGE = 100 -- detection range
Constants.MONSTER_MOVE_SPEED = 25
Constants.MONSTER_ACCELERATION = 800

-- Wall visibility
Constants.WALL_VISIBILITY_FADE_TIME = 2.0 -- seconds for wall to become invisible (increased from 0.5)

return Constants

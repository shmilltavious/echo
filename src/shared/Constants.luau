-- Shared constants for MVP
local Constants = {}

-- Sphere mechanics
Constants.SPHERE_MIN_RADIUS = 5
Constants.SPHERE_MAX_RADIUS = 80
Constants.SPHERE_SCALE_SPEED = 0.15 -- units per second
Constants.MAX_BRIGHTNESS = 2.5 -- Lower ceiling to prevent blinding and light leaking

-- Movement influence
Constants.SPEED_TO_RADIUS_MULTIPLIER = 0.2

-- Audio influence
Constants.MIC_VOLUME_TO_RADIUS_MULTIPLIER = 75

-- Monster AI
Constants.MONSTER_IDLE_RANGE = 100 -- detection range
Constants.MONSTER_MOVE_SPEED = 25
Constants.MONSTER_ACCELERATION = 800

-- Wall visibility
Constants.WALL_VISIBILITY_FADE_TIME = 2.0 -- seconds for wall to become invisible (increased from 0.5)

return Constants

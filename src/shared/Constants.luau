-- Shared constants for MVP
local Constants = {}

-- Sphere mechanics
Constants.SPHERE_MIN_RADIUS = 5
Constants.SPHERE_MAX_RADIUS = 48
Constants.SPHERE_SCALE_SPEED = 0.15 -- units per second
Constants.MAX_BRIGHTNESS = 1.8 -- Lower ceiling to prevent blinding and light leaking

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
		radius = 24,
		monsterRisk = 1.25,
		walkSpeed = 20,
	},
	jump = {
		intensity = 1.45,
		radius = 28,
		monsterRisk = 1.6,
		duration = 0.45,
	},
}

Constants.VOICE_NOISE = {
	intensityMultiplier = 3.2,
	radiusMultiplier = 30,
	monsterRiskMultiplier = 1.3,
}

-- Monster AI
Constants.MONSTER_IDLE_RANGE = 100 -- detection range
Constants.MONSTER_MOVE_SPEED = 25
Constants.MONSTER_ACCELERATION = 800

-- Wall visibility
Constants.WALL_VISIBILITY_FADE_TIME = 2.0 -- seconds for wall to become invisible (increased from 0.5)

Constants.OBJECTIVES = {
	OBJECTIVE_TAG = "Objective",
	REVEAL_TAG = "EcholocationReveal",
	INTERACT_RANGE = 16,
	REPAIR_DURATION = 3,
	FLASHLIGHT_ITEM_ID = "Flashlight",
	FUSE_BOX_DISCONNECTED_NAME = "Fuse Box (Disconnected)",
	FUSE_BOX_CONNECTED_NAME = "Fuse Box (Connected)",
	PROTOTYPE_MAP_NAME = "Prototype_Map",
	GAMEPLAY_ITEMS_FOLDER_NAME = "GameplayItems",
	AUTHORED_MAP_NAMES = { "New Map", "Spaceship_Map", "Map" },
	ESCAPE_DOOR_POSITION = Vector3.new(158.5, 6, 39),
	ESCAPE_DOOR_SIZE = Vector3.new(7, 10, 1),
	ESCAPE_DOOR_OPEN_OFFSET = Vector3.new(0, 12, 0),
	DECOY_SHARD_COUNT = 10,
	DECOY_SHATTER_FALLBACK_SECONDS = 2.25,
	ORDER = {
		Keycard = 1,
		Fuse = 2,
		RepairPanel = 3,
		EscapeDoor = 4,
		DecoyBottle = 0,
	},
	INTERACT_PART_NAMES = {
		Keycard = "KeycardInteract",
		Fuse = "FuseInteract",
		RepairPanel = "RepairPanelInteract",
		EscapeDoor = "EscapeDoorInteract",
		DecoyBottle = "DecoyBottleInteract",
	},
}

Constants.SOUNDS = {
	pickup = "rbxassetid://9112854440",
	panelRepair = "rbxassetid://9112854440",
	escapeSuccess = "rbxassetid://9112854440",
	decoyThrow = "rbxassetid://9112854440",
	decoyShatter = "rbxassetid://9112854440",
	ambientLandmark = "rbxassetid://9112854440",
	monster = {
		idle = "",
		look = "",
		roar = "",
		run = "",
		attack = "",
	},
}

Constants.MONSTER_ANIMATIONS = {
	-- Replace Run after exporting Monster_Run_InPlace_Roblox from Blender.
	-- Walk intentionally uses Run at reduced speed until a dedicated walk clip is imported.
	Idle = "rbxassetid://93982960068097",
	Look = "rbxassetid://106914673591637",
	Roar = "rbxassetid://110729878275185",
	Run = "rbxassetid://117522782092613",
	Walk = "rbxassetid://117522782092613",
	Attack = "rbxassetid://74427646472939",
}

Constants.REMOTE_LIMITS = {
	OBJECTIVE_INTERACT_COOLDOWN = 0.15,
	OBJECTIVE_REPAIR_COOLDOWN = 0.1,
	DECOY_THROW_COOLDOWN = 0.35,
	NOISE_REPORT_MIN_INTERVAL = 0.07,
	CLIENT_WAIT_TIMEOUT = 10,
}

Constants.MONSTER_AI = {
	PATROL_SPEED = 6.5,
	CORNER_SPEED = 7.5,
	COLLISION_HULL_SIZE = Vector3.new(11.8, 7, 11.8),
	PATH_AGENT_RADIUS = 5.9,
	PATH_AGENT_HEIGHT = 7,
	NAV_AGENT_RADIUS = 3.4,
	NAV_AGENT_HEIGHT = 7,
	DIRECT_MOVE_CLEARANCE_DISTANCE = 6,
	NOISE_TARGET_SAMPLE_RADII = { 7, 10, 14 },
	NOISE_TARGET_SAMPLE_DIRECTIONS = 12,
	REPATH_COOLDOWN = 0.35,
	SIGNIFICANT_NOISE_MIN_INTERVAL = 0.07,
	IDLE_NOISE_MIN_INTERVAL = 0.25,
	APPROACH_TARGET_MAX_RING = 18,
	PATH_DEBUG_ATTRIBUTES = true,
	CLIENT_NOISE_MAX_SERVER_DISTANCE = 32,
	CLIENT_NOISE_MAX_LAST_ACCEPTED_DISTANCE = 45,
	CLIENT_NOISE_STALE_SERVER_HEIGHT = 40,
	STRAIGHT_ACCEL_DELAY = 3.25,
	STRAIGHT_ACCEL_TIME = 1.25,
	SENSE_DECAY_TIME = 5,
	HEAR_THRESHOLD = 0.35,
	WAYPOINT_REACH_DIST = 4,
	WAYPOINT_TIMEOUT = 6,
	ATTACK_RANGE = 5.5,
	TOUCH_ATTACK_RANGE = 2.35,
	STILL_SURVIVE_TIME = 1.35,
	CATCH_COOLDOWN = 4,
	COOP_VISUAL_THRESHOLD = 0.025,
	RESPAWN_CHARACTER_TIMEOUT = 5,
	NOISE_REACTIONS = {
		crouch = {
			hearThreshold = 0.55,
			speed = 7.5,
			maxSpeed = 9.5,
			decay = 2.5,
		},
		walk = {
			hearThreshold = 0.35,
			speed = 9.5,
			maxSpeed = 12,
			decay = 4,
		},
		sprint = {
			hearThreshold = 0.2,
			speed = 11.5,
			maxSpeed = 17,
			decay = 7,
		},
		jump = {
			hearThreshold = 0.15,
			speed = 12,
			maxSpeed = 17.5,
			decay = 8,
		},
		voice = {
			hearThreshold = 0.2,
			speed = 12,
			maxSpeed = 18,
			decay = 8,
		},
		decoy = {
			hearThreshold = 0.1,
			speed = 12.5,
			maxSpeed = 18.5,
			decay = 9,
		},
	},
}

return Constants

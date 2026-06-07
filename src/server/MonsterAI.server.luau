local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MonsterVisualController = require(script.Parent.MonsterVisualController)
local MONSTER_CONFIG = Constants.MONSTER_AI
local REMOTE_LIMITS = Constants.REMOTE_LIMITS
local NOISE_REPORT_MIN_INTERVAL = REMOTE_LIMITS.NOISE_REPORT_MIN_INTERVAL

local PATROL_SPEED = MONSTER_CONFIG.PATROL_SPEED
local CORNER_SPEED = MONSTER_CONFIG.CORNER_SPEED
local COLLISION_HULL_SIZE = MONSTER_CONFIG.COLLISION_HULL_SIZE or Vector3.new(11.8, 7, 11.8)
local PATH_AGENT_RADIUS = MONSTER_CONFIG.PATH_AGENT_RADIUS or 5.9
local PATH_AGENT_HEIGHT = MONSTER_CONFIG.PATH_AGENT_HEIGHT or 7
local NAV_AGENT_RADIUS = MONSTER_CONFIG.NAV_AGENT_RADIUS or 3.4
local NAV_AGENT_HEIGHT = MONSTER_CONFIG.NAV_AGENT_HEIGHT or 7
local STRAIGHT_ACCEL_DELAY = MONSTER_CONFIG.STRAIGHT_ACCEL_DELAY
local STRAIGHT_ACCEL_TIME = MONSTER_CONFIG.STRAIGHT_ACCEL_TIME
local SENSE_DECAY_TIME = MONSTER_CONFIG.SENSE_DECAY_TIME
local HEAR_THRESHOLD = MONSTER_CONFIG.HEAR_THRESHOLD
local WAYPOINT_REACH_DIST = MONSTER_CONFIG.WAYPOINT_REACH_DIST
local WAYPOINT_TIMEOUT = MONSTER_CONFIG.WAYPOINT_TIMEOUT
local ATTACK_RANGE = MONSTER_CONFIG.ATTACK_RANGE
local TOUCH_ATTACK_RANGE = MONSTER_CONFIG.TOUCH_ATTACK_RANGE
local STILL_SURVIVE_TIME = MONSTER_CONFIG.STILL_SURVIVE_TIME
local CATCH_COOLDOWN = MONSTER_CONFIG.CATCH_COOLDOWN
local COOP_VISUAL_THRESHOLD = MONSTER_CONFIG.COOP_VISUAL_THRESHOLD
local DIRECT_MOVE_CLEARANCE_DISTANCE = MONSTER_CONFIG.DIRECT_MOVE_CLEARANCE_DISTANCE or 6
local NOISE_TARGET_SAMPLE_RADII = MONSTER_CONFIG.NOISE_TARGET_SAMPLE_RADII or { 7, 10, 14 }
local NOISE_TARGET_SAMPLE_DIRECTIONS = MONSTER_CONFIG.NOISE_TARGET_SAMPLE_DIRECTIONS or 12
local REPATH_COOLDOWN = MONSTER_CONFIG.REPATH_COOLDOWN or 0.35
local STOPPED_NOISE_FACING_DELAY = MONSTER_CONFIG.STOPPED_NOISE_FACING_DELAY or 0.18
local STOPPED_NOISE_FACING_SPEED = MONSTER_CONFIG.STOPPED_NOISE_FACING_SPEED or 0.35
local SIGNIFICANT_NOISE_MIN_INTERVAL = MONSTER_CONFIG.SIGNIFICANT_NOISE_MIN_INTERVAL or NOISE_REPORT_MIN_INTERVAL
local IDLE_NOISE_MIN_INTERVAL = MONSTER_CONFIG.IDLE_NOISE_MIN_INTERVAL or 0.25
local APPROACH_TARGET_MAX_RING = MONSTER_CONFIG.APPROACH_TARGET_MAX_RING or 18
local PATH_DEBUG_ATTRIBUTES = MONSTER_CONFIG.PATH_DEBUG_ATTRIBUTES == true
local CLIENT_NOISE_MAX_SERVER_DISTANCE = MONSTER_CONFIG.CLIENT_NOISE_MAX_SERVER_DISTANCE or 32
local CLIENT_NOISE_MAX_LAST_ACCEPTED_DISTANCE = MONSTER_CONFIG.CLIENT_NOISE_MAX_LAST_ACCEPTED_DISTANCE or 45
local CLIENT_NOISE_STALE_SERVER_HEIGHT = MONSTER_CONFIG.CLIENT_NOISE_STALE_SERVER_HEIGHT or 40
local AUTHORED_MAP_NAMES = Constants.OBJECTIVES.AUTHORED_MAP_NAMES
local VALID_MOVEMENT_STATES = {
	idle = true,
	crouch = true,
	walk = true,
	sprint = true,
	jump = true,
	decoy = true,
}
local NOISE_REACTIONS = MONSTER_CONFIG.NOISE_REACTIONS
local monsterContainer: Model? = nil

local function findHumanoidDriverModel(container: Model): Model?
	if container:FindFirstChildOfClass("Humanoid") and container:FindFirstChild("HumanoidRootPart") then
		return container
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:FindFirstChildOfClass("Humanoid")
			and descendant:FindFirstChild("HumanoidRootPart")
		then
			return descendant
		end
	end

	return nil
end

local function resolveHumanoidDriverModel(container: Model): Model?
	local deadline = os.clock() + 5
	repeat
		local driverModel = findHumanoidDriverModel(container)
		if driverModel then
			return driverModel
		end
		task.wait(0.1)
	until os.clock() > deadline

	return nil
end

local function findMonsterModel(): Model?
	local found = workspace:WaitForChild("Monster", 5)
	if found and found:IsA("Model") then
		monsterContainer = found
		local driverModel = resolveHumanoidDriverModel(found)
		if driverModel then
			if driverModel ~= found then
				print(string.format("MonsterAI: using nested Humanoid driver %s inside game.Workspace.Monster", driverModel:GetFullName()))
			end
			return driverModel
		end
	end

	warn("MonsterAI disabled: expected game.Workspace.Monster to be or contain a Humanoid driver model.")
	return nil
end

local monsterModel = findMonsterModel()
if not monsterModel then
	return
end

local humanoid = monsterModel:WaitForChild("Humanoid", 5)
local rootPart = monsterModel:WaitForChild("HumanoidRootPart", 5)
if not (humanoid and humanoid:IsA("Humanoid") and rootPart and rootPart:IsA("BasePart")) then
	warn("MonsterAI disabled: monster is missing Humanoid or HumanoidRootPart.")
	return
end

rootPart:SetNetworkOwner(nil)

humanoid.AutoRotate = true
humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

local motionAttachment = rootPart:FindFirstChild("MonsterMotionAttachment")
if not (motionAttachment and motionAttachment:IsA("Attachment")) then
	motionAttachment = Instance.new("Attachment")
	motionAttachment.Name = "MonsterMotionAttachment"
	motionAttachment.Parent = rootPart
end

local motionVelocity = rootPart:FindFirstChild("MonsterMotionLinearVelocity")
if not (motionVelocity and motionVelocity:IsA("LinearVelocity")) then
	motionVelocity = Instance.new("LinearVelocity")
	motionVelocity.Name = "MonsterMotionLinearVelocity"
	motionVelocity.Parent = rootPart
end
motionVelocity.Attachment0 = motionAttachment
motionVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
motionVelocity.MaxForce = 1e7
motionVelocity.VectorVelocity = Vector3.zero
motionVelocity.Enabled = false

local monsterVisual = MonsterVisualController.start({
	driverRoot = rootPart,
	hideDriverModel = monsterModel,
	rig = monsterContainer,
	visualPartName = "geometry_0",
	hiddenPrewarm = true,
})
local collisionHull = (monsterContainer or monsterModel):WaitForChild("MonsterCollisionHull", 3)
if not (collisionHull and collisionHull:IsA("BasePart")) then
	warn("MonsterAI: MonsterCollisionHull was not ready; wall avoidance may be less reliable.")
end

local pulseEvent = ReplicatedStorage:FindFirstChild("EcholocationPulse")
if not pulseEvent then
	pulseEvent = Instance.new("RemoteEvent")
	pulseEvent.Name = "EcholocationPulse"
	pulseEvent.Parent = ReplicatedStorage
end

local serverNoiseEvent = ReplicatedStorage:FindFirstChild("ServerNoiseEvent") or Instance.new("BindableEvent")
serverNoiseEvent.Name = "ServerNoiseEvent"
serverNoiseEvent.Parent = ReplicatedStorage

local caughtEvent = ReplicatedStorage:FindFirstChild("MonsterCaughtPlayer") or Instance.new("RemoteEvent")
caughtEvent.Name = "MonsterCaughtPlayer"
caughtEvent.Parent = ReplicatedStorage

local function getActiveMap(): Instance?
	for _, mapName in ipairs(AUTHORED_MAP_NAMES) do
		local map = workspace:FindFirstChild(mapName)
		if map then
			return map
		end
	end

	return workspace:FindFirstChild("Prototype_Map")
end

local lastNoisePosition = nil
local lastNoiseTime = 0
local lastNoiseDecay = SENSE_DECAY_TIME
local lastNoiseType = "none"
local lastNoiseIntensity = 0
local chaseBaseSpeed = NOISE_REACTIONS.walk.speed
local chaseMaxSpeed = NOISE_REACTIONS.walk.maxSpeed
local patrolWaypoints = {}
local currentWaypointIndex = 1
local lastMoveDirection: Vector3? = nil
local straightRunTime = 0
local cornerSlowUntil = 0
local playerNoiseState = {}
local caughtCooldowns = {}
local lastNoiseReportAt = {}
local lastSignificantNoiseAt = {}
local lastAcceptedNoisePositions = {}
local chaseRoarUntil = 0
local lastRequestedLocomotionState: string? = nil

local function telegraphNewChase(now: number)
	chaseRoarUntil = math.max(chaseRoarUntil, now + 0.85)
	if monsterVisual then
		monsterVisual.playRoar()
	end
end

local function setMonsterDebugAttribute(name: string, value)
	if not PATH_DEBUG_ATTRIBUTES then
		return
	end

	local container = monsterContainer or monsterModel
	if container then
		container:SetAttribute("MonsterAI_" .. name, value)
	end
end

local function setPathDebug(status: string, chosenTarget: Vector3?, blockedReason: string?)
	setMonsterDebugAttribute("PathStatus", status)
	setMonsterDebugAttribute("ChosenTarget", chosenTarget)
	setMonsterDebugAttribute("BlockedReason", blockedReason or "")
end

local function setFacingModeDebug(mode: string)
	setMonsterDebugAttribute("CurrentFacingMode", mode)
end

local function getNoiseGroundRaycastParams(ignoreInstance: Instance?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = { monsterModel }
	if monsterContainer then
		table.insert(ignored, monsterContainer)
	end
	if ignoreInstance then
		table.insert(ignored, ignoreInstance)
	end
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	return params
end

local function projectNoisePositionToGround(position: Vector3, ignoreInstance: Instance?): Vector3
	local origin = position + Vector3.new(0, 8, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -220, 0), getNoiseGroundRaycastParams(ignoreInstance))
	if result then
		return result.Position + Vector3.new(0, PATH_AGENT_HEIGHT * 0.5, 0)
	end

	return Vector3.new(position.X, rootPart.Position.Y, position.Z)
end

local function getPlanarDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function isServerCharacterPositionStale(serverPosition: Vector3, ignoreInstance: Instance?): boolean
	local projectedServerPosition = projectNoisePositionToGround(serverPosition, ignoreInstance)
	return math.abs(serverPosition.Y - projectedServerPosition.Y) >= CLIENT_NOISE_STALE_SERVER_HEIGHT
end

local function chooseReportedNoisePosition(player, reportedPosition, serverPosition: Vector3, ignoreInstance: Instance?)
	if typeof(reportedPosition) ~= "Vector3" then
		setMonsterDebugAttribute("LastAcceptedNoisePosition", serverPosition)
		setMonsterDebugAttribute("LastRejectedNoiseReason", "")
		return serverPosition
	end

	local serverDelta = getPlanarDistance(serverPosition, reportedPosition)
	if serverDelta <= CLIENT_NOISE_MAX_SERVER_DISTANCE then
		lastAcceptedNoisePositions[player] = reportedPosition
		setMonsterDebugAttribute("LastAcceptedNoisePosition", reportedPosition)
		setMonsterDebugAttribute("LastRejectedNoiseReason", "")
		return reportedPosition
	end

	local lastAccepted = lastAcceptedNoisePositions[player]
	if lastAccepted and getPlanarDistance(lastAccepted, reportedPosition) <= CLIENT_NOISE_MAX_LAST_ACCEPTED_DISTANCE then
		lastAcceptedNoisePositions[player] = reportedPosition
		setMonsterDebugAttribute("LastAcceptedNoisePosition", reportedPosition)
		setMonsterDebugAttribute("LastRejectedNoiseReason", "")
		return reportedPosition
	end

	if isServerCharacterPositionStale(serverPosition, ignoreInstance) then
		lastAcceptedNoisePositions[player] = reportedPosition
		setMonsterDebugAttribute("LastAcceptedNoisePosition", reportedPosition)
		setMonsterDebugAttribute("LastRejectedNoiseReason", "AcceptedClientPositionServerCharacterStale")
		return reportedPosition
	end

	setMonsterDebugAttribute("LastRejectedNoiseReason", "ClientPositionTooFar")
	return serverPosition
end

local function recordHeardNoise(position: Vector3, noise, reaction, now: number, ignoreInstance: Instance?)
	local pathPosition = projectNoisePositionToGround(position, ignoreInstance)
	lastNoisePosition = pathPosition
	lastNoiseTime = now
	lastNoiseDecay = reaction.decay or SENSE_DECAY_TIME
	lastNoiseType = if noise.hasVoice then "voice" else tostring(noise.movementState or "walk")
	lastNoiseIntensity = tonumber(noise.intensity) or 0

	setMonsterDebugAttribute("LastHeardAt", now)
	setMonsterDebugAttribute("LastNoiseType", lastNoiseType)
	setMonsterDebugAttribute("LastNoiseIntensity", lastNoiseIntensity)
	setMonsterDebugAttribute("LastNoisePosition", position)
	setMonsterDebugAttribute("LastNoisePathPosition", pathPosition)
	setMonsterDebugAttribute("ClientVoiceVolume", tonumber(noise.voiceVolume) or 0)
	setMonsterDebugAttribute("NoiseLatched", true)
	setMonsterDebugAttribute("LastSignificantNoiseAt", now)
	setPathDebug("Heard", nil, "")
end

local function normalizeNoiseReport(report)
	if typeof(report) == "number" then
		return {
			intensity = math.clamp(report, 0, 6),
			movementState = "walk",
			hasVoice = false,
			radius = 0,
		}
	end

	if typeof(report) ~= "table" then
		return {
			intensity = 0,
			movementState = "idle",
			hasVoice = false,
			radius = 0,
		}
	end

	local movementState = tostring(report.movementState or "walk")
	if not VALID_MOVEMENT_STATES[movementState] then
		movementState = "walk"
	end

	return {
		intensity = math.clamp(tonumber(report.intensity) or 0, 0, 6),
		visualIntensity = math.clamp(tonumber(report.visualIntensity) or tonumber(report.intensity) or 0, 0, 5),
		radius = math.clamp(tonumber(report.radius) or 0, 0, 64),
		movementState = movementState,
		hasVoice = report.hasVoice == true,
		voiceVolume = math.clamp(tonumber(report.voiceVolume) or 0, 0, 1),
	}
end

local function getServerMovementNoise(playerRoot: BasePart, playerHumanoid: Humanoid)
	local state = playerHumanoid:GetState()
	local velocity = playerRoot.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return {
			intensity = 1.45,
			visualIntensity = 0.44,
			radius = 9,
			movementState = "jump",
		}
	elseif horizontalSpeed >= 16 then
		return {
			intensity = 1.25,
			visualIntensity = 0.33,
			radius = 8,
			movementState = "sprint",
		}
	elseif horizontalSpeed >= 8 then
		return {
			intensity = 0.45,
			visualIntensity = 0.14,
			radius = 5,
			movementState = "walk",
		}
	end

	return nil
end

local function applyServerMovementFloor(noise, playerRoot: BasePart, playerHumanoid: Humanoid)
	local movementNoise = getServerMovementNoise(playerRoot, playerHumanoid)
	if not movementNoise or noise.intensity >= movementNoise.intensity then
		return noise
	end

	noise.intensity = movementNoise.intensity
	noise.visualIntensity = math.max(tonumber(noise.visualIntensity) or 0, movementNoise.visualIntensity)
	noise.radius = math.max(tonumber(noise.radius) or 0, movementNoise.radius)
	noise.movementState = movementNoise.movementState
	return noise
end

local function getNoiseReaction(report)
	if report.movementState == "decoy" then
		return NOISE_REACTIONS.decoy
	end

	if report.hasVoice and report.voiceVolume > 0.08 then
		return NOISE_REACTIONS.voice
	end

	return NOISE_REACTIONS[report.movementState] or NOISE_REACTIONS.walk
end

local function horizontalDirection(fromPosition: Vector3, toPosition: Vector3): Vector3?
	local delta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
	if delta.Magnitude < 0.05 then
		return nil
	end
	return delta.Unit
end

local function getHorizontalDelta(fromPosition: Vector3, toPosition: Vector3): Vector3
	return Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
end

local function setMonsterFacing(position: Vector3)
	if not monsterVisual then
		return
	end

	local direction = horizontalDirection(rootPart.Position, position)
	if direction then
		monsterVisual.setFacingDirection(direction)
	end
end

local function setMonsterFacingDirection(direction: Vector3)
	if monsterVisual then
		monsterVisual.setFacingDirection(direction)
	end
end

local function getMonsterPlanarSpeed(): number
	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function faceNoiseSourceAfterStop(noiseSource: Vector3)
	task.wait(STOPPED_NOISE_FACING_DELAY)
	if getMonsterPlanarSpeed() <= STOPPED_NOISE_FACING_SPEED then
		setFacingModeDebug("NoiseSource")
		setMonsterFacing(noiseSource)
	end
end

local function setMonsterLocomotion(state: string)
	if lastRequestedLocomotionState == state then
		return
	end
	lastRequestedLocomotionState = state
	if monsterVisual then
		monsterVisual.setLocomotionState(state)
	end
end

local function getClearanceRaycastParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored = { monsterModel }
	if monsterContainer then
		table.insert(ignored, monsterContainer)
	end
	if monsterVisual and monsterVisual.rig then
		table.insert(ignored, monsterVisual.rig)
	end
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	return params
end

local function getHullClearanceBlock(destination: Vector3, minimumClearanceDistance: number?): RaycastResult?
	local delta = getHorizontalDelta(rootPart.Position, destination)
	local distance = delta.Magnitude
	if distance <= 0.05 then
		return nil
	end

	local direction = delta.Unit
	local origin = CFrame.lookAt(rootPart.Position, rootPart.Position + direction)
	local maxDistance = if minimumClearanceDistance and minimumClearanceDistance > 0
		then math.max(distance, minimumClearanceDistance)
		else distance
	return workspace:Blockcast(origin, COLLISION_HULL_SIZE, direction * maxDistance, getClearanceRaycastParams())
end

local function getBlockerName(result: RaycastResult?): string
	local instance = result and result.Instance
	return if instance then instance:GetFullName() else ""
end

local function hasHullClearanceTo(destination: Vector3, minimumClearanceDistance: number?): boolean
	local result = getHullClearanceBlock(destination, minimumClearanceDistance)
	if result then
		setMonsterDebugAttribute("FullHullBlockedBy", getBlockerName(result))
	else
		setMonsterDebugAttribute("FullHullBlockedBy", "")
	end
	return result == nil
end

local function getSafeApproachBeforeBlock(destination: Vector3, minimumClearanceDistance: number?): Vector3?
	local result = getHullClearanceBlock(destination, minimumClearanceDistance)
	if not result then
		return destination
	end

	setMonsterDebugAttribute("FullHullBlockedBy", getBlockerName(result))
	local delta = getHorizontalDelta(rootPart.Position, destination)
	local distance = delta.Magnitude
	if distance <= WAYPOINT_REACH_DIST then
		return nil
	end

	local hitDistance = getHorizontalDelta(rootPart.Position, result.Position).Magnitude
	local safeDistance = math.clamp(hitDistance - (COLLISION_HULL_SIZE.X * 0.15), 0, distance)
	if safeDistance <= WAYPOINT_REACH_DIST then
		return nil
	end

	local safePosition = rootPart.Position + (delta.Unit * safeDistance)
	return Vector3.new(safePosition.X, rootPart.Position.Y, safePosition.Z)
end

local function setMonsterVelocity(velocity: Vector3)
	motionVelocity.VectorVelocity = velocity
	motionVelocity.Enabled = velocity.Magnitude > 0.01
	rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, rootPart.AssemblyLinearVelocity.Y, velocity.Z)
end

local function stopMonsterMotion()
	motionVelocity.VectorVelocity = Vector3.zero
	motionVelocity.Enabled = false
	humanoid:Move(Vector3.zero, false)
	humanoid:MoveTo(rootPart.Position)
	rootPart.AssemblyLinearVelocity = Vector3.new(0, rootPart.AssemblyLinearVelocity.Y, 0)
	setMonsterDebugAttribute("CurrentMoveTarget", nil)
end

local function setChaseSpeeds(reaction, intensity)
	local baseSpeed = reaction.speed or NOISE_REACTIONS.walk.speed
	local maxSpeed = reaction.maxSpeed or baseSpeed
	local urgency = math.clamp((tonumber(intensity) or 0) - 0.35, 0, 1)

	chaseBaseSpeed = math.clamp(baseSpeed + (urgency * 0.8), PATROL_SPEED, maxSpeed)
	chaseMaxSpeed = math.max(chaseBaseSpeed, maxSpeed + (urgency * 0.6))
end

local function broadcastCoopPulse(sourcePlayer, rootPosition: Vector3, noise)
	local visualIntensity = math.clamp(tonumber(noise.visualIntensity) or 0, 0, 5)
	local radius = math.clamp(tonumber(noise.radius) or 0, 0, 64)
	if visualIntensity < COOP_VISUAL_THRESHOLD or radius <= 0 then
		return
	end

	local payload = {
		type = "CoopEcholocationPulse",
		sourceUserId = sourcePlayer.UserId,
		position = rootPosition,
		intensity = visualIntensity,
		radius = radius,
		movementState = noise.movementState,
		hasVoice = noise.hasVoice,
		voiceVolume = math.clamp(tonumber(noise.voiceVolume) or 0, 0, 1),
	}

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= sourcePlayer then
			pulseEvent:FireClient(otherPlayer, payload)
		end
	end
end

local function getSpawnCFrame()
	local spawnMarker = workspace:FindFirstChild("spawn")
	if spawnMarker and spawnMarker:IsA("BasePart") then
		return spawnMarker.CFrame + Vector3.new(0, 3, 0)
	end

	local spawnLocation = workspace:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		return spawnLocation.CFrame + Vector3.new(0, 3, 0)
	end

	return CFrame.new(0, 5, 0)
end

local function waitForCharacter(player, timeoutSeconds: number): Model?
	local deadline = os.clock() + timeoutSeconds
	while player.Parent and not player.Character and os.clock() < deadline do
		task.wait(0.1)
	end

	return player.Character
end

local function updatePlayerNoiseState(player, noise)
	local now = os.clock()
	local state = playerNoiseState[player]
	if not state then
		state = {
			lastRisk = 0,
			lastNoisyTime = -math.huge,
			movementState = "idle",
			hasVoice = false,
		}
		playerNoiseState[player] = state
	end

	state.lastRisk = noise.intensity
	state.movementState = noise.movementState
	state.hasVoice = noise.hasVoice
	state.lastReportTime = now

	if noise.intensity >= HEAR_THRESHOLD or noise.hasVoice or noise.movementState == "sprint" or noise.movementState == "jump" then
		state.lastNoisyTime = now
	end

	return state
end

local function isPlayerStillEnoughToSurvive(player)
	local state = playerNoiseState[player]
	if not state then
		return true
	end

	local silentFor = os.clock() - (state.lastNoisyTime or -math.huge)
	return silentFor >= STILL_SURVIVE_TIME
		and state.lastRisk < HEAR_THRESHOLD
		and not state.hasVoice
		and state.movementState ~= "sprint"
		and state.movementState ~= "jump"
end

local function resetPlayerAfterCatch(player)
	task.delay(1.4, function()
		if not player.Parent then return end
		player:LoadCharacter()
		local character = waitForCharacter(player, MONSTER_CONFIG.RESPAWN_CHARACTER_TIMEOUT)
		task.wait(0.15)
		if character and character.Parent then
			character:PivotTo(getSpawnCFrame())
		else
			warn("MonsterAI: player character did not respawn before timeout.")
		end
	end)
end

local function catchPlayer(player)
	if player:GetAttribute("Escaped") == true then
		return
	end

	local now = os.clock()
	if caughtCooldowns[player] and now - caughtCooldowns[player] < CATCH_COOLDOWN then
		return
	end

	caughtCooldowns[player] = now
	if monsterVisual then
		monsterVisual.playAttack()
	end
	caughtEvent:FireClient(player, {
		outcome = "death",
	})

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	lastNoisePosition = nil
	setMonsterDebugAttribute("NoiseLatched", false)
	resetPlayerAfterCatch(player)
end

local function updateDynamicSpeed(destination: Vector3, isChasing: boolean)
	if not isChasing then
		humanoid.WalkSpeed = PATROL_SPEED
		lastMoveDirection = nil
		straightRunTime = 0
		return
	end

	local direction = horizontalDirection(rootPart.Position, destination)
	if not direction then
		humanoid.WalkSpeed = math.min(humanoid.WalkSpeed, CORNER_SPEED)
		return
	end

	local now = os.clock()
	if lastMoveDirection then
		local directionDot = math.clamp(lastMoveDirection:Dot(direction), -1, 1)
		if directionDot < 0.94 then
			straightRunTime = 0
			cornerSlowUntil = now + 0.75
		else
			straightRunTime += 0.1
		end
	else
		straightRunTime = 0
	end
	lastMoveDirection = direction

	local speed = chaseBaseSpeed
	if straightRunTime > STRAIGHT_ACCEL_DELAY then
		local alpha = math.clamp((straightRunTime - STRAIGHT_ACCEL_DELAY) / STRAIGHT_ACCEL_TIME, 0, 1)
		speed = chaseBaseSpeed + ((chaseMaxSpeed - chaseBaseSpeed) * alpha)
	end

	if now < cornerSlowUntil then
		speed = math.min(speed, CORNER_SPEED)
	end

	humanoid.WalkSpeed = speed
end

local function setupPatrol()
	local map = getActiveMap()
	if not map then return end
	-- Prefer dedicated patrol point parts
	for _, child in pairs(map:GetDescendants()) do
		if child:IsA("BasePart") and (child.Name == "PatrolPoint" or child.Name == "Waypoint") then
			table.insert(patrolWaypoints, child.Position)
		end
	end
	-- Fall back to generic Parts in the map root
	if #patrolWaypoints == 0 then
		for _, child in pairs(map:GetChildren()) do
			if child:IsA("BasePart") and child.Name == "Part" and #patrolWaypoints < 10 then
				table.insert(patrolWaypoints, child.Position)
			end
		end
	end
	print(string.format("MonsterAI: %d patrol waypoints loaded", #patrolWaypoints))
end

local function computePath(destination: Vector3, agentRadius: number?, agentHeight: number?)
	local path = PathfindingService:CreatePath({
		AgentRadius = agentRadius or PATH_AGENT_RADIUS,
		AgentHeight = agentHeight or PATH_AGENT_HEIGHT,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local success = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)
	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints(), "Success"
	end
	return nil, if success then tostring(path.Status) else "ComputeFailed"
end

local function buildNoiseTargetCandidates(sourcePosition: Vector3): { Vector3 }
	local candidates = { sourcePosition }
	local sampleDirections = math.max(1, math.floor(NOISE_TARGET_SAMPLE_DIRECTIONS))
	local radii = table.clone(NOISE_TARGET_SAMPLE_RADII)
	local hasMaxRing = false

	for _, radius in ipairs(radii) do
		if typeof(radius) == "number" and math.abs(radius - APPROACH_TARGET_MAX_RING) < 0.01 then
			hasMaxRing = true
			break
		end
	end
	if not hasMaxRing and APPROACH_TARGET_MAX_RING > 0 then
		table.insert(radii, APPROACH_TARGET_MAX_RING)
	end

	for _, radius in ipairs(radii) do
		if typeof(radius) == "number" and radius > 0 then
			for index = 0, sampleDirections - 1 do
				local angle = (index / sampleDirections) * math.pi * 2
				table.insert(candidates, sourcePosition + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
			end
		end
	end

	return candidates
end

local function chooseReachableNoiseTarget(sourcePosition: Vector3)
	local candidates = buildNoiseTargetCandidates(sourcePosition)
	local bestDirectTarget = nil
	local bestDirectScore = math.huge
	local bestDirectStatus = "PathDirect"

	for index, candidate in ipairs(candidates) do
		if hasHullClearanceTo(candidate, DIRECT_MOVE_CLEARANCE_DISTANCE) then
			local score = getHorizontalDelta(candidate, sourcePosition).Magnitude
			if index == 1 then
				score -= 0.01
			end

			if score < bestDirectScore then
				bestDirectTarget = candidate
				bestDirectScore = score
				bestDirectStatus = if index == 1 then "PathDirect" else "PathClosestReachableDirect"
			end
		end
	end

	if bestDirectTarget then
		setMonsterDebugAttribute("NavProbeTarget", nil)
		setMonsterDebugAttribute("FullHullBlockedBy", "")
		setPathDebug(bestDirectStatus, bestDirectTarget, "")
		return {
			position = bestDirectTarget,
			waypoints = nil,
			status = bestDirectStatus,
		}
	end

	local bestNavTarget = nil
	local bestNavWaypoints = nil
	local bestNavScore = math.huge
	local bestNavStatus = "BlockedNoCandidate"
	local lastPathStatus = "NotComputed"
	local lastBlocker = ""

	for index, candidate in ipairs(candidates) do
		local waypoints, pathStatus = computePath(candidate, NAV_AGENT_RADIUS, NAV_AGENT_HEIGHT)
		lastPathStatus = pathStatus
		if waypoints and #waypoints >= 2 then
			local endPosition = waypoints[#waypoints].Position
			local score = getHorizontalDelta(endPosition, sourcePosition).Magnitude
			if index == 1 then
				score -= 0.01
			end

			if score < bestNavScore then
				bestNavTarget = candidate
				bestNavWaypoints = waypoints
				bestNavScore = score
				bestNavStatus = if index == 1 then "NavProbePathExact" else "NavProbeClosestReachable"
			end
		else
			local result = getHullClearanceBlock(candidate, DIRECT_MOVE_CLEARANCE_DISTANCE)
			lastBlocker = getBlockerName(result)
		end
	end

	if bestNavTarget then
		setMonsterDebugAttribute("NavProbeTarget", bestNavTarget)
		setMonsterDebugAttribute("FullHullBlockedBy", "")
		setPathDebug(bestNavStatus, bestNavTarget, "")
		return {
			position = bestNavTarget,
			waypoints = bestNavWaypoints,
			status = bestNavStatus,
		}
	end

	setMonsterDebugAttribute("NavProbeTarget", nil)
	setMonsterDebugAttribute("FullHullBlockedBy", lastBlocker)
	setPathDebug("BlockedNoCandidate", nil, if lastBlocker ~= "" then lastBlocker else lastPathStatus)
	return nil
end

-- Move toward a single position, polling every 0.1s.
-- Returns true when reached, false on timeout or interrupt.
local function moveTo(position, interruptFn, isChasing, facingPosition: Vector3?)
	setMonsterDebugAttribute("CurrentMoveTarget", position)
	setFacingModeDebug("Movement")
	setMonsterFacing(position)
	setMonsterLocomotion(if isChasing then "Run" else "Walk")
	local startTime = os.clock()
	local lastProgressTime = startTime
	local lastDistance = getHorizontalDelta(rootPart.Position, position).Magnitude
	repeat
		task.wait(0.05)
		setFacingModeDebug("Movement")
		setMonsterFacing(position)
		setMonsterLocomotion(if isChasing then "Run" else "Walk")
		updateDynamicSpeed(position, isChasing == true)
		if interruptFn and interruptFn() then
			stopMonsterMotion()
			return false
		end
		if not hasHullClearanceTo(position) then
			local safePosition = getSafeApproachBeforeBlock(position)
			if safePosition and getHorizontalDelta(rootPart.Position, safePosition).Magnitude > WAYPOINT_REACH_DIST then
				position = safePosition
				setMonsterDebugAttribute("CurrentMoveTarget", position)
				setPathDebug("FullHullSafeApproach", position, "HullClearance")
				continue
			end

			stopMonsterMotion()
			setMonsterLocomotion("Idle")
			setPathDebug("BlockedSegment", position, "HullClearance")
			return false
		end
		local distance = getHorizontalDelta(rootPart.Position, position).Magnitude
		if distance < WAYPOINT_REACH_DIST then
			stopMonsterMotion()
			if facingPosition then
				faceNoiseSourceAfterStop(facingPosition)
			end
			return true
		end
		local direction = getHorizontalDelta(rootPart.Position, position).Unit
		setFacingModeDebug("Movement")
		setMonsterFacingDirection(direction)
		setMonsterVelocity(Vector3.new(
			direction.X * humanoid.WalkSpeed,
			0,
			direction.Z * humanoid.WalkSpeed
		))
		humanoid:Move(direction, false)
		if distance < lastDistance - 0.25 then
			lastDistance = distance
			lastProgressTime = os.clock()
		elseif os.clock() - lastProgressTime > 1.4 then
			stopMonsterMotion()
			setMonsterLocomotion("Idle")
			setPathDebug("BlockedSegment", position, "Stuck")
			return false
		end
	until os.clock() - startTime > WAYPOINT_TIMEOUT
	stopMonsterMotion()
	setMonsterLocomotion("Idle")
	setPathDebug("BlockedSegment", position, "WaypointTimeout")
	return false
end

-- Walk the full computed path waypoint-by-waypoint instead of jumping to a
-- single mid-path node, which was causing the monster to run in one direction.
-- Checks interruptFn between each step so chase can preempt patrol immediately.
local function followPath(destination, interruptFn, isChasing, precomputedWaypoints, facingPosition: Vector3?)
	local waypoints = precomputedWaypoints
	if not waypoints then
		waypoints = computePath(destination)
	end
	if not waypoints or #waypoints < 2 then
		if hasHullClearanceTo(destination, DIRECT_MOVE_CLEARANCE_DISTANCE) then
			setPathDebug(if isChasing then "PathDirect" else "PatrolDirect", destination, "")
			return moveTo(destination, interruptFn, isChasing, facingPosition)
		end

		stopMonsterMotion()
		setMonsterLocomotion("Idle")
		setPathDebug(if isChasing then "BlockedNoCandidate" else "PatrolBlocked", destination, "NoPath")
		return false
	end
	for i = 2, #waypoints do
		if interruptFn and interruptFn() then
			stopMonsterMotion()
			return false
		end
		local wp = waypoints[i]
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		local nextWaypoint = waypoints[i + 1]
		local incoming = horizontalDirection(rootPart.Position, wp.Position)
		local outgoing = nextWaypoint and horizontalDirection(wp.Position, nextWaypoint.Position)
		if incoming and outgoing and incoming:Dot(outgoing) < 0.88 then
			cornerSlowUntil = os.clock() + 0.9
			straightRunTime = 0
		end

		if not hasHullClearanceTo(wp.Position) then
			local safePosition = getSafeApproachBeforeBlock(wp.Position)
			if safePosition and getHorizontalDelta(rootPart.Position, safePosition).Magnitude > WAYPOINT_REACH_DIST then
				setPathDebug("FullHullSafeApproach", safePosition, "HullClearance")
				return moveTo(safePosition, interruptFn, isChasing, facingPosition)
			else
				stopMonsterMotion()
				setMonsterLocomotion("Idle")
				setPathDebug("BlockedSegment", wp.Position, "HullClearance")
				return false
			end
		end

		local finalFacingPosition = if i == #waypoints then facingPosition else nil
		local reached = moveTo(wp.Position, interruptFn, isChasing, finalFacingPosition)
		if not reached then return false end
	end
	return true
end

pulseEvent.OnServerEvent:Connect(function(player, report)
	if player:GetAttribute("Escaped") == true then
		return
	end

	local now = os.clock()
	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
	local playerHumanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (playerRoot and playerRoot:IsA("BasePart") and playerHumanoid) then return end

	local noise = applyServerMovementFloor(normalizeNoiseReport(report), playerRoot, playerHumanoid)
	local reaction = getNoiseReaction(noise)
	local hearThreshold = reaction.hearThreshold or HEAR_THRESHOLD
	local isSignificantNoise = noise.intensity >= hearThreshold
		or noise.hasVoice
		or noise.movementState == "sprint"
		or noise.movementState == "jump"
		or noise.movementState == "decoy"

	if isSignificantNoise then
		if now - (lastSignificantNoiseAt[player] or 0) < SIGNIFICANT_NOISE_MIN_INTERVAL then
			return
		end
		lastSignificantNoiseAt[player] = now
	else
		if now - (lastNoiseReportAt[player] or 0) < IDLE_NOISE_MIN_INTERVAL then
			return
		end
		lastNoiseReportAt[player] = now
	end

	updatePlayerNoiseState(player, noise)

	broadcastCoopPulse(player, playerRoot.Position, noise)

	if noise.intensity < hearThreshold then return end

	local wasInvestigating = lastNoisePosition ~= nil and (now - lastNoiseTime < lastNoiseDecay)
	local reportedPosition = if typeof(report) == "table" then report.position else nil
	local noisePosition = chooseReportedNoisePosition(player, reportedPosition, playerRoot.Position, char)
	recordHeardNoise(noisePosition, noise, reaction, now, char)
	setChaseSpeeds(reaction, noise.intensity)
	if not wasInvestigating then
		telegraphNewChase(now)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerNoiseState[player] = nil
	caughtCooldowns[player] = nil
	lastNoiseReportAt[player] = nil
	lastSignificantNoiseAt[player] = nil
	lastAcceptedNoisePositions[player] = nil
end)

serverNoiseEvent.Event:Connect(function(report)
	local noise = normalizeNoiseReport(report)
	local reaction = getNoiseReaction(noise)
	local position = typeof(report) == "table" and report.position
	if typeof(position) ~= "Vector3" then return end

	local now = os.clock()
	local wasInvestigating = lastNoisePosition ~= nil and (now - lastNoiseTime < lastNoiseDecay)
	if typeof(report) == "table" and tonumber(report.decay) then
		reaction = table.clone(reaction)
		reaction.decay = tonumber(report.decay)
	end
	recordHeardNoise(position, noise, reaction, now, nil)
	setChaseSpeeds(reaction, noise.intensity)
	if not wasInvestigating then
		telegraphNewChase(now)
	end
end)

setupPatrol()

task.spawn(function()
	while true do
		if not (humanoid and humanoid.Parent and humanoid.Health > 0) then
			task.wait(1)
			continue
		end

		local isInvestigating = lastNoisePosition ~= nil and (os.clock() - lastNoiseTime < lastNoiseDecay)

		if isInvestigating then
			local noiseSource = lastNoisePosition

			if os.clock() < chaseRoarUntil then
				if noiseSource then
					setFacingModeDebug("NoiseSource")
					setMonsterFacing(noiseSource)
				end
				stopMonsterMotion()
				setMonsterLocomotion("Idle")
				task.wait(0.1)
				continue
			end

			if (rootPart.Position - noiseSource).Magnitude < WAYPOINT_REACH_DIST then
				lastNoisePosition = nil
				setMonsterDebugAttribute("NoiseLatched", false)
				setMonsterLocomotion("Idle")
				faceNoiseSourceAfterStop(noiseSource)
				if monsterVisual then monsterVisual.playLook() end
			else
				local reachableTarget = chooseReachableNoiseTarget(noiseSource)
				if not reachableTarget then
					stopMonsterMotion()
					setMonsterLocomotion("Idle")
					task.wait(REPATH_COOLDOWN)
					continue
				end

				local reached = followPath(reachableTarget.position, function()
					return os.clock() - lastNoiseTime >= lastNoiseDecay
						or lastNoisePosition ~= noiseSource
				end, true, reachableTarget.waypoints, noiseSource)
				if not reached then
					task.wait(REPATH_COOLDOWN)
				end
			end

			if not lastNoisePosition or os.clock() - lastNoiseTime >= lastNoiseDecay then
				if os.clock() - lastNoiseTime >= lastNoiseDecay then
					lastNoisePosition = nil
				end
				humanoid.WalkSpeed = PATROL_SPEED
				lastMoveDirection = nil
				straightRunTime = 0
				setMonsterDebugAttribute("NoiseLatched", false)
				setPathDebug("Idle", nil, "")
				setMonsterLocomotion("Idle")
			end
		else
			humanoid.WalkSpeed = PATROL_SPEED

			if #patrolWaypoints > 0 then
				local target = patrolWaypoints[currentWaypointIndex]
				local reached = followPath(target, function()
					return lastNoisePosition ~= nil and os.clock() - lastNoiseTime < lastNoiseDecay
				end, false)
				if not reached then
					task.wait(0.25)
				end
				currentWaypointIndex = (currentWaypointIndex % #patrolWaypoints) + 1
			else
				-- No waypoints: wander to a random nearby position using pathfinding
				local offset = Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
				local reached = followPath(rootPart.Position + offset, function()
					return lastNoisePosition ~= nil and os.clock() - lastNoiseTime < lastNoiseDecay
				end, false)
				if not reached then
					task.wait(0.25)
				end
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.12)
		if not (humanoid and humanoid.Parent and humanoid.Health > 0) then
			continue
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Escaped") == true then
				continue
			end

			local character = player.Character
			local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
			local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			if playerRoot and playerHumanoid and playerHumanoid.Health > 0 then
				local distance = (rootPart.Position - playerRoot.Position).Magnitude
				if distance <= TOUCH_ATTACK_RANGE then
					catchPlayer(player)
				elseif distance <= ATTACK_RANGE then
					if isPlayerStillEnoughToSurvive(player) then
						if lastNoisePosition and (lastNoisePosition - playerRoot.Position).Magnitude < 8 then
							lastNoisePosition = nil
						end
					else
						catchPlayer(player)
					end
				end
			end
		end
	end
end)

print("Monster AI initialized and listening for pulses")

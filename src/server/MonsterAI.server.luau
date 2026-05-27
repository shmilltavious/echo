local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MonsterVisualController = require(script.Parent.MonsterVisualController)
local MONSTER_CONFIG = Constants.MONSTER_AI
local REMOTE_LIMITS = Constants.REMOTE_LIMITS

local PATROL_SPEED = MONSTER_CONFIG.PATROL_SPEED
local CORNER_SPEED = MONSTER_CONFIG.CORNER_SPEED
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
local NOISE_REPORT_MIN_INTERVAL = REMOTE_LIMITS.NOISE_REPORT_MIN_INTERVAL
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

local function findMonsterModel(): Model?
	local found = workspace:FindFirstChild("Monster") or workspace:WaitForChild("Rig", 5)
	if found and found:IsA("Model") then
		return found
	end

	warn("MonsterAI disabled: expected Workspace.Monster or Workspace.Rig model.")
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

local monsterVisual = MonsterVisualController.start({
	driverRoot = rootPart,
	hideDriverModel = monsterModel,
	hiddenPrewarm = true,
})

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
local chaseRoarUntil = 0

local function telegraphNewChase(now: number)
	chaseRoarUntil = math.max(chaseRoarUntil, now + 0.85)
	if monsterVisual then
		monsterVisual.playRoar()
	end
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

local function computePath(destination)
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 6,
		AgentCanJump = false,
		WaypointSpacing = 4,
	})
	local success = pcall(function()
		path:ComputeAsync(rootPart.Position, destination)
	end)
	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	end
	return nil
end

-- Move toward a single position, polling every 0.1s.
-- Returns true when reached, false on timeout or interrupt.
local function moveTo(position, interruptFn, isChasing)
	if monsterVisual then
		monsterVisual.playRun()
	end
	humanoid:MoveTo(position)
	local startTime = os.clock()
	repeat
		task.wait(0.1)
		updateDynamicSpeed(position, isChasing == true)
		if interruptFn and interruptFn() then return false end
		if (rootPart.Position - position).Magnitude < WAYPOINT_REACH_DIST then return true end
	until os.clock() - startTime > WAYPOINT_TIMEOUT
	return false
end

-- Walk the full computed path waypoint-by-waypoint instead of jumping to a
-- single mid-path node, which was causing the monster to run in one direction.
-- Checks interruptFn between each step so chase can preempt patrol immediately.
local function followPath(destination, interruptFn, isChasing)
	local waypoints = computePath(destination)
	if not waypoints or #waypoints < 2 then
		moveTo(destination, interruptFn, isChasing)
		return
	end
	for i = 2, #waypoints do
		if interruptFn and interruptFn() then return end
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

		local reached = moveTo(wp.Position, interruptFn, isChasing)
		if not reached then return end
	end
end

pulseEvent.OnServerEvent:Connect(function(player, report)
	if player:GetAttribute("Escaped") == true then
		return
	end

	local now = os.clock()
	if now - (lastNoiseReportAt[player] or 0) < NOISE_REPORT_MIN_INTERVAL then
		return
	end
	lastNoiseReportAt[player] = now

	local char = player.Character
	local playerRoot = char and char:FindFirstChild("HumanoidRootPart")
	local playerHumanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not (playerRoot and playerRoot:IsA("BasePart") and playerHumanoid) then return end

	local noise = applyServerMovementFloor(normalizeNoiseReport(report), playerRoot, playerHumanoid)
	updatePlayerNoiseState(player, noise)

	broadcastCoopPulse(player, playerRoot.Position, noise)

	local reaction = getNoiseReaction(noise)
	local hearThreshold = reaction.hearThreshold or HEAR_THRESHOLD
	if noise.intensity < hearThreshold then return end

	local wasInvestigating = lastNoisePosition ~= nil and (now - lastNoiseTime < lastNoiseDecay)
	lastNoisePosition = playerRoot.Position
	lastNoiseTime = now
	lastNoiseDecay = reaction.decay or SENSE_DECAY_TIME
	setChaseSpeeds(reaction, noise.intensity)
	if not wasInvestigating then
		telegraphNewChase(now)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playerNoiseState[player] = nil
	caughtCooldowns[player] = nil
	lastNoiseReportAt[player] = nil
end)

serverNoiseEvent.Event:Connect(function(report)
	local noise = normalizeNoiseReport(report)
	local reaction = getNoiseReaction(noise)
	local position = typeof(report) == "table" and report.position
	if typeof(position) ~= "Vector3" then return end

	local now = os.clock()
	local wasInvestigating = lastNoisePosition ~= nil and (now - lastNoiseTime < lastNoiseDecay)
	lastNoisePosition = position
	lastNoiseTime = now
	lastNoiseDecay = tonumber(report.decay) or reaction.decay or SENSE_DECAY_TIME
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
			local target = lastNoisePosition

			if os.clock() < chaseRoarUntil then
				humanoid:MoveTo(rootPart.Position)
				task.wait(0.1)
				continue
			end

			if (rootPart.Position - target).Magnitude < WAYPOINT_REACH_DIST then
				lastNoisePosition = nil
				if monsterVisual then
					monsterVisual.playLook()
				end
			else
				followPath(target, function()
					-- Abort if scent decayed or a newer noise position arrived
					return os.clock() - lastNoiseTime >= lastNoiseDecay
						or lastNoisePosition ~= target
				end, true)
			end

			if not lastNoisePosition or os.clock() - lastNoiseTime >= lastNoiseDecay then
				humanoid.WalkSpeed = PATROL_SPEED
				lastMoveDirection = nil
				straightRunTime = 0
				if monsterVisual then
					monsterVisual.playIdle()
				end
			end
		else
			humanoid.WalkSpeed = PATROL_SPEED

			if #patrolWaypoints > 0 then
				local target = patrolWaypoints[currentWaypointIndex]
				followPath(target, function()
					return lastNoisePosition ~= nil and os.clock() - lastNoiseTime < lastNoiseDecay
				end, false)
				currentWaypointIndex = (currentWaypointIndex % #patrolWaypoints) + 1
			else
				-- No waypoints: wander to a random nearby position using pathfinding
				local offset = Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
				followPath(rootPart.Position + offset, function()
					return lastNoisePosition ~= nil and os.clock() - lastNoiseTime < lastNoiseDecay
				end, false)
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

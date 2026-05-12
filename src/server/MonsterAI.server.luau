local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PATROL_SPEED = 6.5
local CORNER_SPEED = 7.5
local STRAIGHT_ACCEL_DELAY = 3.25
local STRAIGHT_ACCEL_TIME = 1.25
local SENSE_DECAY_TIME = 5
local HEAR_THRESHOLD = 0.35
local WAYPOINT_REACH_DIST = 4
local WAYPOINT_TIMEOUT = 6
local ATTACK_RANGE = 5.5
local TOUCH_ATTACK_RANGE = 2.35
local STILL_SURVIVE_TIME = 1.35
local CATCH_COOLDOWN = 4
local NOISE_REACTIONS = {
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
}

local monsterModel = workspace:FindFirstChild("Monster") or workspace:WaitForChild("Rig")
local humanoid = monsterModel:WaitForChild("Humanoid")
local rootPart = monsterModel:WaitForChild("HumanoidRootPart")

rootPart:SetNetworkOwner(nil)

humanoid.AutoRotate = true
humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

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

local function normalizeNoiseReport(report)
	if typeof(report) == "number" then
		return {
			intensity = report,
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

	return {
		intensity = tonumber(report.intensity) or 0,
		visualIntensity = tonumber(report.visualIntensity) or tonumber(report.intensity) or 0,
		radius = tonumber(report.radius) or 0,
		movementState = tostring(report.movementState or "walk"),
		hasVoice = report.hasVoice == true,
		voiceVolume = tonumber(report.voiceVolume) or 0,
	}
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
		local character = player.Character or player.CharacterAdded:Wait()
		task.wait(0.15)
		if character and character.Parent then
			character:PivotTo(getSpawnCFrame())
		end
	end)
end

local function catchPlayer(player)
	local now = os.clock()
	if caughtCooldowns[player] and now - caughtCooldowns[player] < CATCH_COOLDOWN then
		return
	end

	caughtCooldowns[player] = now
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
	local map = workspace:FindFirstChild("Prototype_Map")
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
	local noise = normalizeNoiseReport(report)
	updatePlayerNoiseState(player, noise)

	local reaction = getNoiseReaction(noise)
	local hearThreshold = reaction.hearThreshold or HEAR_THRESHOLD
	if noise.intensity < hearThreshold then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	lastNoisePosition = char.HumanoidRootPart.Position
	lastNoiseTime = os.clock()
	lastNoiseDecay = reaction.decay or SENSE_DECAY_TIME
	setChaseSpeeds(reaction, noise.intensity)
end)

Players.PlayerRemoving:Connect(function(player)
	playerNoiseState[player] = nil
	caughtCooldowns[player] = nil
end)

serverNoiseEvent.Event:Connect(function(report)
	local noise = normalizeNoiseReport(report)
	local reaction = getNoiseReaction(noise)
	local position = typeof(report) == "table" and report.position
	if typeof(position) ~= "Vector3" then return end

	lastNoisePosition = position
	lastNoiseTime = os.clock()
	lastNoiseDecay = tonumber(report.decay) or reaction.decay or SENSE_DECAY_TIME
	setChaseSpeeds(reaction, noise.intensity)
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

			if (rootPart.Position - target).Magnitude < WAYPOINT_REACH_DIST then
				lastNoisePosition = nil
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

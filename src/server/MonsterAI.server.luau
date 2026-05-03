local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PATROL_SPEED = 8
local CHASE_SPEED = 18
local SENSE_DECAY_TIME = 5
local HEAR_THRESHOLD = 0.8
local WAYPOINT_REACH_DIST = 4
local WAYPOINT_TIMEOUT = 6

local monsterModel = workspace:WaitForChild("Rig")
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

local lastNoisePosition = nil
local lastNoiseTime = 0
local patrolWaypoints = {}
local currentWaypointIndex = 1

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
local function moveTo(position, interruptFn)
	humanoid:MoveTo(position)
	local startTime = os.clock()
	repeat
		task.wait(0.1)
		if interruptFn and interruptFn() then return false end
		if (rootPart.Position - position).Magnitude < WAYPOINT_REACH_DIST then return true end
	until os.clock() - startTime > WAYPOINT_TIMEOUT
	return false
end

-- Walk the full computed path waypoint-by-waypoint instead of jumping to a
-- single mid-path node, which was causing the monster to run in one direction.
-- Checks interruptFn between each step so chase can preempt patrol immediately.
local function followPath(destination, interruptFn)
	local waypoints = computePath(destination)
	if not waypoints or #waypoints < 2 then
		moveTo(destination, interruptFn)
		return
	end
	for i = 2, #waypoints do
		if interruptFn and interruptFn() then return end
		local wp = waypoints[i]
		if wp.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		local reached = moveTo(wp.Position, interruptFn)
		if not reached then return end
	end
end

pulseEvent.OnServerEvent:Connect(function(player, intensity)
	if intensity < HEAR_THRESHOLD then return end
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	lastNoisePosition = char.HumanoidRootPart.Position
	lastNoiseTime = os.clock()

	if intensity > 1.5 then
		humanoid.WalkSpeed = math.min(CHASE_SPEED + (intensity * 1.5), CHASE_SPEED * 2)
	elseif intensity > 0.5 then
		humanoid.WalkSpeed = 14
	else
		humanoid.WalkSpeed = PATROL_SPEED
	end
end)

setupPatrol()

task.spawn(function()
	while true do
		if not (humanoid and humanoid.Parent and humanoid.Health > 0) then
			task.wait(1)
			continue
		end

		local isInvestigating = lastNoisePosition ~= nil and (os.clock() - lastNoiseTime < SENSE_DECAY_TIME)

		if isInvestigating then
			local target = lastNoisePosition

			if (rootPart.Position - target).Magnitude < WAYPOINT_REACH_DIST then
				lastNoisePosition = nil
			else
				followPath(target, function()
					-- Abort if scent decayed or a newer noise position arrived
					return os.clock() - lastNoiseTime >= SENSE_DECAY_TIME
						or lastNoisePosition ~= target
				end)
			end

			if not lastNoisePosition or os.clock() - lastNoiseTime >= SENSE_DECAY_TIME then
				humanoid.WalkSpeed = math.max(PATROL_SPEED, humanoid.WalkSpeed - 2)
			end
		else
			humanoid.WalkSpeed = PATROL_SPEED

			if #patrolWaypoints > 0 then
				local target = patrolWaypoints[currentWaypointIndex]
				followPath(target, function()
					return lastNoisePosition ~= nil and os.clock() - lastNoiseTime < SENSE_DECAY_TIME
				end)
				currentWaypointIndex = (currentWaypointIndex % #patrolWaypoints) + 1
			else
				-- No waypoints: wander to a random nearby position using pathfinding
				local offset = Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
				followPath(rootPart.Position + offset, function()
					return lastNoisePosition ~= nil and os.clock() - lastNoiseTime < SENSE_DECAY_TIME
				end)
			end
		end
	end
end)

print("Monster AI initialized and listening for pulses")

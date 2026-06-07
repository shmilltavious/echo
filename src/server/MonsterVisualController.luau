local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MonsterGroundLock = require(script.Parent.MonsterGroundLock)

local MonsterVisualController = {}

local RIG_NAME = "rigging (1)"
local VISUAL_PART_NAME = "geometry_0"
local LOOP_FADE_TIME = 0.35
local ACTION_FADE_TIME = 0.25
local ATTACK_FADE_TIME = 0.12
local ONE_SHOT_EXIT_FADE_TIME = 0.3
local LOCOMOTION_INTERRUPT_FADE_TIME = 0.18
local EMERGENCY_FADE_TIME = 0.05
local MIN_ONE_SHOT_RESTART_SECONDS = 0.35
local ACTION_START_DOWNWARD_SUPPRESSION_SECONDS = 0.2
local HIDDEN_PREWARM_ACTIONS = { "Look", "Roar" }
local HIDDEN_PREWARM_SECONDS = 0.45
local VISUAL_YAW_OFFSET = math.rad(-90)
local FOLLOW_RESPONSIVENESS = 20
local TURN_RESPONSIVENESS = 10
local MAX_VISUAL_CORRECTION_PER_SECOND = 120
local MAX_VISUAL_FOLLOW_LAG = 0.25
local MOVE_START_SPEED = 0.8
local MOVE_STOP_SPEED = 0.35
local MOVEMENT_STATE_SETTLE_SECONDS = 0.12
local LARGE_DISPLACEMENT_SNAP_DISTANCE = 24
local FACING_SPEED_THRESHOLD = 0.2
local DRIVER_VELOCITY_FACING_THRESHOLD = 0.35
local OLD_VISUAL_YAW_OFFSET_DEGREES = 90
local CALIBRATED_VISUAL_YAW_OFFSET_DEGREES = -90
local DRIFT_COMPENSATION_RESPONSIVENESS = 34
local MAX_DRIFT_COMPENSATION = 5
local DRIFT_REEXPORT_WARN_THRESHOLD = 1.25
local RUN_SPEED_REFERENCE = 13
local WALK_SPEED_REFERENCE = 6.5
local PLAYBACK_SPEED_RESPONSIVENESS = 8
local ROOT_BONE_NAME_PRIORITY = {
	"root",
	"armature",
	"hips",
	"pelvis",
	"spine",
}

local ANIMATIONS = {
	Idle = {
		assetId = Constants.MONSTER_ANIMATIONS.Idle,
		looped = true,
		soundKey = "idle",
		priority = Enum.AnimationPriority.Movement,
	},
	Look = {
		assetId = Constants.MONSTER_ANIMATIONS.Look,
		looped = false,
		soundKey = "look",
		priority = Enum.AnimationPriority.Action,
	},
	Roar = {
		assetId = Constants.MONSTER_ANIMATIONS.Roar,
		looped = false,
		soundKey = "roar",
		priority = Enum.AnimationPriority.Action,
	},
	Run = {
		assetId = Constants.MONSTER_ANIMATIONS.Run,
		looped = true,
		soundKey = "run",
		priority = Enum.AnimationPriority.Movement,
	},
	Walk = {
		assetId = Constants.MONSTER_ANIMATIONS.Walk,
		looped = true,
		soundKey = "run",
		playbackSpeed = 0.55,
		priority = Enum.AnimationPriority.Movement,
	},
	Attack = {
		assetId = Constants.MONSTER_ANIMATIONS.Attack,
		looped = false,
		soundKey = "attack",
		priority = Enum.AnimationPriority.Action4,
	},
}

local SOUND_DEFAULTS = {
	idle = {
		looped = true,
		volume = 0.18,
		maxDistance = 55,
	},
	look = {
		looped = false,
		volume = 0.45,
		maxDistance = 75,
	},
	roar = {
		looped = false,
		volume = 0.95,
		maxDistance = 140,
	},
	run = {
		looped = true,
		volume = 0.42,
		maxDistance = 95,
	},
	attack = {
		looped = false,
		volume = 0.9,
		maxDistance = 100,
	},
}

local activeController = nil

local function getMonsterSounds()
	local sounds = Constants.SOUNDS.monster
	if typeof(sounds) == "table" then
		return sounds
	end

	return {}
end

local function getFlatForward(cframe: CFrame): Vector3
	local lookVector = cframe.LookVector
	local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end

	return flat.Unit
end

local function getFlatDirection(vector: Vector3, fallback: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.01 then
		return fallback
	end

	return flat.Unit
end

local function getPlanarPosition(position: Vector3): Vector3
	return Vector3.new(position.X, 0, position.Z)
end

local function getSmoothingAlpha(responsiveness: number, deltaTime: number): number
	return 1 - math.exp(-responsiveness * math.max(deltaTime, 0))
end

local function buildVisualCFrame(position: Vector3, forward: Vector3, yawOffset: number): CFrame
	local safeForward = getFlatDirection(forward, Vector3.new(0, 0, -1))
	return CFrame.lookAt(position, position + safeForward) * CFrame.Angles(0, yawOffset, 0)
end

local function getRigRenderedForward(cframe: CFrame, fallback: Vector3): Vector3
	return getFlatDirection(-cframe.RightVector, fallback)
end

local function getVisualParts(rig: Model): { BasePart }
	local parts = {}
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getRigBones(rig: Model): { Bone }
	local bones = {}
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("Bone") then
			table.insert(bones, descendant)
		end
	end

	return bones
end

local function getBoneNameScore(name: string): number
	local lowered = string.lower(name)
	for index, pattern in ipairs(ROOT_BONE_NAME_PRIORITY) do
		if lowered == pattern then
			return index
		end
	end
	for index, pattern in ipairs(ROOT_BONE_NAME_PRIORITY) do
		if string.find(lowered, pattern, 1, true) then
			return index + #ROOT_BONE_NAME_PRIORITY
		end
	end

	return math.huge
end

local function getDriftProbeBones(rig: Model): { Bone }
	local bones = getRigBones(rig)
	local bestBone: Bone? = nil
	local bestScore = math.huge
	local topLevelBones = {}

	for _, bone in ipairs(bones) do
		if not bone.Parent or not bone.Parent:IsA("Bone") then
			table.insert(topLevelBones, bone)
		end

		local score = getBoneNameScore(bone.Name)
		if score < bestScore then
			bestScore = score
			bestBone = bone
		end
	end

	if bestBone and bestScore < math.huge then
		return { bestBone }
	end
	if #topLevelBones > 0 then
		return topLevelBones
	end

	return {}
end

local function getVisualFootprintSize(rig: Model, visualPart: BasePart, hiddenDriverModel: Model?): Vector3
	local minPosition: Vector3? = nil
	local maxPosition: Vector3? = nil

	for _, part in ipairs(getVisualParts(rig)) do
		if part ~= visualPart and part.Name == "MonsterCollisionHull" then
			continue
		end
		if hiddenDriverModel and part:IsDescendantOf(hiddenDriverModel) then
			continue
		end

		local halfSize = part.Size * 0.5
		for _, x in ipairs({ -1, 1 }) do
			for _, y in ipairs({ -1, 1 }) do
				for _, z in ipairs({ -1, 1 }) do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(halfSize.X * x, halfSize.Y * y, halfSize.Z * z))
					minPosition = if minPosition
						then Vector3.new(
							math.min(minPosition.X, corner.X),
							math.min(minPosition.Y, corner.Y),
							math.min(minPosition.Z, corner.Z)
						)
						else corner
					maxPosition = if maxPosition
						then Vector3.new(
							math.max(maxPosition.X, corner.X),
							math.max(maxPosition.Y, corner.Y),
							math.max(maxPosition.Z, corner.Z)
						)
						else corner
				end
			end
		end
	end

	if minPosition and maxPosition then
		return maxPosition - minPosition
	end

	return visualPart.Size
end

local function hideDriverModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("MonsterDriverOriginalTransparency", descendant.Transparency)
			descendant:SetAttribute("MonsterDriverOriginalCastShadow", descendant.CastShadow)
			descendant.Transparency = 1
			descendant.CastShadow = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant:SetAttribute("MonsterDriverOriginalTransparency", descendant.Transparency)
			descendant.Transparency = 1
		end
	end
end

local function loadTracks(animator: Animator)
	local tracks = {}
	for name, animationInfo in pairs(ANIMATIONS) do
		local animation = Instance.new("Animation")
		animation.Name = "Monster" .. name .. "Animation"
		animation.AnimationId = animationInfo.assetId

		local track = animator:LoadAnimation(animation)
		track.Name = name
		track.Looped = animationInfo.looped
		track.Priority = animationInfo.priority or Enum.AnimationPriority.Movement
		tracks[name] = track
	end

	return tracks
end

local function createSound(parent: Instance, soundKey: string): Sound?
	local soundId = getMonsterSounds()[soundKey]
	if typeof(soundId) ~= "string" or soundId == "" then
		return nil
	end

	local defaults = SOUND_DEFAULTS[soundKey]
	local sound = Instance.new("Sound")
	sound.Name = "Monster" .. string.upper(string.sub(soundKey, 1, 1)) .. string.sub(soundKey, 2) .. "Sound"
	sound.SoundId = soundId
	sound.Volume = defaults.volume
	sound.Looped = defaults.looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = defaults.maxDistance
	sound.Parent = parent

	return sound
end

local function stopSound(sound: Sound?)
	if sound and sound.IsPlaying then
		sound:Stop()
	end
end

function MonsterVisualController.start(config)
	if activeController then
		if config and config.driverRoot then
			activeController.setDriver(config.driverRoot)
		end
		return activeController
	end

	config = config or {}

	local rig = config.rig
	if not rig then
		rig = workspace:WaitForChild(config.rigName or RIG_NAME, 10)
	end
	if not (rig and rig:IsA("Model")) then
		warn("MonsterVisualController disabled: expected Workspace." .. (config.rigName or RIG_NAME))
		return nil
	end

	local visualPart = rig:WaitForChild(config.visualPartName or VISUAL_PART_NAME, 10)
	local animationController = rig:WaitForChild("AnimationController", 10)
	if not (visualPart and visualPart:IsA("BasePart") and animationController and animationController:IsA("AnimationController")) then
		warn("MonsterVisualController disabled: animated rig is missing geometry_0 or AnimationController.")
		return nil
	end

	local animator = animationController:FindFirstChildOfClass("Animator") or animationController:WaitForChild("Animator", 5)
	if not (animator and animator:IsA("Animator")) then
		warn("MonsterVisualController disabled: AnimationController is missing Animator.")
		return nil
	end

	visualPart.Anchored = true
	visualPart.CanCollide = false
	visualPart.CanTouch = false
	visualPart.CanQuery = true
	local yawOffsetDegrees = visualPart:GetAttribute("MonsterVisualYawOffsetDegrees")
	if yawOffsetDegrees == nil
		or (typeof(yawOffsetDegrees) == "number" and math.abs(yawOffsetDegrees - OLD_VISUAL_YAW_OFFSET_DEGREES) < 0.01)
	then
		visualPart:SetAttribute("MonsterVisualYawOffsetDegrees", CALIBRATED_VISUAL_YAW_OFFSET_DEGREES)
	end
	if visualPart:GetAttribute("MonsterVisualDynamicPlaybackEnabled") == nil then
		visualPart:SetAttribute("MonsterVisualDynamicPlaybackEnabled", false)
	end

	local visualParts = getVisualParts(rig)
	local driftProbeBones = getDriftProbeBones(rig)
	local tracks = loadTracks(animator)
	local sounds = {}
	for _, animationInfo in pairs(ANIMATIONS) do
		if animationInfo.soundKey then
			sounds[animationInfo.soundKey] = createSound(visualPart, animationInfo.soundKey)
		end
	end

	local groundLock = MonsterGroundLock.start({
		rig = rig,
		visualPart = visualPart,
		contactBoneSuffixes = {
			"LeftFoot",
			"RightFoot",
			"LeftToeBase",
			"RightToeBase",
		},
		groundClearance = 0.05,
		raycastStartHeight = 0.5,
		raycastDown = 80,
		maxCorrectionPerSecond = 18,
		maxFloorRisePerFrame = 2,
	})
	local visualBoundsSize = getVisualFootprintSize(rig, visualPart, config.hideDriverModel)
	local hullSize = Constants.MONSTER_AI.COLLISION_HULL_SIZE or Vector3.new(11.8, 7, 11.8)
	print(string.format(
		"Monster visual footprint: bounds=%s hull=%s yawOffset=%.1f",
		tostring(visualBoundsSize),
		tostring(hullSize),
		visualPart:GetAttribute("MonsterVisualYawOffsetDegrees") or math.deg(VISUAL_YAW_OFFSET)
	))
	local footprintTolerance = 0.05
	if visualBoundsSize.X > hullSize.X + footprintTolerance or visualBoundsSize.Z > hullSize.Z + footprintTolerance then
		warn("MonsterVisualController: visual footprint exceeds MonsterCollisionHull footprint; wall clipping may still be visible.")
	end
	if #driftProbeBones == 0 then
		warn("MonsterVisualController: no root/top-level bones found; animation drift compensation will use anchor-only diagnostics.")
	else
		visualPart:SetAttribute("MonsterVisualDriftProbe", driftProbeBones[1].Name)
	end

	local controller = {
		rig = rig,
		visualPart = visualPart,
		tracks = tracks,
		driverRoot = config.driverRoot,
	}
	local currentTrack: AnimationTrack? = nil
	local currentActionName: string? = nil
	local currentOneShotName: string? = nil
	local currentOneShotStartedAt = 0
	local followConnection: RBXScriptConnection? = nil
	local destroyed = false
	local lastDriverPosition: Vector3? = nil
	local lastFacingForward = getFlatForward(visualPart.CFrame * CFrame.Angles(0, -VISUAL_YAW_OFFSET, 0))
	local hasFollowedDriver = false
	local isMoving = false
	local locomotionState = "Idle"
	local pendingMoving: boolean? = nil
	local pendingMovingSince = 0
	local lastKnownDriverSpeed = 0
	local authoritativeFacingDirection: Vector3? = nil
	local driftBaselineLocal: Vector3? = nil
	local driftCompensationWorld = Vector3.zero
	local lastDriftMagnitude = 0
	local maxDriftByAction = {}
	local warnedDriftByAction = {}
	local currentPlaybackSpeed = 1

	local function getVisualYawOffset(): number
		local degrees = visualPart:GetAttribute("MonsterVisualYawOffsetDegrees")
		if typeof(degrees) == "number" then
			return math.rad(degrees)
		end

		return VISUAL_YAW_OFFSET
	end

	local function setDebugAttribute(name: string, value)
		local attributeName = "MonsterVisual_" .. name
		visualPart:SetAttribute(attributeName, value)
		rig:SetAttribute(attributeName, value)

		local monsterContainer = workspace:FindFirstChild("Monster")
		if monsterContainer then
			monsterContainer:SetAttribute(attributeName, value)
		end
	end

	local function setForwardDebug(moveForward: Vector3, renderedCFrame: CFrame)
		local safeMoveForward = getFlatDirection(moveForward, lastFacingForward)
		local renderForward = getRigRenderedForward(renderedCFrame, safeMoveForward)
		setDebugAttribute("MoveForward", safeMoveForward)
		setDebugAttribute("RenderForward", renderForward)
		setDebugAttribute("ForwardDot", math.clamp(renderForward:Dot(safeMoveForward), -1, 1))
	end

	local function getTrackFadeTime(actionName: string): number
		if actionName == "Attack" then
			return ATTACK_FADE_TIME
		end

		local animationInfo = ANIMATIONS[actionName]
		if animationInfo and animationInfo.looped then
			return LOOP_FADE_TIME
		end

		return ACTION_FADE_TIME
	end

	local function getTrackPlaybackSpeed(actionName: string): number
		local animationInfo = ANIMATIONS[actionName]
		local baseSpeed = (animationInfo and animationInfo.playbackSpeed) or 1
		if visualPart:GetAttribute("MonsterVisualDynamicPlaybackEnabled") == false then
			return baseSpeed
		end

		if actionName == "Run" then
			return math.clamp(lastKnownDriverSpeed / RUN_SPEED_REFERENCE, 0.75, 1.35)
		elseif actionName == "Walk" then
			local speedScale = math.clamp(lastKnownDriverSpeed / WALK_SPEED_REFERENCE, 0.75, 1.25)
			return math.clamp(baseSpeed * speedScale, 0.45, 0.75)
		end

		return baseSpeed
	end

	local function getProbeCenterLocal(): Vector3?
		if #driftProbeBones == 0 then
			return Vector3.zero
		end

		local sum = Vector3.zero
		local count = 0
		for _, bone in ipairs(driftProbeBones) do
			if bone.Parent then
				sum += visualPart.CFrame:PointToObjectSpace(bone.WorldCFrame.Position)
				count += 1
			end
		end

		if count == 0 then
			return nil
		end

		return sum / count
	end

	local function updateDriftCompensation(baseCFrame: CFrame, deltaTime: number)
		local compensationEnabled = visualPart:GetAttribute("MonsterVisualDriftCompensationEnabled")
		if compensationEnabled == false or #driftProbeBones == 0 then
			driftCompensationWorld = Vector3.zero
			lastDriftMagnitude = 0
			setDebugAttribute("DriftMagnitude", 0)
			setDebugAttribute("DriftCompensationOffset", Vector3.zero)
			return baseCFrame
		end

		local centerLocal = getProbeCenterLocal()
		if not centerLocal then
			return baseCFrame + driftCompensationWorld
		end
		if not driftBaselineLocal then
			driftBaselineLocal = centerLocal
		end

		local localDrift = Vector3.new(
			centerLocal.X - driftBaselineLocal.X,
			0,
			centerLocal.Z - driftBaselineLocal.Z
		)
		local rawMagnitude = localDrift.Magnitude
		lastDriftMagnitude = rawMagnitude

		local targetCompensation = -baseCFrame:VectorToWorldSpace(localDrift)
		targetCompensation = Vector3.new(targetCompensation.X, 0, targetCompensation.Z)
		if targetCompensation.Magnitude > MAX_DRIFT_COMPENSATION then
			targetCompensation = targetCompensation.Unit * MAX_DRIFT_COMPENSATION
		end

		local alpha = getSmoothingAlpha(DRIFT_COMPENSATION_RESPONSIVENESS, deltaTime)
		driftCompensationWorld = driftCompensationWorld:Lerp(targetCompensation, alpha)
		driftCompensationWorld = Vector3.new(driftCompensationWorld.X, 0, driftCompensationWorld.Z)

		local actionName = currentActionName or "None"
		maxDriftByAction[actionName] = math.max(maxDriftByAction[actionName] or 0, rawMagnitude)
		setDebugAttribute("DriftMagnitude", rawMagnitude)
		setDebugAttribute("DriftCompensationOffset", driftCompensationWorld)
		setDebugAttribute("MaxDriftMagnitude", maxDriftByAction[actionName] or rawMagnitude)

		if rawMagnitude >= DRIFT_REEXPORT_WARN_THRESHOLD and not warnedDriftByAction[actionName] then
			warn(string.format(
				"MonsterVisualController: %s animation has %.2f studs of planar root drift after code compensation; re-export in-place if visible sliding remains.",
				actionName,
				rawMagnitude
			))
			warnedDriftByAction[actionName] = true
		end

		return baseCFrame + driftCompensationWorld
	end

	local function resetDriftBaseline()
		driftBaselineLocal = getProbeCenterLocal()
		driftCompensationWorld = Vector3.zero
		lastDriftMagnitude = 0
		setDebugAttribute("DriftMagnitude", 0)
		setDebugAttribute("DriftCompensationOffset", Vector3.zero)
	end

	local function stopLoopSoundsExcept(soundKey: string?)
		for key, sound in pairs(sounds) do
			if key ~= soundKey and SOUND_DEFAULTS[key] and SOUND_DEFAULTS[key].looped then
				stopSound(sound)
			end
		end
	end

	local function playSoundForAction(actionName: string)
		local animationInfo = ANIMATIONS[actionName]
		if not animationInfo then
			return
		end

		local soundKey = animationInfo.soundKey
		if not soundKey then
			return
		end

		stopLoopSoundsExcept(soundKey)
		local sound = sounds[soundKey]
		if not sound then
			return
		end

		if SOUND_DEFAULTS[soundKey] and SOUND_DEFAULTS[soundKey].looped then
			if not sound.IsPlaying then
				sound:Play()
			end
		else
			sound:Play()
		end
	end

	local function stopCurrent(fadeTime: number?)
		if currentTrack and currentTrack.IsPlaying then
			currentTrack:Stop(fadeTime or EMERGENCY_FADE_TIME)
		end
	end

	local playAction

	local function getDesiredLoopAction(): string
		return locomotionState
	end

	local function playDesiredLoop(fadeTimeOverride: number?)
		if currentOneShotName then
			return
		end

		playAction(getDesiredLoopAction(), false, fadeTimeOverride)
	end

	local function interruptOneShotForLocomotion(fadeTime: number?): boolean
		if not currentOneShotName or currentOneShotName == "Attack" then
			return false
		end

		local interruptedOneShot = currentOneShotName
		stopCurrent(fadeTime or LOCOMOTION_INTERRUPT_FADE_TIME)
		currentTrack = nil
		currentActionName = nil
		currentOneShotName = nil
		currentOneShotStartedAt = 0
		resetDriftBaseline()
		setDebugAttribute("InterruptedOneShot", interruptedOneShot)
		playDesiredLoop(fadeTime or LOCOMOTION_INTERRUPT_FADE_TIME)
		return true
	end

	function playAction(actionName: string, forceReplay: boolean?, fadeTimeOverride: number?)
		local track = tracks[actionName]
		if not track then
			return
		end

		if currentActionName == actionName and currentTrack and currentTrack.IsPlaying and not forceReplay then
			return
		end
		if currentOneShotName == actionName and currentTrack and currentTrack.IsPlaying and forceReplay then
			if os.clock() - currentOneShotStartedAt < MIN_ONE_SHOT_RESTART_SECONDS then
				return
			end
		end

		local animationInfo = ANIMATIONS[actionName]
		local fadeTime = fadeTimeOverride or getTrackFadeTime(actionName)
		local playbackSpeed = getTrackPlaybackSpeed(actionName)
		if currentTrack and currentTrack.IsPlaying and animationInfo and currentActionName then
			local currentInfo = ANIMATIONS[currentActionName]
			if currentInfo
				and currentInfo.looped
				and animationInfo.looped
				and currentInfo.assetId == animationInfo.assetId
				and not forceReplay
			then
				currentActionName = actionName
				currentOneShotName = nil
				currentPlaybackSpeed = playbackSpeed
				currentTrack:AdjustSpeed(playbackSpeed)
				playSoundForAction(actionName)
				setDebugAttribute("CurrentAnimation", actionName)
				setDebugAttribute("TransitionTarget", actionName)
				setDebugAttribute("ActiveLocomotionState", locomotionState)
				return
			end
		end

		stopCurrent(fadeTime)
		local previousActionName = currentActionName
		local previousWasLoop = previousActionName and ANIMATIONS[previousActionName] and ANIMATIONS[previousActionName].looped
		currentTrack = track
		currentActionName = actionName
		currentOneShotName = if track.Looped then nil else actionName
		if currentOneShotName then
			currentOneShotStartedAt = os.clock()
		end
		if previousWasLoop ~= animationInfo.looped then
			resetDriftBaseline()
		end

		if actionName ~= "Idle" then
			groundLock.suppressDownwardCorrection(ACTION_START_DOWNWARD_SUPPRESSION_SECONDS)
		end
		currentPlaybackSpeed = playbackSpeed
		track:Play(fadeTime, 1, playbackSpeed)
		playSoundForAction(actionName)
		setDebugAttribute("CurrentAnimation", actionName)
		setDebugAttribute("TransitionTarget", actionName)
		setDebugAttribute("ActiveLocomotionState", locomotionState)
	end

	local function updateMovementState(speed: number, now: number)
		local targetMoving = isMoving
		if isMoving then
			if speed <= MOVE_STOP_SPEED then
				targetMoving = false
			end
		elseif speed >= MOVE_START_SPEED then
			targetMoving = true
		end

		if targetMoving == isMoving then
			pendingMoving = nil
			return
		end

		if pendingMoving ~= targetMoving then
			pendingMoving = targetMoving
			pendingMovingSince = now
			return
		end

		if now - pendingMovingSince < MOVEMENT_STATE_SETTLE_SECONDS then
			return
		end

		isMoving = targetMoving
		locomotionState = if isMoving then "Run" else "Idle"
		pendingMoving = nil
		playDesiredLoop()
	end

	local function updateFollow(deltaTime: number)
		local driverRoot = controller.driverRoot
		if not (driverRoot and driverRoot.Parent and visualPart.Parent) then
			return
		end

		local currentPosition = visualPart.Position - driftCompensationWorld
		local driverPosition = driverRoot.Position
		local driverDelta = Vector3.zero
		local driverSpeed = Vector3.new(driverRoot.AssemblyLinearVelocity.X, 0, driverRoot.AssemblyLinearVelocity.Z).Magnitude
		if lastDriverPosition then
			driverDelta = Vector3.new(driverPosition.X - lastDriverPosition.X, 0, driverPosition.Z - lastDriverPosition.Z)
			if deltaTime > 0 then
				driverSpeed = driverDelta.Magnitude / deltaTime
			end
		end
		lastKnownDriverSpeed = driverSpeed
		lastDriverPosition = driverPosition

		local desiredForward = lastFacingForward
		if authoritativeFacingDirection then
			desiredForward = authoritativeFacingDirection
		elseif driverDelta.Magnitude >= FACING_SPEED_THRESHOLD then
			desiredForward = driverDelta.Unit
		else
			local velocity = Vector3.new(driverRoot.AssemblyLinearVelocity.X, 0, driverRoot.AssemblyLinearVelocity.Z)
			if velocity.Magnitude >= DRIVER_VELOCITY_FACING_THRESHOLD then
				desiredForward = velocity.Unit
			elseif not hasFollowedDriver then
				desiredForward = getFlatForward(driverRoot.CFrame)
			end
		end

		local currentPlanarPosition = getPlanarPosition(currentPosition)
		local driverPlanarPosition = getPlanarPosition(driverPosition)
		local planarDistance = (currentPlanarPosition - driverPlanarPosition).Magnitude
		local followPosition
		if not hasFollowedDriver or planarDistance >= LARGE_DISPLACEMENT_SNAP_DISTANCE then
			followPosition = Vector3.new(driverPosition.X, currentPosition.Y, driverPosition.Z)
			hasFollowedDriver = true
		else
			local followAlpha = getSmoothingAlpha(FOLLOW_RESPONSIVENESS, deltaTime)
			local planarCorrection = Vector3.new(
				(driverPosition.X - currentPosition.X) * followAlpha,
				0,
				(driverPosition.Z - currentPosition.Z) * followAlpha
			)
			local maxCorrection = MAX_VISUAL_CORRECTION_PER_SECOND * deltaTime
			if planarCorrection.Magnitude > maxCorrection and maxCorrection > 0 then
				planarCorrection = planarCorrection.Unit * maxCorrection
			end
			followPosition = Vector3.new(
				currentPosition.X + planarCorrection.X,
				currentPosition.Y,
				currentPosition.Z + planarCorrection.Z
			)
			local remainingOffset = Vector3.new(driverPosition.X - followPosition.X, 0, driverPosition.Z - followPosition.Z)
			if remainingOffset.Magnitude > MAX_VISUAL_FOLLOW_LAG then
				local clampedPlanarPosition = Vector3.new(driverPosition.X, 0, driverPosition.Z)
					- (remainingOffset.Unit * MAX_VISUAL_FOLLOW_LAG)
				followPosition = Vector3.new(clampedPlanarPosition.X, followPosition.Y, clampedPlanarPosition.Z)
			end
		end

		local turnAlpha = getSmoothingAlpha(TURN_RESPONSIVENESS, deltaTime)
		if lastFacingForward:Dot(desiredForward) < -0.98 then
			lastFacingForward = desiredForward
		else
			lastFacingForward = getFlatDirection(lastFacingForward:Lerp(desiredForward, turnAlpha), desiredForward)
		end

		local baseCFrame = buildVisualCFrame(followPosition, lastFacingForward, getVisualYawOffset())
		visualPart.CFrame = baseCFrame + driftCompensationWorld
		visualPart.CFrame = updateDriftCompensation(baseCFrame, deltaTime)
		setForwardDebug(lastFacingForward, visualPart.CFrame)
		groundLock.step(deltaTime)
		updateMovementState(lastKnownDriverSpeed, os.clock())
		if currentTrack and currentTrack.IsPlaying and currentActionName then
			local animationInfo = ANIMATIONS[currentActionName]
			if animationInfo and animationInfo.looped then
				local targetSpeed = getTrackPlaybackSpeed(currentActionName)
				local speedAlpha = getSmoothingAlpha(PLAYBACK_SPEED_RESPONSIVENESS, deltaTime)
				currentPlaybackSpeed += (targetSpeed - currentPlaybackSpeed) * speedAlpha
				currentTrack:AdjustSpeed(currentPlaybackSpeed)
			end
		end
	end

	function controller.setDriver(driverRoot: BasePart?)
		controller.driverRoot = driverRoot
		lastDriverPosition = driverRoot and driverRoot.Position or nil
		hasFollowedDriver = false
		pendingMoving = nil
		lastKnownDriverSpeed = 0
		driftCompensationWorld = Vector3.zero
		if driverRoot then
			lastFacingForward = getFlatForward(driverRoot.CFrame)
		end
	end

	function controller.setFacingDirection(direction: Vector3?)
		if typeof(direction) ~= "Vector3" then
			authoritativeFacingDirection = nil
			return
		end

		authoritativeFacingDirection = getFlatDirection(direction, lastFacingForward)
	end

	function controller.setLocomotionState(state: string)
		if state ~= "Idle" and state ~= "Walk" and state ~= "Run" then
			return
		end

		locomotionState = state
		isMoving = state ~= "Idle"
		pendingMoving = nil
		setDebugAttribute("ActiveLocomotionState", locomotionState)
		if isMoving and interruptOneShotForLocomotion(LOCOMOTION_INTERRUPT_FADE_TIME) then
			return
		end

		playDesiredLoop()
	end

	function controller.playIdle()
		currentOneShotName = nil
		controller.setLocomotionState("Idle")
	end

	function controller.playLook()
		playAction("Look", true)
	end

	function controller.playRoar()
		playAction("Roar", true)
	end

	function controller.playRun()
		controller.setLocomotionState("Run")
	end

	function controller.playAttack()
		playAction("Attack", true)
	end

	function controller.playWalk()
		controller.setLocomotionState("Walk")
	end

	function controller.getAnimationDiagnostics()
		return {
			currentAnimation = currentActionName,
			currentOneShot = currentOneShotName,
			locomotionState = locomotionState,
			driftMagnitude = lastDriftMagnitude,
			driftCompensationOffset = driftCompensationWorld,
			maxDriftByAction = table.clone(maxDriftByAction),
			driftProbe = if #driftProbeBones > 0 then driftProbeBones[1].Name else "",
			forwardDot = visualPart:GetAttribute("MonsterVisual_ForwardDot"),
			moveForward = visualPart:GetAttribute("MonsterVisual_MoveForward"),
			renderForward = visualPart:GetAttribute("MonsterVisual_RenderForward"),
		}
	end

	function controller.resetAnimationDiagnostics(actionName: string?)
		if typeof(actionName) == "string" then
			maxDriftByAction[actionName] = 0
			warnedDriftByAction[actionName] = nil
		else
			table.clear(maxDriftByAction)
			table.clear(warnedDriftByAction)
		end
		lastDriftMagnitude = 0
		setDebugAttribute("DriftMagnitude", 0)
		setDebugAttribute("MaxDriftMagnitude", 0)
	end

	function controller.stop()
		if destroyed then
			return
		end
		destroyed = true
		if followConnection then
			followConnection:Disconnect()
			followConnection = nil
		end
		if groundLock and groundLock.stop then
			groundLock.stop()
		end
		for _, sound in pairs(sounds) do
			stopSound(sound)
		end
		stopCurrent(0)
		if activeController == controller then
			activeController = nil
		end
	end

	for actionName, track in pairs(tracks) do
		if not track.Looped then
			track.Stopped:Connect(function()
				if currentOneShotName == actionName then
					currentOneShotName = nil
					currentActionName = nil
					currentTrack = nil
					playDesiredLoop(ONE_SHOT_EXIT_FADE_TIME)
				end
			end)
		end
	end

	if config.hideDriverModel and config.hideDriverModel:IsA("Model") then
		hideDriverModel(config.hideDriverModel)
	end

	activeController = controller
	driftBaselineLocal = getProbeCenterLocal()
	setDebugAttribute("DriftProbe", if #driftProbeBones > 0 then driftProbeBones[1].Name else "")
	setDebugAttribute("ActiveLocomotionState", locomotionState)
	controller.playIdle()

	task.spawn(function()
		if config.hiddenPrewarm == false then
			return
		end

		local cachedTransparency = {}
		for _, part in ipairs(visualParts) do
			cachedTransparency[part] = part.Transparency
			part.Transparency = 1
		end

		for _, actionName in ipairs(HIDDEN_PREWARM_ACTIONS) do
			playAction(actionName, true)
			task.wait(HIDDEN_PREWARM_SECONDS)
			local track = tracks[actionName]
			if track and track.IsPlaying then
				track:Stop(0)
			end
		end

		for part, transparency in pairs(cachedTransparency) do
			if part.Parent then
				part.Transparency = transparency
			end
		end
		controller.playIdle()
	end)

	followConnection = RunService.Heartbeat:Connect(updateFollow)
	return controller
end

return MonsterVisualController

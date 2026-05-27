local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MonsterGroundLock = require(script.Parent.MonsterGroundLock)

local MonsterVisualController = {}

local RIG_NAME = "rigging (1)"
local VISUAL_PART_NAME = "geometry_0"
local FADE_TIME = 0.15
local ACTION_START_DOWNWARD_SUPPRESSION_SECONDS = 0.2
local HIDDEN_PREWARM_ACTIONS = { "Look", "Roar" }
local HIDDEN_PREWARM_SECONDS = 0.45
local FOLLOW_DEADZONE = 0.05
local DRIVER_MOVING_THRESHOLD = 0.18

local ANIMATIONS = {
	Idle = {
		assetId = "rbxassetid://93982960068097",
		looped = true,
		soundKey = "idle",
	},
	Look = {
		assetId = "rbxassetid://106914673591637",
		looped = false,
		soundKey = "look",
	},
	Roar = {
		assetId = "rbxassetid://110729878275185",
		looped = false,
		soundKey = "roar",
	},
	Run = {
		assetId = "rbxassetid://117522782092613",
		looped = true,
		soundKey = "run",
	},
	Attack = {
		assetId = "rbxassetid://74427646472939",
		looped = false,
		soundKey = "attack",
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

local function getVisualParts(rig: Model): { BasePart }
	local parts = {}
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
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

	local rig = workspace:WaitForChild(config.rigName or RIG_NAME, 10)
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

	local visualParts = getVisualParts(rig)
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

	local controller = {
		rig = rig,
		visualPart = visualPart,
		tracks = tracks,
		driverRoot = config.driverRoot,
	}
	local currentTrack: AnimationTrack? = nil
	local currentActionName: string? = nil
	local currentOneShotName: string? = nil
	local followConnection: RBXScriptConnection? = nil
	local destroyed = false
	local lastDriverPosition: Vector3? = nil

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
			currentTrack:Stop(fadeTime or FADE_TIME)
		end
	end

	local function playAction(actionName: string, forceReplay: boolean?)
		local track = tracks[actionName]
		if not track then
			return
		end

		if currentActionName == actionName and track.IsPlaying and not forceReplay then
			return
		end

		stopCurrent(FADE_TIME)
		currentTrack = track
		currentActionName = actionName
		currentOneShotName = if track.Looped then nil else actionName

		if actionName ~= "Idle" then
			groundLock.suppressDownwardCorrection(ACTION_START_DOWNWARD_SUPPRESSION_SECONDS)
		end
		track:Play(FADE_TIME)
		playSoundForAction(actionName)
	end

	local function updateFollow()
		local driverRoot = controller.driverRoot
		if not (driverRoot and driverRoot.Parent and visualPart.Parent) then
			return
		end

		local currentPosition = visualPart.Position
		local driverPosition = driverRoot.Position
		local followPosition = Vector3.new(driverPosition.X, currentPosition.Y, driverPosition.Z)
		local forward = getFlatForward(driverRoot.CFrame)
		local nextCFrame = CFrame.lookAt(followPosition, followPosition + forward)

		if (Vector3.new(currentPosition.X, 0, currentPosition.Z) - Vector3.new(driverPosition.X, 0, driverPosition.Z)).Magnitude > FOLLOW_DEADZONE then
			visualPart.CFrame = nextCFrame
		else
			visualPart.CFrame = CFrame.lookAt(currentPosition, currentPosition + forward)
		end

		local driverMoved = false
		if lastDriverPosition then
			local delta = Vector3.new(driverPosition.X - lastDriverPosition.X, 0, driverPosition.Z - lastDriverPosition.Z).Magnitude
			driverMoved = delta > DRIVER_MOVING_THRESHOLD
		end
		lastDriverPosition = driverPosition

		if not currentOneShotName then
			if driverMoved then
				playAction("Run")
			else
				playAction("Idle")
			end
		end
	end

	function controller.setDriver(driverRoot: BasePart?)
		controller.driverRoot = driverRoot
		lastDriverPosition = driverRoot and driverRoot.Position or nil
	end

	function controller.playIdle()
		currentOneShotName = nil
		playAction("Idle")
	end

	function controller.playLook()
		playAction("Look", true)
	end

	function controller.playRoar()
		playAction("Roar", true)
	end

	function controller.playRun()
		if not currentOneShotName then
			playAction("Run")
		end
	end

	function controller.playAttack()
		playAction("Attack", true)
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
					controller.playIdle()
				end
			end)
		end
	end

	if config.hideDriverModel and config.hideDriverModel:IsA("Model") then
		hideDriverModel(config.hideDriverModel)
	end

	activeController = controller
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

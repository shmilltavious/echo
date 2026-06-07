-- Client-side input handler for movement state, microphone volume, and noise events
local InputHandler = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VoiceChatService = game:GetService("VoiceChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(game.ReplicatedStorage.Shared.Constants)

local player = Players.LocalPlayer
local movementSpeed = 0
local micVolume = 0
local audioAnalyzer = nil
local voiceEnabled = false
local voiceInputAvailable = false
local rawMicLevel = 0
local silentVoiceWarningShown = false
local voiceSilenceStartedAt = nil
local activePulseSphere = nil
local initialized = false
local isCrouching = false
local isSprinting = false
local jumpNoiseUntil = 0
local lastReportTime = 0
local REPORT_RATE = 0.1
local NOISE_THRESHOLD = 0.025
local VOICE_ACTIVITY_THRESHOLD = 0.008
local MIC_GAIN = 42
local MIC_NOISE_FLOOR = 0.0002
local MIC_RESPONSE_POWER = 0.72
local MOVEMENT_VISUAL_INTENSITY_SCALE = 0.3
local MOVEMENT_VISUAL_RADIUS_SCALE = 0.3
local DEFAULT_WALK_SPEED = 12

local currentNoise = {
	intensity = 0,
	radius = 0,
	monsterRisk = 0,
	movementState = "idle",
	hasVoice = false,
	voiceVolume = 0,
}

local function setSilentNoise()
	movementSpeed = 0
	micVolume = 0
	currentNoise = {
		intensity = 0,
		radius = 0,
		monsterRisk = 0,
		movementState = "idle",
		hasVoice = false,
		voiceVolume = 0,
	}
end

function InputHandler.getMovementSpeed(): number
	return movementSpeed
end

function InputHandler.getMicVolume(): number
	return micVolume
end

function InputHandler.getNoiseInfo()
	return currentNoise
end

function InputHandler.getVoiceDiagnostics()
	return {
		voiceEnabled = voiceEnabled,
		voiceInputAvailable = voiceInputAvailable,
		rawMicLevel = rawMicLevel,
		micVolume = micVolume,
		hasVoice = currentNoise.hasVoice,
		monsterRisk = currentNoise.monsterRisk,
	}
end

local function updateNoiseDebugAttributes()
	player:SetAttribute("EcholocationVoiceEnabled", voiceEnabled)
	player:SetAttribute("EcholocationVoiceInputAvailable", voiceInputAvailable)
	player:SetAttribute("EcholocationRawMicLevel", rawMicLevel)
	player:SetAttribute("EcholocationMicVolume", micVolume)
	player:SetAttribute("EcholocationHasVoice", currentNoise.hasVoice)
	player:SetAttribute("EcholocationMonsterRisk", currentNoise.monsterRisk)
	player:SetAttribute("EcholocationMovementState", currentNoise.movementState)
end

local function setHumanoidSpeed(humanoid: Humanoid)
	if isCrouching then
		humanoid.WalkSpeed = Constants.MOVEMENT_NOISE.crouch.walkSpeed
	elseif isSprinting then
		humanoid.WalkSpeed = Constants.MOVEMENT_NOISE.sprint.walkSpeed
	else
		humanoid.WalkSpeed = Constants.MOVEMENT_NOISE.walk.walkSpeed or DEFAULT_WALK_SPEED
	end
end

local function getMovementState(humanoid: Humanoid?): string
	if not humanoid or movementSpeed < 0.1 then
		return "idle"
	end

	if os.clock() < jumpNoiseUntil then
		return "jump"
	end

	if isCrouching then
		return "crouch"
	end

	if isSprinting then
		return "sprint"
	end

	return "walk"
end

local function calculateNoise(humanoid: Humanoid?)
	local movementState = getMovementState(humanoid)
	local movementTier = Constants.MOVEMENT_NOISE[movementState] or Constants.MOVEMENT_NOISE.idle
	local movementVisualIntensity = movementTier.intensity * MOVEMENT_VISUAL_INTENSITY_SCALE
	local movementVisualRadius = movementTier.radius * MOVEMENT_VISUAL_RADIUS_SCALE
	local voiceIntensity = micVolume * Constants.VOICE_NOISE.intensityMultiplier
	local voiceRadius = micVolume * Constants.VOICE_NOISE.radiusMultiplier
	local voiceRisk = voiceIntensity * Constants.VOICE_NOISE.monsterRiskMultiplier
	local hasVoice = micVolume > VOICE_ACTIVITY_THRESHOLD

	currentNoise = {
		intensity = math.clamp(movementVisualIntensity + voiceIntensity, 0, 5),
		radius = math.clamp(movementVisualRadius + voiceRadius, 0, Constants.SPHERE_MAX_RADIUS),
		monsterRisk = math.clamp(movementTier.monsterRisk + voiceRisk, 0, 6),
		movementState = movementState,
		hasVoice = hasVoice,
		voiceVolume = micVolume,
	}
end

local function updatePulseSphere(rootPart: BasePart)
	if activePulseSphere then
		activePulseSphere:Destroy()
		activePulseSphere = nil
	end
end

local function calculateMicVolume(rawLevel: number): number
	local adjustedLevel = math.max(rawLevel - MIC_NOISE_FLOOR, 0) * MIC_GAIN
	if adjustedLevel <= 0 then
		return 0
	end

	return math.clamp(adjustedLevel ^ MIC_RESPONSE_POWER, 0, 1)
end

local function setupVoiceInput()
	local success, isVoiceEnabled = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)

	if not (success and isVoiceEnabled) then
		voiceEnabled = false
		voiceInputAvailable = false
		warn("Spatial Voice is not available or enabled for this player. Movement echolocation remains active.")
		return
	end
	voiceEnabled = true

	local audioInput = Instance.new("AudioDeviceInput")
	audioInput.Player = player
	audioInput.Parent = player

	audioAnalyzer = Instance.new("AudioAnalyzer")
	audioAnalyzer.Parent = player

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioInput
	wire.TargetInstance = audioAnalyzer
	wire.Parent = player
	voiceInputAvailable = true
end

local function setupMovementKeys()
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			isCrouching = true
			isSprinting = false
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			isSprinting = true
			isCrouching = false
		elseif input.KeyCode == Enum.KeyCode.Space then
			jumpNoiseUntil = os.clock() + Constants.MOVEMENT_NOISE.jump.duration
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.C then
			isCrouching = false
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			isSprinting = false
		end
	end)
end

function InputHandler.init()
	if initialized then return end
	initialized = true

	local pulseEvent = ReplicatedStorage:WaitForChild("EcholocationPulse", 10)
	if not pulseEvent then
		warn("EcholocationPulse RemoteEvent not found! Monster AI will be deaf.")
	end

	setupVoiceInput()
	setupMovementKeys()

	RunService.RenderStepped:Connect(function()
		if player:GetAttribute("Escaped") == true then
			setSilentNoise()
			return
		end

		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")

		if humanoid then
			setHumanoidSpeed(humanoid)
			movementSpeed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
		else
			movementSpeed = 0
		end

		if audioAnalyzer then
			rawMicLevel = audioAnalyzer.RmsLevel
			micVolume = calculateMicVolume(rawMicLevel)
		else
			rawMicLevel = 0
			micVolume = 0
		end

		calculateNoise(humanoid)
		updateNoiseDebugAttributes()

		if voiceEnabled and voiceInputAvailable and rawMicLevel <= MIC_NOISE_FLOOR then
			voiceSilenceStartedAt = voiceSilenceStartedAt or os.clock()
			if not silentVoiceWarningShown and os.clock() - voiceSilenceStartedAt >= 8 then
				silentVoiceWarningShown = true
				warn("Spatial Voice is enabled, but echolocation microphone input is reading silence. Movement noise remains active.")
			end
		else
			voiceSilenceStartedAt = nil
		end

		if rootPart then
			updatePulseSphere(rootPart)
		end

		local currentTime = os.clock()
		if pulseEvent and currentTime - lastReportTime > REPORT_RATE then
			lastReportTime = currentTime
			pulseEvent:FireServer({
				intensity = currentNoise.monsterRisk,
				visualIntensity = currentNoise.intensity,
				radius = currentNoise.radius,
				movementState = currentNoise.movementState,
				hasVoice = currentNoise.hasVoice,
				voiceVolume = currentNoise.voiceVolume,
				position = rootPart.Position,
			})
		end
	end)
end

function InputHandler.setMicVolume(volume: number)
	micVolume = math.clamp(volume, 0, 1)
end

return InputHandler

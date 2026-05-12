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
local activePulseSphere = nil
local initialized = false
local isCrouching = false
local isSprinting = false
local jumpNoiseUntil = 0
local lastReportTime = 0
local REPORT_RATE = 0.1
local NOISE_THRESHOLD = 0.08
local DEFAULT_WALK_SPEED = 12

local currentNoise = {
	intensity = 0,
	radius = 0,
	monsterRisk = 0,
	movementState = "idle",
	hasVoice = false,
	voiceVolume = 0,
}

function InputHandler.getMovementSpeed(): number
	return movementSpeed
end

function InputHandler.getMicVolume(): number
	return micVolume
end

function InputHandler.getNoiseInfo()
	return currentNoise
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
	local voiceIntensity = micVolume * Constants.VOICE_NOISE.intensityMultiplier
	local voiceRadius = micVolume * Constants.VOICE_NOISE.radiusMultiplier
	local voiceRisk = voiceIntensity * Constants.VOICE_NOISE.monsterRiskMultiplier
	local hasVoice = micVolume > 0.03

	currentNoise = {
		intensity = math.clamp(movementTier.intensity + voiceIntensity, 0, 5),
		radius = math.clamp(movementTier.radius + voiceRadius, 0, Constants.SPHERE_MAX_RADIUS),
		monsterRisk = math.clamp(movementTier.monsterRisk + voiceRisk, 0, 6),
		movementState = movementState,
		hasVoice = hasVoice,
		voiceVolume = micVolume,
	}
end

local function updatePulseSphere(rootPart: BasePart)
	local totalNoise = currentNoise.intensity
	if totalNoise > NOISE_THRESHOLD then
		if not activePulseSphere then
			activePulseSphere = Instance.new("Part")
			activePulseSphere.Name = "ActiveEcholocation"
			activePulseSphere.Shape = Enum.PartType.Ball
			activePulseSphere.CanCollide = false
			activePulseSphere.CanQuery = false
			activePulseSphere.Anchored = true
			activePulseSphere.Material = Enum.Material.ForceField
			activePulseSphere.Color = Color3.fromRGB(200, 200, 200)
			activePulseSphere.Size = Vector3.new(0, 0, 0)
			activePulseSphere.Parent = workspace.CurrentCamera

			local light = Instance.new("PointLight")
			light.Name = "PulseLight"
			light.Shadows = true
			light.Parent = activePulseSphere
		end

		activePulseSphere.Position = rootPart.Position
		local targetSize = Vector3.new(currentNoise.radius, currentNoise.radius, currentNoise.radius)
		activePulseSphere.Size = activePulseSphere.Size:Lerp(targetSize, 0.15)
		activePulseSphere.Transparency = math.clamp(0.92 - (currentNoise.voiceVolume * 0.55), 0.35, 0.92)

		local light = activePulseSphere:FindFirstChild("PulseLight")
		if light then
			light.Range = currentNoise.radius * 1.1
			light.Brightness = math.clamp((currentNoise.monsterRisk * 0.2), 0, Constants.MAX_BRIGHTNESS)
		end
	elseif activePulseSphere then
		activePulseSphere.Size = activePulseSphere.Size:Lerp(Vector3.new(0, 0, 0), 0.2)
		activePulseSphere.Transparency += 0.05

		if activePulseSphere.Size.Magnitude < 0.5 or activePulseSphere.Transparency >= 1 then
			activePulseSphere:Destroy()
			activePulseSphere = nil
		end
	end
end

local function setupVoiceInput()
	local success, isVoiceEnabled = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)

	if not (success and isVoiceEnabled) then
		warn("Spatial Voice is not available or enabled for this player. Movement echolocation remains active.")
		return
	end

	local audioInput = Instance.new("AudioDeviceInput")
	audioInput.Player = player
	audioInput.Parent = player

	audioAnalyzer = Instance.new("AudioAnalyzer")
	audioAnalyzer.Parent = player

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioInput
	wire.TargetInstance = audioAnalyzer
	wire.Parent = player
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
			micVolume = math.clamp(audioAnalyzer.RmsLevel * 15, 0, 1)
		else
			micVolume = 0
		end

		calculateNoise(humanoid)

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
			})
		end
	end)
end

function InputHandler.setMicVolume(volume: number)
	micVolume = math.clamp(volume, 0, 1)
end

return InputHandler

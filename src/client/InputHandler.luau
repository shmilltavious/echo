-- Client-side input handler for movement speed and microphone volume
local InputHandler = {}

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VoiceChatService = game:GetService("VoiceChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- State
local movementSpeed = 0
local micVolume = 0
local audioAnalyzer = nil
local activePulseSphere = nil
local NOISE_THRESHOLD = 0.1 -- Lowered to allow subtle movement visuals
local lastReportTime = 0
local REPORT_RATE = 0.1 -- Report every 0.1s for more accurate tracking

-- Public methods
function InputHandler.getMovementSpeed(): number
	return movementSpeed
end

function InputHandler.getMicVolume(): number
	return micVolume
end

-- Initialize input detection
function InputHandler.init()
	local pulseEvent = ReplicatedStorage:WaitForChild("EcholocationPulse", 10)
	if not pulseEvent then
		warn("EcholocationPulse RemoteEvent not found! Monster AI will be deaf.")
	end

	local player = Players.LocalPlayer

	-- Check if Voice Chat is enabled for the user
	local success, isVoiceEnabled = pcall(function()
		return VoiceChatService:IsVoiceEnabledForUserIdAsync(player.UserId)
	end)

	if not (success and isVoiceEnabled) then
		warn("Spatial Voice is not available or enabled for this player.")
		-- You could trigger a UI notification here to let the player know 
		-- that voice-based echolocation will be disabled for them.
		return
	end

	-- Set up Audio Input (Only if voice is confirmed enabled)
	local audioInput = Instance.new("AudioDeviceInput")
	audioInput.Player = player
	audioInput.Parent = player

	audioAnalyzer = Instance.new("AudioAnalyzer")
	audioAnalyzer.Parent = player

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioInput
	wire.TargetInstance = audioAnalyzer
	wire.Parent = player

	-- Update movement and audio data each frame
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local humanoid = character:FindFirstChild("Humanoid") 
			if humanoid then
				movementSpeed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
			end
		end

		if audioAnalyzer then
			-- RmsLevel provides a smoother volume average than PeakLevel
			micVolume = math.clamp(audioAnalyzer.RmsLevel * 15, 0, 1)
		end

		-- Calculate separate weights for movement vs voice
		-- Movement now has a much smaller impact on the visual radius
		local movementNoise = (movementSpeed / 16) * 0.25 
		local voiceNoise = micVolume * 4
		local totalNoise = math.clamp(movementNoise + voiceNoise, 0, 5)

		if totalNoise > NOISE_THRESHOLD and rootPart then
			-- Create the sphere if it doesn't exist
			if not activePulseSphere then
				activePulseSphere = Instance.new("Part")
				activePulseSphere.Name = "ActiveEcholocation"
				activePulseSphere.Shape = Enum.PartType.Ball
				activePulseSphere.CanCollide = false
				activePulseSphere.CanQuery = false
				activePulseSphere.Anchored = true
				activePulseSphere.Material = Enum.Material.ForceField
				activePulseSphere.Color = Color3.fromRGB(200, 200, 200) -- Slightly dimmer white
				activePulseSphere.Size = Vector3.new(0, 0, 0)
				activePulseSphere.Parent = workspace.CurrentCamera

				local light = Instance.new("PointLight")
				light.Name = "PulseLight"
				light.Shadows = true
				light.Parent = activePulseSphere
			end

			-- Dynamically update position and size
			activePulseSphere.Position = rootPart.Position
			
			-- Reduced radius for movement to meet "barely a bubble" requirement
			local targetRadius = 1 + (totalNoise * 10)
			local targetSize = Vector3.new(targetRadius, targetRadius, targetRadius)
			
			-- Smoothly lerp the size for a "reactive" feel
			activePulseSphere.Size = activePulseSphere.Size:Lerp(targetSize, 0.15)
			
			-- Make the bubble fainter when it's mostly movement-based
			activePulseSphere.Transparency = math.clamp(0.9 - (voiceNoise * 0.5), 0.4, 0.9)

			local light = activePulseSphere:FindFirstChild("PulseLight")
			if light then
				light.Range = targetRadius * 2
				light.Brightness = (voiceNoise * 0.8) + (movementNoise * 0.4)
			end
		elseif activePulseSphere then
			-- Smoothly shrink and destroy when quiet
			activePulseSphere.Size = activePulseSphere.Size:Lerp(Vector3.new(0, 0, 0), 0.2)
			activePulseSphere.Transparency = activePulseSphere.Transparency + 0.05
			
			if activePulseSphere.Size.Magnitude < 0.5 or activePulseSphere.Transparency >= 1 then
				activePulseSphere:Destroy()
				activePulseSphere = nil
			end
		end

		-- Tell the server about the noise so the Monster AI can react
		local currentTime = os.clock()
		if pulseEvent and currentTime - lastReportTime > REPORT_RATE then
			lastReportTime = currentTime
			-- We send the totalNoise to the server
			pulseEvent:FireServer(totalNoise)
		end
	end)
end

function InputHandler.setMicVolume(volume: number)
	micVolume = math.clamp(volume, 0, 1)
end

return InputHandler

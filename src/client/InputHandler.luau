-- Client-side input handler for movement speed and microphone volume
local InputHandler = {}

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- State
local movementSpeed = 0
local micVolume = 0
local keysPressed = {}
local audioAnalyzer = nil

-- Public methods
function InputHandler.getMovementSpeed(): number
	return movementSpeed
end

function InputHandler.getMicVolume(): number
	return micVolume
end

-- Initialize input detection
function InputHandler.init()
	-- Set up Audio Input
	local audioInput = Instance.new("AudioDeviceInput")
	audioInput.Player = Players.LocalPlayer
	audioInput.Parent = Players.LocalPlayer

	audioAnalyzer = Instance.new("AudioAnalyzer")
	audioAnalyzer.Parent = Players.LocalPlayer

	local wire = Instance.new("Wire")
	wire.SourceInstance = audioInput
	wire.TargetInstance = audioAnalyzer
	wire.Parent = Players.LocalPlayer

	-- Track key presses for movement
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.A 
			or input.KeyCode == Enum.KeyCode.S or input.KeyCode == Enum.KeyCode.D then
			keysPressed[input.KeyCode] = true
		end
	end)
	
	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		keysPressed[input.KeyCode] = nil
	end)
	
	-- Update movement speed each frame
	RunService.RenderStepped:Connect(function()
		local character = game.Players.LocalPlayer.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid then
				movementSpeed = humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed
			end
		end
	end)
	
	RunService.RenderStepped:Connect(function()
		if audioAnalyzer then
			-- PeakLevel or RmsLevel provide volume data
			-- We multiply by a sensitivity factor to make it useful for the radius
			micVolume = math.clamp(audioAnalyzer.RmsLevel * 10, 0, 1)
		end
	end)
end

function InputHandler.setMicVolume(volume: number)
	micVolume = math.clamp(volume, 0, 1)
end

return InputHandler

-- Client-side button proximity prompt
local ButtonPrompt = {}

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- Settings
local PROMPT_RANGE = 20 -- distance to show prompt
local INTERACTION_KEY = Enum.KeyCode.E

-- State
local player = Players.LocalPlayer
local promptGui = nil
local isNearButton = false
local buttonPart = nil

-- Get or create the prompt GUI
function ButtonPrompt.createPromptGui(): TextLabel
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ButtonPromptGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player.PlayerGui
	
	-- Create prompt label
	local promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "PromptLabel"
	promptLabel.Size = UDim2.new(0, 200, 0, 50)
	promptLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	promptLabel.BackgroundTransparency = 0.3
	promptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	promptLabel.TextSize = 16
	promptLabel.TextStrokeTransparency = 0.5
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.Text = "Press [E] to Open Gate"
	promptLabel.Visible = false
	promptLabel.Parent = screenGui
	
	-- Add corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = promptLabel
	
	return promptLabel
end

-- Check distance to button
function ButtonPrompt.updateProximity()
	if not buttonPart then return end
	
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	
	local distance = (buttonPart.Position - character.HumanoidRootPart.Position).Magnitude
	local wasNearButton = isNearButton
	isNearButton = distance <= PROMPT_RANGE
	
	-- Show/hide and position prompt
	if promptGui then
		if isNearButton then
			promptGui.Visible = true
			
			-- Position GUI near button using WorldToScreenPoint
			local camera = workspace.CurrentCamera
			local screenPos = camera:WorldToScreenPoint(buttonPart.Position + Vector3.new(0, 5, 0))
			promptGui.Position = UDim2.new(0, screenPos.X - 100, 0, screenPos.Y - 25)
			
			if not wasNearButton then
				print("📍 Player near button! Showing prompt. Distance:", distance)
			end
		elseif wasNearButton then
			promptGui.Visible = false
			print("📍 Player left button range. Hiding prompt.")
		end
	end
end

-- Initialize button prompt
function ButtonPrompt.init()
	print("🔘 ButtonPrompt starting initialization...")
	
	-- Find the button - wait for it to exist since map might load late
	local prototypeMap = workspace:FindFirstChild("Prototype_Map")
	if not prototypeMap then
		print("⏳ Waiting for Prototype_Map...")
		prototypeMap = workspace:WaitForChild("Prototype_Map", 10)
		if not prototypeMap then
			warn("❌ Prototype_Map not found after 10 seconds")
			return
		end
	end
	print("✅ Prototype_Map found")
	
	-- Wait for button specifically
	print("⏳ Waiting for Button inside Prototype_Map...")
	buttonPart = prototypeMap:WaitForChild("Button", 10)
	if not buttonPart then
		warn("❌ Button not found after 10 seconds")
		print("=== Available children in Prototype_Map ===")
		for _, child in pairs(prototypeMap:GetChildren()) do
			print("  📦", child.Name, "| Type:", child.ClassName)
		end
		return
	end
	print("✅ Button found at", buttonPart.Position)
	
	-- Create GUI
	promptGui = ButtonPrompt.createPromptGui()
	print("✅ Prompt GUI created")
	
	-- Get RemoteEvent for button presses
	print("⏳ Waiting for ButtonPress RemoteEvent...")
	local buttonPressEvent = game.ReplicatedStorage:WaitForChild("ButtonPress", 5)
	if not buttonPressEvent then
		warn("❌ ButtonPress RemoteEvent not found after 5 seconds")
		return
	end
	print("✅ ButtonPress RemoteEvent found")
	
	-- Listen for interaction key
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		if input.KeyCode == INTERACTION_KEY and isNearButton then
			print("🔘 Button pressed! Firing to server...")
			buttonPressEvent:FireServer("pressed")
		end
	end)
	
	-- Update proximity each frame
	RunService.RenderStepped:Connect(function()
		ButtonPrompt.updateProximity()
	end)
	
	print("✅ Button prompt initialized successfully")
end

return ButtonPrompt

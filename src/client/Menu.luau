-- Client-side menu manager
local Menu = {}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- State
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local character = player.Character or player.CharacterAdded:Wait()
local menuGui = nil
local inMenu = true
local menuCameraConnection = nil

-- Lazy-loaded references (initialized when game starts)
local SphereVisuals = nil
local ButtonPrompt = nil

-- Initialize menu setup
function Menu.init()
	print("🎮 Menu system initializing...")
	
	-- Make sure MenuCameraPos doesn't collide and is invisible
	-- Search entire workspace recursively (in case it's nested inside another model)
	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	if menuCameraPos then
		menuCameraPos.CanCollide = false
		menuCameraPos.CanQuery = false
		menuCameraPos.Transparency = 1  -- Make it fully invisible
		menuCameraPos.Anchored = true   -- Prevent physics from moving it
		menuCameraPos.Size = Vector3.new(1, 1, 1)  -- Force tiny size so it can't clip into anything even if found
		menuCameraPos.CFrame = CFrame.new(-91.034, 10.966, 23.389)  -- Lock it in place
		print("📸 Existing MenuCameraPos overridden at", tostring(menuCameraPos.Position))
	else
		-- Create the part programmatically so the camera system works
		menuCameraPos = Instance.new("Part")
		menuCameraPos.Name = "MenuCameraPos"
		menuCameraPos.Anchored = true
		menuCameraPos.CanCollide = false
		menuCameraPos.CanQuery = false
		menuCameraPos.Transparency = 1
		menuCameraPos.Size = Vector3.new(1, 1, 1)
		menuCameraPos.CFrame = CFrame.new(-91.034, 10.966, 23.389)
		menuCameraPos.Parent = workspace
		
		print("📸 MenuCameraPos created programmatically at", tostring(menuCameraPos.Position))
	end
	
	-- Hide character FIRST
	Menu.hideCharacter()
	
	-- Move character far above map so it doesn't clip into the baseplate at y=-10
	-- while still being far from the camera position
	if character then
		character:MoveTo(Vector3.new(-91.034, 100, 23.389))
	end
	
	-- Position camera at MenuCameraPos
	Menu.setCameraToMenuPos()
	
	-- Start continuous camera lock
	Menu.startCameraLock()
	
	-- Create menu UI
	Menu.createMenuUI()
	
	-- Ensure world is dark
	Menu.setDarkAmbiance()
	
	print("✅ Menu ready!")
end

-- Start continuously locking camera to MenuCameraPos
function Menu.startCameraLock()
	if menuCameraConnection then
		menuCameraConnection:Disconnect()
	end
	
	menuCameraConnection = RunService.RenderStepped:Connect(function()
		if not inMenu then return end
		
		local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
		if menuCameraPos then
			camera.CFrame = menuCameraPos.CFrame
		end
	end)
	
	print("🔒 Camera lock activated")
end

-- Stop camera lock
function Menu.stopCameraLock()
	if menuCameraConnection then
		menuCameraConnection:Disconnect()
		menuCameraConnection = nil
	end
	
	-- Reset camera type to allow player control
	camera.CameraType = Enum.CameraType.Custom
	
	print("🔓 Camera lock deactivated")
end

-- Set camera to MenuCameraPos part
function Menu.setCameraToMenuPos()
	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	
	if not menuCameraPos then
		warn("⚠️  MenuCameraPos part not found in workspace!")
		return
	end
	
	-- Set camera to fixed mode (not following character)
	camera.CameraType = Enum.CameraType.Fixed
	camera.CFrame = menuCameraPos.CFrame
	camera.FieldOfView = 70
	
	-- Debug output
	print("📷 Camera positioned at MenuCameraPos (Fixed mode)")
	print("   MenuCameraPos Position: " .. tostring(menuCameraPos.Position))
	print("   Camera CFrame: " .. tostring(camera.CFrame))
	print("   MenuCameraPos CFrame: " .. tostring(menuCameraPos.CFrame))
end

-- Hide the player character
function Menu.hideCharacter()
	if not character then return end
	
	-- Hide all character parts
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Transparency = 1
		end
	end
	
	-- Disable humanoid
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.HealthDisplayDistance = 0
	end
	
	print("👻 Character hidden")
end

-- Create the menu UI
function Menu.createMenuUI()
	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MenuGui"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")
	
	-- Create background frame (mostly transparent)
	local bgFrame = Instance.new("Frame")
	bgFrame.Name = "Background"
	bgFrame.Size = UDim2.new(1, 0, 1, 0)
	bgFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bgFrame.BackgroundTransparency = 0.7  -- Transparent to see background
	bgFrame.Parent = screenGui
	
	-- Create title with dark, tech aesthetic
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0, 400, 0, 120)
	titleLabel.Position = UDim2.new(0.5, -200, 0.15, 0)  -- Moved way up
	titleLabel.BackgroundTransparency = 1
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)  -- Pure white
	titleLabel.TextSize = 96  -- Much bigger
	titleLabel.Font = Enum.Font.Oswald  -- Angular, more ominous font
	titleLabel.Text = "ECH.o"
	titleLabel.TextStrokeTransparency = 0.0  -- Full opacity stroke for dramatic effect
	titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)  -- Black stroke for harsh contrast
	titleLabel.Parent = bgFrame
	
	-- Create PLAY button (minimal, sleek design)
	local playButton = Instance.new("TextButton")
	playButton.Name = "PlayButton"
	playButton.Size = UDim2.new(0, 180, 0, 50)
	playButton.Position = UDim2.new(0.5, -90, 0.55, 0)
	playButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)  -- Almost black
	playButton.TextColor3 = Color3.fromRGB(100, 100, 100)  -- Dark gray text
	playButton.TextSize = 18
	playButton.Font = Enum.Font.GothamMedium
	playButton.Text = "ENTER"
	playButton.BorderSizePixel = 0
	playButton.Parent = bgFrame
	
	-- Add minimal border effect
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = Color3.fromRGB(60, 60, 60)
	uiStroke.Thickness = 1
	uiStroke.Parent = playButton
	
	-- Add corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = playButton
	
	-- Subtle hover effect (fade text color)
	playButton.MouseEnter:Connect(function()
		playButton.TextColor3 = Color3.fromRGB(180, 180, 180)  -- Lighter on hover
		uiStroke.Color = Color3.fromRGB(100, 100, 100)
	end)
	
	playButton.MouseLeave:Connect(function()
		playButton.TextColor3 = Color3.fromRGB(100, 100, 100)
		uiStroke.Color = Color3.fromRGB(60, 60, 60)
	end)
	
	-- Play button click handler
	playButton.MouseButton1Click:Connect(function()
		print("▶️  Play clicked!")
		Menu.startGame()
	end)
	
	menuGui = screenGui
	print("🎨 Menu UI created (horror themed)")
end

-- Set dark ambiance
function Menu.setDarkAmbiance()
	Lighting.Ambient = Color3.fromRGB(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
	print("🌑 Dark ambiance set")
end

-- Start the game (transition from menu to gameplay)
function Menu.startGame()
	print("🚀 Starting game...")
	
	-- Stop camera lock
	Menu.stopCameraLock()
	
	-- Hide menu UI
	if menuGui then
		menuGui:Destroy()
	end
	
	-- Keep character hidden during teleport to prevent physics glitches
	-- MoveTo is async, so we need to wait for it to complete
	
	-- Teleport player to spawn location
	local spawnPosition = Vector3.new(0, 5, 0)
	local spawnLocation = workspace:FindFirstChild("SpawnLocation")
	if spawnLocation then
		spawnPosition = spawnLocation.Position + Vector3.new(0, 3, 0)
	end
	
	-- Teleport while still invisible (no collisions)
	character:MoveTo(spawnPosition)
	
	-- Wait for physics to settle the MoveTo
	task.wait(0.15)
	
	-- Remove MenuCameraPos entirely (delayed so character teleport settles first)
	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	if menuCameraPos then
		menuCameraPos:Destroy()
		print("🗑️ MenuCameraPos destroyed")
	end
	
	-- Now show the character at the correct spawn position (no longer at y=100)
	Menu.showCharacter()
	
	-- Reset camera to follow character naturally
	task.wait(0.05)
	local head = character:FindFirstChild("Head")
	if head then
		camera.CFrame = head.CFrame
	end
	
	-- Initialize spatial audio system (reads mic + movement, creates pulse sphere)
	if not SphereVisuals then
		SphereVisuals = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("SphereVisuals", 5))
	end
	if SphereVisuals then
		task.spawn(function()
			SphereVisuals.init()
		end)
	end
	
	-- Initialize button proximity prompt
	if not ButtonPrompt then
		ButtonPrompt = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("ButtonPrompt", 5))
	end
	if ButtonPrompt then
		task.spawn(function()
			ButtonPrompt.init()
		end)
	end
	
	inMenu = false
	print("✅ Game started! Camera unlocked.")
end

-- Show the character
function Menu.showCharacter()
	if not character then return end
	
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			part.CanCollide = true
		end
	end
	
	print("👤 Character shown")
end

return Menu

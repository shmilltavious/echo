-- Client-side menu manager
local Menu = {}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local character = player.Character or player.CharacterAdded:Wait()
local menuGui: ScreenGui? = nil
local inMenu = true
local menuCameraConnection: RBXScriptConnection? = nil

local SphereVisuals = nil
local ObjectiveClient = nil
local CameraEffects = nil
local MonsterFeedback = nil

local MENU_CAMERA_CFRAME =
	CFrame.new(-91.034, 10.966, 23.389)
	* CFrame.Angles(0, math.rad(25), 0)
	* CFrame.Angles(math.rad(-18), 0, 0)
	* CFrame.new(0, 0, -3)

local function getClientModule(name: string)
	return script.Parent:WaitForChild(name, 5)
end

function Menu.init()
	print("Menu system initializing...")

	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	if not menuCameraPos then
		menuCameraPos = Instance.new("Part")
		menuCameraPos.Name = "MenuCameraPos"
		menuCameraPos.Parent = workspace
	end

	menuCameraPos.Anchored = true
	menuCameraPos.CanCollide = false
	menuCameraPos.CanQuery = false
	menuCameraPos.Transparency = 1
	menuCameraPos.Size = Vector3.new(1, 1, 1)
	menuCameraPos.CFrame = MENU_CAMERA_CFRAME

	Menu.hideCharacter()

	if character then
		character:MoveTo(Vector3.new(-91.034, 100, 23.389))
	end

	Menu.setCameraToMenuPos()
	Menu.startCameraLock()
	Menu.createMenuUI()
	Menu.setDarkAmbiance()

	print("Menu ready")
end

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
end

function Menu.stopCameraLock()
	if menuCameraConnection then
		menuCameraConnection:Disconnect()
		menuCameraConnection = nil
	end

	camera.CameraType = Enum.CameraType.Custom
end

function Menu.setCameraToMenuPos()
	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	if not menuCameraPos then
		warn("MenuCameraPos part not found in workspace")
		return
	end

	camera.CameraType = Enum.CameraType.Fixed
	camera.CFrame = menuCameraPos.CFrame
	camera.FieldOfView = 70
end

function Menu.hideCharacter()
	if not character then return end

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Transparency = 1
		end
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.HealthDisplayDistance = 0
	end
end

function Menu.createMenuUI()
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = playerGui:FindFirstChild("MenuGui")

	if not screenGui then
		local starterMenuGui = StarterGui:FindFirstChild("MenuGui")
		if not starterMenuGui then
			warn("MenuGui not found in StarterGui")
			return
		end

		screenGui = starterMenuGui:Clone()
		screenGui.Parent = playerGui
	end

	screenGui.ResetOnSpawn = false
	screenGui.Enabled = true

	local bgFrame = screenGui:WaitForChild("Background", 5)
	local playButton = bgFrame and bgFrame:WaitForChild("PlayButton", 5)
	local uiStroke = playButton and playButton:FindFirstChildOfClass("UIStroke")

	if not playButton then
		warn("MenuGui.PlayButton not found")
		return
	end

	playButton.MouseEnter:Connect(function()
		playButton.TextColor3 = Color3.fromRGB(180, 180, 180)
		if uiStroke then
			uiStroke.Color = Color3.fromRGB(100, 100, 100)
		end
	end)

	playButton.MouseLeave:Connect(function()
		playButton.TextColor3 = Color3.fromRGB(100, 100, 100)
		if uiStroke then
			uiStroke.Color = Color3.fromRGB(60, 60, 60)
		end
	end)

	playButton.MouseButton1Click:Connect(function()
		Menu.startGame()
	end)

	menuGui = screenGui
	print("Menu UI loaded from StarterGui")
end

function Menu.setDarkAmbiance()
	Lighting.Ambient = Color3.fromRGB(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
	Lighting.Brightness = 0
	Lighting.ClockTime = 0
	Lighting.FogColor = Color3.fromRGB(0, 0, 0)
	Lighting.FogStart = 0
	Lighting.FogEnd = 90

	local colorCorrection = Lighting:FindFirstChild("ECHO_ColorCorrection")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "ECHO_ColorCorrection"
		colorCorrection.Parent = Lighting
	end
	if colorCorrection:IsA("ColorCorrectionEffect") then
		colorCorrection.Brightness = -0.12
		colorCorrection.Contrast = 0.28
		colorCorrection.Saturation = -0.35
		colorCorrection.TintColor = Color3.fromRGB(190, 205, 215)
	end

	local bloom = Lighting:FindFirstChild("Bloom")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = 0.28
		bloom.Size = 28
		bloom.Threshold = 1.2
	end
end

function Menu.startGame()
	print("Starting game...")

	Menu.stopCameraLock()

	if menuGui then
		menuGui:Destroy()
		menuGui = nil
	end

	local spawnCFrame = CFrame.new(0, 5, 0)
	local spawnMarker = workspace:FindFirstChild("spawn")
	if spawnMarker and spawnMarker:IsA("BasePart") then
		spawnCFrame = spawnMarker.CFrame + Vector3.new(0, 3, 0)
	else
		local spawnLocation = workspace:FindFirstChild("SpawnLocation")
		if spawnLocation and spawnLocation:IsA("BasePart") then
			spawnCFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
		end
	end

	character:PivotTo(spawnCFrame)
	task.wait(0.15)

	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	if menuCameraPos then
		menuCameraPos:Destroy()
	end

	Menu.showCharacter()

	task.wait(0.05)
	local head = character:FindFirstChild("Head")
	if head then
		camera.CFrame = head.CFrame
	end

	if not SphereVisuals then
		local module = getClientModule("SphereVisuals")
		if module then
			SphereVisuals = require(module)
		end
	end
	if SphereVisuals then
		task.spawn(function()
			SphereVisuals.init()
		end)
	end

	if not ObjectiveClient then
		local module = getClientModule("ObjectiveClient")
		if module then
			ObjectiveClient = require(module)
		end
	end
	if ObjectiveClient then
		task.spawn(function()
			ObjectiveClient.init()
		end)
	end

	if not CameraEffects then
		local module = getClientModule("CameraEffects")
		if module then
			CameraEffects = require(module)
		end
	end
	if CameraEffects then
		task.spawn(function()
			CameraEffects.init()
		end)
	end

	if not MonsterFeedback then
		local module = getClientModule("MonsterFeedback")
		if module then
			MonsterFeedback = require(module)
		end
	end
	if MonsterFeedback then
		task.spawn(function()
			MonsterFeedback.init()
		end)
	end

	inMenu = false
	print("Game started")
end

function Menu.showCharacter()
	if not character then return end

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			part.CanCollide = true
		end
	end
end

return Menu

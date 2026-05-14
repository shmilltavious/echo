-- Client-side menu manager
local Menu = {}

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local character = player.Character or player.CharacterAdded:Wait()
local menuGui: ScreenGui? = nil
local inMenu = true
local startRequested = false
local menuCameraConnection: RBXScriptConnection? = nil
local transitionGui: ScreenGui? = nil
local transitionFrame: Frame? = nil
local hiddenPartState = {}
local menuFreezeState = nil
local quietSoundState = {}
local quietSoundConnection: RBXScriptConnection? = nil

local SphereVisuals = nil
local ObjectiveClient = nil
local InventoryClient = nil
local CameraEffects = nil
local MonsterFeedback = nil
local AudioFeedback = nil

local MENU_CAMERA_CFRAME =
	CFrame.new(-91.034, 10.966, 23.389)
	* CFrame.Angles(0, math.rad(25), 0)
	* CFrame.Angles(math.rad(-18), 0, 0)
	* CFrame.new(0, 0, -3)
local FADE_TO_BLACK_SECONDS = 0.45
local BLACK_HOLD_SECONDS = 0.15
local FADE_FROM_BLACK_SECONDS = 0.65
local TRANSITION_DISPLAY_ORDER = 10000

local function getCurrentCharacter(): Model?
	character = player.Character or player.CharacterAdded:Wait()
	return character
end

local function getCurrentCamera(): Camera?
	camera = workspace.CurrentCamera
	return camera
end

local function getClientModule(name: string)
	return script.Parent:WaitForChild(name, 5)
end

local function getPlayerGui(): PlayerGui?
	return player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", 10)
end

local function getSpawnCFrame(): CFrame
	local spawnMarker = workspace:FindFirstChild("spawn")
	if spawnMarker and spawnMarker:IsA("BasePart") then
		return spawnMarker.CFrame + Vector3.new(0, 3, 0)
	end

	local spawnLocation = workspace:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		return spawnLocation.CFrame + Vector3.new(0, 3, 0)
	end

	return CFrame.new(0, 5, 0)
end

local function zeroCharacterVelocity(targetCharacter: Model)
	for _, descendant in ipairs(targetCharacter:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function positionCharacterAtSpawn(targetCharacter: Model)
	targetCharacter:PivotTo(getSpawnCFrame())
	zeroCharacterVelocity(targetCharacter)
end

local function muteCharacterSound(sound: Sound)
	if quietSoundState[sound] == nil then
		quietSoundState[sound] = sound.Volume
	end
	sound.Volume = 0
end

local function beginStartupQuietWindow(targetCharacter: Model)
	if quietSoundConnection then
		quietSoundConnection:Disconnect()
		quietSoundConnection = nil
	end
	table.clear(quietSoundState)

	for _, descendant in ipairs(targetCharacter:GetDescendants()) do
		if descendant:IsA("Sound") then
			muteCharacterSound(descendant)
		end
	end

	quietSoundConnection = targetCharacter.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Sound") then
			muteCharacterSound(descendant)
		end
	end)
end

local function endStartupQuietWindow()
	if quietSoundConnection then
		quietSoundConnection:Disconnect()
		quietSoundConnection = nil
	end

	for sound, volume in pairs(quietSoundState) do
		if sound and sound.Parent then
			sound.Volume = volume
		end
	end
	table.clear(quietSoundState)
end

local function freezeCharacterForMenu(targetCharacter: Model)
	local humanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")

	menuFreezeState = {
		humanoid = humanoid,
		rootPart = rootPart,
		walkSpeed = humanoid and humanoid.WalkSpeed or nil,
		jumpPower = humanoid and humanoid.JumpPower or nil,
		jumpHeight = humanoid and humanoid.JumpHeight or nil,
		autoRotate = humanoid and humanoid.AutoRotate or nil,
		rootAnchored = if rootPart and rootPart:IsA("BasePart") then rootPart.Anchored else nil,
	}

	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end
	if rootPart and rootPart:IsA("BasePart") then
		rootPart.Anchored = true
	end
	zeroCharacterVelocity(targetCharacter)
end

local function restoreCharacterFromMenu()
	local state = menuFreezeState
	menuFreezeState = nil
	if not state then
		return
	end

	local humanoid = state.humanoid
	if humanoid and humanoid.Parent then
		if state.walkSpeed then humanoid.WalkSpeed = state.walkSpeed end
		if state.jumpPower then humanoid.JumpPower = state.jumpPower end
		if state.jumpHeight then humanoid.JumpHeight = state.jumpHeight end
		if state.autoRotate ~= nil then humanoid.AutoRotate = state.autoRotate end
	end

	local rootPart = state.rootPart
	if rootPart and rootPart.Parent and rootPart:IsA("BasePart") and state.rootAnchored ~= nil then
		rootPart.Anchored = state.rootAnchored
	end
end

local function ensureTransitionOverlay(): Frame?
	if transitionFrame and transitionFrame.Parent then
		return transitionFrame
	end

	local playerGui = getPlayerGui()
	if not playerGui then
		warn("PlayerGui not available for menu transition")
		return nil
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "MenuTransitionGui"
	gui.DisplayOrder = TRANSITION_DISPLAY_ORDER
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Blackout"
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.Active = false
	frame.Parent = gui

	transitionGui = gui
	transitionFrame = frame
	return frame
end

local function tweenBlackout(targetTransparency: number, duration: number)
	local frame = ensureTransitionOverlay()
	if not frame then
		task.wait(duration)
		return
	end

	frame.Active = true
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = targetTransparency }
	)
	tween:Play()
	tween.Completed:Wait()
	if targetTransparency >= 1 then
		frame.Active = false
	end
end

local function cleanupTransitionOverlay()
	if transitionGui then
		transitionGui:Destroy()
	end
	transitionGui = nil
	transitionFrame = nil
end

function Menu.init()
	print("Menu system initializing...")
	local currentCharacter = getCurrentCharacter()
	getCurrentCamera()

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

	if currentCharacter then
		positionCharacterAtSpawn(currentCharacter)
		Menu.hideCharacter()
		beginStartupQuietWindow(currentCharacter)
		freezeCharacterForMenu(currentCharacter)
	end

	Menu.setCameraToMenuPos()
	Menu.startCameraLock()
	Menu.createMenuUI()
	ensureTransitionOverlay()
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
		local currentCamera = getCurrentCamera()
		if menuCameraPos and currentCamera then
			currentCamera.CFrame = menuCameraPos.CFrame
		end
	end)
end

function Menu.stopCameraLock()
	if menuCameraConnection then
		menuCameraConnection:Disconnect()
		menuCameraConnection = nil
	end

	local currentCamera = getCurrentCamera()
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

function Menu.setCameraToMenuPos()
	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	local currentCamera = getCurrentCamera()
	if not menuCameraPos then
		warn("MenuCameraPos part not found in workspace")
		return
	end
	if not currentCamera then
		warn("CurrentCamera not available for menu")
		return
	end

	currentCamera.CameraType = Enum.CameraType.Fixed
	currentCamera.CFrame = menuCameraPos.CFrame
	currentCamera.FieldOfView = 70
end

function Menu.hideCharacter()
	if not character then return end

	table.clear(hiddenPartState)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			hiddenPartState[part] = {
				canCollide = part.CanCollide,
				transparency = part.Transparency,
			}
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
	local playerGui = getPlayerGui()
	if not playerGui then
		warn("PlayerGui not available for MenuGui")
		return
	end

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
	if startRequested or not inMenu then
		return
	end
	startRequested = true
	print("Starting game...")
	local currentCharacter = getCurrentCharacter()
	local currentCamera = getCurrentCamera()
	if not currentCharacter then
		warn("Cannot start game: character not available")
		startRequested = false
		return
	end

	tweenBlackout(0, FADE_TO_BLACK_SECONDS)
	Menu.stopCameraLock()

	if menuGui then
		menuGui:Destroy()
		menuGui = nil
	end

	positionCharacterAtSpawn(currentCharacter)
	task.wait(0.15)

	local menuCameraPos = workspace:FindFirstChild("MenuCameraPos", true)
	if menuCameraPos then
		menuCameraPos:Destroy()
	end

	restoreCharacterFromMenu()
	Menu.showCharacter()

	task.wait(0.05)
	local head = currentCharacter:FindFirstChild("Head")
	if head and currentCamera then
		currentCamera.CFrame = head.CFrame
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

	if not InventoryClient then
		local module = getClientModule("InventoryClient")
		if module then
			InventoryClient = require(module)
		end
	end
	if InventoryClient then
		task.spawn(function()
			InventoryClient.init()
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

	if not AudioFeedback then
		local module = getClientModule("AudioFeedback")
		if module then
			AudioFeedback = require(module)
		end
	end
	if AudioFeedback then
		task.spawn(function()
			AudioFeedback.init()
		end)
	end

	inMenu = false
	task.wait(BLACK_HOLD_SECONDS)
	tweenBlackout(1, FADE_FROM_BLACK_SECONDS)
	endStartupQuietWindow()
	cleanupTransitionOverlay()
	print("Game started")
end

function Menu.showCharacter()
	if not character then return end

	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local state = hiddenPartState[part]
			part.Transparency = if state then state.transparency else 0
			part.CanCollide = if state then state.canCollide else part.CanCollide
		end
	end
end

return Menu

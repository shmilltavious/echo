-- Battery-powered flashlight with limited runtime and toggle
local Flashlight = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local EquipmentClient = require(script.Parent.EquipmentClient)

-- Constants
local CLIENT_WAIT_TIMEOUT = Constants.REMOTE_LIMITS.CLIENT_WAIT_TIMEOUT
local GAMEPLAY_ITEMS_FOLDER_NAME = Constants.OBJECTIVES.GAMEPLAY_ITEMS_FOLDER_NAME
local MAX_BATTERY = 60 -- 60 seconds of total flashlight usage
local FULL_BRIGHTNESS = 5.25
local FULL_RANGE = 40
local CLOSE_FILL_BRIGHTNESS = 0.55
local CLOSE_FILL_RANGE = 10
local SURFACE_FILL_BRIGHTNESS = 1.05
local SURFACE_FILL_RANGE = 16
local SPOT_ANGLE = 54
local DIMMING_THRESHOLD = 12 -- last 12 seconds = dimming phase
local VIEWMODEL_TEMPLATE_NAME = "Flashlight"
local VIEWMODEL_SCALE = 0.14
local VIEWMODEL_OFFSET = CFrame.new(0.58, -0.66, -1.12) * CFrame.Angles(math.rad(-4), math.rad(92), math.rad(-9))
local VIEWMODEL_HIDDEN_OFFSET = CFrame.new(0.34, -1.18, 0.48) * CFrame.Angles(math.rad(22), math.rad(-12), math.rad(-18))
local LIGHT_EMITTER_OFFSET = CFrame.new(0.44, -0.52, -1.58)
local HAND_SKIN_COLOR = Color3.fromRGB(180, 132, 96)
local SLEEVE_COLOR = Color3.fromRGB(34, 35, 38)
local EQUIP_ANIMATION_TIME = 0.38
local UNEQUIP_ANIMATION_TIME = 0.3
local TOGGLE_COOLDOWN = 0.32
local FLASHLIGHT_REPORT_RATE = 0.08
local REMOTE_STALE_TIME = 0.35
local REMOTE_BEAM_LENGTH = 26
local REMOTE_BEAM_THICKNESS = 0.2
local FLASHLIGHT_CLICK_SOUND_ID = "rbxasset://sounds/switch.wav"

-- State
local battery = MAX_BATTERY
local flashlightPart: Part? = nil
local flashlightViewModel: Model? = nil
local handViewModel: Model? = nil
local handParts = {}
local flashlightSpot: SpotLight? = nil
local flashlightFill: PointLight? = nil
local surfaceFillPart: Part? = nil
local surfaceFillLight: PointLight? = nil
local batteryConnection: RBXScriptConnection? = nil
local isDead = false
local isOn = true
local isEquipped = true
local hudFrame: Frame? = nil
local hudStatus: TextLabel? = nil
local hudBatteryText: TextLabel? = nil
local hudBatteryFill: Frame? = nil
local lastToggleTime = -math.huge
local viewmodelAlpha = 1
local viewmodelStartAlpha = 1
local viewmodelTargetAlpha = 1
local viewmodelAnimationTime = 0
local viewmodelAnimationDuration = 0
local viewModelSuppressed = false
local flashlightStateEvent: RemoteEvent? = nil
local reportTimer = 0
local remoteFlashlights = {}

local function addTextStroke(label: TextLabel, transparency: number)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = transparency
end

local function smoothStep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	return clamped * clamped * (3 - (2 * clamped))
end

local function setViewModelParent(parent: Instance?)
	if flashlightViewModel and flashlightViewModel.Parent ~= parent then
		flashlightViewModel.Parent = parent
	end
	if handViewModel and handViewModel.Parent ~= parent then
		handViewModel.Parent = parent
	end
end

local function setLightsEnabled(enabled: boolean)
	if flashlightSpot then
		flashlightSpot.Enabled = enabled
	end
	if flashlightFill then
		flashlightFill.Enabled = enabled
	end
	if surfaceFillLight then
		surfaceFillLight.Enabled = enabled
	end
end

local function shouldEmitLight(): boolean
	return isEquipped and isOn and not isDead
end

local function applyEquippedVisibility()
	setLightsEnabled(shouldEmitLight())
	if hudFrame then
		hudFrame.Visible = isEquipped
	end
end

local function playClickSound(turningOn: boolean)
	local sound = Instance.new("Sound")
	sound.Name = "FlashlightClick"
	sound.SoundId = FLASHLIGHT_CLICK_SOUND_ID
	sound.Volume = 0.14
	sound.PlaybackSpeed = (if turningOn then 1.04 else 0.92) + (math.random() * 0.04)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 1.5)
end

local function startViewModelTransition(show: boolean)
	viewmodelStartAlpha = viewmodelAlpha
	viewmodelTargetAlpha = if show then 1 else 0
	viewmodelAnimationTime = 0
	viewmodelAnimationDuration = if show then EQUIP_ANIMATION_TIME else UNEQUIP_ANIMATION_TIME
end

local function updateViewModelAnimation(dt: number)
	if viewmodelAlpha == viewmodelTargetAlpha then
		return
	end

	viewmodelAnimationTime += dt
	local alpha = smoothStep(viewmodelAnimationTime / math.max(viewmodelAnimationDuration, 0.01))
	viewmodelAlpha = viewmodelStartAlpha + ((viewmodelTargetAlpha - viewmodelStartAlpha) * alpha)

	if viewmodelAnimationTime >= viewmodelAnimationDuration then
		viewmodelAlpha = viewmodelTargetAlpha
	end
end

local function getAnimatedViewModelOffset(): CFrame
	local pose = VIEWMODEL_HIDDEN_OFFSET:Lerp(CFrame.identity, smoothStep(viewmodelAlpha))
	if viewmodelAnimationTime > 0 and viewmodelAnimationTime < viewmodelAnimationDuration then
		local phase = math.clamp(viewmodelAnimationTime / viewmodelAnimationDuration, 0, 1)
		local flick = math.sin(phase * math.pi)
		local direction = if viewmodelTargetAlpha > viewmodelStartAlpha then 1 else -1
		pose *= CFrame.new(0, 0.03 * flick, -0.04 * flick * direction)
			* CFrame.Angles(math.rad(-5 * flick * direction), math.rad(2 * flick), math.rad(5 * flick * direction))
	end

	return pose
end

local function prepareViewModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Massless = true
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function findFlashlightTemplate(): Model?
	local gameplayItems = workspace:FindFirstChild(GAMEPLAY_ITEMS_FOLDER_NAME)
	local template = gameplayItems and gameplayItems:FindFirstChild(VIEWMODEL_TEMPLATE_NAME)
	if not template then
		template = workspace:FindFirstChild(VIEWMODEL_TEMPLATE_NAME, true)
	end

	if template and template:IsA("Model") then
		return template
	end

	return nil
end

local function createFlashlightViewModel(camera: Camera?): Model?
	local template = findFlashlightTemplate()
	if not template then
		warn("Flashlight model not found in Workspace.GameplayItems or workspace descendants. Falling back to light-only flashlight.")
		return nil
	end

	local viewModel = template:Clone()
	viewModel.Name = "FirstPersonFlashlight"
	prepareViewModel(viewModel)

	local scaled = pcall(function()
		viewModel:ScaleTo(VIEWMODEL_SCALE)
	end)
	if not scaled then
		warn("Unable to scale flashlight viewmodel; using authored size.")
	end

	viewModel.Parent = camera or workspace
	return viewModel
end

local function createHandPart(name: string, shape: Enum.PartType, size: Vector3, color: Color3, offset: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Massless = true
	part.Parent = handViewModel
	table.insert(handParts, {
		part = part,
		offset = offset,
	})
	return part
end

local function createHandViewModel(camera: Camera?): Model
	local model = Instance.new("Model")
	model.Name = "FirstPersonFlashlightHand"
	model.Parent = camera or workspace
	handViewModel = model
	table.clear(handParts)

	createHandPart(
		"Sleeve",
		Enum.PartType.Block,
		Vector3.new(0.22, 0.2, 0.28),
		SLEEVE_COLOR,
		CFrame.new(0.88, -1.1, -0.54) * CFrame.Angles(math.rad(-18), math.rad(-10), math.rad(8))
	)
	createHandPart(
		"Forearm",
		Enum.PartType.Block,
		Vector3.new(0.16, 0.16, 0.32),
		HAND_SKIN_COLOR,
		CFrame.new(0.74, -0.92, -0.78) * CFrame.Angles(math.rad(-18), math.rad(-14), math.rad(8))
	)
	createHandPart(
		"Hand",
		Enum.PartType.Ball,
		Vector3.new(0.22, 0.17, 0.18),
		HAND_SKIN_COLOR,
		CFrame.new(0.58, -0.7, -1.1) * CFrame.Angles(math.rad(-6), math.rad(-18), math.rad(4))
	)
	createHandPart(
		"Thumb",
		Enum.PartType.Block,
		Vector3.new(0.07, 0.09, 0.14),
		HAND_SKIN_COLOR,
		CFrame.new(0.46, -0.69, -1.05) * CFrame.Angles(math.rad(18), math.rad(28), math.rad(-12))
	)

	return model
end

local function disableLocalCharacterShadows(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CastShadow = false
		end
	end

	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CastShadow = false
		end
	end)
end

local function createSurfaceFillLight(): (Part, PointLight)
	local part = Instance.new("Part")
	part.Name = "FlashlightSurfaceFillEmitter"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.16, 0.16, 0.16)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = workspace

	local light = Instance.new("PointLight")
	light.Name = "FlashlightSurfaceFill"
	light.Brightness = SURFACE_FILL_BRIGHTNESS
	light.Range = SURFACE_FILL_RANGE
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 240, 210)
	light.Enabled = shouldEmitLight()
	light.Parent = part

	return part, light
end

-- Create the held local flashlight and lights that follow its muzzle.
function Flashlight.createFlashlight(): (Part, SpotLight)
	local camera = workspace.CurrentCamera
	flashlightViewModel = createFlashlightViewModel(camera)
	createHandViewModel(camera)

	local part = Instance.new("Part")
	part.Name = "FlashlightEmitter"
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(0.12, 0.12, 0.12)
	part.Transparency = 1 -- invisible
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.CastShadow = false
	part.Parent = workspace

	local spotLight = Instance.new("SpotLight")
	spotLight.Name = "FlashlightBeam"
	spotLight.Brightness = FULL_BRIGHTNESS
	spotLight.Range = FULL_RANGE
	spotLight.Angle = SPOT_ANGLE
	spotLight.Shadows = true
	spotLight.Color = Color3.fromRGB(255, 245, 220) -- Warm white
	spotLight.Face = Enum.NormalId.Front
	spotLight.Enabled = shouldEmitLight()
	spotLight.Parent = part

	local fillLight = Instance.new("PointLight")
	fillLight.Name = "FlashlightCloseFill"
	fillLight.Brightness = CLOSE_FILL_BRIGHTNESS
	fillLight.Range = CLOSE_FILL_RANGE
	fillLight.Shadows = false
	fillLight.Color = Color3.fromRGB(255, 240, 210)
	fillLight.Enabled = shouldEmitLight()
	fillLight.Parent = part
	flashlightFill = fillLight
	surfaceFillPart, surfaceFillLight = createSurfaceFillLight()

	return part, spotLight
end

local function updateFlashlightTransform(camera: Camera, dt: number)
	updateViewModelAnimation(dt)

	if flashlightPart then
		if flashlightPart.Parent ~= workspace then
			flashlightPart.Parent = workspace
		end
		flashlightPart.CFrame = camera.CFrame * LIGHT_EMITTER_OFFSET
	end

	if surfaceFillPart and surfaceFillLight then
		if shouldEmitLight() then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local ignored = { flashlightPart, surfaceFillPart, flashlightViewModel, handViewModel }
			local character = Players.LocalPlayer.Character
			if character then
				table.insert(ignored, character)
			end
			params.FilterDescendantsInstances = ignored
			params.IgnoreWater = true

			local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * FULL_RANGE, params)
			if result then
				local distanceAlpha = math.clamp(1 - (result.Distance / FULL_RANGE), 0, 1)
				surfaceFillPart.Position = result.Position + (result.Normal * 0.18)
				surfaceFillLight.Enabled = true
				surfaceFillLight.Brightness = SURFACE_FILL_BRIGHTNESS * (0.35 + (distanceAlpha * 0.65))
				surfaceFillLight.Range = SURFACE_FILL_RANGE * (0.55 + (distanceAlpha * 0.45))
			else
				surfaceFillLight.Enabled = false
			end
		else
			surfaceFillLight.Enabled = false
		end
	end

	local shouldShowViewModel = not viewModelSuppressed and (isEquipped or viewmodelAlpha > 0.01 or viewmodelTargetAlpha > 0)
	setViewModelParent(if shouldShowViewModel then camera else nil)
	local animatedOffset = getAnimatedViewModelOffset()

	if flashlightViewModel and flashlightViewModel.Parent then
		flashlightViewModel:PivotTo(camera.CFrame * animatedOffset * VIEWMODEL_OFFSET)
	end
	for _, data in ipairs(handParts) do
		if data.part and data.part.Parent then
			data.part.CFrame = camera.CFrame * animatedOffset * data.offset
		end
	end
end

-- Create HUD in bottom-right corner
function Flashlight.createHUD()
	local player = Players.LocalPlayer
	local playerGui = player:FindFirstChild("PlayerGui") or player:WaitForChild("PlayerGui", CLIENT_WAIT_TIMEOUT)
	if not playerGui then
		warn("[Flashlight] PlayerGui was not available; flashlight HUD disabled.")
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FlashlightHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "HudFrame"
	frame.Size = UDim2.new(0, 252, 0, 86)
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -24, 1, -30)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = isEquipped
	frame.Parent = screenGui

	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.Size = UDim2.new(0, 22, 0, 22)
	diamond.Position = UDim2.new(0, 0, 0, 8)
	diamond.BackgroundTransparency = 1
	diamond.Rotation = 45
	diamond.Parent = frame

	local diamondStroke = Instance.new("UIStroke")
	diamondStroke.Color = Color3.fromRGB(185, 186, 178)
	diamondStroke.Transparency = 0.22
	diamondStroke.Thickness = 1
	diamondStroke.Parent = diamond

	local innerDiamond = Instance.new("Frame")
	innerDiamond.Name = "InnerDiamond"
	innerDiamond.Size = UDim2.new(0, 10, 0, 10)
	innerDiamond.Position = UDim2.new(0.5, -5, 0.5, -5)
	innerDiamond.BackgroundTransparency = 1
	innerDiamond.Parent = diamond

	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = Color3.fromRGB(126, 28, 28)
	innerStroke.Transparency = 0.2
	innerStroke.Thickness = 1
	innerStroke.Parent = innerDiamond

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -38, 0, 24)
	title.Position = UDim2.new(0, 34, 0, 3)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Garamond
	title.Text = "Flashlight"
	title.TextColor3 = Color3.fromRGB(232, 230, 220)
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame
	addTextStroke(title, 0.55)

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.Size = UDim2.new(0, 72, 0, 20)
	status.Position = UDim2.new(0, 34, 0, 29)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamMedium
	status.TextColor3 = Color3.fromRGB(198, 196, 186)
	status.TextSize = 13
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextYAlignment = Enum.TextYAlignment.Top
	status.Parent = frame
	addTextStroke(status, 0.68)

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.new(1, -112, 0, 20)
	hint.Position = UDim2.new(0, 110, 0, 29)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.Text = "F Toggle"
	hint.TextColor3 = Color3.fromRGB(150, 148, 140)
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.Parent = frame
	addTextStroke(hint, 0.75)

	local batteryTrack = Instance.new("Frame")
	batteryTrack.Name = "BatteryTrack"
	batteryTrack.Size = UDim2.new(1, -38, 0, 3)
	batteryTrack.Position = UDim2.new(0, 34, 0, 57)
	batteryTrack.BackgroundColor3 = Color3.fromRGB(72, 71, 67)
	batteryTrack.BackgroundTransparency = 0.35
	batteryTrack.BorderSizePixel = 0
	batteryTrack.Parent = frame

	local batteryFill = Instance.new("Frame")
	batteryFill.Name = "BatteryFill"
	batteryFill.Size = UDim2.new(1, 0, 1, 0)
	batteryFill.BackgroundColor3 = Color3.fromRGB(208, 205, 190)
	batteryFill.BorderSizePixel = 0
	batteryFill.Parent = batteryTrack

	local batteryText = Instance.new("TextLabel")
	batteryText.Name = "Battery"
	batteryText.Size = UDim2.new(1, -38, 0, 18)
	batteryText.Position = UDim2.new(0, 34, 0, 64)
	batteryText.BackgroundTransparency = 1
	batteryText.Font = Enum.Font.Gotham
	batteryText.TextColor3 = Color3.fromRGB(170, 168, 158)
	batteryText.TextSize = 12
	batteryText.TextXAlignment = Enum.TextXAlignment.Left
	batteryText.TextYAlignment = Enum.TextYAlignment.Top
	batteryText.Parent = frame
	addTextStroke(batteryText, 0.75)

	hudFrame = frame
	hudStatus = status
	hudBatteryText = batteryText
	hudBatteryFill = batteryFill
end

-- Update HUD text
function Flashlight.updateHUD()
	if not hudStatus or not hudBatteryText or not hudBatteryFill then return end

	local batteryPercent = math.floor((battery / MAX_BATTERY) * 100)
	local flashlightStatus = if isDead then "DEAD" else (if isOn then "ON" else "OFF")
	local warningColor = Color3.fromRGB(148, 42, 42)
	local normalColor = Color3.fromRGB(198, 196, 186)
	local dimColor = Color3.fromRGB(126, 124, 116)
	local statusColor = if isDead then warningColor else (if isOn then normalColor else dimColor)
	local batteryColor = if batteryPercent > 30 then Color3.fromRGB(208, 205, 190) else warningColor

	hudStatus.Text = flashlightStatus
	hudStatus.TextColor3 = statusColor
	hudBatteryText.Text = string.format("Battery  %d%%", batteryPercent)
	hudBatteryText.TextColor3 = batteryColor
	hudBatteryFill.Size = UDim2.new(math.clamp(battery / MAX_BATTERY, 0, 1), 0, 1, 0)
	hudBatteryFill.BackgroundColor3 = batteryColor
end

-- Toggle flashlight on/off
function Flashlight.toggle()
	if isDead or not isEquipped or viewModelSuppressed then return end
	local now = os.clock()
	if now - lastToggleTime < TOGGLE_COOLDOWN then
		return
	end
	lastToggleTime = now

	isOn = not isOn
	playClickSound(isOn)
	applyEquippedVisibility()

	print("🔦 Flashlight", if isOn then "ON" else "OFF")
	Flashlight.updateHUD()
end

-- Suppresses or restores the first-person flashlight model without changing equipment state.
function Flashlight.setViewModelSuppressed(suppressed: boolean)
	viewModelSuppressed = suppressed == true
	if viewModelSuppressed then
		setViewModelParent(nil)
	end
end

-- Applies whether the flashlight item is currently equipped.
function Flashlight.setEquipped(equipped: boolean)
	local nextEquipped = equipped == true
	if isEquipped == nextEquipped then
		applyEquippedVisibility()
		return
	end

	isEquipped = nextEquipped
	startViewModelTransition(isEquipped)
	applyEquippedVisibility()
end

local function createRemoteFlashlight()
	local model = Instance.new("Model")
	model.Name = "RemoteFlashlight"
	model.Parent = workspace

	local emitter = Instance.new("Part")
	emitter.Name = "RemoteFlashlightEmitter"
	emitter.Size = Vector3.new(0.16, 0.16, 0.16)
	emitter.Transparency = 1
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanTouch = false
	emitter.CanQuery = false
	emitter.CastShadow = false
	emitter.Parent = model

	local light = Instance.new("SpotLight")
	light.Name = "RemoteFlashlightBeam"
	light.Angle = SPOT_ANGLE
	light.Brightness = FULL_BRIGHTNESS * 0.55
	light.Range = FULL_RANGE
	light.Shadows = true
	light.Color = Color3.fromRGB(255, 245, 220)
	light.Face = Enum.NormalId.Front
	light.Parent = emitter

	local beam = Instance.new("Part")
	beam.Name = "RemoteFlashlightRay"
	beam.Size = Vector3.new(REMOTE_BEAM_THICKNESS, REMOTE_BEAM_THICKNESS, REMOTE_BEAM_LENGTH)
	beam.Transparency = 0.78
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 244, 206)
	beam.Parent = model

	return {
		model = model,
		emitter = emitter,
		light = light,
		beam = beam,
		lastSeen = os.clock(),
	}
end

local function destroyRemoteFlashlight(sourceUserId: string)
	local remote = remoteFlashlights[sourceUserId]
	if remote then
		if remote.model then
			remote.model:Destroy()
		end
		remoteFlashlights[sourceUserId] = nil
	end
end

local function handleRemoteFlashlight(payload)
	if typeof(payload) ~= "table" then return end
	if tonumber(payload.sourceUserId) == Players.LocalPlayer.UserId then return end

	local sourceUserId = tostring(payload.sourceUserId or "")
	if sourceUserId == "" then return end

	if payload.enabled ~= true then
		destroyRemoteFlashlight(sourceUserId)
		return
	end

	local origin = payload.origin
	local direction = payload.direction
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude <= 0 then
		destroyRemoteFlashlight(sourceUserId)
		return
	end

	local remote = remoteFlashlights[sourceUserId]
	if not remote then
		remote = createRemoteFlashlight()
		remoteFlashlights[sourceUserId] = remote
	end

	local unitDirection = direction.Unit
	local range = math.clamp(tonumber(payload.range) or FULL_RANGE, 8, FULL_RANGE)
	local brightnessScale = math.clamp(tonumber(payload.brightnessScale) or 1, 0.1, 1)
	local beamLength = math.min(REMOTE_BEAM_LENGTH, range)
	local beamCenter = origin + (unitDirection * (beamLength * 0.5))

	remote.lastSeen = os.clock()
	remote.emitter.CFrame = CFrame.lookAt(origin, origin + unitDirection)
	remote.light.Brightness = FULL_BRIGHTNESS * 0.55 * brightnessScale
	remote.light.Range = range
	remote.light.Enabled = true
	remote.beam.Size = Vector3.new(REMOTE_BEAM_THICKNESS, REMOTE_BEAM_THICKNESS, beamLength)
	remote.beam.CFrame = CFrame.lookAt(beamCenter, beamCenter + unitDirection)
	remote.beam.Transparency = 0.82 - (0.18 * brightnessScale)
end

local function updateRemoteFlashlights()
	local now = os.clock()
	for sourceUserId, remote in pairs(remoteFlashlights) do
		if now - (remote.lastSeen or 0) > REMOTE_STALE_TIME then
			destroyRemoteFlashlight(sourceUserId)
		end
	end
end

local function reportFlashlightState(dt: number)
	if not flashlightStateEvent then return end

	reportTimer += dt
	if reportTimer < FLASHLIGHT_REPORT_RATE then
		return
	end
	reportTimer = 0

	local enabled = shouldEmitLight()
	local camera = workspace.CurrentCamera
	local origin = flashlightPart and flashlightPart.Position
	local direction = camera and camera.CFrame.LookVector
	local brightnessScale = math.clamp(battery / MAX_BATTERY, 0, 1)

	if enabled and battery < DIMMING_THRESHOLD then
		brightnessScale = math.clamp(battery / DIMMING_THRESHOLD, 0.1, 1)
	end

	flashlightStateEvent:FireServer({
		enabled = enabled,
		origin = origin,
		direction = direction,
		range = flashlightSpot and flashlightSpot.Range or FULL_RANGE,
		brightnessScale = brightnessScale,
	})
end

-- Initializes flashlight input, viewmodel, lights, HUD, and remote replication.
function Flashlight.init()
	print("🔦 Flashlight initializing...")

	EquipmentClient.init()
	flashlightStateEvent = ReplicatedStorage:WaitForChild("FlashlightState", CLIENT_WAIT_TIMEOUT)
	flashlightPart, flashlightSpot = Flashlight.createFlashlight()

	local player = Players.LocalPlayer
	if player.Character then
		disableLocalCharacterShadows(player.Character)
	end
	player.CharacterAdded:Connect(disableLocalCharacterShadows)

	-- Create HUD
	Flashlight.createHUD()
	Flashlight.updateHUD()
	applyEquippedVisibility()

	EquipmentClient.onChanged(function(state)
		Flashlight.setEquipped(state.equippedItemId == "Flashlight")
	end)

	if flashlightStateEvent then
		flashlightStateEvent.OnClientEvent:Connect(handleRemoteFlashlight)
	end

	-- Listen for F key to toggle flashlight
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.F then
			Flashlight.toggle()
		end
	end)

	-- Start battery depletion + HUD update + camera-sync loop (runs every frame)
	local hudTimer = 0
	batteryConnection = RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if flashlightPart and camera then
			updateFlashlightTransform(camera, dt)
		end

		Flashlight.updateBattery(dt)
		reportFlashlightState(dt)
		updateRemoteFlashlights()

		-- Update HUD text every 0.5s to avoid spam
		hudTimer = hudTimer + dt
		if hudTimer >= 0.5 then
			hudTimer = 0
			Flashlight.updateHUD()
		end
	end)

	print(string.format("🔦 Flashlight ready (%.0f seconds of battery)", MAX_BATTERY))
	Flashlight.updateHUD()
end

-- Depletes battery each frame while the flashlight is on and equipped.
function Flashlight.updateBattery(dt: number)
	if not flashlightSpot or isDead then return end

	if isEquipped and isOn then
		battery = math.max(0, battery - dt)

		-- Dim the flashlight during the last 12 seconds as a warning
		if battery < DIMMING_THRESHOLD and battery > 0 then
			local ratio = math.max(0, battery / DIMMING_THRESHOLD)
			flashlightSpot.Brightness = FULL_BRIGHTNESS * ratio
			flashlightSpot.Range = (FULL_RANGE * 0.5) + (FULL_RANGE * 0.5 * ratio)
			if flashlightFill then
				flashlightFill.Brightness = CLOSE_FILL_BRIGHTNESS * ratio
				flashlightFill.Range = (CLOSE_FILL_RANGE * 0.55) + (CLOSE_FILL_RANGE * 0.45 * ratio)
			end
		elseif battery > 0 then
			flashlightSpot.Brightness = FULL_BRIGHTNESS
			flashlightSpot.Range = FULL_RANGE
			if flashlightFill then
				flashlightFill.Brightness = CLOSE_FILL_BRIGHTNESS
				flashlightFill.Range = CLOSE_FILL_RANGE
			end
		elseif battery <= 0 then
			isDead = true
			isOn = false
			applyEquippedVisibility()
			Flashlight.updateHUD()
			print("🔋 Flashlight battery depleted!")
		end
	end
end

-- Cleans up flashlight viewmodel, lights, HUD, and frame connections.
function Flashlight.destroy()
	if batteryConnection then
		batteryConnection:Disconnect()
		batteryConnection = nil
	end
	if flashlightPart then
		flashlightPart:Destroy()
		flashlightPart = nil
		flashlightSpot = nil
		flashlightFill = nil
	end
	if surfaceFillPart then
		surfaceFillPart:Destroy()
		surfaceFillPart = nil
		surfaceFillLight = nil
	end
	if flashlightViewModel then
		flashlightViewModel:Destroy()
		flashlightViewModel = nil
	end
	if handViewModel then
		handViewModel:Destroy()
		handViewModel = nil
	end
	table.clear(handParts)
	if hudFrame then
		hudFrame.Parent = nil
		hudFrame:Destroy()
		hudFrame = nil
		hudStatus = nil
		hudBatteryText = nil
		hudBatteryFill = nil
	end
end

-- Returns the current remaining battery seconds.
function Flashlight.getBattery(): number
	return battery
end

-- Returns the maximum battery seconds.
function Flashlight.getMaxBattery(): number
	return MAX_BATTERY
end

-- Returns whether the battery is depleted.
function Flashlight.getIsDead(): boolean
	return isDead
end

-- Returns whether the flashlight beam should currently be visible.
function Flashlight.getIsOn(): boolean
	return isEquipped and isOn
end

-- Returns whether the flashlight item is currently equipped.
function Flashlight.getIsEquipped(): boolean
	return isEquipped
end

return Flashlight

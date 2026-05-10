-- Client-side echolocation lighting and temporary reveal system
local SphereVisuals = {}

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Constants = require(game.ReplicatedStorage.Shared.Constants)
local SphereDetection = require(game.ReplicatedStorage.Shared.SphereDetection)
local InputHandler = require(script.Parent.InputHandler)
local Flashlight = require(script.Parent.Flashlight)

local lightPart: Part? = nil
local activeLight: PointLight? = nil
local initialized = false
local revealedParts = {}
local darknessFrame: Frame? = nil
local edgeFrames = {}
local overlayPulse = 0

local NOISE_THRESHOLD = 0.1
local REVEAL_TRANSPARENCY = 0.28

local REVEAL_TAGS = { "EcholocationReveal", "RevealTarget" }

local function createSensoryOverlay()
	local playerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SensoryOverlay"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = -20
	screenGui.Parent = playerGui

	local darkness = Instance.new("Frame")
	darkness.Name = "Darkness"
	darkness.Size = UDim2.fromScale(1, 1)
	darkness.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	darkness.BackgroundTransparency = 0.78
	darkness.BorderSizePixel = 0
	darkness.ZIndex = 1
	darkness.Parent = screenGui

	local function makeGradientEdge(name, size, position, rotation)
		local edge = Instance.new("Frame")
		edge.Name = name
		edge.Size = size
		edge.Position = position
		edge.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		edge.BackgroundTransparency = 0.12
		edge.BorderSizePixel = 0
		edge.ZIndex = 2
		edge.Parent = screenGui

		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.42, 0.28),
			NumberSequenceKeypoint.new(0.72, 0.72),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = edge

		table.insert(edgeFrames, edge)
	end

	makeGradientEdge("TopVignette", UDim2.new(1, 0, 0.46, 0), UDim2.fromScale(0, 0), 90)
	makeGradientEdge("BottomVignette", UDim2.new(1, 0, 0.5, 0), UDim2.new(0, 0, 0.5, 0), 270)
	makeGradientEdge("LeftVignette", UDim2.new(0.42, 0, 1, 0), UDim2.fromScale(0, 0), 0)
	makeGradientEdge("RightVignette", UDim2.new(0.42, 0, 1, 0), UDim2.new(0.58, 0, 0, 0), 180)

	darknessFrame = darkness
end

local function getTaggedRevealParts(): {BasePart}
	local taggedParts = {}
	local seen = {}

	for _, tagName in ipairs(REVEAL_TAGS) do
		for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
			if instance:IsA("BasePart") and not seen[instance] then
				seen[instance] = true
				table.insert(taggedParts, instance)
			end
		end
	end

	return taggedParts
end

local function getFallbackRevealFolder(): Instance?
	return workspace:FindFirstChild("RevealTargets")
		or workspace:FindFirstChild("Walls")
		or workspace:FindFirstChild("Prototype_Map")
end

function SphereVisuals.createLight(rootPart: BasePart): (Part, PointLight)
	local part = Instance.new("Part")
	part.Name = "EcholocationLight"
	part.Shape = Enum.PartType.Ball
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.CFrame = rootPart.CFrame
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Parent = workspace

	local light = Instance.new("PointLight")
	light.Name = "EcholocationPointLight"
	light.Brightness = 0
	light.Range = 0
	light.Shadows = true
	light.Color = Color3.fromRGB(255, 235, 165)
	light.Parent = part

	return part, light
end

function SphereVisuals.revealTouchedParts(center: Vector3, radius: number, noiseIntensity: number)
	local now = os.clock()
	local taggedParts = getTaggedRevealParts()
	local touchedParts
	if #taggedParts > 0 then
		touchedParts = SphereDetection.getPartsTouchedBySphere(center, radius, taggedParts)
	else
		local revealFolder = getFallbackRevealFolder()
		if not revealFolder then return end
		touchedParts = SphereDetection.getWallsTouchedBySphere(center, radius, revealFolder)
	end

	local targetTransparency = math.clamp(REVEAL_TRANSPARENCY - (noiseIntensity * 0.02), 0.05, REVEAL_TRANSPARENCY)

	for _, part in ipairs(touchedParts) do
		if part.Name ~= "Baseplate" then
			local data = revealedParts[part]
			if not data then
				data = {
					originalTransparency = part.Transparency,
					originalColor = part.Color,
					originalMaterial = part.Material,
					revealTransparency = math.min(part.Transparency, targetTransparency),
					lastSeen = now,
				}

				local highlight = Instance.new("Highlight")
				highlight.Name = "EcholocationOutline"
				highlight.Adornee = part
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.FillTransparency = 1
				highlight.OutlineColor = Color3.fromRGB(155, 220, 255)
				highlight.OutlineTransparency = 0.18
				highlight.Parent = part
				data.highlight = highlight
				revealedParts[part] = data
			end

			data.revealTransparency = math.min(data.revealTransparency, targetTransparency)
			data.lastSeen = now
			part.Transparency = data.revealTransparency
			part.Color = data.originalColor:Lerp(Color3.fromRGB(145, 215, 245), math.clamp(noiseIntensity * 0.08, 0.16, 0.42))
			if noiseIntensity > 0.6 then
				part.Material = Enum.Material.Neon
			end
			if data.highlight then
				data.highlight.OutlineTransparency = 0.18
			end
		end
	end
end

function SphereVisuals.fadeRevealedParts()
	local now = os.clock()
	local fadeTime = Constants.WALL_VISIBILITY_FADE_TIME or 2

	for part, data in pairs(revealedParts) do
		if not part.Parent then
			revealedParts[part] = nil
			continue
		end

		local elapsed = now - data.lastSeen
		if elapsed >= fadeTime then
			part.Transparency = data.originalTransparency
			part.Color = data.originalColor
			part.Material = data.originalMaterial
			if data.highlight then
				data.highlight:Destroy()
			end
			revealedParts[part] = nil
		else
			local alpha = elapsed / fadeTime
			part.Transparency = data.revealTransparency + ((data.originalTransparency - data.revealTransparency) * alpha)
			part.Color = data.originalColor:Lerp(Color3.fromRGB(145, 215, 245), (1 - alpha) * 0.35)
			if data.highlight then
				data.highlight.OutlineTransparency = 0.18 + (alpha * 0.72)
			end
		end
	end
end

function SphereVisuals.updateSensoryOverlay(noiseInfo)
	if not darknessFrame then return end

	local noiseAlpha = math.clamp((noiseInfo.radius or 0) / Constants.SPHERE_MAX_RADIUS, 0, 1)
	if noiseInfo.intensity > NOISE_THRESHOLD then
		overlayPulse = math.max(overlayPulse, noiseAlpha)
	end
	overlayPulse = math.max(0, overlayPulse - 0.025)

	local flashlightRelief = if Flashlight.getIsOn() and not Flashlight.getIsDead() then 0.12 else 0
	local targetTransparency = math.clamp(0.72 + flashlightRelief + (overlayPulse * 0.18), 0.68, 0.92)
	darknessFrame.BackgroundTransparency = darknessFrame.BackgroundTransparency
		+ ((targetTransparency - darknessFrame.BackgroundTransparency) * 0.08)

	local edgeTransparency = math.clamp(0.1 + flashlightRelief + (overlayPulse * 0.24), 0.08, 0.48)
	for _, edge in ipairs(edgeFrames) do
		edge.BackgroundTransparency = edge.BackgroundTransparency
			+ ((edgeTransparency - edge.BackgroundTransparency) * 0.08)
	end
end

function SphereVisuals.updateLight()
	local character = game.Players.LocalPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end

	local rootPart = character.HumanoidRootPart

	if not lightPart then
		lightPart, activeLight = SphereVisuals.createLight(rootPart)
		print("Echolocation light created")
	end

	local lp = lightPart
	local al = activeLight
	if not lp or not al then return end

	local movementSpeed = InputHandler.getMovementSpeed()
	local micVolume = InputHandler.getMicVolume()
	local noiseInfo = InputHandler.getNoiseInfo()
	local soundRadius = math.max(noiseInfo.radius, SphereDetection.calculateSphereRadius(movementSpeed, micVolume, Constants) * 0.25)
	local totalNoise = noiseInfo.intensity

	lp.Position = rootPart.Position + Vector3.new(0, 2, 0)

	if totalNoise > NOISE_THRESHOLD then
		al.Range = soundRadius
		al.Brightness = math.clamp(noiseInfo.intensity * 0.45, 0, Constants.MAX_BRIGHTNESS)
		SphereVisuals.revealTouchedParts(rootPart.Position, soundRadius, totalNoise)
	else
		al.Range = 0
		al.Brightness = 0
	end

	SphereVisuals.updateSensoryOverlay(noiseInfo)
	SphereVisuals.fadeRevealedParts()
end

function SphereVisuals.init()
	if initialized then return end
	initialized = true

	InputHandler.init()
	createSensoryOverlay()

	local player = game.Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	print("Player locked into first-person mode")

	Flashlight.init()

	local function fixCharacterParts(characterToFix)
		local cp = characterToFix:FindFirstChild("CollisionPart")
		if cp then cp:Destroy() end

		local hrp = characterToFix:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Transparency = 1 end

		characterToFix.ChildAdded:Connect(function(child)
			if child.Name == "CollisionPart" then child:Destroy() end
		end)
	end

	if player.Character then fixCharacterParts(player.Character) end
	player.CharacterAdded:Connect(fixCharacterParts)

	RunService.RenderStepped:Connect(function()
		SphereVisuals.updateLight()
	end)

	print("Echolocation reveal system initialized")
end

return SphereVisuals

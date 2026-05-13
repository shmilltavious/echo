-- Client-side echolocation lighting and temporary reveal system
local SphereVisuals = {}

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(game.ReplicatedStorage.Shared.Constants)
local SphereDetection = require(game.ReplicatedStorage.Shared.SphereDetection)
local InputHandler = require(script.Parent.InputHandler)
local Flashlight = require(script.Parent.Flashlight)

local lightPart: Part? = nil
local activeLight: PointLight? = nil
local initialized = false
local revealedParts = {}
local remotePulses = {}
local darknessFrame: Frame? = nil
local edgeFrames = {}
local overlayPulse = 0

local NOISE_THRESHOLD = 0.025
local MIN_REVEAL_STRENGTH = 0.03
local FAR_FADE_TIME_MULTIPLIER = 0.35
local CLOSE_FADE_TIME_MULTIPLIER = 1.35
local OBJECTIVE_FADE_BONUS = 0.25
local REMOTE_PULSE_FADE_TIME = 0.5
local REMOTE_PULSE_HEIGHT = 2

local REVEAL_TAGS = { "EcholocationReveal", "RevealTarget" }

local objectiveColors = {
	Keycard = Color3.fromRGB(95, 210, 255),
	Fuse = Color3.fromRGB(255, 214, 92),
	RepairPanel = Color3.fromRGB(115, 255, 170),
	EscapeDoor = Color3.fromRGB(210, 210, 230),
	DecoyBottle = Color3.fromRGB(130, 235, 225),
	AudioLandmark = Color3.fromRGB(255, 140, 66),
}

local function getRevealColor(part: BasePart): Color3
	local objectiveName = part:GetAttribute("ObjectiveName")
	if typeof(objectiveName) == "string" and objectiveColors[objectiveName] then
		return objectiveColors[objectiveName]
	end

	return Color3.fromRGB(150, 220, 255)
end

local function isObjectiveLike(part: BasePart): boolean
	return part:GetAttribute("ObjectiveName") ~= nil
		or part:GetAttribute("EquipSlot") ~= nil
		or part.Name:find("Interact") ~= nil
end

local function isCollected(part: BasePart): boolean
	if part:GetAttribute("Collected") then
		return true
	end

	local current = part.Parent
	while current and current ~= workspace do
		if current:GetAttribute("Collected") then
			return true
		end
		current = current.Parent
	end

	return false
end

local function clearReveal(part: BasePart, data)
	if data and data.highlight then
		data.highlight:Destroy()
	end

	local leftoverHighlight = part:FindFirstChild("EcholocationOutline")
	if leftoverHighlight and leftoverHighlight:IsA("Highlight") then
		leftoverHighlight:Destroy()
	end

	revealedParts[part] = nil
end

local function lerpNumber(from: number, to: number, alpha: number): number
	return from + ((to - from) * alpha)
end

local function getLargestAxis(size: Vector3): number
	return math.max(size.X, math.max(size.Y, size.Z))
end

local function getRevealMetrics(part: BasePart, center: Vector3, radius: number, noiseInfo): (number, number)
	if radius <= 0 then
		return 0, 0
	end

	local distance = SphereDetection.getDistanceFromPart(center, part)
	if distance > radius then
		return 0, 0
	end

	local distanceAlpha = math.clamp(1 - (distance / radius), 0, 1)
	local distanceFalloff = distanceAlpha ^ 1.45
	local intensity = math.clamp((noiseInfo.intensity or 0) / 2.6, 0.16, 1)
	local voiceVolume = math.clamp(noiseInfo.voiceVolume or 0, 0, 1)
	local sourcePower = math.clamp(0.2 + (intensity * 0.52) + (voiceVolume * 0.28), 0.2, 1)

	local largestAxis = getLargestAxis(part.Size)
	local sizePenalty = 1
	if largestAxis > radius * 1.25 then
		local centerDistance = (part.Position - center).Magnitude
		if centerDistance > radius then
			sizePenalty = math.clamp(radius / centerDistance, 0.18, 1)
		end
	end

	return math.clamp(distanceFalloff * sourcePower * sizePenalty, 0, 1), distanceAlpha
end

local function getHighlightTransparency(part: BasePart, strength: number): (number, number)
	if isObjectiveLike(part) then
		return lerpNumber(0.9, 0.64, strength), lerpNumber(0.48, 0.0, strength)
	end

	return lerpNumber(0.96, 0.78, strength), lerpNumber(0.72, 0.02, strength)
end

local function getFadeDuration(part: BasePart, distanceAlpha: number): number
	local baseFadeTime = Constants.WALL_VISIBILITY_FADE_TIME or 2
	local fadeDuration = baseFadeTime
		* lerpNumber(FAR_FADE_TIME_MULTIPLIER, CLOSE_FADE_TIME_MULTIPLIER, distanceAlpha ^ 0.85)

	if isObjectiveLike(part) then
		fadeDuration += OBJECTIVE_FADE_BONUS
	end

	return fadeDuration
end

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

local function createRemotePulseLight(): (Part, PointLight)
	local part = Instance.new("Part")
	part.Name = "CoopEcholocationLight"
	part.Shape = Enum.PartType.Ball
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Transparency = 1
	part.Parent = workspace

	local light = Instance.new("PointLight")
	light.Name = "CoopEcholocationPointLight"
	light.Brightness = 0
	light.Range = 0
	light.Shadows = true
	light.Color = Color3.fromRGB(165, 225, 255)
	light.Parent = part

	return part, light
end

function SphereVisuals.revealTouchedParts(center: Vector3, radius: number, noiseInfo)
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

	for _, part in ipairs(touchedParts) do
		if part.Name ~= "Baseplate" then
			if isCollected(part) then
				clearReveal(part, revealedParts[part])
				continue
			end

			local revealStrength, distanceAlpha = getRevealMetrics(part, center, radius, noiseInfo)
			if revealStrength < MIN_REVEAL_STRENGTH then
				continue
			end

			local revealColor = getRevealColor(part)
			local fillTransparency, outlineTransparency = getHighlightTransparency(part, revealStrength)
			local fadeDuration = getFadeDuration(part, distanceAlpha)

			local data = revealedParts[part]
			if not data then
				data = {
					originalTransparency = part.Transparency,
					originalColor = part.Color,
					originalMaterial = part.Material,
					revealColor = revealColor,
					revealStrength = revealStrength,
					fadeDuration = fadeDuration,
					lastSeen = now,
				}

				local highlight = Instance.new("Highlight")
				highlight.Name = "EcholocationOutline"
				highlight.Adornee = part
				highlight.DepthMode = Enum.HighlightDepthMode.Occluded
				highlight.FillColor = revealColor
				highlight.FillTransparency = fillTransparency
				highlight.OutlineColor = revealColor
				highlight.OutlineTransparency = outlineTransparency
				highlight.Parent = part
				data.highlight = highlight
				revealedParts[part] = data
			end

			data.revealColor = revealColor
			data.revealStrength = revealStrength
			data.fadeDuration = fadeDuration
			data.lastSeen = now
			if data.highlight then
				data.highlight.FillColor = revealColor
				data.highlight.OutlineColor = revealColor
				data.highlight.FillTransparency = fillTransparency
				data.highlight.OutlineTransparency = outlineTransparency
			end
		end
	end
end

function SphereVisuals.fadeRevealedParts()
	local now = os.clock()

	for part, data in pairs(revealedParts) do
		if not part.Parent then
			revealedParts[part] = nil
			continue
		end
		if isCollected(part) then
			clearReveal(part, data)
			continue
		end

		local elapsed = now - data.lastSeen
		local fadeTime = data.fadeDuration or Constants.WALL_VISIBILITY_FADE_TIME or 2
		if elapsed >= fadeTime then
			if data.highlight then
				data.highlight:Destroy()
			end
			revealedParts[part] = nil
		else
			local alpha = elapsed / fadeTime
			local revealStrength = data.revealStrength or 0.35
			if data.highlight then
				local fillTransparency, outlineTransparency = getHighlightTransparency(part, revealStrength)
				data.highlight.FillTransparency = fillTransparency + ((1 - fillTransparency) * alpha)
				data.highlight.OutlineTransparency = outlineTransparency + ((1 - outlineTransparency) * alpha)
			end
		end
	end
end

function SphereVisuals.handleRemotePulse(payload)
	if typeof(payload) ~= "table" or payload.type ~= "CoopEcholocationPulse" then
		return
	end

	if tonumber(payload.sourceUserId) == Players.LocalPlayer.UserId then
		return
	end

	local position = payload.position
	if typeof(position) ~= "Vector3" then
		return
	end

	local radius = math.clamp(tonumber(payload.radius) or 0, 0, Constants.SPHERE_MAX_RADIUS)
	local intensity = math.clamp(tonumber(payload.intensity) or 0, 0, 5)
	if radius <= 0 or intensity <= NOISE_THRESHOLD then
		return
	end

	local sourceUserId = tostring(payload.sourceUserId or "unknown")
	local pulse = remotePulses[sourceUserId]
	if not pulse then
		local part, light = createRemotePulseLight()
		pulse = {
			part = part,
			light = light,
			lastSeen = 0,
			baseBrightness = 0,
		}
		remotePulses[sourceUserId] = pulse
	end

	local noiseInfo = {
		intensity = intensity,
		radius = radius,
		movementState = payload.movementState or "walk",
		hasVoice = payload.hasVoice == true,
		voiceVolume = math.clamp(tonumber(payload.voiceVolume) or 0, 0, 1),
	}

	pulse.lastSeen = os.clock()
	pulse.part.Position = position + Vector3.new(0, REMOTE_PULSE_HEIGHT, 0)
	pulse.light.Range = radius
	pulse.baseBrightness = math.clamp(intensity * 0.42, 0, math.min(Constants.MAX_BRIGHTNESS, 1.35))
	pulse.light.Brightness = pulse.baseBrightness
	SphereVisuals.revealTouchedParts(position, radius, noiseInfo)
end

function SphereVisuals.updateRemotePulses()
	local now = os.clock()
	for sourceUserId, pulse in pairs(remotePulses) do
		local age = now - (pulse.lastSeen or 0)
		if age >= REMOTE_PULSE_FADE_TIME then
			if pulse.part then
				pulse.part:Destroy()
			end
			remotePulses[sourceUserId] = nil
		else
			local alpha = 1 - (age / REMOTE_PULSE_FADE_TIME)
			if pulse.light then
				pulse.light.Brightness = (pulse.baseBrightness or 0) * math.clamp(alpha, 0, 1)
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
		al.Brightness = math.clamp(noiseInfo.intensity * 0.55, 0, math.min(Constants.MAX_BRIGHTNESS, 1.65))
		SphereVisuals.revealTouchedParts(rootPart.Position, soundRadius, noiseInfo)
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
		local function keepCollisionPartInvisible(instance)
			if instance.Name == "CollisionPart" and instance:IsA("BasePart") then
				instance.Transparency = 1
				instance.CanCollide = true
				instance.CanQuery = false
			end
		end

		local cp = characterToFix:FindFirstChild("CollisionPart")
		if cp then keepCollisionPartInvisible(cp) end

		local hrp = characterToFix:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Transparency = 1 end

		characterToFix.ChildAdded:Connect(keepCollisionPartInvisible)
	end

	if player.Character then fixCharacterParts(player.Character) end
	player.CharacterAdded:Connect(fixCharacterParts)

	RunService.RenderStepped:Connect(function()
		SphereVisuals.updateLight()
		SphereVisuals.updateRemotePulses()
	end)

	local pulseEvent = ReplicatedStorage:WaitForChild("EcholocationPulse", 10)
	if pulseEvent then
		pulseEvent.OnClientEvent:Connect(SphereVisuals.handleRemotePulse)
	else
		warn("EcholocationPulse RemoteEvent not found. Co-op echolocation visuals disabled.")
	end

	print("Echolocation reveal system initialized")
end

return SphereVisuals

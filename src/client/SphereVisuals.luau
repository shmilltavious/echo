-- Client-side echolocation lighting system
local SphereVisuals = {}

local RunService = game:GetService("RunService")
local Constants = require(game.ReplicatedStorage.Shared.Constants)
local SphereDetection = require(game.ReplicatedStorage.Shared.SphereDetection)
local InputHandler = require(script.Parent.InputHandler)

-- State
local lightPart: Part
local activeLight: Light

-- Create the echolocation light
function SphereVisuals.createLight(rootPart: BasePart): (Part, Light)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.CFrame = rootPart.CFrame
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1 -- invisible, just holds the light
	part.Parent = workspace
	
	local light = Instance.new("PointLight")
	light.Brightness = 0
	light.Range = 0
	light.Shadows = true -- This prevents light from bleeding through walls
	light.Color = Color3.fromRGB(255, 235, 165) -- Warm yellowish hue
	light.Parent = part
	
	return part, light
end

-- Update light position and intensity based on sound input
function SphereVisuals.updateLight()
	local character = game.Players.LocalPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	
	local rootPart = character.HumanoidRootPart

	if not lightPart then
		lightPart, activeLight = SphereVisuals.createLight(rootPart)
		print("💡 Light created at", lightPart.Position)
	end
	
	local movementSpeed = InputHandler.getMovementSpeed()
	local micVolume = InputHandler.getMicVolume()
	
	-- Calculate light radius based on sound (movement + voice)
	local soundRadius = SphereDetection.calculateSphereRadius(movementSpeed, micVolume, Constants)
	
	-- Update light position
	lightPart.Position = rootPart.Position + Vector3.new(0, 2, 0) -- Move slightly up to eye level
	
	-- Scale light brightness and range with sound intensity
	local totalSound = (movementSpeed / 16 * 0.1) + (micVolume * 20)
	activeLight.Range = soundRadius
	activeLight.Brightness = math.clamp(totalSound, 0, Constants.MAX_BRIGHTNESS) 
	
	print("Movement:", movementSpeed, "| Mic:", micVolume, "| Range:", soundRadius, "| Brightness:", activeLight.Brightness)
end

-- Initialize the system
function SphereVisuals.init()
	InputHandler.init()
	game.Players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
	
	-- Clean up Realism Mod artifacts that clip into the character
	local function fixCharacterParts(character)
		local cp = character:FindFirstChild("CollisionPart")
		if cp then cp:Destroy() end
		
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.Transparency = 1 end
		
		character.ChildAdded:Connect(function(child)
			if child.Name == "CollisionPart" then child:Destroy() end
		end)
	end
	
	local player = game.Players.LocalPlayer
	if player.Character then fixCharacterParts(player.Character) end
	player.CharacterAdded:Connect(fixCharacterParts)
	
	RunService.RenderStepped:Connect(function()
		SphereVisuals.updateLight()
	end)
	
	print("✅ Echolocation lighting system initialized - pitch black world")
end

return SphereVisuals

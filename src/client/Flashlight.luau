-- Battery-powered flashlight with limited runtime and toggle
local Flashlight = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Constants
local MAX_BATTERY = 60 -- 60 seconds of total flashlight usage
local FULL_BRIGHTNESS = 4
local FULL_RANGE = 20
local SPOT_ANGLE = 45
local DIMMING_THRESHOLD = 12 -- last 12 seconds = dimming phase

-- State
local battery = MAX_BATTERY
local flashlightPart: Part? = nil
local flashlightSpot: SpotLight? = nil
local batteryConnection: RBXScriptConnection? = nil
local isDead = false
local isOn = true
local hudLabel: TextLabel? = nil
local hudFrame: Frame? = nil

-- Create the flashlight as a SpotLight attached to the camera (follows view direction)
function Flashlight.createFlashlight(): (Part, SpotLight)
	local camera = workspace.CurrentCamera

	local part = Instance.new("Part")
	part.Name = "Flashlight"
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Transparency = 1 -- invisible
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true
	part.Parent = camera

	local spotLight = Instance.new("SpotLight")
	spotLight.Name = "FlashlightBeam"
	spotLight.Brightness = FULL_BRIGHTNESS
	spotLight.Range = FULL_RANGE
	spotLight.Angle = SPOT_ANGLE
	spotLight.Shadows = true
	spotLight.Color = Color3.fromRGB(255, 245, 220) -- Warm white
	spotLight.Face = Enum.NormalId.Front -- Shines forward from camera
	spotLight.Parent = part

	return part, spotLight
end

-- Create HUD in bottom-right corner
function Flashlight.createHUD()
	local player = Players.LocalPlayer
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FlashlightHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "HudFrame"
	frame.Size = UDim2.new(0, 220, 0, 80)
	frame.Position = UDim2.new(1, -240, 1, -100) -- bottom-right with padding
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "HudText"
	label.Size = UDim2.new(1, -10, 1, -10)
	label.Position = UDim2.new(0, 5, 0, 5)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(200, 200, 200)
	label.TextSize = 14
	label.Font = Enum.Font.GothamMedium
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	label.Parent = frame

	hudFrame = frame
	hudLabel = label
end

-- Update HUD text
function Flashlight.updateHUD()
	if not hudLabel then return end

	local batteryPercent = math.floor((battery / MAX_BATTERY) * 100)
	local flashlightStatus = if isDead then "DEAD" else (if isOn then "ON" else "OFF")
	local batteryColor = if batteryPercent > 30 then "255, 255, 255" else "255, 80, 80"

	hudLabel.Text = string.format(
		"[F] Flashlight: %s\nBattery: <font color=\"rgb(%s)\">%d%%</font>\n[E] Interact",
		flashlightStatus,
		batteryColor,
		batteryPercent
	)
	hudLabel.RichText = true
end

-- Toggle flashlight on/off
function Flashlight.toggle()
	if isDead then return end

	isOn = not isOn

	if flashlightSpot then
		flashlightSpot.Enabled = isOn
	end

	print("🔦 Flashlight", if isOn then "ON" else "OFF")
	Flashlight.updateHUD()
end

-- Initialize the flashlight system
function Flashlight.init()
	print("🔦 Flashlight initializing...")

	flashlightPart, flashlightSpot = Flashlight.createFlashlight()

	-- Create HUD
	Flashlight.createHUD()
	Flashlight.updateHUD()

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
		-- Sync flashlight position/direction to current camera
		if flashlightPart then
			flashlightPart.CFrame = workspace.CurrentCamera.CFrame
		end

		Flashlight.updateBattery(dt)

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

-- Deplete battery each frame based on delta time (only when ON)
function Flashlight.updateBattery(dt: number)
	if not flashlightSpot or isDead then return end

	if isOn then
		battery = math.max(0, battery - dt)

		-- Dim the flashlight during the last 12 seconds as a warning
		if battery < DIMMING_THRESHOLD and battery > 0 then
			local ratio = math.max(0, battery / DIMMING_THRESHOLD)
			flashlightSpot.Brightness = FULL_BRIGHTNESS * ratio
			flashlightSpot.Range = (FULL_RANGE * 0.5) + (FULL_RANGE * 0.5 * ratio)
		elseif battery <= 0 then
			flashlightSpot.Enabled = false
			isDead = true
			isOn = false
			Flashlight.updateHUD()
			print("🔋 Flashlight battery depleted!")
		end
	end
end

-- Clean up flashlight objects
function Flashlight.destroy()
	if batteryConnection then
		batteryConnection:Disconnect()
		batteryConnection = nil
	end
	if flashlightPart then
		flashlightPart:Destroy()
		flashlightPart = nil
		flashlightSpot = nil
	end
	if hudFrame then
		hudFrame.Parent = nil
		hudFrame:Destroy()
		hudFrame = nil
		hudLabel = nil
	end
end

-- Getters
function Flashlight.getBattery(): number
	return battery
end

function Flashlight.getMaxBattery(): number
	return MAX_BATTERY
end

function Flashlight.getIsDead(): boolean
	return isDead
end

function Flashlight.getIsOn(): boolean
	return isOn
end

return Flashlight
-- Battery-powered flashlight with limited runtime and toggle
local Flashlight = {}

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Constants
local MAX_BATTERY = 60 -- 60 seconds of total flashlight usage
local FULL_BRIGHTNESS = 8
local FULL_RANGE = 44
local CLOSE_FILL_BRIGHTNESS = 0.75
local CLOSE_FILL_RANGE = 12
local SPOT_ANGLE = 58
local DIMMING_THRESHOLD = 12 -- last 12 seconds = dimming phase

-- State
local battery = MAX_BATTERY
local flashlightPart: Part? = nil
local flashlightSpot: SpotLight? = nil
local flashlightFill: PointLight? = nil
local batteryConnection: RBXScriptConnection? = nil
local isDead = false
local isOn = true
local hudFrame: Frame? = nil
local hudStatus: TextLabel? = nil
local hudBatteryText: TextLabel? = nil
local hudBatteryFill: Frame? = nil

local function addTextStroke(label: TextLabel, transparency: number)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = transparency
end

-- Create the flashlight as local lights that follow the camera.
function Flashlight.createFlashlight(): (Part, SpotLight)
	local part = Instance.new("Part")
	part.Name = "Flashlight"
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(0.2, 0.2, 0.2)
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
	spotLight.Face = Enum.NormalId.Front -- Shines forward from camera
	spotLight.Parent = part

	local fillLight = Instance.new("PointLight")
	fillLight.Name = "FlashlightCloseFill"
	fillLight.Brightness = CLOSE_FILL_BRIGHTNESS
	fillLight.Range = CLOSE_FILL_RANGE
	fillLight.Shadows = false
	fillLight.Color = Color3.fromRGB(255, 240, 210)
	fillLight.Parent = part
	flashlightFill = fillLight

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
	frame.Size = UDim2.new(0, 252, 0, 86)
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -24, 1, -30)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
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
	if isDead then return end

	isOn = not isOn

	if flashlightSpot then
		flashlightSpot.Enabled = isOn
	end
	if flashlightFill then
		flashlightFill.Enabled = isOn
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
		local camera = workspace.CurrentCamera
		if flashlightPart and camera then
			flashlightPart.CFrame = camera.CFrame * CFrame.new(0.35, -0.2, -0.85)
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
			flashlightSpot.Enabled = false
			if flashlightFill then
				flashlightFill.Enabled = false
			end
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
		flashlightFill = nil
	end
	if hudFrame then
		hudFrame.Parent = nil
		hudFrame:Destroy()
		hudFrame = nil
		hudStatus = nil
		hudBatteryText = nil
		hudBatteryFill = nil
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

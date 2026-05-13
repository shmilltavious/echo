local SpectateClient = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Flashlight = require(script.Parent.Flashlight)

local player = Players.LocalPlayer
local active = false
local currentIndex = 1
local currentTarget: Player? = nil
local renderConnection: RBXScriptConnection? = nil
local inputConnection: RBXScriptConnection? = nil
local screenGui: ScreenGui? = nil
local targetLabel: TextLabel? = nil

local function getSpectateTargets()
	local targets = {}
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player and candidate:GetAttribute("Escaped") ~= true then
			local character = candidate.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				table.insert(targets, candidate)
			end
		end
	end
	return targets
end

local function isValidSpectateTarget(targetPlayer: Player?): boolean
	if not targetPlayer or targetPlayer.Parent ~= Players then
		return false
	end
	if targetPlayer == player or targetPlayer:GetAttribute("Escaped") == true then
		return false
	end

	local character = targetPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function createGui()
	if screenGui then return end

	local playerGui = player:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpectateHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 45
	gui.Parent = playerGui

	local label = Instance.new("TextLabel")
	label.Name = "Target"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -26)
	label.Size = UDim2.new(0, 360, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(182, 180, 170)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.55
	label.TextSize = 13
	label.Text = ""
	label.Parent = gui

	screenGui = gui
	targetLabel = label
end

local function setCameraToTarget(targetPlayer)
	local camera = workspace.CurrentCamera
	local character = targetPlayer and targetPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or not humanoid then
		return false
	end

	player.CameraMode = Enum.CameraMode.Classic
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = humanoid
	currentTarget = targetPlayer
	if targetLabel then
		targetLabel.Text = "SPECTATING  " .. targetPlayer.Name .. "   Q / E / CLICK TO CYCLE"
	end
	return true
end

local function selectTarget(index: number): boolean
	local targets = getSpectateTargets()
	if #targets == 0 then
		currentTarget = nil
		if targetLabel then
			targetLabel.Text = "NO SURVIVORS REMAIN"
		end
		return false
	end

	currentIndex = ((index - 1) % #targets) + 1
	return setCameraToTarget(targets[currentIndex])
end

local function refreshTarget()
	if isValidSpectateTarget(currentTarget) then
		return setCameraToTarget(currentTarget)
	end

	local targets = getSpectateTargets()
	if #targets == 0 then
		currentTarget = nil
		if targetLabel then
			targetLabel.Text = "NO SURVIVORS REMAIN"
		end
		return false
	end

	currentIndex = math.clamp(currentIndex, 1, #targets)
	return selectTarget(currentIndex)
end

local function cycleTarget(direction: number)
	if not active then return end
	selectTarget(currentIndex + direction)
end

function SpectateClient.start(): boolean
	active = true
	createGui()
	Flashlight.destroy()

	local targets = getSpectateTargets()
	if #targets > 0 then
		currentIndex = math.random(1, #targets)
	end

	if not selectTarget(currentIndex) then
		return false
	end

	if not renderConnection then
		renderConnection = RunService.RenderStepped:Connect(function()
			if not active then return end
			refreshTarget()
		end)
	end

	if not inputConnection then
		inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or not active then return end
			if input.KeyCode == Enum.KeyCode.Q then
				cycleTarget(-1)
			elseif input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Tab then
				cycleTarget(1)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				cycleTarget(1)
			end
		end)
	end

	return true
end

return SpectateClient

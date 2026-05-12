-- Client-side caught/jumpscare feedback for the monster reset loop
local MonsterFeedback = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local initialized = false
local caughtEvent = ReplicatedStorage:WaitForChild("MonsterCaughtPlayer", 10)
local screenGui: ScreenGui? = nil
local blackout: Frame? = nil
local title: TextLabel? = nil

local function createGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MonsterFeedback"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Blackout"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Parent = gui

	local redFlash = Instance.new("Frame")
	redFlash.Name = "RedFlash"
	redFlash.Size = UDim2.fromScale(1, 1)
	redFlash.BackgroundColor3 = Color3.fromRGB(80, 0, 0)
	redFlash.BackgroundTransparency = 1
	redFlash.BorderSizePixel = 0
	redFlash.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "CaughtText"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(0, 420, 0, 80)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Garamond
	label.Text = "SILENCE BROKEN"
	label.TextColor3 = Color3.fromRGB(210, 205, 195)
	label.TextSize = 34
	label.TextTransparency = 1
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.25
	label.Parent = frame

	screenGui = gui
	blackout = frame
	title = label
end

local function playCaughtFeedback()
	if not screenGui or not blackout or not title then return end

	local redFlash = blackout:FindFirstChild("RedFlash")
	screenGui.Enabled = true
	blackout.BackgroundTransparency = 1
	title.TextTransparency = 1
	if redFlash and redFlash:IsA("Frame") then
		redFlash.BackgroundTransparency = 0.35
	end

	local camera = workspace.CurrentCamera
	if camera then
		local originalFov = camera.FieldOfView
		camera.FieldOfView = math.min(originalFov + 10, 90)
		task.delay(0.35, function()
			if camera then
				camera.FieldOfView = originalFov
			end
		end)
	end

	TweenService:Create(blackout, TweenInfo.new(0.18), { BackgroundTransparency = 0.08 }):Play()
	TweenService:Create(title, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
	if redFlash and redFlash:IsA("Frame") then
		TweenService:Create(redFlash, TweenInfo.new(0.28), { BackgroundTransparency = 1 }):Play()
	end

	task.delay(1.1, function()
		if not screenGui or not blackout or not title then return end
		TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(blackout, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		if screenGui then
			screenGui.Enabled = false
		end
	end)
end

function MonsterFeedback.init()
	if initialized then return end
	initialized = true

	createGui()

	if caughtEvent then
		caughtEvent.OnClientEvent:Connect(playCaughtFeedback)
	end
end

return MonsterFeedback

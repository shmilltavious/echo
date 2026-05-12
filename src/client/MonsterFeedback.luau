-- Client-side death/reset and escape success feedback
local MonsterFeedback = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local initialized = false
local caughtEvent = ReplicatedStorage:WaitForChild("MonsterCaughtPlayer", 10)
local gameOutcomeEvent = ReplicatedStorage:WaitForChild("GameOutcome", 10)
local screenGui: ScreenGui? = nil
local blackout: Frame? = nil
local title: TextLabel? = nil
local subtitle: TextLabel? = nil
local statLine: TextLabel? = nil
local sessionStartedAt = os.clock()

local SOUND_IDS = {
	death = "rbxasset://sounds/uuhhh.mp3",
	success = "rbxassetid://9112854440",
}

local function formatTime(seconds: number): string
	local safeSeconds = math.max(0, math.floor(seconds))
	local minutes = math.floor(safeSeconds / 60)
	local remainder = safeSeconds % 60
	return string.format("%d:%02d", minutes, remainder)
end

local function playUiSound(name: string, soundId: string, volume: number, playbackSpeed: number?)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.Parent = SoundService
	sound:Play()
	task.delay(5, function()
		if sound then
			sound:Destroy()
		end
	end)
end

local function addTextStroke(label: TextLabel, transparency: number)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = transparency
end

local function createGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "MonsterFeedback"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 80
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
	redFlash.BackgroundColor3 = Color3.fromRGB(85, 0, 0)
	redFlash.BackgroundTransparency = 1
	redFlash.BorderSizePixel = 0
	redFlash.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "OutcomeTitle"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.43)
	label.Size = UDim2.new(0, 520, 0, 62)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Garamond
	label.Text = ""
	label.TextColor3 = Color3.fromRGB(220, 215, 205)
	label.TextSize = 38
	label.TextTransparency = 1
	label.TextWrapped = true
	addTextStroke(label, 0.25)
	label.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.Name = "OutcomeSubtitle"
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.51)
	sub.Size = UDim2.new(0, 540, 0, 36)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.Text = ""
	sub.TextColor3 = Color3.fromRGB(180, 178, 168)
	sub.TextSize = 15
	sub.TextTransparency = 1
	sub.TextWrapped = true
	addTextStroke(sub, 0.55)
	sub.Parent = frame

	local stats = Instance.new("TextLabel")
	stats.Name = "OutcomeStats"
	stats.AnchorPoint = Vector2.new(0.5, 0.5)
	stats.Position = UDim2.fromScale(0.5, 0.57)
	stats.Size = UDim2.new(0, 460, 0, 28)
	stats.BackgroundTransparency = 1
	stats.Font = Enum.Font.Gotham
	stats.Text = ""
	stats.TextColor3 = Color3.fromRGB(142, 178, 184)
	stats.TextSize = 13
	stats.TextTransparency = 1
	stats.TextWrapped = true
	addTextStroke(stats, 0.68)
	stats.Parent = frame

	screenGui = gui
	blackout = frame
	title = label
	subtitle = sub
	statLine = stats
end

local function setTextTransparency(value: number)
	if title then title.TextTransparency = value end
	if subtitle then subtitle.TextTransparency = value end
	if statLine then statLine.TextTransparency = value end
end

local function showOutcome(outcome: string, survivedTime: number?, score: number?)
	if not screenGui or not blackout or not title or not subtitle or not statLine then return end

	local redFlash = blackout:FindFirstChild("RedFlash")
	local isWin = outcome == "win"
	local timeText = formatTime(survivedTime or (os.clock() - sessionStartedAt))

	screenGui.Enabled = true
	blackout.BackgroundTransparency = 1
	setTextTransparency(1)

	title.Text = if isWin then "ESCAPE ROUTE OPEN" else "SILENCE BROKEN"
	subtitle.Text = if isWin then "You survived the prototype." else "The entity found you. Resetting at spawn..."
	statLine.Text = if isWin
		then string.format("Time survived %s   Score %d", timeText, score or 0)
		else string.format("Time survived %s", timeText)

	if redFlash and redFlash:IsA("Frame") then
		redFlash.BackgroundTransparency = if isWin then 1 else 0.32
	end

	if isWin then
		playUiSound("EscapeSuccessUi", SOUND_IDS.success, 0.45, 0.72)
	else
		playUiSound("DeathResetUi", SOUND_IDS.death, 0.7)
	end

	local camera = workspace.CurrentCamera
	if camera then
		local originalFov = camera.FieldOfView
		camera.FieldOfView = if isWin then math.max(originalFov - 6, 58) else math.min(originalFov + 10, 90)
		task.delay(0.45, function()
			if camera then
				camera.FieldOfView = originalFov
			end
		end)
	end

	TweenService:Create(blackout, TweenInfo.new(0.2), {
		BackgroundTransparency = if isWin then 0.16 else 0.08,
	}):Play()
	TweenService:Create(title, TweenInfo.new(0.2), { TextTransparency = 0 }):Play()
	TweenService:Create(subtitle, TweenInfo.new(0.28), { TextTransparency = 0 }):Play()
	TweenService:Create(statLine, TweenInfo.new(0.34), { TextTransparency = 0 }):Play()

	if redFlash and redFlash:IsA("Frame") then
		TweenService:Create(redFlash, TweenInfo.new(0.34), { BackgroundTransparency = 1 }):Play()
	end

	if not isWin then
		task.delay(1.7, function()
			if not screenGui or not blackout then return end
			if title then TweenService:Create(title, TweenInfo.new(0.35), { TextTransparency = 1 }):Play() end
			if subtitle then TweenService:Create(subtitle, TweenInfo.new(0.35), { TextTransparency = 1 }):Play() end
			if statLine then TweenService:Create(statLine, TweenInfo.new(0.35), { TextTransparency = 1 }):Play() end
			TweenService:Create(blackout, TweenInfo.new(0.65), { BackgroundTransparency = 1 }):Play()
			task.wait(0.7)
			if screenGui then
				screenGui.Enabled = false
			end
		end)
	end
end

function MonsterFeedback.init()
	if initialized then return end
	initialized = true

	createGui()

	player.CharacterAdded:Connect(function()
		sessionStartedAt = os.clock()
	end)

	if caughtEvent then
		caughtEvent.OnClientEvent:Connect(function(payload)
			local deathPayload = if typeof(payload) == "table" then payload else nil
			showOutcome("death", deathPayload and deathPayload.survivedTime, deathPayload and deathPayload.score)
		end)
	end

	if gameOutcomeEvent then
		gameOutcomeEvent.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			showOutcome(tostring(payload.outcome or "win"), tonumber(payload.survivedTime), tonumber(payload.score))
		end)
	end
end

return MonsterFeedback

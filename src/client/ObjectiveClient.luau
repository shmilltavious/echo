-- Client-side objective prompts and decoy throwing
local ObjectiveClient = {}

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local objectiveEvent = ReplicatedStorage:WaitForChild("ObjectiveInteract", 10)
local objectiveStatusEvent = ReplicatedStorage:WaitForChild("ObjectiveStatus", 10)
local decoyThrowEvent = ReplicatedStorage:WaitForChild("DecoyThrow", 10)

local initialized = false
local nearestObjective: BasePart? = nil
local promptFrame: Frame? = nil
local promptTitle: TextLabel? = nil
local promptAction: TextLabel? = nil
local promptScale: UIScale? = nil
local statusFrame: Frame? = nil
local statusHeader: TextLabel? = nil
local statusLabel: TextLabel? = nil
local subStatusLabel: TextLabel? = nil
local statusHideAt = 0
local subStatusHideAt = 0

local PROMPT_RANGE = 16
local PROMPT_FADE_START = 9
local PROMPT_BASE_SIZE = Vector2.new(230, 58)

local objectiveCopy = {
	Keycard = {
		title = "Keycard",
		action = "Take",
	},
	Fuse = {
		title = "Fuse",
		action = "Take",
	},
	RepairPanel = {
		title = "Repair Panel",
		action = "Repair",
	},
	EscapeDoor = {
		title = "Escape Door",
		action = "Open",
	},
	DecoyBottle = {
		title = "Glass Bottle",
		action = "Take",
	},
}

local function addTextStroke(label: TextLabel, transparency: number)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = transparency
end

local function createPrompt(screenGui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "Prompt"
	frame.Size = UDim2.new(0, 230, 0, 58)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = screenGui

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = frame

	local icon = Instance.new("Frame")
	icon.Name = "KeyCircle"
	icon.Size = UDim2.new(0, 34, 0, 34)
	icon.Position = UDim2.new(0, 0, 0.5, -17)
	icon.BackgroundTransparency = 1
	icon.Parent = frame

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(232, 232, 222)
	iconStroke.Transparency = 0.12
	iconStroke.Thickness = 2
	iconStroke.Parent = icon

	local keyText = Instance.new("TextLabel")
	keyText.Name = "KeyText"
	keyText.Size = UDim2.new(1, 0, 1, 0)
	keyText.BackgroundTransparency = 1
	keyText.Font = Enum.Font.Garamond
	keyText.Text = "E"
	keyText.TextColor3 = Color3.fromRGB(238, 238, 228)
	keyText.TextSize = 22
	keyText.TextStrokeTransparency = 0.35
	keyText.Parent = icon

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -46, 0, 28)
	title.Position = UDim2.new(0, 46, 0, 4)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Garamond
	title.TextColor3 = Color3.fromRGB(238, 238, 228)
	title.TextSize = 24
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.Parent = frame
	addTextStroke(title, 0.42)

	local action = Instance.new("TextLabel")
	action.Name = "Action"
	action.Size = UDim2.new(1, -46, 0, 22)
	action.Position = UDim2.new(0, 47, 0, 30)
	action.BackgroundTransparency = 1
	action.Font = Enum.Font.GothamMedium
	action.TextColor3 = Color3.fromRGB(176, 174, 164)
	action.TextSize = 13
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.TextYAlignment = Enum.TextYAlignment.Top
	action.Parent = frame
	addTextStroke(action, 0.55)

	promptFrame = frame
	promptTitle = title
	promptAction = action
	promptScale = scale
end

local function createStatus(screenGui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "StatusFrame"
	frame.Size = UDim2.new(0, 286, 0, 96)
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -28, 0, 30)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = true
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

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.Size = UDim2.new(1, -38, 0, 24)
	header.Position = UDim2.new(0, 34, 0, 3)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.Garamond
	header.Text = "Objectives"
	header.TextColor3 = Color3.fromRGB(232, 230, 220)
	header.TextSize = 21
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Parent = frame
	addTextStroke(header, 0.55)

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.Size = UDim2.new(1, -38, 0, 22)
	label.Position = UDim2.new(0, 34, 0, 31)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = Color3.fromRGB(198, 196, 186)
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.Parent = frame
	addTextStroke(label, 0.68)

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubStatus"
	subLabel.Size = UDim2.new(1, -38, 0, 34)
	subLabel.Position = UDim2.new(0, 34, 0, 53)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.Gotham
	subLabel.TextColor3 = Color3.fromRGB(150, 148, 140)
	subLabel.TextSize = 12
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.TextYAlignment = Enum.TextYAlignment.Top
	subLabel.TextWrapped = true
	subLabel.Visible = false
	subLabel.Parent = frame
	addTextStroke(subLabel, 0.75)

	statusFrame = frame
	statusHeader = header
	statusLabel = label
	subStatusLabel = subLabel
end

local function createGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ObjectiveHUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	createPrompt(screenGui)
	createStatus(screenGui)
end

local function getCharacterRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function findNearestObjective()
	local rootPart = getCharacterRoot()
	if not rootPart then return nil end

	local closest = nil
	local closestDistance = PROMPT_RANGE

	for _, instance in ipairs(CollectionService:GetTagged("Objective")) do
		if instance:IsA("BasePart") and not instance:GetAttribute("Collected") then
			local distance = (rootPart.Position - instance.Position).Magnitude
			if distance <= closestDistance then
				closest = instance
				closestDistance = distance
			end
		end
	end

	return closest
end

local function setPromptAlpha(alpha: number)
	if not promptFrame then return end

	for _, descendant in ipairs(promptFrame:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.TextTransparency = 1 - alpha
			descendant.TextStrokeTransparency = math.clamp(1 - (alpha * 0.65), 0.35, 1)
		elseif descendant:IsA("UIStroke") then
			descendant.Transparency = math.clamp(1 - (alpha * 0.88), 0.12, 1)
		end
	end
end

local function getPromptWorldPosition(part: BasePart): Vector3
	local yOffset = math.clamp(part.Size.Y * 0.5 + 1.2, 1.5, 5)
	return part.Position + Vector3.new(0, yOffset, 0)
end

local function updatePrompt()
	nearestObjective = findNearestObjective()

	if not promptFrame or not promptTitle or not promptAction then return end
	if nearestObjective then
		local camera = workspace.CurrentCamera
		local rootPart = getCharacterRoot()
		if not camera or not rootPart then
			promptFrame.Visible = false
			return
		end

		local distance = (rootPart.Position - nearestObjective.Position).Magnitude
		local viewportPoint, onScreen = camera:WorldToViewportPoint(getPromptWorldPosition(nearestObjective))
		local viewportSize = camera.ViewportSize
		local insideScreen = viewportPoint.X >= 0
			and viewportPoint.X <= viewportSize.X
			and viewportPoint.Y >= 0
			and viewportPoint.Y <= viewportSize.Y

		if not onScreen or not insideScreen or distance > PROMPT_RANGE then
			promptFrame.Visible = false
			return
		end

		local fadeAlpha = 1
		if distance > PROMPT_FADE_START then
			fadeAlpha = 1 - ((distance - PROMPT_FADE_START) / (PROMPT_RANGE - PROMPT_FADE_START))
		end
		fadeAlpha = math.clamp(fadeAlpha, 0, 1)

		if fadeAlpha <= 0.05 then
			promptFrame.Visible = false
			return
		end

		local scale = 0.72 + (fadeAlpha * 0.28)
		local verticalLift = 8 + ((1 - fadeAlpha) * 8)
		promptFrame.Position = UDim2.fromOffset(viewportPoint.X, viewportPoint.Y - verticalLift)
		promptFrame.Size = UDim2.fromOffset(PROMPT_BASE_SIZE.X, PROMPT_BASE_SIZE.Y)
		if promptScale then
			promptScale.Scale = scale
		end
		setPromptAlpha(fadeAlpha)

		local objectiveName = nearestObjective:GetAttribute("ObjectiveName") or nearestObjective.Name
		local copy = objectiveCopy[objectiveName] or {
			title = tostring(objectiveName),
			action = "Interact",
		}

		promptTitle.Text = copy.title
		promptAction.Text = copy.action
		promptFrame.Visible = true
	else
		promptFrame.Visible = false
	end
end

local function showStatus(text, statusType)
	if not statusFrame or not statusLabel then return end

	if statusType == "sub" then
		if not subStatusLabel then return end
		subStatusLabel.Text = text
		subStatusLabel.Visible = true
		subStatusHideAt = os.clock() + 4
	else
		statusLabel.Text = text
		statusHideAt = math.huge
	end

	statusFrame.Visible = true
end

local function throwDecoy()
	if not decoyThrowEvent then return end
	local camera = workspace.CurrentCamera
	local rootPart = getCharacterRoot()
	if not rootPart then return end

	local origin = rootPart.Position + Vector3.new(0, 2, 0)
	local direction = camera and camera.CFrame.LookVector or rootPart.CFrame.LookVector
	decoyThrowEvent:FireServer(origin, direction)
end

function ObjectiveClient.init()
	if initialized then return end
	initialized = true

	createGui()
	showStatus("Find the keycard.", "main")

	if objectiveStatusEvent then
		objectiveStatusEvent.OnClientEvent:Connect(showStatus)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.E and nearestObjective and objectiveEvent then
			local objectiveName = nearestObjective:GetAttribute("ObjectiveName") or nearestObjective.Name
			objectiveEvent:FireServer(objectiveName)
		elseif input.KeyCode == Enum.KeyCode.G then
			throwDecoy()
		end
	end)

	RunService.RenderStepped:Connect(function()
		updatePrompt()

		if statusFrame and statusFrame.Visible and statusHideAt ~= math.huge and os.clock() > statusHideAt then
			statusFrame.Visible = false
		end
		if subStatusLabel and subStatusLabel.Visible and os.clock() > subStatusHideAt then
			subStatusLabel.Visible = false
		end
	end)
end

return ObjectiveClient

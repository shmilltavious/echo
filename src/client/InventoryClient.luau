local InventoryClient = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryDefinitions = require(ReplicatedStorage.Shared.InventoryDefinitions)
local EquipmentClient = require(script.Parent.EquipmentClient)

local player = Players.LocalPlayer
local initialized = false
local slotsFrame: Frame? = nil
local screenGui: ScreenGui? = nil
local itemArtTemplates = {}

local SLOT_SIZE = 54
local SLOT_WIDTH = 78
local SLOT_GAP = 6
local OCCUPIED_BORDER_COLOR = Color3.fromRGB(238, 238, 228)
local EQUIPPED_BORDER_COLOR = Color3.fromRGB(255, 246, 196)
local ICON_MODEL_ROTATIONS = {
	Fuse = CFrame.Angles(0, math.rad(90), 0),
}

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function addStroke(parent: Instance, color: Color3, transparency: number, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function prepareIconModel(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Name:find("Interact") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Transparency = descendant:GetAttribute("EchoOriginalTransparency") or descendant.Transparency
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function findItemArtSource(itemId: string): Model?
	local templateRoot = ReplicatedStorage:FindFirstChild("ItemTemplates")
	local template = templateRoot and templateRoot:FindFirstChild(itemId, true)
	if template and template:IsA("Model") then
		return template
	end
	if templateRoot then
		for _, descendant in ipairs(templateRoot:GetDescendants()) do
			if descendant:IsA("Model") and descendant:GetAttribute("ObjectiveName") == itemId then
				return descendant
			end
		end
	end

	local named = workspace:FindFirstChild(itemId, true)
	if named and named:IsA("Model") then
		return named
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant:GetAttribute("ObjectiveName") == itemId then
			return descendant
		end
	end

	return nil
end

local function cacheItemArtTemplate(itemId: string)
	if itemArtTemplates[itemId] then return end

	local source = findItemArtSource(itemId)
	if not source then
		return
	end

	local template = Instance.new("Model")
	template.Name = itemId .. "InventoryTemplate"
	for _, child in ipairs(source:GetChildren()) do
		if not child.Name:find("Interact") then
			child:Clone().Parent = template
		end
	end
	prepareIconModel(template)
	if #template:GetChildren() == 0 then
		template:Destroy()
		return
	end

	template.Parent = nil
	itemArtTemplates[itemId] = template
end

local function cacheItemArtTemplates()
	for itemId in pairs(InventoryDefinitions.ITEMS) do
		cacheItemArtTemplate(itemId)
	end
end

local function addAuthoredIconModel(itemId: string, viewport: ViewportFrame): boolean
	cacheItemArtTemplate(itemId)
	local template = itemArtTemplates[itemId]
	if not template then
		return false
	end

	local model = template:Clone()
	model.Name = itemId .. "IconModel"
	prepareIconModel(model)
	model.Parent = viewport

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() - boundsCFrame.Position)
	boundsCFrame, boundsSize = model:GetBoundingBox()
	local iconRotation = ICON_MODEL_ROTATIONS[itemId]
	if iconRotation then
		model:PivotTo(iconRotation)
		boundsCFrame, boundsSize = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() - boundsCFrame.Position)
		boundsCFrame, boundsSize = model:GetBoundingBox()
	end

	local maxAxis = math.max(boundsSize.X, math.max(boundsSize.Y, boundsSize.Z))
	if maxAxis <= 0 then
		model:Destroy()
		return false
	end

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(0, maxAxis * 0.12, maxAxis * 2.35) * CFrame.Angles(math.rad(-8), 0, 0)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return true
end

local function createProceduralIcon(itemId: string, color: Color3, parent: Instance)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(0, 38, 0, 34)
	viewport.Position = UDim2.new(0, 8, 0, 7)
	viewport.Ambient = Color3.fromRGB(35, 38, 39)
	viewport.LightColor = color
	viewport.LightDirection = Vector3.new(-0.5, -1, -0.6)
	viewport.Parent = parent

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.new(0, 0.2, 5)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local model = Instance.new("Model")
	model.Name = itemId .. "IconModel"
	model.Parent = viewport

	if itemId == "Flashlight" then
		local handle = Instance.new("Part")
		handle.Name = "FlashlightHandle"
		handle.Shape = Enum.PartType.Cylinder
		handle.Size = Vector3.new(1.8, 0.28, 0.28)
		handle.CFrame = CFrame.Angles(0, 0, math.rad(90))
		handle.Material = Enum.Material.Metal
		handle.Color = color
		handle.Parent = model

		local head = Instance.new("Part")
		head.Name = "FlashlightHead"
		head.Shape = Enum.PartType.Cylinder
		head.Size = Vector3.new(0.42, 0.62, 0.62)
		head.CFrame = CFrame.new(0.92, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
		head.Material = Enum.Material.Metal
		head.Color = color
		head.Parent = model
	elseif itemId == "Fuse" then
		local body = Instance.new("Part")
		body.Name = "FuseBody"
		body.Shape = Enum.PartType.Cylinder
		body.Size = Vector3.new(1.8, 0.42, 0.42)
		body.CFrame = CFrame.Angles(0, 0, math.rad(90))
		body.Material = Enum.Material.Metal
		body.Color = color
		body.Parent = model
	elseif itemId == "DecoyBottle" then
		local bottle = Instance.new("Part")
		bottle.Name = "BottleBody"
		bottle.Shape = Enum.PartType.Cylinder
		bottle.Size = Vector3.new(1.5, 0.42, 0.42)
		bottle.CFrame = CFrame.Angles(0, 0, math.rad(90))
		bottle.Material = Enum.Material.Glass
		bottle.Color = color
		bottle.Transparency = 0.18
		bottle.Parent = model
	else
		local card = Instance.new("Part")
		card.Name = "Card"
		card.Size = Vector3.new(1.7, 0.08, 1.05)
		card.CFrame = CFrame.Angles(math.rad(18), math.rad(-20), 0)
		card.Material = Enum.Material.Neon
		card.Color = color
		card.Parent = model
	end
end

local function createSilhouette(itemId: string, color: Color3, parent: Instance)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.new(0, 40, 0, 34)
	viewport.Position = UDim2.new(0, 7, 0, 7)
	viewport.Ambient = Color3.fromRGB(70, 72, 68)
	viewport.LightColor = Color3.fromRGB(232, 228, 210)
	viewport.LightDirection = Vector3.new(-0.45, -1, -0.65)
	viewport.Parent = parent

	if addAuthoredIconModel(itemId, viewport) then
		return
	end

	viewport:Destroy()
	createProceduralIcon(itemId, color, parent)
end

local function createSlotLabel(text: string, parent: Instance, subdued: boolean)
	local slotLabel = Instance.new("TextLabel")
	slotLabel.Name = "SlotNumber"
	slotLabel.BackgroundTransparency = 1
	slotLabel.Size = UDim2.new(0, 24, 0, 24)
	slotLabel.Position = UDim2.new(0, 4, 0, 6)
	slotLabel.Font = Enum.Font.GothamBold
	slotLabel.Text = text
	slotLabel.TextColor3 = if subdued then Color3.fromRGB(118, 116, 108) else Color3.fromRGB(238, 235, 218)
	slotLabel.TextSize = 13
	slotLabel.TextXAlignment = Enum.TextXAlignment.Center
	slotLabel.TextYAlignment = Enum.TextYAlignment.Center
	slotLabel.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Transparency = 0.65
	stroke.Thickness = 1
	stroke.Parent = slotLabel
end

local function createItemCell(item, heightSlots: number, isEquipped: boolean)
	local cell = Instance.new("Frame")
	cell.Name = item.id .. "Cell"
	cell.Size = UDim2.new(0, SLOT_WIDTH, 0, (SLOT_SIZE * heightSlots) + (SLOT_GAP * (heightSlots - 1)))
	cell.BackgroundColor3 = Color3.fromRGB(7, 8, 9)
	cell.BackgroundTransparency = if isEquipped then 0.04 else 0.12
	cell.BorderSizePixel = 0
	addStroke(cell, if isEquipped then EQUIPPED_BORDER_COLOR else OCCUPIED_BORDER_COLOR, if isEquipped then 0.02 else 0.18, if isEquipped then 2 else 1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = cell

	createSlotLabel(tostring(item.slotLabel or ""), cell, false)

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.BackgroundTransparency = 1
	iconHolder.Size = UDim2.new(0, SLOT_SIZE, 1, 0)
	iconHolder.Position = UDim2.new(0, 24, 0, 0)
	iconHolder.Parent = cell

	createSilhouette(item.id, item.color or Color3.fromRGB(170, 170, 160), iconHolder)

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Size = UDim2.new(1, -32, 0, 20)
	label.Position = UDim2.new(0.5, 12, 1, -6)
	label.Font = Enum.Font.GothamMedium
	label.Text = item.name
	label.TextColor3 = Color3.fromRGB(204, 201, 190)
	label.TextSize = 11
	label.TextScaled = true
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = cell

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 5
	textConstraint.MaxTextSize = 9
	textConstraint.Parent = label

	return cell
end

local function createEmptyCell(index: number)
	local cell = Instance.new("Frame")
	cell.Name = "EmptySlot" .. tostring(index)
	cell.Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_SIZE)
	cell.BackgroundColor3 = Color3.fromRGB(5, 6, 7)
	cell.BackgroundTransparency = 0.58
	cell.BorderSizePixel = 0
	addStroke(cell, Color3.fromRGB(92, 92, 86), 0.74, 1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = cell

	createSlotLabel(tostring(index), cell, true)

	local line = Instance.new("Frame")
	line.Name = "EmptyLine"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.new(0, 51, 0.5, 0)
	line.Size = UDim2.new(0, 20, 0, 1)
	line.BackgroundColor3 = Color3.fromRGB(75, 75, 70)
	line.BackgroundTransparency = 0.62
	line.BorderSizePixel = 0
	line.Parent = cell

	return cell
end

local function createGui()
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "InventoryHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 25
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Slots"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 28, 1, -28)
	frame.Size = UDim2.new(0, SLOT_WIDTH, 0, (SLOT_SIZE * InventoryDefinitions.CAPACITY) + (SLOT_GAP * (InventoryDefinitions.CAPACITY - 1)))
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.Parent = frame

	screenGui = gui
	slotsFrame = frame
end

local function render(state)
	if not slotsFrame then return end
	clearChildren(slotsFrame)

	local capacity = math.max(1, tonumber(state.capacity) or InventoryDefinitions.CAPACITY)
	local used = 0
	local layoutOrder = 0

	if typeof(state.items) == "table" then
		for _, item in ipairs(state.items) do
			local weight = math.clamp(tonumber(item.weight) or 1, 1, capacity)
			local isEquipped = tostring(item.id or "") == state.equippedItemId
			local cell = createItemCell(item, weight, isEquipped)
			cell.LayoutOrder = layoutOrder
			cell.Parent = slotsFrame
			used += weight
			layoutOrder += weight
		end
	end

	for index = used + 1, capacity do
		local empty = createEmptyCell(index)
		empty.LayoutOrder = layoutOrder
		empty.Parent = slotsFrame
		layoutOrder += 1
	end
end

function InventoryClient.init()
	if initialized then return end
	initialized = true

	EquipmentClient.init()
	cacheItemArtTemplates()
	createGui()
	EquipmentClient.onChanged(render)
end

return InventoryClient

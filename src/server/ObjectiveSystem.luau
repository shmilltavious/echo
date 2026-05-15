-- Server-side objective chain, inventory authority, and throwable decoys
local ObjectiveSystem = {}

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local InventoryDefinitions = require(ReplicatedStorage.Shared.InventoryDefinitions)

local OBJECTIVE_CONFIG = Constants.OBJECTIVES
local REMOTE_LIMITS = Constants.REMOTE_LIMITS
local OBJECTIVE_TAG = OBJECTIVE_CONFIG.OBJECTIVE_TAG
local REVEAL_TAG = OBJECTIVE_CONFIG.REVEAL_TAG
local INTERACT_RANGE = OBJECTIVE_CONFIG.INTERACT_RANGE
local REPAIR_DURATION = OBJECTIVE_CONFIG.REPAIR_DURATION
local FLASHLIGHT_ITEM_ID = OBJECTIVE_CONFIG.FLASHLIGHT_ITEM_ID
local FUSE_BOX_DISCONNECTED_NAME = OBJECTIVE_CONFIG.FUSE_BOX_DISCONNECTED_NAME
local FUSE_BOX_CONNECTED_NAME = OBJECTIVE_CONFIG.FUSE_BOX_CONNECTED_NAME
local PROTOTYPE_MAP_NAME = OBJECTIVE_CONFIG.PROTOTYPE_MAP_NAME
local AUTHORED_MAP_NAMES = OBJECTIVE_CONFIG.AUTHORED_MAP_NAMES
local SOUND_IDS = Constants.SOUNDS
local ESCAPE_DOOR_POSITION = OBJECTIVE_CONFIG.ESCAPE_DOOR_POSITION
local ESCAPE_DOOR_SIZE = OBJECTIVE_CONFIG.ESCAPE_DOOR_SIZE
local ESCAPE_DOOR_OPEN_OFFSET = OBJECTIVE_CONFIG.ESCAPE_DOOR_OPEN_OFFSET
local DECOY_SHARD_COUNT = OBJECTIVE_CONFIG.DECOY_SHARD_COUNT
local DECOY_SHATTER_FALLBACK_SECONDS = OBJECTIVE_CONFIG.DECOY_SHATTER_FALLBACK_SECONDS
local DECOY_THROW_COOLDOWN = REMOTE_LIMITS.DECOY_THROW_COOLDOWN
local OBJECTIVE_INTERACT_COOLDOWN = REMOTE_LIMITS.OBJECTIVE_INTERACT_COOLDOWN
local OBJECTIVE_REPAIR_COOLDOWN = REMOTE_LIMITS.OBJECTIVE_REPAIR_COOLDOWN

local objectiveOrder = OBJECTIVE_CONFIG.ORDER
local interactPartNames = OBJECTIVE_CONFIG.INTERACT_PART_NAMES

local playerState = {}
local inventories = {}
local repairSessions = {}
local itemArtTemplates = {}
local warnedValidationMessages = {}
local lastDecoyThrowAt = {}
local lastObjectiveInteractAt = {}
local lastRepairActionAt = {}
local objectiveState = {
	keycardAcquired = false,
	fuseHolder = nil,
	repaired = false,
}

local objectiveEvent = ReplicatedStorage:FindFirstChild("ObjectiveInteract") or Instance.new("RemoteEvent")
objectiveEvent.Name = "ObjectiveInteract"
objectiveEvent.Parent = ReplicatedStorage

local objectiveStatusEvent = ReplicatedStorage:FindFirstChild("ObjectiveStatus") or Instance.new("RemoteEvent")
objectiveStatusEvent.Name = "ObjectiveStatus"
objectiveStatusEvent.Parent = ReplicatedStorage

local decoyThrowEvent = ReplicatedStorage:FindFirstChild("DecoyThrow") or Instance.new("RemoteEvent")
decoyThrowEvent.Name = "DecoyThrow"
decoyThrowEvent.Parent = ReplicatedStorage

local gameOutcomeEvent = ReplicatedStorage:FindFirstChild("GameOutcome") or Instance.new("RemoteEvent")
gameOutcomeEvent.Name = "GameOutcome"
gameOutcomeEvent.Parent = ReplicatedStorage

local inventoryUpdateEvent = ReplicatedStorage:FindFirstChild("InventoryUpdate") or Instance.new("RemoteEvent")
inventoryUpdateEvent.Name = "InventoryUpdate"
inventoryUpdateEvent.Parent = ReplicatedStorage

local serverNoiseEvent = ReplicatedStorage:FindFirstChild("ServerNoiseEvent") or Instance.new("BindableEvent")
serverNoiseEvent.Name = "ServerNoiseEvent"
serverNoiseEvent.Parent = ReplicatedStorage

local function getPlayerState(player)
	local state = playerState[player]
	if not state then
		state = {
			escaped = false,
			startedAt = os.clock(),
		}
		playerState[player] = state
		player:SetAttribute("Escaped", false)
	end
	return state
end

local function getInventory(player)
	local inventory = inventories[player]
	if not inventory then
		inventory = {
			items = { FLASHLIGHT_ITEM_ID },
		}
		inventories[player] = inventory
	elseif not table.find(inventory.items, FLASHLIGHT_ITEM_ID) then
		table.insert(inventory.items, 1, FLASHLIGHT_ITEM_ID)
	end
	return inventory
end

local function getInventoryUsed(player): number
	local used = 0
	for _, itemId in ipairs(getInventory(player).items) do
		used += InventoryDefinitions.getWeight(itemId)
	end
	return used
end

local function makeSlotLabel(slotStart: number?, slotEnd: number?): string
	if not slotStart then
		return ""
	end
	if slotEnd and slotEnd ~= slotStart then
		return tostring(slotStart) .. "-" .. tostring(slotEnd)
	end
	return tostring(slotStart)
end

local function findInventorySlot(weight: number, occupied): number?
	for startSlot = 2, InventoryDefinitions.CAPACITY do
		local endSlot = startSlot + weight - 1
		if endSlot > InventoryDefinitions.CAPACITY then
			return nil
		end

		local available = true
		for slot = startSlot, endSlot do
			if occupied[slot] then
				available = false
				break
			end
		end

		if available then
			return startSlot
		end
	end

	return nil
end

local function getInventoryPayload(player)
	local payloadItems = {}
	local occupied = {}
	for _, itemId in ipairs(getInventory(player).items) do
		local item = InventoryDefinitions.getItem(itemId)
		local weight = InventoryDefinitions.getWeight(itemId)
		local slotStart = nil
		local slotEnd = nil
		if item.id == FLASHLIGHT_ITEM_ID then
			slotStart = 1
			slotEnd = 1
		else
			slotStart = findInventorySlot(weight, occupied)
			slotEnd = if slotStart then slotStart + weight - 1 else nil
		end

		if slotStart and slotEnd then
			for slot = slotStart, slotEnd do
				occupied[slot] = true
			end
		end

		table.insert(payloadItems, {
			id = item.id,
			name = item.name,
			weight = weight,
			slotStart = slotStart,
			slotEnd = slotEnd,
			slotLabel = makeSlotLabel(slotStart, slotEnd),
		})
	end

	return {
		capacity = InventoryDefinitions.CAPACITY,
		used = getInventoryUsed(player),
		items = payloadItems,
	}
end

local function sendInventory(player)
	inventoryUpdateEvent:FireClient(player, getInventoryPayload(player))
end

local function hasItem(player, itemId: string): boolean
	for _, heldId in ipairs(getInventory(player).items) do
		if heldId == itemId then
			return true
		end
	end
	return false
end

local function addItem(player, itemId: string): boolean
	if hasItem(player, itemId) then
		return true
	end

	local weight = InventoryDefinitions.getWeight(itemId)
	local used = getInventoryUsed(player)
	if used + weight > InventoryDefinitions.CAPACITY then
		return false
	end

	table.insert(getInventory(player).items, itemId)
	sendInventory(player)
	return true
end

local function removeItem(player, itemId: string): boolean
	if itemId == FLASHLIGHT_ITEM_ID then
		return false
	end

	local items = getInventory(player).items
	for index, heldId in ipairs(items) do
		if heldId == itemId then
			table.remove(items, index)
			sendInventory(player)
			return true
		end
	end
	return false
end

local function warnOnce(key: string, message: string)
	if warnedValidationMessages[key] then
		return
	end

	warnedValidationMessages[key] = true
	warn("[ObjectiveSystem] " .. message)
end

local function isKnownObjectiveName(objectiveName: string): boolean
	return interactPartNames[objectiveName] ~= nil
end

local function playWorldSound(parent: Instance, name: string, soundId: string, volume: number, maxDistance: number)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = maxDistance
	sound.RollOffMinDistance = 6
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 6)
end

local function playAnchoredWorldSound(position: Vector3, name: string, soundId: string, volume: number, maxDistance: number)
	local anchor = Instance.new("Part")
	anchor.Name = name .. "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position
	anchor.Parent = workspace
	playWorldSound(anchor, name, soundId, volume, maxDistance)
	Debris:AddItem(anchor, 6)
end

local function getActiveAuthoredMap(): Instance?
	for _, mapName in ipairs(AUTHORED_MAP_NAMES) do
		local map = workspace:FindFirstChild(mapName)
		if map then
			return map
		end
	end

	return nil
end

local function getActiveMap(): Instance?
	return getActiveAuthoredMap() or workspace:FindFirstChild(PROTOTYPE_MAP_NAME)
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

	local direct = workspace:FindFirstChild(itemId)
	if direct and direct:IsA("Model") then
		return direct
	end

	local nested = workspace:FindFirstChild(itemId, true)
	if nested and nested:IsA("Model") then
		return nested
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant:GetAttribute("ObjectiveName") == itemId then
			return descendant
		end
	end

	return nil
end

local function prepareItemArtClone(model: Model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant.Name:find("Interact") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = true
			descendant.CanTouch = true
			descendant.CanQuery = true
			descendant.Transparency = descendant:GetAttribute("EchoOriginalTransparency") or descendant.Transparency
			CollectionService:AddTag(descendant, REVEAL_TAG)
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function cacheItemArtTemplate(itemId: string)
	if itemArtTemplates[itemId] then
		return
	end

	local source = findItemArtSource(itemId)
	if not source then
		return
	end

	local template = Instance.new("Model")
	template.Name = itemId .. "ArtTemplate"
	for _, child in ipairs(source:GetChildren()) do
		if not child.Name:find("Interact") then
			child:Clone().Parent = template
		end
	end
	prepareItemArtClone(template)
	if #template:GetChildren() == 0 then
		template:Destroy()
		return
	end
	template.Parent = nil
	itemArtTemplates[itemId] = template
end

local function cloneItemArt(itemId: string, name: string): Model?
	cacheItemArtTemplate(itemId)
	local template = itemArtTemplates[itemId]
	if not template then
		return nil
	end

	local clone = template:Clone()
	clone.Name = name
	prepareItemArtClone(clone)
	return clone
end

local function getLargestPart(model: Model): BasePart?
	local largestPart = nil
	local largestVolume = -math.huge
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local size = descendant.Size
			local volume = size.X * size.Y * size.Z
			if volume > largestVolume then
				largestVolume = volume
				largestPart = descendant
			end
		end
	end
	return largestPart
end

local function makeThrownItemPhysical(model: Model): BasePart?
	local primary = model.PrimaryPart or getLargestPart(model)
	if not primary then
		return nil
	end
	model.PrimaryPart = primary

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanTouch = true
			descendant.CanQuery = true
			descendant.CanCollide = descendant == primary
			if descendant ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end

	return primary
end

local function getSurvivalStats(state)
	local survivedTime = math.max(0, os.clock() - (state.startedAt or os.clock()))
	local score = math.floor(500 + (survivedTime * 12))
	return survivedTime, score
end

local function ensureMap()
	local map = workspace:FindFirstChild(PROTOTYPE_MAP_NAME)
	if not map then
		map = Instance.new("Folder")
		map.Name = PROTOTYPE_MAP_NAME
		map.Parent = workspace
	end
	return map
end

local function getExplicitInteractPart(candidate: Instance?, objectiveName: string): BasePart?
	if not candidate then
		return nil
	end

	local interactName = interactPartNames[objectiveName]
	if not interactName then
		return nil
	end

	if candidate:IsA("BasePart") and candidate.Name == interactName then
		return candidate
	end

	local descendant = candidate:FindFirstChild(interactName, true)
	if descendant and descendant:IsA("BasePart") then
		return descendant
	end

	local current = candidate.Parent
	while current and current ~= workspace do
		local sibling = current:FindFirstChild(interactName, true)
		if sibling and sibling:IsA("BasePart") then
			return sibling
		end
		current = current.Parent
	end

	return nil
end

local function getBasePartFromCandidate(candidate: Instance?, objectiveName: string): BasePart?
	if not candidate then
		return nil
	end

	local interactPart = getExplicitInteractPart(candidate, objectiveName)
	if interactPart then
		return interactPart
	end

	if candidate:IsA("BasePart") then
		return candidate
	end
	if candidate:IsA("Model") then
		if candidate.PrimaryPart then
			return candidate.PrimaryPart
		end
	end

	local namedPart = candidate:FindFirstChild(objectiveName, true)
	if namedPart and namedPart:IsA("BasePart") then
		return namedPart
	end

	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function findAuthoredObjectivePart(objectiveName: string): BasePart?
	for _, instance in ipairs(CollectionService:GetTagged(OBJECTIVE_TAG)) do
		if instance:IsDescendantOf(workspace) and instance:GetAttribute("ObjectiveName") == objectiveName then
			local part = getBasePartFromCandidate(instance, objectiveName)
			if part then
				return part
			end
		end
	end

	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:GetAttribute("ObjectiveName") == objectiveName then
			local part = getBasePartFromCandidate(instance, objectiveName)
			if part then
				return part
			end
		end
	end

	local interactName = interactPartNames[objectiveName]
	if interactName then
		local interactPart = workspace:FindFirstChild(interactName, true)
		if interactPart and interactPart:IsA("BasePart") then
			return interactPart
		end
	end

	local legacyObjective = workspace:FindFirstChild(objectiveName, true)
	return getBasePartFromCandidate(legacyObjective, objectiveName)
end

local function isEscapeDoorTrigger(instance: Instance?): boolean
	return instance ~= nil
		and instance:IsA("BasePart")
		and instance.Name == interactPartNames.EscapeDoor
end

local function findEscapeDoorTrigger(): BasePart?
	local namedTrigger = workspace:FindFirstChild(interactPartNames.EscapeDoor, true)
	if namedTrigger and namedTrigger:IsA("BasePart") then
		return namedTrigger
	end

	for _, instance in ipairs(CollectionService:GetTagged(OBJECTIVE_TAG)) do
		if instance:IsDescendantOf(workspace)
			and instance:IsA("BasePart")
			and instance:GetAttribute("ObjectiveName") == "EscapeDoor"
		then
			return instance
		end
	end

	return nil
end

local function findEscapeDoorVisual(): Instance?
	local namedDoor = workspace:FindFirstChild("EscapeDoor", true)
	if namedDoor and not isEscapeDoorTrigger(namedDoor) and (namedDoor:IsA("BasePart") or namedDoor:IsA("Model")) then
		return namedDoor
	end

	for _, instance in ipairs(workspace:GetDescendants()) do
		if instance:GetAttribute("ObjectiveName") == "EscapeDoor"
			and not isEscapeDoorTrigger(instance)
			and (instance:IsA("BasePart") or instance:IsA("Model"))
		then
			return instance
		end
	end

	return nil
end

local function getInstanceBounds(instance: Instance?): (CFrame, Vector3)
	if instance and instance:IsA("Model") then
		return instance:GetBoundingBox()
	elseif instance and instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return CFrame.new(ESCAPE_DOOR_POSITION), ESCAPE_DOOR_SIZE
end

local function tagRevealVisual(instance: Instance)
	if instance:IsA("BasePart") then
		CollectionService:AddTag(instance, REVEAL_TAG)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			CollectionService:AddTag(descendant, REVEAL_TAG)
		end
	end
end

local function cacheEscapeDoorState(visual: Instance)
	if visual:IsA("BasePart") then
		if visual:GetAttribute("ClosedPosition") == nil then
			visual:SetAttribute("ClosedPosition", visual.Position)
		end
		if visual:GetAttribute("OpenPosition") == nil then
			visual:SetAttribute("OpenPosition", visual.Position + ESCAPE_DOOR_OPEN_OFFSET)
		end
	elseif visual:IsA("Model") then
		if visual:GetAttribute("ClosedPivot") == nil then
			visual:SetAttribute("ClosedPivot", visual:GetPivot())
		end
		if visual:GetAttribute("OpenPivot") == nil then
			visual:SetAttribute("OpenPivot", visual:GetPivot() + ESCAPE_DOOR_OPEN_OFFSET)
		end
	end
end

local function makeEscapeDoorVisual(parent: Instance, trigger: BasePart?): BasePart
	local visual = Instance.new("Part")
	visual.Name = "EscapeDoor"
	visual.Anchored = true
	visual.CanCollide = true
	visual.Size = ESCAPE_DOOR_SIZE
	visual.CFrame = if trigger then CFrame.new(trigger.Position) else CFrame.new(ESCAPE_DOOR_POSITION)
	visual.Color = Color3.fromRGB(90, 90, 100)
	visual.Material = Enum.Material.Metal
	visual.Parent = parent
	return visual
end

local function ensureEscapeDoorSetup(parent: Instance): BasePart
	local trigger = findEscapeDoorTrigger()
	local visual = findEscapeDoorVisual()

	if not visual then
		visual = makeEscapeDoorVisual(parent, trigger)
	end

	local visualCFrame, visualSize = getInstanceBounds(visual)
	if not trigger then
		trigger = Instance.new("Part")
		trigger.Name = interactPartNames.EscapeDoor
		trigger.Parent = parent
	end

	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.CanQuery = true
	trigger.Transparency = 1
	trigger.Size = Vector3.new(math.max(visualSize.X, 6), math.max(visualSize.Y, 8), math.max(visualSize.Z, 4))
	trigger.CFrame = visualCFrame
	trigger:SetAttribute("ObjectiveName", "EscapeDoor")
	trigger:SetAttribute("ObjectiveOrder", objectiveOrder.EscapeDoor)
	trigger:SetAttribute("EquipSlot", "World")
	trigger:SetAttribute("ViewModelWhenEquipped", false)
	CollectionService:AddTag(trigger, OBJECTIVE_TAG)

	tagRevealVisual(visual)
	cacheEscapeDoorState(visual)

	return trigger
end

local function makePart(parent, objectiveName, name, position, size, color, material, allowFallback: boolean?)
	local existing = findAuthoredObjectivePart(objectiveName)
	if existing then
		return existing
	end

	if allowFallback == false then
		warnOnce("missing-objective-" .. objectiveName, string.format(
			"Missing authored objective '%s'. Expected a tagged/attributed model or a BasePart named '%s'. Prototype fallback was skipped because an authored map is present.",
			objectiveName,
			name
		))
		return nil
	end

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.Metal
	part.Parent = parent
	return part
end

local function tagObjective(part, objectiveName)
	part.Anchored = true
	CollectionService:AddTag(part, OBJECTIVE_TAG)
	CollectionService:AddTag(part, REVEAL_TAG)
	part:SetAttribute("ObjectiveName", objectiveName)
	part:SetAttribute("ObjectiveOrder", objectiveOrder[objectiveName] or 0)
	part:SetAttribute("ViewModelWhenEquipped", false)
end

local function findObjectivePart(objectiveName)
	if objectiveName == "EscapeDoor" then
		return findEscapeDoorTrigger()
	end

	return findAuthoredObjectivePart(objectiveName)
end

local function clearEcholocationHighlights(instance: Instance)
	if instance:IsA("BasePart") then
		local highlight = instance:FindFirstChild("EcholocationOutline")
		if highlight and highlight:IsA("Highlight") then
			highlight:Destroy()
		end
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local highlight = descendant:FindFirstChild("EcholocationOutline")
			if highlight and highlight:IsA("Highlight") then
				highlight:Destroy()
			end
		end
	end
end

local function cacheVisualState(instance: Instance)
	if instance:IsA("BasePart") then
		if instance:GetAttribute("EchoOriginalTransparency") == nil then
			instance:SetAttribute("EchoOriginalTransparency", instance.Transparency)
			instance:SetAttribute("EchoOriginalCanCollide", instance.CanCollide)
			instance:SetAttribute("EchoOriginalCanTouch", instance.CanTouch)
			instance:SetAttribute("EchoOriginalCanQuery", instance.CanQuery)
		end
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		if instance:GetAttribute("EchoOriginalTransparency") == nil then
			instance:SetAttribute("EchoOriginalTransparency", instance.Transparency)
		end
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		if instance:GetAttribute("EchoOriginalEnabled") == nil then
			instance:SetAttribute("EchoOriginalEnabled", instance.Enabled)
		end
	end
end

local function setVisualInstanceEnabled(instance: Instance, enabled: boolean)
	cacheVisualState(instance)
	instance:SetAttribute("EcholocationRevealHidden", not enabled)

	if instance:IsA("BasePart") then
		if enabled then
			instance.Transparency = instance:GetAttribute("EchoOriginalTransparency") or 0
			instance.CanCollide = instance:GetAttribute("EchoOriginalCanCollide") == true
			instance.CanTouch = instance:GetAttribute("EchoOriginalCanTouch") == true
			instance.CanQuery = instance:GetAttribute("EchoOriginalCanQuery") ~= false
		else
			instance.Transparency = 1
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
		end
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = if enabled then (instance:GetAttribute("EchoOriginalTransparency") or 0) else 1
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = if enabled then (instance:GetAttribute("EchoOriginalEnabled") ~= false) else false
	end

	if not enabled then
		clearEcholocationHighlights(instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		setVisualInstanceEnabled(descendant, enabled)
	end
end

local function getAuthoredFuseBox(name: string): Instance?
	local activeMap = getActiveMap()
	local inMap = activeMap and activeMap:FindFirstChild(name, true)
	if inMap then
		return inMap
	end

	return workspace:FindFirstChild(name, true)
end

local function prepareFuseBoxes()
	local disconnectedBox = getAuthoredFuseBox(FUSE_BOX_DISCONNECTED_NAME)
	local connectedBox = getAuthoredFuseBox(FUSE_BOX_CONNECTED_NAME)
	if not disconnectedBox or not connectedBox then
		return
	end

	setVisualInstanceEnabled(disconnectedBox, true)
	setVisualInstanceEnabled(connectedBox, false)
end

local function showConnectedFuseBox(): boolean
	local disconnectedBox = getAuthoredFuseBox(FUSE_BOX_DISCONNECTED_NAME)
	local connectedBox = getAuthoredFuseBox(FUSE_BOX_CONNECTED_NAME)
	if not disconnectedBox or not connectedBox then
		return false
	end

	local targetCFrame
	if disconnectedBox:IsA("Model") then
		targetCFrame = disconnectedBox:GetPivot()
	elseif disconnectedBox:IsA("BasePart") then
		targetCFrame = disconnectedBox.CFrame
	else
		return false
	end

	if connectedBox:IsA("Model") then
		connectedBox:PivotTo(targetCFrame)
	elseif connectedBox:IsA("BasePart") then
		connectedBox.CFrame = targetCFrame
	else
		return false
	end

	setVisualInstanceEnabled(disconnectedBox, false)
	setVisualInstanceEnabled(connectedBox, true)
	return true
end

local function validateInteractPart(objectiveName: string, part: BasePart?)
	local expectedName = interactPartNames[objectiveName]
	if not part then
		warnOnce("validate-missing-" .. objectiveName, string.format(
			"Authored map is missing '%s' for objective '%s'.",
			expectedName or objectiveName,
			objectiveName
		))
		return
	end

	if expectedName and part.Name ~= expectedName then
		warnOnce("validate-name-" .. objectiveName, string.format(
			"Objective '%s' resolved to '%s'. Prefer an explicit '%s' trigger so final-map visuals can move independently.",
			objectiveName,
			part:GetFullName(),
			expectedName
		))
	end

	if part.Transparency < 0.95 then
		warnOnce("validate-visible-" .. objectiveName, string.format(
			"Interact trigger '%s' should usually be invisible; current Transparency is %.2f.",
			part:GetFullName(),
			part.Transparency
		))
	end
	if part.CanCollide then
		warnOnce("validate-collide-" .. objectiveName, "Interact trigger '" .. part:GetFullName() .. "' should not block players.")
	end
	if not part.CanQuery or not part.CanTouch then
		warnOnce("validate-query-" .. objectiveName, "Interact trigger '" .. part:GetFullName() .. "' should have CanQuery and CanTouch enabled.")
	end
end

local function hasMonsterWaypoints(map: Instance): boolean
	if map:FindFirstChild("MonsterPatrolWaypoints", true) then
		return true
	end

	for _, descendant in ipairs(map:GetDescendants()) do
		if descendant:IsA("BasePart") and (descendant.Name == "PatrolPoint" or descendant.Name == "Waypoint") then
			return true
		end
	end

	return false
end

local function validateAuthoredMapSetup(map: Instance)
	for objectiveName in pairs(interactPartNames) do
		validateInteractPart(objectiveName, findObjectivePart(objectiveName))
	end

	for _, itemId in ipairs({ "Flashlight", "Keycard", "Fuse", "DecoyBottle" }) do
		if not findItemArtSource(itemId) then
			warnOnce("validate-art-" .. itemId, "Missing authored item art model for inventory/held/thrown clone: " .. itemId)
		end
	end

	if not (map:FindFirstChild("RevealTargets", true) or workspace:FindFirstChild("RevealTargets")) then
		warnOnce("validate-reveal-root", "Authored map has no RevealTargets folder. Echolocation will use tagged reveal parts or the active map root as fallback.")
	end

	if not hasMonsterWaypoints(map) then
		warnOnce("validate-waypoints", "Authored map has no MonsterPatrolWaypoints folder, PatrolPoint parts, or Waypoint parts.")
	end
end

local function ensureObjectiveProps()
	local authoredMap = getActiveAuthoredMap()
	local map = authoredMap or ensureMap()
	local allowFallback = authoredMap == nil

	local keycard = makePart(map, "Keycard", interactPartNames.Keycard, Vector3.new(80.5, 3, 26), Vector3.new(2, 0.2, 1.2), Color3.fromRGB(45, 170, 255), Enum.Material.Neon, allowFallback)
	local fuse = makePart(map, "Fuse", interactPartNames.Fuse, Vector3.new(132.5, 3, 13), Vector3.new(1.2, 1.2, 2.5), Color3.fromRGB(255, 210, 70), Enum.Material.Metal, allowFallback)
	local repairPanel = makePart(map, "RepairPanel", interactPartNames.RepairPanel, Vector3.new(151.2, 5, -32.5), Vector3.new(4, 6, 0.6), Color3.fromRGB(85, 130, 120), Enum.Material.Metal, allowFallback)
	local existingEscapeTrigger = findEscapeDoorTrigger()
	local existingEscapeVisual = findEscapeDoorVisual()
	if authoredMap and not existingEscapeTrigger then
		warnOnce("missing-objective-EscapeDoor", string.format(
			"Missing authored objective 'EscapeDoor'. Expected a persistent BasePart named '%s'.",
			interactPartNames.EscapeDoor
		))
	end
	local escapeDoor = if allowFallback or existingEscapeTrigger or existingEscapeVisual then ensureEscapeDoorSetup(map) else nil
	local decoy = makePart(map, "DecoyBottle", interactPartNames.DecoyBottle, Vector3.new(106.5, 3, -13), Vector3.new(1, 2, 1), Color3.fromRGB(120, 190, 180), Enum.Material.Glass, allowFallback)
	local landmark = makePart(map, "AudioLandmark", "AudioLandmark", Vector3.new(93.5, 4, -39), Vector3.new(2, 4, 2), Color3.fromRGB(255, 125, 40), Enum.Material.Neon, allowFallback)

	for _, itemId in ipairs({ "Flashlight", "Keycard", "Fuse", "DecoyBottle" }) do
		cacheItemArtTemplate(itemId)
	end

	if keycard then keycard.CanCollide = false end
	if fuse then fuse.CanCollide = false end
	if decoy then decoy.CanCollide = false end
	prepareFuseBoxes()

	for _, part in pairs({ keycard, fuse, repairPanel, decoy, landmark }) do
		CollectionService:AddTag(part, REVEAL_TAG)
	end
	if keycard then
		tagObjective(keycard, "Keycard")
		keycard:SetAttribute("EquipSlot", "Inventory")
	end
	if fuse then
		tagObjective(fuse, "Fuse")
		fuse:SetAttribute("EquipSlot", "Inventory")
	end
	if repairPanel then
		tagObjective(repairPanel, "RepairPanel")
		repairPanel:SetAttribute("EquipSlot", "World")
	end
	if decoy then
		tagObjective(decoy, "DecoyBottle")
		decoy:SetAttribute("EquipSlot", "Inventory")
		decoy:SetAttribute("ViewModelWhenEquipped", true)
	end
	if landmark then
		landmark:SetAttribute("ObjectiveName", "AudioLandmark")
		landmark:SetAttribute("EquipSlot", "World")
		landmark:SetAttribute("ViewModelWhenEquipped", false)

		local sound = landmark:FindFirstChild("AmbientLoop")
		if not sound then
			sound = Instance.new("Sound")
			sound.Name = "AmbientLoop"
			sound.Looped = true
			sound.Volume = 0.35
			sound.RollOffMaxDistance = 65
			sound.RollOffMinDistance = 8
			sound.SoundId = SOUND_IDS.ambientLandmark
			sound.Parent = landmark
		end
		sound:Play()
	end

	if authoredMap then
		validateAuthoredMapSetup(authoredMap)
	end
end

local function sendStatus(player, text, statusType)
	objectiveStatusEvent:FireClient(player, text, statusType or "sub")
end

local function broadcastStatus(text, statusType)
	for _, player in ipairs(Players:GetPlayers()) do
		sendStatus(player, text, statusType)
	end
end

local function isEscaped(player): boolean
	local state = getPlayerState(player)
	return state.escaped == true or player:GetAttribute("Escaped") == true
end

local function isCloseEnough(player, part)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	return (rootPart.Position - part.Position).Magnitude <= INTERACT_RANGE
end

local function getCollectibleRoot(part: BasePart, objectiveName: string): Instance
	local current = part.Parent
	while current and current ~= workspace do
		if current:IsA("Model") and (current.Name == objectiveName or current:GetAttribute("ObjectiveName") == objectiveName) then
			return current
		end
		current = current.Parent
	end

	return part
end

local function hideCollectedInstance(instance: Instance)
	instance:SetAttribute("Collected", true)

	if instance:IsA("BasePart") then
		instance.Transparency = 1
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance:SetAttribute("Collected", true)
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = 1
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = false
	elseif instance:IsA("Highlight") or instance:IsA("SelectionBox") then
		instance:Destroy()
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		descendant:SetAttribute("Collected", true)

		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant:SetAttribute("Collected", true)
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = false
		elseif descendant:IsA("Highlight") or descendant:IsA("SelectionBox") then
			descendant:Destroy()
		end
	end
end

local function showCollectibleInstance(instance: Instance)
	instance:SetAttribute("Collected", false)

	if instance:IsA("BasePart") then
		if instance.Name:find("Interact") then
			instance.Transparency = 1
			instance.CanCollide = false
			instance.CanTouch = true
			instance.CanQuery = true
		else
			instance.Transparency = 0
			instance.CanTouch = true
			instance.CanQuery = true
		end
		instance:SetAttribute("Collected", false)
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = 0
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = true
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		descendant:SetAttribute("Collected", false)

		if descendant:IsA("BasePart") then
			if descendant.Name:find("Interact") then
				descendant.Transparency = 1
				descendant.CanCollide = false
				descendant.CanTouch = true
				descendant.CanQuery = true
			else
				descendant.Transparency = 0
				descendant.CanTouch = true
				descendant.CanQuery = true
			end
			descendant:SetAttribute("Collected", false)
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 0
		elseif descendant:IsA("SurfaceGui") or descendant:IsA("BillboardGui") then
			descendant.Enabled = true
		end
	end
end

local function setCollected(part: BasePart, objectiveName: string)
	local root = getCollectibleRoot(part, objectiveName)
	hideCollectedInstance(root)
	part:SetAttribute("Collected", true)
	root:SetAttribute("Collected", true)
end

local function isCollectibleCollected(part: BasePart, objectiveName: string): boolean
	local root = getCollectibleRoot(part, objectiveName)
	return part:GetAttribute("Collected") == true or root:GetAttribute("Collected") == true
end

local function restoreCollectible(objectiveName: string)
	local part = findObjectivePart(objectiveName)
	if not part then return end

	local root = getCollectibleRoot(part, objectiveName)
	showCollectibleInstance(root)
	part:SetAttribute("Collected", false)
	root:SetAttribute("Collected", false)
	if objectiveName == "Fuse" then
		part.CanCollide = false
	end
end

local function tryAddInventoryPickup(player, itemId: string): boolean
	if addItem(player, itemId) then
		return true
	end

	local item = InventoryDefinitions.getItem(itemId)
	sendStatus(player, string.format("Not enough room for %s.", item.name), "sub")
	return false
end

local function openEscapeDoor()
	local visual = findEscapeDoorVisual()
	if not visual then return end

	if visual:IsA("BasePart") then
		visual.Position = visual:GetAttribute("OpenPosition") or (visual.Position + ESCAPE_DOOR_OPEN_OFFSET)
		visual.CanCollide = false
	elseif visual:IsA("Model") then
		visual:PivotTo(visual:GetAttribute("OpenPivot") or (visual:GetPivot() + ESCAPE_DOOR_OPEN_OFFSET))
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("BasePart") and not isEscapeDoorTrigger(descendant) then
				descendant.CanCollide = false
			end
		end
	end

	local trigger = findEscapeDoorTrigger()
	if trigger then
		trigger.CanCollide = false
		trigger.CanTouch = true
		trigger.CanQuery = true
		trigger.Transparency = 1
	end
end

local function cancelRepair(player, message: string?)
	local session = repairSessions[player]
	if session then
		session.cancelled = true
		repairSessions[player] = nil
	end

	objectiveStatusEvent:FireClient(player, "", "repairCancel")
	if message then
		sendStatus(player, message, "sub")
	end
end

local function canRepair(player, part: BasePart): (boolean, string?)
	if isEscaped(player) then
		return false, nil
	end
	if objectiveState.repaired then
		return false, "Power is already restored."
	end
	if objectiveState.fuseHolder ~= player or not hasItem(player, "Fuse") then
		return false, "The panel needs the fuse carrier."
	end
	if not isCloseEnough(player, part) then
		return false, nil
	end

	return true, nil
end

local function completeRepair(player, part: BasePart)
	local canComplete, message = canRepair(player, part)
	if not canComplete then
		cancelRepair(player, message)
		return
	end

	objectiveState.repaired = true
	objectiveState.fuseHolder = nil
	repairSessions[player] = nil
	removeItem(player, "Fuse")

	if not showConnectedFuseBox() then
		part.Color = Color3.fromRGB(80, 255, 140)
	end

	openEscapeDoor()
	playWorldSound(part, "PanelRepair", SOUND_IDS.panelRepair, 0.75, 65)
	objectiveStatusEvent:FireClient(player, "", "repairComplete")
	broadcastStatus("Reach the escape door.", "main")
	broadcastStatus("Power restored.", "sub")
end

local function beginRepair(player)
	local part = findObjectivePart("RepairPanel")
	if not (part and part:IsA("BasePart")) then return end

	local canBegin, message = canRepair(player, part)
	if not canBegin then
		cancelRepair(player, message)
		return
	end
	if repairSessions[player] then
		return
	end

	local session = {
		cancelled = false,
		part = part,
		startedAt = os.clock(),
	}
	repairSessions[player] = session
	sendStatus(player, "Repairing panel...", "sub")

	task.spawn(function()
		while repairSessions[player] == session and not session.cancelled do
			local elapsed = os.clock() - session.startedAt
			if elapsed >= REPAIR_DURATION then
				break
			end

			local canContinue, cancelMessage = canRepair(player, part)
			if not canContinue then
				cancelRepair(player, cancelMessage)
				return
			end

			task.wait(0.1)
		end

		if repairSessions[player] == session and not session.cancelled then
			completeRepair(player, part)
		end
	end)
end

local function hideEscapedCharacter(player)
	local character = player.Character
	if not character then return end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("Decal") then
			descendant.Transparency = 1
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	end
end

local function setPlayerEscaped(player)
	local state = getPlayerState(player)
	if state.escaped then
		return false
	end

	state.escaped = true
	player:SetAttribute("Escaped", true)
	hideEscapedCharacter(player)
	return true
end

local function interact(player, objectiveName)
	if isEscaped(player) then return end

	local part = findObjectivePart(objectiveName)
	if not (part and part:IsA("BasePart")) then return end
	if not isCloseEnough(player, part) then return end

	local state = getPlayerState(player)

	if objectiveName == "Keycard" then
		if objectiveState.keycardAcquired then
			sendStatus(player, "The keycard is already gone.", "sub")
			return
		end
		if isCollectibleCollected(part, objectiveName) then
			sendStatus(player, "The keycard is already gone.", "sub")
			return
		end
		if not tryAddInventoryPickup(player, "Keycard") then return end

		objectiveState.keycardAcquired = true
		playWorldSound(part, "ObjectivePickup", SOUND_IDS.pickup, 0.45, 45)
		setCollected(part, objectiveName)
		broadcastStatus("Find the fuse.", "main")
		broadcastStatus(player.Name .. " acquired the keycard.", "sub")
	elseif objectiveName == "Fuse" then
		if not objectiveState.keycardAcquired then
			sendStatus(player, "The fuse case is locked. Find the keycard.", "sub")
			return
		end
		if objectiveState.fuseHolder then
			sendStatus(player, "The fuse is already being carried.", "sub")
			return
		end
		if isCollectibleCollected(part, objectiveName) then
			sendStatus(player, "The fuse is already being carried.", "sub")
			return
		end
		local consumedKeycard = removeItem(player, "Keycard")
		if not tryAddInventoryPickup(player, "Fuse") then
			if consumedKeycard then
				addItem(player, "Keycard")
			end
			return
		end

		objectiveState.fuseHolder = player
		playWorldSound(part, "ObjectivePickup", SOUND_IDS.pickup, 0.45, 45)
		setCollected(part, objectiveName)
		broadcastStatus("Restore power at the repair panel.", "main")
		broadcastStatus(player.Name .. " acquired the fuse.", "sub")
	elseif objectiveName == "RepairPanel" then
		if objectiveState.repaired then
			sendStatus(player, "Power is already restored.", "sub")
			return
		end
		beginRepair(player)
	elseif objectiveName == "EscapeDoor" then
		if not objectiveState.repaired then
			sendStatus(player, "Escape door is locked. Repair ship systems first.", "sub")
			return
		end
		if not setPlayerEscaped(player) then return end

		playWorldSound(part, "EscapeSuccess", SOUND_IDS.escapeSuccess, 0.85, 90)
		local survivedTime, score = getSurvivalStats(state)
		gameOutcomeEvent:FireClient(player, {
			outcome = "win",
			survivedTime = survivedTime,
			score = score,
			spectate = true,
		})
		sendStatus(player, "You escaped. Spectating survivors.", "main")
	elseif objectiveName == "DecoyBottle" then
		if isCollectibleCollected(part, objectiveName) then
			sendStatus(player, "The bottle is already gone.", "sub")
			return
		end
		if not tryAddInventoryPickup(player, "DecoyBottle") then return end

		playWorldSound(part, "ObjectivePickup", SOUND_IDS.pickup, 0.4, 45)
		setCollected(part, objectiveName)
		sendStatus(player, "Decoy bottle acquired. Equip it, then press G to throw.", "sub")
	end
end

local function throwDecoy(player, origin, direction)
	if isEscaped(player) then return end
	if not hasItem(player, "DecoyBottle") then
		sendStatus(player, "No decoy bottle available.", "sub")
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	if not removeItem(player, "DecoyBottle") then
		sendStatus(player, "No decoy bottle available.", "sub")
		return
	end

	local safeDirection = if typeof(direction) == "Vector3" and direction.Magnitude > 0 then direction.Unit else rootPart.CFrame.LookVector
	local spawnPosition = if typeof(origin) == "Vector3" then origin else (rootPart.Position + Vector3.new(0, 2, 0))
	if (spawnPosition - rootPart.Position).Magnitude > 12 then
		spawnPosition = rootPart.Position + Vector3.new(0, 2, 0)
	end

	local bottle = cloneItemArt("DecoyBottle", "ThrownDecoyBottle")
	if not bottle then
		bottle = Instance.new("Model")
		bottle.Name = "ThrownDecoyBottle"
		local fallback = Instance.new("Part")
		fallback.Name = "BottleBody"
		fallback.Shape = Enum.PartType.Cylinder
		fallback.Size = Vector3.new(1.55, 0.48, 0.48)
		fallback.Material = Enum.Material.Glass
		fallback.Color = Color3.fromRGB(130, 210, 220)
		fallback.Transparency = 0.18
		fallback.Parent = bottle
	end

	bottle.Parent = workspace
	local body = makeThrownItemPhysical(bottle)
	if not body then
		bottle:Destroy()
		addItem(player, "DecoyBottle")
		sendStatus(player, "Could not throw the bottle.", "sub")
		return
	end

	bottle:PivotTo(CFrame.new(spawnPosition) * CFrame.Angles(math.rad(-12), math.rad(18), math.rad(20)))
	body.AssemblyLinearVelocity = (safeDirection * 85) + Vector3.new(0, 18, 0)
	body.AssemblyAngularVelocity = Vector3.new(4, 9, 2)
	playWorldSound(body, "DecoyThrow", SOUND_IDS.decoyThrow, 0.25, 35)

	local hasShattered = false
	local thrownAt = os.clock()
	local touchedConnection: RBXScriptConnection? = nil

	local function spawnGlassShard(parent: Instance, position: Vector3, sourceVelocity: Vector3)
		local shard = Instance.new("Part")
		shard.Name = "DecoyGlassShard"
		shard.Anchored = false
		shard.CanCollide = true
		shard.CanTouch = false
		shard.CanQuery = true
		shard.Size = Vector3.new(
			0.18 + (math.random() * 0.28),
			0.04 + (math.random() * 0.08),
			0.12 + (math.random() * 0.24)
		)
		shard.CFrame = CFrame.new(position + Vector3.new(
			(math.random() - 0.5) * 0.8,
			math.random() * 0.35,
			(math.random() - 0.5) * 0.8
		)) * CFrame.Angles(math.random() * math.pi, math.random() * math.pi, math.random() * math.pi)
		shard.Material = Enum.Material.Glass
		shard.Color = Color3.fromRGB(150, 230, 235)
		shard.Transparency = 0.22
		shard.Parent = parent
		shard.AssemblyLinearVelocity = (sourceVelocity * 0.18) + Vector3.new(
			(math.random() - 0.5) * 24,
			8 + (math.random() * 16),
			(math.random() - 0.5) * 24
		)
		shard.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 18,
			(math.random() - 0.5) * 18,
			(math.random() - 0.5) * 18
		)
		CollectionService:AddTag(shard, REVEAL_TAG)
	end

	local function shatterDecoy()
		if hasShattered then return end
		hasShattered = true
		if touchedConnection then
			touchedConnection:Disconnect()
			touchedConnection = nil
		end

		local impactPosition = body.Position
		local impactVelocity = body.AssemblyLinearVelocity
		bottle:Destroy()

		local shardFolder = Instance.new("Folder")
		shardFolder.Name = "DecoyBottleShards"
		shardFolder.Parent = workspace
		for _ = 1, DECOY_SHARD_COUNT do
			spawnGlassShard(shardFolder, impactPosition, impactVelocity)
		end

		playAnchoredWorldSound(impactPosition, "DecoyShatter", SOUND_IDS.decoyShatter, 1.1, 120)
		serverNoiseEvent:Fire({
			position = impactPosition,
			intensity = 2.2,
			movementState = "decoy",
			decay = 9,
		})

		Debris:AddItem(shardFolder, 5)
	end

	touchedConnection = body.Touched:Connect(function(hit)
		if hasShattered or os.clock() - thrownAt < 0.15 then return end
		if not hit or not hit.Parent then return end
		if hit:IsDescendantOf(bottle) then return end
		if character and hit:IsDescendantOf(character) then return end
		shatterDecoy()
	end)

	task.delay(DECOY_SHATTER_FALLBACK_SECONDS, function()
		if bottle.Parent and not hasShattered then
			shatterDecoy()
		end
	end)

	Debris:AddItem(bottle, 12)
	sendStatus(player, "Decoy thrown.", "sub")
end

-- Initializes objective remotes, authored world props, inventories, and cleanup hooks.
function ObjectiveSystem.init()
	ensureObjectiveProps()

	for _, player in ipairs(Players:GetPlayers()) do
		getPlayerState(player)
		sendInventory(player)
	end

	Players.PlayerAdded:Connect(function(player)
		getPlayerState(player)
		sendInventory(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		cancelRepair(player)
		if objectiveState.fuseHolder == player then
			objectiveState.fuseHolder = nil
			if not objectiveState.repaired then
				restoreCollectible("Fuse")
			end
		end
		playerState[player] = nil
		inventories[player] = nil
		lastDecoyThrowAt[player] = nil
		lastObjectiveInteractAt[player] = nil
		lastRepairActionAt[player] = nil
	end)

	objectiveEvent.OnServerEvent:Connect(function(player, objectiveName, action)
		if typeof(objectiveName) ~= "string" then return end
		if not isKnownObjectiveName(objectiveName) then return end

		local now = os.clock()
		if objectiveName == "RepairPanel" and action == "BeginRepair" then
			if now - (lastRepairActionAt[player] or 0) < OBJECTIVE_REPAIR_COOLDOWN then
				return
			end
			lastRepairActionAt[player] = now
			beginRepair(player)
			return
		elseif objectiveName == "RepairPanel" and action == "CancelRepair" then
			if now - (lastRepairActionAt[player] or 0) < OBJECTIVE_REPAIR_COOLDOWN then
				return
			end
			lastRepairActionAt[player] = now
			cancelRepair(player)
			return
		end

		if now - (lastObjectiveInteractAt[player] or 0) < OBJECTIVE_INTERACT_COOLDOWN then
			return
		end
		lastObjectiveInteractAt[player] = now
		interact(player, objectiveName)
	end)

	decoyThrowEvent.OnServerEvent:Connect(function(player, origin, direction)
		local now = os.clock()
		if now - (lastDecoyThrowAt[player] or 0) < DECOY_THROW_COOLDOWN then
			return
		end
		lastDecoyThrowAt[player] = now
		throwDecoy(player, origin, direction)
	end)
end

return ObjectiveSystem

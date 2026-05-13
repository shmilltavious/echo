-- Server-side objective chain, inventory authority, and throwable decoys
local ObjectiveSystem = {}

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryDefinitions = require(ReplicatedStorage.Shared.InventoryDefinitions)

local OBJECTIVE_TAG = "Objective"
local REVEAL_TAG = "EcholocationReveal"
local INTERACT_RANGE = 16
local SOUND_IDS = {
	pickup = "rbxassetid://9112854440",
	panelRepair = "rbxassetid://9112854440",
	escapeSuccess = "rbxassetid://9112854440",
	decoyImpact = "rbxassetid://9113420772",
}

local objectiveOrder = {
	Keycard = 1,
	Fuse = 2,
	RepairPanel = 3,
	EscapeDoor = 4,
	DecoyBottle = 0,
}

local interactPartNames = {
	Keycard = "KeycardInteract",
	Fuse = "FuseInteract",
	RepairPanel = "RepairPanelInteract",
	EscapeDoor = "EscapeDoorInteract",
	DecoyBottle = "DecoyBottleInteract",
}

local playerState = {}
local inventories = {}
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
			items = {},
		}
		inventories[player] = inventory
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

local function getInventoryPayload(player)
	local payloadItems = {}
	for _, itemId in ipairs(getInventory(player).items) do
		local item = InventoryDefinitions.getItem(itemId)
		table.insert(payloadItems, {
			id = item.id,
			name = item.name,
			weight = InventoryDefinitions.getWeight(itemId),
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

local function getSurvivalStats(state)
	local survivedTime = math.max(0, os.clock() - (state.startedAt or os.clock()))
	local score = math.floor(500 + (survivedTime * 12))
	return survivedTime, score
end

local function ensureMap()
	local map = workspace:FindFirstChild("Prototype_Map")
	if not map then
		map = Instance.new("Folder")
		map.Name = "Prototype_Map"
		map.Parent = workspace
	end
	return map
end

local function getBasePartFromCandidate(candidate: Instance?, objectiveName: string): BasePart?
	if not candidate then
		return nil
	end
	if candidate:IsA("BasePart") then
		return candidate
	end
	if candidate:IsA("Model") then
		if candidate.PrimaryPart then
			return candidate.PrimaryPart
		end

		local interactName = interactPartNames[objectiveName]
		local interactPart = interactName and candidate:FindFirstChild(interactName, true)
		if interactPart and interactPart:IsA("BasePart") then
			return interactPart
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

local function makePart(parent, objectiveName, name, position, size, color, material)
	local existing = findAuthoredObjectivePart(objectiveName)
	if existing then
		return existing
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
	return findAuthoredObjectivePart(objectiveName)
end

local function ensureObjectiveProps()
	local map = ensureMap()

	local keycard = makePart(map, "Keycard", interactPartNames.Keycard, Vector3.new(80.5, 3, 26), Vector3.new(2, 0.2, 1.2), Color3.fromRGB(45, 170, 255), Enum.Material.Neon)
	local fuse = makePart(map, "Fuse", interactPartNames.Fuse, Vector3.new(132.5, 3, 13), Vector3.new(1.2, 1.2, 2.5), Color3.fromRGB(255, 210, 70), Enum.Material.Metal)
	local repairPanel = makePart(map, "RepairPanel", interactPartNames.RepairPanel, Vector3.new(151.2, 5, -32.5), Vector3.new(4, 6, 0.6), Color3.fromRGB(85, 130, 120), Enum.Material.Metal)
	local escapeDoor = makePart(map, "EscapeDoor", interactPartNames.EscapeDoor, Vector3.new(158.5, 6, 39), Vector3.new(7, 10, 1), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	local decoy = makePart(map, "DecoyBottle", interactPartNames.DecoyBottle, Vector3.new(106.5, 3, -13), Vector3.new(1, 2, 1), Color3.fromRGB(120, 190, 180), Enum.Material.Glass)
	local landmark = makePart(map, "AudioLandmark", "AudioLandmark", Vector3.new(93.5, 4, -39), Vector3.new(2, 4, 2), Color3.fromRGB(255, 125, 40), Enum.Material.Neon)

	keycard.CanCollide = false
	fuse.CanCollide = false
	decoy.CanCollide = false
	if escapeDoor:GetAttribute("ClosedPosition") == nil then
		escapeDoor:SetAttribute("ClosedPosition", escapeDoor.Position)
	end
	if escapeDoor:GetAttribute("OpenPosition") == nil then
		escapeDoor:SetAttribute("OpenPosition", escapeDoor.Position + Vector3.new(0, 12, 0))
	end

	for _, part in ipairs({ keycard, fuse, repairPanel, escapeDoor, decoy, landmark }) do
		CollectionService:AddTag(part, REVEAL_TAG)
	end
	tagObjective(keycard, "Keycard")
	tagObjective(fuse, "Fuse")
	tagObjective(repairPanel, "RepairPanel")
	tagObjective(escapeDoor, "EscapeDoor")
	tagObjective(decoy, "DecoyBottle")
	keycard:SetAttribute("EquipSlot", "Inventory")
	fuse:SetAttribute("EquipSlot", "Inventory")
	decoy:SetAttribute("EquipSlot", "Inventory")
	decoy:SetAttribute("ViewModelWhenEquipped", true)
	decoy:SetAttribute("ViewModelNote", "Replace with a right-hand bottle/tool viewmodel when equipped.")
	repairPanel:SetAttribute("EquipSlot", "World")
	escapeDoor:SetAttribute("EquipSlot", "World")
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
		sound.SoundId = "rbxassetid://9112854440"
		sound.Parent = landmark
	end
	sound:Play()
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
	if instance:IsA("BasePart") then
		instance.Transparency = 0
		instance.CanTouch = true
		instance.CanQuery = true
		instance:SetAttribute("Collected", false)
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		instance.Transparency = 0
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		instance.Enabled = true
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 0
			descendant.CanTouch = true
			descendant.CanQuery = true
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
	local door = findObjectivePart("EscapeDoor")
	if not door then return end
	door.Position = door:GetAttribute("OpenPosition") or (door.Position + Vector3.new(0, 12, 0))
	door.CanCollide = false
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
		if not tryAddInventoryPickup(player, "Fuse") then return end

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
		if objectiveState.fuseHolder ~= player or not hasItem(player, "Fuse") then
			sendStatus(player, "The panel needs the fuse carrier.", "sub")
			return
		end

		objectiveState.repaired = true
		objectiveState.fuseHolder = nil
		removeItem(player, "Fuse")
		part.Color = Color3.fromRGB(80, 255, 140)
		openEscapeDoor()
		playWorldSound(part, "PanelRepair", SOUND_IDS.panelRepair, 0.75, 65)
		broadcastStatus("Reach the escape door.", "main")
		broadcastStatus("Power restored.", "sub")
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
		if not tryAddInventoryPickup(player, "DecoyBottle") then return end

		playWorldSound(part, "ObjectivePickup", SOUND_IDS.pickup, 0.4, 45)
		setCollected(part, objectiveName)
		sendStatus(player, "Decoy bottle acquired. Press G to throw it.", "sub")
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

	local bottle = Instance.new("Part")
	bottle.Name = "ThrownDecoy"
	bottle.Shape = Enum.PartType.Ball
	bottle.Size = Vector3.new(1, 1, 1)
	bottle.Material = Enum.Material.Glass
	bottle.Color = Color3.fromRGB(130, 210, 220)
	bottle.Position = spawnPosition
	bottle.CanCollide = true
	bottle.Parent = workspace
	CollectionService:AddTag(bottle, REVEAL_TAG)

	bottle.AssemblyLinearVelocity = (safeDirection * 85) + Vector3.new(0, 18, 0)
	bottle.AssemblyAngularVelocity = Vector3.new(4, 9, 2)

	local sound = Instance.new("Sound")
	sound.Name = "DecoyClatter"
	sound.SoundId = SOUND_IDS.decoyImpact
	sound.Volume = 1.1
	sound.RollOffMaxDistance = 120
	sound.Parent = bottle

	task.delay(0.45, function()
		if bottle.Parent then
			sound:Play()
			serverNoiseEvent:Fire({
				position = bottle.Position,
				intensity = 2.2,
				movementState = "decoy",
				decay = 9,
			})
		end
	end)

	Debris:AddItem(bottle, 12)
	sendStatus(player, "Decoy thrown.", "sub")
end

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
		if objectiveState.fuseHolder == player then
			objectiveState.fuseHolder = nil
			if not objectiveState.repaired then
				restoreCollectible("Fuse")
			end
		end
		playerState[player] = nil
		inventories[player] = nil
	end)

	objectiveEvent.OnServerEvent:Connect(function(player, objectiveName)
		if typeof(objectiveName) ~= "string" then return end
		interact(player, objectiveName)
	end)

	decoyThrowEvent.OnServerEvent:Connect(function(player, origin, direction)
		throwDecoy(player, origin, direction)
	end)
end

return ObjectiveSystem

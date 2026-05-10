-- Server-side objective chain and throwable decoy prototype
local ObjectiveSystem = {}

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OBJECTIVE_TAG = "Objective"
local REVEAL_TAG = "EcholocationReveal"
local INTERACT_RANGE = 16

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

local objectiveEvent = ReplicatedStorage:FindFirstChild("ObjectiveInteract") or Instance.new("RemoteEvent")
objectiveEvent.Name = "ObjectiveInteract"
objectiveEvent.Parent = ReplicatedStorage

local objectiveStatusEvent = ReplicatedStorage:FindFirstChild("ObjectiveStatus") or Instance.new("RemoteEvent")
objectiveStatusEvent.Name = "ObjectiveStatus"
objectiveStatusEvent.Parent = ReplicatedStorage

local decoyThrowEvent = ReplicatedStorage:FindFirstChild("DecoyThrow") or Instance.new("RemoteEvent")
decoyThrowEvent.Name = "DecoyThrow"
decoyThrowEvent.Parent = ReplicatedStorage

local serverNoiseEvent = ReplicatedStorage:FindFirstChild("ServerNoiseEvent") or Instance.new("BindableEvent")
serverNoiseEvent.Name = "ServerNoiseEvent"
serverNoiseEvent.Parent = ReplicatedStorage

local function getPlayerState(player)
	local state = playerState[player]
	if not state then
		state = {
			hasKeycard = false,
			hasFuse = false,
			repaired = false,
			escaped = false,
			decoys = 0,
		}
		playerState[player] = state
	end
	return state
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

local function makePart(parent, name, position, size, color, material, legacyName)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("BasePart") then
		return existing
	end

	if legacyName then
		local legacy = parent:FindFirstChild(legacyName)
		if legacy and legacy:IsA("BasePart") then
			legacy.Name = name
			return legacy
		end
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
	CollectionService:AddTag(part, OBJECTIVE_TAG)
	CollectionService:AddTag(part, REVEAL_TAG)
	part:SetAttribute("ObjectiveName", objectiveName)
	part:SetAttribute("ObjectiveOrder", objectiveOrder[objectiveName] or 0)
	part:SetAttribute("ViewModelWhenEquipped", false)
end

local function findObjectivePart(objectiveName)
	for _, instance in ipairs(CollectionService:GetTagged(OBJECTIVE_TAG)) do
		if instance:IsA("BasePart") and instance:GetAttribute("ObjectiveName") == objectiveName then
			return instance
		end
	end

	local map = ensureMap()
	local interactName = interactPartNames[objectiveName]
	local directPart = interactName and map:FindFirstChild(interactName, true)
	if directPart and directPart:IsA("BasePart") then
		return directPart
	end

	local legacyPart = map:FindFirstChild(objectiveName)
	if legacyPart and legacyPart:IsA("BasePart") then
		return legacyPart
	end

	return nil
end

local function ensureObjectiveProps()
	local map = ensureMap()

	local keycard = makePart(map, interactPartNames.Keycard, Vector3.new(80.5, 3, 26), Vector3.new(2, 0.2, 1.2), Color3.fromRGB(45, 170, 255), Enum.Material.Neon, "Keycard")
	local fuse = makePart(map, interactPartNames.Fuse, Vector3.new(132.5, 3, 13), Vector3.new(1.2, 1.2, 2.5), Color3.fromRGB(255, 210, 70), Enum.Material.Metal, "Fuse")
	local repairPanel = makePart(map, interactPartNames.RepairPanel, Vector3.new(151.2, 5, -32.5), Vector3.new(4, 6, 0.6), Color3.fromRGB(85, 130, 120), Enum.Material.Metal, "RepairPanel")
	local escapeDoor = makePart(map, interactPartNames.EscapeDoor, Vector3.new(158.5, 6, 39), Vector3.new(7, 10, 1), Color3.fromRGB(90, 90, 100), Enum.Material.Metal, "EscapeDoor")
	local decoy = makePart(map, interactPartNames.DecoyBottle, Vector3.new(106.5, 3, -13), Vector3.new(1, 2, 1), Color3.fromRGB(120, 190, 180), Enum.Material.Glass, "DecoyBottle")
	local landmark = makePart(map, "AudioLandmark", Vector3.new(93.5, 4, -39), Vector3.new(2, 4, 2), Color3.fromRGB(255, 125, 40), Enum.Material.Neon)

	keycard.CanCollide = false
	fuse.CanCollide = false
	decoy.CanCollide = false
	repairPanel.CFrame = CFrame.new(repairPanel.Position) * CFrame.Angles(0, math.rad(90), 0)
	escapeDoor:SetAttribute("ClosedPosition", escapeDoor.Position)
	escapeDoor:SetAttribute("OpenPosition", escapeDoor.Position + Vector3.new(0, 12, 0))

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
	decoy:SetAttribute("EquipSlot", "RightHand")
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

local function isCloseEnough(player, part)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	return (rootPart.Position - part.Position).Magnitude <= INTERACT_RANGE
end

local function setCollected(part)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part:SetAttribute("Collected", true)
end

local function interact(player, objectiveName)
	local part = findObjectivePart(objectiveName)
	if not (part and part:IsA("BasePart")) then return end
	if not isCloseEnough(player, part) then return end

	local state = getPlayerState(player)

	if objectiveName == "Keycard" then
		if state.hasKeycard then return end
		state.hasKeycard = true
		setCollected(part)
		sendStatus(player, "Find the fuse.", "main")
		sendStatus(player, "Keycard acquired.", "sub")
	elseif objectiveName == "Fuse" then
		if not state.hasKeycard then
			sendStatus(player, "The fuse case is locked. Find the keycard.", "sub")
			return
		end
		if state.hasFuse then return end
		state.hasFuse = true
		setCollected(part)
		sendStatus(player, "Restore power at the repair panel.", "main")
		sendStatus(player, "Fuse acquired.", "sub")
	elseif objectiveName == "RepairPanel" then
		if not state.hasFuse then
			sendStatus(player, "The panel is dead. Find the fuse.", "sub")
			return
		end
		if state.repaired then return end
		state.repaired = true
		part.Color = Color3.fromRGB(80, 255, 140)
		sendStatus(player, "Reach the escape door.", "main")
		sendStatus(player, "Power restored.", "sub")
	elseif objectiveName == "EscapeDoor" then
		if not state.repaired then
			sendStatus(player, "Escape door is locked. Repair ship systems first.", "sub")
			return
		end
		if state.escaped then return end
		state.escaped = true
		part.Position = part:GetAttribute("OpenPosition") or (part.Position + Vector3.new(0, 12, 0))
		part.CanCollide = false
		sendStatus(player, "Escape route open.", "main")
		sendStatus(player, "You survived the prototype.", "sub")
	elseif objectiveName == "DecoyBottle" then
		state.decoys += 1
		setCollected(part)
		sendStatus(player, "Decoy bottle acquired. Press G to throw it.", "sub")
	end
end

local function throwDecoy(player, origin, direction)
	local state = getPlayerState(player)
	if state.decoys <= 0 then
		sendStatus(player, "No decoy bottle available.", "sub")
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	state.decoys -= 1

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
	sound.SoundId = "rbxassetid://9113420772"
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

	objectiveEvent.OnServerEvent:Connect(function(player, objectiveName)
		if typeof(objectiveName) ~= "string" then return end
		interact(player, objectiveName)
	end)

	decoyThrowEvent.OnServerEvent:Connect(function(player, origin, direction)
		throwDecoy(player, origin, direction)
	end)
end

return ObjectiveSystem

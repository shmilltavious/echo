local EquipmentClient = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InventoryDefinitions = require(ReplicatedStorage.Shared.InventoryDefinitions)

local FLASHLIGHT_ITEM_ID = "Flashlight"
local SLOT_KEYCODES = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}

local initialized = false
local equippedItemId = FLASHLIGHT_ITEM_ID
local equippedSlot = 1
local capacity = InventoryDefinitions.CAPACITY
local items = {}
local slots = {}
local listeners = {}

local defaultPayload = {
	capacity = InventoryDefinitions.CAPACITY,
	items = {
		{
			id = FLASHLIGHT_ITEM_ID,
			name = InventoryDefinitions.getItem(FLASHLIGHT_ITEM_ID).name,
			weight = InventoryDefinitions.getWeight(FLASHLIGHT_ITEM_ID),
		},
	},
}

local function makeSlotLabel(slotStart: number?, slotEnd: number?): string
	if not slotStart then
		return ""
	end
	if slotEnd and slotEnd ~= slotStart then
		return tostring(slotStart) .. "-" .. tostring(slotEnd)
	end
	return tostring(slotStart)
end

local function findContiguousSlot(weight: number, occupied): number?
	for startSlot = 2, capacity do
		local endSlot = startSlot + weight - 1
		if endSlot > capacity then
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

local function hasEquippedItem(): boolean
	for _, item in ipairs(items) do
		if item.id == equippedItemId then
			return true
		end
	end
	return false
end

local function notify()
	for _, listener in ipairs(listeners) do
		task.spawn(listener, {
			capacity = capacity,
			items = items,
			slots = slots,
			equippedItemId = equippedItemId,
			equippedSlot = equippedSlot,
		})
	end
end

local function applyPayload(payload)
	if typeof(payload) ~= "table" then
		payload = defaultPayload
	end

	capacity = math.max(1, tonumber(payload.capacity) or InventoryDefinitions.CAPACITY)
	local ordered = {}
	local sawFlashlight = false

	if typeof(payload.items) == "table" then
		for _, payloadItem in ipairs(payload.items) do
			local itemId = tostring(payloadItem.id or "")
			if itemId == FLASHLIGHT_ITEM_ID then
				sawFlashlight = true
				table.insert(ordered, 1, payloadItem)
			elseif itemId ~= "" then
				table.insert(ordered, payloadItem)
			end
		end
	end

	if not sawFlashlight then
		table.insert(ordered, 1, defaultPayload.items[1])
	end

	local nextItems = {}
	local nextSlots = {}
	local occupied = {}

	for _, payloadItem in ipairs(ordered) do
		local itemId = tostring(payloadItem.id or "")
		local definition = InventoryDefinitions.getItem(itemId)
		local weight = math.clamp(tonumber(payloadItem.weight) or definition.weight or 1, 1, capacity)
		local slotStart = tonumber(payloadItem.slotStart)
		local slotEnd = tonumber(payloadItem.slotEnd)

		if itemId == FLASHLIGHT_ITEM_ID then
			slotStart = 1
			slotEnd = 1
		elseif not slotStart then
			slotStart = findContiguousSlot(weight, occupied)
			slotEnd = if slotStart then slotStart + weight - 1 else nil
		end

		if slotStart and slotEnd and slotEnd <= capacity then
			for slot = slotStart, slotEnd do
				occupied[slot] = true
			end

			local item = {
				id = itemId,
				name = tostring(payloadItem.name or definition.name or itemId),
				weight = weight,
				color = definition.color,
				slotStart = slotStart,
				slotEnd = slotEnd,
				slotLabel = tostring(payloadItem.slotLabel or makeSlotLabel(slotStart, slotEnd)),
			}
			table.insert(nextItems, item)

			for slot = slotStart, slotEnd do
				nextSlots[slot] = item
			end
		end
	end

	items = nextItems
	slots = nextSlots

	if not hasEquippedItem() then
		equippedItemId = FLASHLIGHT_ITEM_ID
		equippedSlot = 1
	else
		local item = EquipmentClient.getItem(equippedItemId)
		equippedSlot = item and item.slotStart or 1
	end

	notify()
end

-- Initializes inventory state, slot hotkeys, and server inventory updates.
function EquipmentClient.init()
	if initialized then return end
	initialized = true

	applyPayload(defaultPayload)

	local inventoryEvent = ReplicatedStorage:WaitForChild("InventoryUpdate", 10)
	if inventoryEvent then
		inventoryEvent.OnClientEvent:Connect(applyPayload)
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		local slot = SLOT_KEYCODES[input.KeyCode]
		if slot then
			EquipmentClient.equipSlot(slot)
		end
	end)
end

-- Registers a listener that receives equipment state snapshots.
function EquipmentClient.onChanged(listener)
	table.insert(listeners, listener)
	listener({
		capacity = capacity,
		items = items,
		slots = slots,
		equippedItemId = equippedItemId,
		equippedSlot = equippedSlot,
	})

	return function()
		for index, existing in ipairs(listeners) do
			if existing == listener then
				table.remove(listeners, index)
				break
			end
		end
	end
end

-- Equips the item occupying a numbered inventory slot.
function EquipmentClient.equipSlot(slot: number): boolean
	local item = slots[slot]
	if not item then
		return false
	end

	if equippedItemId == item.id then
		return true
	end

	equippedItemId = item.id
	equippedSlot = item.slotStart or slot
	notify()
	return true
end

-- Equips a held item by ID when it is present in inventory.
function EquipmentClient.equipItem(itemId: string): boolean
	local item = EquipmentClient.getItem(itemId)
	if not item then
		return false
	end

	equippedItemId = item.id
	equippedSlot = item.slotStart or 1
	notify()
	return true
end

-- Returns the current inventory item payload for an item ID.
function EquipmentClient.getItem(itemId: string)
	for _, item in ipairs(items) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

-- Returns whether the current inventory contains an item ID.
function EquipmentClient.hasItem(itemId: string): boolean
	return EquipmentClient.getItem(itemId) ~= nil
end

-- Returns the ordered current inventory items.
function EquipmentClient.getItems()
	return items
end

-- Returns the current slot-to-item map.
function EquipmentClient.getSlots()
	return slots
end

-- Returns the equipped item ID.
function EquipmentClient.getEquippedItemId(): string
	return equippedItemId
end

-- Returns the equipped starting slot.
function EquipmentClient.getEquippedSlot(): number
	return equippedSlot
end

-- Returns whether an item ID is currently equipped.
function EquipmentClient.isEquipped(itemId: string): boolean
	return equippedItemId == itemId
end

return EquipmentClient

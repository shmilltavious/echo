local InventoryDefinitions = {}

InventoryDefinitions.CAPACITY = 3

InventoryDefinitions.ITEMS = {
	Flashlight = {
		id = "Flashlight",
		name = "Flashlight",
		weight = 1,
		color = Color3.fromRGB(208, 205, 190),
	},
	Keycard = {
		id = "Keycard",
		name = "Keycard",
		weight = 1,
		color = Color3.fromRGB(76, 180, 220),
	},
	Fuse = {
		id = "Fuse",
		name = "Fuse",
		weight = 2,
		color = Color3.fromRGB(236, 188, 72),
	},
	DecoyBottle = {
		id = "DecoyBottle",
		name = "Bottle",
		weight = 1,
		color = Color3.fromRGB(118, 198, 190),
	},
}

-- Returns an item definition, falling back to a generic one for unknown IDs.
function InventoryDefinitions.getItem(itemId: string)
	return InventoryDefinitions.ITEMS[itemId] or {
		id = itemId,
		name = itemId,
		weight = 1,
		color = Color3.fromRGB(170, 170, 160),
	}
end

-- Returns a safe positive inventory weight for an item ID.
function InventoryDefinitions.getWeight(itemId: string): number
	local item = InventoryDefinitions.getItem(itemId)
	return math.max(1, tonumber(item.weight) or 1)
end

return InventoryDefinitions

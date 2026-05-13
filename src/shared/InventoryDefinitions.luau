local InventoryDefinitions = {}

InventoryDefinitions.CAPACITY = 3

InventoryDefinitions.ITEMS = {
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

function InventoryDefinitions.getItem(itemId: string)
	return InventoryDefinitions.ITEMS[itemId] or {
		id = itemId,
		name = itemId,
		weight = 1,
		color = Color3.fromRGB(170, 170, 160),
	}
end

function InventoryDefinitions.getWeight(itemId: string): number
	local item = InventoryDefinitions.getItem(itemId)
	return math.max(1, tonumber(item.weight) or 1)
end

return InventoryDefinitions

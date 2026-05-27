local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)

local MapEcholocationSetup = {}

local REVEAL_TAG = Constants.OBJECTIVES.REVEAL_TAG
local AUTHORED_MAP_NAMES = Constants.OBJECTIVES.AUTHORED_MAP_NAMES
local MONSTER_MODEL_NAMES = {
	Monster = true,
	monster = true,
	Rig = true,
	["rigging (1)"] = true,
}

local MONSTER_TEXTURE_ATTRIBUTE_BY_PROPERTY = {
	ColorMap = "MonsterColorMap",
	NormalMap = "MonsterNormalMap",
	RoughnessMap = "MonsterRoughnessMap",
	MetalnessMap = "MonsterMetalnessMap",
}

local HELPER_NAME_PATTERNS = {
	"trigger",
	"interact",
	"waypoint",
	"patrol",
	"spawn",
	"collisionpart",
	"humanoidrootpart",
}

local initialized = false

local function hasHiddenAncestor(instance: Instance): boolean
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute("EcholocationRevealHidden") == true then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isHelperPart(part: BasePart): boolean
	local lowerName = string.lower(part.Name)
	for _, pattern in ipairs(HELPER_NAME_PATTERNS) do
		if string.find(lowerName, pattern, 1, true) then
			return true
		end
	end

	return part.Transparency >= 0.98
end

local function shouldRevealMapPart(part: BasePart): boolean
	if hasHiddenAncestor(part) or isHelperPart(part) then
		return false
	end

	return part.Name ~= "Baseplate"
end

local function tagRevealPart(part: BasePart)
	CollectionService:AddTag(part, REVEAL_TAG)
	part.CanQuery = true
end

local function tagMap(root: Instance)
	local taggedCount = 0

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and shouldRevealMapPart(descendant) then
			tagRevealPart(descendant)
			taggedCount += 1
		end
	end

	print(string.format("MapEcholocationSetup: tagged %d reveal parts under %s", taggedCount, root:GetFullName()))
end

local function readTextureAttribute(part: MeshPart, propertyName: string): string
	local attributeName = MONSTER_TEXTURE_ATTRIBUTE_BY_PROPERTY[propertyName]
	local current: Instance? = part

	while current and current ~= workspace do
		local value = current:GetAttribute(attributeName)
		if typeof(value) == "string" and value ~= "" then
			return value
		end
		current = current.Parent
	end

	return ""
end

local function ensureMonsterSurfaceAppearance(part: MeshPart)
	local surfaceAppearance = part:FindFirstChildOfClass("SurfaceAppearance")
	if not surfaceAppearance then
		surfaceAppearance = Instance.new("SurfaceAppearance")
		surfaceAppearance.Name = "MonsterSurfaceAppearance"
		surfaceAppearance.Parent = part
	end

	local appliedAnyTexture = false
	for propertyName in pairs(MONSTER_TEXTURE_ATTRIBUTE_BY_PROPERTY) do
		local textureId = readTextureAttribute(part, propertyName)
		if textureId ~= "" then
			surfaceAppearance[propertyName] = textureId
			appliedAnyTexture = true
		end
	end

	part:SetAttribute("MonsterTextureUploadRequired", not appliedAnyTexture)
end

local function tagMonsterModel(model: Model)
	if model:FindFirstChildOfClass("Humanoid") and model:FindFirstChild("HumanoidRootPart") then
		return
	end

	model:SetAttribute("RevealKind", "Monster")

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			tagRevealPart(descendant)
			descendant:SetAttribute("RevealKind", "Monster")
			descendant.CanCollide = false
			descendant.CanTouch = false

			if descendant:IsA("MeshPart") then
				ensureMonsterSurfaceAppearance(descendant)
			end
		end
	end

	print("MapEcholocationSetup: monster reveal prepared for " .. model:GetFullName())
end

local function prepareMonstersIn(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Model") and MONSTER_MODEL_NAMES[descendant.Name] then
			tagMonsterModel(descendant)
		end
	end
end

local function prepareWorkspaceMonster(modelName: string)
	local model = workspace:FindFirstChild(modelName)
	if model and model:IsA("Model") then
		tagMonsterModel(model)
	end
end

local function prepareMap(map: Instance)
	tagMap(map)
	prepareMonstersIn(map)
end

function MapEcholocationSetup.init()
	if initialized then
		return
	end
	initialized = true

	for _, mapName in ipairs(AUTHORED_MAP_NAMES) do
		local map = workspace:FindFirstChild(mapName)
		if map then
			prepareMap(map)
		end
	end

	prepareWorkspaceMonster("Monster")
	prepareWorkspaceMonster("Rig")
	prepareWorkspaceMonster("rigging (1)")

	workspace.ChildAdded:Connect(function(child)
		if table.find(AUTHORED_MAP_NAMES, child.Name) then
			prepareMap(child)
		elseif child:IsA("Model") and MONSTER_MODEL_NAMES[child.Name] then
			tagMonsterModel(child)
		end
	end)
end

return MapEcholocationSetup

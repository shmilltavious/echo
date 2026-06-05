-- R15 rig — Motor6D joints already connect every limb, so NO welds needed here.
-- Adding WeldConstraints on top of Motor6Ds over-constrains the rig and causes
-- it to fall over or slide sideways.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local Constants = require(ReplicatedStorage.Shared.Constants)
local MONSTER_CONFIG = Constants.MONSTER_AI
local MONSTER_BODY_COLLISION_GROUP = "MonsterHiddenBody"
local DRIVER_MODEL_NAME = "MonsterDriver"

local foundMonster = workspace:WaitForChild("Monster", 5)
if not (foundMonster and foundMonster:IsA("Model")) then
	warn("MonsterSetup disabled: expected game.Workspace.Monster model.")
	return
end

local function findHumanoidDriverModel(container: Model): Model?
	if container:FindFirstChildOfClass("Humanoid") and container:FindFirstChild("HumanoidRootPart") then
		return container
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:FindFirstChildOfClass("Humanoid")
			and descendant:FindFirstChild("HumanoidRootPart")
		then
			return descendant
		end
	end

	return nil
end

local function resolveHumanoidDriverModel(container: Model): Model?
	local driverModel = findHumanoidDriverModel(container)
	if driverModel then
		return driverModel
	end

	local existingDriver = container:FindFirstChild(DRIVER_MODEL_NAME)
	if existingDriver and existingDriver:IsA("Model") then
		existingDriver:Destroy()
	end

	local driver = Instance.new("Model")
	driver.Name = DRIVER_MODEL_NAME
	driver.Parent = container

	local pivot = container:GetPivot()

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Massless = false
	root.CFrame = pivot
	root.Parent = driver
	driver.PrimaryPart = root

	local body = Instance.new("Part")
	body.Name = "MonsterDriverBody"
	body.Size = Vector3.new(2, 4, 1)
	body.Transparency = 1
	body.Anchored = false
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.Massless = true
	body.CFrame = pivot * CFrame.new(0, 1, 0)
	body.Parent = driver

	local bodyWeld = Instance.new("WeldConstraint")
	bodyWeld.Name = "MonsterDriverBodyWeld"
	bodyWeld.Part0 = root
	bodyWeld.Part1 = body
	bodyWeld.Parent = body

	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HipHeight = 0
	humanoid.WalkSpeed = MONSTER_CONFIG.PATROL_SPEED
	humanoid.Parent = driver

	print("MonsterSetup: created hidden Humanoid driver inside game.Workspace.Monster")
	return driver
end

local monsterModel = resolveHumanoidDriverModel(foundMonster)
if not monsterModel then
	warn("MonsterSetup disabled: expected game.Workspace.Monster to be or contain a Humanoid driver model.")
	return
end
if monsterModel ~= foundMonster then
	print(string.format("MonsterSetup: using nested Humanoid driver %s inside game.Workspace.Monster", monsterModel:GetFullName()))
end
local rootPart = monsterModel:WaitForChild("HumanoidRootPart", 5)
local humanoid = monsterModel:WaitForChild("Humanoid", 5)
if not (rootPart and rootPart:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid")) then
	warn("MonsterSetup disabled: monster is missing Humanoid or HumanoidRootPart.")
	return
end

-- Server owns physics so NPC movement is smooth and authoritative
rootPart:SetNetworkOwner(nil)

local collisionHull: BasePart? = nil

local function ensureCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(MONSTER_BODY_COLLISION_GROUP)
	end)
	PhysicsService:CollisionGroupSetCollidable(MONSTER_BODY_COLLISION_GROUP, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(MONSTER_BODY_COLLISION_GROUP, MONSTER_BODY_COLLISION_GROUP, false)
end

local function enforceSingleCollisionHull()
	for _, descendant in ipairs(foundMonster:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local isHull = descendant == collisionHull
			descendant.CanCollide = isHull
			descendant.CanTouch = false
			if isHull then
				descendant.CanQuery = false
			end
			descendant.CollisionGroup = if isHull then "Default" else MONSTER_BODY_COLLISION_GROUP
		end
	end
end

local function configureSingleCollisionHull()
	enforceSingleCollisionHull()

	local hull = foundMonster:FindFirstChild("MonsterCollisionHull")
	if not (hull and hull:IsA("Part")) then
		hull = Instance.new("Part")
		hull.Name = "MonsterCollisionHull"
		hull.Parent = foundMonster
	end

	hull.Size = MONSTER_CONFIG.COLLISION_HULL_SIZE or Vector3.new(11.8, 7, 11.8)
	hull.Transparency = 1
	hull.Anchored = false
	hull.CanCollide = true
	hull.CanTouch = false
	hull.CanQuery = false
	hull.Massless = true
	hull.CastShadow = false
	hull.CFrame = rootPart.CFrame
	hull.CollisionGroup = "Default"
	hull:SetAttribute("MonsterHullDebug_Size", tostring(hull.Size))
	hull:SetAttribute("MonsterHullDebug_CollisionGroup", hull.CollisionGroup)
	hull:SetAttribute("MonsterHullDebug_SourceModel", monsterModel:GetFullName())
	collisionHull = hull

	local weld = hull:FindFirstChild("MonsterCollisionHullWeld")
	if not (weld and weld:IsA("WeldConstraint")) then
		weld = Instance.new("WeldConstraint")
		weld.Name = "MonsterCollisionHullWeld"
		weld.Parent = hull
	end
	weld.Part0 = rootPart
	weld.Part1 = hull
	for _, descendant in ipairs(foundMonster:GetDescendants()) do
		if descendant ~= hull and descendant:IsA("BasePart") and descendant.Name == "MonsterCollisionHull" then
			descendant:Destroy()
		end
	end
	enforceSingleCollisionHull()
end

ensureCollisionGroups()
configureSingleCollisionHull()

local collisionConnection
collisionConnection = RunService.Heartbeat:Connect(function()
	if not foundMonster.Parent then
		if collisionConnection then
			collisionConnection:Disconnect()
			collisionConnection = nil
		end
		return
	end

	enforceSingleCollisionHull()
end)

humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

-- PrimaryAxisOnly locks only the upright (Y) axis so the rig can't tip over,
-- while still allowing AutoRotate to turn it freely to face its movement direction.
-- math.huge MaxTorque causes physics instability; 2e4 is firm enough without fighting the humanoid.
local attachment = rootPart:FindFirstChild("UprightAttachment")
if not (attachment and attachment:IsA("Attachment")) then
	attachment = Instance.new("Attachment")
	attachment.Name = "UprightAttachment"
	attachment.Parent = rootPart
end

local alignOrientation = rootPart:FindFirstChild("MonsterUprightAlignOrientation")
if not (alignOrientation and alignOrientation:IsA("AlignOrientation")) then
	alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "MonsterUprightAlignOrientation"
	alignOrientation.Parent = rootPart
end
alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignOrientation.Attachment0 = attachment
alignOrientation.PrimaryAxisOnly = true
alignOrientation.MaxTorque = 2e4
alignOrientation.Responsiveness = 30

print(string.format(
	"Monster rig ready: hull=%s pathRadius=%.2f bodyGroup=%s",
	tostring(MONSTER_CONFIG.COLLISION_HULL_SIZE or Vector3.new(11.8, 7, 11.8)),
	MONSTER_CONFIG.PATH_AGENT_RADIUS or 5.9,
	MONSTER_BODY_COLLISION_GROUP
))

-- Server-side Monster AI with pathfinding and sphere detection
local MonsterAI = {}

local Constants = require(game.ReplicatedStorage.Shared.Constants)
local SphereDetection = require(game.ReplicatedStorage.Shared.SphereDetection)

-- Monster class
local Monster = {}
Monster.__index = Monster

function Monster.new(monsterPart: Part)
	local self = setmetatable({}, Monster)
	
	self.part = monsterPart
	self.humanoid = monsterPart.Parent:FindFirstChild("Humanoid")
	self.currentTarget = nil
	self.isMoving = false
	self.lastSphereDetection = 0
	
	return self
end

function Monster:update()
	-- Check for sphere activation
	if self:detectSphere() then
		self:moveTowardsSphere()
	else
		self:idle()
	end
end

function Monster:detectSphere()
	-- TODO: Implement detection logic for expanding sphere
	-- This should listen for sphere events from clients or check proximity
	-- For now, placeholder implementation
	
	local playersInRange = false
	for _, player in pairs(game.Players:GetPlayers()) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			local distance = (player.Character.HumanoidRootPart.Position - self.part.Position).Magnitude
			if distance <= Constants.MONSTER_IDLE_RANGE then
				playersInRange = true
				self.currentTarget = player.Character.HumanoidRootPart.Position
				break
			end
		end
	end
	
	return playersInRange
end

function Monster:moveTowardsSphere()
	if not self.currentTarget or not self.humanoid then return end
	
	self.isMoving = true
	
	-- Calculate direction to target
	local direction = (self.currentTarget - self.part.Position).Unit
	
	-- Move monster toward target
	if self.humanoid then
		self.humanoid:MoveTo(self.currentTarget)
	end
	
	-- Stop moving if reached target
	local distance = (self.currentTarget - self.part.Position).Magnitude
	if distance < 5 then
		self.isMoving = false
		self.currentTarget = nil
	end
end

function Monster:idle()
	self.isMoving = false
	if self.humanoid then
		self.humanoid:MoveTo(self.part.Position)
	end
end

-- Initialize monsters in the workspace
function MonsterAI.init()
	local monsterfolder = workspace:FindFirstChild("Monsters")
	if not monsterfolder then
		warn("Monsters folder not found in workspace")
		return
	end
	
	local monsters = {}
	
	-- Create monster instances
	for _, monsterPart in pairs(monsterfolder:GetDescendants()) do
		if monsterPart:IsA("Part") and monsterPart.Name == "Monster" then
			table.insert(monsters, Monster.new(monsterPart))
		end
	end
	
	-- Update loop
	while true do
		task.wait(1 / 30) -- 30 FPS update
		
		for _, monster in pairs(monsters) do
			monster:update()
		end
	end
end

return MonsterAI

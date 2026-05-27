local RunService = game:GetService("RunService")

local MonsterGroundLock = {}

local DEFAULT_CONTACT_BONE_SUFFIXES = {
	"LeftFoot",
	"RightFoot",
	"LeftToeBase",
	"RightToeBase",
}

local function nameEndsWith(value: string, suffix: string): boolean
	return value == suffix or value:sub(-#suffix) == suffix
end

local function findContactBones(rig: Instance, contactBoneSuffixes)
	local contactBones = {}

	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("Bone") then
			for _, suffix in ipairs(contactBoneSuffixes) do
				if nameEndsWith(descendant.Name, suffix) then
					table.insert(contactBones, descendant)
					break
				end
			end
		end
	end

	return contactBones
end

local function getLowestContactY(contactBones)
	local lowestY = math.huge

	for _, bone in ipairs(contactBones) do
		if bone.Parent then
			lowestY = math.min(lowestY, bone.WorldCFrame.Position.Y)
		end
	end

	if lowestY == math.huge then
		return nil
	end

	return lowestY
end

function MonsterGroundLock.start(config)
	local rig = config.rig
	local visualPart = config.visualPart
	local contactBoneSuffixes = config.contactBoneSuffixes or DEFAULT_CONTACT_BONE_SUFFIXES
	local groundClearance = config.groundClearance or 0.05
	local raycastStartHeight = config.raycastStartHeight or 0.5
	local raycastDown = config.raycastDown or 80
	local maxCorrectionPerSecond = config.maxCorrectionPerSecond or 18
	local maxFloorRisePerFrame = config.maxFloorRisePerFrame or 2
	local correctionDeadZone = config.correctionDeadZone or 0.03

	assert(typeof(rig) == "Instance", "MonsterGroundLock.start requires config.rig")
	assert(typeof(visualPart) == "Instance" and visualPart:IsA("BasePart"), "MonsterGroundLock.start requires config.visualPart")

	local contactBones = findContactBones(rig, contactBoneSuffixes)
	if #contactBones == 0 then
		warn("MonsterGroundLock: no contact bones found; ground lock disabled.")
		return {
			stop = function() end,
			suppressDownwardCorrection = function() end,
		}
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { rig }

	local lastFloorY = nil
	local suppressDownwardCorrectionUntil = 0
	local connection

	local controller = {}

	function controller.stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	function controller.suppressDownwardCorrection(durationSeconds: number)
		suppressDownwardCorrectionUntil = math.max(suppressDownwardCorrectionUntil, os.clock() + durationSeconds)
	end

	connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not rig.Parent or not visualPart.Parent then
			controller.stop()
			return
		end

		local origin = visualPart.Position + Vector3.new(0, raycastStartHeight, 0)
		local direction = Vector3.new(0, -raycastDown, 0)
		local raycastResult = workspace:Raycast(origin, direction, raycastParams)
		if raycastResult and raycastResult.Position.Y <= origin.Y then
			local floorY = raycastResult.Position.Y
			if not lastFloorY or floorY <= lastFloorY + maxFloorRisePerFrame then
				lastFloorY = floorY
			end
		end

		local lowestContactY = getLowestContactY(contactBones)
		if not lowestContactY or not lastFloorY then
			return
		end

		local targetContactY = lastFloorY + groundClearance
		local correction = targetContactY - lowestContactY
		if math.abs(correction) < correctionDeadZone then
			return
		end
		if correction < 0 and os.clock() < suppressDownwardCorrectionUntil then
			return
		end

		local maxCorrection = maxCorrectionPerSecond * deltaTime
		local smoothedCorrection = math.clamp(correction, -maxCorrection, maxCorrection)
		visualPart.CFrame += Vector3.new(0, smoothedCorrection, 0)
	end)

	return controller
end

return MonsterGroundLock

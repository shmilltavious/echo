-- Shared logic for sphere-based detection and wall interactions
local SphereDetection = {}

-- Returns the shortest world-space distance between a point and a part's bounds.
function SphereDetection.getDistanceFromPart(point: Vector3, part: BasePart): number
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	local closestLocalPoint = Vector3.new(
		math.clamp(localPoint.X, -halfSize.X, halfSize.X),
		math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
	)
	local closestWorldPoint = part.CFrame:PointToWorldSpace(closestLocalPoint)
	return (closestWorldPoint - point).Magnitude
end

-- Returns whether a world-space point is inside a sphere.
function SphereDetection.isPointInSphere(sphereCenter: Vector3, sphereRadius: number, point: Vector3): boolean
	local distance = (point - sphereCenter).Magnitude
	return distance <= sphereRadius
end

-- Returns BaseParts under wallFolder intersected by a sphere.
function SphereDetection.getWallsTouchedBySphere(sphereCenter: Vector3, sphereRadius: number, wallFolder: Folder): {Part}
	local touchedWalls = {}
	
	if not wallFolder then
		return touchedWalls
	end
	
	for _, wall in pairs(wallFolder:GetDescendants()) do
		if wall:IsA("BasePart") then
			local distance = SphereDetection.getDistanceFromPart(sphereCenter, wall)
			if distance <= sphereRadius then
				table.insert(touchedWalls, wall)
			end
		end
	end
	
	return touchedWalls
end

-- Returns the supplied parts that intersect a sphere.
function SphereDetection.getPartsTouchedBySphere(sphereCenter: Vector3, sphereRadius: number, parts: {BasePart}): {BasePart}
	local touchedParts = {}

	for _, part in ipairs(parts) do
		local distance = SphereDetection.getDistanceFromPart(sphereCenter, part)
		if distance <= sphereRadius then
			table.insert(touchedParts, part)
		end
	end

	return touchedParts
end

-- Calculates echolocation radius from movement and microphone inputs.
function SphereDetection.calculateSphereRadius(movementSpeed: number, micVolume: number, constants: {any}): number
	local speedInfluence = movementSpeed * 0.2
	local volumeInfluence = micVolume * 55
	local totalRadius = constants.SPHERE_MIN_RADIUS + speedInfluence + volumeInfluence
	
	return math.min(totalRadius, constants.SPHERE_MAX_RADIUS)
end

return SphereDetection

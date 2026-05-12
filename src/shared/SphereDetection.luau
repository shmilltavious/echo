-- Shared logic for sphere-based detection and wall interactions
local SphereDetection = {}

-- Check if a point is within a sphere
function SphereDetection.isPointInSphere(sphereCenter: Vector3, sphereRadius: number, point: Vector3): boolean
	local distance = (point - sphereCenter).Magnitude
	return distance <= sphereRadius
end

-- Get all walls touched by a sphere
function SphereDetection.getWallsTouchedBySphere(sphereCenter: Vector3, sphereRadius: number, wallFolder: Folder): {Part}
	local touchedWalls = {}
	
	if not wallFolder then
		return touchedWalls
	end
	
	for _, wall in pairs(wallFolder:GetDescendants()) do
		if wall:IsA("BasePart") then
			local distance = (wall.Position - sphereCenter).Magnitude
			-- Account for part size when checking collision
			if distance <= (sphereRadius + wall.Size.Magnitude / 2) then
				table.insert(touchedWalls, wall)
			end
		end
	end
	
	return touchedWalls
end

function SphereDetection.getPartsTouchedBySphere(sphereCenter: Vector3, sphereRadius: number, parts: {BasePart}): {BasePart}
	local touchedParts = {}

	for _, part in ipairs(parts) do
		local distance = (part.Position - sphereCenter).Magnitude
		if distance <= (sphereRadius + part.Size.Magnitude / 2) then
			table.insert(touchedParts, part)
		end
	end

	return touchedParts
end

-- Calculate sphere radius based on movement speed and mic volume
function SphereDetection.calculateSphereRadius(movementSpeed: number, micVolume: number, constants: {any}): number
	local speedInfluence = movementSpeed * 0.2
	local volumeInfluence = micVolume * 55
	local totalRadius = constants.SPHERE_MIN_RADIUS + speedInfluence + volumeInfluence
	
	return math.min(totalRadius, constants.SPHERE_MAX_RADIUS)
end

return SphereDetection

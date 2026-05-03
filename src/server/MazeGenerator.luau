-- Server-side maze generator (optional utility for creating untextured walls)
local MazeGenerator = {}

local Constants = require(game.ReplicatedStorage.Shared.Constants)

-- Create a simple wall
function MazeGenerator.createWall(position: Vector3, size: Vector3): Part
	local wall = Instance.new("Part")
	wall.Shape = Enum.PartType.Block
	wall.Material = Enum.Material.Plastic
	wall.Color = Color3.fromRGB(128, 128, 128)
	wall.CanCollide = true
	wall.CFrame = CFrame.new(position)
	wall.Size = size
	wall.TopSurface = Enum.SurfaceType.Smooth
	wall.BottomSurface = Enum.SurfaceType.Smooth
	wall.Transparency = 1 -- Start invisible for the mechanic
	wall.Name = "Wall"
	wall.Parent = workspace.Walls or Instance.new("Folder", workspace)
	
	return wall
end

-- Create a simple grid-based maze
function MazeGenerator.generateSimpleMaze(width: number, height: number, cellSize: number)
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "Walls"
	wallFolder.Parent = workspace
	
	-- Create outer walls
	local wallThickness = 1
	
	-- North wall
	MazeGenerator.createWall(
		Vector3.new(0, 5, -cellSize * height / 2),
		Vector3.new(cellSize * width, wallThickness, wallThickness)
	)
	
	-- South wall
	MazeGenerator.createWall(
		Vector3.new(0, 5, cellSize * height / 2),
		Vector3.new(cellSize * width, wallThickness, wallThickness)
	)
	
	-- West wall
	MazeGenerator.createWall(
		Vector3.new(-cellSize * width / 2, 5, 0),
		Vector3.new(wallThickness, wallThickness, cellSize * height)
	)
	
	-- East wall
	MazeGenerator.createWall(
		Vector3.new(cellSize * width / 2, 5, 0),
		Vector3.new(wallThickness, wallThickness, cellSize * height)
	)
	
	-- Optional: Add some interior walls
	for i = 1, math.floor(width / 3) do
		MazeGenerator.createWall(
			Vector3.new(i * cellSize - cellSize * width / 2, 5, 0),
			Vector3.new(wallThickness, wallThickness, cellSize * height / 2)
		)
	end
end

return MazeGenerator

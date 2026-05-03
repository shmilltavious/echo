-- Server-side button interaction and gate control
local ButtonSystem = {}

-- Create RemoteEvent for client-server communication
local buttonPressEvent = Instance.new("RemoteEvent")
buttonPressEvent.Name = "ButtonPress"
buttonPressEvent.Parent = game.ReplicatedStorage

-- Gate animation settings
local GATE_RETRACT_SPEED = 50 -- studs per second
local GATE_RETRACT_DISTANCE = 10 -- how far into the wall

-- State
local gateOpen = false
local isAnimating = false
local gateParts = {} -- Stores {part, originalPosition}

-- Initialize button
function ButtonSystem.init()
	local button = workspace:FindFirstChild("Prototype_Map") and workspace.Prototype_Map:FindFirstChild("Button")
	if not button then
		warn("Button not found in Prototype_Map")
		return
	end
	
	-- Listen for button press from client
	buttonPressEvent.OnServerEvent:Connect(function(player, action)
		if action == "pressed" and not isAnimating then
			print("📨 Received button press from", player.Name)
			ButtonSystem.toggleGate()
		end
	end)

	-- Cache initial positions of all gate parts
	local prototypeMap = workspace:FindFirstChild("Prototype_Map")
	if prototypeMap then
		local gateBars = prototypeMap:FindFirstChild("Gate Bars")
		if gateBars then
			for _, child in pairs(gateBars:GetChildren()) do
				if child:IsA("BasePart") then
					table.insert(gateParts, {
						instance = child,
						closedPos = child.Position,
						openPos = child.Position + (child.CFrame.RightVector * GATE_RETRACT_DISTANCE)
					})
				end
			end
		end
	end
	
	print("✅ Button system initialized")
end

-- Toggle gate open/closed
function ButtonSystem.toggleGate()
	print("🔘 Button pressed! Toggling gate...")
	local prototypeMap = workspace:FindFirstChild("Prototype_Map")
	if not prototypeMap then
		warn("❌ Prototype_Map not found")
		return
	end
	
	local gateBars = prototypeMap:FindFirstChild("Gate Bars")
	if not gateBars then
		warn("❌ Gate Bars not found in Prototype_Map")
		print("Available children:", table.concat({prototypeMap:GetChildren()}, ", "))
		return
	end
	
	gateOpen = not gateOpen
	isAnimating = true
	print("  Gate state:", if gateOpen then "OPEN" else "CLOSED")
	
	if gateOpen then
		ButtonSystem.animateGate(true)
	else
		ButtonSystem.animateGate(false)
	end
	
	isAnimating = false
end

-- Animate all gate parts
function ButtonSystem.animateGate(opening: boolean)
	local duration = GATE_RETRACT_DISTANCE / GATE_RETRACT_SPEED
	local startTime = os.clock()

	while os.clock() - startTime < duration do
		local t = (os.clock() - startTime) / duration
		
		for _, data in pairs(gateParts) do
			local start = if opening then data.closedPos else data.openPos
			local goal = if opening then data.openPos else data.closedPos
			data.instance.Position = start:Lerp(goal, t)
		end
		
		task.wait()
	end

	-- Ensure final position is exact
	for _, data in pairs(gateParts) do
		data.instance.Position = if opening then data.openPos else data.closedPos
	end
end

return ButtonSystem

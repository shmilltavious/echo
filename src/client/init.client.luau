-- Client initialization script
print("Hello world, from client!")

local StarterGui = game:GetService("StarterGui")
local clientFolder = game.StarterPlayer.StarterPlayerScripts.Client
local Menu = require(clientFolder:WaitForChild("Menu", 5))
local SphereVisuals = require(clientFolder:WaitForChild("SphereVisuals", 5))
local ObjectiveClient = require(clientFolder:WaitForChild("ObjectiveClient", 5))
local CameraEffects = require(clientFolder:WaitForChild("CameraEffects", 5))
local AudioFeedback = require(clientFolder:WaitForChild("AudioFeedback", 5))

local function hidePlayerList()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
end

hidePlayerList()
task.spawn(function()
	for _ = 1, 5 do
		task.wait(0.5)
		hidePlayerList()
	end
end)

if not Menu then
	warn("Menu failed to load")
else
	print("Menu loaded")
	Menu.init()
end

if not SphereVisuals then
	warn("SphereVisuals failed to load")
else
	print("SphereVisuals loaded")
end

if not ObjectiveClient then
	warn("ObjectiveClient failed to load")
else
	print("ObjectiveClient loaded")
end

if not CameraEffects then
	warn("CameraEffects failed to load")
else
	print("CameraEffects loaded")
end

if not AudioFeedback then
	warn("AudioFeedback failed to load")
else
	print("AudioFeedback loaded")
end

print("MVP client systems initialized!")

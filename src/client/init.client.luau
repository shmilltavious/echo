-- Client initialization script
print("Hello world, from client!")

local StarterGui = game:GetService("StarterGui")
local clientFolder = script

local function requireClientModule(name: string)
	local module = clientFolder:WaitForChild(name, 5)
	if not module then
		warn(name .. " failed to load: module missing")
		return nil
	end

	local ok, result = pcall(require, module)
	if not ok then
		warn(name .. " failed to load: " .. tostring(result))
		return nil
	end

	return result
end

local Menu = requireClientModule("Menu")
local SphereVisuals = requireClientModule("SphereVisuals")
local ObjectiveClient = requireClientModule("ObjectiveClient")
local CameraEffects = requireClientModule("CameraEffects")
local AudioFeedback = requireClientModule("AudioFeedback")

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

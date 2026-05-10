-- Client initialization script
print("Hello world, from client!")

-- Use absolute paths for requires
local Menu = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("Menu", 5))
local SphereVisuals = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("SphereVisuals", 5))
local ButtonPrompt = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("ButtonPrompt", 5))
local Flashlight = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("Flashlight", 5))

if not Menu then
	warn("❌ Menu failed to load")
else
	print("✅ Menu loaded")
	Menu.init()
end

if not SphereVisuals then
	warn("❌ SphereVisuals failed to load")
else
	print("✅ SphereVisuals loaded")
end

if not ButtonPrompt then
	warn("❌ ButtonPrompt failed to load")
else
	print("✅ ButtonPrompt loaded")
end

print("MVP client systems initialized!")
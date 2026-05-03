-- Client initialization script
print("Hello world, from client!")

-- Use absolute paths for requires
local SphereVisuals = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("SphereVisuals", 5))
local ButtonPrompt = require(game.StarterPlayer.StarterPlayerScripts.Client:WaitForChild("ButtonPrompt", 5))

if not SphereVisuals then
	warn("❌ SphereVisuals failed to load")
else
	print("✅ SphereVisuals loaded")
	SphereVisuals.init()
end

if not ButtonPrompt then
	warn("❌ ButtonPrompt failed to load")
else
	print("✅ ButtonPrompt loaded")
	ButtonPrompt.init()
end

print("MVP client systems initialized!")

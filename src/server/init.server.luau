-- Server initialization script
print("Hello world, from server!")

-- MonsterAI.server.luau and MonsterSetup.server.luau are standalone Scripts
-- that Roblox runs automatically -- requiring them here would crash since only
-- ModuleScripts can be passed to require().
local ButtonSystem = require(script:WaitForChild("ButtonSystem", 5))

if not ButtonSystem then
	warn("❌ ButtonSystem failed to load")
else
	print("✅ ButtonSystem loaded")
	ButtonSystem.init()
end

print("MVP server systems initialized!")

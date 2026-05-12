-- Server initialization script
print("Hello world, from server!")

-- MonsterAI.server.luau and MonsterSetup.server.luau are standalone Scripts
-- that Roblox runs automatically -- requiring them here would crash since only
-- ModuleScripts can be passed to require().
local ObjectiveSystem = require(script:WaitForChild("ObjectiveSystem", 5))

if not ObjectiveSystem then
	warn("ObjectiveSystem failed to load")
else
	print("ObjectiveSystem loaded")
	ObjectiveSystem.init()
end

print("MVP server systems initialized!")

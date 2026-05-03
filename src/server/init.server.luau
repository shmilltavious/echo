-- Server initialization script
print("Hello world, from server!")

-- Use absolute paths for requires
local MonsterAI = require(game.ServerScriptService.Server:WaitForChild("MonsterAI", 5))
local ButtonSystem = require(game.ServerScriptService.Server:WaitForChild("ButtonSystem", 5))

if not MonsterAI then
	warn("❌ MonsterAI failed to load")
else
	print("✅ MonsterAI loaded")
	MonsterAI.init()
end

if not ButtonSystem then
	warn("❌ ButtonSystem failed to load")
else
	print("✅ ButtonSystem loaded")
	ButtonSystem.init()
end

print("MVP server systems initialized!")

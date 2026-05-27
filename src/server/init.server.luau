-- Server initialization script
print("Hello world, from server!")

-- MonsterAI.server.luau and MonsterSetup.server.luau are standalone Scripts
-- that Roblox runs automatically -- requiring them here would crash since only
-- ModuleScripts can be passed to require().
local function requireServerModule(name: string)
	local module = script:WaitForChild(name, 5)
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

local ObjectiveSystem = requireServerModule("ObjectiveSystem")
local MapEcholocationSetup = requireServerModule("MapEcholocationSetup")

if not ObjectiveSystem then
	warn("ObjectiveSystem failed to load")
else
	print("ObjectiveSystem loaded")
	ObjectiveSystem.init()
end

if not MapEcholocationSetup then
	warn("MapEcholocationSetup failed to load")
else
	MapEcholocationSetup.init()
end

print("MVP server systems initialized!")

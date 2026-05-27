local RIG_NAME = "rigging (1)"
local PROMPT_NAME = "MonsterAnimationPrompt"
local PROMPT_WARMUP_SECONDS = 0.5

local MonsterVisualController = require(script.Parent.MonsterVisualController)

if script:GetAttribute("TesterEnabled") ~= true and workspace:GetAttribute("EnableMonsterAnimationTester") ~= true then
	print("Monster animation tester disabled. Set script.TesterEnabled attribute or workspace.EnableMonsterAnimationTester to true to use it.")
	return
end

local rig = workspace:WaitForChild(RIG_NAME)
local promptParent = rig:WaitForChild("geometry_0")
local monsterVisual = MonsterVisualController.start({
	hiddenPrewarm = false,
})
if not monsterVisual then
	warn("Monster animation tester disabled: MonsterVisualController failed to start.")
	return
end

local prompt = promptParent:FindFirstChild(PROMPT_NAME)
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.Parent = promptParent
end

prompt.ActionText = "Test Animation"
prompt.ObjectText = "Monster"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.Enabled = false

local testAnimationOrder = {
	"Look",
	"Roar",
	"Run",
	"Attack",
}
local nextAnimationIndex = 1

local function playNextAnimation(player: Player)
	local animationName = testAnimationOrder[nextAnimationIndex]
	local methodName = "play" .. animationName
	local playMethod = monsterVisual[methodName]
	if typeof(playMethod) == "function" then
		playMethod()
	end

	print(string.format("Monster animation tester: %s triggered %s", player.Name, animationName))

	nextAnimationIndex += 1
	if nextAnimationIndex > #testAnimationOrder then
		nextAnimationIndex = 1
	end
end

monsterVisual.playIdle()
prompt.Triggered:Connect(playNextAnimation)

task.delay(PROMPT_WARMUP_SECONDS, function()
	if prompt.Parent then
		prompt.Enabled = true
	end
end)

print("Monster animation tester ready. Use the ProximityPrompt on " .. rig:GetFullName() .. " to cycle animations.")

local RIG_NAME = "rigging (1)"
local PROMPT_NAME = "MonsterAnimationPrompt"
local PROMPT_WARMUP_SECONDS = 0.5
local DRIFT_SAMPLE_SECONDS = 1.35
local CALIBRATION_YAW_OFFSETS = { -90, 90, 180, 0 }

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
	"Idle",
	"Look",
	"Roar",
	"Walk",
	"Run",
	"Attack",
}
local nextAnimationIndex = 1

local function playAnimation(animationName: string)
	if animationName == "Idle" then
		monsterVisual.playIdle()
	elseif animationName == "Walk" then
		if typeof(monsterVisual.playWalk) == "function" then
			monsterVisual.playWalk()
		else
			monsterVisual.setLocomotionState("Walk")
		end
	else
		local methodName = "play" .. animationName
		local playMethod = monsterVisual[methodName]
		if typeof(playMethod) == "function" then
			playMethod()
		end
	end
end

local function runYawCalibration()
	local originalOffset = promptParent:GetAttribute("MonsterVisualYawOffsetDegrees")
	local bestOffset = originalOffset
	local bestDot = -math.huge

	for _, offset in ipairs(CALIBRATION_YAW_OFFSETS) do
		promptParent:SetAttribute("MonsterVisualYawOffsetDegrees", offset)
		task.wait(0.2)
		local dot = promptParent:GetAttribute("MonsterVisual_ForwardDot")
			or rig:GetAttribute("MonsterVisual_ForwardDot")
			or -math.huge
		print(string.format("Monster animation tester: yaw %d forward dot %.2f", offset, dot))
		if dot > bestDot then
			bestDot = dot
			bestOffset = offset
		end
	end

	if typeof(bestOffset) == "number" then
		promptParent:SetAttribute("MonsterVisualYawOffsetDegrees", bestOffset)
	elseif typeof(originalOffset) == "number" then
		promptParent:SetAttribute("MonsterVisualYawOffsetDegrees", originalOffset)
	end
	print(string.format("Monster animation tester: best yaw offset %s with forward dot %.2f", tostring(bestOffset), bestDot))
end

local function playNextAnimation(player: Player)
	local animationName = testAnimationOrder[nextAnimationIndex]
	if typeof(monsterVisual.resetAnimationDiagnostics) == "function" then
		monsterVisual.resetAnimationDiagnostics(animationName)
	end
	playAnimation(animationName)

	print(string.format("Monster animation tester: %s triggered %s", player.Name, animationName))
	task.delay(DRIFT_SAMPLE_SECONDS, function()
		if typeof(monsterVisual.getAnimationDiagnostics) ~= "function" then
			return
		end

		local diagnostics = monsterVisual.getAnimationDiagnostics()
		local maxDriftByAction = diagnostics.maxDriftByAction or {}
		local maxDrift = maxDriftByAction[animationName] or diagnostics.driftMagnitude or 0
		print(string.format(
			"Monster animation tester: %s max planar drift %.2f studs, compensation=%s, probe=%s, forwardDot=%s",
			animationName,
			maxDrift,
			tostring(diagnostics.driftCompensationOffset or Vector3.zero),
			tostring(diagnostics.driftProbe or ""),
			tostring(diagnostics.forwardDot or "")
		))
		if animationName == "Run" then
			runYawCalibration()
		end
	end)

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

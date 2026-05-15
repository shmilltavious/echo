-- First-person sprint/jump camera shake only. Tool viewmodels should be equipped by tools.
local CameraEffects = {}

local RunService = game:GetService("RunService")

local InputHandler = require(script.Parent.InputHandler)

local initialized = false
local sprintTime = 0

function CameraEffects.init()
	if initialized then return end
	initialized = true

	RunService:BindToRenderStep("ECHO_CameraEffects", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = workspace.CurrentCamera
		if not camera then return end

		local noise = InputHandler.getNoiseInfo()
		local isSprinting = noise.movementState == "sprint"
		local isJumping = noise.movementState == "jump"
		local targetAlpha = if isSprinting then 1 elseif isJumping then 0.65 else 0
		sprintTime += dt * (1 + targetAlpha)

		local shakeX = math.sin(sprintTime * 17) * 0.022 * targetAlpha
		local shakeRoll = math.sin(sprintTime * 12) * math.rad(0.6) * targetAlpha
		local shakeYaw = math.sin(sprintTime * 9) * math.rad(0.3) * targetAlpha

		camera.CFrame = camera.CFrame * CFrame.new(shakeX, 0, 0) * CFrame.Angles(0, shakeYaw, shakeRoll)
	end)
end

return CameraEffects

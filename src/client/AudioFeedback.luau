-- Local audio feedback for movement, breathing, monster proximity, and warnings
local AudioFeedback = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local initialized = false
local lastPlayerStepAt = 0
local lastMonsterStepAt = 0
local lastMonsterPosition: Vector3? = nil

local SOUND_IDS = {
	footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	monsterFootstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	breathing = "rbxassetid://9112854440",
	warning = "rbxassetid://9112854440",
}

local breathLoop: Sound? = nil
local warningLoop: Sound? = nil
local playerStepSound: Sound? = nil
local monsterStepSound: Sound? = nil

local function createSound(name: string, soundId: string, volume: number, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Volume = volume
	sound.Looped = looped
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = SoundService
	return sound
end

local function getCharacterRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function getMonsterRoot(): BasePart?
	local monster = workspace:FindFirstChild("Monster") or workspace:FindFirstChild("Rig")
	return monster and monster:FindFirstChild("HumanoidRootPart")
end

local function ensureSounds()
	if not playerStepSound then
		playerStepSound = createSound("PlayerStep", SOUND_IDS.footstep, 0.18, false)
	end
	if not monsterStepSound then
		monsterStepSound = createSound("MonsterStep", SOUND_IDS.monsterFootstep, 0.35, false)
		monsterStepSound.PlaybackSpeed = 0.72
	end
	if not breathLoop then
		breathLoop = createSound("PlayerBreathingLoop", SOUND_IDS.breathing, 0, true)
		breathLoop.PlaybackSpeed = 0.62
		breathLoop:Play()
	end
	if not warningLoop then
		warningLoop = createSound("MonsterWarningLoop", SOUND_IDS.warning, 0, true)
		warningLoop.PlaybackSpeed = 0.48
		warningLoop:Play()
	end
end

local function updatePlayerFootsteps(now: number, humanoid: Humanoid)
	if humanoid.FloorMaterial == Enum.Material.Air or humanoid.MoveDirection.Magnitude < 0.1 then
		return
	end

	local speed = humanoid.WalkSpeed
	local interval = if speed >= 18 then 0.26 elseif speed <= 8 then 0.58 else 0.42
	if now - lastPlayerStepAt < interval then
		return
	end

	lastPlayerStepAt = now
	if playerStepSound then
		playerStepSound.Volume = if speed >= 18 then 0.3 elseif speed <= 8 then 0.09 else 0.18
		playerStepSound.PlaybackSpeed = 0.92 + (math.random() * 0.16)
		playerStepSound:Play()
	end
end

local function updateBreathing(humanoid: Humanoid, monsterDistance: number?)
	if not breathLoop then return end

	local movingHard = humanoid.MoveDirection.Magnitude > 0.1 and humanoid.WalkSpeed >= 18
	local proximityStress = if monsterDistance then math.clamp(1 - ((monsterDistance - 12) / 46), 0, 1) else 0
	local targetVolume = math.clamp((movingHard and 0.16 or 0.045) + (proximityStress * 0.22), 0.035, 0.32)
	breathLoop.Volume += (targetVolume - breathLoop.Volume) * 0.08
	breathLoop.PlaybackSpeed = 0.62 + (proximityStress * 0.18) + (movingHard and 0.12 or 0)
end

local function updateMonsterAudio(now: number, playerRoot: BasePart?)
	local monsterRoot = getMonsterRoot()
	if not monsterRoot or not playerRoot then
		if warningLoop then
			warningLoop.Volume += (0 - warningLoop.Volume) * 0.08
		end
		return nil
	end

	local distance = (monsterRoot.Position - playerRoot.Position).Magnitude
	local warningIntensity = math.clamp(1 - ((distance - 14) / 56), 0, 1)

	if warningLoop then
		warningLoop.Volume += ((warningIntensity * 0.28) - warningLoop.Volume) * 0.08
		warningLoop.PlaybackSpeed = 0.42 + (warningIntensity * 0.18)
	end

	if lastMonsterPosition then
		local moved = (monsterRoot.Position - lastMonsterPosition).Magnitude
		local stepInterval = math.clamp(0.7 - (warningIntensity * 0.28), 0.28, 0.7)
		if moved > 0.18 and now - lastMonsterStepAt >= stepInterval and monsterStepSound then
			lastMonsterStepAt = now
			monsterStepSound.Volume = math.clamp(warningIntensity * 0.46, 0.04, 0.46)
			monsterStepSound.PlaybackSpeed = 0.62 + (math.random() * 0.12)
			monsterStepSound:Play()
		end
	end

	lastMonsterPosition = monsterRoot.Position
	return distance
end

function AudioFeedback.init()
	if initialized then return end
	initialized = true

	ensureSounds()

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local humanoid = getHumanoid()
		local rootPart = getCharacterRoot()
		local monsterDistance = updateMonsterAudio(now, rootPart)

		if humanoid then
			updatePlayerFootsteps(now, humanoid)
			updateBreathing(humanoid, monsterDistance)
		end
	end)
end

return AudioFeedback

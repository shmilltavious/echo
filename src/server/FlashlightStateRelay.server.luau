local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FLASHLIGHT_EVENT_NAME = "FlashlightState"
local MAX_ORIGIN_DISTANCE = 14
local MIN_REPORT_INTERVAL = 0.04
local MAX_RANGE = 40

local flashlightStateEvent = ReplicatedStorage:FindFirstChild(FLASHLIGHT_EVENT_NAME) or Instance.new("RemoteEvent")
flashlightStateEvent.Name = FLASHLIGHT_EVENT_NAME
flashlightStateEvent.Parent = ReplicatedStorage

local lastReportAt = {}

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function sanitizePayload(player: Player, payload)
	local root = getRoot(player)
	if not root then
		return {
			sourceUserId = player.UserId,
			enabled = false,
		}
	end

	if typeof(payload) ~= "table" or payload.enabled ~= true or player:GetAttribute("Escaped") == true then
		return {
			sourceUserId = player.UserId,
			enabled = false,
		}
	end

	local origin = payload.origin
	local direction = payload.direction
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude <= 0 then
		return {
			sourceUserId = player.UserId,
			enabled = false,
		}
	end

	if (origin - root.Position).Magnitude > MAX_ORIGIN_DISTANCE then
		origin = root.Position + Vector3.new(0, 1.4, 0)
	end

	return {
		sourceUserId = player.UserId,
		enabled = true,
		origin = origin,
		direction = direction.Unit,
		range = math.clamp(tonumber(payload.range) or MAX_RANGE, 8, MAX_RANGE),
		brightnessScale = math.clamp(tonumber(payload.brightnessScale) or 1, 0.1, 1),
	}
end

local function broadcastExcept(sourcePlayer: Player, payload)
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= sourcePlayer then
			flashlightStateEvent:FireClient(player, payload)
		end
	end
end

flashlightStateEvent.OnServerEvent:Connect(function(player, payload)
	local now = os.clock()
	if now - (lastReportAt[player] or 0) < MIN_REPORT_INTERVAL then
		return
	end
	lastReportAt[player] = now

	broadcastExcept(player, sanitizePayload(player, payload))
end)

Players.PlayerRemoving:Connect(function(player)
	lastReportAt[player] = nil
	broadcastExcept(player, {
		sourceUserId = player.UserId,
		enabled = false,
	})
end)

local Debris = game:GetService("Debris")

local SoundManager = {}

local DEFAULT_ROLLOFF_MIN = 5
local DEFAULT_ROLLOFF_MAX = 150

local function normalizeId(soundId: string): string
	if soundId:sub(1, 13) == "rbxassetid://" then
		return soundId
	end
	return "rbxassetid://" .. soundId
end

local function buildSound(soundId: string, config: {[string]: any}): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = normalizeId(soundId)
	sound.Volume = config.Volume or 0.65
	sound.Pitch = config.Pitch or 1
	sound.RollOffMinDistance = config.RollOffMin or DEFAULT_ROLLOFF_MIN
	sound.RollOffMaxDistance = config.RollOffMax or DEFAULT_ROLLOFF_MAX
	sound.Looped = config.Looped or false
	return sound
end

function SoundManager.PlayOneShot3D(position: Vector3, soundId: string, config: {[string]: any}?)
	config = config or {}

	local anchor = Instance.new("Part")
	anchor.Name = "_SoundManagerAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local sound = buildSound(soundId, config)
	sound.Parent = anchor
	sound.Ended:Once(function() anchor:Destroy() end)
	sound:Play()

	Debris:AddItem(anchor, config.MaxLifetime or 10)
end

function SoundManager.PlayAttached(instance: Instance, soundId: string, config: {[string]: any}?, key: string?)
	config = config or {}

	local sound = key and instance:FindFirstChild(key)

	if not sound then
		sound = buildSound(soundId, config)
		if key then sound.Name = key end
		sound.Parent = instance
	else
		(sound :: Sound).SoundId = normalizeId(soundId)
	end

	(sound :: Sound):Play()

	if not key then
		(sound :: Sound).Ended:Once(function() sound:Destroy() end)
		Debris:AddItem(sound, config.MaxLifetime or 10)
	end

	return sound
end

return SoundManager

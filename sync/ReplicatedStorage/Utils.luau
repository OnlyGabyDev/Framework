local Utils = {}

function Utils.getRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
end

function Utils.GetCameraRelativeDirection(moveVector, cameraCFrame)
	local camLook = cameraCFrame.LookVector
	camLook = Vector3.new(camLook.X, 0, camLook.Z).Unit

	local camRight = cameraCFrame.RightVector
	camRight = Vector3.new(camRight.X, 0, camRight.Z).Unit

	local direction = (camLook * moveVector.Z) + (camRight * moveVector.X)

	if direction.Magnitude > 0 then
		return direction.Unit
	else
		return Vector3.zero
	end
end

function Utils.clamp(value, min, max)
	if value < min then
		return min
	elseif value > max then
		return max
	else
		return value
	end
end

function Utils.lerp(a, b, t)
	return a + (b - a) * t
end

function Utils.round(value)
	return math.floor(value + 0.5)
end

function Utils.sign(value)
	if value > 0 then
		return 1
	elseif value < 0 then
		return -1
	else
		return 0
	end
end

function Utils.percent(part, whole)
	if whole == 0 then
		return 0
	else
		return (part / whole) * 100
	end
end


local function cloneFunction(fn)
	return function(...)
		return fn(...)
	end
end

function Utils.copySkill(skill)
	local copy = {
		data = {},
		callbacks = {}
	}
	for key, value in pairs(skill.data) do
		if type(value) == "table" then
			local t = {}
			for k, v in pairs(value) do
				t[k] = v
			end
			copy.data[key] = t
		else
			copy.data[key] = value
		end
	end

	for name, fn in pairs(skill.callbacks) do
		if type(fn) == "function" then
			copy.callbacks[name] = cloneFunction(fn)
		end
	end

	return copy
end


return Utils
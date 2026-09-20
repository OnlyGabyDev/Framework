local Utils = {}

function Utils.getRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
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



return Utils
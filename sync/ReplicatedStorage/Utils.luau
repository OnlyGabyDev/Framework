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

--[[
Rotaciona `current` em direção a `target` (Vector3, não precisam ser unitários),
respeitando um ângulo máximo por chamada. DONO ÚNICO dessa lógica (Regra 1) —
usado por MovementController (giro de personagem em Force) e por
HitboxBehaviors.Homing (giro de projétil). Não duplique isto em nenhum lugar.
]]
function Utils.rotateTowards(current, target, maxRadians)
	if current.Magnitude < 1e-6 then
		return target.Unit
	end

	local currentUnit = current.Unit
	local targetUnit = target.Unit

	local dot = math.clamp(currentUnit:Dot(targetUnit), -1, 1)
	local angle = math.acos(dot)

	if angle <= maxRadians or angle < 1e-4 then
		return targetUnit
	end

	local axis = currentUnit:Cross(targetUnit)
	if axis.Magnitude < 1e-6 then
		axis = currentUnit:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-6 then
			axis = Vector3.xAxis
		end
	end

	local rotation = CFrame.fromAxisAngle(axis.Unit, maxRadians)
	return (rotation * currentUnit).Unit
end

--[[
Projeta moveDirection no espaço LOCAL 2D de facingDirection: X = componente
lateral (direita positiva), Z = componente frontal (frente positiva). Plano
XZ só (é INTENÇÃO de combate, não voo). Dono único da matemática de projeção
— tanto classifyDirection quanto Helper.BuildContext usam isto, não duplique.
]]
function Utils.worldToLocalPlanar(moveDirection, facingDirection)
	local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flatMove.Magnitude < 0.1 then
		return Vector3.zero
	end
	flatMove = flatMove.Unit

	local flatFacing = Vector3.new(facingDirection.X, 0, facingDirection.Z)
	flatFacing = flatFacing.Magnitude < 0.1 and Vector3.new(0, 0, -1) or flatFacing.Unit

	local right = Vector3.new(flatFacing.Z, 0, -flatFacing.X)
	local forwardDot = flatMove:Dot(flatFacing)
	local rightDot = flatMove:Dot(right)

	return Vector3.new(rightDot, 0, forwardDot)
end

--[[
Classifica em octante: "Forward","ForwardRight","Right","BackRight","Back",
"BackLeft","Left","ForwardLeft", ou "None" se moveDirection for ~zero.
]]
function Utils.classifyDirection(moveDirection, facingDirection)
	local localVec = Utils.worldToLocalPlanar(moveDirection, facingDirection)
	if localVec.Magnitude < 0.05 then
		return "None"
	end

	local angle = math.deg(math.atan2(localVec.X, localVec.Z))

	if angle >= -22.5 and angle < 22.5 then return "Forward"
	elseif angle >= 22.5 and angle < 67.5 then return "ForwardRight"
	elseif angle >= 67.5 and angle < 112.5 then return "Right"
	elseif angle >= 112.5 and angle < 157.5 then return "BackRight"
	elseif angle >= 157.5 or angle < -157.5 then return "Back"
	elseif angle >= -157.5 and angle < -112.5 then return "BackLeft"
	elseif angle >= -112.5 and angle < -67.5 then return "Left"
	else return "ForwardLeft" end
end

return Utils
local ContextActionService = game:GetService("ContextActionService")

-- Define ações para vetores e botões (caso tenha suporte a console futuramente é só adicionar mais keys)
local inputConfig = {
	Forward = {
		keys = { Enum.KeyCode.W, Enum.KeyCode.Up },
		vector = Vector3.new(0, 0, 1),
	},
	Back = {
		keys = { Enum.KeyCode.S, Enum.KeyCode.Down },
		vector = Vector3.new(0, 0, -1),
	},
	Left = {
		keys = { Enum.KeyCode.A, Enum.KeyCode.Left },
		vector = Vector3.new(-1, 0, 0),
	},
	Right = {
		keys = { Enum.KeyCode.D, Enum.KeyCode.Right },
		vector = Vector3.new(1, 0, 0),
	},
}


local activeInputs = {}
local lastPressed = nil
local lastVector = Vector3.zero


-- Callback genérico para todas as ações
local function onAction(actionName, inputState, _)
	if not inputConfig[actionName] then
		return Enum.ContextActionResult.Pass
	end

	if inputState == Enum.UserInputState.Begin then
		activeInputs[actionName] = true
		LastPressed = actionName
		LastVector = inputConfig[actionName].vector
	elseif inputState == Enum.UserInputState.End then
		activeInputs[actionName] = false
	end

	return Enum.ContextActionResult.Pass
end

-- Bind automático com base na tabela de config
for actionName, data in pairs(inputConfig) do
	ContextActionService:BindAction(actionName, onAction, false, unpack(data.keys))
	activeInputs[actionName] = false
end

-- Utilidade: calcular direção atual
local function getCurrentDirection()
	local dir = Vector3.zero
	for action, isPressed in pairs(activeInputs) do
		if isPressed then
			dir += inputConfig[action].vector
		end
	end
	return dir.Magnitude > 0 and dir.Unit or Vector3.zero
end

return {
	GetCurrentDirection = getCurrentDirection,
	GetLastPressedDirection = function()
		return LastVector
	end,
	GetLastPressed = function()
		return LastPressed
	end
}

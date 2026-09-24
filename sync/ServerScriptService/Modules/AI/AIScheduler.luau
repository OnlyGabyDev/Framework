--[[ Roda o Brain de todo AIComponent ativo num único Heartbeat (Regra 6 —
mesmo padrão de MovementController: nada de 1 conexão por entidade). ]]
local RunService = game:GetService("RunService")

local AIScheduler = {}
local tracked = {}

function AIScheduler.Register(component)
	tracked[component] = true
end

function AIScheduler.Unregister(component)
	tracked[component] = nil
end

RunService.Heartbeat:Connect(function(dt)
	for component in pairs(tracked) do
		if component.Enabled and component.Brain then
			local ok, err = pcall(component.Brain, component.Entity, dt)
			if not ok then
				warn("[AIScheduler] Erro no Brain de", tostring(component.Entity and component.Entity.ID), ":", err)
			end
		end
	end
end)

return AIScheduler

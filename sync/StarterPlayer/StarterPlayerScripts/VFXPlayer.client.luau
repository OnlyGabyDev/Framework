local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(script.Parent.VFXRegistry)

local PlayVFX = ReplicatedStorage.RemoteEvents:WaitForChild("PlayVFX")

PlayVFX.OnClientEvent:Connect(function(effectName: string, data: {[string]: any})
	print("[VFXPlayer] Recebido evento para:", effectName)
	local builder = Registry[effectName]
	if not builder then
		warn("[VFXPlayer] Efeito não registrado:", effectName)
		return
	end

	local ok, err = pcall(builder, data)
	if not ok then
		warn("[VFXPlayer] Erro construindo efeito", effectName, ":", err)
	else
		print("[VFXPlayer] Efeito construído com sucesso:", effectName)
	end
end)

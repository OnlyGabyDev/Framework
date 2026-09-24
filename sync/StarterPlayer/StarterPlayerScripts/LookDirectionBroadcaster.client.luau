--[[
	LookDirectionBroadcaster
	========================
	Envia a direção "plana" (sem componente Y) da câmera do jogador pro
	servidor, em baixa frequência, via UnreliableRemoteEvent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RequestLook = ReplicatedStorage.RemoteEvents:WaitForChild("RequestLook")
local camera = workspace.CurrentCamera

local SEND_RATE = 1 / 30       -- 30hz é de sobra pra direção de câmera. Suba se notar delay perceptível no steering.
local MIN_DELTA = 0.02         -- não reenvia se a direção não mudou o suficiente

local accumulated = 0
local lastSent = Vector3.zero

RunService.RenderStepped:Connect(function(dt)
	accumulated += dt
	if accumulated < SEND_RATE then
		return
	end
	accumulated = 0

	-- Antes achatava aqui (Y=0) antes de enviar. Agora manda o vetor 3D
	-- cheio — LookDirection (combate, plano) continua existindo, mas é
	-- DERIVADO no servidor a partir deste vetor. Isso é o que permite Ults
	-- de voo considerarem o pitch da câmera sem duplicar remote/rate-limit.
	local aim = camera.CFrame.LookVector

	if (aim - lastSent).Magnitude > MIN_DELTA then
		lastSent = aim
		RequestLook:FireServer(aim)
	end
end)

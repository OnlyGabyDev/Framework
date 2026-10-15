--[[
	__AuditClientHooks (LocalScript, coloque em PlayerGui durante o Play)
	Registra o que o servidor manda pro cliente e as trocas de CameraSubject.
	Saída: ReplicatedStorage.__ClientAuditLog (StringValue LOCAL, JSON).
	Usado para ler os cenários P6 (HUD) e P7 (câmera) da BatchP e os casos F22/F56/F57.
]]

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Remotes = RS:WaitForChild("RemoteEvents")
local log = RS:FindFirstChild("__ClientAuditLog") or Instance.new("StringValue")
log.Name = "__ClientAuditLog"
log.Parent = RS

local entries = {}
local function push(kind, ...)
	local args = table.pack(...)
	local parts = {}
	for i = 1, args.n do
		parts[i] = tostring(args[i])
	end
	table.insert(entries, { t = math.floor(workspace.DistributedGameTime * 100) / 100, k = kind, a = table.concat(parts, "|") })
	if #entries > 400 then
		table.remove(entries, 1)
	end
	log.Value = HttpService:JSONEncode(entries)
end

Remotes.ControlStateChanged.OnClientEvent:Connect(function(...) push("ControlStateChanged", ...) end)
Remotes.UpdateHealthBar.OnClientEvent:Connect(function(...) push("UpdateHealthBar", ...) end)
Remotes.SkillFired.OnClientEvent:Connect(function(...) push("SkillFired", ...) end)

local camera = workspace.CurrentCamera
camera:GetPropertyChangedSignal("CameraSubject"):Connect(function()
	push("CameraSubject", camera.CameraSubject and camera.CameraSubject:GetFullName() or "nil")
end)
Players.LocalPlayer.CharacterAdded:Connect(function(character)
	push("CharacterAdded", character:GetFullName())
end)

push("hooked", "ok")

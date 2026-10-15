--[[
	__AuditUltDriver (LocalScript, coloque em PlayerGui durante o Play)
	Par do probes/PlayerUlt.server.luau. Quando ReplicatedStorage.UltGo vira true,
	aperta e solta a intent Ultimate pela rede (mesmo caminho do InputService).
]]

local RS = game:GetService("ReplicatedStorage")
local R = RS:WaitForChild("RemoteEvents")

local t0 = os.clock()
while not RS:GetAttribute("UltGo") and os.clock() - t0 < 15 do
	task.wait(0.05)
end
R.RequestIntent:FireServer("Ultimate", true)
task.wait(0.1)
R.RequestIntent:FireServer("Ultimate", false)

script:Destroy()

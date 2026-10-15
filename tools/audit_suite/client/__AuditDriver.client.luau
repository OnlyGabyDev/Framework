--[[
	__AuditDriver (LocalScript, coloque em PlayerGui durante o Play)
	Par do probes/ManualSeq.server.luau. Faz o papel do jogador durante a sequência
	de possessão manual (torre -> enxame): manda RequestDir e RequestIntent pelos
	mesmos remotes do InputService, quando ReplicatedStorage.AuditStep muda.
	O teclado virtual do Studio é recusado pelo VirtualInput; este driver é o atalho.
]]

local RS = game:GetService("ReplicatedStorage")
local R = RS:WaitForChild("RemoteEvents")
local done = {}

local function press(intent)
	R.RequestIntent:FireServer(intent, true)
	task.wait(0.08)
	R.RequestIntent:FireServer(intent, false)
end

while true do
	local st = RS:GetAttribute("AuditStep")
	if st == "tower" and not done.tower then
		done.tower = true
		for _ = 1, 30 do
			R.RequestDir:FireServer(Vector3.new(0, 0, -1))
			task.wait(0.05)
		end
		R.RequestDir:FireServer(Vector3.zero)
		press("Primary")
		task.wait(1.4)
		press("Primary")
	elseif st == "swarm" and not done.swarm then
		done.swarm = true
		for _ = 1, 40 do
			R.RequestDir:FireServer(Vector3.new(1, 0, 0))
			task.wait(0.05)
		end
		R.RequestDir:FireServer(Vector3.zero)
		press("Primary")
		task.wait(1)
		press("Primary")
	elseif st == "done" then
		break
	end
	task.wait(0.05)
end

script:Destroy()

-- SONDA TEMPORÁRIA (investigação do atraso ao mover o hunter). Apagar depois.
local Run = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
repeat task.wait(0.2) until workspace.DistributedGameTime > 9
local hunter
for _, m in workspace:GetChildren() do
	if m:IsA("Model") and m.PrimaryPart and m.PrimaryPart.Color == Color3.fromRGB(200, 40, 40) then hunter = m end
end
if not hunter then warn("[Probe] hunter não achado no cliente") return end
local root = hunter.PrimaryPart
for trial = 1, 4 do
	local start = root.Position
	local t0 = os.clock()
	RS.RemoteEvents.RequestDir:FireServer(Vector3.new(0, 0, trial % 2 == 0 and 1 or -1))
	local tMove
	repeat
		Run.Heartbeat:Wait()
		if ((root.Position - start) * Vector3.new(1, 0, 1)).Magnitude > 0.5 then tMove = os.clock() - t0 end
	until tMove or os.clock() - t0 > 2
	task.wait(0.6)
	RS.RemoteEvents.RequestDir:FireServer(Vector3.zero)
	local t1 = os.clock()
	local tStop
	repeat
		Run.Heartbeat:Wait()
		if (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude < 1 then tStop = os.clock() - t1 end
	until tStop or os.clock() - t1 > 2
	print(string.format("[Probe:Client] tentativa %d: andou em %s, parou em %s (t=%.1f)", trial,
		tMove and string.format("%.3fs", tMove) or ">2s", tStop and string.format("%.3fs", tStop) or ">2s", workspace.DistributedGameTime))
	task.wait(0.6)
end

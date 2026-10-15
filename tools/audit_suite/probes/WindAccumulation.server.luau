--[[
	Sonda F29 (vento acumulando forças) + dash Hard atravessando o vento.
	Resultado em ServerStorage.__AUDIT:GetAttribute("EnvFollow").
	Antes da correção: "forças Fan simultâneas no pico=5 | velocidade X máx=100.0 (configurado 20)".
	Depois da correção esperado: pico=1 e velocidade ~20.
]]

local SS = game:GetService("ServerStorage")
local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"
folder.Parent = SS

local Lib = require(SS.__AuditKitLib)
local AreaEffect = require(SS.Modules.Combat.AreaEffect)
local AreaBehaviors = require(SS.Modules.Combat.AreaBehaviors)

local C = Vector3.new(-300, 103, 900)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(600, 2, 200)
floor.Position = C - Vector3.new(0, 4, 0)
floor.Parent = workspace

local out = {}

-- (a) corpo leve dentro de uma zona larga, sem sair dela
local e = Lib.spawn("EnvAcc", "Env", C + Vector3.new(-250, 0.8, 0), { size = Vector3.new(1, 1.4, 1), comps = { "Character", "Health", "Status", "Movement", "Attributes" }, hp = 1e6 })
task.wait(0.4)
local z = AreaEffect.new(function() return CFrame.new(C) end, "Box", Vector3.new(560, 20, 40), 10)
z:OnStay(function(ent) AreaBehaviors.DirectionalForce(ent, Vector3.xAxis, 20, "Fan", { RequiresControl = false }) end)
z:Start()
local maxF, maxV = 0, 0
local t0 = os.clock()
while os.clock() - t0 < 2.5 do
	local n = 0
	for _, f in pairs(e:GetComponent("Movement").ActiveForces) do
		if f.Type == "Fan" then n += 1 end
	end
	maxF = math.max(maxF, n)
	maxV = math.max(maxV, e.GetRoot().AssemblyLinearVelocity.X)
	task.wait(0.05)
end
table.insert(out, ("(a) forças Fan simultâneas no pico=%d | velocidade X máx=%.1f (configurado 20)"):format(maxF, maxV))

-- (b) dash Hard atravessando o vento: velocidade X amostrada durante o dash (deve ficar 0 enquanto o dash dura)
local d = Lib.spawn("EnvDash", "Env", C + Vector3.new(100, 1.6, -15), { size = Vector3.new(2, 3, 1.5), comps = { "Character", "Health", "Status", "Movement", "Attributes" }, hp = 1e6 })
task.wait(0.6)
d.AddForce({ Type = "Dash", Duration = 0.5, Speed = 60, Direction = Vector3.zAxis, Hard = true, Priority = 10 })
local vx = {}
for _ = 1, 8 do
	task.wait(0.05)
	table.insert(vx, string.format("%.1f", d.GetRoot().AssemblyLinearVelocity.X))
end
table.insert(out, "(b) velocidade X durante o dash (amostras ~50 ms): " .. table.concat(vx, ","))

z:Stop()
Lib.despawn(e)
Lib.despawn(d)
floor:Destroy()
folder:SetAttribute("EnvFollow", table.concat(out, "\n"))
print("[AUDIT] WindAccumulation:\n" .. table.concat(out, "\n"))

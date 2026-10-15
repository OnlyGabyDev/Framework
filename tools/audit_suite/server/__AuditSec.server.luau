local SS, RS = game.ServerStorage, game.ReplicatedStorage
local SSS = game.ServerScriptService
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local DataManager = require(SSS.EntityData.DataManager)
local AC = require(SSS.Modules.GlobalAntiCheat)
local StateTable = require(SS.Modules.Combat.StateTable)
local AreaEffect = require(SS.Modules.Combat.AreaEffect)
local AreaBehaviors = require(SS.Modules.Combat.AreaBehaviors)
local plr = game.Players:GetPlayers()[1]
local pid = "Player_" .. plr.UserId
local body = DataManager.Get(pid)
local hrp = plr.Character.HumanoidRootPart
local log = {}
local errs, errSample = 0, nil
local lc = LogService.MessageOut:Connect(function(m, t) if t == Enum.MessageType.MessageError then errs += 1; errSample = errSample or m:sub(1, 200) end end)
local frames = {}
local hbc = RunService.Heartbeat:Connect(function(dt) table.insert(frames, dt) end)
local function L(s) table.insert(log, s) end
local function step(name, waitClient)
	RS:SetAttribute("SecAck", nil)
	RS:SetAttribute("SecStep", name)
	if waitClient then
		local t0 = os.clock()
		while RS:GetAttribute("SecAck") ~= name and os.clock() - t0 < 8 do task.wait(0.05) end
	end
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local home = hrp.CFrame
task.wait(1)

-- S0 baseline
local p0 = hrp.Position; task.wait(1)
L(("S0 parado: deslocamento=%.1f studs"):format(flat(hrp.Position - p0).Magnitude))
-- S1 speed hack por CFrame
p0 = hrp.Position
step("speedhack", true)
L(("S1 speed hack (cliente move o HRP por CFrame, ~120 studs/s por 1 s): servidor viu %.1f studs; WalkSpeed no servidor=%s"):format(flat(hrp.Position - p0).Magnitude, tostring(plr.Character.Humanoid.WalkSpeed)))
-- S2 teleporte
p0 = hrp.Position
step("teleport", true)
local jump = (hrp.Position - p0).Magnitude
task.wait(2)
L(("S2 teleporte de 150 studs pelo cliente: servidor viu salto de %.1f studs; 2 s depois ainda está lá? %s"):format(jump, tostring((hrp.Position - p0).Magnitude > 100)))
hrp.CFrame = home; task.wait(0.5)
-- S3 andar durante Stun
body.ApplyStatus(StateTable.States.Stun, { Duration = 3 })
task.wait(0.3)
p0 = hrp.Position
step("stunwalk", true)
L(("S3 Stun ativo (WalkSpeed servidor=%s), cliente anda por CFrame: servidor viu %.1f studs"):format(tostring(plr.Character.Humanoid.WalkSpeed), flat(hrp.Position - p0).Magnitude))
body.RemoveStatus("Stun")
hrp.CFrame = home; task.wait(0.5)
-- S4 Lock de input
AC.LockPlayerInput(plr); task.wait(0.3)
p0 = hrp.Position
step("lockwalk", true)
L(("S4 LockPlayerInput ativo, cliente anda por CFrame: servidor viu %.1f studs"):format(flat(hrp.Position - p0).Magnitude))
AC.UnlockPlayerInput(plr)
hrp.CFrame = home; task.wait(0.5)
-- S5 WalkSpeed local
step("walkspeed", true)
L(("S5 cliente seta WalkSpeed=100: servidor enxerga WalkSpeed=%s; cliente reportou=%s"):format(tostring(plr.Character.Humanoid.WalkSpeed), tostring(RS:GetAttribute("SecClientWS"))))
-- S6 fuzz de remotes
local e0 = errs
table.clear(frames)
step("fuzz", true)
L(("S6 fuzz (%s mensagens com tipos inválidos/NaN/inf): erros no servidor=%d %s"):format(tostring(RS:GetAttribute("SecFuzzCount")), errs - e0, errSample and ("ex: " .. errSample) or ""))
-- S7 spam
table.clear(frames)
local cd0 = body.GetCooldown("Schema_M1")
step("spam", true)
local s, m = 0, 0
for _, d in ipairs(frames) do s += d; m = math.max(m, d) end
L(("S7 spam (5000 RequestLook + 2000 RequestDir + 300 Press/Release): frame médio=%.1f ms, máx=%.1f ms"):format(s / math.max(1, #frames) * 1000, m * 1000))
-- S8 ventilador no player (física client-owned)
hrp.CFrame = home; task.wait(0.5)
p0 = hrp.Position
local z = AreaEffect.new(function() return hrp.CFrame end, "Box", Vector3.new(12, 12, 12), 10)
z:OnStay(function(ent) AreaBehaviors.DirectionalForce(ent, Vector3.xAxis, 20, "Fan", { RequiresControl = false }) end)
z:Start()
task.wait(1.5)
z:Stop()
L(("S8 ventilador (20 studs/s nominal) no player client-owned: deslocamento=%.1f studs em 1.5 s"):format(flat(hrp.Position - p0).Magnitude))
hrp.CFrame = home
step("done", false)
hbc:Disconnect(); lc:Disconnect()
SS.__AUDIT:SetAttribute("SecLog", table.concat(log, "\n"))

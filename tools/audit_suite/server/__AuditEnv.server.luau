local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Lib = require(SS.__AuditKitLib)
local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)
local E = StateTable.Enum
local SkillHandler = require(SSS.Modules.SkillHandler)
local AreaEffect = require(SS.Modules.Combat.AreaEffect)
local AreaBehaviors = require(SS.Modules.Combat.AreaBehaviors)

local out = SS.__AUDIT:FindFirstChild("Env") or Instance.new("StringValue")
out.Name = "Env"; out.Parent = SS.__AUDIT
local results = {}
local errors = {}
local lc = LogService.MessageOut:Connect(function(m, t) if t == Enum.MessageType.MessageError then table.insert(errors, m:sub(1, 200)) end end)
local function flush(done) out.Value = HttpService:JSONEncode({ done = done, results = results }) end
local function test(id, name, fn)
	local rec = { id = id, name = name, checks = {}, metrics = {} }
	local t = {}
	function t.check(label, cond, observed) table.insert(rec.checks, { label = label, ok = cond and true or false, observed = tostring(observed) }) end
	function t.metric(k, v) rec.metrics[k] = (type(v) == "number") and (math.floor(v * 100 + 0.5) / 100) or tostring(v) end
	local e0 = #errors
	local ok, err = xpcall(fn, debug.traceback, t)
	if not ok then rec.error = tostring(err):sub(1, 800) end
	rec.server_errors = {}
	for i = e0 + 1, math.min(#errors, e0 + 5) do table.insert(rec.server_errors, errors[i]) end
	local pass = ok
	for _, c in ipairs(rec.checks) do if not c.ok then pass = false end end
	rec.status = pass and "PASS" or "FAIL"
	table.insert(results, rec); flush(false)
end

local C = Vector3.new(-300, 103, -900)
local floor = Instance.new("Part"); floor.Name = "__AuditEnvFloor"; floor.Anchored = true
floor.Size = Vector3.new(400, 2, 400); floor.Position = C - Vector3.new(0, 4, 0); floor.Parent = workspace
local FLOOR_Y = floor.Position.Y + 1

local SIZES = { leve = Vector3.new(1, 1.4, 1), medio = Vector3.new(2, 3, 1.5), pesado = Vector3.new(5, 7, 4) }
local made = {}
local function body(kind, pos, comps)
	local sz = SIZES[kind]
	local e = Lib.spawn("Env_" .. kind, "Env", Vector3.new(pos.X, FLOOR_Y + sz.Y / 2 + 0.05, pos.Z), { size = sz, comps = comps or { "Character", "Health", "Status", "Movement", "Attributes" }, speed = 16, hp = 1e6 })
	table.insert(made, e)
	return e
end
local function clear()
	for _, e in ipairs(made) do if e.Active then Lib.despawn(e) end end
	table.clear(made)
end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function fanZone(center, size, dir, speed, opts)
	local z = AreaEffect.new(function() return CFrame.new(center) end, "Box", size, 10)
	z:OnStay(function(ent) AreaBehaviors.DirectionalForce(ent, dir, speed, "Fan", opts) end)
	z:OnEnter(function(ent) AreaBehaviors.DirectionalForce(ent, dir, speed, "Fan", opts) end)
	z:Start()
	return z
end
local function countForces(e, ftype)
	local n = 0
	for _, f in pairs(e:GetComponent("Movement").ActiveForces) do if not ftype or f.Type == ftype then n += 1 end end
	return n
end

task.wait(1)

test("ENV1", "Ventilador empurra corpos leve/médio/pesado (+ acúmulo de forças por OnStay)", function(t)
	local base = C + Vector3.new(-120, 0, -120)
	local L, M, H = body("leve", base + Vector3.new(-15, 0, -8)), body("medio", base + Vector3.new(-15, 0, 0)), body("pesado", base + Vector3.new(-15, 0, 10))
	task.wait(0.5)
	local p0 = { L.GetRoot().Position, M.GetRoot().Position, H.GetRoot().Position }
	local z = fanZone(base, Vector3.new(40, 16, 40), Vector3.xAxis, 30)
	task.wait(1.0)
	local forcesL = countForces(L, "Fan")
	local vL = L.GetRoot().AssemblyLinearVelocity.X
	task.wait(0.5)
	local d = { flat(L.GetRoot().Position - p0[1]).Magnitude, flat(M.GetRoot().Position - p0[2]).Magnitude, flat(H.GetRoot().Position - p0[3]).Magnitude }
	z:Stop()
	t.metric("deslocamento_leve_1.5s", d[1]); t.metric("deslocamento_medio_1.5s", d[2]); t.metric("deslocamento_pesado_1.5s", d[3])
	t.metric("velocidade_X_leve", vL)
	t.metric("forcas_Fan_simultaneas_no_leve", forcesL)
	t.check("leve e médio são empurrados", d[1] > 5 and d[2] > 5, ("%.1f / %.1f"):format(d[1], d[2]))
	t.check("pesado também é empurrado (vento não ignora massa grande)", d[3] > 2, d[3])
	t.check("OnStay a 10 Hz mantém 1 força de vento (não acumula)", forcesL <= 1, forcesL .. " forças Fan simultâneas")
	t.check("velocidade do empurrão ~ configurada (30)", math.abs(vL - 30) < 8, vL)
	clear()
end)

test("ENV2", "Zonas sobrepostas: empurra +X (30) e puxa -X (20)", function(t)
	local base = C + Vector3.new(0, 0, -120)
	local M = body("medio", base)
	task.wait(0.4)
	local z1 = fanZone(base, Vector3.new(30, 16, 30), Vector3.xAxis, 30, { RequiresControl = false })
	local z2 = fanZone(base, Vector3.new(30, 16, 30), -Vector3.xAxis, 20, { RequiresControl = false })
	task.wait(1)
	local v = M.GetRoot().AssemblyLinearVelocity.X
	t.metric("velocidade_X_resultante", v)
	t.metric("forcas_ativas", countForces(M))
	t.note = nil
	z1:Stop(); z2:Stop()
	t.check("resultante = 30 - 20 = +10 (soma de velocidades Soft)", math.abs(v - 10) < 4, v)
	clear()
end)

test("ENV3", "Vento em alvo com Root (força externa deve ignorar controle)", function(t)
	local base = C + Vector3.new(120, 0, -120)
	local A = body("medio", base + Vector3.new(-8, 0, -4))
	local B = body("medio", base + Vector3.new(-8, 0, 4))
	task.wait(0.4)
	A.ApplyStatus(StateTable.States.Root, { Duration = 5 })
	B.ApplyStatus(StateTable.States.Root, { Duration = 5 })
	local pa, pb = A.GetRoot().Position, B.GetRoot().Position
	local z1 = fanZone(base + Vector3.new(0, 0, -4), Vector3.new(30, 16, 6), Vector3.xAxis, 30)
	local z2 = fanZone(base + Vector3.new(0, 0, 4), Vector3.new(30, 16, 6), Vector3.xAxis, 30, { RequiresControl = false })
	task.wait(1.2)
	local da, db = flat(A.GetRoot().Position - pa).Magnitude, flat(B.GetRoot().Position - pb).Magnitude
	z1:Stop(); z2:Stop()
	t.metric("rooted_vento_padrao", da); t.metric("rooted_vento_RequiresControl_false", db)
	t.check("vento com opções padrão do AreaBehaviors empurra alvo com Root", da > 3, da)
	clear()
end)

test("ENV4", "canDisplace=false bloqueia o próprio dash da entidade?", function(t)
	local base = C + Vector3.new(-120, 0, 0)
	local M = body("medio", base)
	task.wait(0.4)
	M.ApplyStatus({ data = { name = "AncoradoAudit", category = E.Categories.Buff, duration = 3, tags = { [E.Tags.canDisplace] = false } }, callbacks = {} })
	local p0 = M.GetRoot().Position
	local fid = M.AddForce({ Type = "DashProprio", Duration = 0.4, Speed = 60, Direction = Vector3.zAxis, Hard = true, Priority = 10 })
	task.wait(0.5)
	local d = flat(M.GetRoot().Position - p0).Magnitude
	t.metric("deslocamento_dash_com_canDisplace_false", d)
	t.check("dash próprio continua funcionando (canDisplace deveria barrar só forças externas)", d > 10, d)
	clear()
end)

test("ENV5", "Gravidade: zona de baixa gravidade (Override 0.2) e gravidade invertida", function(t)
	local base = C + Vector3.new(0, 0, 0)
	local inside = body("medio", base + Vector3.new(-6, 40, 0))
	local outside = body("medio", base + Vector3.new(40, 40, 0))
	inside.GetRoot().Anchored = true; outside.GetRoot().Anchored = true
	inside.GetRoot().CFrame = CFrame.new(base + Vector3.new(-6, 40, 0)); outside.GetRoot().CFrame = CFrame.new(base + Vector3.new(40, 40, 0))
	local z = AreaEffect.new(function() return CFrame.new(base + Vector3.new(-6, 20, 0)) end, "Box", Vector3.new(14, 60, 14), 20)
	z:OnEnter(function(ent) ent.AddModifier("GravityScale", "LowG", E.ModifierType.Override, 0.2) end)
	z:OnExit(function(ent) ent.RemoveModifier("GravityScale", "LowG") end)
	z:Start()
	task.wait(0.4)
	inside.GetRoot().Anchored = false; outside.GetRoot().Anchored = false
	local t0 = os.clock()
	local tIn, tOut
	while os.clock() - t0 < 8 and (not tIn or not tOut) do
		if not tIn and inside.GetRoot().Position.Y < FLOOR_Y + 3 then tIn = os.clock() - t0 end
		if not tOut and outside.GetRoot().Position.Y < FLOOR_Y + 3 then tOut = os.clock() - t0 end
		task.wait()
	end
	t.metric("queda_fora_s", tOut or -1); t.metric("queda_dentro_s", tIn or -1)
	t.check("queda dentro da zona ~2.2x mais lenta (sqrt(1/0.2))", tIn and tOut and tIn / tOut > 1.7, tIn and tOut and (tIn / tOut) or "sem pouso")
	inside.AddModifier("GravityScale", "Inverte", E.ModifierType.Override, -1)
	t.check("gravidade invertida (GravityScale -1) é possível", inside.GetStat("GravityScale", 1) < 0, inside.GetStat("GravityScale", 1))
	t.metric("air_state_com_gravidade_0", (function() inside.AddModifier("GravityScale", "Zero", E.ModifierType.Override, 0); inside.Teleport(base + Vector3.new(-6, 30, 0)); task.wait(0.2); return inside.GetAirState() end)())
	z:Stop()
	clear()
end)

test("ENV6", "Slow/speed por zona e duas zonas iguais sobrepostas (mesmo sourceID)", function(t)
	local base = C + Vector3.new(120, 0, 0)
	local W = body("leve", base + Vector3.new(-40, 0, 0))
	task.wait(0.4)
	local function zone(cx, w, id, mult)
		local z = AreaEffect.new(function() return CFrame.new(base + Vector3.new(cx, 0, 0)) end, "Box", Vector3.new(w, 16, 12), 20)
		z:OnEnter(function(ent) ent.AddModifier("Speed", id, E.ModifierType.MultPercent, mult) end)
		z:OnExit(function(ent) ent.RemoveModifier("Speed", id) end)
		z:Start()
		return z
	end
	local slow = zone(-20, 12, "SlowZone", 0.5)
	local haste = zone(0, 12, "HasteZone", 2)
	local lamaA = zone(22, 14, "Lama", 0.5)
	local lamaB = zone(30, 14, "Lama", 0.5)
	local samples = {}
	local stop = false
	task.spawn(function()
		while not stop do
			SkillHandler.HandleMovementInput(W.ID, Vector3.xAxis)
			local x = W.GetRoot().Position.X - base.X
			table.insert(samples, { x = x, v = W.GetRoot().AssemblyLinearVelocity.X, s = W.GetStat("Speed", 16) })
			task.wait(0.1)
		end
	end)
	task.wait(6)
	stop = true
	local function avgIn(a, b) local s, n = 0, 0 for _, p in ipairs(samples) do if p.x > a and p.x < b then s += p.v; n += 1 end end return n > 0 and s / n or -1 end
	local function statAt(a, b) for _, p in ipairs(samples) do if p.x > a and p.x < b then return p.s end end return -1 end
	t.metric("vel_livre", avgIn(-38, -27)); t.metric("vel_slow", avgIn(-25, -15)); t.metric("vel_haste", avgIn(-5, 5))
	t.metric("stat_entre_as_lamas_(so_dentro_da_B)", statAt(29.5, 36))
	t.check("slow reduz pela metade (16 -> ~8)", math.abs(avgIn(-25, -15) - 8) < 3, avgIn(-25, -15))
	t.check("haste dobra (16 -> ~32)", math.abs(avgIn(-5, 5) - 32) < 6, avgIn(-5, 5))
	t.check("sair da Lama A mantém o slow enquanto ainda dentro da Lama B", statAt(29.5, 36) < 16, statAt(29.5, 36))
	for _, z in ipairs({ slow, haste, lamaA, lamaB }) do z:Stop() end
	clear()
end)

test("ENV7", "Esteira: NPC andando contra força Soft (+X 10)", function(t)
	local base = C + Vector3.new(-120, 0, 120)
	local W = body("leve", base + Vector3.new(10, 0, 0))
	task.wait(0.4)
	local z = fanZone(base, Vector3.new(60, 16, 12), Vector3.xAxis, 10, { RequiresControl = false })
	local stop = false
	task.spawn(function() while not stop do SkillHandler.HandleMovementInput(W.ID, -Vector3.xAxis); task.wait(0.1) end end)
	task.wait(1.5)
	local v = W.GetRoot().AssemblyLinearVelocity.X
	stop = true; z:Stop()
	t.metric("velocidade_X_andando_contra", v)
	t.check("input do NPC soma com a esteira (16 - 10 = -6)", v < -2, v)
	clear()
end)

test("ENV8", "Knockback (Soft, 0.25 s, 60) em leve/médio/pesado", function(t)
	local base = C + Vector3.new(0, 0, 120)
	local bs = { body("leve", base + Vector3.new(0, 0, -10)), body("medio", base), body("pesado", base + Vector3.new(0, 0, 12)) }
	task.wait(0.5)
	local p0 = {}
	for i, b in ipairs(bs) do p0[i] = b.GetRoot().Position; b.AddForce({ Type = "Knock", Duration = 0.25, Speed = 60, Direction = Vector3.xAxis, RequiresControl = false }) end
	task.wait(0.8)
	local names = { "leve", "medio", "pesado" }
	for i, b in ipairs(bs) do t.metric("knock_" .. names[i], flat(b.GetRoot().Position - p0[i]).Magnitude) end
	t.check("pesado sofre algum knockback", flat(bs[3].GetRoot().Position - p0[3]).Magnitude > 1, flat(bs[3].GetRoot().Position - p0[3]).Magnitude)
	clear()
end)

test("ENV9", "Jump pad (Hard Y 60 por 0.25 s): altura normal x baixa gravidade", function(t)
	local base = C + Vector3.new(120, 0, 120)
	local a, b = body("medio", base), body("medio", base + Vector3.new(20, 0, 0))
	task.wait(0.5)
	b.AddModifier("GravityScale", "LowG", E.ModifierType.Override, 0.3)
	local y0a, y0b = a.GetRoot().Position.Y, b.GetRoot().Position.Y
	for _, e in ipairs({ a, b }) do e.AddForce({ Type = "Pad", Duration = 0.25, Speed = 60, Direction = Vector3.yAxis, Hard = true, Axes = { Y = true }, RequiresControl = false }) end
	local ma, mb = 0, 0
	local t0 = os.clock()
	while os.clock() - t0 < 4 do ma = math.max(ma, a.GetRoot().Position.Y - y0a); mb = math.max(mb, b.GetRoot().Position.Y - y0b); task.wait() end
	t.metric("altura_normal", ma); t.metric("altura_baixa_gravidade", mb)
	t.check("baixa gravidade pula mais alto", mb > ma * 1.5, ("%.1f vs %.1f"):format(mb, ma))
	clear()
end)

test("ENV10", "Carga: 20 ventiladores girando + 30 corpos dentro", function(t)
	local base = C + Vector3.new(0, 0, -40)
	local frames = {}
	local hb = RunService.Heartbeat:Connect(function(dt) table.insert(frames, dt) end)
	task.wait(2)
	local function stats() local s, m = 0, 0 for _, d in ipairs(frames) do s += d; m = math.max(m, d) end return s / math.max(1, #frames) * 1000, m * 1000 end
	local avg0, max0 = stats(); table.clear(frames)
	local bodies = {}
	for i = 1, 30 do table.insert(bodies, body("leve", base + Vector3.new(math.random(-30, 30), 0, math.random(-30, 30)))) end
	local zones, angle = {}, 0
	for i = 1, 20 do
		local cx, cz = math.random(-30, 30), math.random(-30, 30)
		local z = AreaEffect.new(function() return CFrame.new(base + Vector3.new(cx, 0, cz)) * CFrame.Angles(0, os.clock() + i, 0) end, "Box", Vector3.new(16, 12, 16), 10)
		z:OnStay(function(ent) AreaBehaviors.DirectionalForce(ent, function() return (CFrame.Angles(0, os.clock() + i, 0)).LookVector end, 20, "Fan", { RequiresControl = false }) end)
		z:Start(); table.insert(zones, z)
	end
	task.wait(5)
	local avg1, max1 = stats()
	local maxForces = 0
	for _, b in ipairs(bodies) do maxForces = math.max(maxForces, countForces(b)) end
	for _, z in ipairs(zones) do z:Stop() end
	hb:Disconnect()
	t.metric("frame_ms_antes", avg0); t.metric("frame_ms_durante", avg1); t.metric("frame_max_durante", max1)
	t.metric("maior_numero_de_forcas_num_corpo", maxForces)
	t.check("custo médio adicional < 4 ms/frame", avg1 - avg0 < 4, avg1 - avg0)
	clear()
end)

test("ENV11", "Dash (Hard) atravessando ventilador (Soft)", function(t)
	local base = C + Vector3.new(-120, 0, -40)
	local M = body("medio", base + Vector3.new(0, 0, -15))
	task.wait(0.4)
	local z = fanZone(base, Vector3.new(30, 16, 40), Vector3.xAxis, 30, { RequiresControl = false })
	task.wait(0.4)
	local p0 = M.GetRoot().Position
	M.AddForce({ Type = "Dash", Duration = 0.4, Speed = 60, Direction = Vector3.zAxis, Hard = true, Priority = 10 })
	task.wait(0.35)
	local dx = M.GetRoot().Position.X - p0.X
	z:Stop()
	t.metric("deriva_X_durante_dash", dx)
	t.check("dash Hard não sofre deriva lateral do vento", math.abs(dx) < 2, dx)
	clear()
end)

test("ENV12", "Tether (Hard) dentro do ventilador", function(t)
	local base = C + Vector3.new(120, 0, -40)
	local anchor = Instance.new("Part"); anchor.Anchored = true; anchor.CanCollide = false; anchor.Size = Vector3.one; anchor.Position = base + Vector3.new(0, 3, 0); anchor.Parent = workspace
	local V = body("medio", base + Vector3.new(6, 0, 0))
	task.wait(0.4)
	local z = fanZone(base, Vector3.new(30, 16, 30), Vector3.xAxis, 30, { RequiresControl = false })
	V.AddForce({ Type = "Tether", Duration = 2, Hard = true, IgnoreGravity = true, RequiresControl = false, FollowTarget = function() return anchor end, FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true, FollowResponsiveness = 20, FollowMaxSpeed = 100 })
	task.wait(1)
	local drift = (V.GetRoot().Position - anchor.CFrame:PointToWorldSpace(Vector3.new(0, 0, -3))).Magnitude
	z:Stop(); anchor:Destroy()
	t.metric("drift_tether_no_vento", drift)
	t.check("tether segura o alvo contra o vento (< 1.5 stud)", drift < 1.5, drift)
	clear()
end)

test("ENV14", "Entidade destruída dentro de uma zona", function(t)
	local base = C + Vector3.new(0, 0, 40)
	local M = body("medio", base)
	task.wait(0.3)
	local exits, exitErr = 0, nil
	local z = AreaEffect.new(function() return CFrame.new(base) end, "Box", Vector3.new(14, 14, 14), 20)
	z:OnEnter(function(ent) ent.AddModifier("Speed", "ZonaX", E.ModifierType.MultPercent, 0.5) end)
	z:OnExit(function(ent)
		exits += 1
		local ok, err = pcall(function() ent.RemoveModifier("Speed", "ZonaX") end)
		if not ok then exitErr = err end
		t.metric("entidade_no_OnExit_Active", ent.Active)
	end)
	z:Start()
	task.wait(0.4)
	Lib.despawn(M)
	task.wait(0.4)
	z:Stop()
	t.metric("OnExit_chamado", exits)
	t.check("OnExit não estoura com entidade destruída", exitErr == nil, exitErr)
	clear()
end)

lc:Disconnect()
floor:Destroy()
flush(true)
print("[AUDIT] Env concluída")

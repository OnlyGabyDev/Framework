local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)
local E = StateTable.Enum
local SkillHandler = require(SSS.Modules.SkillHandler)
local Intents = require(RS.Input.Intents)
local HitboxSpawner = require(SS.Modules.Combat.Hitbox.HitboxSpawner)
local HitboxWrapperMod = require(SS.Modules.Combat.Hitbox.HitboxWrapper)
local AreaEffect = require(SS.Modules.Combat.AreaEffect)
local Utils = require(RS.Utils)
local MC = require(SSS.Modules.Physics.MovementController)

local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"; folder.Parent = SS
local out = folder:FindFirstChild("BatchC") or Instance.new("StringValue")
out.Name = "BatchC"; out.Parent = folder
local results = {}
local function flush(done) out.Value = HttpService:JSONEncode({ done = done, results = results }) end
local function test(id, name, fn)
	local rec = { id = id, name = name, checks = {}, metrics = {}, notes = {} }
	local t = {}
	function t.check(label, cond, observed) table.insert(rec.checks, { label = label, ok = cond and true or false, observed = tostring(observed) }) end
	function t.metric(k, v) rec.metrics[k] = (type(v) == "number") and (math.floor(v * 1000 + 0.5) / 1000) or tostring(v) end
	function t.note(s) table.insert(rec.notes, tostring(s)) end
	local t0 = os.clock()
	local ok, err = xpcall(fn, debug.traceback, t)
	rec.elapsed_s = math.floor((os.clock() - t0) * 1000) / 1000
	if not ok then rec.error = tostring(err) end
	local pass = ok
	for _, c in ipairs(rec.checks) do if not c.ok then pass = false end end
	rec.status = pass and "PASS" or "FAIL"
	table.insert(results, rec)
	flush(false)
end

local ZONE = Vector3.new(800, 103, -800)
local platform = Instance.new("Part")
platform.Name = "__AuditPlatformC"; platform.Anchored = true
platform.Size = Vector3.new(400, 2, 400); platform.Position = ZONE - Vector3.new(0, 4, 0)
platform.Parent = workspace

local function makeModel(pos, anchored)
	local model = Instance.new("Model")
	model.Name = "__AuditDummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"; root.Size = Vector3.new(2, 2, 1); root.CFrame = CFrame.new(pos); root.Anchored = anchored or false
	root.Parent = model; model.PrimaryPart = root; model.Parent = workspace
	return model
end
local function makeEntity(pos, comps, configs, anchored) return DataManager.Create(makeModel(pos, anchored), comps, configs) end
local function makeRig(pos)
	local rig = workspace.Rig:Clone()
	rig.Name = "__AuditRig"
	rig:PivotTo(CFrame.new(pos))
	rig.Parent = workspace
	return rig
end
local function cleanup(e)
	if not e then return end
	local inst = e.Instance
	if inst then pcall(DataManager.Remove, inst); inst:Destroy() end
end
local P = 0
local function spot() P += 1; return ZONE + Vector3.new(((P % 10) - 5) * 30, 0, (math.floor(P / 10) - 5) * 30) end
local COMBAT_FULL = { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "Weapon", "Animation" }

task.wait(1)

test("T27", "Hitbox: HitStart(1.0) dura quanto? (5 execuções)", function(t)
	local hb, carrier = HitboxSpawner.Spawn(nil, CFrame.new(spot()))
	hb:SetCastData({ CastType = "Spherecast", Radius = 1 })
	local stopped = false
	hb:OnStopped(function() stopped = true end)
	local ds = {}
	for _ = 1, 5 do
		stopped = false
		local t0 = os.clock()
		hb:HitStart(1.0)
		while not stopped and os.clock() - t0 < 3 do task.wait() end
		table.insert(ds, os.clock() - t0)
	end
	HitboxSpawner.Cleanup(hb, carrier)
	local sum, mn, mx = 0, math.huge, 0
	for _, d in ipairs(ds) do sum += d; mn = math.min(mn, d); mx = math.max(mx, d) end
	t.metric("duracao_media_s", sum / #ds); t.metric("min_s", mn); t.metric("max_s", mx)
	t.check("dura 1.0 s ± 0.1", math.abs(sum / #ds - 1) < 0.1, sum / #ds)
end)

test("T28", "Hitbox: Blockcast reaproveita CFrame da ativação anterior", function(t)
	local A = spot()
	local hb, carrier = HitboxSpawner.Spawn(nil, CFrame.new(A))
	hb:SetCastData({ CastType = "Blockcast", Size = Vector3.new(4, 4, 4) })
	local moving = true
	hb:OnUpdate(function(dt)
		if moving then HitboxSpawner.SetCarrierCFrame(carrier, carrier.CFrame + Vector3.new(20 * dt, 0, 0)) end
	end)
	hb:HitStart(0.3); task.wait(0.5)
	moving = false
	local A2 = carrier.Position
	local seg
	for _, s in pairs(hb:GetAllSegments()) do seg = s end
	local stale = seg and seg.CastData._LastCFrameBlockCast
	HitboxSpawner.SetCarrierCFrame(carrier, CFrame.new(A + Vector3.new(0, 0, 80)))
	local target = Instance.new("Part")
	target.Anchored = true; target.Size = Vector3.new(4, 6, 4); target.Position = A2 + Vector3.new(4.6, 0, 0); target.Parent = workspace
	local phantom = false
	hb:OnHit(function(result) if result and result.Instance == target then phantom = true end end)
	hb:HitStart(0.3)
	local still = seg and seg.CastData._LastCFrameBlockCast
	t.check("HitStart zera o _LastCFrameBlockCast", still == nil or (still.Position - carrier.Position).Magnitude < 1, still and ("ainda aponta pra posição antiga, a " .. math.floor((still.Position - carrier.Position).Magnitude) .. " studs") or "nil")
	task.wait(0.5)
	t.check("hitbox reposicionada a 80 studs não acerta alvo da posição antiga", not phantom, "acerto fantasma na posição da ativação anterior")
	target:Destroy()
	HitboxSpawner.Cleanup(hb, carrier)
	t.metric("stale_existia_antes", stale ~= nil)
end)

test("T29", "Hitbox de arma: giro de 360° acerta o alvo 1 vez (anti multi-hit) e caminho sem Combat", function(t)
	local blade = Instance.new("Model"); blade.Name = "AuditBlade"
	local handle = Instance.new("Part"); handle.Name = "Handle"; handle.Size = Vector3.new(1, 1, 1); handle.CanCollide = false; handle.Massless = true; handle.Parent = blade
	local hbFolder = Instance.new("Folder"); hbFolder.Name = "Hitbox"; hbFolder.Parent = blade
	local edge = Instance.new("Part"); edge.Name = "Edge"; edge.Size = Vector3.new(0.5, 0.5, 6); edge.CanCollide = false; edge.Massless = true
	edge.CFrame = handle.CFrame * CFrame.new(0, 0, -3.5); edge.Parent = hbFolder
	for i = 1, 3 do local a = Instance.new("Attachment"); a.Name = "DmgPoint"; a.Position = Vector3.new(0, 0, -3 + i * 1.5); a.Parent = edge end
	local w = Instance.new("WeldConstraint"); w.Part0 = handle; w.Part1 = edge; w.Parent = handle
	local at = Instance.new("StringValue"); at.Name = "AttachTo"; at.Value = "HumanoidRootPart"; at.Parent = blade
	local base = spot()
	local attacker = makeEntity(base, { "Character", "Health", "Status", "Weapon" }, { Weapon = { WeaponName = "AuditBlade", WeaponModel = blade } }, true)
	local target = makeEntity(base + Vector3.new(0, 0, -5), { "Character", "Health", "Status" }, nil, true)
	t.check("arma equipada pelo caminho sem Combat", attacker.HasWeapon(), attacker.HasWeapon())
	local hits = 0
	local owner = { onHit = function(_, hit) if hit.target == target then hits += 1 end end }
	attacker.AddHitboxOwner(owner)
	local started = attacker.StartHitbox(1.0)
	local root = attacker.GetRoot()
	local t0 = os.clock()
	while os.clock() - t0 < 0.9 do
		root.CFrame = CFrame.new(base) * CFrame.Angles(0, (os.clock() - t0) / 0.9 * math.pi * 4, 0)
		task.wait()
	end
	task.wait(0.2)
	t.check("StartHitbox iniciou", started == true, started)
	t.check("2 voltas completas acertam o alvo exatamente 1 vez", hits == 1, hits)
	t.metric("pool", HttpService:JSONEncode(HitboxWrapperMod.GetPoolStats().byType))
	attacker.RemoveHitboxOwner(owner)
	cleanup(attacker); cleanup(target)
end)

test("T30", "Arma real (Martelo): resolução da pasta duplicada e modo Dual", function(t)
	local rig = makeRig(spot())
	local ok, e = pcall(DataManager.Create, rig, COMBAT_FULL)
	t.check("entidade completa criada sem erro", ok, e)
	if not ok then rig:Destroy() return end
	local wc = e:GetComponent("Weapon")
	local data = wc:GetWeaponData()
	local resolved = RS.Assets.Weapons.Schema:FindFirstChild("Martelo")
	t.metric("pasta_resolvida_tem_model", resolved:FindFirstChild("Martelo") ~= nil)
	t.metric("BaseName_carregado", data and data.BaseName)
	t.check("arma equipada", e.HasWeapon(), e.HasWeapon())
	t.metric("modo_atual", wc:GetCurrentMode())
	local p, s = wc.Motors.primary, wc.Motors.secondary
	t.check("modo Dual usa 2 handles diferentes (um por mão)", p and s and p.Part1 ~= s.Part1, (p and s) and ("primary.Part1=" .. p.Part1.Name .. " secondary.Part1=" .. s.Part1.Name) or "motor ausente")
	_G.__AUDIT_T31 = e
end)

test("T31", "WeaponTransform: loadout depois da troca de modo", function(t)
	local e = _G.__AUDIT_T31
	if not e then t.check("entidade do T30 disponível", false, "nil") return end
	local function slots()
		local k = {}
		for slot in pairs(e:GetComponent("Combat").Loadout) do table.insert(k, slot) end
		table.sort(k); return table.concat(k, ",")
	end
	local before = slots()
	local ok1 = SkillHandler.HandleIntent(e.ID, Intents.NewEvent(Intents.Id.Ability3, Intents.Kind.Activate, Intents.Gesture.Press))
	task.wait(0.4)
	local after = slots()
	t.metric("slots_antes", before); t.metric("slots_depois", after)
	t.check("WeaponTransform ativou", ok1 == true, ok1)
	t.metric("modo_depois", e:GetComponent("Weapon"):GetCurrentMode())
	t.check("slot da própria troca (Ability3) continua equipado", e.GetSkillFromSlot(Intents.Id.Ability3) ~= nil, "loadout substituído: " .. after)
	t.check("M1/Dash/Ultimate continuam equipados", e.GetSkillFromSlot(Intents.Id.Primary) ~= nil and e.GetSkillFromSlot(Intents.Id.Dash) ~= nil, after)
	task.wait(0.3)
	local ok2 = SkillHandler.HandleIntent(e.ID, Intents.NewEvent(Intents.Id.Ability3, Intents.Kind.Activate, Intents.Gesture.Press))
	t.check("consegue voltar ao modo anterior", ok2 == true, ok2)
	cleanup(e)
	_G.__AUDIT_T31 = nil
end)

test("T32", "Animação: replay na mesma key e vazamento de conexões", function(t)
	local rig = makeRig(spot())
	local e = DataManager.Create(rig, { "Character", "Animation" })
	local id = "109260837176213"
	local tr1 = e.PlayAnimation(id, "k")
	local tr2 = e.PlayAnimation(id, "k")
	task.wait(0.8)
	t.check("após replay, GetTrack(key) devolve a track nova", e.GetTrack("k") == tr2, e.GetTrack("k") == nil and "nil (apagada pelo Stopped da antiga)" or "outra track")
	local comp = e:GetComponent("Animation")
	local c0 = #comp._connections
	for i = 1, 200 do e.PlayAnimation(id, "bulk" .. (i % 5)) end
	e.StopAllAnimations(0)
	task.wait(0.5)
	t.metric("conexoes_antes", c0)
	t.metric("conexoes_depois_200_plays", #comp._connections)
	t.check("conexões não crescem sem limite", #comp._connections - c0 < 20, #comp._connections - c0)
	local animator = comp.Animator
	local okTracks, n = pcall(function() return #animator:GetPlayingAnimationTracks() end)
	t.metric("tracks_tocando_apos_StopAll", okTracks and n or "erro")
	cleanup(e)
end)

test("T35", "Direção: classifyDirection e eixo lateral", function(t)
	local look = Vector3.new(0, 0, -1)
	local right = CFrame.lookAt(Vector3.zero, look).RightVector
	t.metric("RightVector_real", tostring(right))
	t.check("andar para +X olhando para -Z é 'Right'", Utils.classifyDirection(right, look) == "Right", Utils.classifyDirection(right, look))
	t.check("worldToLocalPlanar(right).X > 0", Utils.worldToLocalPlanar(right, look).X > 0, Utils.worldToLocalPlanar(right, look).X)
	t.check("andar para frente é 'Forward'", Utils.classifyDirection(look, look) == "Forward", Utils.classifyDirection(look, look))
end)

test("T36", "Forças: 350 forças numa entidade e resolução de prioridade Hard", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status", "Movement" })
	local comp = e:GetComponent("Movement")
	for i = 1, 300 do e.AddForce({ Type = "Soft" .. i, Duration = 5, Speed = 1, Direction = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5), RequiresControl = false }) end
	for i = 1, 50 do e.AddForce({ Type = "Hard" .. i, Duration = 5, Speed = 5, Direction = Vector3.xAxis, Hard = true, Priority = i % 5, RequiresControl = false }) end
	local t0 = os.clock()
	for _ = 1, 100 do MC.ProcessEntity(comp, 1 / 60) end
	t.metric("process_ms_por_frame_350_forcas", (os.clock() - t0) * 1000 / 100)
	e.ClearForces()
	e.AddForce({ Type = "Low", Duration = 5, Speed = 10, Direction = Vector3.xAxis, Hard = true, Priority = 5, Axes = { X = true } })
	e.AddForce({ Type = "High", Duration = 5, Speed = 20, Direction = -Vector3.xAxis, Hard = true, Priority = 10, Axes = { X = true } })
	MC.ProcessEntity(comp, 1 / 60)
	local v = comp.MovementWrapper._rig.Velocity.VectorVelocity
	t.check("Hard de maior prioridade vence no eixo X", math.abs(v.X + 20) < 0.01, v.X)
	e.ClearForces()
	e.ApplyStatus(StateTable.States.Root, { Duration = 2 })
	local id = e.AddForce({ Type = "Walky", Duration = 5, Speed = 10, Direction = Vector3.zAxis })
	MC.ProcessEntity(comp, 1 / 60)
	t.check("Root cancela força Soft que exige controle", comp.ActiveForces[id] == nil, "força ainda ativa")
	cleanup(e)
end)

test("T37", "Atributos: fórmula, Override, negativos e cache de default", function(t)
	local e = makeEntity(spot(), { "Character", "Attributes" }, { Attributes = { BaseStats = { Speed = 16, GravityScale = 1 } } })
	e.AddModifier("Speed", "f", E.ModifierType.Flat, 4)
	e.AddModifier("Speed", "a", E.ModifierType.AddPercent, 0.5)
	e.AddModifier("Speed", "m", E.ModifierType.MultPercent, 0.5)
	t.check("((16+4)*1.5)*0.5 = 15", math.abs(e.GetStat("Speed") - 15) < 1e-6, e.GetStat("Speed"))
	e.AddModifier("Speed", "o1", E.ModifierType.Override, 50)
	e.AddModifier("Speed", "o2", E.ModifierType.Override, 0)
	t.metric("dois_overrides_50_e_0", e.GetStat("Speed"))
	t.note("Override resolve sempre pelo MENOR valor (regra fixa, sem prioridade configurável)")
	e.AddModifier("GravityScale", "anti", E.ModifierType.Flat, -2)
	t.check("GravityScale pode ficar negativo (antigravidade)", e.GetStat("GravityScale") < 0, e.GetStat("GravityScale"))
	local a = e.GetStat("NaoExiste", 5)
	local b = e.GetStat("NaoExiste", 9)
	t.check("default passado no GetStat é respeitado a cada chamada", a == 5 and b == 9, ("1ª=%s 2ª=%s"):format(tostring(a), tostring(b)))
	cleanup(e)
end)

test("T38", "Tether isolado (refaz o teste Sprint 8/9 longe do GrandIntegrationDemo)", function(t)
	local base = spot()
	local caster = makeEntity(base, { "Character", "Health", "Movement" })
	local victim = makeEntity(base + Vector3.new(10, 0, 0), { "Character", "Health", "Movement" })
	local forceId = victim.AddForce({ Type = "TestGrab", Duration = 1, Hard = true, IgnoreGravity = true, RequiresControl = false,
		FollowTarget = function() return caster.GetRoot() end, FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
		FollowResponsiveness = 20, FollowMaxSpeed = 100 })
	task.wait(0.5)
	local expected = caster.GetCFrame():PointToWorldSpace(Vector3.new(0, 0, -3))
	local drift = (expected - victim.GetRoot().Position).Magnitude
	t.metric("drift_studs", drift)
	t.check("converge (< 1.5 studs) quando isolado", drift < 1.5, drift)
	t.check("root da vítima com ownership do servidor", victim.GetRoot():GetNetworkOwner() == nil, tostring(victim.GetRoot():GetNetworkOwner()))
	victim.RemoveForce(forceId)
	cleanup(caster); cleanup(victim)
end)

test("T51", "Ownership: NPC criado perto do player", function(t)
	local plr = Players:GetPlayers()[1]
	local char = plr and plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then t.check("player presente", false, "sem personagem") return end
	local e = makeEntity(hrp.Position + Vector3.new(6, 2, 0), { "Character", "Health", "Status", "Movement" })
	task.wait(1.5)
	local owner = e.GetRoot():GetNetworkOwner()
	t.check("NPC sem força Hard fica com ownership do servidor", owner == nil, "owner=" .. tostring(owner))
	e.AddForce({ Type = "Push", Duration = 0.3, Speed = 5, Direction = Vector3.xAxis, RequiresControl = false })
	task.wait(0.2)
	t.metric("owner_apos_forca_soft", tostring(e.GetRoot():GetNetworkOwner()))
	cleanup(e)
end)

test("T53", "AreaEffect: Stop() com entidade dentro da área", function(t)
	local base = spot()
	local e = makeEntity(base, { "Character", "Health", "Status", "Movement", "Attributes" }, { Attributes = { BaseStats = { Speed = 16 } } })
	local zone = AreaEffect.new(function() return CFrame.new(base) end, "Box", Vector3.new(12, 12, 12), 20)
	zone:OnEnter(function(ent) ent.AddModifier("Speed", "AuditZoneSlow", E.ModifierType.MultPercent, 0.5) end)
	zone:OnExit(function(ent) ent.RemoveModifier("Speed", "AuditZoneSlow") end)
	zone:Start()
	task.wait(0.4)
	t.check("OnEnter aplicou o slow", math.abs(e.GetStat("Speed") - 8) < 1e-6, e.GetStat("Speed"))
	zone:Stop()
	task.wait(0.3)
	t.check("Stop() dispara OnExit para quem estava dentro", math.abs(e.GetStat("Speed") - 16) < 1e-6, "slow preso: Speed=" .. e.GetStat("Speed"))
	cleanup(e)
end)

platform:Destroy()
flush(true)
print("[AUDIT] BatchC concluída:", #results, "testes")

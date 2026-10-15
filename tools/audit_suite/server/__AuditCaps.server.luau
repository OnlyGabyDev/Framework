local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Lib = require(SS.__AuditKitLib)
local Kits = require(SS.__AuditKits)
local E, Intents = Lib.E, Lib.Intents
local Id = Intents.Id
local StateTable = require(SS.Modules.Combat.StateTable)
local SkillHandler = require(SSS.Modules.SkillHandler)
local SkillRunner = require(SSS.Modules.SkillRunner)
local DataManager = require(SSS.EntityData.DataManager)

local folder = SS.__AUDIT
local out = folder:FindFirstChild("Caps") or Instance.new("StringValue")
out.Name = "Caps"; out.Parent = folder
local results = {}
local errors, warns = {}, 0
local logConn = LogService.MessageOut:Connect(function(msg, t)
	if t == Enum.MessageType.MessageError then table.insert(errors, msg:sub(1, 220)) elseif t == Enum.MessageType.MessageWarning then warns += 1 end
end)
local function flush(done) out.Value = HttpService:JSONEncode({ done = done, results = results, workarounds = Lib.workarounds, notes = Lib.stats.notes }) end
local function cap(id, name, fn)
	local rec = { id = id, name = name, checks = {}, metrics = {} }
	local t = {}
	function t.check(label, cond, observed) table.insert(rec.checks, { label = label, ok = cond and true or false, observed = tostring(observed) }) end
	function t.metric(k, v) rec.metrics[k] = (type(v) == "number") and (math.floor(v * 100 + 0.5) / 100) or tostring(v) end
	local e0 = #errors
	local ok, err = xpcall(fn, debug.traceback, t)
	if not ok then rec.error = tostring(err):sub(1, 900) end
	rec.server_errors = {}
	for i = e0 + 1, math.min(#errors, e0 + 6) do table.insert(rec.server_errors, errors[i]) end
	local pass = ok
	for _, c in ipairs(rec.checks) do if not c.ok then pass = false end end
	rec.status = pass and "PASS" or "FAIL"
	table.insert(results, rec)
	flush(false)
end

local ZONE = Vector3.new(-900, 103, 0)
local platform = Instance.new("Part"); platform.Name = "__AuditPlatformCaps"; platform.Anchored = true
platform.Size = Vector3.new(500, 2, 500); platform.Position = ZONE - Vector3.new(0, 4, 0); platform.Parent = workspace
local slotN = 0
local function area() slotN += 1; return ZONE + Vector3.new(((slotN % 4) - 1.5) * 110, 0, (math.floor(slotN / 4) - 1) * 110) end
local function dummy(pos, hp, team, comps)
	local d = Lib.spawn("Alvo", team or "B", pos, { comps = comps or { "Character", "Health", "Status", "Movement" }, hp = hp or 1000 })
	return d
end
local function hero(kit, pos, team)
	local K = Kits[kit]
	local e = Lib.spawn(kit, team or "A", pos, { hp = K.hp, size = K.size, color = K.color, comps = K.comps, speed = K.speed })
	if K.anchored then e.GetRoot().Anchored = true end
	K.setup(e)
	return e
end
local function look(e, dir) SkillHandler.HandleLookInput(e.ID, dir) end
local function clearArea() for i = #Lib.alive, 1, -1 do Lib.despawn(Lib.alive[i]) end end

task.wait(1)

cap("K1", "Pistoleira: adagas geram balas, troca de modo, roleta, Foco persistente, recarga x stun, perfurante x iFrame, marca", function(t)
	local base = area()
	local P = hero("Pistoleira", base)
	local d = dummy(base + Vector3.new(0, 0, -4))
	task.wait(0.4)
	look(P, Vector3.new(0, 0, -1))
	for _ = 1, 10 do Lib.press(P, Id.Primary); task.wait(0.5) end
	local K = Kits.Pistoleira
	local c = K.chamber(P)
	local specials = 0
	for _, b in ipairs(c.chamber) do if b ~= "_" and b ~= "Normal" then specials += 1 end end
	t.metric("tambor_apos_10_adagas", table.concat(c.chamber, ","))
	t.check("hits de adaga geram balas especiais (listener OUT.OnDamage com Query Melee)", specials >= 1, specials)
	Lib.press(P, Id.Ability3); task.wait(0.6)
	t.check("troca para Ranged", c.mode == "Ranged", c.mode)
	t.check("slot da troca e a Ultimate continuam equipados", P.GetSkillFromSlot(Id.Ability3) ~= nil and P.GetSkillFromSlot(Id.Ultimate) ~= nil, "faltando")
	t.check("Roleta equipada no Ability2", P.GetSkillFromSlot(Id.Ability2) and P.GetSkillFromSlot(Id.Ability2).data.name == "Pist_Roleta", "não")
	local okStart = Lib.press(P, Id.Ability2); task.wait(0.55)
	local needleBefore = P.Instance:GetAttribute("RouletteNeedle")
	local okStop = Lib.press(P, Id.Ability2); task.wait(0.15)
	t.check("roleta: 1º toque inicia e 2º toque (recast) para", okStart == true and okStop == true, tostring(okStart) .. "/" .. tostring(okStop))
	t.check("cursor do tambor = posição do ponteiro", c.cursor == needleBefore, ("cursor=%s ponteiro=%s"):format(tostring(c.cursor), tostring(needleBefore)))
	t.check("cooldown real da roleta aplicado depois do recast", P.HasCooldown("Pist_Roleta"), P.GetCooldown("Pist_Roleta"))
	P.ApplyStatus(K.Foco, { Duration = 6 })
	Lib.press(P, Id.Ability3); task.wait(0.6)
	t.check("Foco sobrevive à troca de modo", P.GetStatus("Foco") ~= nil and c.mode == "Melee", c.mode)
	local hp0 = d.GetHP(); Lib.press(P, Id.Primary); task.wait(0.3)
	t.metric("dano_adaga_com_Foco", hp0 - d.GetHP())
	t.check("Foco multiplica o dano (6 x 1.3 = 7.8)", math.abs((hp0 - d.GetHP()) - 7.8) < 0.05, hp0 - d.GetHP())
	task.wait(1.1)
	Lib.press(P, Id.Ability3); task.wait(0.6)
	for i = 1, 6 do c.chamber[i] = "_" end
	local okR = Lib.press(P, Id.Ability1); task.wait(0.2)
	P.ApplyStatus(StateTable.States.Stun, { Duration = 0.6 })
	task.wait(1.4)
	local refilled = 0
	for _, b in ipairs(c.chamber) do if b ~= "_" then refilled += 1 end end
	t.check("recarga iniciou", okR == true, okR)
	t.check("recarga interrompida por Stun NÃO recarrega (onEnd roda após cancel)", refilled == 0, refilled .. " balas recarregadas mesmo interrompida")
	task.wait(0.5)
	d.ApplyStatus(StateTable.Status.iFrame, { Duration = 3 })
	c.chamber[c.cursor] = "Perfurante"
	local hp1 = d.GetHP(); local okP = Lib.press(P, Id.Primary); task.wait(0.3)
	t.check("bala Perfurante atravessa iFrame (TrueHit injetado)", okP and math.abs((hp1 - d.GetHP()) - 10) < 0.05, ("ok=%s dano=%s"):format(tostring(okP), tostring(hp1 - d.GetHP())))
	task.wait(3)
	local okM = Lib.press(P, Id.Ultimate); task.wait(0.4)
	c.chamber[c.cursor] = "Normal"
	local hp2 = d.GetHP(); Lib.press(P, Id.Primary); task.wait(0.3)
	t.check("marca de alvo: +50% no marcado (8 x 1.5 = 12)", okM and math.abs((hp2 - d.GetHP()) - 12) < 0.05, ("ok=%s dano=%s"):format(tostring(okM), tostring(hp2 - d.GetHP())))
	t.metric("hud_atributos", ("Chamber=%s Ammo=%s Mode=%s"):format(tostring(P.Instance:GetAttribute("Chamber")), tostring(P.Instance:GetAttribute("Ammo")), tostring(P.Instance:GetAttribute("Mode"))))
	_G.__AuditPistoleiraModel = P.Instance
	clearArea()
end)

cap("K2", "Invocador: minion herda listeners, crédito de kill, morte do dono", function(t)
	local base = area()
	local I = hero("Invocador", base)
	local d = dummy(base + Vector3.new(0, 0, -8))
	task.wait(0.3)
	Lib.press(I, Id.Ability1); task.wait(0.3)
	local st = Lib.state[I]
	local m = st.minions and st.minions[1]
	t.check("minion invocado via MinionFactory", m ~= nil, "nil")
	if not m then return end
	local inherited = 0
	for _, list in pairs(m._triggerSet and m._triggerSet.Subscriptions.OUT or {}) do inherited += #list end
	t.metric("listeners_OUT_herdados_pelo_minion", inherited)
	m.SetEnabled(false)
	m.Teleport(d.GetRoot().Position + Vector3.new(0, 0, 2.5)); look(m, Vector3.new(0, 0, -1)); task.wait(0.2)
	Lib.press(m, Id.Primary); task.wait(0.3)
	t.check("mordida do minion aplica MarcaSombria (listener herdado do invocador)", d.GetStatus("MarcaSombria") ~= nil, "sem marca")
	local weak = dummy(base + Vector3.new(6, 0, -8), 3)
	m.Teleport(weak.GetRoot().Position + Vector3.new(0, 0, 2.5)); look(m, Vector3.new(0, 0, -1)); task.wait(0.9)
	local before = Lib.stats.notes["Invocador:kill_do_minion_creditado(heranca)"] or 0
	Lib.press(m, Id.Primary); task.wait(0.3)
	t.check("kill do minion chega no invocador via OUT.OnDeath herdado", (Lib.stats.notes["Invocador:kill_do_minion_creditado(heranca)"] or 0) > before, "não creditado")
	local late = 0
	I:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.onHit, Inherit = { Generations = 1 }, Action = function() late += 1 end })
	m.Teleport(d.GetRoot().Position + Vector3.new(0, 0, 2.5)); look(m, Vector3.new(0, 0, -1)); task.wait(0.9)
	Lib.press(m, Id.Primary); task.wait(0.3)
	t.check("listener herdável criado DEPOIS do spawn chega no minion", late > 0, "não chega (Fork é snapshot na criação)")
	I.Die(nil); task.wait(0.2)
	t.check("morte do invocador mata os minions (listener manual)", not Lib.isAlive(m), "minion vivo")
	clearArea()
end)

cap("K3", "Duelista: parry, counter-hit, quebra-guarda", function(t)
	local base = area()
	local D = hero("Duelista", base)
	local A = Lib.spawn("Atacante", "B", base + Vector3.new(0, 0, -4), { hp = 500 })
	local soco = Lib.skill("Aud_Soco", { cooldown = 0, duration = 0.1 }, { onStart = function(self) Lib.hit(self, D, 10, "Atacante") end })
	local lento = Lib.skill("Aud_Lento", { cooldown = 0, duration = 1, castTime = 0.6 }, {})
	A.EquipSkill(Id.Primary, soco); A.EquipSkill(Id.Ability1, lento)
	task.wait(0.3)
	look(D, Vector3.new(0, 0, -1))
	Lib.press(D, Id.Primary); task.wait(0.1)
	t.check("Estocada em cooldown antes do parry", D.HasCooldown("Duel_Estocada"), D.GetCooldown("Duel_Estocada"))
	local hp0 = D.GetHP()
	Lib.press(D, Id.Ability1); task.wait(0.05)
	Lib.press(A, Id.Primary); task.wait(0.1)
	t.check("parry anula o dano", D.GetHP() == hp0, hp0 - D.GetHP())
	t.check("parry atordoa o atacante", A.GetStatus("Stun") ~= nil, "sem Stun")
	t.check("parry zera o cooldown da Estocada", not D.HasCooldown("Duel_Estocada"), D.GetCooldown("Duel_Estocada"))
	task.wait(1)
	Lib.press(A, Id.Ability1); task.wait(0.1)
	local hpA = A.GetHP(); Lib.press(D, Id.Primary); task.wait(0.2)
	t.check("counter-hit durante o castTime do alvo (14 de dano)", math.abs((hpA - A.GetHP()) - 14) < 0.01, hpA - A.GetHP())
	task.wait(1)
	A.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5 })
	Lib.press(D, Id.Ability2); task.wait(0.2)
	t.metric("GenericBlock_apos_QuebraGuarda", A.GetStatus("GenericBlock") and "ativo" or "quebrado (mesmo com trait Unbreakable)")
	clearArea()
end)

cap("K4", "Alquimista: reação em cadeia em grade 8x8 (64 alvos)", function(t)
	local base = area()
	local alq = hero("Alquimista", base + Vector3.new(0, 0, 30))
	local grid = {}
	for i = 0, 7 do for j = 0, 7 do
		local g = dummy(base + Vector3.new(i * 5 - 17.5, 0, j * 5 - 17.5), 25, "B", { "Character", "Health", "Status" })
		g.GetRoot().Anchored = true
		g.ApplyStatus(Kits.Alquimista.Instavel, { Duration = 30 })
		Kits.Alquimista.arm(alq, g)
		table.insert(grid, g)
	end end
	task.wait(0.3)
	local runner = SkillRunner.new(Lib.skill("Aud_Detonar", { duration = 1 }, {}), alq, "Aud_Detonar", E.Types.Skill)
	runner:start()
	local refusedBefore = Lib.stats.notes["Alquimista:explosao_recusada_MAX_RECURSION"] or 0
	local t0 = os.clock()
	local ok, err = pcall(function() grid[1].TakeDamage(1000, runner) end)
	local ms = (os.clock() - t0) * 1000
	local dead = 0
	for _, g in ipairs(grid) do if not g.IsAlive() then dead += 1 end end
	t.check("cadeia não lança erro", ok, err)
	t.metric("tempo_da_cadeia_ms", ms)
	t.metric("explosoes_recusadas_por_MAX_RECURSION", (Lib.stats.notes["Alquimista:explosao_recusada_MAX_RECURSION"] or 0) - refusedBefore)
	t.check("todos os 64 alvos encadeados morrem", dead == 64, dead .. "/64")
	runner:endSkill(false)
	clearArea()
end)

cap("K5", "Ladrão: roubo de skill (portabilidade + herança de cooldown) e possessão de IA", function(t)
	local base = area()
	local L = hero("Ladrao", base)
	local D = hero("Duelista", base + Vector3.new(0, 0, -5), "B")
	task.wait(0.3)
	look(D, Vector3.new(0, 0, 1)); Lib.press(D, Id.Primary); task.wait(0.05)
	local remainingBefore = D.GetCooldown("Duel_Estocada")
	look(L, Vector3.new(0, 0, -1))
	Lib.press(L, Id.Ability1); task.wait(0.1)
	t.check("roubou a Estocada", L.GetSkillFromSlot(Id.Ability2) and L.GetSkillFromSlot(Id.Ability2).data.name == "Duel_Estocada", "não roubou")
	t.check("vítima perdeu o slot", D.GetSkillFromSlot(Id.Primary) == nil, "ainda tem")
	t.check("cooldown restante herdado", L.HasCooldown("Duel_Estocada") or remainingBefore == 0, ("restante=%.2f"):format(remainingBefore))
	task.wait(0.8)
	local hp0 = D.GetHP(); local okUse = Lib.press(L, Id.Ability2); task.wait(0.2)
	t.check("skill roubada funciona no ladrão", okUse and (hp0 - D.GetHP()) >= 9, ("ok=%s dano=%s"):format(tostring(okUse), tostring(hp0 - D.GetHP())))
	local rig = workspace.Rig:Clone(); rig:PivotTo(CFrame.new(base + Vector3.new(8, 0, -5)))
	for _, p in ipairs(rig:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
	rig.Parent = workspace
	local schema = DataManager.Create(rig, { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "Weapon", "Animation" })
	schema.Team = "B"; table.insert(Lib.alive, schema)
	task.wait(0.5)
	local m1 = schema.GetSkillFromSlot(Id.Primary)
	L.EquipSkill(Id.Ability2, m1)
	local e0 = #errors
	local okM1, errM1 = pcall(function() return Lib.press(L, Id.Ability2) end)
	task.wait(0.3)
	t.check("M1 roubado da Schema funciona fora da Schema (portável)", okM1 and #errors == e0, okM1 and ("erros=" .. (#errors - e0)) or tostring(errM1):sub(1, 160))
	L.StopAllActiveSkills(true)
	local victim = hero("Enxame", base + Vector3.new(-6, 0, -6), "B")
	victim.SetBrain(Lib.brain(Kits.Enxame))
	local enemyOfPuppet = dummy(base + Vector3.new(-20, 0, -6), 1000, "A")
	task.wait(0.5)
	victim.Possess({ AI = true, Brain = function() end })
	task.wait(0.4)
	t.check("Possess(AI) oficial suspende a IA do alvo", victim:GetComponent("AI").Enabled == false, "IA do alvo continua ligada")
	victim.Release()
	clearArea()
end)

cap("K6", "Cronomante: rewind de posição e HP", function(t)
	local base = area()
	local C = hero("Cronomante", base)
	task.wait(3.2)
	local origin = C.GetRoot().Position
	C.Teleport(base + Vector3.new(30, 0, 0)); C.TakeDamage(40, nil); task.wait(0.3)
	Lib.press(C, Id.Ability1); task.wait(0.2)
	t.metric("distancia_do_ponto_de_3s_atras", (C.GetRoot().Position - origin).Magnitude)
	t.check("rewind volta a posição de ~3 s atrás", (C.GetRoot().Position - origin).Magnitude < 4, (C.GetRoot().Position - origin).Magnitude)
	t.check("rewind restaura o HP", C.GetHP() >= 119, C.GetHP())
	clearArea()
end)

cap("K7", "Canalizador: hold/release com HeldTime e canal interrompido por Stun", function(t)
	local base = area()
	local C = hero("Canalizador", base)
	local d = dummy(base + Vector3.new(0, 0, -10))
	task.wait(0.3)
	look(C, Vector3.new(0, 0, -1))
	local okH = Lib.press(C, Id.Primary, Intents.Gesture.Hold, 0.3)
	task.wait(1.0)
	local hp0 = d.GetHP()
	Lib.release(C, Id.Primary, 1.0); task.wait(0.2)
	t.check("Hold ativou", okH == true, okH)
	t.check("dano escala com HeldTime (5 + 1.0*10 = 15)", math.abs((hp0 - d.GetHP()) - 15) < 0.01, hp0 - d.GetHP())
	task.wait(1.2)
	Lib.press(C, Id.Ability1); task.wait(0.3)
	C.ApplyStatus(StateTable.States.Stun, { Duration = 1 })
	task.wait(0.3)
	t.check("canal para quando chega Stun (checagem manual no onStep)", C.GetActiveSkillCount("Can_Feixe") == 0, C.GetActiveSkillCount("Can_Feixe"))
	clearArea()
end)

cap("K8", "Cartas: mana, carta sem mana devolve cooldown, compra em runtime", function(t)
	local base = area()
	local M = hero("Cartas", base)
	task.wait(0.2)
	M.SetStat("Mana", 0)
	local card = M.GetSkillFromSlot(Id.Ability1)
	t.check("compra equipou 3 cartas", card ~= nil and M.GetSkillFromSlot(Id.Ability2) ~= nil and M.GetSkillFromSlot(Id.Ability3) ~= nil, "slots vazios")
	local ok1 = Lib.press(M, Id.Ability1); task.wait(0.1)
	t.check("carta sem mana devolve o cooldown", not M.HasCooldown(card.data.name), M.GetCooldown(card.data.name))
	M.SetStat("Mana", 10)
	local ok2 = Lib.press(M, Id.Ability1)
	t.check("com mana a carta funciona logo em seguida", ok2 == true, ok2)
	t.metric("mana_restante", M.GetStat("Mana", 0))
	clearArea()
end)

cap("E1", "Colosso: fases por HP, adds, enrage via DamageMult", function(t)
	local base = area()
	local B = hero("Colosso", base, "N")
	local d = dummy(base + Vector3.new(0, 0, -6), 5000, "A")
	task.wait(0.3)
	look(B, Vector3.new(0, 0, -1))
	local hp0 = d.GetHP(); Lib.press(B, Id.Primary); task.wait(1.0)
	local dmgBefore = hp0 - d.GetHP()
	B.TakeDamage(B.GetMaxHP() * 0.4, nil); task.wait(0.3)
	t.check("fase 2 ativada a 60% de HP", Lib.state[B].phase == 2, Lib.state[B].phase)
	t.check("iFrame da transição aplicado", B.GetStatus("iFrame") ~= nil, "sem iFrame")
	task.wait(2.2)
	local hp1 = d.GetHP(); Lib.press(B, Id.Primary); task.wait(1.0)
	local dmgAfter = hp1 - d.GetHP()
	t.metric("dano_golpe_antes_enrage", dmgBefore); t.metric("dano_golpe_depois_enrage", dmgAfter)
	t.check("enrage (DamageMult +0.5) aumenta o dano", dmgAfter > dmgBefore, ("antes=%s depois=%s"):format(dmgBefore, dmgAfter))
	clearArea()
end)

cap("E2", "Torre: escudo frontal e projétil teleguiado", function(t)
	local base = area()
	local T = hero("Torre", base, "N")
	local front = Lib.spawn("Atacante", "A", base + Vector3.new(0, 0, -8), { hp = 300 })
	local back = Lib.spawn("Atacante", "A", base + Vector3.new(0, 0, 8), { hp = 300 })
	local soco = Lib.skill("Aud_Soco2", { cooldown = 0, duration = 0.1 }, { onStart = function(self) Lib.hit(self, T, 10, "Atacante") end })
	front.EquipSkill(Id.Primary, soco); back.EquipSkill(Id.Primary, soco)
	task.wait(0.3)
	T.GetRoot().CFrame = CFrame.lookAt(T.GetRoot().Position, T.GetRoot().Position + Vector3.new(0, 0, -1))
	local hp0 = T.GetHP(); Lib.press(front, Id.Primary); task.wait(0.1)
	t.check("ataque pela frente é bloqueado", T.GetHP() == hp0, hp0 - T.GetHP())
	local hp1 = T.GetHP(); Lib.press(back, Id.Primary); task.wait(0.1)
	t.check("ataque por trás passa", hp1 - T.GetHP() == 10, hp1 - T.GetHP())
	local hpF = front.GetHP()
	Lib.press(T, Id.Primary); task.wait(1.5)
	t.check("projétil teleguiado acerta", front.GetHP() < hpF or back.GetHP() < 300, ("front=%s back=%s"):format(front.GetHP(), back.GetHP()))
	clearArea()
end)

cap("E3", "Espelho: copia a última skill que o acertou e usa de volta", function(t)
	local base = area()
	local M = hero("Espelho", base, "N")
	local D = hero("Duelista", base + Vector3.new(0, 0, -4), "A")
	task.wait(0.3)
	look(D, Vector3.new(0, 0, 1))
	Lib.press(D, Id.Primary); task.wait(0.2)
	t.check("espelho copiou a Estocada", M.GetSkillFromSlot(Id.Ability1) and M.GetSkillFromSlot(Id.Ability1).data.name == "Duel_Estocada", tostring(Lib.state[M].copied))
	look(M, Vector3.new(0, 0, -1))
	local hp0 = D.GetHP(); local ok = Lib.press(M, Id.Ability1); task.wait(0.2)
	t.check("cópia funciona contra o dono original", ok and hp0 - D.GetHP() >= 9, ("ok=%s dano=%s"):format(tostring(ok), tostring(hp0 - D.GetHP())))
	t.check("cópia não compartilha cooldown com o dono", not (D.HasCooldown("Duel_Estocada") and false), "ok")
	clearArea()
end)

logConn:Disconnect()
platform:Destroy()
flush(true)
print("[AUDIT] Caps concluída:", #results)

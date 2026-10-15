local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DataManager = require(SSS.EntityData.DataManager)
local EntityCore = require(SSS.EntityData.EntityCore)
local StateTable = require(SS.Modules.Combat.StateTable)
local E = StateTable.Enum
local SkillRunner = require(SSS.Modules.SkillRunner)
local SkillHandler = require(SSS.Modules.SkillHandler)

local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"; folder.Parent = SS
local out = folder:FindFirstChild("BatchA") or Instance.new("StringValue")
out.Name = "BatchA"; out.Parent = folder

local results = {}
local function flush(done) out.Value = HttpService:JSONEncode({ done = done, results = results }) end

local function test(id, name, fn)
	local rec = { id = id, name = name, checks = {}, metrics = {}, notes = {} }
	local t = {}
	function t.check(label, cond, observed)
		table.insert(rec.checks, { label = label, ok = cond and true or false, observed = tostring(observed) })
	end
	function t.metric(k, v)
		rec.metrics[k] = (type(v) == "number") and (math.floor(v * 1000 + 0.5) / 1000) or tostring(v)
	end
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

local ZONE = Vector3.new(800, 103, 800)
local platform = Instance.new("Part")
platform.Name = "__AuditPlatformA"; platform.Anchored = true
platform.Size = Vector3.new(400, 2, 400); platform.Position = ZONE - Vector3.new(0, 4, 0)
platform.Parent = workspace

local function makeModel(pos, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = opts.name or "__AuditDummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = opts.size or Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(pos)
	root.Anchored = opts.anchored or false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	return model
end

local function makeEntity(pos, comps, configs, opts)
	local model = makeModel(pos, opts)
	return DataManager.Create(model, comps, configs), model
end

local function cleanup(e)
	if not e then return end
	local inst = e.Instance
	if inst then pcall(DataManager.Remove, inst) end
	if inst then inst:Destroy() end
end

local function chainDepth()
	local n = 0
	while StateTable.TryEnterChain() do
		n += 1
		if n > 500 then break end
	end
	for _ = 1, n do StateTable.ExitChain() end
	return E.MAX_RECURSION - n
end
local function restoreChain(k) for _ = 1, math.max(0, k) do StateTable.ExitChain() end end

local function silentStatus(name, extra, callbacks)
	local data = { name = name, category = E.Categories.Debuff, duration = 5 }
	for k, v in pairs(extra or {}) do data[k] = v end
	return { data = data, callbacks = callbacks or {} }
end

local function keysOf(t) local k = {} for n in pairs(t) do table.insert(k, tostring(n)) end table.sort(k) return table.concat(k, ",") end

local P = 0
local function spot() P += 1; return ZONE + Vector3.new(((P % 25) - 12) * 8, 0, (math.floor(P / 25) - 6) * 8) end

task.wait(1)

------------------------------------------------------------------ T01
test("T01", "ECS: criar e destruir 300 entidades (Character+Health+Status+Movement+Attributes)", function(t)
	local N = 300
	local mem0 = gcinfo()
	local t0 = os.clock()
	local list = {}
	for i = 1, N do
		local pos = ZONE + Vector3.new(((i % 20) - 10) * 6, 0, (math.floor(i / 20) - 8) * 6 + 150)
		list[i] = (makeEntity(pos, { "Character", "Health", "Status", "Movement", "Attributes" }))
		if i % 30 == 0 then task.wait() end
	end
	local createMs = (os.clock() - t0) * 1000
	t.metric("create_ms_total_incl_yields", createMs)
	local MC = require(SSS.Modules.Physics.MovementController)
	local t1 = os.clock()
	for _, e in ipairs(list) do MC.ProcessEntity(e:GetComponent("Movement"), 1 / 60) end
	t.metric("movement_process_us_per_entity", (os.clock() - t1) * 1e6 / N)
	t.metric("mem_kb_delta_after_create", gcinfo() - mem0)
	local ids = {}
	for _, e in ipairs(list) do table.insert(ids, e.ID) end
	local t2 = os.clock()
	for i, e in ipairs(list) do
		cleanup(e)
		if i % 30 == 0 then task.wait() end
	end
	t.metric("destroy_ms_total_incl_yields", (os.clock() - t2) * 1000)
	task.wait(1)
	local still = 0
	for i = 1, N, 15 do if DataManager.Get(ids[i]) then still += 1 end end
	t.check("DataManager.Get retorna nil após Remove (amostra de 20)", still == 0, still)
	local inactive = 0
	for _, e in ipairs(list) do if e.Active == false then inactive += 1 end end
	t.check("todas as entidades marcadas Active=false", inactive == N, inactive)
	t.metric("mem_kb_delta_after_destroy_1s", gcinfo() - mem0)
end)

------------------------------------------------------------------ T02
test("T02", "ECS: API exposta continua viva depois de RemoveComponent", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local d0 = chainDepth()
	e:RemoveComponent("Health")
	t.check("HasComponent(Health) = false", not e:HasComponent("Health"), e:HasComponent("Health"))
	local stale = rawget(e, "TakeDamage")
	t.check("closure TakeDamage removida da entidade (deveria cair no stub)", stale == nil, stale and "closure antiga presente" or "nil")
	local ok, err = pcall(function() return e.TakeDamage(10) end)
	t.check("e.TakeDamage após RemoveComponent não lança erro", ok, err)
	local d1 = chainDepth()
	t.check("profundidade de cadeia (MAX_RECURSION) não vaza", d1 == d0, ("antes=%d depois=%d"):format(d0, d1))
	restoreChain(d1 - d0)
	cleanup(e)
end)

------------------------------------------------------------------ T03
test("T03", "ECS: colisões de nome entre ExposeAPI e com métodos do EntityCore", function(t)
	local seen, dups, shadow, total = {}, {}, {}, 0
	for _, m in ipairs(SSS.EntityData.Components:GetChildren()) do
		if m:IsA("ModuleScript") then
			local mod = require(m)
			for name in pairs(mod.ExposeAPI or {}) do
				total += 1
				if seen[name] then table.insert(dups, name .. " (" .. seen[name] .. " x " .. m.Name .. ")") else seen[name] = m.Name end
				if rawget(EntityCore, name) ~= nil then table.insert(shadow, name .. " <- " .. m.Name) end
			end
		end
	end
	t.metric("metodos_expostos", total)
	t.check("nenhum método exposto por 2 componentes", #dups == 0, table.concat(dups, "; "))
	t.check("nenhum método de componente sobrescreve método do EntityCore", #shadow == 0, table.concat(shadow, "; "))
end)

------------------------------------------------------------------ T04
test("T04", "ECS: IsNPC() em NPC criado pelo DataManager", function(t)
	local e = makeEntity(spot(), { "Character" })
	t.check("IsNPC() == true", e:IsNPC(), "Type=" .. tostring(e.Type) .. " IsNPC=" .. tostring(e:IsNPC()))
	cleanup(e)
end)

------------------------------------------------------------------ T05
test("T05", "ECS: Movement sem Character (dependência não declarada)", function(t)
	local model = makeModel(spot())
	local ok, res = pcall(DataManager.Create, model, { "Movement" })
	t.check("DataManager.Create({Movement}) não lança erro", ok, res)
	local id = model:GetAttribute("EntityID")
	t.check("falha não deixa entidade meio-registrada", ok or id == nil, "EntityID=" .. tostring(id) .. " ficou no model")
	pcall(DataManager.Remove, model)
	model:Destroy()
end)

------------------------------------------------------------------ T06
test("T06", "ECS: EventKey dos componentes registrado em EntityCore.Events", function(t)
	t.check("EntityCore.Events.onDamage definido (Health exporta EventKey)", EntityCore.Events.onDamage ~= nil, "Events={" .. keysOf(EntityCore.Events) .. "}")
end)

------------------------------------------------------------------ T07
test("T07", "Status: 1000 aplicações de status stackOnSelf (maxStacks 10)", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local S = silentStatus("AuditStackSelf", { stackOnSelf = true, maxStacks = 10, traits = { E.Traits.Stackable } })
	local t0 = os.clock()
	for _ = 1, 1000 do e.ApplyStatus(S) end
	t.metric("apply_us_each", (os.clock() - t0) * 1e6 / 1000)
	t.check("contador = maxStacks (10)", e.GetStatusCounter("AuditStackSelf") == 10, e.GetStatusCounter("AuditStackSelf"))
	local entry = e:GetComponent("Status").Effects.Status.AuditStackSelf
	t.check("uma única entrada/runner", entry ~= nil and entry.runner ~= nil and entry[1] == nil, entry and "ok" or "nil")
	t.check("campo entry.counter coerente com runner.skill.counter", entry and entry.counter == entry.runner.skill.counter, entry and ("entry.counter=" .. tostring(entry.counter) .. " runner=" .. tostring(entry.runner.skill.counter)))
	cleanup(e)
end)

------------------------------------------------------------------ T08
test("T08", "Status: RemoveStatus em stack de instâncias múltiplas (10 runners)", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local steps, ends = {}, 0
	local S = silentStatus("AuditMulti", { maxStacks = 20, traits = { E.Traits.Stackable } }, {
		onStep = function(self) steps[self.Runner] = (steps[self.Runner] or 0) + 1 end,
		onCancel = function() ends += 1 end,
	})
	for _ = 1, 10 do e.ApplyStatus(S) end
	t.check("10 instâncias aplicadas", e.GetStatusCounter("AuditMulti") == 10, e.GetStatusCounter("AuditMulti"))
	task.wait(0.2)
	e.RemoveStatus("AuditMulti")
	t.check("GetStatus nil após RemoveStatus", e.GetStatus("AuditMulti") == nil, "ainda listado")
	t.metric("onCancel_chamados", ends)
	local snap = {}
	for r, c in pairs(steps) do snap[r] = c end
	task.wait(0.6)
	local alive = 0
	for r, c in pairs(steps) do if c > (snap[r] or 0) then alive += 1 end end
	t.check("nenhum runner continua rodando (órfão) após RemoveStatus", alive == 0, alive .. " de 10 ainda executam onStep")
	cleanup(e)
end)

------------------------------------------------------------------ T09
test("T09", "Status: RemoveStatusByID numa stack de 5 instâncias", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local S = silentStatus("AuditMultiID", { maxStacks = 20, traits = { E.Traits.Stackable } })
	for i = 1, 5 do e.ApplyStatus(S, { ID = "ID" .. i }) end
	local removed = e.RemoveStatusByID("ID2")
	local remaining = {}
	for _, entry in ipairs(e.GetStatus("AuditMultiID") or {}) do table.insert(remaining, tostring(entry.ID)) end
	t.check("RemoveStatusByID retorna true", removed == true, removed)
	t.check("remove exatamente 1 instância (sobram 4)", #remaining == 4, "restaram [" .. table.concat(remaining, ",") .. "]")
	cleanup(e)
end)

------------------------------------------------------------------ T10
test("T10", "Runner: SkillRunner:ApplyStatus com opts", function(t)
	local caster = makeEntity(spot(), { "Character", "Health", "Status" })
	local target = makeEntity(spot(), { "Character", "Health", "Status" })
	local runner = SkillRunner.new({ data = { name = "AuditCaster", duration = 2 }, callbacks = {} }, caster, "AuditCaster", E.Types.Skill)
	runner:start()
	local id = runner:ApplyStatus(silentStatus("AuditViaRunner"), { Target = target, Duration = 1, ID = "WantedID" })
	t.check("retorna ID do tipo string", type(id) == "string", type(id))
	local entry = (target.GetStatus("AuditViaRunner") or {})[1]
	t.check("opts.ID respeitado", entry ~= nil and entry.ID == "WantedID", entry and tostring(entry.ID))
	t.check("RemoveStatusByID('WantedID') funciona", target.RemoveStatusByID("WantedID") == true, "false")
	runner:endSkill(false)
	cleanup(caster); cleanup(target)
end)

------------------------------------------------------------------ T11
test("T11", "Status: StatusShield (ShieldsFrom={DOT}) contra status DOT", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	e.ApplyStatus(StateTable.Status.StatusShield, { Duration = 3 })
	local id = e.ApplyStatus(silentStatus("AuditDOT", { traits = { E.Traits.DOT } }))
	t.check("status com trait DOT é bloqueado pelo StatusShield", id == nil, "aplicado, id=" .. tostring(id))
	cleanup(e)
end)

------------------------------------------------------------------ T12
test("T12", "Dano: GenericBlock(Unbreakable) x BlockBreak e TrueBlock x TrueHit", function(t)
	local attacker = makeEntity(spot(), { "Character", "Health", "Status", "Movement", "Attributes", "Combat" })
	local target = makeEntity(spot(), { "Character", "Health", "Status" })
	target.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "Block1" })
	local breaker = SkillRunner.new({ data = { name = "AuditBreaker", duration = 2, traits = { E.Traits.BlockBreak } }, callbacks = {} }, attacker, "AuditBreaker", E.Types.Skill)
	breaker:start()
	local hp0 = target.GetHP()
	breaker:Damage(target, 10)
	t.check("GenericBlock com trait Unbreakable sobrevive a BlockBreak", target.GetStatus("GenericBlock") ~= nil, "block quebrado")
	t.metric("hp_perdido_com_GenericBlock_ativo", hp0 - target.GetHP())
	breaker:endSkill(false)

	local target2 = makeEntity(spot(), { "Character", "Health", "Status" })
	target2.ApplyStatus({ data = { name = "AuditTrueBlock", category = E.Categories.Buff, tags = { [E.Tags.block] = true }, traits = { E.Traits.TrueBlock } },
		callbacks = { onTrigger = function() return 0 end } }, { Duration = 5 })
	local trueHit = SkillRunner.new({ data = { name = "AuditTrueHit", duration = 2, traits = { E.Traits.TrueHit } }, callbacks = {} }, attacker, "AuditTrueHit", E.Types.Skill)
	trueHit:start()
	local hp1 = target2.GetHP()
	trueHit:Damage(target2, 10)
	t.check("TrueBlock (onTrigger devolve 0) não é ignorado por TrueHit", hp1 - target2.GetHP() == 0, "perdeu " .. (hp1 - target2.GetHP()) .. " HP")
	trueHit:endSkill(false)
	cleanup(attacker); cleanup(target); cleanup(target2)
end)

------------------------------------------------------------------ T13
test("T13", "Dano: iFrame bloqueia e TrueHit atravessa", function(t)
	local attacker = makeEntity(spot(), { "Character", "Health", "Status", "Movement", "Attributes", "Combat" })
	local target = makeEntity(spot(), { "Character", "Health", "Status" })
	target.ApplyStatus(StateTable.Status.iFrame, { Duration = 2 })
	local ok, reason = target.TakeDamage(10, nil)
	t.check("iFrame bloqueia dano comum", ok == false and reason == "iFrame", tostring(ok) .. "/" .. tostring(reason))
	local r = SkillRunner.new({ data = { name = "AuditTH", duration = 2, traits = { E.Traits.TrueHit } }, callbacks = {} }, attacker, "AuditTH", E.Types.Skill)
	r:start()
	local ok2 = target.TakeDamage(10, r)
	t.check("TrueHit atravessa iFrame", ok2 == true, ok2)
	r:endSkill(false)
	cleanup(attacker); cleanup(target)
end)

------------------------------------------------------------------ T14
test("T14", "Robustez: erro dentro da cadeia vaza o contador global MAX_RECURSION", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local d0 = chainDepth()
	for _ = 1, 10 do pcall(e.ApplyStatus, {}) end
	local d1 = chainDepth()
	t.check("ApplyStatus malformado não vaza profundidade", d1 == d0, ("vazou %d de 10"):format(d1 - d0))
	local leakRest = E.MAX_RECURSION - d1
	for _ = 1, leakRest do pcall(e.ApplyStatus, {}) end
	local healthy = makeEntity(spot(), { "Character", "Health" })
	local ok, reason = healthy.TakeDamage(5, nil)
	t.check("dano em entidade saudável continua funcionando depois dos vazamentos", ok == true, tostring(ok) .. "/" .. tostring(reason))
	local hasStatus = makeEntity(spot(), { "Character", "Health", "Status" })
	local sid = hasStatus.ApplyStatus(silentStatus("AuditAfterLeak"))
	t.check("ApplyStatus continua funcionando depois dos vazamentos", sid ~= nil, tostring(sid))
	restoreChain(chainDepth() - d0)
	t.metric("profundidade_apos_restaurar", chainDepth())

	local blk = { data = { name = "AuditBadBlock", category = E.Categories.Buff, tags = { [E.Tags.block] = true } },
		callbacks = { onTrigger = function() error("onTrigger quebrado") end } }
	e.ApplyStatus(blk, { Duration = 3 })
	local d2 = chainDepth()
	for _ = 1, 5 do pcall(e.TakeDamage, 1, nil) end
	local d3 = chainDepth()
	t.check("erro em onTrigger de block não vaza profundidade", d3 == d2, ("vazou %d de 5 hits"):format(d3 - d2))
	restoreChain(d3 - d2)
	cleanup(e); cleanup(healthy); cleanup(hasStatus)
end)

------------------------------------------------------------------ T15
test("T15", "Recursão: ping-pong síncrono de reflexo entre 2 entidades", function(t)
	local A = makeEntity(spot(), { "Character", "Health", "Status" }, { Health = { MaxHP = 1e9 } })
	local B = makeEntity(spot(), { "Character", "Health", "Status" }, { Health = { MaxHP = 1e9 } })
	local reflects = 0
	local Reflect = { data = { name = "AuditReflect", category = E.Categories.Buff, tags = { [E.Tags.block] = true } },
		callbacks = { onTrigger = function(self, context)
			reflects += 1
			local attacker = context.sourceEntity
			if attacker and attacker ~= self.Entity then attacker.TakeDamage(1, self.Runner) end
			return context.damage
		end } }
	A.ApplyStatus(Reflect, { Duration = 5 })
	B.ApplyStatus(Reflect, { Duration = 5 })
	local d0 = chainDepth()
	local rB = SkillRunner.new({ data = { name = "AuditPoke", duration = 2 }, callbacks = {} }, B, "AuditPoke", E.Types.Skill)
	rB:start()
	local ok, err = pcall(function() return A.TakeDamage(1, rB) end)
	t.check("cadeia síncrona infinita não estoura a pilha", ok, err)
	t.metric("reflexos_ate_parar", reflects)
	t.check("MAX_RECURSION corta a cadeia perto de 50", reflects > 0 and reflects <= E.MAX_RECURSION + 2, reflects)
	t.check("profundidade volta ao valor inicial", chainDepth() == d0, chainDepth())
	rB:endSkill(false)
	cleanup(A); cleanup(B)
end)

------------------------------------------------------------------ T44
test("T44", "Dano: efeitos on-hit em hit 100% bloqueado e em hit de 0 de dano", function(t)
	local attacker = makeEntity(spot(), { "Character", "Health", "Status", "Movement", "Attributes", "Combat" })
	local target = makeEntity(spot(), { "Character", "Health", "Status" })
	target.ApplyStatus({ data = { name = "AuditFullBlock", category = E.Categories.Buff, tags = { [E.Tags.block] = true } },
		callbacks = { onTrigger = function() return 0 end } }, { Duration = 5 })
	local Debuff = silentStatus("AuditOnHitDebuff", { duration = 2 })
	local r = SkillRunner.new({ data = { name = "AuditEffectHit", duration = 2, effects = { Debuff } }, callbacks = {} }, attacker, "AuditEffectHit", E.Types.Skill)
	r:start()
	local hp0 = target.GetHP()
	r:Damage(target, 10)
	t.metric("hp_perdido_no_hit_bloqueado", hp0 - target.GetHP())
	t.check("hit totalmente bloqueado NÃO aplica efeitos on-hit", target.GetStatus("AuditOnHitDebuff") == nil, "debuff aplicado mesmo com dano 0")
	local target2 = makeEntity(spot(), { "Character", "Health", "Status" })
	r:Damage(target2, 0)
	t.check("hit de 0 de dano consegue aplicar efeito (ex.: slow puro)", target2.GetStatus("AuditOnHitDebuff") ~= nil, "efeito descartado (TakeDamage retorna cedo com damage<=0)")
	r:endSkill(false)
	cleanup(attacker); cleanup(target); cleanup(target2)
end)

------------------------------------------------------------------ T45
test("T45", "Dano: ApplyDamage em entidade sem Health", function(t)
	local attacker = makeEntity(spot(), { "Character", "Health", "Status", "Movement", "Attributes", "Combat" })
	local wall = makeEntity(spot(), { "Character" })
	local r = SkillRunner.new({ data = { name = "AuditWallHit", duration = 1 }, callbacks = {} }, attacker, "AuditWallHit", E.Types.Skill)
	r:start()
	local ok, a, b = pcall(function() return r:Damage(wall, 5) end)
	t.check("não lança erro", ok, a)
	t.check("retorna false explícito (não nil)", ok and a == false, tostring(a))
	r:endSkill(false)
	cleanup(attacker); cleanup(wall)
end)

------------------------------------------------------------------ T46
test("T46", "Status: aplicar status em entidade morta", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	e.TakeDamage(1e6, nil)
	t.check("entidade morta", e.IsAlive() == false, e.IsAlive())
	local id = e.ApplyStatus(silentStatus("AuditOnCorpse"))
	t.check("ApplyStatus em entidade morta é recusado", id == nil, "aplicado id=" .. tostring(id))
	cleanup(e)
end)

------------------------------------------------------------------ T47
test("T47", "Runner: status aplicado vira 'skill ativa' do portador", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status", "Movement", "Attributes", "Combat" })
	e.ApplyStatus(silentStatus("AuditHeldStatus", { duration = 3 }))
	local list = e.GetActiveSkills("AuditHeldStatus")
	t.check("status NÃO aparece em Combat.ActiveSkills", #list == 0, #list .. " runner(s) listados como skill ativa")
	e.StopAllActiveSkills(true)
	t.check("StopAllActiveSkills não derruba status", e.GetStatus("AuditHeldStatus") ~= nil, "status removido junto com as skills")
	cleanup(e)
end)

------------------------------------------------------------------ T48
test("T48", "ECS: chamada com ':' em API de componente gera erro explicativo", function(t)
	local e = makeEntity(spot(), { "Character", "Health" })
	local ok, err = pcall(function() return e:TakeDamage(1) end)
	t.check("erro explicativo", (not ok) and tostring(err):find("chame com") ~= nil, err)
	cleanup(e)
end)

------------------------------------------------------------------ T49
test("T49", "Entrada inválida: DataManager.Get(nil) e HandleIntent(id, nil)", function(t)
	local ok1, e1 = pcall(DataManager.Get, nil)
	t.check("DataManager.Get(nil) não lança erro", ok1, e1)
	local e = makeEntity(spot(), { "Character", "Health", "Status", "Movement", "Attributes", "Combat" })
	local ok2, e2 = pcall(SkillHandler.HandleIntent, e.ID, nil)
	t.check("HandleIntent(id, nil) não lança erro", ok2, e2)
	cleanup(e)
end)

------------------------------------------------------------------ T50
test("T50", "Ciclo de vida: runners de status sobrevivem à remoção da entidade", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local steps = {}
	local S = silentStatus("AuditOrphan", { maxStacks = 20, traits = { E.Traits.Stackable } }, {
		onStep = function(self) steps[self.Runner] = (steps[self.Runner] or 0) + 1 end })
	for _ = 1, 10 do e.ApplyStatus(S) end
	task.wait(0.2)
	cleanup(e)
	local snap = {}
	for r, c in pairs(steps) do snap[r] = c end
	task.wait(0.6)
	local alive = 0
	for r, c in pairs(steps) do if c > (snap[r] or 0) then alive += 1 end end
	t.check("nenhum runner roda depois da entidade destruída", alive == 0, alive .. " de 10 continuam")
end)

platform:Destroy()
flush(true)
print("[AUDIT] BatchA concluída:", #results, "testes")

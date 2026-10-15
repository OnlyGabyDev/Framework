local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)
local E = StateTable.Enum
local SkillRunner = require(SSS.Modules.SkillRunner)
local SkillHandler = require(SSS.Modules.SkillHandler)
local TriggerSet = require(SS.Modules.Combat.TriggerSet)
local Intents = require(RS.Input.Intents)
local GestureResolver = require(RS.Input.GestureResolver)

local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"; folder.Parent = SS
local out = folder:FindFirstChild("BatchB") or Instance.new("StringValue")
out.Name = "BatchB"; out.Parent = folder
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

local ZONE = Vector3.new(-800, 103, 800)
local platform = Instance.new("Part")
platform.Name = "__AuditPlatformB"; platform.Anchored = true
platform.Size = Vector3.new(400, 2, 400); platform.Position = ZONE - Vector3.new(0, 4, 0)
platform.Parent = workspace

local function makeModel(pos)
	local model = Instance.new("Model")
	model.Name = "__AuditDummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"; root.Size = Vector3.new(2, 2, 1); root.CFrame = CFrame.new(pos)
	root.Parent = model; model.PrimaryPart = root; model.Parent = workspace
	return model
end
local function makeEntity(pos, comps, configs) return DataManager.Create(makeModel(pos), comps, configs) end
local function cleanup(e)
	if not e then return end
	local inst = e.Instance
	if inst then pcall(DataManager.Remove, inst); inst:Destroy() end
end
local P = 0
local function spot() P += 1; return ZONE + Vector3.new(((P % 25) - 12) * 8, 0, (math.floor(P / 25) - 6) * 8) end
local COMBAT = { "Character", "Health", "Status", "Movement", "Attributes", "Combat" }
local function press(e, intent) return SkillHandler.HandleIntent(e.ID, Intents.NewEvent(intent, Intents.Kind.Activate, Intents.Gesture.Press)) end

local frames = 0
local dts = {}
local monitor = RunService.Heartbeat:Connect(function(dt) frames += 1; table.insert(dts, dt) if #dts > 4000 then table.remove(dts, 1) end end)
local function frameStats(fromIdx)
	local sum, mx, n = 0, 0, 0
	for i = fromIdx, #dts do sum += dts[i]; mx = math.max(mx, dts[i]); n += 1 end
	return n > 0 and (sum / n * 1000) or 0, mx * 1000, n
end

task.wait(1)

test("T16", "Scheduler: 3000 skills simultâneas com onStep (1 s cada)", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local ended, steps = 0, 0
	local skill = { data = { name = "AuditMass", duration = 1 }, callbacks = {
		onStep = function(self, dt) steps += 1 end,
		onEnd = function() ended += 1 end } }
	local idx = #dts + 1
	local t0 = os.clock()
	for _ = 1, 3000 do SkillRunner.new(skill, e, "AuditMass", E.Types.Skill):start() end
	t.metric("criacao_ms_3000_runners", (os.clock() - t0) * 1000)
	task.wait(1.6)
	local avg, mx = frameStats(idx)
	t.metric("frame_ms_medio_durante", avg)
	t.metric("frame_ms_max_durante", mx)
	t.metric("onStep_total", steps)
	t.check("todos os 3000 terminaram pelo duration", ended == 3000, ended)
	t.check("frame máximo < 50 ms com 3000 runners", mx < 50, mx)
	cleanup(e)
end)

test("T17", "Scheduler: runner que encerra runners de índice menor recebe update duplo", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local victims = {}
	for i = 1, 20 do
		local r = SkillRunner.new({ data = { name = "AuditVictim" .. i, duration = 10 }, callbacks = {} }, e, "AuditVictim" .. i, E.Types.Skill)
		r:start(); victims[i] = r
	end
	local bSteps, killed, f0 = 0, 0, nil
	local B = SkillRunner.new({ data = { name = "AuditKiller", duration = 10 }, callbacks = {
		onStep = function(self)
			f0 = f0 or frames
			bSteps += 1
			if killed < 20 then killed += 1; victims[killed]:endSkill(false) end
		end } }, e, "AuditKiller", E.Types.Skill)
	B:start()
	task.wait(0.8)
	local framesSeen = frames - (f0 or frames) + 1
	B:endSkill(false)
	t.metric("frames_observados", framesSeen)
	t.metric("onStep_do_killer", bSteps)
	t.check("onStep roda 1x por frame (sem update duplo)", bSteps <= framesSeen + 1, ("%d steps em %d frames"):format(bSteps, framesSeen))
	for _, v in ipairs(victims) do v:endSkill(false) end
	cleanup(e)
end)

test("T18", "SkillHandler: cooldown bloqueia o recast da própria skill", function(t)
	local e = makeEntity(spot(), COMBAT)
	local rec = { starts = 0, recasts = 0 }
	e.EquipSkill(Intents.Id.Ability2, { data = { name = "AuditRecast", cooldown = 2, duration = 3 }, callbacks = {
		onStart = function() rec.starts += 1 end, onRecast = function() rec.recasts += 1 end } })
	local ok1 = press(e, Intents.Id.Ability2)
	task.wait(0.2)
	local ok2 = press(e, Intents.Id.Ability2)
	t.check("1ª ativação ok", ok1 == true, ok1)
	t.check("2º toque durante a skill chega no onRecast", ok2 == true and rec.recasts == 1, ("ok2=%s recasts=%d"):format(tostring(ok2), rec.recasts))
	e.StopAllActiveSkills(true)
	cleanup(e)
end)

test("T19", "SkillHandler: maxInstances=3 com 5 ativações", function(t)
	local e = makeEntity(spot(), COMBAT)
	local starts = 0
	e.EquipSkill(Intents.Id.Ability2, { data = { name = "AuditMulti3", cooldown = 0, duration = 2, maxInstances = 3 }, callbacks = {
		onStart = function() starts += 1 end } })
	local oks = {}
	for i = 1, 5 do oks[i] = tostring(press(e, Intents.Id.Ability2)) end
	t.metric("retornos", table.concat(oks, ","))
	t.check("3 instâncias ativas", e.GetActiveSkillCount("AuditMulti3") == 3, e.GetActiveSkillCount("AuditMulti3"))
	t.check("onStart 3 vezes", starts == 3, starts)
	e.StopAllActiveSkills(true)
	cleanup(e)
end)

test("T20", "SkillRunner: erro no onEnd deixa runner 'fantasma' ativo", function(t)
	local e = makeEntity(spot(), COMBAT)
	local rec = { starts = 0, recasts = 0 }
	e.EquipSkill(Intents.Id.Ability2, { data = { name = "AuditBadEnd", cooldown = 0, duration = 0.2 }, callbacks = {
		onStart = function() rec.starts += 1 end,
		onEnd = function() error("onEnd quebrado") end,
		onRecast = function() rec.recasts += 1 end } })
	press(e, Intents.Id.Ability2)
	task.wait(0.5)
	t.check("ActiveSkills limpo após onEnd com erro", e.GetActiveSkillCount("AuditBadEnd") == 0, e.GetActiveSkillCount("AuditBadEnd") .. " runner(s) presos")
	press(e, Intents.Id.Ability2)
	task.wait(0.1)
	t.check("nova ativação cria runner novo (onStart=2, recast=0)", rec.starts == 2 and rec.recasts == 0, ("starts=%d recasts=%d"):format(rec.starts, rec.recasts))
	e.StopAllActiveSkills(true)
	cleanup(e)
end)

test("T21", "SkillRunner: erro no onStart", function(t)
	local e = makeEntity(spot(), COMBAT)
	e.EquipSkill(Intents.Id.Ability2, { data = { name = "AuditBadStart", cooldown = 0, duration = 0.6 }, callbacks = {
		onStart = function(self)
			self.Entity.ApplyStatus({ data = { name = "AuditPartial", category = E.Categories.Debuff, duration = 3 }, callbacks = {} })
			error("onStart quebrado")
		end } })
	local ok, err = pcall(press, e, Intents.Id.Ability2)
	t.check("erro no onStart não escapa do SkillHandler", ok, err)
	t.check("runner com onStart falho não fica ativo", e.GetActiveSkillCount("AuditBadStart") == 0, e.GetActiveSkillCount("AuditBadStart") .. " ativo(s)")
	t.note("status aplicado antes do erro permanece: " .. tostring(e.GetStatus("AuditPartial") ~= nil))
	e.StopAllActiveSkills(true)
	cleanup(e)
end)

test("T22", "Recursão assíncrona: cadeia de skills via task.defer", function(t)
	local e = makeEntity(spot(), { "Character", "Health", "Status" })
	local maxDepth, count = 0, 0
	local Chain
	Chain = { data = { name = "AuditChain", duration = 0.05 }, callbacks = {
		onStart = function(self, ctx)
			count += 1
			maxDepth = math.max(maxDepth, ctx.depth or 0)
			if (ctx.depth or 0) < 120 then
				local lin = self.Runner.Lineage
				task.defer(function() SkillRunner.new(Chain, self.Entity, "AuditChain", E.Types.Skill, lin):start() end)
			end
		end } }
	SkillRunner.new(Chain, e, "AuditChain", E.Types.Skill):start()
	task.wait(1.5)
	t.metric("profundidade_atingida", maxDepth)
	t.check("motor limita cadeia assíncrona em MAX_RECURSION", maxDepth <= E.MAX_RECURSION, maxDepth)

	local bin, binDepth = 0, 0
	local t0 = os.clock()
	local Fork
	Fork = { data = { name = "AuditFork", duration = 0.05 }, callbacks = {
		onStart = function(self, ctx)
			bin += 1
			binDepth = math.max(binDepth, ctx.depth or 0)
			if (ctx.depth or 0) < 11 then
				local lin = self.Runner.Lineage
				for _ = 1, 2 do task.defer(function() SkillRunner.new(Fork, self.Entity, "AuditFork", E.Types.Skill, lin):start() end) end
			end
		end } }
	SkillRunner.new(Fork, e, "AuditFork", E.Types.Skill):start()
	task.wait(1.5)
	t.metric("arvore_binaria_runners", bin)
	t.metric("arvore_binaria_profundidade", binDepth)
	t.note("crescimento exponencial só para porque o autor da skill checou ctx.depth; o motor não impõe limite assíncrono")
	cleanup(e)
end)

test("T23", "TriggerSet: custo de inscrever e emitir com 3000 listeners", function(t)
	local ts = TriggerSet.new()
	local subCpu = 0
	for chunk = 1, 12 do
		local c0 = os.clock()
		for i = 1, 250 do ts:Subscribe({ Role = "OUT", Breakpoint = "onHit", Priority = (chunk * 250 + i) % 7, Action = function() end }) end
		subCpu += os.clock() - c0
		task.wait()
	end
	local ctx = { traits = {} }
	local c1 = os.clock()
	for _ = 1, 50 do ts:Emit("OUT", "onHit", ctx) end
	local emitMs = (os.clock() - c1) * 1000 / 50
	t.metric("subscribe_cpu_ms_total", subCpu * 1000)
	t.metric("emit_ms_por_evento", emitMs)
	t.check("inscrever 3000 listeners custa < 250 ms", subCpu * 1000 < 250, subCpu * 1000)
	t.check("emitir para 3000 listeners < 5 ms", emitMs < 5, emitMs)
end)

test("T24", "TriggerSet: Limit, TTD, isolamento de erro, Fork, Query, reentrância", function(t)
	local ts = TriggerSet.new()
	local fired = 0
	ts:Subscribe({ Role = "IN", Breakpoint = "X", Limit = { Max = 3, OnExhaust = "Remove" }, Action = function() fired += 1 end })
	for _ = 1, 10 do ts:Emit("IN", "X", { traits = {} }) end
	t.check("Limit Max=3 dispara 3x", fired == 3, fired)
	local ttd = 0
	ts:Subscribe({ Role = "IN", Breakpoint = "Y", TTD = 0.2, Action = function() ttd += 1 end })
	ts:Emit("IN", "Y", { traits = {} }); task.wait(0.3); ts:Emit("IN", "Y", { traits = {} })
	t.check("TTD expira", ttd == 1, ttd)
	local after = 0
	ts:Subscribe({ Role = "IN", Breakpoint = "Z", Priority = 10, Action = function() error("boom") end })
	ts:Subscribe({ Role = "IN", Breakpoint = "Z", Priority = 0, Action = function() after += 1 end })
	ts:Emit("IN", "Z", { traits = {} })
	t.check("erro num listener não bloqueia os demais", after == 1, after)
	local gen = 0
	ts:Subscribe({ Role = "OUT", Breakpoint = "G", Inherit = { Generations = 1 }, Action = function() gen += 1 end })
	local child = ts:Fork(); local grand = child:Fork()
	child:Emit("OUT", "G", { traits = {} }); grand:Emit("OUT", "G", { traits = {} })
	t.check("Generations=1: filho herda, neto não", gen == 1, gen)
	local tree = 0
	local p = TriggerSet.new()
	p:Subscribe({ Role = "OUT", Breakpoint = "T", Inherit = { Generations = 3 }, Limit = { Max = 2, Scope = "Tree", OnExhaust = "Disable" }, Action = function() tree += 1 end })
	local c1, c2 = p:Fork(), p:Fork()
	p:Emit("OUT", "T", { traits = {} }); c1:Emit("OUT", "T", { traits = {} }); c2:Emit("OUT", "T", { traits = {} }); c1:Emit("OUT", "T", { traits = {} })
	t.check("Scope=Tree compartilha o limite entre pai e filhos", tree == 2, tree)
	local q = 0
	p:Subscribe({ Role = "IN", Breakpoint = "Q", Query = { All = { "A" }, None = { "B" } }, Action = function() q += 1 end })
	p:Emit("IN", "Q", { traits = { "A" } }); p:Emit("IN", "Q", { traits = { "A", "B" } }); p:Emit("IN", "Q", { traits = {} })
	t.check("TraitQuery All/None", q == 1, q)
	local re = 0
	p:Subscribe({ Role = "IN", Breakpoint = "R", Action = function()
		re += 1
		p:Subscribe({ Role = "IN", Breakpoint = "R", Action = function() re += 100 end })
	end })
	p:Emit("IN", "R", { traits = {} })
	t.check("inscrição feita durante Emit não roda no mesmo Emit", re == 1, re)
end)

test("T25", "TriggerSet: Owner por string colide entre atacantes (padrão do Dash)", function(t)
	local target = makeEntity(spot(), { "Character", "Health", "Status" })
	local a, b = 0, 0
	target:Listen({ Role = "IN", Breakpoint = E.Breakpoints.PostDamage, Owner = "DashBleedCombo", Action = function() a += 1 end })
	target:Listen({ Role = "IN", Breakpoint = E.Breakpoints.PostDamage, Owner = "DashBleedCombo", Action = function() b += 1 end })
	target:UnsubscribeByOwner("DashBleedCombo")
	target.TakeDamage(1, nil)
	t.check("limpar o combo do atacante A preserva o listener do atacante B", b == 1, "listener de B removido junto (b=" .. b .. ")")
	cleanup(target)
end)

test("T26", "TriggerSet: Emit com context nil", function(t)
	local e = makeEntity(spot(), { "Character", "Health" })
	e:Listen({ Role = "IN", Breakpoint = "AuditCustom", Action = function() end })
	local ok, err = pcall(function() e:Emit("IN", "AuditCustom", nil) end)
	t.check("Emit(role, bp, nil) não lança erro", ok, err)
	cleanup(e)
end)

test("T39", "Fuzz: GestureResolver (8 configs, 8 s de press/release aleatórios)", function(t)
	local configs = { false, { Hold = 0.05 }, { DoubleTap = 0.06 }, { Hold = 0.04, DoubleTap = 0.05 }, { Hold = true }, { DoubleTap = true, Tap = false }, { Hold = 0.03, Tap = false }, {} }
	local R = {}
	local violations = {}
	for i, raw in ipairs(configs) do
		local cfg = GestureResolver.Normalize(raw or nil)
		local st = { armed = 0, acts = 0, rels = 0, taps = 0 }
		local r = GestureResolver.new("Primary", function(ev)
			if ev.Kind == Intents.Kind.Activate then
				st.acts += 1
				if ev.Gesture == Intents.Gesture.Tap then st.taps += 1 else
					st.armed += 1
					if st.armed > 1 then table.insert(violations, "cfg" .. i .. ": Activate duplo sem Release") end
				end
			else
				st.rels += 1
				if st.armed ~= 1 then table.insert(violations, "cfg" .. i .. ": Release sem Activate armado") end
				st.armed = 0
			end
		end)
		R[i] = { r = r, cfg = cfg, st = st }
	end
	local ops, errors = 0, 0
	local deadline = os.clock() + 8
	while os.clock() < deadline do
		for _, x in ipairs(R) do
			local ok = pcall(function()
				if math.random() < 0.5 then x.r:Press(os.clock(), x.cfg) else x.r:Release(os.clock()) end
			end)
			ops += 1
			if not ok then errors += 1 end
		end
		task.wait(math.random() * 0.06)
	end
	for _, x in ipairs(R) do x.r:Release(os.clock()) end
	task.wait(0.5)
	local acts, rels, taps = 0, 0, 0
	for _, x in ipairs(R) do acts += x.st.acts; rels += x.st.rels; taps += x.st.taps end
	t.metric("operacoes", ops); t.metric("activates", acts); t.metric("releases", rels); t.metric("taps", taps)
	t.check("nenhum erro lançado", errors == 0, errors)
	t.check("invariante Activate/Release mantida", #violations == 0, table.concat(violations, " | "):sub(1, 400))
	t.check("todo Activate não-Tap tem Release", rels == acts - taps, ("rels=%d acts-taps=%d"):format(rels, acts - taps))
end)

monitor:Disconnect()
platform:Destroy()
flush(true)
print("[AUDIT] BatchB concluída:", #results, "testes")

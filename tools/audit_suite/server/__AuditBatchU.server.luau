local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")

local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)
local E = StateTable.Enum
local SkillHandler = require(SSS.Modules.SkillHandler)
local SkillRunner = require(SSS.Modules.SkillRunner)
local Intents = require(RS.Input.Intents)
local SkillDB = require(SS.DataBase.SkillDatabase)
local UltModule = require(SkillDB._Registry[SkillDB.Keys.Schema.Ultimate])

local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"; folder.Parent = SS
local out = folder:FindFirstChild("BatchU") or Instance.new("StringValue")
out.Name = "BatchU"; out.Parent = folder
local results = {}
local function flush(done) out.Value = HttpService:JSONEncode({ done = done, results = results }) end
local errors = {}
local logConn = LogService.MessageOut:Connect(function(msg, mtype)
	if mtype == Enum.MessageType.MessageError then table.insert(errors, msg:sub(1, 250)) end
end)
local function test(id, name, fn)
	local rec = { id = id, name = name, checks = {}, metrics = {}, notes = {} }
	local t = {}
	function t.check(label, cond, observed) table.insert(rec.checks, { label = label, ok = cond and true or false, observed = tostring(observed) }) end
	function t.metric(k, v) rec.metrics[k] = (type(v) == "number") and (math.floor(v * 100 + 0.5) / 100) or tostring(v) end
	function t.note(s) table.insert(rec.notes, tostring(s)) end
	local e0 = #errors
	local t0 = os.clock()
	local ok, err = xpcall(fn, debug.traceback, t)
	rec.elapsed_s = math.floor((os.clock() - t0) * 1000) / 1000
	if not ok then rec.error = tostring(err) end
	rec.server_errors = {}
	for i = e0 + 1, math.min(#errors, e0 + 8) do table.insert(rec.server_errors, errors[i]) end
	local pass = ok
	for _, c in ipairs(rec.checks) do if not c.ok then pass = false end end
	rec.status = pass and "PASS" or "FAIL"
	table.insert(results, rec)
	flush(false)
end

local ZONE = Vector3.new(-800, 103, -800)
local platform = Instance.new("Part")
platform.Name = "__AuditPlatformU"; platform.Anchored = true
platform.Size = Vector3.new(600, 2, 600); platform.Position = ZONE - Vector3.new(0, 4, 0)
platform.Parent = workspace

local COMBAT_FULL = { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "Weapon", "Animation" }
local function makeCaster(pos)
	local rig = workspace.Rig:Clone(); rig.Name = "__AuditUltCaster"
	rig:PivotTo(CFrame.new(pos) * CFrame.Angles(0, 0, 0)); rig.Parent = workspace
	return DataManager.Create(rig, COMBAT_FULL)
end
local function makeVictim(pos, name)
	local m = Instance.new("Model"); m.Name = name or "__AuditUltVictim"
	local r = Instance.new("Part"); r.Name = "HumanoidRootPart"; r.Size = Vector3.new(2, 3, 1.5); r.CFrame = CFrame.new(pos); r.Parent = m
	m.PrimaryPart = r; m.Parent = workspace
	return DataManager.Create(m, { "Character", "Health", "Status", "Movement" })
end
local function cleanup(e)
	if not e then return end
	local inst = e.Instance
	if inst then pcall(DataManager.Remove, inst); inst:Destroy() end
end
local function grabbed(v)
	for _, f in pairs(v:GetComponent("Movement").ActiveForces) do
		if f.Type == "UltGrab" then return true end
	end
	return false
end
local function desiredPoint(caster)
	return caster.GetRoot().CFrame:PointToWorldSpace(UltModule.data.GrabOffset or Vector3.new(0, 0, -4))
end

local function runScenario(t, label, opts)
	local base = ZONE + (opts.offset or Vector3.zero)
	local caster = makeCaster(base)
	local victims = {}
	for i, dz in ipairs({ -9, -15, -21 }) do
		victims[i] = makeVictim(base + Vector3.new((i - 2) * 0.8, 0, dz), "__AuditUltVictim" .. i)
	end
	task.wait(0.6)
	SkillHandler.HandleLookInput(caster.ID, Vector3.new(0, 0, -1))
	local ok = SkillHandler.HandleIntent(caster.ID, Intents.NewEvent(Intents.Id.Ultimate, Intents.Kind.Activate, Intents.Gesture.Press))
	t.check(label .. ": Ultimate ativou via SkillHandler", ok == true, ok)
	local runner = caster.GetActiveSkills(UltModule.data.name or SkillDB.Keys.Schema.Ultimate)[1]
	local maxErrStraight, maxErrTurn, minPair = 0, 0, math.huge
	local grabbedAt = {}
	local t0 = os.clock()
	local lastPos, speedSamples = caster.GetRoot().Position, {}
	while os.clock() - t0 < (opts.flyTime or 4) do
		local el = os.clock() - t0
		if opts.turnAt and el >= opts.turnAt and not opts._turned then
			opts._turned = true
			SkillHandler.HandleLookInput(caster.ID, Vector3.new(1, 0, 0))
		end
		if opts.killAt and el >= opts.killAt and not opts._killed then
			opts._killed = true
			caster.TakeDamage(1e6, nil)
		end
		local dp = desiredPoint(caster)
		local held = {}
		for i, v in ipairs(victims) do
			if grabbed(v) then
				grabbedAt[i] = grabbedAt[i] or el
				local err = (v.GetRoot().Position - dp).Magnitude
				if opts._turned then maxErrTurn = math.max(maxErrTurn, err) else maxErrStraight = math.max(maxErrStraight, err) end
				table.insert(held, v)
			end
		end
		for a = 1, #held do for b = a + 1, #held do
			minPair = math.min(minPair, (held[a].GetRoot().Position - held[b].GetRoot().Position).Magnitude)
		end end
		local p = caster.GetRoot().Position
		table.insert(speedSamples, (p - lastPos).Magnitude)
		lastPos = p
		RunService.Heartbeat:Wait()
	end
	local nGrab = 0
	for i in pairs(grabbedAt) do nGrab += 1 end
	local sumS = 0 for _, s in ipairs(speedSamples) do sumS += s end
	t.metric(label .. "_alvos_agarrados", nGrab .. "/3")
	t.metric(label .. "_velocidade_media_caster_studs_s", sumS / math.max(1, (opts.flyTime or 4)))
	t.metric(label .. "_erro_max_reta_studs", maxErrStraight)
	if opts.turnAt then t.metric(label .. "_erro_max_curva_studs", maxErrTurn) end
	t.metric(label .. "_menor_distancia_entre_agarrados", minPair == math.huge and "n/a" or minPair)
	return caster, victims, runner, nGrab, maxErrStraight, maxErrTurn, minPair
end

task.wait(1)

test("U1", "Ultimate Schema: agarrar 3 alvos em voo reto + curva de 90° e cancelar", function(t)
	local caster, victims, runner, nGrab, eS, eT, minPair = runScenario(t, "U1", { flyTime = 4, turnAt = 2 })
	t.check("os 3 alvos no caminho são agarrados", nGrab == 3, nGrab .. "/3")
	t.check("alvo preso fica a < 2 studs do ponto de grab em voo reto", eS < 2, eS)
	t.check("alvo preso fica a < 3 studs do ponto de grab na curva", eT < 3, eT)
	t.check("alvos agarrados não se sobrepõem (> 1 stud entre eles)", minPair == math.huge or minPair > 1, minPair)
	caster.StopAllActiveSkills(true)
	task.wait(1)
	local still = 0
	for _, v in ipairs(victims) do if grabbed(v) then still += 1 end end
	t.check("cancelar a Ultimate solta os alvos", still == 0, still .. " alvo(s) ainda presos 1 s depois do cancel")
	t.check("cancelar remove o NoControl do caster", caster.GetStatus("NoControl") == nil, "NoControl ainda ativo")
	t.check("cancelar limpa o ActionState", caster.GetActionState() == nil or caster.GetActionState().name == nil, caster.GetActionState() and tostring(caster.GetActionState().name))
	local pos1 = victims[1].GetRoot().Position
	task.wait(1)
	t.metric("U1_alvo1_deslocamento_1s_apos_cancel", (victims[1].GetRoot().Position - pos1).Magnitude)
	cleanup(caster); for _, v in ipairs(victims) do cleanup(v) end
end)

test("U2", "Ultimate Schema: fim natural (duração encurtada para 3 s)", function(t)
	local base = ZONE + Vector3.new(150, 0, 0)
	local caster = makeCaster(base)
	local victim = makeVictim(base + Vector3.new(0, 0, -9), "__AuditUltVictimU2")
	task.wait(0.6)
	SkillHandler.HandleLookInput(caster.ID, Vector3.new(0, 0, -1))
	local short = { data = setmetatable({ duration = 3, name = "AuditUltShort" }, { __index = UltModule.data }), callbacks = UltModule.callbacks }
	local runner = SkillRunner.new(short, caster, "AuditUltShort", E.Types.Skill)
	runner:start()
	local wasGrabbed = false
	local t0 = os.clock()
	while os.clock() - t0 < 3.6 do
		if grabbed(victim) then wasGrabbed = true end
		task.wait(0.05)
	end
	t.metric("U2_runner_terminou", runner:IsEnded())
	t.check("alvo foi agarrado", wasGrabbed, wasGrabbed)
	task.wait(0.8)
	t.check("fim natural solta o alvo", not grabbed(victim), "alvo preso após o fim da Ultimate")
	t.check("fim natural remove a força de voo do caster", next(caster:GetComponent("Movement").ActiveForces) == nil, "forças restantes no caster")
	cleanup(caster); cleanup(victim)
end)

test("U3", "Ultimate Schema: caster morre no meio do voo", function(t)
	local caster, victims = runScenario(t, "U3", { offset = Vector3.new(-150, 0, 0), flyTime = 2.5, killAt = 1.2 })
	t.check("caster morto", caster.IsAlive() == false, caster.IsAlive())
	t.check("morte do caster encerra a Ultimate", caster.GetActiveSkillCount(UltModule.data.name or "Schema_Ultimate") == 0, caster.GetActiveSkillCount(UltModule.data.name or "Schema_Ultimate") .. " runner(s) ativos")
	local anyGrab = 0
	for _, v in ipairs(victims) do if grabbed(v) then anyGrab += 1 end end
	t.check("alvos são soltos quando o caster morre", anyGrab == 0, anyGrab .. " ainda presos")
	cleanup(caster); for _, v in ipairs(victims) do cleanup(v) end
end)

logConn:Disconnect()
platform:Destroy()
flush(true)
print("[AUDIT] BatchU concluída:", #results, "testes")

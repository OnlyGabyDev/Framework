local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")

local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)
local SkillHandler = require(SSS.Modules.SkillHandler)
local AC = require(SSS.Modules.GlobalAntiCheat)
local ControlComponent = require(SSS.EntityData.Components.ControlComponent)

local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"; folder.Parent = SS
local out = folder:FindFirstChild("BatchP") or Instance.new("StringValue")
out.Name = "BatchP"; out.Parent = folder
local results, timeline = {}, {}
local function mark(s) table.insert(timeline, ("%.2f %s"):format(workspace.DistributedGameTime, s)) end
local function flush(done) out.Value = HttpService:JSONEncode({ done = done, results = results, timeline = timeline }) end
local errors = {}
local logConn = LogService.MessageOut:Connect(function(msg, mtype)
	if mtype == Enum.MessageType.MessageError then table.insert(errors, ("%.2f %s"):format(workspace.DistributedGameTime, msg:sub(1, 300))) end
end)
local function test(id, name, fn)
	local rec = { id = id, name = name, checks = {}, metrics = {}, notes = {} }
	local t = {}
	function t.check(label, cond, observed) table.insert(rec.checks, { label = label, ok = cond and true or false, observed = tostring(observed) }) end
	function t.metric(k, v) rec.metrics[k] = (type(v) == "number") and (math.floor(v * 1000 + 0.5) / 1000) or tostring(v) end
	function t.note(s) table.insert(rec.notes, tostring(s)) end
	local e0 = #errors
	local t0 = os.clock()
	local ok, err = xpcall(fn, debug.traceback, t)
	rec.elapsed_s = math.floor((os.clock() - t0) * 1000) / 1000
	if not ok then rec.error = tostring(err) end
	rec.server_errors = {}
	for i = e0 + 1, #errors do table.insert(rec.server_errors, errors[i]) end
	local pass = ok
	for _, c in ipairs(rec.checks) do if not c.ok then pass = false end end
	rec.status = pass and "PASS" or "FAIL"
	table.insert(results, rec)
	flush(false)
end

local plr = Players:GetPlayers()[1]
local playerId = "Player_" .. plr.UserId
local function body() return DataManager.Get(playerId) end
local function hrp() local b = body(); return b and b.GetRoot() end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function makePuppet(offset, comps, parent)
	local rig = workspace.Rig:Clone()
	rig.Name = "__AuditPuppet"
	rig:PivotTo(CFrame.new(hrp().Position + offset))
	rig.Parent = parent or workspace
	return DataManager.Create(rig, comps or { "Character", "Health", "Status", "Movement", "Control", "Attributes" })
end
local function cleanup(e)
	if not e then return end
	local inst = e.Instance
	if inst then pcall(DataManager.Remove, inst); inst:Destroy() end
end
local function resetPlayer()
	pcall(function()
		AC.UnlockPlayerInput(plr)
		ControlComponent.ReleasePlayer(plr) -- a pilha de controle mora no ControlComponent (a PriorControlledID do AC saiu)
		AC.SetControlledEntity(plr, playerId)
		AC.SetNativeControlSuspended(plr, false)
		local b = body()
		if b then b.SetDrivesInput(false); b.SetDirection(Vector3.zero) end
		local r = hrp(); if r then r:SetNetworkOwner(plr) end
	end)
end

task.wait(1)

test("P1", "Possessão: player possui NPC andando; corpo abandonado e NPC solto", function(t)
	resetPlayer()
	local puppet = makePuppet(Vector3.new(14, 0, 0))
	task.wait(0.3)
	SkillHandler.HandleMovementInput(playerId, Vector3.new(1, 0, 0))
	task.wait(0.1)
	mark("P1 Possess")
	puppet.Possess({ Player = plr })
	t.check("input do player roteado pro NPC", AC.GetEntityID(plr) == puppet.ID, AC.GetEntityID(plr))
	t.check("corpo do player passa a ser server-owned", hrp():GetNetworkOwner() == nil, tostring(hrp():GetNetworkOwner()))
	local p0 = hrp().Position
	task.wait(1.2)
	local drift = flat(hrp().Position - p0).Magnitude
	t.metric("corpo_abandonado_andou_studs", drift)
	t.check("corpo abandonado não segue andando com o último input", drift < 2, drift)
	SkillHandler.HandleMovementInput(AC.GetEntityID(plr), Vector3.new(0, 0, 1))
	local q0 = puppet.GetRoot().Position
	task.wait(1)
	t.metric("npc_possuido_andou_studs", flat(puppet.GetRoot().Position - q0).Magnitude)
	mark("P1 Release")
	puppet.Release()
	t.check("input volta pro corpo do player", AC.GetEntityID(plr) == playerId, AC.GetEntityID(plr))
	t.check("corpo volta a ser do cliente", hrp():GetNetworkOwner() == plr, tostring(hrp():GetNetworkOwner()))
	local r0 = puppet.GetRoot().Position
	task.wait(1.2)
	local npcDrift = flat(puppet.GetRoot().Position - r0).Magnitude
	t.metric("npc_solto_andou_studs", npcDrift)
	t.check("NPC solto não continua andando com o último input do player", npcDrift < 2, npcDrift)
	cleanup(puppet)
	resetPlayer()
end)

test("P2", "Possessão aninhada: A, depois B sem soltar A, depois Release de B e de A", function(t)
	resetPlayer()
	local A = makePuppet(Vector3.new(-14, 0, 0))
	local B = makePuppet(Vector3.new(0, 0, 14))
	task.wait(0.3)
	mark("P2 Possess A")
	A.Possess({ Player = plr }); task.wait(0.3)
	mark("P2 Possess B")
	B.Possess({ Player = plr }); task.wait(0.3)
	t.check("input em B", AC.GetEntityID(plr) == B.ID, AC.GetEntityID(plr))
	t.check("A sabe que perdeu o controle", A.GetController().Player == nil, "A.Controller.Player=" .. tostring(A.GetController().Player))
	mark("P2 Release B")
	B.Release(); task.wait(0.3)
	local afterB = AC.GetEntityID(plr)
	t.metric("roteamento_apos_Release_B", afterB == A.ID and "A" or (afterB == playerId and "corpo" or tostring(afterB)))
	mark("P2 Release A")
	A.Release(); task.wait(0.3)
	local final = AC.GetEntityID(plr)
	t.check("depois de soltar tudo o input volta pro corpo original", final == playerId, final == A.ID and "preso em A" or tostring(final))
	t.check("corpo original volta a ser do cliente", hrp():GetNetworkOwner() == plr, tostring(hrp():GetNetworkOwner()))
	t.check("GetPossessionOf(player) limpo", ControlComponent.GetPossessionOf(plr) == nil, tostring(ControlComponent.GetPossessionOf(plr)))
	cleanup(A); cleanup(B)
	resetPlayer()
end)

test("P3", "Possessão: NPC possuído é destruído durante a possessão", function(t)
	resetPlayer()
	local C = makePuppet(Vector3.new(14, 0, 14))
	task.wait(0.3)
	mark("P3 Possess C")
	C.Possess({ Player = plr }); task.wait(0.3)
	mark("P3 Destroy C")
	cleanup(C)
	task.wait(0.5)
	t.check("input volta pro corpo quando o possuído some", AC.GetEntityID(plr) == playerId, tostring(AC.GetEntityID(plr)) .. " (entidade morta)")
	t.check("GetPossessionOf limpo", ControlComponent.GetPossessionOf(plr) == nil, tostring(ControlComponent.GetPossessionOf(plr)))
	t.check("corpo original volta a ser do cliente", hrp():GetNetworkOwner() == plr, tostring(hrp():GetNetworkOwner()))
	resetPlayer()
end)

test("P4", "IA possuindo IA: B.Possess({AI=true, Brain=...})", function(t)
	local A = makePuppet(Vector3.new(-30, 0, -30), { "Character", "Health", "Status", "Movement", "Control", "AI" })
	local B = makePuppet(Vector3.new(-30, 0, -50), { "Character", "Health", "Status", "Movement", "Control", "AI" })
	B.SetBrain(function(ent) SkillHandler.HandleMovementInput(ent.ID, Vector3.new(-1, 0, 0)) end)
	local ownBrainRuns = 0
	B.SetBrain(function(ent) ownBrainRuns += 1; SkillHandler.HandleMovementInput(ent.ID, Vector3.new(-1, 0, 0)) end)
	task.wait(0.3)
	local possessorRuns = 0
	B.Possess({ AI = true, Brain = function(ent) possessorRuns += 1; SkillHandler.HandleMovementInput(ent.ID, Vector3.new(0, 0, 1)) end })
	local runsAtPossess = ownBrainRuns
	local p0 = B.GetRoot().Position
	task.wait(1.2)
	local d = B.GetRoot().Position - p0
	t.metric("deslocamento_X", d.X); t.metric("deslocamento_Z", d.Z)
	t.check("Brain próprio de B é suspenso pela possessão", ownBrainRuns == runsAtPossess, (ownBrainRuns - runsAtPossess) .. " execuções do brain próprio depois do Possess")
	t.check("Brain do possuidor passa a dirigir B", possessorRuns > 0 and d.Z > 3, ("execuções do possuidor=%d, Z=%.1f"):format(possessorRuns, d.Z))
	B.Release()
	cleanup(A); cleanup(B)
end)

test("P5", "Lock/Unlock durante possessão", function(t)
	resetPlayer()
	local D = makePuppet(Vector3.new(-14, 0, 14))
	task.wait(0.3)
	D.Possess({ Player = plr })
	D.Lock()
	t.check("Lock corta o input (GetEntityID nil)", AC.GetEntityID(plr) == nil, AC.GetEntityID(plr))
	D.Unlock()
	t.check("Unlock devolve pro possuído", AC.GetEntityID(plr) == D.ID, AC.GetEntityID(plr))
	D.Lock()
	local E2 = makePuppet(Vector3.new(-20, 0, 20))
	E2.Possess({ Player = plr })
	t.check("Possess durante Lock não vaza input", AC.GetEntityID(plr) == nil, AC.GetEntityID(plr))
	D.Unlock()
	t.metric("roteamento_apos_unlock", AC.GetEntityID(plr) == E2.ID and "E2" or tostring(AC.GetEntityID(plr)))
	E2.Release(); D.Release()
	cleanup(D); cleanup(E2)
	resetPlayer()
end)

test("P6", "HUD durante possessão: barra de vida mostra quem?", function(t)
	resetPlayer()
	local F = makePuppet(Vector3.new(20, 0, -14), { "Character", "Health", "Status", "Movement", "Control" })
	task.wait(0.3)
	F.Possess({ Player = plr })
	mark("P6 dano no possuido (-30)")
	F.TakeDamage(30, nil)
	task.wait(0.5)
	mark("P6 dano no corpo original (-1)")
	body().TakeDamage(1, nil)
	task.wait(0.5)
	F.Release()
	t.note("conferir no log do cliente: UpdateHealthBar após 'dano no possuido'")
	body().Heal(100)
	cleanup(F)
	resetPlayer()
end)

test("P7", "Câmera: NPC possuído dentro de uma Folder", function(t)
	resetPlayer()
	local f = Instance.new("Folder"); f.Name = "__AuditNPCs"; f.Parent = workspace
	local G = makePuppet(Vector3.new(0, 0, -20), nil, f)
	task.wait(0.3)
	mark("P7 Possess G (dentro de Folder)")
	G.Possess({ Player = plr })
	task.wait(1.5)
	mark("P7 Release G")
	G.Release()
	task.wait(0.5)
	t.note("conferir no log do cliente: CameraSubject durante a janela do P7")
	cleanup(G); f:Destroy()
	resetPlayer()
end)

test("P8", "Respawn (LoadCharacter) enquanto possui um NPC", function(t)
	resetPlayer()
	local H = makePuppet(Vector3.new(14, 0, -30))
	task.wait(0.3)
	H.Possess({ Player = plr })
	task.wait(0.3)
	local oldChar = plr.Character
	mark("P8 LoadCharacter")
	plr:LoadCharacter()
	local t0 = os.clock()
	while (plr.Character == oldChar or not plr.Character) and os.clock() - t0 < 10 do task.wait(0.1) end
	task.wait(2)
	local b = body()
	t.check("novo corpo registrado no DataManager", b ~= nil and b.Instance == plr.Character, b and tostring(b.Instance) or "sem entidade")
	t.check("input roteado pro novo corpo", AC.GetEntityID(plr) == playerId, AC.GetEntityID(plr))
	t.check("GetPossessionOf limpo após respawn", ControlComponent.GetPossessionOf(plr) == nil, tostring(ControlComponent.GetPossessionOf(plr)))
	cleanup(H)
	resetPlayer()
end)

logConn:Disconnect()
flush(true)
print("[AUDIT] BatchP concluída:", #results, "testes")

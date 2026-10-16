--[[
Roda uma vez no boot (Studio/PlayEmpty). Cada teste cria e limpa suas
próprias entidades descartáveis, numa faixa própria longe da origem. Ferramenta
de sprint — não deixe isso rodando num lugar que vá pra produção real.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestHarness = require(script.Parent.TestHarness)
local DataManager = require(ServerScriptService.EntityData.DataManager)
local SkillRunner = require(ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(ServerScriptService.Modules.SkillFactory)
local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local Lineage = require(ServerStorage.Modules.Combat.Lineage)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)
local Intents = require(ReplicatedStorage.Input.Intents)

-- Componentes de uma entidade que casta pelo SkillHandler (mesmo conjunto da suíte de auditoria)
local COMBAT = { "Character", "Health", "Status", "Movement", "Attributes", "Combat" }

-- Cada teste roda numa faixa própria, longe da origem: a GrandIntegrationDemo e o ventilador
-- nascem lá, e o teste de Tether falhava por interferência (F59). makeDummy recebe a posição
-- relativa ao chão da faixa do teste atual.
local GROUND = Vector3.new(1400, 100, 1400) -- topo da plataforma, no início da 1ª faixa
local ZONE_SPACING = 60
local platform = Instance.new("Part")
platform.Name = "__IntegrationTestsPlatform"
platform.Anchored = true
platform.Size = Vector3.new(2048, 2, 120)
platform.CFrame = CFrame.new(GROUND + Vector3.new(1024 - ZONE_SPACING / 2, -1, 0))
platform.Parent = workspace

local zoneOrigin = CFrame.new(GROUND)
local zoneCount = 0

local function run(name: string, fn: (t: any) -> ())
	zoneOrigin = CFrame.new(GROUND + Vector3.new(zoneCount * ZONE_SPACING, 0, 0))
	zoneCount += 1
	TestHarness.Run(name, fn)
end

local function makeDummy(cframe: CFrame, components: {string}?, configs: {[string]: any}?, parentEntity: any?)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = zoneOrigin * cframe
	root.Anchored = false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace

	return DataManager.Create(model, components or { "Character", "Health", "Movement" }, configs, parentEntity)
end

local function cleanup(entity: any)
	if not entity then return end
	local instance = entity.Instance
	DataManager.Remove(instance)
	if instance then instance:Destroy() end
end

-- Runner de skill descartável, com data e callbacks inline (não passa pelo loadout)
local function makeRunner(entity: any, name: string, data: {[string]: any}, callbacks: {[string]: any})
	data.name = name
	local skill = SkillFactory.GetSkill({ data = data, callbacks = callbacks })
	return SkillRunner.new(skill, entity, name, StateTable.Enum.Types.Skill)
end

-- Aperto de botão pelo caminho real do input (SkillHandler.HandleIntent)
local function press(entity: any, intent: string)
	return SkillHandler.HandleIntent(entity.ID, Intents.NewEvent(intent, Intents.Kind.Activate, Intents.Gesture.Press))
end

task.wait(2) -- deixa o resto do jogo terminar de bootar

run("Sprint 1 — Block determinístico", function(t)
	local dummy = makeDummy(CFrame.new(0, 10, 0), { "Character", "Health", "Movement", "Status" })

	dummy.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "FirstBlock" })
	task.wait(0.05)
	dummy.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "SecondBlock" })

	local _, owners = dummy.GetActiveTags()
	local blockOwner = owners[StateTable.Enum.Tags.block]

	t.assert(blockOwner ~= nil, "Nenhum dono de block resolvido")
	t.assert(blockOwner.data.ID == "SecondBlock", "Dono resolvido não é o mais recente")

	cleanup(dummy)
end)

run("Sprint 6 — Floating não confunde com Falling", function(t)
	local dummy = makeDummy(CFrame.new(0, 50, 0), { "Character", "Health", "Movement" })
	dummy.SetMovement()
	task.wait(0.1)

	local stateBeforeForce = dummy.GetAirState()
	t.log("Estado sem Force:", stateBeforeForce)
	t.assert(stateBeforeForce == "Falling" or stateBeforeForce == "Jumping", "Esperava queda livre sem Force ativa")

	local forceId = dummy.AddForce({
		Type = "TestHover", Duration = 2, Hard = true, IgnoreGravity = true,
		Direction = Vector3.zero, Speed = 0, RequiresControl = false,
	})
	task.wait(0.2)

	local stateDuringHover = dummy.GetAirState()
	t.log("Estado hovering:", stateDuringHover)
	t.assert(stateDuringHover == "Floating", "Deveria reportar Floating com Hard force + IgnoreGravity, mesmo sem velocidade")

	dummy.RemoveForce(forceId)
	cleanup(dummy)
end)

run("Sprint 8/9 — Tether gruda posição + reivindica ownership de servidor", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0))
	local victim = makeDummy(CFrame.new(10, 5, 0))
	caster.SetMovement()
	victim.SetMovement()

	local forceId = victim.AddForce({
		Type = "TestGrab", Duration = 1, Hard = true, IgnoreGravity = true, RequiresControl = false,
		FollowTarget = function() return caster.GetRoot() end,
		FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
		FollowResponsiveness = 20, FollowMaxSpeed = 100,
	})

	task.wait(0.5)

	local expected = caster.GetCFrame():PointToWorldSpace(Vector3.new(0, 0, -3))
	local actual = victim.GetRoot().Position
	local drift = (expected - actual).Magnitude
	t.log("Drift após convergência:", drift, "studs")
	t.assert(drift < 1.5, "Vítima não convergiu — modo Tether não está funcionando")

	local owner = victim.GetRoot():GetNetworkOwner()
	t.assert(owner == nil, "Root da vítima deveria estar sob ownership do SERVIDOR enquanto Hard force ativa")

	victim.RemoveForce(forceId)
	task.wait(0.1)
	cleanup(caster)
	cleanup(victim)
end)

run("Sprint 10 — Fork de TriggerSet propaga OUT.onHit do minion pro pai", function(t)
	local summoner = makeDummy(CFrame.new(0, 5, 0))
	local heard = false

	local unsubscribe = summoner:Listen({
		Role = StateTable.Enum.Roles.OUT,
		Breakpoint = StateTable.Enum.Breakpoints.onHit,
		Inherit = { Generations = 1 },
		Priority = 0,
		Action = function() heard = true end,
	})

	local minion = makeDummy(CFrame.new(5, 5, 0), nil, nil, summoner)
	minion:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onHit, StateTable.BuildContext(nil, 1))
	task.wait(0.05)

	t.assert(heard, "Listener do summoner não disparou quando o MINION emitiu onHit")

	unsubscribe()
	cleanup(summoner)
	cleanup(minion)
end)

run("Sprint 11 — ComboWindow marca e consome dentro da janela", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Status" })

	BaseSkills.ComboWindow.Mark(dummy, "TestMarker", 0.3, { Foo = "bar" })
	local immediate = BaseSkills.ComboWindow.Consume(dummy, "TestMarker")
	t.assert(immediate and immediate.Foo == "bar", "Consume imediato deveria trazer o payload")

	BaseSkills.ComboWindow.Mark(dummy, "TestMarker", 0.1, { Foo = "baz" })
	task.wait(0.3)
	local expired = BaseSkills.ComboWindow.Consume(dummy, "TestMarker")
	t.assert(expired == nil, "Consume após expirar deveria vir nil")

	cleanup(dummy)
end)

run("Sprint 13 — Link espelha movimento, Unlink corta", function(t)
	local primary = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Control" })
	local secondary = makeDummy(CFrame.new(3, 5, 0), { "Character", "Health", "Movement", "Control" })
	primary.SetMovement()
	secondary.SetMovement()

	primary.LinkTo(secondary, { MirrorMovement = true })

	local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
	SkillHandler.HandleMovementInput(primary.ID, Vector3.new(1, 0, 0))
	task.wait(0.05)
	t.assert(secondary.GetDirection().Magnitude > 0.5, "Secundário deveria ter recebido a direção espelhada")

	primary.Unlink(secondary)
	SkillHandler.HandleMovementInput(primary.ID, Vector3.new(0, 0, 1))
	task.wait(0.05)
	t.assert(secondary.GetDirection().X > 0.5, "Após Unlink, secundário não deveria mais atualizar")

	cleanup(primary)
	cleanup(secondary)
end)

run("Sprint 18 — AddComponent dinâmico dispara OnAdded", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement" })
	dummy:AddComponent(dummy.ComponentKey.AI, {}, true)

	local ranBrain = false
	dummy.SetBrain(function() ranBrain = true end)
	task.wait(0.1)

	t.assert(ranBrain, "Brain nunca rodou — AIComponent.OnAdded não foi chamado no add dinâmico")
	cleanup(dummy)
end)

--=============================================================================
--  FASE 1 DO HARDENING (tools/audit_suite/HANDOFF_HARDENING.md)
--=============================================================================

run("F1.3 — Recast e TriggerAction ignoram runner encerrado", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local recasts, triggers = 0, 0
	local runner = makeRunner(dummy, "__TestRecastEnded", { duration = 10 }, {
		onRecast = function() recasts += 1 end,
		onTrigger = function() triggers += 1; return true end,
	})
	runner:start()
	t.assert(runner:Recast(true) == true, "Runner vivo deveria aceitar recast")
	t.assert(runner:TriggerAction({}) == true, "Runner vivo deveria responder ao TriggerAction")

	runner:endSkill(false)
	t.assert(runner:Recast(true) == false, "Recast(checkOnly) respondeu true num runner encerrado")
	t.assert(runner:Recast() == false, "Recast respondeu true num runner encerrado")
	t.assert(runner:TriggerAction({}) == nil, "TriggerAction respondeu num runner encerrado")
	t.assert(recasts == 0 and triggers == 1,
		string.format("Callbacks rodaram depois do fim (onRecast %d, onTrigger %d)", recasts, triggers))

	cleanup(dummy)
end)

run("F1.7 — runner:ApplyStatus não muta o opts e devolve ID utilizável", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local victimA = makeDummy(CFrame.new(4, 5, 0), { "Health", "Status" })
	local victimB = makeDummy(CFrame.new(8, 5, 0), { "Health", "Status" })
	local status = { data = { name = "__TestOptsStatus" }, callbacks = {} }
	local runner1 = makeRunner(caster, "__TestOptsCaster1", { duration = 10 }, {})
	local runner2 = makeRunner(caster, "__TestOptsCaster2", { duration = 10 }, {})
	runner1:start()
	runner2:start()

	-- Constante de módulo congelada: antes o runner gravava Source nela (erro de escrita)
	local idA = runner1:ApplyStatus(status, table.freeze({ Duration = 5, Target = victimA }))
	t.assert(type(idA) == "string", "ApplyStatus com opts congelado deveria aplicar e devolver ID string")

	-- A mesma tabela usada por dois casts: o Source do 1º não pode vazar para o 2º
	local OPTS = { Duration = 5, Target = victimA }
	runner1:ApplyStatus(status, OPTS)
	OPTS.Target = victimB
	local idB = runner2:ApplyStatus(status, OPTS)
	t.assert(OPTS.Source == nil, "runner:ApplyStatus gravou Source no opts do chamador")

	local entryB = victimB.GetStatus("__TestOptsStatus")
	t.assert(entryB ~= nil and entryB[1].runner.Source == runner2, "Source do 2º cast ficou com o runner do 1º")
	t.assert(entryB[1].runner.Entity == victimB, "O runner do status deveria agir no alvo")
	t.assert(victimB.RemoveStatusByID(idB) == true, "RemoveStatusByID com o ID devolvido falhou")
	t.assert(victimB.GetStatus("__TestOptsStatus") == nil, "Status seguiu ativo depois do RemoveStatusByID")

	-- No componente, Target de outra entidade é ignorado (com warn): o status fica no portador
	victimA.ApplyStatus(status, { Duration = 5, Target = victimB })
	local entryA = victimA.GetStatus("__TestOptsStatus")
	t.assert(entryA ~= nil and entryA[1].runner.Entity == victimA, "Target de outra entidade desviou o runner do portador")
	t.assert(victimB.GetStatus("__TestOptsStatus") == nil, "Target de outra entidade aplicou o status no alvo errado")

	runner1:endSkill(false)
	runner2:endSkill(false)
	cleanup(caster)
	cleanup(victimA)
	cleanup(victimB)
end)

run("F1.2 — onStart com erro devolve o cooldown", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	dummy.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestBadStartCD", cooldown = 5, duration = 1 }, callbacks = {
		onStart = function() error("[FW-DEBUG] onStart quebrado de propósito (teste F1.2)") end,
	} })

	local ok = press(dummy, Intents.Id.Ability2)
	t.assert(ok == false, "Ativação com onStart quebrado deveria falhar")
	t.assert(not dummy.HasCooldown("__TestBadStartCD"), "O cooldown seguiu contando depois do onStart com erro")
	t.assert(dummy.GetActiveSkillCount("__TestBadStartCD") == 0, "Runner com onStart falho ficou ativo")

	cleanup(dummy)
end)

run("F1.4 — ActionState sai junto com o runner que o setou", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local outCast = StateTable.ActionStates.Out.cast
	-- Skill que seta um ActionState Out e "esquece" de remover
	dummy.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestForgetsState", cooldown = 0, duration = 0.1 }, callbacks = {
		onStart = function(self) self.Entity.SetActionState(outCast, self) end,
	} })
	dummy.EquipSkill(Intents.Id.Ability3, { data = { name = "__TestNextSkill", cooldown = 0, duration = 0.1 }, callbacks = {} })

	t.assert(press(dummy, Intents.Id.Ability2) == true, "A 1ª skill deveria ativar")
	local state = dummy.GetActionState()
	t.assert(state ~= nil and state.name == outCast.data.name, "O ActionState Out não foi setado")
	t.wait(0.3)
	t.assert(dummy.GetActionState() == nil, "O ActionState Out ficou preso depois do fim da skill")
	t.assert(press(dummy, Intents.Id.Ability3) == true, "Skill nova recusada pelo ActionState de um runner morto")

	dummy.StopAllActiveSkills(true)
	cleanup(dummy)
end)

run("F1.5 — status homônimo não vira skill ativa nem bloqueia a skill", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local starts = 0
	-- A skill aplica em si um status com o mesmo nome (ex.: skill "Roleta" e status "Roleta")
	local sameName = { data = { name = "__TestRoleta" }, callbacks = {} }
	dummy.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestRoleta", cooldown = 0, duration = 0.1 }, callbacks = {
		onStart = function(self)
			starts += 1
			self:ApplyStatus(sameName, { Duration = 5 })
		end,
	} })

	t.assert(press(dummy, Intents.Id.Ability2) == true, "A 1ª ativação falhou")
	t.wait(0.3) -- a skill acabou; o status homônimo segue no portador
	t.assert(dummy.GetStatus("__TestRoleta") ~= nil, "O status homônimo deveria seguir ativo")
	t.assert(dummy.GetActiveSkillCount("__TestRoleta") == 0, "O status entrou em ActiveSkills como se fosse a skill")
	t.assert(press(dummy, Intents.Id.Ability2) == true and starts == 2,
		"A 2ª ativação caiu no status em vez de criar runner novo (onStart " .. starts .. "x)")

	dummy.StopAllActiveSkills(true)
	t.assert(dummy.GetStatus("__TestRoleta") ~= nil, "StopAllActiveSkills derrubou o status junto com as skills")
	cleanup(dummy)
end)

run("F80 — OUT.onEnd é emitido também em entidade sem Combat", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local starts, ends, reason = 0, 0, nil
	dummy:Listen({ Role = StateTable.Enum.Roles.OUT, Breakpoint = StateTable.Enum.Breakpoints.onStart, Action = function() starts += 1 end })
	dummy:Listen({ Role = StateTable.Enum.Roles.OUT, Breakpoint = StateTable.Enum.Breakpoints.onEnd,
		Action = function(ctx) ends += 1; reason = ctx.reason end })

	local runner = makeRunner(dummy, "__TestEndNoCombat", { duration = 10 }, {})
	runner:start()
	runner:endSkill(false)
	t.assert(starts == 1, "OUT.onStart não disparou (" .. starts .. "x)")
	t.assert(ends == 1 and reason == StateTable.Enum.EndReasons.Stop,
		string.format("OUT.onEnd disparou %dx (reason %s)", ends, tostring(reason)))

	cleanup(dummy)
end)

run("F1.6 — cast por input é a raiz da Lineage (depth 1, rootOrigin = caster)", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local seen = {}
	local child = { data = { name = "__TestLineageChild" }, callbacks = {
		onStart = function(_, ctx) seen.childDepth = ctx.depth; seen.childRoot = ctx.rootOrigin end,
	} }
	dummy.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestLineageRoot", cooldown = 0, duration = 0.1 }, callbacks = {
		onStart = function(self, ctx)
			seen.depth = ctx.depth
			seen.rootOrigin = ctx.rootOrigin
			seen.history = Lineage.GetHistoryArray(self.Runner.Lineage)
			self:ApplyStatus(child, { Duration = 1 })
		end,
	} })

	t.assert(press(dummy, Intents.Id.Ability2) == true, "A ativação falhou")
	t.assert(seen.depth == 1, "depth do cast por input deveria ser 1 (veio " .. tostring(seen.depth) .. ")")
	t.assert(seen.rootOrigin == dummy, "rootOrigin deveria ser quem castou (veio " .. tostring(seen.rootOrigin) .. ")")
	t.assert(#seen.history == 1 and seen.history[1] == "__TestLineageRoot",
		"Histórico com nó raiz extra: " .. table.concat(seen.history, " > "))
	t.assert(seen.childDepth == 2 and seen.childRoot == dummy,
		"Status aplicado pela skill: depth " .. tostring(seen.childDepth) .. ", rootOrigin " .. tostring(seen.childRoot))

	dummy.StopAllActiveSkills(true)
	cleanup(dummy)
end)

task.wait(1)
TestHarness.Summary()
platform:Destroy()

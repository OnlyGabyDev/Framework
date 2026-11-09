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

run("F1.8 — stackOnSelf: ID do restack é o existente e o máximo renova a duração", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health", "Status" })
	local Stackable = StateTable.Enum.Traits.Stackable
	local stack = { data = { name = "__TestStack", stackOnSelf = true, maxStacks = 2, traits = { Stackable } }, callbacks = {} }

	local id1 = dummy.ApplyStatus(stack, { Duration = 0.5 })
	local id2 = dummy.ApplyStatus(stack, { Duration = 1 }) -- a duração da reaplicação passa a valer
	t.assert(type(id1) == "string" and id2 == id1, "O restack devolveu um ID diferente do existente")
	t.assert(dummy.GetStatusCounter("__TestStack") == 2, "Deveria ter 2 stacks")

	t.wait(0.6) -- com a duração da 1ª aplicação (0,5 s) já teria expirado
	local id3 = dummy.ApplyStatus(stack, { Duration = 1 }) -- no máximo: só renova
	t.assert(id3 == id1, "A reaplicação no máximo criou outra instância (a duração do restack não valeu?)")
	t.assert(dummy.GetStatusCounter("__TestStack") == 2, "Passou do máximo de stacks")
	t.wait(0.6) -- 1,2 s desde o restack: sem a renovação no máximo já teria expirado
	t.assert(dummy.GetStatus("__TestStack") ~= nil, "A reaplicação no máximo não renovou a duração")

	t.assert(dummy.RemoveStatusByID(id2) == true, "RemoveStatusByID com o ID do restack falhou")
	t.assert(dummy.GetStatus("__TestStack") == nil, "O status seguiu ativo depois do RemoveStatusByID")

	-- Opt-out: com refreshOnMax = false a reaplicação no máximo não muda nada
	local noRefresh = { data = { name = "__TestStackNoRefresh", stackOnSelf = true, maxStacks = 1, refreshOnMax = false,
		traits = { Stackable } }, callbacks = {} }
	dummy.ApplyStatus(noRefresh, { Duration = 0.8 })
	t.wait(0.5)
	dummy.ApplyStatus(noRefresh, { Duration = 0.8 })
	t.wait(0.5)
	t.assert(dummy.GetStatus("__TestStackNoRefresh") == nil, "refreshOnMax = false renovou a duração mesmo assim")

	cleanup(dummy)
end)

run("F1.10 — status: onCancel/onEnd recebem o ctx e o cancel não tem veto", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health", "Status" })
	local got = {}
	local vetoing = { data = { name = "__TestStatusVeto" }, callbacks = {
		onCancel = function(_, ctx) got.cancelReason = ctx and ctx.reason; return false end,
		onEnd = function(_, ctx) got.endReason = ctx and ctx.reason end,
	} }
	dummy.ApplyStatus(vetoing, { Duration = 5 })
	local runner = dummy.GetStatus("__TestStatusVeto")[1].runner

	t.assert(dummy.RemoveStatus("__TestStatusVeto") == true, "RemoveStatus falhou")
	local Cancel = StateTable.Enum.EndReasons.Cancel
	t.assert(got.cancelReason == Cancel and got.endReason == Cancel,
		string.format("ctx.reason não chegou (onCancel %s, onEnd %s)", tostring(got.cancelReason), tostring(got.endReason)))
	t.assert(runner:IsEnded(), "O onCancel com return false vetou o fim: runner órfão fora do registro")

	cleanup(dummy)
end)

--=============================================================================
--  LOTE 1 DOS PENDENTES DA AUDITORIA (08/11/2026)
--=============================================================================

local Traits = StateTable.Enum.Traits

-- Status de bloqueio inline (o formato dos módulos de Status/Buffs)
local function blockStatus(name: string, meta: {[string]: any})
	meta.name = name
	meta.tags = meta.tags or { [StateTable.Enum.Tags.block] = true }
	return { data = meta, callbacks = {} }
end

run("F10 — Unbreakable e TrueBlock são lidos do meta do bloqueio", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local victim = makeDummy(CFrame.new(4, 5, 0), { "Health", "Status" })
	local hit = makeRunner(caster, "__TestBreaker", { duration = 10 }, {})
	hit:start()

	local FULL = { mode = StateTable.Enum.BlockModes.Full }
	victim.ApplyStatus(blockStatus("__TestUnbreakable", { traits = { Traits.Unbreakable }, block = FULL }), { Duration = 10 })
	local ctx = StateTable.BuildContext(hit, 10)
	ctx.traits = { Traits.BlockBreak }
	victim.TakeDamage(ctx)
	t.assert(victim.GetStatus("__TestUnbreakable") ~= nil, "BlockBreak quebrou um bloqueio Unbreakable")
	victim.RemoveStatus("__TestUnbreakable")

	victim.ApplyStatus(blockStatus("__TestTrueBlock", { traits = { Traits.TrueBlock }, block = FULL }), { Duration = 10 })
	local hpBefore = victim.GetHP and victim.GetHP() or nil
	local ctx2 = StateTable.BuildContext(hit, 10)
	ctx2.traits = { Traits.TrueHit }
	local _, dealt = victim.TakeDamage(ctx2)
	t.assert((dealt == 0 or dealt == false or dealt == nil) and (hpBefore == nil or victim.GetHP() == hpBefore),
		"TrueHit atravessou um bloqueio TrueBlock (dano " .. tostring(dealt) .. ")")

	hit:endSkill(false)
	cleanup(caster)
	cleanup(victim)
end)

run("F11 — bloqueio declarado (Full) e o ShieldsFrom filtra", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local victim = makeDummy(CFrame.new(4, 5, 0), { "Health", "Status" })
	local hit = makeRunner(caster, "__TestShieldHit", { duration = 10 }, {})
	hit:start()

	-- Bloqueio Full declarado que só barra DOT: hit comum passa, hit DOT é zerado
	victim.ApplyStatus(blockStatus("__TestDotBlock", { ShieldsFrom = { Traits.DOT },
		block = { mode = StateTable.Enum.BlockModes.Full } }), { Duration = 10 })
	local plain = StateTable.BuildContext(hit, 10)
	local _, dealtPlain = victim.TakeDamage(plain)
	t.assert(dealtPlain == 10, "Hit sem a trait do ShieldsFrom foi bloqueado (dano " .. tostring(dealtPlain) .. ")")
	local dot = StateTable.BuildContext(hit, 10)
	dot.traits = { Traits.DOT }
	local _, dealtDot = victim.TakeDamage(dot)
	t.assert(dealtDot ~= 10, "Bloqueio Full deixou passar o hit DOT")
	victim.RemoveStatus("__TestDotBlock")

	-- Escudo de status (StatusShield: ShieldsFrom = DOT) barra a aplicação de um status DOT
	victim.ApplyStatus(StateTable.Status.StatusShield, { Duration = 10 })
	local dotStatus = { data = { name = "__TestDotStatus", traits = { Traits.DOT } }, callbacks = {} }
	victim.ApplyStatus(dotStatus, { Duration = 5 })
	t.assert(victim.GetStatus("__TestDotStatus") == nil, "StatusShield não barrou um status DOT")
	local plainStatus = { data = { name = "__TestPlainStatus" }, callbacks = {} }
	victim.ApplyStatus(plainStatus, { Duration = 5 })
	t.assert(victim.GetStatus("__TestPlainStatus") ~= nil, "StatusShield barrou um status sem DOT")

	hit:endSkill(false)
	cleanup(caster)
	cleanup(victim)
end)

run("F12 — recast roda com o cooldown da própria skill correndo", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local starts, recasts = 0, 0
	-- Recast com o cooldown correndo agora é escolha declarada da skill (D13): recast = Free
	dummy.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestRecastCD", cooldown = 5, duration = 3,
		cooldownPolicy = { recast = StateTable.Enum.RecastPolicy.Free } }, callbacks = {
		onStart = function() starts += 1 end,
		onRecast = function() recasts += 1 end,
	} })

	t.assert(press(dummy, Intents.Id.Ability2) == true, "1º toque não ativou")
	t.assert(dummy.HasCooldown("__TestRecastCD"), "Cast não iniciou o cooldown")
	local ok = press(dummy, Intents.Id.Ability2)
	t.assert(ok == true and recasts == 1 and starts == 1,
		string.format("Recast barrado pelo cooldown (ok %s, starts %d, recasts %d)", tostring(ok), starts, recasts))

	dummy.StopAllActiveSkills()
	t.assert(press(dummy, Intents.Id.Ability2) == false, "Cast novo ignorou o cooldown")

	cleanup(dummy)
end)

run("F15 — encerrar runner de índice menor no update não roda o atual 2 vezes", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local stepsB = 0
	local first = makeRunner(dummy, "__TestSchedA", { duration = 10 }, {})
	first:start()
	local second = makeRunner(dummy, "__TestSchedB", { duration = 10 }, {
		onStep = function()
			stepsB += 1
			if not first:IsEnded() then first:endSkill(false) end
		end,
	})
	second:start()

	local RunService = game:GetService("RunService")
	local frames = 0
	local conn = RunService.Heartbeat:Connect(function() frames += 1 end)
	t.wait(0.5)
	conn:Disconnect()
	second:endSkill(false)
	-- Folga de 1 frame entre o contador e o scheduler; antes o B rodava 2 vezes no frame do fim do A
	t.assert(stepsB <= frames + 1, string.format("onStep do B rodou %d vezes em %d frames", stepsB, frames))

	cleanup(dummy)
end)

run("F78 — erro no onStep encerra o runner mesmo com o onCancel recusando", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local steps = 0
	local runner = makeRunner(dummy, "__TestStepError", { duration = 10 }, {
		onStep = function()
			steps += 1
			error("[FW-DEBUG] onStep quebrado de propósito (teste F78)")
		end,
		onCancel = function() return false end,
	})
	runner:start()
	t.wait(0.3)
	t.assert(runner:IsEnded(), "Runner com erro no onStep seguiu vivo")
	t.assert(steps == 1, "onStep com erro rodou " .. steps .. " vezes")

	cleanup(dummy)
end)

run("F75 — entidade morta não inicia cast novo", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local starts = 0
	dummy.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestDeadCast", cooldown = 0, duration = 1 }, callbacks = {
		onStart = function() starts += 1 end,
	} })
	dummy.TakeDamage(10000)
	t.assert(not dummy.IsAlive(), "A entidade não morreu")
	t.assert(press(dummy, Intents.Id.Ability2) == false and starts == 0, "Entidade morta castou")

	-- Override por entidade: RefuseCastOnDeath = false no config do Combat libera
	local free = makeDummy(CFrame.new(4, 5, 0), COMBAT, { Combat = { RefuseCastOnDeath = false } })
	free.EquipSkill(Intents.Id.Ability2, { data = { name = "__TestDeadCastFree", cooldown = 0, duration = 1 }, callbacks = {} })
	free.TakeDamage(10000)
	t.assert(press(free, Intents.Id.Ability2) == true, "RefuseCastOnDeath = false não liberou o cast")

	cleanup(dummy)
	cleanup(free)
end)

run("F28 — andar para a direita é classificado como Right", function(t)
	local Utils = require(ReplicatedStorage.Utils)
	local facing = Vector3.new(0, 0, -1)
	t.assert(Utils.classifyDirection(Vector3.new(1, 0, 0), facing) == "Right",
		"+X com facing -Z deu " .. Utils.classifyDirection(Vector3.new(1, 0, 0), facing))
	t.assert(Utils.classifyDirection(Vector3.new(-1, 0, 0), facing) == "Left", "-X com facing -Z não deu Left")
	t.assert(Utils.classifyDirection(Vector3.new(1, 0, -1), facing) == "ForwardRight", "Diagonal frente-direita errada")
	-- Facing +X: a direita é +Z
	t.assert(Utils.classifyDirection(Vector3.new(0, 0, 1), Vector3.new(1, 0, 0)) == "Right", "+Z com facing +X não deu Right")
end)

run("F26/F27 — HitStart zera o sweep do Blockcast e o timer dura o pedido", function(t)
	local ShapecastHitbox = require(ServerStorage.Modules.Combat.Hitbox.ShapecastHitbox)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CFrame = zoneOrigin * CFrame.new(0, 5, 0)
	local attachment = Instance.new("Attachment")
	attachment.Name = ShapecastHitbox.Settings.Tag
	attachment:SetAttribute("CastType", "Blockcast")
	attachment:SetAttribute("CastSize", Vector3.one)
	attachment.Parent = part
	part.Parent = workspace

	local hitbox = ShapecastHitbox.new(part)
	local _, segment = next(hitbox:GetAllSegments())
	t.assert(segment ~= nil, "Hitbox sem segmento")
	segment.CastData._LastCFrameBlockCast = CFrame.new(0, 5000, 0)

	local stoppedAt
	hitbox:OnStopped(function() stoppedAt = os.clock() end)
	local startedAt = os.clock()
	hitbox:HitStart(1.0)
	t.assert(segment.CastData._LastCFrameBlockCast ~= CFrame.new(0, 5000, 0), "HitStart manteve o sweep da ativação anterior")

	t.wait(1.3)
	t.assert(stoppedAt ~= nil, "A hitbox não parou")
	local lasted = stoppedAt - startedAt
	t.assert(math.abs(lasted - 1.0) < 0.06, string.format("HitStart(1.0) durou %.3f s", lasted))

	hitbox:Destroy()
	part:Destroy()
end)

run("F25 — replay na mesma key não perde a track nova", function(t)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = zoneOrigin * CFrame.new(0, 5, 0)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	Instance.new("Animator").Parent = humanoid
	humanoid.Parent = model
	model.Parent = workspace
	local dummy = DataManager.Create(model, { "Character", "Health", "Animation" })
	local anim = dummy:GetComponent(dummy.ComponentKey.Animation)
	t.assert(anim ~= nil and anim.Animator ~= nil, "AnimationComponent sem Animator no dummy")

	local first = anim:PlayAnimation(507766388, "__k", 0)
	local second = anim:PlayAnimation(507766388, "__k", 0)
	t.wait(0.3) -- o Stopped da 1ª (parada pelo replay) já disparou
	t.assert(anim.Tracks.__k == second, "O Stopped da track antiga apagou a nova")
	t.assert(first.Parent == nil, "A track parada não foi destruída")

	anim:StopAllAnimations(0)
	t.wait(0.3)
	t.assert(not second.IsPlaying, "StopAllAnimations deixou a track tocando")

	cleanup(dummy)
end)

--=============================================================================
--  LOTE 2 DOS PENDENTES DA AUDITORIA (08/11/2026)
--=============================================================================

run("F35/F37/F38 — RemoveComponent tira a API, Events preenchido, NPC é NPC", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Status" })
	t.assert(dummy:IsNPC(), "Entidade sem player não é NPC (Type = " .. tostring(dummy.Type) .. ")")
	t.assert(not dummy:IsPlayer(), "NPC respondeu IsPlayer")

	dummy:RemoveComponent(dummy.ComponentKey.Status)
	t.assert(rawget(dummy, "ApplyStatus") == nil, "A API do componente removido seguiu na entidade")
	local ok = pcall(dummy.ApplyStatus, { data = { name = "__TestRemoved" }, callbacks = {} }, {})
	t.assert(ok, "A chamada à API removida deu erro em vez de cair no stub")

	local Core = require(ServerScriptService.EntityData.EntityCore)
	t.assert(next(Core.Events) ~= nil, "EntityCore.Events vazio (EventKey não copiado no registro)")

	cleanup(dummy)
end)

run("F36/F49 — Movement sem Character e entradas inválidas não derrubam nada", function(t)
	local ok, entity = pcall(makeDummy, CFrame.new(0, 5, 0), { "Health", "Movement" })
	t.assert(ok and entity ~= nil, "Movement sem Character derrubou o DataManager.Create: " .. tostring(entity))
	t.assert(DataManager.Get(entity.ID) == entity, "A entidade ficou meio registrada")
	cleanup(entity)

	local okGet, got = pcall(DataManager.Get, nil)
	t.assert(okGet and got == nil, "DataManager.Get(nil) deu erro")
	local okNum = pcall(DataManager.Get, 42)
	t.assert(okNum, "DataManager.Get(42) deu erro")

	local dummy = makeDummy(CFrame.new(4, 5, 0), COMBAT)
	local okIntent, res = pcall(SkillHandler.HandleIntent, dummy.ID, nil)
	t.assert(okIntent and res == false, "HandleIntent(id, nil) deu erro")
	cleanup(dummy)
end)

run("F34 — NPC com Movement fica com a física no servidor", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement" })
	local root = dummy.GetRoot()
	t.assert(root:GetNetworkOwnershipAuto() == false, "NPC seguiu com auto-ownership")
	t.assert(root:GetNetworkOwner() == nil, "NPC com dono cliente")
	cleanup(dummy)
end)

run("F42 — GetStat sem base não cacheia o default", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Attributes" })
	t.assert(dummy.GetStat("__TestNoBase", 5) == 5, "1ª chamada não devolveu o default")
	t.assert(dummy.GetStat("__TestNoBase", 9) == 9, "2ª chamada com outro default devolveu o cache da 1ª")
	dummy.SetStat("__TestWithBase", 3)
	t.assert(dummy.GetStat("__TestWithBase", 9) == 3, "Com base registrada o default não pode valer")
	cleanup(dummy)
end)

run("F44 — AreaEffect:Stop dispara o OnExit de quem estava dentro", function(t)
	local AreaEffect = require(ServerStorage.Modules.Combat.AreaEffect)
	local dummy = makeDummy(CFrame.new(0, 3, 0), { "Character", "Health" })
	local center = zoneOrigin * CFrame.new(0, 3, 0)
	local area = AreaEffect.new(function() return center end, "Box", Vector3.new(10, 10, 10), 30)
	local entered, exited = 0, 0
	area:OnEnter(function(e) if e == dummy then entered += 1 end end)
	area:OnExit(function(e) if e == dummy then exited += 1 end end)
	area:Start()
	t.wait(0.3)
	t.assert(entered == 1, "A entidade não entrou na zona (" .. entered .. ")")
	area:Stop()
	t.wait(0.1)
	t.assert(exited == 1, "Stop não disparou o OnExit")
	cleanup(dummy)
end)

run("F48/F52 — Emit sem context e ordem da inscrição ordenada", function(t)
	local TriggerSet = require(ServerStorage.Modules.Combat.TriggerSet)
	local set = TriggerSet.new()
	local order = {}
	local function sub(tag, priority)
		set:Subscribe({ Role = "IN", Breakpoint = "__bp", Priority = priority,
			Action = function() table.insert(order, tag) end })
	end
	sub("a0", 0); sub("b5", 5); sub("c0", 0); sub("d5", 5); sub("e9", 9); sub("f0", nil)
	local list = set.Subscriptions.IN.__bp
	local got = {}
	for _, s in list do
		table.insert(got, tostring(s.Priority or 0))
	end
	t.assert(table.concat(got, ",") == "9,5,5,0,0,0", "Ordem por Priority errada: " .. table.concat(got, ","))
	t.assert(list[2]._seq < list[3]._seq and list[4]._seq < list[5]._seq, "Empate não manteve a ordem de inscrição")

	local ok, err = pcall(function() set:Emit("IN", "__bp", nil) end)
	t.assert(ok, "Emit com context nil deu erro: " .. tostring(err))

	-- 3000 inscrições: a ordenação por inserção não pode custar segundos
	local t0 = os.clock()
	for i = 1, 3000 do
		set:Subscribe({ Role = "IN", Breakpoint = "__big", Priority = i % 7, Action = function() end })
	end
	local spent = os.clock() - t0
	t.assert(spent < 0.5, string.format("3000 inscrições levaram %.2f s", spent))
end)

run("F65 — ApplyDamage em alvo sem Health devolve false, 0", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local wall = makeDummy(CFrame.new(4, 5, 0), { "Character" })
	local ok, dealt = caster.ApplyDamage(10, nil, wall)
	t.assert(ok == false and dealt == 0, "Alvo sem Health devolveu " .. tostring(ok) .. ", " .. tostring(dealt))
	cleanup(caster)
	cleanup(wall)
end)

run("F74 — regras de imunidade mescladas por tag", function(t)
	local Helper = require(ServerStorage.Modules.Combat.StateTable.Helper)
	local fake = { Status = {
		A = { data = { tags = { __imm = true }, bypassBy = { "X", "Y" } } },
		B = { data = { tags = { __imm = true }, bypassBy = { "Y", "Z" } } },
	} }
	local rules = Helper.BuildImmunityRules(fake)
	local rule = rules.__imm
	t.assert(rule ~= nil, "Regra mesclada ausente")
	t.assert(#rule.bypassableBy == 1 and rule.bypassableBy[1] == "Y",
		"Mescla deveria deixar só Y: " .. table.concat(rule.bypassableBy, ","))
	t.assert(rule.name == "A+B", "Nome da regra mesclada: " .. tostring(rule.name))
end)

--=============================================================================
--  LOTE 3 DOS PENDENTES DA AUDITORIA (08/11/2026)
--=============================================================================

run("F17 — ponto secundário sem Handle_<key> não reusa o Handle do primário", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Weapon" })
	for _, armName in { "Right Arm", "Left Arm" } do
		local arm = Instance.new("Part")
		arm.Name = armName
		arm.Size = Vector3.new(1, 2, 1)
		arm.CFrame = dummy.Instance.PrimaryPart.CFrame
		arm.Parent = dummy.Instance
	end
	local weapon = Instance.new("Model")
	weapon.Name = "__TestWeapon"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Parent = weapon
	weapon.Parent = dummy.Instance

	local comp = dummy:GetComponent(dummy.ComponentKey.Weapon)
	comp:_AttachAllPoints(weapon, { primary = "Right Arm", secondary = "Left Arm" })
	local motors = 0
	for _, d in handle:GetChildren() do
		if d:IsA("Motor6D") then motors += 1 end
	end
	t.assert(motors == 1, "O Handle recebeu " .. motors .. " Motor6D (o secundário reusou a peça)")
	t.assert(comp.Motors.secondary == nil, "Ponto secundário sem Handle_secondary ganhou motor")

	cleanup(dummy)
end)

run("F82 — Lock sobrevive ao respawn (Register)", function(t)
	local Players = game:GetService("Players")
	local player = Players:GetPlayers()[1]
	if not player or not player.Character or not player.Character:GetAttribute("EntityID") then
		t.log("sem player com entidade neste Play: teste pulado")
		return
	end
	local AntiCheat = require(ServerScriptService.Modules.GlobalAntiCheat)
	local native = AntiCheat.GetNativeEntityId(player)
	-- O roteamento de antes (o player pode estar possuindo um corpo da GrandIntegrationDemo): o
	-- teste mexe direto no AntiCheat e precisa devolvê-lo, senão a pilha de possessão e o
	-- roteamento ficam discordando para os testes seguintes
	local routedBefore = AntiCheat.GetControlledEntityId(player)
	t.assert(AntiCheat.LockPlayerInput(player), "Lock falhou")
	AntiCheat.Register(player) -- o que o respawn faz
	local stillLocked = AntiCheat.GetEntityID(player) == nil
	local restored = AntiCheat.UnlockPlayerInput(player)
	local afterUnlock = AntiCheat.GetEntityID(player)
	AntiCheat.SetControlledEntity(player, routedBefore)
	t.assert(stillLocked, "O Register (respawn) soltou o Lock")
	t.assert(restored and afterUnlock == native, "O Unlock não devolveu o corpo nativo")
end)

--=============================================================================
--  LOTE 4 DOS PENDENTES DA AUDITORIA (08/11/2026)
--=============================================================================

run("F45 — modificador com o mesmo ID de duas fontes usa contagem", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Attributes" })
	dummy.SetStat("__TestSpeed", 10)
	local Flat = StateTable.Enum.ModifierType.Flat
	dummy.AddModifier("__TestSpeed", "SlowZone", Flat, -4) -- zona A
	dummy.AddModifier("__TestSpeed", "SlowZone", Flat, -4) -- zona B, mesmo ID
	dummy.RemoveModifier("__TestSpeed", "SlowZone") -- sai da A
	t.assert(dummy.GetStat("__TestSpeed") == 6, "Sair de uma zona tirou o efeito da outra (" .. dummy.GetStat("__TestSpeed") .. ")")
	dummy.RemoveModifier("__TestSpeed", "SlowZone")
	t.assert(dummy.GetStat("__TestSpeed") == 10, "O modificador não saiu com a última referência")
	cleanup(dummy)
end)

run("F47 — canDisplace = false barra força externa, não o dash próprio", function(t)
	local dummy = makeDummy(CFrame.new(0, 3, 0), { "Character", "Health", "Status", "Movement" })
	dummy.ApplyStatus({ data = { name = "__TestUnstoppable", tags = { [StateTable.Enum.Tags.canDisplace] = false } }, callbacks = {} }, { Duration = 5 })
	local root = dummy.GetRoot()

	local start = root.Position
	dummy.AddForce({ Type = "__TestKnock", Duration = 0.4, Speed = 40, Direction = Vector3.new(1, 0, 0), RequiresControl = false })
	t.wait(0.5)
	local pushed = (root.Position - start) * Vector3.new(1, 0, 1)
	t.assert(pushed.Magnitude < 2, string.format("Força externa deslocou %.1f studs com canDisplace = false", pushed.Magnitude))

	start = root.Position
	dummy.AddForce({ Type = "__TestDash", Duration = 0.4, Speed = 40, Direction = Vector3.new(1, 0, 0), Hard = true })
	t.wait(0.5)
	local dashed = (root.Position - start) * Vector3.new(1, 0, 1)
	t.assert(dashed.Magnitude > 5, string.format("Dash próprio andou só %.1f studs com canDisplace = false", dashed.Magnitude))

	cleanup(dummy)
end)

run("F50 — entidade criada ancorada ganha ForceRig e anda ao ser solta", function(t)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = zoneOrigin * CFrame.new(0, 3, 0)
	root.Anchored = true
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace
	local dummy = DataManager.Create(model, { "Character", "Health", "Movement" })
	root.Anchored = false
	local start = root.Position
	dummy.AddForce({ Type = "__TestPush", Duration = 0.4, Speed = 30, Direction = Vector3.new(1, 0, 0), Hard = true })
	t.wait(0.5)
	local moved = ((root.Position - start) * Vector3.new(1, 0, 1)).Magnitude
	t.assert(moved > 5, string.format("Entidade nascida ancorada andou %.1f studs depois de solta", moved))
	cleanup(dummy)
end)

run("F67 — exclusive remove também stacks em lista da mesma categoria", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health", "Status" })
	local Stackable = StateTable.Enum.Traits.Stackable
	local cat = "__TestCat"
	local stacked = { data = { name = "__TestStackList", category = cat, traits = { Stackable }, maxStacks = 3 }, callbacks = {} }
	dummy.ApplyStatus(stacked, { Duration = 5 })
	dummy.ApplyStatus(stacked, { Duration = 5 })
	t.assert(#dummy.GetStatus("__TestStackList") == 2, "Setup: stack em lista não criou 2 instâncias")
	dummy.ApplyStatus({ data = { name = "__TestExclusive", category = cat, exclusive = true }, callbacks = {} }, { Duration = 5 })
	t.assert(dummy.GetStatus("__TestStackList") == nil, "exclusive não removeu a lista da mesma categoria")
	t.assert(dummy.GetStatus("__TestExclusive") ~= nil, "O exclusive não ficou ativo")
	cleanup(dummy)
end)

--=============================================================================
--  TESTES DOS ITENS CORRIGIDOS SÓ COM LEITURA (08/11/2026)
--=============================================================================

run("F18 — pasta de arma duplicada resolve para a completa", function(t)
	local WeaponModule = require(ServerScriptService.EntityData.Components.WeaponComponent)
	local find = WeaponModule._findWeaponFolder
	local weapons = Instance.new("Folder")

	local only = Instance.new("Folder")
	only.Name = "__Solo"
	only.Parent = weapons
	t.assert(find(weapons, "__Solo") == only, "Pasta única não foi achada")
	t.assert(find(weapons, "__Nada") == nil, "Pasta inexistente devolveu algo")

	-- A legada vem PRIMEIRO na ordem dos filhos (o FindFirstChild pegaria ela)
	local legacy = Instance.new("Folder")
	legacy.Name = "__Martelo"
	legacy.Parent = weapons
	local complete = Instance.new("Folder")
	complete.Name = "__Martelo"
	local model = Instance.new("Model")
	model.Name = "__Martelo"
	model.Parent = complete
	complete.Parent = weapons
	t.assert(weapons:FindFirstChild("__Martelo") == legacy, "Setup: a legada deveria vir primeiro")
	t.assert(find(weapons, "__Martelo") == complete, "Duplicata resolveu para a pasta sem model")

	-- Diferença só de capitalização também é duplicata (regra 19)
	local lowerLegacy = Instance.new("Folder")
	lowerLegacy.Name = "__machado"
	lowerLegacy.Parent = weapons
	local upperComplete = Instance.new("Folder")
	upperComplete.Name = "__Machado"
	local axe = Instance.new("Model")
	axe.Name = "__Machado"
	axe.Parent = upperComplete
	upperComplete.Parent = weapons
	t.assert(find(weapons, "__Machado") == upperComplete, "Duplicata por capitalização resolveu errado")

	weapons:Destroy()
end)

run("F53 — runner sem onStep não monta context por frame", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local function counting(runner)
		local calls = 0
		runner.BuildContext = function(self)
			calls += 1
			return SkillRunner.BuildContext(self)
		end
		return function() return calls end
	end

	local silent = makeRunner(dummy, "__TestNoStep", { duration = 10 }, {})
	local silentCalls = counting(silent)
	silent:start()
	local afterStart = silentCalls()
	t.wait(0.3)
	t.assert(silentCalls() == afterStart,
		string.format("Runner sem onStep montou %d contexts em 0,3 s", silentCalls() - afterStart))

	local stepping = makeRunner(dummy, "__TestWithStep", { duration = 10 }, { onStep = function() end })
	local steppingCalls = counting(stepping)
	stepping:start()
	t.wait(0.3)
	t.assert(steppingCalls() > 5, "Runner com onStep não recebeu context (gancho do teste quebrado?)")

	silent:endSkill(false)
	stepping:endSkill(false)
	cleanup(dummy)
end)

run("F63 — player sem HRP usa a PrimaryPart como root", function(t)
	local CharacterModule = require(ServerScriptService.EntityData.Components.CharacterComponent)
	local model = Instance.new("Model")
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Anchored = true
	torso.CFrame = zoneOrigin * CFrame.new(0, 5, 0)
	torso.Parent = model
	model.PrimaryPart = torso
	Instance.new("Humanoid").Parent = model
	model.Parent = workspace

	-- Formato de entidade de player ({ Model, Player }), sem passar pelo registro do DataManager
	local comp = CharacterModule.new({ Instance = model }, {})
	comp:SetEntity({ Model = model, Player = nil })
	local root = comp:GetRoot()
	t.assert(root == torso, "Root do player sem HRP: " .. tostring(root))

	model:Destroy()
end)

run("F72 — WaitForMarker com timeout retorna no disparo", function(t)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = zoneOrigin * CFrame.new(0, 5, 0)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	Instance.new("Animator").Parent = humanoid
	humanoid.Parent = model
	model.Parent = workspace
	local dummy = DataManager.Create(model, { "Character", "Health", "Animation" })
	local anim = dummy:GetComponent(dummy.ComponentKey.Animation)

	-- Marker controlado pelo teste (uma animação de verdade com marker exigiria asset próprio)
	local marker = Instance.new("BindableEvent")
	anim.GetMarkerSignal = function() return marker.Event end

	task.delay(0.1, marker.Fire, marker)
	local t0 = os.clock()
	local fired = anim:WaitForMarker("__k", "Hit", 2)
	local waited = os.clock() - t0
	t.assert(fired == true, "WaitForMarker não viu o disparo")
	t.assert(waited < 0.5, string.format("WaitForMarker esperou %.2f s com o marker em 0,1 s", waited))

	t0 = os.clock()
	local timedOut = anim:WaitForMarker("__k", "Hit", 0.3)
	waited = os.clock() - t0
	t.assert(timedOut == false, "Sem disparo deveria devolver false")
	t.assert(waited >= 0.25 and waited < 0.7, string.format("Timeout de 0,3 s durou %.2f s", waited))

	marker:Destroy()
	cleanup(dummy)
end)

run("F81 — WeaponTransform dura TransformTime e troca o modo no fim", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "Weapon" })
	local weapon = dummy:GetComponent(dummy.ComponentKey.Weapon)
	local modeSet
	-- Arma de teste: os modos vêm daqui, sem depender dos assets do place
	weapon.GetCurrentMode = function() return "Merged" end
	weapon.GetWeaponData = function()
		return { Modes = { Dual = { TransformTime = 0.5 }, Merged = { TransformTime = 0.5 } } }
	end
	weapon.SetMode = function(_, mode) modeSet = mode; return true end
	weapon.GetModeData = function() return {} end

	local module = require(ServerStorage.DataBase.SkillDatabase.Schema.WeaponTransform)
	local runner = SkillRunner.new(SkillFactory.GetSkill(module), dummy, "WeaponTransform", StateTable.Enum.Types.Skill)
	runner:start()
	t.wait(0.25)
	t.assert(not runner:IsEnded(), "A transformação acabou antes do TransformTime (janela de 1 frame)")
	t.assert(modeSet == nil, "O modo trocou antes do fim da transformação")
	t.wait(0.45)
	t.assert(runner:IsEnded(), "A transformação não terminou depois do TransformTime")
	t.assert(modeSet == "Dual", "O modo não trocou para Dual no fim (" .. tostring(modeSet) .. ")")

	cleanup(dummy)
end)

run("F83 — Lock durante a possessão manda o ID roteado ao cliente", function(t)
	local Players = game:GetService("Players")
	local player = Players:GetPlayers()[1]
	if not player or not player.Character or not player.Character:GetAttribute("EntityID") then
		t.log("sem player com entidade neste Play: teste pulado")
		return
	end
	local AntiCheat = require(ServerScriptService.Modules.GlobalAntiCheat)
	local routedBefore = AntiCheat.GetControlledEntityId(player) -- devolvido no fim (ver F82)
	local body = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health" })

	AntiCheat.SetControlledEntity(player, body.ID)
	AntiCheat.LockPlayerInput(player)
	local locked, routed = AntiCheat._ControlStatePayload(player)
	local inputCut = AntiCheat.GetEntityID(player) == nil
	AntiCheat.UnlockPlayerInput(player)
	AntiCheat.SetControlledEntity(player, routedBefore)

	t.assert(locked == true, "O payload não indicou Lock")
	t.assert(routed == body.ID, "Lock mandou " .. tostring(routed) .. " em vez do corpo possuído (a câmera voltaria ao nativo)")
	t.assert(inputCut, "Com Lock o input não foi cortado no servidor")
	t.assert(AntiCheat.GetEntityID(player) == routedBefore, "O teste não devolveu o roteamento de antes")

	cleanup(body)
end)

--=============================================================================
--  D13 — POLÍTICA DE COOLDOWN DECLARADA (08/11/2026)
--=============================================================================

local CooldownPolicy = require(ServerScriptService.Modules.CooldownPolicy)
local RECAST = StateTable.Enum.RecastPolicy
local START = StateTable.Enum.CooldownStart

-- Equipa uma skill inline no Ability2 de um dummy de combate
local function equip(dummy, name, data, callbacks)
	data.name = name
	dummy.EquipSkill(Intents.Id.Ability2, { data = data, callbacks = callbacks or {} })
	return function() return press(dummy, Intents.Id.Ability2) end
end

run("D13 — validação: onRecast sem recast declarado, cooldown inválido, M1", function(t)
	local _, issues = CooldownPolicy.Validate({ name = "a", cooldown = 1 }, { onRecast = function() end })
	t.assert(#issues == 1, "onRecast sem recast declarado deveria gerar 1 aviso (" .. #issues .. ")")
	local policy = CooldownPolicy.Validate({ name = "a", cooldown = 1 }, { onRecast = function() end })
	t.assert(policy.recast == RECAST.Restart, "Sem declaração o recast deveria cair no comportamento antigo (Restart)")

	local bad, badIssues = CooldownPolicy.Validate({ name = "b" }, {})
	t.assert(#badIssues >= 1 and bad.cooldown == 0, "cooldown ausente deveria avisar e usar 0")
	local _, refundIssues = CooldownPolicy.Validate({ name = "c", cooldown = 1, cooldownPolicy = { refund = { cancel = 2, nada = 1 } } }, {})
	t.assert(#refundIssues == 2, "refund fora de 0..1 e motivo desconhecido deveriam avisar (" .. #refundIssues .. ")")

	local ok, issuesOk = CooldownPolicy.Validate({ name = "d", cooldown = 0 }, {})
	t.assert(#issuesOk == 0 and ok.cooldown == 0 and ok.start == START.Cast, "cooldown = 0 declarado é válido")

	local M1 = require(ServerStorage.DataBase.SkillDatabase.Schema.M1)
	local m1Policy, m1Issues = CooldownPolicy.Validate(M1.data, M1.callbacks)
	t.assert(#m1Issues == 0 and m1Policy.recast == RECAST.Restart,
		"M1 deveria declarar recast = Restart sem avisos (" .. table.concat(m1Issues, "; ") .. ")")
end)

run("D13 — recast Restart: espera o cooldown e o reinicia (ritmo do combo do M1)", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local recasts = 0
	local tap = equip(dummy, "__TestRestart", { cooldown = 0.3, duration = 5, cooldownPolicy = { recast = RECAST.Restart } },
		{ onRecast = function() recasts += 1 end })
	t.assert(tap() == true, "Cast não ativou")
	t.assert(tap() == false and recasts == 0, "Recast passou com o cooldown do cast correndo")
	t.wait(0.35)
	t.assert(tap() == true and recasts == 1, "Recast não rodou depois do cooldown")
	t.assert(dummy.HasCooldown("__TestRestart"), "Restart não reiniciou o cooldown")
	t.assert(tap() == false and recasts == 1, "Recast seguinte passou sem esperar o cooldown reiniciado")
	dummy.StopAllActiveSkills()
	cleanup(dummy)
end)

run("D13 — recast Blocked: espera o cooldown e não o reinicia", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local recasts = 0
	local tap = equip(dummy, "__TestBlocked", { cooldown = 0.3, duration = 5, cooldownPolicy = { recast = RECAST.Blocked } },
		{ onRecast = function() recasts += 1 end })
	tap()
	t.assert(tap() == false, "Recast passou com o cooldown correndo")
	t.wait(0.35)
	t.assert(tap() == true and recasts == 1, "Recast não rodou depois do cooldown")
	t.assert(not dummy.HasCooldown("__TestBlocked"), "Blocked reiniciou o cooldown")
	t.assert(tap() == true and recasts == 2, "Sem cooldown o recast seguinte deveria passar")
	dummy.StopAllActiveSkills()
	cleanup(dummy)
end)

run("D13 — recast Free: ignora o cooldown e não o reinicia", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local recasts = 0
	local tap = equip(dummy, "__TestFree", { cooldown = 5, duration = 5, cooldownPolicy = { recast = RECAST.Free } },
		{ onRecast = function() recasts += 1 end })
	tap()
	t.wait(0.2)
	t.assert(tap() == true and recasts == 1, "Free não deixou o recast passar com o cooldown correndo")
	t.assert(dummy.GetCooldown("__TestFree") < 4.9, "Free reiniciou o cooldown")
	dummy.StopAllActiveSkills()
	cleanup(dummy)
end)

run("D13 — recast com intervalo numérico próprio", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local recasts = 0
	local tap = equip(dummy, "__TestGap", { cooldown = 5, duration = 5, cooldownPolicy = { recast = 0.3 } },
		{ onRecast = function() recasts += 1 end })
	tap()
	t.assert(tap() == false, "Recast passou antes do intervalo")
	t.wait(0.35)
	t.assert(tap() == true and recasts == 1, "Recast não passou depois do intervalo")
	t.assert(tap() == false and recasts == 1, "O intervalo não recomeçou depois do recast")
	t.assert(dummy.GetCooldown("__TestGap") < 4.7, "O intervalo próprio mexeu no cooldown")
	dummy.StopAllActiveSkills()
	cleanup(dummy)
end)

run("D13 — start = End: o cooldown começa no fim do runner", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local tap = equip(dummy, "__TestEnd", { cooldown = 2, duration = 0.3, cooldownPolicy = { start = START.End } })
	t.assert(tap() == true, "Cast não ativou")
	t.assert(not dummy.HasCooldown("__TestEnd"), "Cooldown começou no cast com start = End")
	t.assert(tap() == false, "Segundo cast passou com o runner vivo (a trava é o maxInstances)")
	t.wait(0.45)
	t.assert(dummy.HasCooldown("__TestEnd") and dummy.GetCooldown("__TestEnd") > 1.5,
		"Cooldown não começou no fim (" .. dummy.GetCooldown("__TestEnd") .. ")")
	cleanup(dummy)
end)

run("D13 — start = Manual: sem commit não cobra, com commit cobra", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local tapSkip = equip(dummy, "__TestManualSkip", { cooldown = 2, duration = 0.2, cooldownPolicy = { start = START.Manual } })
	tapSkip()
	t.assert(not dummy.HasCooldown("__TestManualSkip"), "Manual cobrou o cooldown antes do commit")
	t.wait(0.35)
	t.assert(not dummy.HasCooldown("__TestManualSkip"), "Manual sem commit cobrou o cooldown no fim")

	local committed
	local tapCommit = equip(dummy, "__TestManualCommit", { cooldown = 2, duration = 0.2, cooldownPolicy = { start = START.Manual } }, {
		onStart = function(self) committed = self:CommitCooldown() end,
	})
	tapCommit()
	t.assert(committed == true and dummy.HasCooldown("__TestManualCommit"), "CommitCooldown não cobrou o cooldown")
	cleanup(dummy)
end)

run("D13 — CommitCooldown fora de Manual não faz nada", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local result
	local tap = equip(dummy, "__TestCommitCast", { cooldown = 0.5, duration = 0.2 }, {
		onStart = function(self) result = self:CommitCooldown() end,
	})
	tap()
	t.assert(result == false, "CommitCooldown com start = Cast deveria devolver false")
	cleanup(dummy)
end)

run("D13 — Fizzle no onStart devolve o cooldown inteiro", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local reason
	local tap = equip(dummy, "__TestFizzle", { cooldown = 5, duration = 3 }, {
		onStart = function(self) self:Fizzle() end,
		onEnd = function(_, ctx) reason = ctx.reason end,
	})
	tap()
	t.assert(reason == StateTable.Enum.EndReasons.Fizzle, "onEnd não recebeu o motivo fizzle (" .. tostring(reason) .. ")")
	t.assert(not dummy.HasCooldown("__TestFizzle"), "Fizzle cobrou o cooldown")
	t.assert(dummy.GetActiveSkillCount("__TestFizzle") == 0, "Runner com Fizzle seguiu ativo")
	cleanup(dummy)
end)

run("D13 — refund por motivo: cancelamento devolve metade", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local tap = equip(dummy, "__TestRefund", { cooldown = 4, duration = 5,
		cooldownPolicy = { refund = { [StateTable.Enum.EndReasons.Cancel] = 0.5 } } })
	tap()
	dummy.StopAllActiveSkills(true)
	local left = dummy.GetCooldown("__TestRefund")
	t.assert(left > 1.6 and left < 2.1, string.format("Cancelamento com refund 0,5 deixou %.2f s de 4", left))
	cleanup(dummy)
end)

run("D13 — erro no onStep encerra com motivo error e devolve o cooldown", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local reason
	local tap = equip(dummy, "__TestStepErrCD", { cooldown = 5, duration = 3 }, {
		onStep = function() error("[FW-DEBUG] onStep quebrado de propósito (teste D13)") end,
		onEnd = function(_, ctx) reason = ctx.reason end,
	})
	tap()
	t.wait(0.2)
	t.assert(reason == StateTable.Enum.EndReasons.Error, "Motivo do fim por erro: " .. tostring(reason))
	t.assert(not dummy.HasCooldown("__TestStepErrCD"), "Erro no onStep cobrou o cooldown")
	cleanup(dummy)
end)

--=============================================================================
--  D13 — CARGAS, REDUÇÃO DE COOLDOWN E HERANÇA (08/11/2026)
--=============================================================================

run("D13 — cargas: N usos, recarga uma por vez, emendando", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local name = "__TestCharges"
	local tap = equip(dummy, name, { cooldown = 0.4, duration = 0.05, cooldownPolicy = { charges = 2 } })
	t.assert(tap() == true, "1º uso falhou")
	t.assert(dummy.GetCooldownCharges(name) == 1, "Sobrou " .. tostring(dummy.GetCooldownCharges(name)) .. " carga(s), esperado 1")
	t.assert(not dummy.HasCooldown(name), "Com 1 carga a skill deveria estar disponível")
	t.wait(0.1)
	t.assert(tap() == true, "2º uso (2ª carga) falhou")
	t.assert(dummy.HasCooldown(name), "Sem cargas a skill deveria estar em cooldown")
	t.wait(0.1)
	t.assert(tap() == false, "Usou sem carga")
	t.wait(0.25) -- 0,45 s desde o 1º uso: a 1ª recarga terminou
	t.assert(dummy.GetCooldownCharges(name) == 1, "A 1ª recarga não devolveu a carga")
	t.wait(0.4) -- 0,85 s: a 2ª recarga (emendada na 1ª) terminou
	local charges, max = dummy.GetCooldownCharges(name)
	t.assert(charges == 2 and max == 2, string.format("Recarga emendada: %s de %s", tostring(charges), tostring(max)))
	t.assert(dummy.GetCooldown(name) == 0, "Com cargas cheias o cooldown deveria ser 0")
	cleanup(dummy)
end)

run("D13 — cargas: Fizzle e erro devolvem a carga", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local name = "__TestChargeFizzle"
	local tap = equip(dummy, name, { cooldown = 3, duration = 1, cooldownPolicy = { charges = 2 } }, {
		onStart = function(self) self:Fizzle() end,
	})
	tap()
	t.assert(dummy.GetCooldownCharges(name) == 2, "Fizzle não devolveu a carga (" .. tostring(dummy.GetCooldownCharges(name)) .. ")")
	cleanup(dummy)
end)

run("D13 — redução de cooldown pelo stat, opt-out e teto", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local CDR = StateTable.Enum.Stats.CooldownReduction
	dummy.SetStat(CDR, 0.5)

	equip(dummy, "__TestCDR", { cooldown = 4, duration = 0.05 })()
	local reduced = dummy.GetCooldown("__TestCDR")
	t.assert(reduced > 1.8 and reduced <= 2, string.format("50%% de redução em 4 s deu %.2f", reduced))

	t.wait(0.1)
	equip(dummy, "__TestCDRIgnore", { cooldown = 4, duration = 0.05, cooldownPolicy = { ignoreReduction = true } })()
	t.assert(dummy.GetCooldown("__TestCDRIgnore") > 3.8, "ignoreReduction não ignorou a redução")

	t.wait(0.1)
	dummy.SetStat(CDR, 0.95)
	equip(dummy, "__TestCDRCap", { cooldown = 4, duration = 0.05 })()
	local capped = dummy.GetCooldown("__TestCDRCap")
	t.assert(capped > 0.7 and capped <= 0.8, string.format("Teto de 80%%: 4 s deveria virar 0,8 (deu %.2f)", capped))

	-- Mudar o stat no meio não reescala a contagem que já corre (documentado)
	dummy.SetStat(CDR, 0)
	t.assert(math.abs(dummy.GetCooldown("__TestCDRCap") - capped) < 0.1, "Mudar o stat reescalou a contagem em andamento")
	cleanup(dummy)
end)

run("D13 — teto da redução por skill (95% e 50%) e valor inválido", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	dummy.SetStat(StateTable.Enum.Stats.CooldownReduction, 0.9)

	equip(dummy, "__TestCap95", { cooldown = 4, duration = 0.05, cooldownPolicy = { maxReduction = 0.95 } })()
	local high = dummy.GetCooldown("__TestCap95")
	t.assert(high > 0.3 and high <= 0.4, string.format("Teto 95%% com 90%% de redução: 4 s deveria virar 0,4 (deu %.2f)", high))

	t.wait(0.1)
	equip(dummy, "__TestCap50", { cooldown = 4, duration = 0.05, cooldownPolicy = { maxReduction = 0.5 } })()
	local low = dummy.GetCooldown("__TestCap50")
	t.assert(low > 1.9 and low <= 2, string.format("Teto 50%%: 4 s deveria virar 2 (deu %.2f)", low))

	t.wait(0.1)
	equip(dummy, "__TestCapDefault", { cooldown = 4, duration = 0.05 })()
	local default = dummy.GetCooldown("__TestCapDefault")
	local expected = 4 * (1 - StateTable.Enum.CooldownDefaults.maxReduction)
	t.assert(math.abs(default - expected) < 0.1, string.format("Sem declaração deveria valer o padrão (%.2f, deu %.2f)", expected, default))

	local _, issues = CooldownPolicy.Validate({ name = "x", cooldown = 1, cooldownPolicy = { maxReduction = 1.5 } }, {})
	t.assert(#issues == 1, "maxReduction fora de 0..1 deveria avisar")
	local full = CooldownPolicy.Validate({ name = "y", cooldown = 1, cooldownPolicy = { maxReduction = 1 } }, {})
	t.assert(full.maxReduction == 1, "maxReduction = 1 (sem teto) é válido")
	cleanup(dummy)
end)

run("D13 — ReduceCooldown encurta a contagem corrente", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	equip(dummy, "__TestReduce", { cooldown = 4, duration = 0.05 })()
	dummy.ReduceCooldown("__TestReduce", 1.5)
	local left = dummy.GetCooldown("__TestReduce")
	t.assert(left > 2.3 and left <= 2.5, string.format("4 s − 1,5 s deu %.2f", left))
	dummy.ReduceCooldown("__TestReduce", 10)
	t.assert(not dummy.HasCooldown("__TestReduce"), "Reduzir além do restante deveria deixar a skill pronta")
	cleanup(dummy)
end)

run("D13 — herança de cooldown (skill roubada): Copy e Move, com cargas", function(t)
	local owner = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local thief = makeDummy(CFrame.new(4, 5, 0), COMBAT)
	equip(owner, "__TestStolen", { cooldown = 4, duration = 0.05 })()
	t.wait(0.1)

	t.assert(CooldownPolicy.Transfer(owner, thief, "__TestStolen", "Copy"), "Transfer Copy falhou")
	local a, b = owner.GetCooldown("__TestStolen"), thief.GetCooldown("__TestStolen")
	t.assert(math.abs(a - b) < 0.05 and b > 3.5, string.format("Copy: dono %.2f, ladrão %.2f", a, b))

	local thief2 = makeDummy(CFrame.new(8, 5, 0), COMBAT)
	CooldownPolicy.Transfer(owner, thief2, "__TestStolen", "Move")
	t.assert(thief2.GetCooldown("__TestStolen") > 3.5, "Move não levou o cooldown")
	t.assert(not owner.HasCooldown("__TestStolen"), "Move deveria liberar o dono")

	-- Com cargas: o estado das cargas vai junto
	equip(owner, "__TestStolenCharges", { cooldown = 3, duration = 0.05, cooldownPolicy = { charges = 3 } })()
	CooldownPolicy.Transfer(owner, thief, "__TestStolenCharges", "Copy")
	local charges, max = thief.GetCooldownCharges("__TestStolenCharges")
	t.assert(charges == 2 and max == 3, string.format("Cargas herdadas: %s de %s", tostring(charges), tostring(max)))

	local wall = makeDummy(CFrame.new(12, 5, 0), { "Health" })
	t.assert(CooldownPolicy.Transfer(owner, wall, "__TestStolen") == false, "Transfer para entidade sem Combat deveria falhar")

	cleanup(owner)
	cleanup(thief)
	cleanup(thief2)
	cleanup(wall)
end)

--=============================================================================
--  D14 — BLOQUEIO DECLARADO (08/11/2026)
--=============================================================================

run("D14 — modos de bloqueio: Full, Flat, Percent e sem declaração", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local victim = makeDummy(CFrame.new(4, 5, 0), { "Health", "Status" })
	local hit = makeRunner(caster, "__TestBlockModes", { duration = 10 }, {})
	hit:start()
	local MODES = StateTable.Enum.BlockModes
	local function dealtWith(name, block)
		victim.ApplyStatus(blockStatus(name, { block = block }), { Duration = 10 })
		local _, dealt = victim.TakeDamage(StateTable.BuildContext(hit, 10))
		victim.RemoveStatus(name)
		return dealt
	end

	local full = dealtWith("__TestFull", { mode = MODES.Full })
	t.assert(full ~= 10 and (full == 0 or full == false or type(full) == "string"), "Full deixou passar: " .. tostring(full))
	t.assert(dealtWith("__TestFlat", { mode = MODES.Flat, value = 4 }) == 6, "Flat 4 em 10 deveria dar 6")
	t.assert(dealtWith("__TestPercent", { mode = MODES.Percent, value = 0.25 }) == 7.5, "Percent 0,25 em 10 deveria dar 7,5")
	t.assert(dealtWith("__TestUndeclared", nil) == 10, "Bloqueio sem declaração bloqueou (era implícito)")
	t.assert(dealtWith("__TestCustomNoTrigger", { mode = MODES.Custom }) == 10, "Custom sem onTrigger bloqueou")

	hit:endSkill(false)
	cleanup(caster)
	cleanup(victim)
end)

run("D14 — escudo de status: só Full barra status", function(t)
	local victim = makeDummy(CFrame.new(0, 5, 0), { "Health", "Status" })
	local MODES = StateTable.Enum.BlockModes
	local dotStatus = { data = { name = "__TestDotStatus2", traits = { Traits.DOT } }, callbacks = {} }

	victim.ApplyStatus(blockStatus("__TestFlatShield", { ShieldsFrom = { Traits.DOT }, block = { mode = MODES.Flat, value = 5 } }), { Duration = 10 })
	victim.ApplyStatus(dotStatus, { Duration = 5 })
	t.assert(victim.GetStatus("__TestDotStatus2") ~= nil, "Escudo Flat barrou um status (só Full barra)")
	victim.RemoveStatus("__TestDotStatus2")
	victim.RemoveStatus("__TestFlatShield")

	victim.ApplyStatus(blockStatus("__TestNoDeclShield", { ShieldsFrom = { Traits.DOT } }), { Duration = 10 })
	victim.ApplyStatus(dotStatus, { Duration = 5 })
	t.assert(victim.GetStatus("__TestDotStatus2") ~= nil, "Escudo sem declaração barrou o status")
	cleanup(victim)
end)

--=============================================================================
--  ITEM 4 — HIGIENE (08/11/2026)
--=============================================================================

run("F64 — Logger: nível por canal e WarnOnce", function(t)
	local Logger = require(ReplicatedStorage.Logger)
	local LogService = game:GetService("LogService")
	local seen = {}
	local conn = LogService.MessageOut:Connect(function(message)
		if message:find("__TestLog", 1, true) then table.insert(seen, message) end
	end)

	local log = Logger.Channel("__TestLog")
	Logger.SetLevel("Warn", "__TestLog")
	log.Debug("debug-escondido")
	log.Info("info-escondido")
	log.Warn("warn-visivel")
	log.WarnOnce("k", "once-1")
	log.WarnOnce("k", "once-2") -- repetição: só em Debug, escondida aqui
	Logger.SetLevel("Off", "__TestLog")
	log.Error("error-escondido")
	t.wait(0.2)
	conn:Disconnect()

	local joined = table.concat(seen, "\n")
	-- Busca literal (plain): "-" é quantificador nos padrões Lua
	local function has(text) return joined:find(text, 1, true) ~= nil end
	t.assert(not has("escondido"), "Mensagem abaixo do nível apareceu:\n" .. joined)
	t.assert(has("warn-visivel") and has("once-1"), "Warn não apareceu:\n" .. joined)
	t.assert(not has("once-2"), "WarnOnce repetiu em Warn")
	t.assert(has("[__TestLog]"), "Prefixo do canal ausente")
end)

run("F51 — dono de inscrição por entidade: limpar o combo de um atacante não apaga o do outro", function(t)
	local target = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local attackerA = makeDummy(CFrame.new(4, 5, 0), { "Health" })
	local attackerB = makeDummy(CFrame.new(8, 5, 0), { "Health" })
	local ownerA = StateTable.OwnerToken(attackerA, "__TestCombo")
	local ownerB = StateTable.OwnerToken(attackerB, "__TestCombo")
	t.assert(ownerA ~= ownerB, "Atacantes diferentes receberam o mesmo token")
	t.assert(StateTable.OwnerToken(attackerA, "__TestCombo") == ownerA, "O token da mesma entidade e tag mudou")

	local firedA, firedB = 0, 0
	local IN, Post = StateTable.Enum.Roles.IN, StateTable.Enum.Breakpoints.PostDamage
	target:Listen({ Role = IN, Breakpoint = Post, Owner = ownerA, Action = function() firedA += 1 end })
	target:Listen({ Role = IN, Breakpoint = Post, Owner = ownerB, Action = function() firedB += 1 end })
	target:UnsubscribeByOwner(ownerA) -- o novo Dash do A limpa o combo antigo dele
	target.TakeDamage(1)
	t.assert(firedA == 0, "O combo do A não saiu")
	t.assert(firedB == 1, "Limpar o combo do A apagou o do B")

	cleanup(target)
	cleanup(attackerA)
	cleanup(attackerB)
end)

--=============================================================================
--  DECISÕES D5–D17 (08/11/2026)
--=============================================================================

run("D5/F16 — loadout em camadas: o modo troca só os slots que declara", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local LAYERS = StateTable.Enum.LoadoutLayers
	local function skill(name) return { data = { name = name, cooldown = 0, duration = 0.1 }, callbacks = {} } end
	local base = { Slots = {
		[Intents.Id.Primary] = skill("__M1"),
		[Intents.Id.Dash] = skill("__Dash"),
		[Intents.Id.Ability1] = skill("__BaseA1"),
		[Intents.Id.Ultimate] = skill("__Ult"),
	} }
	dummy.ApplyLoadout(base)
	local function nameAt(slot)
		local s = dummy.GetSkillFromSlot(slot)
		return s and s.data.name
	end

	dummy.ApplyLoadout({ Slots = { [Intents.Id.Ability1] = skill("__DualA1") } }, LAYERS.WeaponMode)
	t.assert(nameAt(Intents.Id.Ability1) == "__DualA1", "A camada do modo não sobrescreveu o Ability1")
	t.assert(nameAt(Intents.Id.Primary) == "__M1" and nameAt(Intents.Id.Dash) == "__Dash" and nameAt(Intents.Id.Ultimate) == "__Ult",
		"O modo apagou slots que não declarou (F16)")

	-- Trocar de modo troca só a camada do modo
	dummy.ApplyLoadout({ Slots = { [Intents.Id.Ability1] = skill("__MergedA1") } }, LAYERS.WeaponMode)
	t.assert(nameAt(Intents.Id.Ability1) == "__MergedA1", "A reaplicação da camada não trocou o slot")
	t.assert(#dummy.GetLoadoutLayers() == 2, "Reaplicar a mesma camada criou outra")

	-- false esvazia o slot da base enquanto a camada existir
	dummy.ApplyLoadout({ Slots = { [Intents.Id.Dash] = false } }, "__Silencio")
	t.assert(nameAt(Intents.Id.Dash) == nil, "Slots[slot] = false não esvaziou o slot")
	dummy.RemoveLoadoutLayer("__Silencio")
	t.assert(nameAt(Intents.Id.Dash) == "__Dash", "Remover a camada não devolveu o slot da base")

	-- Sem a camada do modo, volta a base
	dummy.RemoveLoadoutLayer(LAYERS.WeaponMode)
	t.assert(nameAt(Intents.Id.Ability1) == "__BaseA1", "Sem a camada do modo a base não voltou")
	t.assert(dummy.RemoveLoadoutLayer(LAYERS.Base) == false, "A camada Base não pode sair")

	-- Um modo com o loadout inteiro: todos os slots na própria camada
	dummy.ApplyLoadout({ Slots = {
		[Intents.Id.Primary] = skill("__X1"), [Intents.Id.Dash] = skill("__X2"),
		[Intents.Id.Ability1] = skill("__X3"), [Intents.Id.Ultimate] = skill("__X4"),
	} }, LAYERS.WeaponMode)
	t.assert(nameAt(Intents.Id.Primary) == "__X1" and nameAt(Intents.Id.Ultimate) == "__X4", "Loadout inteiro na camada não valeu")
	cleanup(dummy)
end)

run("D9/F19 — grab da Ultimate: restante da skill, offset por alvo e colisão", function(t)
	local CollisionGroups = require(ServerScriptService.Modules.Physics.CollisionGroups)
	local caster = makeDummy(CFrame.new(0, 3, 0), COMBAT)
	local targetA = makeDummy(CFrame.new(0, 3, -6), { "Character", "Health", "Status", "Movement" })
	local targetB = makeDummy(CFrame.new(3, 3, -6), { "Character", "Health", "Status", "Movement" })
	local Ultimate = require(ServerStorage.DataBase.SkillDatabase.Schema.Ultimate)
	local skill = SkillFactory.GetSkill({ data = table.clone(Ultimate.data), callbacks = { onHit = Ultimate.callbacks.onHit } })
	skill.data.name = "__TestUlt"
	skill.data.duration = 2
	local runner = SkillRunner.new(skill, caster, "__TestUlt", StateTable.Enum.Types.Skill)
	runner:start()
	t.wait(0.5)

	runner:onHit({ target = targetA })
	runner:onHit({ target = targetB })
	runner:onHit({ target = targetA }) -- o mesmo alvo de novo não agarra duas vezes
	local function grabOf(entity)
		for _, force in entity:GetComponent(entity.ComponentKey.Movement).ActiveForces do
			if force.Data.Type == "UltGrab" then return force.Data end
		end
	end
	local grabA, grabB = grabOf(targetA), grabOf(targetB)
	t.assert(grabA and grabB, "Os dois alvos deveriam estar agarrados")
	t.assert(grabA.Duration <= 1.6 and grabA.Duration >= 1.2, string.format("Duração do grab deveria ser o restante (~1,5 s), foi %.2f", grabA.Duration))
	t.assert(grabA.FollowOffset ~= grabB.FollowOffset, "Os dois alvos receberam o mesmo offset (empilham)")
	local count = 0
	for _, force in targetA:GetComponent(targetA.ComponentKey.Movement).ActiveForces do
		if force.Data.Type == "UltGrab" then count += 1 end
	end
	t.assert(count == 1, "O mesmo alvo foi agarrado " .. count .. " vezes")
	t.assert(targetA.GetRoot().CollisionGroup == CollisionGroups.Grabbed, "O agarrado não entrou no grupo de colisão")
	t.assert(caster.GetRoot().CollisionGroup == CollisionGroups.Grabber, "O caster não entrou no grupo de colisão")

	runner:endSkill(true)
	t.assert(grabOf(targetA) == nil and grabOf(targetB) == nil, "O fim da skill não soltou os alvos")
	t.assert(targetA.GetRoot().CollisionGroup == "Default" and caster.GetRoot().CollisionGroup == "Default",
		"O grupo de colisão não foi restaurado")
	cleanup(caster)
	cleanup(targetA)
	cleanup(targetB)
end)

run("F19 — FollowTarget com feed-forward acompanha o líder sem atraso", function(t)
	local leader = makeDummy(CFrame.new(0, 3, 0), { "Character", "Health", "Movement" })
	local follower = makeDummy(CFrame.new(0, 3, 4), { "Character", "Health", "Movement" })
	leader.AddForce({ Type = "__TestRun", Duration = 1.5, Speed = 40, Direction = Vector3.new(1, 0, 0), Hard = true, IgnoreGravity = true })
	follower.AddForce({ Type = "__TestFollow", Duration = 1.5, Hard = true, IgnoreGravity = true, RequiresControl = false,
		FollowTarget = function() return leader.GetRoot() end, FollowOffset = Vector3.new(0, 0, 4),
		FollowResponsiveness = 16, FollowMaxSpeed = 40 })
	t.wait(1.0)
	local desired = leader.GetRoot().Position + Vector3.new(0, 0, 4)
	local err = ((follower.GetRoot().Position - desired) * Vector3.new(1, 0, 1)).Magnitude
	t.assert(err < 2, string.format("Seguidor %.1f studs atrás do ponto (antes ~10)", err))
	cleanup(leader)
	cleanup(follower)
end)

run("D10/F79 — hitbox da arma por skill: liga, desliga e entrega só à dona", function(t)
	local HitboxModule = require(ServerStorage.Modules.Combat.Hitbox.HitboxWrapper)
	local ShapecastHitbox = require(ServerStorage.Modules.Combat.Hitbox.ShapecastHitbox)
	-- Arma de teste: um model com a pasta Hitbox e uma parte com DmgPoint
	local weapon = Instance.new("Model")
	weapon.Name = "__TestWeaponF79"
	local folder = Instance.new("Folder")
	folder.Name = "Hitbox"
	folder.Parent = weapon
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Anchored = true
	blade.CFrame = zoneOrigin * CFrame.new(0, 5, 0)
	local point = Instance.new("Attachment")
	point.Name = ShapecastHitbox.Settings.Tag
	point.Parent = blade
	blade.Parent = folder
	weapon.Parent = workspace
	local owner = Instance.new("Model")
	owner.Parent = workspace
	local fakeEntity = { GetWeapon = function() return weapon end, Instance = owner }
	local wrapper = HitboxModule.new(fakeEntity)

	local hitsA, hitsB = 0, 0
	local skillA = { onHit = function() hitsA += 1 end }
	local skillB = { onHit = function() hitsB += 1 end }
	wrapper:AddOwner(skillA)
	wrapper:AddOwner(skillB)

	t.assert(wrapper:StartHitbox(2, skillA) == true, "Skill A não ligou a hitbox")
	t.assert(wrapper:StartHitbox(2, skillB) == true, "Skill B teve o StartHitbox recusado com a A ativa (F79)")
	wrapper:StopHitbox(skillA) -- a limpeza da A
	t.assert(not wrapper:IsHitboxActive(skillA), "A hitbox da A não desligou")
	t.assert(wrapper:IsHitboxActive(skillB), "O StopHitbox da A desligou a hitbox da B (F79)")

	-- Entrega: o acerto da sessão da B vai só para a B
	local target = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health" })
	local sessionB = wrapper.sessions[skillB]
	wrapper:_handleHit({ Instance = target.GetRoot(), Position = Vector3.zero, Normal = Vector3.yAxis, Distance = 0 },
		nil, wrapper.hitboxConfigs.Blade, sessionB, skillB)
	t.assert(hitsB == 1 and hitsA == 0, string.format("Acerto da B foi entregue: A=%d B=%d", hitsA, hitsB))

	-- Fim da skill B (RemoveOwner) desliga a sessão dela
	wrapper:RemoveOwner(skillB)
	t.assert(not wrapper:IsHitboxActive(), "Depois do fim das duas skills ainda há hitbox ativa")

	wrapper:DestroyHitbox()
	cleanup(target)
	weapon:Destroy()
	owner:Destroy()
end)

run("D7/F31/F33 — força Soft e caminhada proporcionais à massa; MassScaling = false volta ao fixo", function(t)
	local function body(cframe, size, configs)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = size
		root.CFrame = zoneOrigin * cframe
		root.Parent = model
		model.PrimaryPart = root
		model.Parent = workspace
		return DataManager.Create(model, { "Character", "Health", "Movement" }, configs)
	end
	local light = body(CFrame.new(-8, 3, 0), Vector3.new(2, 2, 1))
	-- Chefe 8×10×8 (massa ~448): com os números fixos, 2500 / 448 ≈ 5,6 studs/s², abaixo do atrito
	local boss = body(CFrame.new(8, 6, 0), Vector3.new(8, 10, 8))
	local fixed = body(CFrame.new(22, 6, 0), Vector3.new(8, 10, 8), { Movement = { MassScaling = false } })
	t.wait(0.5) -- assentar na plataforma
	local function pushed(entity)
		local start = entity.GetRoot().Position
		entity.AddForce({ Type = "__TestWind", Duration = 0.8, Speed = 20, Direction = Vector3.new(0, 0, -1), RequiresControl = false })
		return function() return ((entity.GetRoot().Position - start) * Vector3.new(1, 0, 1)).Magnitude end
	end
	local dl, db, df = pushed(light), pushed(boss), pushed(fixed)
	t.wait(0.9)
	local mLight, mBoss, mFixed = dl(), db(), df()
	t.assert(mBoss > 8, string.format("Vento Soft moveu o chefe %.1f studs (antes 0)", mBoss))
	t.assert(math.abs(mBoss - mLight) < 6, string.format("Leve %.1f e chefe %.1f deveriam andar parecido", mLight, mBoss))
	t.assert(mFixed < mBoss * 0.3, string.format("MassScaling = false deveria manter o chefe pesado (andou %.1f; com escala %.1f)", mFixed, mBoss))

	-- Caminhada: o chefe anda com a velocidade pedida
	local start = boss.GetRoot().Position
	boss.SetDirection(Vector3.new(1, 0, 0))
	t.wait(1)
	boss.SetDirection(Vector3.zero)
	local walked = ((boss.GetRoot().Position - start) * Vector3.new(1, 0, 1)).Magnitude
	t.assert(walked > 8, string.format("Chefe andou %.1f studs em 1 s (antes ~0)", walked))
	cleanup(light)
	cleanup(boss)
	cleanup(fixed)
end)

run("D8 — NPC com Humanoid usa o Humanoid", function(t)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = zoneOrigin * CFrame.new(0, 5, 0)
	root.Parent = model
	model.PrimaryPart = root
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.Parent = workspace
	local npc = DataManager.Create(model, { "Character", "Health", "Movement" })
	local wrapper = npc:GetComponent(npc.ComponentKey.Movement).MovementWrapper
	t.assert(wrapper._character:GetHumanoid() == humanoid, "O wrapper de character do NPC não pegou o Humanoid")
	t.assert(wrapper.Move ~= nil and wrapper._desiredWalk == nil, "O NPC com Humanoid ficou com o movimento sem Humanoid")
	npc.SetDirection(Vector3.new(1, 0, 0))
	t.wait(0.3)
	t.assert(humanoid.MoveDirection.Magnitude > 0.5, "O Humanoid não recebeu a direção de caminhada")
	cleanup(npc)
end)

run("D6/F41 — efeitos on-hit: bloqueado não aplica, 0 de dano aplica, skill e efeito sobrescrevem", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local victim = makeDummy(CFrame.new(4, 5, 0), { "Health", "Status" })
	local slow = { data = { name = "__TestSlow" }, callbacks = {} }
	local function hitWith(runnerData, damage)
		local runner = makeRunner(caster, "__TestEffHit" .. tostring(math.random(1e6)), runnerData, {})
		runner:start()
		victim.TakeDamage(StateTable.BuildContext(runner, damage))
		local applied = victim.GetStatus("__TestSlow") ~= nil
		victim.RemoveStatus("__TestSlow")
		runner:endSkill(false)
		return applied
	end

	-- 0 de dano com efeito: aplica (padrão onZeroDamage = true)
	t.assert(hitWith({ duration = 5, effects = { slow } }, 0) == true, "Hit de 0 de dano não aplicou o slow")
	-- Efeito que pede onZeroDamage = false
	t.assert(hitWith({ duration = 5, effects = { { status = slow, onZeroDamage = false } } }, 0) == false,
		"O efeito com onZeroDamage = false foi aplicado num hit de 0")

	-- Hit bloqueado (Full): não aplica por padrão; a skill pode pedir onBlocked = true
	victim.ApplyStatus(blockStatus("__TestEffBlock", { block = { mode = StateTable.Enum.BlockModes.Full } }), { Duration = 10 })
	t.assert(hitWith({ duration = 5, effects = { slow } }, 10) == false, "Hit 100% bloqueado aplicou o efeito")
	t.assert(hitWith({ duration = 5, effects = { slow }, effectPolicy = { onBlocked = true } }, 10) == true,
		"effectPolicy.onBlocked = true da skill não valeu")
	victim.RemoveStatus("__TestEffBlock")

	-- Hit normal: aplica
	t.assert(hitWith({ duration = 5, effects = { slow } }, 5) == true, "Hit normal não aplicou o efeito")
	cleanup(caster)
	cleanup(victim)
end)

run("D11/F43 — fórmula de dano: Defense multiplicativa, Armor subtrativa, DamageMult e TrueDamage", function(t)
	local Stats = StateTable.Enum.Stats
	local caster = makeDummy(CFrame.new(0, 5, 0), COMBAT)
	local victim = makeDummy(CFrame.new(4, 5, 0), { "Character", "Health", "Attributes" })
	local hit = makeRunner(caster, "__TestDmgFormula", { duration = 10 }, {})
	hit:start()
	local function dealt(amount, traits)
		local ctx = StateTable.BuildContext(hit, amount)
		if traits then ctx.traits = traits end
		local _, d = victim.TakeDamage(ctx)
		victim.Heal(1000)
		return d
	end
	local function near(a, b) return type(a) == "number" and math.abs(a - b) < 0.01 end

	victim.SetStat(Stats.Defense, 100)
	victim.SetStat(Stats.Armor, 0)
	t.assert(near(dealt(10), 5), "Defense 100 em 10 deveria dar 5")
	victim.SetStat(Stats.Defense, -100)
	t.assert(near(dealt(10), 15), "Defense −100 em 10 deveria dar 15")
	victim.SetStat(Stats.Defense, 0)
	victim.SetStat(Stats.Armor, 3)
	t.assert(near(dealt(10), 7), "Armor 3 em 10 deveria dar 7")
	victim.SetStat(Stats.Defense, 100)
	t.assert(near(dealt(10), 2), "Defense 100 e depois Armor 3 em 10 deveria dar 2")
	t.assert(near(dealt(10, { StateTable.Enum.Traits.TrueDamage }), 10), "TrueDamage deveria ignorar as proteções")

	-- DamageMult do atacante, pelo caminho real (runner:Damage → ApplyDamage)
	victim.SetStat(Stats.Defense, 0)
	victim.SetStat(Stats.Armor, 0)
	caster.SetStat(Stats.DamageMult, 2)
	local _, viaSkill = hit:Damage(victim, 10)
	t.assert(near(viaSkill, 20), "DamageMult 2 do atacante deveria dobrar o dano (" .. tostring(viaSkill) .. ")")

	hit:endSkill(false)
	cleanup(caster)
	cleanup(victim)
end)

run("D15/F56 — a barra de vida segue o corpo que o player dirige", function(t)
	local Players = game:GetService("Players")
	local player = Players:GetPlayers()[1]
	if not player or not player.Character or not player.Character:GetAttribute("EntityID") then
		t.log("sem player com entidade neste Play: teste pulado")
		return
	end
	local AC = require(ServerScriptService.Modules.GlobalAntiCheat)
	local function viewers(entity)
		return entity:GetComponent(entity.ComponentKey.Health):_HudViewers()
	end
	-- O corpo que o player dirige antes do teste (o nativo, ou um da GrandIntegrationDemo)
	local before = DataManager.Get(AC.GetControlledEntityId(player))
	t.assert(before and #viewers(before) == 1 and viewers(before)[1] == player, "Antes da possessão a barra deveria ser do corpo dirigido")
	local body = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Control" })
	t.assert(#viewers(body) == 0, "Corpo não possuído não deveria mandar vida para ninguém")

	local ControlModule = require(ServerScriptService.EntityData.Components.ControlComponent)
	local possessed = body.Possess({ Player = player })
	local onBody = viewers(body)
	local onBefore = viewers(before)
	local topDuring = ControlModule.GetPossessionOf(player)
	local released = body.Release()
	local topAfter = ControlModule.GetPossessionOf(player)
	t.log(string.format("possess=%s release=%s antes=%s corpo=%s roteadoDepois=%s topoDurante=%s topoDepois=%s",
		tostring(possessed), tostring(released), tostring(before.ID), tostring(body.ID),
		tostring(AC.GetControlledEntityId(player)), tostring(topDuring and topDuring.Entity.ID),
		tostring(topAfter and topAfter.Entity.ID)))

	t.assert(#onBody == 1 and onBody[1] == player, "Durante a possessão a barra não seguiu o corpo controlado")
	t.assert(#onBefore == 0, "Durante a possessão o corpo anterior ainda mandava a vida dele")
	t.assert(#viewers(before) == 1, "Depois do Release a barra não voltou ao corpo anterior")
	cleanup(body)
end)

run("F94 — erro em onRecast/onRelease/onHit/onTrigger vira warn e a skill segue", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Health" })
	local boom = function() error("[FW-DEBUG] callback quebrado de propósito (teste F94)") end
	local runner = makeRunner(dummy, "__TestEventErrors", { duration = 5 }, {
		onRecast = boom, onRelease = boom, onHit = boom, onTrigger = boom,
	})
	runner:start()
	local ok, err = pcall(function()
		runner:Recast()
		runner:Release({})
		runner:onHit({})
		runner:TriggerAction({})
	end)
	t.assert(ok, "Erro de callback de evento escapou: " .. tostring(err))
	t.assert(not runner:IsEnded(), "Erro de callback de evento encerrou a skill")
	runner:endSkill(false)
	cleanup(dummy)
end)

run("F57 — o ControlStateChanged leva o model do corpo roteado", function(t)
	local Players = game:GetService("Players")
	local player = Players:GetPlayers()[1]
	if not player or not player.Character or not player.Character:GetAttribute("EntityID") then
		t.log("sem player com entidade neste Play: teste pulado")
		return
	end
	local AC = require(ServerScriptService.Modules.GlobalAntiCheat)
	local _, routed, _, subject = AC._ControlStatePayload(player)
	local core = DataManager.Get(routed)
	t.assert(core and subject == core.Instance, "O payload não trouxe o model do corpo roteado")
end)

task.wait(1)
TestHarness.Summary()
platform:Destroy()

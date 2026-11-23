/* Referência da API: módulos de combate, input, física/rede e cliente */
(function () {
  function M(group, name, title, call, desc, args, ret, more) {
    var f = { name: name, title: title, call: call, desc: desc, args: args || [], ret: ret };
    for (var k in more || {}) f[k] = more[k];
    DOCS.fn(group, f);
  }

  // ================================================================ COMBATE
  DOCS.page({ id: "api.combate", parent: "api", title: "Combate", kw: "combate módulos", lead: "Regras transversais, eventos, zonas, hitbox solta, minions e combo.", html: "" });

  // ---------------------------------------------------------------- StateTable
  DOCS.group({
    id: "api.StateTable", parent: "api.combate", title: "StateTable",
    kw: "statetable status states actionstates enum helper relation canaffect effectowner ownertoken regras",
    src: "ServerStorage/Modules/Combat/StateTable",
    lead: "Dado central (status, estados, ActionStates, Enum) e as regras transversais do Helper (cadeia, dono do efeito, time, bloqueio, efeitos, mitigação).",
    html: `
${C(`local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)`)}
${T(["Tabela", "O quê"], [
  ["<code>StateTable.Status</code>", "Todos os status de <code>Status/Buffs</code> e <code>Status/Debuffs</code>, por nome do módulo."],
  ["<code>StateTable.States</code>", "Os estados (Stun, Root, Silence, NoControl)."],
  ["<code>StateTable.ActionStates</code>", "<code>Self.selfCast</code>, <code>Self.globalCast</code>, <code>Out.cast</code>, <code>Out.globalCast</code>, <code>LockedCast</code>."],
  ["<code>StateTable.Enum</code>", "O Enum do framework (" + L("enum") + ")."],
  ["<code>StateTable.ImmunityRules</code>", "Mapa de imunidades, calculado uma vez."],
])}`,
  });
  var G = "api.StateTable";
  M(G, "Relation", "StateTable.Relation", "StateTable.Relation(a, b)", "Relação entre duas entidades.", [["a", "EntityCore", ""], ["b", "EntityCore", ""]], "<code>Enum.Relations</code>: Self, Ally, Enemy ou Neutral.", { see: ["conceitos.alvos"] });
  M(G, "CanAffect", "StateTable.CanAffect", "StateTable.CanAffect(source, target, affects?)", "A ação de <code>source</code> afeta <code>target</code>? Vale o <code>data.affects</code> da skill sobre <code>Enum.AffectsDefaults</code>.",
    [["source", "runner | self | EntityCore | nil", "Runner/self de skill (vale o dono do efeito e o affects dele), entidade, ou nil (ambiente: afeta todos)."], ["target", "EntityCore", ""], ["affects", "table?", "Sobrescreve o affects."]], "<code>boolean</code>.");
  M(G, "AffectsFilter", "StateTable.AffectsFilter", "StateTable.AffectsFilter(source, affects?)", "Predicado pronto para <code>AreaEffect:SetFilter</code>.", null, "<code>(entity) -> boolean</code>.");
  M(G, "EffectOwner", "StateTable.EffectOwner", "StateTable.EffectOwner(source)", "Dono de um efeito: sobe o <code>Source</code> dos status até um runner de skill. É quem recebe OUT.OnDamage/OnDeath/OnHeal.", [["source", "runner | self | nil", ""]], "<code>EntityCore?</code>.");
  M(G, "OwnerToken", "StateTable.OwnerToken", "StateTable.OwnerToken(entity, tag)", "Token de Owner por entidade: sempre o mesmo para o par (entidade, tag). Use em vez de string.", [["entity", "EntityCore", ""], ["tag", "string", ""]], "Token.");
  M(G, "HasTrait", "StateTable.HasTrait", "StateTable.HasTrait(data, trait)", "O data declara a trait?", [["data", "table", "data de skill/status."], ["trait", "string", ""]], "<code>boolean</code>.");
  M(G, "ResolveRunner", "StateTable.ResolveRunner", "StateTable.ResolveRunner(runnerOrSelf)", "Normaliza o self de skill para o runner (para comparar identidade).", null, "runner.");
  M(G, "IsDead", "StateTable.IsDead", "StateTable.IsDead(entity)", "Morta do ponto de vista do motor (sem Health, nunca).", null, "<code>boolean</code>.");
  M(G, "MitigateDamage", "StateTable.MitigateDamage", "StateTable.MitigateDamage(damage, getStat, traits)", "Aplica as proteções de <code>Enum.DamageMitigation</code> (usado pelo TakeDamage).", null, "Dano mitigado (≥ 0).");
  M(G, "ResolveBlock", "StateTable.ResolveBlock", "StateTable.ResolveBlock(data, ctx)", "Resultado do <code>data.block</code> declarado.", null, "Dano novo, <code>true</code> (status barrado) ou <code>nil</code>.");
  M(G, "ResolveEffect", "StateTable.ResolveEffect", "StateTable.ResolveEffect(entry, sourceData)", "Resolve um efeito on-hit: o status e se vale para hit bloqueado/0 de dano.", null, "status, onBlocked, onZeroDamage.");
  M(G, "RunInChain", "StateTable.RunInChain", "local ran, ... = StateTable.RunInChain(label, subject, fn, ...)", "Roda <code>fn</code> como um elo da cadeia síncrona: acima de MAX_RECURSION, adia para o próximo frame (ou recusa). Use em ações do jogo que geram dano/status em cadeia.",
    [["label", "string", "Para o warn."], ["subject", "any", "ID ou nome (warn)."], ["fn", "function", ""]], "<code>true, retornos de fn</code>; ou <code>false, Enum.ChainOutcomes.X</code>.", { see: ["conceitos.cadeias"] });
  M(G, "RunInChainReserving", "StateTable.RunInChainReserving", "StateTable.RunInChainReserving(levels, label, subject, fn, ...)", "Igual, reservando <code>levels</code> níveis (ação que chama outra ação da cadeia por dentro).", null, "Igual ao RunInChain.");
  M(G, "GetDeferredCount", "StateTable.GetDeferredCount", "StateTable.GetDeferredCount()", "Ações esperando na fila da cadeia (diagnóstico).", null, "<code>number</code>.");
  M(G, "BuildContext", "StateTable.BuildContext", "StateTable.BuildContext(source, amount, parentContext?)", "Monta um HitContext (traits e effects do data do source, dono, direção, Lineage).", null, "HitContext.");
  M(G, "ResolveDeathPolicy", "StateTable.ResolveDeathPolicy", "StateTable.ResolveDeathPolicy(config, key)", "Regra de morte: o valor do config ou <code>Enum.DeathDefaults[key]</code>.", null, "<code>boolean</code>.");
  M(G, "BuildEffect", "StateTable:BuildEffect", "StateTable:BuildEffect(status, callbackName, fn)", "Clona um status com um callback injetado (variação de um status sem novo módulo).", [["status", "table", ""], ["callbackName", "string", "Ex.: \"onTrigger\"."], ["fn", "function", ""]], "O status clonado.");

  // ---------------------------------------------------------------- TriggerSet
  DOCS.group({
    id: "api.TriggerSet", parent: "api.combate", title: "TriggerSet",
    kw: "triggerset pubsub subscription inscrição emit fork",
    src: "ServerStorage/Modules/Combat/TriggerSet",
    lead: "O pub/sub por entidade por trás de Listen/Emit. Você usa pelo EntityCore; estas são as regras exatas.",
    html: "",
  });
  DOCS.page({
    id: "api.TriggerSet.Subscription", parent: "api.TriggerSet", order: 1, title: "Formato de uma inscrição",
    kw: "subscription inscrição listen formato role breakpoint query priority owner limit ttd inherit action",
    lead: "Types.Subscription: o que Listen, self:Listen e ListenWorld aceitam.",
    html: `
${C(`
{
    Role = "IN" | "OUT",               -- Enum.Roles
    Breakpoint = string,               -- Enum.Breakpoints (ou um seu)
    Action = function(ctx, ...) end,
    Query = { All = {}, Any = {}, None = {} }?,   -- por traits do ctx
    Priority = number?,                -- maior roda antes; empate = ordem de inscrição
    Owner = any?,                      -- UnsubscribeByOwner; use StateTable.OwnerToken
    TTD = number?,                     -- segundos até expirar
    TTDInheritRemaining = boolean?,    -- filho herda o tempo restante, não o TTD cheio
    Limit = { Max = number, OnExhaust = "Remove" | "Disable", Scope = "Holder" | "Branch" | "Tree" }?,
    Inherit = { Generations = number }?,
}
`)}
<ul>
  <li>A Action roda protegida: um erro vira warn com traceback e os outros listeners seguem.</li>
  <li>A lista é copiada antes do Emit: inscrever ou desinscrever dentro de uma Action não pula ninguém.</li>
  <li>TTD é conferido na hora do Emit e do Fork.</li>
  <li>O ctx é o mesmo objeto para todos os listeners do Emit: o que um muda (damage, inherited, cancelled) o próximo vê.</li>
</ul>
<p>Detalhes de Inherit/Limit em ${L("conceitos.heranca")}.</p>`,
  });
  G = "api.TriggerSet";
  M(G, "Subscribe", "TriggerSet:Subscribe", "local unsubscribe = set:Subscribe(sub)", "Inscreve (inserção ordenada por Priority).", null, "<code>unsubscribe()</code>.");
  M(G, "Unsubscribe", "TriggerSet:Unsubscribe", "set:Unsubscribe(sub)", "Remove uma inscrição.", null, null);
  M(G, "UnsubscribeByOwner", "TriggerSet:UnsubscribeByOwner", "set:UnsubscribeByOwner(owner)", "Remove todas com o Owner.", null, null);
  M(G, "HasAny", "TriggerSet:HasAny", "set:HasAny(role, breakpoint)", "Há inscrição neste canal?", null, "<code>boolean</code>.");
  M(G, "Emit", "TriggerSet:Emit", "set:Emit(role, breakpoint, ctx, ...)", "Dispara as Actions que casam (TTD, Query, Limit).", null, null);
  M(G, "Fork", "TriggerSet:Fork", "local filho = set:Fork()", "Cópia das inscrições com Inherit (Generations − 1), respeitando o Scope do Limit.", null, "TriggerSet.");

  // ---------------------------------------------------------------- TraitQuery
  DOCS.group({ id: "api.TraitQuery", parent: "api.combate", title: "TraitQuery", kw: "traitquery query filtro traits all any none", src: "ServerStorage/Modules/Combat/TraitQuery", lead: "O filtro por traits das inscrições.", html: "" });
  M("api.TraitQuery", "Match", "TraitQuery.Match", "TraitQuery.Match(query, traits)", "A lista de traits satisfaz a query? None: nenhuma; All: todas; Any: pelo menos uma. Sem query: sempre.",
    [["query", "TraitQuery?", "<code>{ All?, Any?, None? }</code>."], ["traits", "{string}?", ""]], "<code>boolean</code>.");

  // ---------------------------------------------------------------- AreaEffect
  DOCS.group({
    id: "api.AreaEffect", parent: "api.combate", title: "AreaEffect",
    kw: "areaeffect zona area aoe poll onenter onstay onexit filtro",
    src: "ServerStorage/Modules/Combat/AreaEffect",
    lead: "Zona por consulta de forma (caixa ou esfera) numa taxa fixa. Callbacks recebem (entity, zona). Os métodos de callback e filtro devolvem a zona (encadeáveis).",
    html: `${C(`local AreaEffect = require(game.ServerStorage.Modules.Combat.AreaEffect)`)}<p>Campos: <code>zona.ID</code> (único), <code>zona.Inside</code> (<code>{ [EntityCore] = true }</code>), <code>zona.Active</code>. Veja ${L("conceitos.zonas")}.</p>`,
  });
  G = "api.AreaEffect";
  M(G, "new", "AreaEffect.new", "local zona = AreaEffect.new(cframeProvider, shape, size, pollRate?)", "Cria a zona (parada).",
    [["cframeProvider", "() -> CFrame", "Lido a cada poll (zona que se move)."], ["shape", "string", "\"Box\" ou \"Sphere\"."], ["size", "Vector3 | number", "Tamanho (Box) ou raio (Sphere)."], ["pollRate", "number?", "Hz (padrão 10)."]], "AreaEffect.");
  M(G, "OnEnter", "zona:OnEnter", "zona:OnEnter(fn)", "Ao entrar.", [["fn", "function", "<code>(entity, zona)</code>."]], "A zona.");
  M(G, "OnStay", "zona:OnStay", "zona:OnStay(fn)", "A cada poll com a entidade dentro.", [["fn", "function", "<code>(entity, zona)</code>."]], "A zona.");
  M(G, "OnExit", "zona:OnExit", "zona:OnExit(fn)", "Ao sair (também no Stop).", [["fn", "function", "<code>(entity, zona)</code>."]], "A zona.");
  M(G, "SetFilter", "zona:SetFilter", "zona:SetFilter(fn?)", "Só entidades com <code>fn(entity) == true</code> entram.", [["fn", "function?", ""]], "A zona.");
  M(G, "Start", "zona:Start", "zona:Start()", "Começa a consultar.", null, null);
  M(G, "Stop", "zona:Stop", "zona:Stop()", "Para; quem estava dentro sai pelo OnExit.", null, null);

  // ---------------------------------------------------------------- AreaBehaviors
  DOCS.group({ id: "api.AreaBehaviors", parent: "api.combate", title: "AreaBehaviors", kw: "areabehaviors vento empurrar puxar força de zona directionalforce", src: "ServerStorage/Modules/Combat/AreaBehaviors", lead: "Comportamentos prontos para zonas.", html: C(`local AreaBehaviors = require(game.ServerStorage.Modules.Combat.AreaBehaviors)`) });
  G = "api.AreaBehaviors";
  M(G, "BindDirectionalForce", "AreaBehaviors.BindDirectionalForce", "AreaBehaviors.BindDirectionalForce(zona, direction, speed, forceType, opts?)",
    "Liga uma força à zona: vale da entrada até a saída (inclusive no Stop). Não sobra empurrão depois da borda.",
    [["zona", "AreaEffect", ""], ["direction", "Vector3 | () -> Vector3", ""], ["speed", "number", ""], ["forceType", "string", "Type da Force (padrão \"AreaWind\")."], ["opts", "table?", "<code>{ Key?, Duration?, Hard?, RequiresControl?, MaxForce? }</code>."]], "A zona.",
    { see: ["receitas.vento"] });
  M(G, "DirectionalForce", "AreaBehaviors.DirectionalForce", "AreaBehaviors.DirectionalForce(entity, direction, speed, forceType, opts?)",
    "Aplica (renova pela Key) uma força de ambiente numa entidade. Externa: empurra mesmo sem canMove. Solta, sem zona, dura o Duration (0,5 s).", null, "ID da Force.");

  // ---------------------------------------------------------------- Hitbox solta
  DOCS.group({
    id: "api.HitboxSpawner", parent: "api.combate", title: "HitboxSpawner",
    kw: "hitboxspawner hitbox solta projétil carrier spawn",
    src: "ServerStorage/Modules/Combat/Hitbox/HitboxSpawner",
    lead: "Hitbox desacoplada da arma (projétil, área). Cria um carrier com Attachments DmgPoint e o ShapecastHitbox em cima.",
    html: `<p>O hitbox (ShapecastHitbox) tem <code>:SetCastData({ CastType, Radius, Size })</code>, <code>:OnHit(fn(result, segment))</code>, <code>:OnUpdate(fn(dt))</code>, <code>:OnStopped(fn)</code>, <code>:HitStart(duração)</code> e <code>:HitStop()</code>.</p>`,
  });
  G = "api.HitboxSpawner";
  M(G, "Spawn", "HitboxSpawner.Spawn", "local hitbox, carrier = HitboxSpawner.Spawn(caster?, cframe, offsets?, params?)", "Cria hitbox + carrier. Guarde os dois.",
    [["caster", "EntityCore?", "Excluído do filtro padrão."], ["cframe", "CFrame", "Posição inicial."], ["offsets", "{CFrame}?", "Pontos de dano locais (padrão: 1 na origem)."], ["params", "RaycastParams?", "Filtro próprio."]], "hitbox, carrier.");
  M(G, "SetCarrierCFrame", "HitboxSpawner.SetCarrierCFrame", "HitboxSpawner.SetCarrierCFrame(carrier, cframe)", "Move o carrier (use dentro de <code>hitbox:OnUpdate</code>).", null, null);
  M(G, "Cleanup", "HitboxSpawner.Cleanup", "HitboxSpawner.Cleanup(hitbox, carrier)", "Destrói hitbox e carrier juntos (sem isso o carrier vaza).", null, null);
  M(G, "BuildDefaultFilter", "HitboxSpawner.BuildDefaultFilter", "HitboxSpawner.BuildDefaultFilter(caster?, extraExclude?)", "RaycastParams que exclui o caster e extras.", null, "RaycastParams.");

  DOCS.group({ id: "api.HitboxBehaviors", parent: "api.combate", title: "HitboxBehaviors", kw: "hitboxbehaviors mover crescer homing linear expand", src: "ServerStorage/Modules/Combat/Hitbox/HitboxBehaviors", lead: "Funções de update para <code>hitbox:OnUpdate</code>. Direção/velocidade aceitam valor fixo ou função (elapsed, duration), como nas Forces.", html: "" });
  G = "api.HitboxBehaviors";
  M(G, "LinearMove", "Behaviors.LinearMove", "hitbox:OnUpdate(Behaviors.LinearMove(carrier, direction, speed, duration))", "Move em linha reta.", null, "Função de update.");
  M(G, "Homing", "Behaviors.Homing", "hitbox:OnUpdate(Behaviors.Homing(carrier, getTarget, speed, turnRate?))", "Persegue <code>getTarget()</code>; sem alvo, mantém a última direção. Sem turnRate: perfeito.", null, "Função de update.");
  M(G, "ExpandUniform", "Behaviors.ExpandUniform", "hitbox:OnUpdate(Behaviors.ExpandUniform(hitbox, rate, maxRadius?))", "Cresce o raio (Spherecast).", null, "Função de update.");
  M(G, "ExpandDirectional", "Behaviors.ExpandDirectional", "hitbox:OnUpdate(Behaviors.ExpandDirectional(hitbox, axis, rate, maxSize?))", "Cresce o Size num eixo local (\"X\"|\"Y\"|\"Z\", Blockcast).", null, "Função de update.");

  DOCS.group({ id: "api.HitboxPresets", parent: "api.combate", title: "HitboxPresets", kw: "hitboxpresets preset projétil teleguiado anel cone", src: "ServerStorage/Modules/Combat/Hitbox/HitboxPresets", lead: "Formas prontas (Spawner + Behaviors), que já se limpam no fim. A skill referencia Presets.X; não monta spawner+behavior na mão.", html: "" });
  G = "api.HitboxPresets";
  M(G, "HomingBolt", "Presets.HomingBolt", "local hitbox, carrier = Presets.HomingBolt(caster, origin, getTarget, speed, radius, duration, turnRate?)", "Projétil teleguiado (Spherecast).", null, "hitbox, carrier.", { see: ["receitas.projetil"] });
  M(G, "ExpandingRing", "Presets.ExpandingRing", "local lista = Presets.ExpandingRing(caster, center, count, startRadius, expandRate, sphereRadius, duration)", "Anel de esferas abrindo a partir do centro (onda de choque).", null, "<code>{ { hitbox, carrier } }</code>: conecte OnHit em cada.");
  M(G, "ExpandingCone", "Presets.ExpandingCone", "local hitbox, carrier = Presets.ExpandingCone(caster, originCFrame, axis, expandRate, maxSize, duration)", "Leque parado que abre num eixo (corte).", null, "hitbox, carrier.");

  // ---------------------------------------------------------------- MinionFactory / ComboWindow
  DOCS.group({
    id: "api.MinionFactory", parent: "api.combate", title: "MinionFactory",
    kw: "minionfactory minion lacaio invocar summon blueprint spawn",
    src: "ServerStorage/Modules/MinionFactory",
    lead: "Invoca entidades a partir de blueprints (pasta Blueprints/ ou Register). Não decide componentes por você; não substitui o DataManager.Create.",
    html: C(`
-- MinionFactory/Blueprints/Lobo.luau
return {
    Components = { "Character", "Health", "Movement", "Status", "AI" },
    Configs = { Health = { MaxHP = 40 }, AI = { Brain = brainDoLobo } },
    Model = game.ServerStorage.Assets.Lobo,          -- clonado e posicionado
    -- ou BuildModel = function(cframe) return model end
}
`),
  });
  M("api.MinionFactory", "Spawn", "MinionFactory.Spawn", "local minion = MinionFactory.Spawn(name, cframe, parent?)", "Monta o Model e a entidade. Com <code>parent</code>, o minion herda as reações com Inherit.",
    [["name", "string", "Blueprint."], ["cframe", "CFrame", "Onde."], ["parent", "EntityCore?", "Invocador."]], "<code>EntityCore?</code>.", { see: ["receitas.minion"] });
  M("api.MinionFactory", "Register", "MinionFactory.Register", "MinionFactory.Register(name, blueprint)", "Registra um blueprint em runtime.", null, null);

  DOCS.group({ id: "api.ComboWindow", parent: "api.combate", title: "ComboWindow", kw: "combowindow combo janela marcar consumir sequência", src: "ServerStorage/DataBase/SkillDatabase/BaseSkills/ComboWindow", lead: "Janela de combo curta entre skills, sem acoplar A e B: A marca, B lê e consome. É um status interno por baixo.", html: C(`local ComboWindow = require(game.ServerStorage.DataBase.SkillDatabase.BaseSkills).ComboWindow`) });
  G = "api.ComboWindow";
  M(G, "Mark", "ComboWindow.Mark", "ComboWindow.Mark(entity, marker, window, payload?, source?)", "Abre a janela por <code>window</code> segundos.", [["entity", "EntityCore", ""], ["marker", "string", "Nome."], ["window", "number", "Segundos."], ["payload", "table?", ""], ["source", "runner?", ""]], "ID ou nil.", { see: ["receitas.combo"] });
  M(G, "Consume", "ComboWindow.Consume", "local payload = ComboWindow.Consume(entity, marker)", "Fecha a janela e devolve o payload.", null, "<code>table?</code>: o payload (<code>{}</code> se a janela foi aberta sem payload), ou nil se fechada.");
  M(G, "Peek", "ComboWindow.Peek", "ComboWindow.Peek(entity, marker)", "A janela está aberta?", null, "<code>boolean</code>.");

  // ================================================================ INPUT
  DOCS.page({ id: "api.input", parent: "api", title: "Input", kw: "input módulos", lead: "Intenções, gestos, cliente e bindings.", html: "" });

  DOCS.group({
    id: "api.Intents", parent: "api.input", title: "Intents",
    kw: "intents intent id kind gesture defaults skillorder inputevent payload",
    src: "ReplicatedStorage/Input/Intents",
    lead: "O dicionário de intenções (cliente e servidor) e o único construtor de InputEvent.",
    html: `
${T(["Tabela", "Valores"], [
  ["<code>Intents.Id</code>", "Primary, Dash, Ability1, Ability2, Ability3, Ultimate."],
  ["<code>Intents.Kind</code>", "Activate, Release."],
  ["<code>Intents.Gesture</code>", "Press, Tap, DoubleTap, Hold."],
  ["<code>Intents.Defaults</code>", "HoldTime 0,3 s; DoubleTapWindow 0,25 s; TapMaxTime 0,35 s."],
  ["<code>Intents.SkillOrder</code>", "Ordem dos slots para loadout em lista."],
])}
${C(`
-- InputEvent (imutável)
{ Intent = "Primary", Kind = "Activate", Gesture = "Hold", HeldTime = 0.42, Target = "Entity_123", Point = Vector3 }
`)}`,
  });
  G = "api.Intents";
  M(G, "NewEvent", "Intents.NewEvent", "Intents.NewEvent(intent, kind, gesture?, heldTime?, payload?)", "Cria um InputEvent (NPC, script, teste).", [["intent", "string", ""], ["kind", "string", ""], ["gesture", "string?", ""], ["heldTime", "number?", ""], ["payload", "InputPayload?", "<code>{ Target?, Point? }</code> já validado."]], "InputEvent congelado.");
  M(G, "IsButton", "Intents.IsButton", "Intents.IsButton(id)", "É uma intent conhecida? (aceita qualquer valor)", null, "<code>boolean</code>.");
  M(G, "SanitizePayload", "Intents.SanitizePayload", "Intents.SanitizePayload(raw)", "Valida payload da rede: Target string 1–64 caracteres, Point Vector3 finito com |coord| ≤ 1e6.", null, "InputPayload ou <code>nil</code>.");

  DOCS.group({ id: "api.GestureResolver", parent: "api.input", title: "GestureResolver", kw: "gestureresolver gesto tap hold doubletap máquina de estados", src: "ReplicatedStorage/Input/GestureResolver", lead: "Máquina de estados dos gestos de uma intent. Não conhece Roblox, player nem skill: Press/Release com tempo entram, eventos saem.", html: "" });
  G = "api.GestureResolver";
  M(G, "new", "GestureResolver.new", "local r = GestureResolver.new(intent, sink)", "Um resolver por intent.", [["intent", "string", ""], ["sink", "(InputEvent) -> ()", "Recebe cada evento."]], "Resolver.");
  M(G, "Normalize", "GestureResolver.Normalize", "GestureResolver.Normalize(spec)", "Converte o data.input em config interna (nil = Press cru).", null, "Config?.");
  M(G, "Press", "resolver:Press", "r:Press(now, cfg, payload?)", "Botão desceu.", null, null);
  M(G, "Release", "resolver:Release", "r:Release(now, payload?)", "Botão subiu (o payload do Release substitui o do Press).", null, null);
  M(G, "Cancel", "resolver:Cancel", "r:Cancel(now, silent?)", "Encerra o ciclo (morte, respawn). silent = sem Release.", null, null);

  DOCS.group({ id: "api.InputService", parent: "api.input", title: "InputService (cliente)", kw: "inputservice cliente client bindings botão rebind payload provider mobile", src: "StarterPlayer/StarterPlayerScripts/InputService", lead: "Traduz input físico (teclado, mouse, gamepad, botões de tela) em Press/Release de intent e manda ao servidor.", html: C(`local InputService = require(game.Players.LocalPlayer.PlayerScripts.InputService)`) });
  G = "api.InputService";
  M(G, "SetPayloadProvider", "InputService.SetPayloadProvider", "InputService.SetPayloadProvider(fn?)", "Quem fornece alvo/ponto a cada envio.", [["fn", "(intent) -> InputPayload?", "nil desliga."]], null, { see: ["receitas.mira"] });
  M(G, "Press", "InputService.Press", "InputService.Press(intent, source, payload?)", "Aperta uma intent por código (botão customizado).", [["intent", "string", ""], ["source", "any", "Valor único da fonte (para casar com o Release)."], ["payload", "table?", ""]], null);
  M(G, "Release", "InputService.Release", "InputService.Release(intent, source, payload?)", "Solta.", null, null);
  M(G, "ReleaseAll", "InputService.ReleaseAll", "InputService.ReleaseAll()", "Solta tudo (alt-tab, troca de personagem).", null, null);
  M(G, "Rebind", "InputService.Rebind", "InputService.Rebind(intent, codes)", "Troca as teclas de uma intent em runtime (tela de remap).", [["codes", "{EnumItem}", "KeyCode/UserInputType."]], null);
  M(G, "Init", "InputService.Init", "InputService.Init()", "Liga o serviço (o InputController já chama).", null, null);

  DOCS.page({
    id: "api.InputConfig", parent: "api.input", title: "InputConfig",
    kw: "inputconfig bindings teclas atalhos controle gamepad",
    src: "ReplicatedStorage/Config/InputConfig",
    lead: "Tabela única de bindings: intent → lista de códigos (KeyCode e UserInputType misturados).",
    html: C(`
return {
    Bindings = {
        [Id.Primary] = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonX },
        [Id.Dash] = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB },
        [Id.Ability1] = { Enum.KeyCode.One, Enum.KeyCode.ButtonR1 },
        [Id.Ability2] = { Enum.KeyCode.Two, Enum.KeyCode.ButtonR2 },
        [Id.Ability3] = { Enum.KeyCode.Three, Enum.KeyCode.ButtonL1 },
        [Id.Ultimate] = { Enum.KeyCode.Four, Enum.KeyCode.ButtonY },
    },
    ButtonTag = "InputButton",          -- tag dos botões de tela
    ButtonIntentAttribute = "Intent",   -- atributo com a intent do botão
}
`) + "<p>Aqui <code>Enum</code> é o do Roblox.</p>",
  });

  // ================================================================ FÍSICA E REDE
  DOCS.page({ id: "api.fisica", parent: "api", title: "Física e rede", kw: "física rede módulos", lead: "Configuração de movimento, atraso de visão, grupos de colisão e o anti-cheat.", html: "" });

  DOCS.page({
    id: "api.Settings", parent: "api.fisica", title: "Physics/Settings",
    kw: "settings configurações física força hard soft massa anticheat validação latência teleporte smoothing client view lag",
    src: "ServerScriptService/Modules/Physics/Settings",
    lead: "Todos os números de movimento, Forces, validação de movimento e atraso de rede.",
    html: T(["Chave", "Padrão", "O quê"], [
      ["<code>Hard_Force_Strength</code>", "1e6", "Força por eixo de uma Force Hard (inquebrável)."],
      ["<code>Soft_Force_Strength</code>", "2500", "Força Soft quando a escala por massa está desligada."],
      ["<code>Force_Mass_Scaling</code>", "true", "Soft e caminhada de NPC sem Humanoid proporcionais à massa."],
      ["<code>Soft_Force_Acceleration</code>", "250", "studs/s² da Soft (com massa)."],
      ["<code>Humanoid_Soft_Force_Acceleration</code>", "2500", "Soft em corpo com Humanoid (vence o controlador dele)."],
      ["<code>NPC_Walk_Acceleration</code>", "200", "Caminhada de NPC sem Humanoid (com massa)."],
      ["<code>NPC_Walk_Force</code>", "2000", "Caminhada fixa (MassScaling = false)."],
      ["<code>Face_Direction_Responsiveness</code>", "25", "Rigidez do giro com FaceDirection."],
      ["<code>Teleport_Smoothing_Recovery_Seconds</code>", "0.25", "Câmera engolindo salto de posição (cliente)."],
      ["<code>Teleport_Smoothing_Snap_Threshold</code>", "6", "Studs a partir dos quais é salto."],
      ["<code>Movement_Validation_Enabled</code>", "true", "Validação de movimento do player."],
      ["<code>Movement_Speed_Tolerance</code>", "1.25", "Multiplicador do WalkSpeed do servidor."],
      ["<code>Movement_Speed_Slack</code>", "2", "Folga (studs/s)."],
      ["<code>Movement_Burst_Seconds</code>", "0.25", "Crédito máximo (s de velocidade permitida)."],
      ["<code>Movement_Excess_Limit</code>", "4", "Excesso tolerado antes de corrigir (studs)."],
      ["<code>Movement_Latency_Window</code>", "0.35", "Quanto uma velocidade maior segue valendo depois de cair (+ ping)."],
      ["<code>Movement_Trust_Seconds</code>", "0.5", "Confiança depois de o servidor mover o corpo (+ ping)."],
      ["<code>Movement_Ping_Factor</code>", "2", "Vezes que o ping entra nas janelas."],
      ["<code>Movement_Ground_Probe</code>", "3.5", "Alcance do raycast de chão (plataforma móvel)."],
      ["<code>Movement_Warn_Interval</code>", "1", "Intervalo entre warns de correção."],
      ["<code>Client_View_Lag</code>", "0.35", "Atraso de visão do corpo de cliente, sem ping (base do NetworkView)."],
      ["<code>Client_View_Ping_Factor</code>", "0.5", "Quanto do ping entra no atraso de visão."],
      ["<code>Zone_Prediction_Margin</code>", "40", "Margem de busca das zonas para corpo de cliente."],
    ]),
  });

  DOCS.group({ id: "api.NetworkView", parent: "api.fisica", title: "NetworkView", kw: "networkview atraso lag ping previsão predicted shift cliente", src: "ServerScriptService/Modules/Physics/NetworkView", lead: "Quanto atrasado o servidor vê um corpo simulado por cliente, e quanto ele andou nesse atraso. Corpo do servidor devolve nil.", html: C(`local NetworkView = require(game.ServerScriptService.Modules.Physics.NetworkView)`) });
  M("api.NetworkView", "Lag", "NetworkView.Lag", "NetworkView.Lag(player)", "Segundos de atraso de visão do corpo do player.", null, "<code>number</code>.");
  M("api.NetworkView", "PredictedShift", "NetworkView.PredictedShift", "NetworkView.PredictedShift(part)", "Quanto o corpo andou desde a posição que o servidor vê (velocidade × atraso do dono).", [["part", "BasePart", "O root."]], "<code>Vector3?</code> (nil para corpo do servidor).");

  DOCS.group({ id: "api.CollisionGroups", parent: "api.fisica", title: "CollisionGroups", kw: "collisiongroups colisão grupos grab agarrado", src: "ServerScriptService/Modules/Physics/CollisionGroups", lead: "Grupos do motor: agarrado (FW_Grabbed) não colide com outro agarrado nem com quem agarrou (FW_Grabber).", html: "" });
  M("api.CollisionGroups", "Assign", "CollisionGroups.Assign", "local restore = CollisionGroups.Assign(model, group)", "Põe as BaseParts no grupo.", [["model", "Instance?", ""], ["group", "string", "<code>CollisionGroups.Grabbed</code> ou <code>.Grabber</code>."]], "<code>restore()</code>: devolve cada peça ao grupo original.");

  DOCS.group({ id: "api.GlobalAntiCheat", parent: "api.fisica", title: "GlobalAntiCheat", kw: "anticheat anti-cheat validação lock input roteamento player entidade controlada", src: "ServerScriptService/Modules/GlobalAntiCheat", lead: "Validação de movimento do player e roteamento do input (qual entidade o player dirige, Lock). Normalmente usado pelo ControlComponent e pelo InputValidator.", html: "" });
  G = "api.GlobalAntiCheat";
  M(G, "GetEntityID", "AntiCheat.GetEntityID", "AntiCheat.GetEntityID(player)", "ID para onde o input do player vai agora (nil com Lock).", null, "<code>string?</code>.");
  M(G, "GetControlledEntityId", "AntiCheat.GetControlledEntityId", "AntiCheat.GetControlledEntityId(player)", "ID da entidade dirigida (ignora o Lock).", null, "<code>string?</code>.");
  M(G, "GetNativeEntityId", "AntiCheat.GetNativeEntityId", "AntiCheat.GetNativeEntityId(player)", "ID do corpo do próprio player.", null, "<code>string?</code>.");
  M(G, "GetMovementCorrections", "AntiCheat.GetMovementCorrections", "AntiCheat.GetMovementCorrections(player)", "Quantas correções de movimento desde o spawn.", null, "<code>number</code>.");
  M(G, "LockPlayerInput", "AntiCheat.LockPlayerInput", "AntiCheat.LockPlayerInput(player)", "Corta todo input do player na raiz.", null, "<code>boolean</code> (false se o player não está registrado ou já estava travado).");
  M(G, "UnlockPlayerInput", "AntiCheat.UnlockPlayerInput", "AntiCheat.UnlockPlayerInput(player)", "Devolve o input.", null, "<code>boolean</code> (false se não havia Lock).");
  M(G, "SetControlledEntity", "AntiCheat.SetControlledEntity", "AntiCheat.SetControlledEntity(player, id, suspendNative?)", "Redireciona o input (o ControlComponent usa; prefira Possess).", null, "<code>boolean</code> (false se o player não está registrado).");

  // ================================================================ CLIENTE E UTILITÁRIOS
  DOCS.page({ id: "api.cliente", parent: "api", title: "Cliente e utilitários", kw: "cliente utilitários módulos", lead: "VFX, som, câmera, Logger, animações e utilitários.", html: "" });

  DOCS.group({
    id: "api.VFX", parent: "api.cliente", title: "VFXManager / VFXRegistry",
    kw: "vfx efeito visual partícula registry player playall playnear",
    src: "ServerScriptService/Modules/VFX/VFXManager · StarterPlayerScripts/VFXRegistry",
    lead: "O servidor pede um efeito por nome; o cliente constrói pelo registro.",
    html: C(`
-- cliente: StarterPlayerScripts/VFXRegistry
Registry.Explosao = function(data)
    local p = Instance.new("Part")
    p.Anchored, p.CanCollide, p.Transparency = true, false, 1
    p.Position = data.Position
    p.Parent = workspace
    -- partículas...
    game.Debris:AddItem(p, 3)
end
`) + C(`
-- servidor
local VFXManager = require(game.ServerScriptService.Modules.VFX.VFXManager)
VFXManager.PlayNear(pos, 200, "Explosao", { Position = pos })
`),
  });
  M("api.VFX", "PlayAll", "VFXManager.PlayAll", "VFXManager.PlayAll(name, data)", "Toca em todos os clientes.", null, null);
  M("api.VFX", "PlayNear", "VFXManager.PlayNear", "VFXManager.PlayNear(position, radius, name, data)", "Toca nos players a até <code>radius</code> studs.", null, null);

  DOCS.group({ id: "api.SoundManager", parent: "api.cliente", title: "SoundManager", kw: "soundmanager som sound áudio 3d", src: "ServerScriptService/Modules/Audio/SoundManager", lead: "Som 3D no servidor.", html: "<p>config: <code>{ Volume?, Pitch?, RollOffMin?, RollOffMax?, Looped?, MaxLifetime? }</code>.</p>" });
  M("api.SoundManager", "PlayOneShot3D", "SoundManager.PlayOneShot3D", "SoundManager.PlayOneShot3D(position, soundId, config?)", "Som único numa posição (âncora invisível, destruída no fim).", null, null);
  M("api.SoundManager", "PlayAttached", "SoundManager.PlayAttached", "SoundManager.PlayAttached(instance, soundId, config?, key?)", "Som preso numa instância. Com key, reaproveita o mesmo Sound.", null, "Sound.");

  DOCS.group({ id: "api.CameraOverride", parent: "api.cliente", title: "CameraOverride", kw: "camera câmera ombro shoulder lock-on alvo", src: "StarterPlayer/StarterPlayerScripts/CameraOverride", lead: "Câmera de ombro com soft lock na entidade mais próxima num cone. Tecla C alterna. Segue o corpo possuído.", html: "<p>Ajuste <code>Config</code> no topo do módulo: ShoulderOffset, Distance, TargetLockRadius, TargetLockConeAngleDeg, TargetLockSoftness, TargetSearchInterval.</p>" });
  ["Enable", "Disable", "Toggle", "IsActive", "GetCurrentTarget"].forEach(function (n) {
    M("api.CameraOverride", n, "CameraOverride." + n, "CameraOverride." + n + "()",
      { Enable: "Liga a câmera.", Disable: "Desliga (volta à câmera padrão).", Toggle: "Alterna.", IsActive: "Ligada?", GetCurrentTarget: "O Model travado no lock, se houver." }[n], null,
      n === "IsActive" ? "<code>boolean</code>." : n === "GetCurrentTarget" ? "<code>Model?</code>." : null);
  });

  DOCS.group({
    id: "api.Logger", parent: "api.cliente", title: "Logger e LogConfig",
    kw: "logger log logconfig nível level canal channel debug info warn error",
    src: "ReplicatedStorage/Logger · ReplicatedStorage/Config/LogConfig",
    lead: "Saída padronizada: um canal por módulo, nível global e por canal. Vale para servidor e cliente.",
    html: `
${T(["Nível", "Para quê"], [["Debug", "Rotina do motor (entidade criada, efeito tocado)."], ["Info", "Eventos de teste (AntiCheat iniciado)."], ["Warn", "Configuração errada ou falha contornada."], ["Error", "Falha que interrompeu uma ação."], ["Off", "Nada."]])}
${C(`
-- Config/LogConfig
return {
    Level = "Info",
    Channels = { DataManager = "Debug", VFXPlayer = "Off" },
}
`)}`,
  });
  M("api.Logger", "Channel", "Logger.Channel", "local Log = Logger.Channel(name)", "Um canal: <code>Log.Debug</code>, <code>Log.Info</code>, <code>Log.Warn</code>, <code>Log.Error</code>, <code>Log.WarnOnce(chave, ...)</code>.", null, "Canal.");
  M("api.Logger", "SetLevel", "Logger.SetLevel", "Logger.SetLevel(level, channel?)", "Muda o nível em runtime (todos, ou um canal).", null, null);

  DOCS.group({ id: "api.AnimationLib", parent: "api.cliente", title: "AnimationLib", kw: "animationlib animações ids kit biblioteca charlib", src: "ServerStorage/Modules/Animation/AnimationLib", lead: "IDs de animação por kit: lib.character.&lt;Kit&gt;.&lt;Conjunto&gt;.&lt;Nome&gt;.", html: C(`
lib.character.Schema = {
    M1 = { M1Start = "109260837176213", M1S2 = "101981431556110" },
    S1 = { SpinStart = "130893699034171", SpinLoop = "99420668636443" },
}
`) });
  M("api.AnimationLib", "ForSkill", "lib.ForSkill", "lib.ForSkill(skillKit?, casterKit?)", "A vista que a skill vê em self.charLib: o conjunto do kit dono e, na falta, do kit de quem casta. Cacheada, só leitura.", null, "Vista.");

  DOCS.group({ id: "api.Utils", parent: "api.cliente", title: "Utils", kw: "utils utilitários vetor direção rotacionar lerp clamp octante", src: "ReplicatedStorage/Utils", lead: "Utilitários de número e direção (servidor e cliente).", html: "" });
  G = "api.Utils";
  M(G, "rotateTowards", "Utils.rotateTowards", "Utils.rotateTowards(current, target, maxRadians)", "Gira um vetor em direção a outro, com ângulo máximo por chamada (giro de Force e homing).", null, "<code>Vector3</code>.");
  M(G, "classifyDirection", "Utils.classifyDirection", "Utils.classifyDirection(move, facing)", "Octante do movimento relativo ao facing: Forward, ForwardRight, Right, BackRight, Back, BackLeft, Left, ForwardLeft ou None. É o <code>ctx.direction.Id</code>.", null, "<code>string</code>.");
  M(G, "worldToLocalPlanar", "Utils.worldToLocalPlanar", "Utils.worldToLocalPlanar(move, facing)", "Projeção no espaço local 2D do facing (X lateral, Z frontal).", null, "<code>Vector3</code>.");
  M(G, "getRoot", "Utils.getRoot", "Utils.getRoot(character)", "HumanoidRootPart do model.", null, "<code>BasePart?</code>.");
  M(G, "clamp", "Utils.clamp", "Utils.clamp(v, min, max)", "Limita.", null, "<code>number</code>.");
  M(G, "lerp", "Utils.lerp", "Utils.lerp(a, b, t)", "Interpolação linear.", null, "<code>number</code>.");
  M(G, "round", "Utils.round", "Utils.round(v)", "Arredonda.", null, "<code>number</code>.");
  M(G, "sign", "Utils.sign", "Utils.sign(v)", "-1, 0 ou 1.", null, "<code>number</code>.");
  M(G, "percent", "Utils.percent", "Utils.percent(part, whole)", "Porcentagem.", null, "<code>number</code>.");
})();

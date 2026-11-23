/* Referência da API: raiz e núcleo (DataManager, EntityCore) */

DOCS.page({
  id: "api",
  title: "Referência da API",
  kw: "api referência funções métodos reference",
  lead: "Uma página por função, com sintaxe, argumentos, retorno e exemplo. As funções de componente são chamadas na entidade, com ponto.",
  html: `
<div class="cards">
  <a class="card" href="#api.nucleo"><b>Núcleo</b><span>DataManager e EntityCore: criar, achar, escutar.</span></a>
  <a class="card" href="#api.componentes"><b>Componentes</b><span>Health, Status, Combat, Movement… a API da entidade.</span></a>
  <a class="card" href="#api.skills"><b>Skills</b><span>self dentro da skill, formatos de skill e status, SkillHandler, cooldown.</span></a>
  <a class="card" href="#api.combate"><b>Combate</b><span>StateTable, TriggerSet, zonas, hitbox solta, minions, combo.</span></a>
  <a class="card" href="#api.input"><b>Input</b><span>Intents, gestos, InputService, bindings.</span></a>
  <a class="card" href="#api.fisica"><b>Física e rede</b><span>Settings, NetworkView, CollisionGroups, AntiCheat.</span></a>
  <a class="card" href="#api.cliente"><b>Cliente e utilitários</b><span>VFX, som, câmera, Logger, AnimationLib, Utils.</span></a>
</div>
${N("<p>Requires usados nos exemplos: <code>DataManager = require(game.ServerScriptService.EntityData.DataManager)</code>, <code>Component = require(game.ServerScriptService.EntityData.ComponentsExport)</code>, <code>StateTable = require(game.ServerStorage.Modules.Combat.StateTable)</code>, <code>Enum = StateTable.Enum</code> (o Enum do framework, não o do Roblox, quando o exemplo diz <code>Enum.Breakpoints</code>, <code>Enum.Traits</code> etc.).</p>")}
`,
});

DOCS.page({
  id: "api.nucleo",
  parent: "api",
  title: "Núcleo",
  kw: "núcleo core base",
  lead: "Criar, achar e remover entidades; o EntityCore e os eventos.",
  html: "",
});

// ------------------------------------------------------------------ DataManager
DOCS.group({
  id: "api.DataManager",
  parent: "api.nucleo",
  title: "DataManager",
  kw: "datamanager criar entidade create spawn registrar buscar get remover remove id",
  src: "ServerScriptService/EntityData/DataManager",
  lead: "Registro de todas as entidades vivas: cria, busca por Instance ou ID, e remove. Players e NPCs ficam em mapas separados; o ID vai no atributo EntityID do Model.",
  html: `
${C(`local DataManager = require(game.ServerScriptService.EntityData.DataManager)`)}
<p>IDs: player = <code>Player_&lt;UserId&gt;</code> (o mesmo a cada respawn); NPC/objeto = <code>Entity_&lt;número&gt;</code> único.</p>
`,
});
DOCS.fn("api.DataManager", {
  name: "Create",
  title: "DataManager.Create",
  call: "DataManager.Create(entity, components, configs?, parentEntity?)",
  desc: "Cria a entidade de um corpo (player ou Model), adiciona os componentes, roda os OnAdded e registra. Entrada inválida devolve <code>nil</code> sem registrar nada.",
  args: [
    ["entity", "Model | { Model, Player }", "Um Model (NPC, objeto) ou <code>{ Model = character, Player = player }</code> para um player."],
    ["components", "{string}", "Nomes dos componentes (<code>Component.Health</code>…). Lista ou dicionário."],
    ["configs", "{ [nome]: table }?", "Config por componente, ex.: <code>{ Health = { MaxHP = 200 } }</code>."],
    ["parentEntity", "EntityCore?", "Pai: o filho herda as inscrições com <code>Inherit</code> (Fork do TriggerSet)."],
  ],
  ret: "<code>EntityCore</code>, ou <code>nil</code> se a entrada for inválida.",
  ex: `
local boss = DataManager.Create(workspace.Boss, {
    Component.Character, Component.Health, Component.Status, Component.Movement,
    Component.Attributes, Component.Combat, Component.Affiliation, Component.AI,
}, {
    Health = { MaxHP = 5000, HealCap = 1.2 },
    Combat = { ChosenChar = false },
    Affiliation = { Team = "Chefes" },
    AI = { Brain = brainDoChefe },
})
`,
  exDesc: "Um chefe sem personagem do banco (o kit é montado depois com EquipSkill), num time próprio e dirigido por um Brain.",
  see: ["api.DataManager.CreateData", "api.DataManager.Remove", "conceitos.entidades"],
  kw: "criar spawn instanciar nova entidade npc",
});
DOCS.fn("api.DataManager", {
  name: "CreateData",
  title: "DataManager.CreateData",
  call: "DataManager.CreateData(components, configs?, parentEntity?)",
  desc: "Cria uma entidade só de dado, sem Instance: carta, mão, baralho, gerente de turno, aura invisível. Componentes que dependem de corpo (Character, Movement, Weapon, Animation) não servem nela.",
  args: [
    ["components", "{string}", "Nomes dos componentes."],
    ["configs", "{ [nome]: table }?", "Config por componente."],
    ["parentEntity", "EntityCore?", "Pai (herança de reações)."],
  ],
  ret: "<code>EntityCore</code> com <code>Type = \"Generic\"</code> e <code>Instance = nil</code>.",
  ex: `
local carta = DataManager.CreateData({ Component.Health, Component.Status, Component.Attributes }, {
    Health = { MaxHP = 3 },
    Attributes = { BaseStats = { Custo = 2, Ataque = 4 } },
})
carta.TakeDamage(1)
DataManager.Remove(carta)
`,
  see: ["receitas.cardgame", "api.DataManager.Remove"],
  kw: "card carta deck baralho sem corpo sem model dado abstrata",
});
DOCS.fn("api.DataManager", {
  name: "Get",
  title: "DataManager.Get",
  call: "DataManager.Get(entity)",
  desc: "Devolve o EntityCore a partir do ID, do Model, do Player ou do próprio core. Entrada inválida devolve <code>nil</code> com warn (não dá erro).",
  args: [["entity", "string | Instance | EntityCore", "ID (mais rápido), Model, Player ou o core."]],
  ret: "<code>EntityCore</code> ou <code>nil</code>.",
  ex: `local alvo = DataManager.Get(ctx.input.Target)`,
  notes: N("<p>Para validar entrada da rede sem warn, use " + L("api.DataManager.Exists") + ".</p>"),
  see: ["api.DataManager.Exists", "api.DataManager.GetEntityFromInstance"],
  kw: "buscar achar encontrar obter",
});
DOCS.fn("api.DataManager", {
  name: "Exists",
  title: "DataManager.Exists",
  call: "DataManager.Exists(id)",
  desc: "Existe entidade com este ID? Sem warn: serve para validar entrada da rede.",
  args: [["id", "any", "Qualquer valor (não-string devolve false)."]],
  ret: "<code>boolean</code>.",
  ex: `if not DataManager.Exists(payload.Target) then return end`,
  see: ["api.DataManager.Get"],
});
DOCS.fn("api.DataManager", {
  name: "GetEntityFromInstance",
  title: "DataManager.GetEntityFromInstance",
  call: "DataManager.GetEntityFromInstance(instance)",
  desc: "Sobe a hierarquia a partir de uma peça atingida até achar um Model com EntityID e devolve a entidade dele.",
  args: [["instance", "Instance", "Peça atingida (ex.: <code>raycastResult.Instance</code>)."]],
  ret: "<code>EntityCore</code> ou <code>nil</code>.",
  ex: `
hitbox:OnHit(function(result)
    local atingido = DataManager.GetEntityFromInstance(result.Instance)
    if atingido then self:Damage(atingido, 12) end
end)
`,
  see: ["api.HitboxSpawner"],
  kw: "raycast peça part hit atingido",
});
DOCS.fn("api.DataManager", {
  name: "Remove",
  title: "DataManager.Remove",
  call: "DataManager.Remove(entity)",
  desc: "Destrói a entidade (todos os componentes, skills e status) e tira do registro.",
  args: [["entity", "Player | Model | string | EntityCore", "O Player, o Model, o ID ou o core."]],
  ret: "Nada.",
  ex: `DataManager.Remove(minion)`,
  see: ["api.EntityCore.Destroy"],
  kw: "destruir apagar deletar remover",
});

// ------------------------------------------------------------------ EntityCore
DOCS.group({
  id: "api.EntityCore",
  parent: "api.nucleo",
  title: "EntityCore",
  kw: "entitycore entidade core núcleo componentkey entitytypes emit listen",
  src: "ServerScriptService/EntityData/EntityCore",
  lead: "O núcleo de toda entidade. Métodos próprios usam dois-pontos (entity:Listen); a API dos componentes é injetada e usa ponto (entity.TakeDamage).",
  html: `
<h2>Campos</h2>
${T(["Campo", "Tipo", "O quê"], [
  ["<code>ID</code>", "string", "Identificador único."],
  ["<code>Instance</code>", "Model?", "O corpo (nil em entidade de dado)."],
  ["<code>Type</code>", "string", "<code>EntityCore.EntityTypes</code>: Player, NPC ou Generic."],
  ["<code>Player</code>", "Player?", "O player dono do corpo nativo."],
  ["<code>Active</code>", "boolean", "false depois do Destroy."],
  ["<code>Components</code>", "table", "[nome] = instância do componente."],
])}
<h2>Tabelas estáticas</h2>
${T(["Tabela", "O quê"], [
  ["<code>EntityCore.ComponentKey</code>", "Nomes dos componentes registrados (o mesmo que <code>ComponentsExport</code>)."],
  ["<code>EntityCore.EntityTypes</code>", "<code>{ Player, NPC, Generic }</code>."],
  ["<code>EntityCore.Events</code>", "Eventos exportados por componentes (EventKey)."],
])}
`,
});
DOCS.fn("api.EntityCore", {
  name: "Listen",
  title: "entity:Listen",
  call: "local unsubscribe = entity:Listen(subscription)",
  desc: "Inscreve uma reação num breakpoint desta entidade. É o mecanismo de reação do framework inteiro.",
  args: [["subscription", "Types.Subscription", "<code>{ Role, Breakpoint, Action, Query?, Priority?, Owner?, TTD?, Limit?, Inherit? }</code>. Ver " + L("api.TriggerSet.Subscription") + "."]],
  ret: "Função <code>unsubscribe()</code>.",
  ex: `
local Enum = StateTable.Enum
-- espinhos: devolve 20% do dano recebido para quem bateu
alvo:Listen({
    Role = Enum.Roles.IN,
    Breakpoint = Enum.Breakpoints.PostDamage,
    Query = { None = { Enum.Traits.DOT } },
    Owner = StateTable.OwnerToken(alvo, "Espinhos"),
    Action = function(ctx)
        local agressor = ctx.ownerEntity
        if agressor and agressor ~= alvo then
            agressor.TakeDamage(ctx.actualDamage * 0.2)
        end
    end,
})
`,
  notes: N("<p>Dentro de skill, prefira <code>self:Listen(sub)</code>: a inscrição sai sozinha no fim do runner.</p>"),
  see: ["conceitos.eventos", "api.EntityCore.ListenWorld", "api.EntityCore.UnsubscribeByOwner", "api.skill.Listen"],
  kw: "escutar ouvir evento reagir subscribe inscrever",
});
DOCS.fn("api.EntityCore", {
  name: "ListenWorld",
  title: "EntityCore.ListenWorld",
  call: "local unsubscribe = EntityCore.ListenWorld(subscription)",
  desc: "Escuta um canal de TODAS as entidades. A Action recebe <code>(ctx, entidadeQueEmitiu, ...)</code>. Roda depois dos ouvintes da própria entidade. Sem ouvinte no mundo, o Emit não paga nada a mais.",
  args: [["subscription", "Types.Subscription", "Mesmo formato do Listen."]],
  ret: "Função <code>unsubscribe()</code>.",
  ex: `
local EntityCore = require(game.ServerScriptService.EntityData.EntityCore)
-- "sempre que qualquer lacaio morrer, o chefe ganha 5% de dano"
EntityCore.ListenWorld({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Owner = StateTable.OwnerToken(chefe, "Furia"),
    Action = function(ctx, morto)
        if morto:GetComponent(Component.Affiliation) and morto.GetTeam() == "Lacaios" then
            chefe.AddModifier("DamageMult", "Furia_" .. morto.ID, "AddPercent", 0.05)
        end
    end,
})
`,
  see: ["api.EntityCore.UnsubscribeWorldByOwner", "receitas.global"],
  kw: "global mundo todos qualquer entidade world",
});
DOCS.fn("api.EntityCore", {
  name: "UnsubscribeWorldByOwner",
  title: "EntityCore.UnsubscribeWorldByOwner",
  call: "EntityCore.UnsubscribeWorldByOwner(owner)",
  desc: "Desinscreve do canal global todas as inscrições com este Owner.",
  args: [["owner", "any", "O mesmo Owner usado no ListenWorld."]],
  see: ["api.EntityCore.ListenWorld"],
});
DOCS.fn("api.EntityCore", {
  name: "Emit",
  title: "entity:Emit",
  call: "entity:Emit(role, breakpoint, context, ...)",
  desc: "Dispara um breakpoint nesta entidade (e no canal global). O motor usa para todos os eventos; o jogo pode emitir breakpoints próprios (qualquer string).",
  args: [
    ["role", "string", "<code>Enum.Roles.IN</code> ou <code>OUT</code>."],
    ["breakpoint", "string", "Nome do breakpoint."],
    ["context", "table?", "Contexto entregue às Actions (precisa de <code>traits</code> para Query; o motor cria se faltar)."],
    ["...", "any", "Argumentos extras para as Actions."],
  ],
  ex: `
if mesa:HasListeners(Enum.Roles.OUT, "OnCardPlayed") then
    mesa:Emit(Enum.Roles.OUT, "OnCardPlayed", { traits = { "Feitiço" }, carta = carta })
end
`,
  see: ["api.EntityCore.HasListeners"],
  kw: "disparar emitir evento próprio custom",
});
DOCS.fn("api.EntityCore", {
  name: "HasListeners",
  title: "entity:HasListeners",
  call: "entity:HasListeners(role, breakpoint)",
  desc: "Alguém escuta este canal da entidade, ou do mundo? Evita montar um contexto que ninguém vai ler.",
  args: [["role", "string", "IN ou OUT."], ["breakpoint", "string", "Nome do breakpoint."]],
  ret: "<code>boolean</code>.",
  see: ["api.EntityCore.Emit"],
});
DOCS.fn("api.EntityCore", {
  name: "UnsubscribeByOwner",
  title: "entity:UnsubscribeByOwner",
  call: "entity:UnsubscribeByOwner(owner)",
  desc: "Remove todas as inscrições desta entidade com este Owner.",
  args: [["owner", "any", "Use <code>StateTable.OwnerToken(entidade, tag)</code> para um dono por entidade."]],
  ex: `
local dono = StateTable.OwnerToken(self.Entity, "Combo")
self.Entity:UnsubscribeByOwner(dono) -- limpa combos antigos antes de inscrever de novo
`,
  see: ["api.StateTable.OwnerToken"],
});
DOCS.fn("api.EntityCore", {
  name: "AddComponent",
  title: "entity:AddComponent",
  call: "entity:AddComponent(name, config?, callOnAddedNow?)",
  desc: "Adiciona um componente depois da criação. A API dele é injetada na entidade.",
  args: [
    ["name", "string", "Nome registrado (<code>Component.AI</code>)."],
    ["config", "table?", "Config do componente."],
    ["callOnAddedNow", "boolean?", "true = roda o OnAdded agora (use sempre que a entidade já existe)."],
  ],
  ret: "A instância do componente (ou a existente, com warn).",
  ex: `npc:AddComponent(Component.AI, { Brain = patrulha }, true)`,
  see: ["api.EntityCore.RemoveComponent"],
});
DOCS.fn("api.EntityCore", {
  name: "RemoveComponent",
  title: "entity:RemoveComponent",
  call: "entity:RemoveComponent(name)",
  desc: "Destrói e tira um componente. A API exposta sai junto: chamadas voltam a cair no stub (warn).",
  args: [["name", "string", "Nome do componente."]],
});
DOCS.fn("api.EntityCore", {
  name: "GetComponent",
  title: "entity:GetComponent",
  call: "entity:GetComponent(name)",
  desc: "A instância do componente (para ler campos ou chamar métodos que não estão na ExposeAPI).",
  args: [["name", "string", "Nome do componente."]],
  ret: "O componente ou <code>nil</code>.",
  ex: `local weapon = self.Entity:GetComponent(self.Entity.ComponentKey.Weapon)`,
});
DOCS.fn("api.EntityCore", {
  name: "HasComponent",
  title: "entity:HasComponent",
  call: "entity:HasComponent(name)",
  desc: "A entidade tem este componente?",
  args: [["name", "string", "Nome do componente."]],
  ret: "<code>boolean</code>.",
  ex: `if alvo:HasComponent(Component.Movement) then alvo.AddForce(knockback) end`,
});
DOCS.fn("api.EntityCore", {
  name: "Destroy",
  title: "entity:Destroy",
  call: "entity:Destroy()",
  desc: "Destrói a entidade e os componentes. Prefira " + "<code>DataManager.Remove</code>" + ", que também tira do registro.",
  see: ["api.DataManager.Remove"],
});
DOCS.fn("api.EntityCore", {
  name: "IsPlayer",
  title: "entity:IsPlayer",
  call: "entity:IsPlayer()",
  desc: "A entidade é de um player (Type = Player)?",
  ret: "<code>boolean</code>.",
});
DOCS.fn("api.EntityCore", {
  name: "IsNPC",
  title: "entity:IsNPC",
  call: "entity:IsNPC()",
  desc: "A entidade é um NPC/objeto com corpo (Type = NPC)?",
  ret: "<code>boolean</code>.",
});
DOCS.fn("api.EntityCore", {
  name: "GetAge",
  title: "entity:GetAge",
  call: "entity:GetAge()",
  desc: "Segundos desde a criação.",
  ret: "<code>number</code>.",
});
DOCS.fn("api.EntityCore", {
  name: "PrintComponents",
  title: "entity:PrintComponents",
  call: "entity:PrintComponents()",
  desc: "Debug: imprime ID, Type, Active e os componentes.",
});
DOCS.fn("api.EntityCore", {
  name: "GetRegisteredComponents",
  title: "EntityCore.GetRegisteredComponents",
  call: "EntityCore.GetRegisteredComponents()",
  desc: "Nomes de todos os componentes registrados.",
  ret: "<code>{string}</code>.",
});

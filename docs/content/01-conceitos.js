/* Conceitos: cada sistema, como funciona e por quê */

DOCS.page({
  id: "basico",
  title: "Guia básico",
  kw: "básico iniciante guia começar fundamentos conceitos",
  lead: "O que todo mundo que mexe no jogo precisa saber: entidades, skills, status, eventos, dano, input, movimento, HUD, a regra de centralização e como criar tags e enums novos. Leia na ordem.",
  html: "",
});

DOCS.page({
  id: "avancado",
  title: "Guia avançado",
  kw: "avançado expert profundo internals interno arquitetura",
  lead: "Como o motor decide por dentro: contexto e herança explícita, cadeias e limites, rede e atraso, possessão, herança de reações, desempenho, segurança e como estender sem mexer no motor.",
  html: "",
});

// ------------------------------------------------------------------ entidades
DOCS.page({
  id: "conceitos.entidades",
  parent: "basico",
  order: 10,
  title: "Entidades e componentes",
  kw: "entity entidade componente ecs npc player jogador objeto criar component api exposeapi",
  lead: "Tudo no jogo que participa do combate é uma entidade: um núcleo (EntityCore) com componentes. Componente dá dado e API; entidade simples não paga o custo de entidade complexa.",
  html: `
<h2>O modelo</h2>
<p>Um ${L("api.EntityCore", "EntityCore")} guarda só o mínimo: <code>ID</code>, <code>Instance</code> (o Model, ou nil numa entidade de dado), <code>Type</code> (Player, NPC ou Generic), <code>Player</code> (se for de um player) e a tabela de componentes. Todo o resto vem dos componentes.</p>
<p>Cada componente expõe uma <code>ExposeAPI</code>: as funções dela são injetadas na entidade. Por isso você chama <code>entity.TakeDamage(10)</code> e não <code>entity:GetComponent("Health"):TakeDamage(10)</code>.</p>
${W("<p><strong>Ponto, não dois-pontos.</strong> API de componente se chama com ponto: <code>entity.Heal(5)</code>. Com dois-pontos (<code>entity:Heal(5)</code>) o motor dá erro com a mensagem certa. Os métodos do próprio EntityCore (<code>Listen</code>, <code>Emit</code>, <code>HasComponent</code>, <code>GetComponent</code>…) usam dois-pontos.</p>")}

<h2>Criando</h2>
${C(`
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)

-- NPC (qualquer Model com HumanoidRootPart ou PrimaryPart)
local npc = DataManager.Create(model, {
    Component.Character, Component.Health, Component.Status,
    Component.Movement, Component.Attributes, Component.Combat,
}, {
    Health = { MaxHP = 300 },
    Combat = { ChosenChar = false }, -- sem personagem: kit montado em runtime
})

-- Player (o Main.server já faz isso a cada spawn)
DataManager.Create({ Model = character, Player = player }, PlayerComponents)

-- Entidade só de dado, sem corpo (carta, baralho, gerente de turno)
local deck = DataManager.CreateData({ Component.Health, Component.Status })
`)}
<p>${L("api.DataManager.Create")} valida a entrada antes de construir: entrada inválida devolve <code>nil</code> e não registra nada. O ID vai no atributo <code>EntityID</code> do Model (e do Player), e é por ele que hitbox, zona e input acham a entidade.</p>

<h2>Os componentes</h2>
${T(["Componente", "Para quê", "Depende de"], [
  [L("api.Character", "Character"), "Model, root, Humanoid, posição e teleporte.", "—"],
  [L("api.Health", "Health"), "HP, dano (lado do alvo), cura, morte, revive.", "Status e Attributes (opcionais)"],
  [L("api.Status", "Status"), "Status e estados; as tags deles viram as permissões da entidade.", "—"],
  [L("api.Combat", "Combat"), "Loadout em camadas, cooldowns, skills ativas, dano (lado do atacante).", "Status e Attributes (opcionais)"],
  [L("api.Attributes", "Attributes"), "Stats com modificadores (Flat, %, Override) e limites.", "—"],
  [L("api.Movement", "Movement"), "Direção, mira, Forces, agarrão (AttachTo).", "Character"],
  [L("api.Weapon", "Weapon"), "Arma equipada, modos, hitbox por skill.", "Character"],
  [L("api.Animation", "Animation"), "Tracks, marcadores, sequências, biblioteca do kit.", "Character"],
  [L("api.Control", "Control"), "Possessão em pilha, Lock/Unlock, link de input.", "Movement e AI (opcionais)"],
  [L("api.AI", "AI"), "Um Brain chamado a cada Heartbeat, que gera input como um player.", "—"],
  [L("api.Affiliation", "Affiliation"), "Time/facção. Sem ele a entidade é Neutral.", "—"],
])}
<p>Dependência opcional quer dizer: o componente funciona sem o outro, com o comportamento padrão. Sem Attributes, os stats são ${L("enum.stats", "Enum.StatDefaults")}; sem Status, nada é imune nem bloqueia.</p>

<h2>Componente ausente</h2>
<p>Chamar uma função de um componente que a entidade não tem cai num <b>stub</b>: um warn (uma vez por componente e função; as repetições só em Debug) e retorno <code>nil</code>. Use <code>entity:HasComponent(Component.X)</code> quando o componente é opcional para você.</p>

<h2>Adicionando e removendo depois</h2>
${C(`
entity:AddComponent(Component.AI, { Brain = meuBrain }, true) -- true = roda o OnAdded agora
entity:RemoveComponent(Component.AI) -- a API dele sai junto e volta a cair no stub
`)}

<h2>Herança de reações</h2>
<p>O 4º argumento do Create é a entidade pai. O filho nasce com uma cópia (Fork) das inscrições do pai marcadas com <code>Inherit = { Generations = n }</code>: um minion herda o efeito on-hit do invocador. Veja ${L("conceitos.eventos")} e ${L("receitas.minion")}.</p>

<h2>Escrevendo um componente novo</h2>
<p>Raramente necessário (prefira status, listeners e config). Se for: um ModuleScript em <code>EntityData/Components</code> chamado <code>XComponent</code> é registrado como <code>X</code> automaticamente.</p>
${C(`
local Shield = {}
Shield.__index = Shield

function Shield.new(entity, config)
    return setmetatable({ Entity = entity, Value = config.Value or 0 }, Shield)
end
function Shield:OnAdded() end      -- depois de todos os componentes do lote
function Shield:Destroy() end
function Shield:GetShield() return self.Value end

return {
    new = Shield.new,
    InitPriority = nil,           -- "High" roda o OnAdded antes dos outros
    Requires = { "Health" },      -- dependência declarada: warn imediato se faltar
    ExposeAPI = {
        GetShield = function(component) return component:GetShield() end,
    },
}
`)}
`,
});

// ------------------------------------------------------------------ skills
DOCS.page({
  id: "conceitos.skills",
  parent: "basico",
  order: 20,
  title: "Skills e o ciclo de vida",
  kw: "skill habilidade ability ataque runner lifecycle ciclo callbacks onstart onstep onhit onend oncancel onrecast onrelease ontrigger casttime duration",
  lead: "Uma skill é um módulo { data, callbacks }. Cada ativação vira um SkillRunner com uma instância isolada da skill: o estado de uma ativação nunca vaza para outra.",
  html: `
<h2>Anatomia</h2>
${C(`
local StateTable = require(game.ServerStorage.Modules.Combat.StateTable)

return {
    data = {                       -- estático: nunca escrito em runtime
        cooldown = 2,
        duration = 0.6,            -- nil = só termina por Stop/cancel
        castTime = 0.1,            -- tempo em Casting antes do Running
        traits = { StateTable.Enum.Traits.Melee },
    },
    callbacks = {
        onStart = function(self, ctx) end,
        onStep = function(self, dt, ctx) end,     -- a cada frame, só no Running
        onHit = function(self, hit, ctx) end,     -- acerto da hitbox da arma
        onRecast = function(self, ctx) end,       -- novo toque com a skill viva
        onRelease = function(self, ctx) end,      -- soltou o botão
        onTrigger = function(self, hitCtx, ctx) end, -- bloqueio/escudo (status)
        onCancel = function(self, ctx) end,       -- return false recusa o cancel
        onEnd = function(self, ctx) end,          -- SEMPRE roda, com ctx.reason
    },
}
`)}
<p>Todo callback é opcional. <code>self</code> é a instância da ativação: guarde estado em <code>self.algo</code>, nunca em variável local do módulo (ela seria compartilhada entre ativações).</p>

<h2>Estados do runner</h2>
<ol class="flow">
  <li><b>Idle</b>: criado, ainda não iniciado.</li>
  <li><b>Casting</b>: <code>onStart</code> já rodou. Fica aqui por <code>data.castTime</code> segundos.</li>
  <li><b>Running</b>: <code>onStep</code> roda a cada frame. A duração (<code>self.runtimeDuration</code> ou <code>data.duration</code>) conta a partir daqui.</li>
  <li><b>Ended</b>: terminou (duração, Stop, cancel, erro, fizzle, recusa). Nada mais roda.</li>
</ol>

<h2>Do botão ao onStart</h2>
<p>O ${L("api.SkillHandler.HandleIntent", "SkillHandler.HandleIntent")} é a entrada única (player, IA e scripts usam a mesma):</p>
<ol class="flow">
  <li>Pega a skill do slot da intent no loadout efetivo.</li>
  <li><code>CanContinue</code>: morto não casta (${L("enum.morte", "RefuseCastOnDeath")}); tag <code>canCast = false</code> (Stun, Silence) não casta.</li>
  <li>Se já há <code>maxInstances</code> runners vivos (padrão 1): com <code>onRecast</code>, vira recast (respeitando <code>cooldownPolicy.recast</code>); sem, tenta auto-cancelar a ação atual (ActionState Self).</li>
  <li>Cooldown: em cooldown, recusa.</li>
  <li><code>TrySelfCancel</code>: uma skill com ActionState <b>Self</b> é cancelada para a nova entrar; com <b>Out</b> ou <b>LockedCast</b>, a nova é recusada.</li>
  <li>Cria o runner, cobra o cooldown pela política (start = Cast cobra aqui) e chama <code>start()</code>.</li>
  <li><code>start()</code> confere <code>data.requires</code> e a largura da cadeia; registra no heartbeat; roda <code>onStart</code>; emite <span class="badge out">OUT</span> <code>onStart</code>.</li>
</ol>

<h2>O fim (sempre na mesma ordem)</h2>
<ol class="flow">
  <li>Se é cancelamento: <code>onCancel(self, ctx)</code>. Devolver <code>false</code> recusa: a skill segue viva.</li>
  <li>Estado vira Ended; a vaga na raiz da cadeia é devolvida.</li>
  <li>Os <code>self:Listen(...)</code> da skill são desinscritos e os <code>self:Own(fn)</code> rodam.</li>
  <li><code>onEnd(self, ctx)</code> com <code>ctx.reason</code> (${L("enum.fim", "Enum.EndReasons")}).</li>
  <li>Cooldown de fim (start = End) e devolução por motivo (refund).</li>
  <li>Sai das skills ativas e da hitbox; o ActionState do runner é removido.</li>
  <li><span class="badge out">OUT</span> <code>onEnd</code> na entidade.</li>
</ol>
${N("<p><strong>Uma limpeza só:</strong> como o <code>onEnd</code> roda em qualquer fim (inclusive depois do <code>onCancel</code>), ponha a limpeza lá ou em <code>self:Own(fn)</code>. É o padrão de todas as skills de exemplo.</p>")}

<h2>Erros</h2>
<p>Erro num callback nunca derruba o motor. No <code>onStart</code> ou <code>onStep</code>, o runner é encerrado com o motivo <code>error</code> (o cooldown volta pelo refund padrão). Em <code>onHit</code>, <code>onRecast</code>, <code>onRelease</code>, <code>onTrigger</code> vira warn com traceback e a skill segue.</p>

<h2>O que a skill enxerga em self</h2>
${T(["Campo / método", "O quê"], [
  ["<code>self.Entity</code>", "A entidade dona (quem casta; num status, o portador)."],
  ["<code>self.Runner</code>", "O SkillRunner (para APIs que pedem o runner)."],
  ["<code>self.data</code>", "O data da skill (só leitura)."],
  ["<code>self.counter</code>", "Contador livre, começa em 1 (stacks, estágio do combo, balas)."],
  ["<code>self.runtimeDuration</code>", "Escreva para mudar a duração desta ativação."],
  ["<code>self.statusTable</code>", "O " + L("api.StateTable", "StateTable") + " (status, estados, Enum)."],
  ["<code>self.charLib</code>", "Animações do kit dono da skill (" + L("api.Animation", "Animation") + ")."],
  ["<code>self.weapon</code>, <code>self.hitPoint</code>", "Model da arma e a origem de hitbox (com Weapon)."],
  ["<code>self.Source</code>", "Num status: o runner que o aplicou."],
  ["<code>self:Damage</code>, <code>self:ApplyStatus</code>", "Dano e status com este runner como fonte."],
  ["<code>self:StartHitbox</code>, <code>self:StopHitbox</code>", "A hitbox da arma desta skill."],
  ["<code>self:Listen</code>, <code>self:Own</code>", "Inscrição e limpeza que saem sozinhas no fim."],
  ["<code>self:Stop</code>, <code>self:Fizzle</code>, <code>self:CommitCooldown</code>, <code>self:GetRemainingTime</code>", "Controle do fim e do cooldown."],
])}
<p>Referência completa em ${L("api.skill")}. Formato do data em ${L("api.skill.data")}.</p>

<h2>Skill no banco</h2>
<p>Skills ficam em <code>ServerStorage/DataBase/SkillDatabase/&lt;Kit&gt;/...</code>. O scanner cria a chave pelo caminho (<code>Schema/M1</code> vira <code>"Schema_M1"</code>) e um enum navegável: <code>SkillDatabase.Keys.Schema.M1</code>. A pasta de 1º nível é o <b>kit dono</b>: é de lá que a skill tira as animações em qualquer corpo (uma skill roubada segue com as animações dela). Skill também pode ser uma tabela criada em código e equipada direto (<code>entity.EquipSkill(slot, tabela)</code>).</p>
`,
});

// ------------------------------------------------------------------ status
DOCS.page({
  id: "conceitos.status",
  parent: "basico",
  order: 30,
  title: "Status e estados",
  kw: "status efeito buff debuff dot veneno sangramento bleed stack acumular estado stun root silence nocontrol atordoar imobilizar silenciar escudo shield",
  lead: "Status (buff, debuff) e estados (Stun, Root…) são runners como as skills, registrados no StatusComponent. As tags deles viram as permissões da entidade.",
  html: `
<h2>Status × estado</h2>
${T(["", "Status", "Estado"], [
  ["Onde fica", "<code>StateTable/Status/Buffs</code> e <code>Debuffs</code> (acessa como <code>StateTable.Status.Nome</code>)", "<code>StateTable/States</code> (<code>StateTable.States.Stun</code>)"],
  ["Exemplos", "Bleed, iFrame, StatusShield, GenericBlock", "Stun, Root, Silence, NoControl"],
  ["Grupo", "Status", "State (separado, mesmas regras)"],
])}
<p>Os dois têm o mesmo formato e o mesmo ciclo de vida da skill (onStart, onStep, onRecast, onEnd…). A diferença é só o grupo onde ficam registrados.</p>

<h2>Aplicando</h2>
${C(`
-- de dentro de uma skill (o runner vira o Source: crédito de dano e morte)
self:ApplyStatus(StateTable.Status.Bleed, { Target = alvo, Duration = 4 })

-- de fora de skill
local id = entity.ApplyStatus(StateTable.States.Stun, { Duration = 1.5, Source = runner })
entity.RemoveStatusByID(id)
`)}
<p><code>ApplyStatus</code> devolve o ID (ou <code>nil</code> se não entrou). Prefira remover por ID: duas skills que aplicam o mesmo status não apagam a aplicação uma da outra.</p>

<h2>O que acontece ao aplicar</h2>
<ol class="flow">
  <li>Morto não recebe status (${L("enum.morte", "RefuseStatusOnDeath")}; <code>data.allowOnDead = true</code> fura).</li>
  <li>Escudos de status (<code>ShieldsFrom</code> de um status ativo) podem barrar.</li>
  <li><span class="badge out">OUT</span> <code>PreApplyStatus</code> no dono do efeito: pode cancelar ou injetar em <code>ctx.inherited</code>.</li>
  <li>Cooldown de reaplicação (<code>data.cooldown</code> do status).</li>
  <li>Regra de stack (abaixo), <code>exclusive</code> ou substituição.</li>
  <li><code>onStart</code>. Se o status tem a tag <code>interrupt</code>, a entidade recebe <span class="badge in">IN</span> <code>OnInterrupt</code> (o Combat cancela as skills).</li>
</ol>

<h2>Stacks</h2>
${T(["data", "Comportamento"], [
  ["sem a trait Stackable", "Status único: reaplicar encerra o anterior e cria outro."],
  ["<code>Stackable</code> + <code>stackOnSelf = true</code>", "Mesma instância: reaplicar soma 1 em <code>self.counter</code>, zera o tempo, troca a duração e chama <code>onRecast</code>. Devolve o mesmo ID. O crédito fica com quem aplicou o 1º stack."],
  ["<code>Stackable</code> sem stackOnSelf", "Instâncias separadas, cada uma com seu tempo, até <code>maxStacks</code>."],
  ["<code>maxStacks</code>", "Teto. No teto, a reaplicação só renova a duração (<code>refreshOnMax = false</code> desliga)."],
])}

<h2>exclusive</h2>
<p><code>data.exclusive = true</code> remove os outros status da mesma <code>category</code> ao entrar (ex.: só um "modo" ativo por vez).</p>

<h2>Tags</h2>
<p>As tags de todos os status ativos são combinadas: <b>false vence</b> (um Root com <code>canMove = false</code> trava mesmo com outro buff dizendo true). O resto vem de ${L("enum.tags", "Enum.tagsBase")}. Veja ${L("conceitos.tags")}.</p>

<h2>Escudos de status</h2>
<p>Um status com <code>ShieldsFrom = { ... }</code> (categoria, trait ou nome; <code>"All"</code> = tudo) barra a entrada de status que casam. Se ele também tem <code>onTrigger</code>, o trigger decide; sem trigger, vale o <code>data.block</code>. O <code>StatusShield</code> de exemplo barra DOTs.</p>

<h2>Status com dano periódico</h2>
${C(`
return {
    data = {
        name = "Poison", category = Enum.Categories.Debuff,
        duration = 5, tickRate = 0.5, damage = 3,
        traits = { Enum.Traits.DOT, Enum.Traits.Stackable }, stackOnSelf = true, maxStacks = 5,
    },
    callbacks = {
        onStart = function(self) self.t = 0 end,
        onStep = function(self, dt)
            self.t += dt
            if self.t >= self.data.tickRate then
                self.t = 0
                self.Entity.TakeDamage(self.data.damage * self.counter, self.Runner)
            end
        end,
    },
}
`)}
<p>O dano do DOT tem a trait DOT no contexto (escudos e listeners filtram por ela) e o crédito vai para quem aplicou (o <code>Source</code>). Veja ${L("receitas.dot")}.</p>
${N("<p>Status não pode recusar cancelamento (o retorno do <code>onCancel</code> é ignorado): o RemoveStatus tira a entrada do registro antes de encerrar.</p>")}
`,
});

// ------------------------------------------------------------------ tags e traits
DOCS.page({
  id: "conceitos.tags",
  parent: "basico",
  order: 40,
  title: "Tags, traits e permissões",
  kw: "tag trait permissão canmove cancast iframe block interrupt imunidade invulnerável bypass truehit truedamage uninterruptible query filtro",
  lead: "Tags dizem o que a entidade pode fazer agora; traits dizem o que uma ação é. Os filtros do framework inteiro (imunidade, bloqueio, listeners) se apoiam nas duas.",
  html: `
<h2>Tags (permissões da entidade)</h2>
${T(["Tag", "Padrão", "Efeito quando ligada/desligada"], [
  ["<code>canMove</code>", "true", "false: não anda; Forces que pedem controle (RequiresControl) não valem."],
  ["<code>canCast</code>", "true", "false: nenhuma skill nova começa."],
  ["<code>canRotate</code>", "true", "false: não gira."],
  ["<code>canDisplace</code>", "true", "false: Forces externas (knockback, vento, grab de outro) não deslocam; o próprio dash sim."],
  ["<code>iFrame</code>", "false", "true: imune a hit (menos traits em <code>bypassBy</code>, ex.: TrueHit)."],
  ["<code>block</code>", "false", "true: o hit passa pelo bloqueio do status dono da tag (" + L("conceitos.dano", "pipeline de dano") + ")."],
  ["<code>interrupt</code>", "false", "true: ao entrar, cancela as skills ativas, menos as Uninterruptible."],
])}
<p>Tags vêm só de status/estados ativos. Leia com <code>entity.GetActiveTags()</code>.</p>

<h2>Traits (o que a ação é)</h2>
<p>Lista de strings no <code>data.traits</code> de uma skill ou status (e, por hit, em <code>opts.Traits</code>). O motor usa algumas:</p>
${T(["Trait", "Uso no motor"], [
  ["<code>DOT</code>", "Dano periódico. Escudos e listeners filtram (<code>Query = { None = { DOT } }</code>)."],
  ["<code>TrueHit</code>", "Fura o iFrame e ignora bloqueio comum (BlockIgnore)."],
  ["<code>TrueDamage</code>", "Fura as proteções de stat (Defense, Armor)."],
  ["<code>BlockBreak</code>", "Quebra o bloqueio (encerra o status de block), salvo <code>Unbreakable</code>."],
  ["<code>Unbreakable</code>, <code>TrueBlock</code>", "No status de bloqueio: não quebra / não é ignorado por TrueHit."],
  ["<code>Uninterruptible</code>", "Na skill: não é cancelada pela tag interrupt."],
  ["<code>Stackable</code>", "No status: permite stack."],
  ["<code>Melee</code>, <code>Ultimate</code>", "Marcas de conteúdo (as skills de exemplo filtram por elas)."],
  ["<code>EffectShield</code>, <code>LightCancel</code>, <code>HeavyCancel</code>", "Reservadas."],
])}
<p>Você pode criar traits próprias (qualquer string): elas passam pelo contexto e servem de filtro em <code>Query</code>. Prefira declarar em ${L("enum.traits", "Enum.Traits")} para não ter string mágica.</p>

<h2>Query (filtro por traits)</h2>
${C(`
Query = {
    All = { Traits.Melee },        -- precisa de TODAS
    Any = { Traits.DOT, "Fogo" },  -- precisa de PELO MENOS UMA
    None = { Traits.TrueDamage },  -- não pode ter NENHUMA
}
`)}
<p>Avaliada contra <code>context.traits</code> do evento. Sem Query, casa sempre. Veja ${L("api.TraitQuery.Match")}.</p>

<h2>Imunidade (iFrame e afins)</h2>
<p>Um status com uma tag de imunidade e <code>bypassBy = { traits }</code> torna a entidade imune a hits que não tenham uma das traits. As regras são calculadas uma vez para o servidor (com dois status com a mesma tag, só passa a trait que os dois deixam passar).</p>
`,
});

// ------------------------------------------------------------------ eventos
DOCS.page({
  id: "conceitos.eventos",
  parent: "basico",
  order: 50,
  title: "Eventos: Listen, IN/OUT e breakpoints",
  kw: "evento listener listen escutar ouvir reagir pub sub trigger triggerset breakpoint in out emit priority prioridade owner ttd limit inherit herdar listenworld global",
  lead: "Quase toda mecânica de jogo é uma reação a um momento do combate. O framework emite esses momentos como breakpoints; você escuta com Listen, sem editar o motor.",
  html: `
<h2>Inscrição</h2>
${C(`
local Enum = StateTable.Enum
local unsubscribe = entity:Listen({
    Role = Enum.Roles.IN,                  -- IN: o que acontece COM a entidade
    Breakpoint = Enum.Breakpoints.PreDamage,
    Query = { None = { Enum.Traits.TrueDamage } },
    Priority = 10,                         -- maior roda antes (empate: ordem de inscrição)
    Owner = StateTable.OwnerToken(entity, "Armadura"),
    TTD = 5,                               -- expira em 5 s
    Limit = { Max = 3, OnExhaust = "Remove" },
    Action = function(ctx)
        ctx.damage *= 0.5
    end,
})
`)}
${T(["Campo", "O quê"], [
  ["<code>Role</code>", "<code>IN</code> ou <code>OUT</code> (" + L("enum.breakpoints", "Enum.Roles") + ")."],
  ["<code>Breakpoint</code>", "Qual momento (tabela abaixo)."],
  ["<code>Action</code>", "<code>function(ctx, ...)</code>. Erro vira warn; os outros listeners seguem."],
  ["<code>Query</code>", "Filtro por traits do contexto (" + L("conceitos.tags", "Query") + ")."],
  ["<code>Priority</code>", "Ordem. Listeners do motor usam " + L("enum.breakpoints", "Enum.EnginePriority") + " (rodam antes de todos)."],
  ["<code>Owner</code>", "Para desinscrever em lote: <code>entity:UnsubscribeByOwner(owner)</code>. Use <code>StateTable.OwnerToken(entidade, tag)</code>, não string (string é global entre entidades)."],
  ["<code>TTD</code>", "Segundos até expirar."],
  ["<code>Limit</code>", "<code>{ Max, OnExhaust = 'Remove' | 'Disable', Scope = 'Holder' | 'Branch' | 'Tree' }</code>: quantas vezes pode disparar."],
  ["<code>Inherit</code>", "<code>{ Generations = n }</code>: entidades filhas (Create com pai) herdam a inscrição por n gerações."],
])}
<p>Dentro de uma skill, use <code>self:Listen(sub)</code>: o Owner é o runner e a inscrição sai sozinha quando a skill termina.</p>

<h2>IN e OUT</h2>
<p><span class="badge in">IN</span> é emitido na entidade que <b>sofre</b>: apanhou, morreu, foi curada, entrou em Stun. <span class="badge out">OUT</span> é emitido na entidade que <b>causa</b>: acertou, causou dano, matou, curou, começou uma skill. O OUT de dano, morte e cura vai para o <b>dono do efeito</b>: num DOT, para quem aplicou o DOT, não para a vítima onde o runner roda (${L("api.StateTable.EffectOwner", "EffectOwner")}).</p>

<h2>Todos os breakpoints</h2>
${T(["Breakpoint", "Papel", "Quem emite / quando", "ctx"], [
  ["<code>onHit</code>", '<span class="badge out">OUT</span>', "Atacante, antes do dano chegar no alvo (ApplyDamage). Pode mudar <code>ctx.damage</code>, traits e <code>ctx.inherited</code>.", "HitContext"],
  ["<code>PreDamage</code>", '<span class="badge in">IN</span>', "Alvo, depois de imunidade/bloqueio/proteções e antes do HP mudar. <code>ctx.cancelled = true</code> cancela.", "HitContext"],
  ["<code>PostDamage</code>", '<span class="badge in">IN</span>', "Alvo, depois do HP mudar (<code>ctx.actualDamage</code>).", "HitContext"],
  ["<code>OnDamage</code>", '<span class="badge out">OUT</span>', "Dono do dano, depois do HP mudar, em todo dano (direto e indireto).", "HitContext"],
  ["<code>OnHeal</code>", '<span class="badge in">IN</span> <span class="badge out">OUT</span>', "IN no curado antes de aplicar (pode mudar <code>ctx.damage</code>); OUT no dono da cura com <code>ctx.actualHeal</code>.", "HitContext"],
  ["<code>OnDeath</code>", '<span class="badge in">IN</span> <span class="badge out">OUT</span>', "IN no morto; OUT no dono do que matou (<code>ctx.targetEntity</code> = vítima).", "HitContext"],
  ["<code>OnRevive</code>", '<span class="badge in">IN</span>', "No revivido.", "HitContext"],
  ["<code>PreApplyStatus</code>", '<span class="badge out">OUT</span>', "Dono do efeito, antes de um status entrar. Cancela ou injeta em <code>ctx.inherited</code>.", "HitContext + incomingStatus"],
  ["<code>OnInterrupt</code>", '<span class="badge in">IN</span>', "Entidade que recebeu um estado com a tag interrupt.", "HitContext + incomingStatus"],
  ["<code>onStart</code>", '<span class="badge out">OUT</span>', "Entidade dona, depois do onStart de uma skill/status. <code>ctx.sourceRunner</code> = o runner que começou.", "RunnerContext"],
  ["<code>onEnd</code>", '<span class="badge out">OUT</span>', "Entidade dona, no fim de uma skill/status, com <code>ctx.reason</code>.", "RunnerContext"],
  ["<code>onTrigger</code>, <code>onRecast</code>, <code>onRelease</code>", "—", "Callbacks da própria skill (não são emitidos como evento).", ""],
])}

<h2>Eventos de qualquer entidade</h2>
<p>${L("api.EntityCore.ListenWorld", "EntityCore.ListenWorld")} escuta um canal de <b>todas</b> as entidades. A Action recebe <code>(ctx, entidadeQueEmitiu, ...)</code>. Sem ouvinte no mundo, o Emit não paga nada a mais.</p>
${C(`
local EntityCore = require(game.ServerScriptService.EntityData.EntityCore)
EntityCore.ListenWorld({
    Role = Enum.Roles.IN, Breakpoint = Enum.Breakpoints.OnDeath,
    Action = function(ctx, morto)
        if morto.Type == EntityCore.EntityTypes.NPC then pontos += 1 end
    end,
})
`)}

<h2>Configuração do Health</h2>
<p>Atalho para os eventos IN mais comuns: <code>DataManager.Create(m, comps, { Health = { Events = { onDamage = fn, onHeal = fn, onDeath = fn, onRevive = fn } } })</code>. <code>onDamage</code> é o PostDamage.</p>

<h2>Emitindo os seus</h2>
<p>Qualquer string serve de breakpoint: <code>entity:Emit(Enum.Roles.OUT, "OnCardPlayed", ctx)</code>. Para não montar contexto à toa, confira antes com <code>entity:HasListeners(role, breakpoint)</code>.</p>
`,
});

// ------------------------------------------------------------------ dano
DOCS.page({
  id: "conceitos.dano",
  parent: "basico",
  order: 60,
  title: "Pipeline de dano",
  kw: "dano damage hit golpe ataque applydamage takedamage pipeline fórmula defense armor mitigação bloqueio block parry damagemult multiplicador",
  lead: "Todo dano passa pelo mesmo caminho, do atacante ao alvo. Cada etapa é declarada em dado (enums, data da skill/status) e tem um breakpoint para reagir.",
  html: `
<h2>Do lado do atacante: ApplyDamage</h2>
<p><code>self:Damage(alvo, n, opts)</code> numa skill (ou <code>entity.ApplyDamage(n, runner, alvo, opts)</code>):</p>
<ol class="flow">
  <li>Monta o HitContext: dano base, traits da skill (+ <code>opts.Traits</code>), efeitos (<code>data.effects</code> + <code>opts.Effects</code>), <code>opts.Inherited</code>, ponto do impacto (<code>opts.Hit</code>), dono do efeito.</li>
  <li>Multiplica por <code>DamageMult</code> do atacante (Attributes), salvo <code>opts.Prescaled</code>.</li>
  <li><span class="badge out">OUT</span> <code>onHit</code> no atacante.</li>
  <li>Chama o <code>TakeDamage</code> do alvo com o contexto.</li>
</ol>

<h2>Do lado do alvo: TakeDamage</h2>
<ol class="flow">
  <li>Morto: recusa. Hit de 0 de dano só segue se tiver efeitos (slow puro, marca).</li>
  <li><b>Imunidade</b> (Status): tag como iFrame barra, salvo trait em <code>bypassBy</code>.</li>
  <li><b>Bloqueio</b> (Status): com a tag <code>block</code>, o status dono decide (<code>onTrigger</code>, ou <code>data.block</code>). <code>BlockBreak</code> quebra; <code>TrueHit</code> ignora (salvo <code>TrueBlock</code>). <code>ctx.blocked</code> = o bloqueio zerou o dano.</li>
  <li><b>Proteções de stat</b> (Attributes): ${L("enum.dano", "Enum.DamageMitigation")} em ordem. <code>TrueDamage</code> fura.</li>
  <li><span class="badge in">IN</span> <code>PreDamage</code>: listeners mudam ou cancelam. Dano negativo vira 0 (listener não transforma dano em cura).</li>
  <li>HP muda (pode ir a 0 e matar). Registro no histórico.</li>
  <li><b>Efeitos on-hit</b>: cada status de <code>ctx.effects</code>, pela política (${L("enum.efeitos", "Enum.EffectDefaults")}): bloqueado não aplica, 0 de dano aplica.</li>
  <li><span class="badge in">IN</span> <code>PostDamage</code> no alvo.</li>
  <li><span class="badge out">OUT</span> <code>OnDamage</code> no dono do dano.</li>
</ol>

<h2>Fórmula</h2>
${C(`
dano = base * DamageMult(atacante)            -- salvo Prescaled
dano = bloqueio(dano)                         -- Full zera, Flat subtrai, Percent tira fração
dano = dano * 100 / (100 + Defense)           -- Defense negativa amplifica: dano * (2 - 100/(100 - Defense))
dano = max(0, dano - Armor)
-- e depois os listeners de PreDamage
`)}
<p>A ordem e os modos são dado: troque, reordene ou acrescente proteções em ${L("enum.dano", "Enum.DamageMitigation")} (ex.: resistência mágica ligada a um stat novo, furada por uma trait sua).</p>

<h2>Bloqueio declarado</h2>
${T(["data.block", "Efeito"], [
  ["<code>{ mode = Full }</code>", "Zera o dano; num escudo de status, barra o status."],
  ["<code>{ mode = Flat, value = 10 }</code>", "Tira 10 do dano."],
  ["<code>{ mode = Percent, value = 0.4 }</code>", "Tira 40% do dano."],
  ["<code>{ mode = Custom }</code>", "O <code>onTrigger</code> decide (obrigatório). Devolve o dano novo, ou true para barrar status."],
])}
<p>Sem <code>block</code> e sem <code>onTrigger</code>, o status com a tag não bloqueia (e avisa uma vez).</p>

<h2>Opções por hit</h2>
${C(`
self:Damage(alvo, 30, {
    Traits = { Enum.Traits.TrueDamage },          -- só deste hit
    Effects = { StateTable.Status.Bleed },        -- status on-hit só deste hit
    Hit = hitResult,                              -- ponto do impacto -> ctx.hit
    Prescaled = true,                             -- já escalado: não aplica DamageMult
    Inherited = { stacks = 3 },                   -- payload para os status on-hit
})
`)}

<h2>Retorno</h2>
<p><code>sucesso, danoReal</code>. Se a cadeia estava funda demais, <code>false, Enum.ChainOutcomes.Deferred</code>: o hit inteiro roda no próximo frame (${L("conceitos.cadeias")}).</p>
`,
});

// ------------------------------------------------------------------ cura
DOCS.page({
  id: "conceitos.cura",
  parent: "basico",
  order: 70,
  title: "Cura e sobrevida",
  kw: "cura heal vida hp sobrevida overheal healcap teto maxhp lifesteal roubo de vida regeneração",
  lead: "HP acima do MaxHP é permitido: é escolha de design (sobrevida). O teto da cura é uma política declarada, não um corte do motor.",
  html: `
<h2>Regras</h2>
<ul>
  <li><code>Heal(n, opts)</code> nunca leva o HP além de <code>Cap × MaxHP</code> e <b>nunca reduz</b> o HP (quem está acima do teto continua lá).</li>
  <li>O teto padrão é ${L("enum.cura", "Enum.HealthDefaults.HealCap")} = 1 (até o MaxHP). Por entidade: <code>Health = { HealCap = 1.5 }</code>. Por cura: <code>Heal(n, { Cap = 2 })</code>. <code>math.huge</code> = sem teto.</li>
  <li><code>SetHP(v)</code> define o valor exato, sem corte (só não fica negativo; 0 mata).</li>
  <li><code>Revive(hp?)</code> volta com exatamente <code>hp</code> (ou o MaxHP).</li>
  <li><code>SetMaxHP(v)</code> troca o teto mantendo a proporção do HP.</li>
</ul>

<h2>Eventos</h2>
<p><span class="badge in">IN</span> <code>OnHeal</code> no curado, antes de aplicar (o listener muda <code>ctx.damage</code>, que é o valor da cura). Com <code>opts.Source</code>, <span class="badge out">OUT</span> <code>OnHeal</code> no dono da cura com <code>ctx.actualHeal</code> (quanto subiu de fato).</p>
${C(`
local subiu = alvo.Heal(40, { Source = self.Runner, Traits = { "Sagrado" }, Cap = 1.2 })
`)}
<p>Lifesteal: ${L("receitas.lifesteal")}. Escudo de vida como sobrevida: ${L("receitas.sobrevida")}.</p>
`,
});

// ------------------------------------------------------------------ morte
DOCS.page({
  id: "conceitos.morte",
  parent: "basico",
  order: 80,
  title: "Morte e revive",
  kw: "morte morrer death die matar kill revive reviver respawn crédito killer",
  lead: "HP 0 marca a entidade como morta para o motor. O Humanoid não morre e não há respawn forçado: isso é do jogo.",
  html: `
<h2>O que o motor faz</h2>
${T(["Regra", "Padrão", "Onde desligar"], [
  ["A morte cancela as skills ativas", "true", "<code>Combat = { CancelSkillsOnDeath = false }</code>"],
  ["Morto não recebe status novo", "true", "<code>Status = { RefuseStatusOnDeath = false }</code> ou <code>data.allowOnDead</code> no status"],
  ["Morto não inicia cast", "true", "<code>Combat = { RefuseCastOnDeath = false }</code>"],
])}
<p>Padrões em ${L("enum.morte", "Enum.DeathDefaults")}. Cada componente resolve a regra uma vez, no <code>new()</code>: regra desligada custa zero.</p>

<h2>Crédito</h2>
<p><span class="badge in">IN</span> <code>OnDeath</code> no morto; <span class="badge out">OUT</span> <code>OnDeath</code> no <b>dono</b> do que matou. Morte por Bleed credita quem aplicou o Bleed (o motor sobe o <code>Source</code> do status até um runner de skill).</p>

<h2>Respawn do player</h2>
<p>A cada <code>CharacterAdded</code>, o <code>Main.server</code> cria a entidade de novo com o mesmo ID (<code>Player_&lt;UserId&gt;</code>); a anterior é destruída. Uma possessão em andamento é solta depois que o corpo novo existe.</p>
`,
});

// ------------------------------------------------------------------ context
DOCS.page({
  id: "conceitos.context",
  parent: "avancado",
  order: 10,
  title: "Context por Breakpoint",
  kw: "context ctx contexto inherited herdar herança payload depth profundidade history histórico sourcerunner rootorigin runnercontext hitcontext",
  lead: "Cada breakpoint recebe um contexto montado na hora. Não existe herança implícita entre skills: o que passa de pai para filho vai explícito em inherited.",
  html: `
<h2>Dois formatos</h2>
<p>Dono do formato: <code>ServerStorage/Modules/Combat/Types</code>.</p>
<h3>RunnerContext (callbacks da skill, OUT.onStart/onEnd)</h3>
${T(["Campo", "O quê"], [
  ["<code>depth</code>", "Profundidade na cadeia (cast por input = 1)."],
  ["<code>history</code>", "Nomes da raiz até este runner (congelado)."],
  ["<code>rootOrigin</code>", "Entidade que começou a cadeia."],
  ["<code>sourceRunner</code>", "O runner imediatamente anterior: quem aplicou/criou este (nil no cast por input). No OUT.onStart/onEnd, é o próprio runner que emitiu."],
  ["<code>input</code>", "O InputEvent que originou o cast (Intent, Gesture, HeldTime, Target, Point)."],
  ["<code>inherited</code>", "Payload explícito do pai (só leitura)."],
  ["<code>reason</code>", "Só no onCancel/onEnd: " + L("enum.fim", "Enum.EndReasons") + "."],
])}
<h3>HitContext (dano, cura, status)</h3>
${T(["Campo", "O quê"], [
  ["<code>damage</code>", "Mutável. Na cura, é o valor da cura."],
  ["<code>source</code>", "O runner que causou."],
  ["<code>sourceEntity</code>", "Onde o runner roda (num DOT, a vítima)."],
  ["<code>ownerEntity</code>", "Dono do efeito: recebe os OUT de dano/morte/cura."],
  ["<code>targetEntity</code>", "O alvo."],
  ["<code>traits</code>, <code>effects</code>", "Traits do hit; status on-hit."],
  ["<code>direction</code>", "Direção do atacante (mundo e local)."],
  ["<code>hit</code>", "Ponto do impacto (<code>position</code>, <code>normal</code>, <code>instance</code>), quando veio de hitbox."],
  ["<code>inherited</code>", "Mutável: o que este hit/aplicação passa para o que ele gerar."],
  ["<code>blocked</code>, <code>actualDamage</code>, <code>actualHeal</code>", "Resultado (bloqueio zerou; quanto o HP mudou)."],
  ["<code>cancelled</code>, <code>reason</code>", "Listener de PreDamage/PreApplyStatus cancela."],
  ["<code>incomingStatus</code>", "O status entrando (PreApplyStatus, OnInterrupt, escudo)."],
])}

<h2>inherited: passando dado adiante</h2>
${C(`
-- a skill passa para o status
self:ApplyStatus(Status.Queimadura, { Target = alvo, Inherited = { mult = 3 } })

-- dentro do status
onStart = function(self, ctx)
    self.mult = ctx.inherited.mult or 1
end
`)}
<ul>
  <li>Para status: <code>ApplyStatus(..., { Inherited })</code>.</li>
  <li>Para os status on-hit de um hit: <code>Damage(..., { Inherited })</code>. O OUT.onHit ainda pode injetar.</li>
  <li>Para uma skill criada por skill: <code>SkillRunner.new(..., inherited)</code>.</li>
</ul>
<p>Nada herda sozinho: o neto só recebe o que o filho passar. O filho recebe uma cópia congelada (o pai não muda o que o filho lê).</p>

<h2>Checagem pré-output</h2>
<p>Antes de uma ação sair para o mundo, o dono pode inspecionar e mudar: <span class="badge out">OUT</span> <code>onHit</code> (dano) e <span class="badge out">OUT</span> <code>PreApplyStatus</code> (status). Os dois filtram por traits, cancelam e injetam em <code>ctx.inherited</code>. É o mesmo contexto servindo à propagação e à interceptação: não são dois sistemas.</p>
${C(`
-- "os próximos 3 venenos que eu aplicar vêm com o triplo"
self:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.PreApplyStatus,
    Query = { All = { Enum.Traits.DOT } },
    Limit = { Max = 3, OnExhaust = "Remove" },
    Action = function(ctx) ctx.inherited.mult = 3 end,
})
`)}

<h2>Profundidade</h2>
<p>Lógica por geração lê <code>ctx.depth</code> direto ("o minion só invoca outro até depth 3").</p>
`,
});

// ------------------------------------------------------------------ cadeias
DOCS.page({
  id: "conceitos.cadeias",
  parent: "avancado",
  order: 20,
  title: "Cadeias e limites",
  kw: "cadeia chain reação em cadeia recursão recursion loop infinito reflexo explosão deferred adiar fila chainlimits max_recursion largura",
  lead: "Dano que gera status que gera dano, reflexo de parry contra reflexo, explosão em cadeia: o motor aguenta cadeias longas e corta as infinitas, sem travar o servidor.",
  html: `
<h2>Síncrona (mesma pilha)</h2>
<p>Dano → morte → dano na mesma pilha conta profundidade. Acima de ${L("enum.cadeia", "MAX_RECURSION")} (50), a ação não roda nesta pilha: vai para uma fila e roda no próximo frame, numa pilha nova. <code>TakeDamage</code>/<code>ApplyDamage</code> devolvem <code>false, "Deferred"</code>; <code>ApplyStatus</code> devolve <code>nil</code>. A cadeia longa e finita termina inteira (80 alvos em linha: 2 frames).</p>
<p>Cada vez que uma ação adiada adia outra, conta uma geração. Acima de <code>maxDeferrals</code> (20) a ação é recusada com aviso: o ping-pong infinito de dois reflexos para aí (~1000 reflexos, um lote por frame).</p>

<h2>Assíncrona (runner que cria runner)</h2>
<p>Status que aplica status, skill que cria skill: o limite é a <b>largura</b>, runners vivos ao mesmo tempo sob a mesma raiz (<code>maxLiveRunnersPerRoot</code> = 256). Cadeia linear não tem limite (um status que se renova é legítimo); a árvore que dobra a cada geração para na largura, com o motivo <code>refused</code>.</p>

<h2>Configuração</h2>
${C(`
Enum.ChainLimits = {
    deferAtMaxDepth = true,       -- false: acima de MAX_RECURSION recusa na hora
    maxDeferrals = 20,            -- gerações de adiamento por cadeia
    deferredPerFrame = 256,       -- orçamento da fila por frame
    maxLiveRunnersPerRoot = 256,  -- largura da cadeia assíncrona
}
`)}
<p>Se um jogo precisar de mais (uma aura de partida inteira num MOBA grande), aumente na config.</p>
${N("<p>Para um reflexo que não deve adiar, quebre a cadeia você mesmo: um delay, ou um status de imunidade curto em quem acabou de refletir.</p>")}
`,
});

// ------------------------------------------------------------------ cooldown
DOCS.page({
  id: "conceitos.cooldown",
  parent: "basico",
  order: 90,
  title: "Cooldown",
  kw: "cooldown recarga cd tempo de recarga cargas charges recast refund devolver redução cooldownreduction cdr manual commit",
  lead: "A skill declara a política no data; o CooldownPolicy executa. Cargas, recast, devolução por motivo, redução por stat e herança entre entidades, sem código na skill.",
  html: `
<h2>Declaração</h2>
${C(`
data = {
    cooldown = 6,                 -- obrigatório (0 é válido)
    cooldownPolicy = {
        start = "Cast",           -- Cast | End | Manual
        recast = "Restart",       -- Blocked | Restart | Free | número (s); obrigatório com onRecast
        refund = { fizzle = 1, cancel = 0.5 }, -- fração devolvida por motivo de fim
        charges = 2,              -- 2 usos; cada um recarrega em 'cooldown' (um por vez)
        ignoreReduction = false,  -- true: CooldownReduction não vale aqui
        maxReduction = 0.6,       -- teto da redução para esta skill
    },
}
`)}

<h2>start</h2>
${T(["Valor", "Quando o cooldown começa"], [
  ["<code>Cast</code> (padrão)", "Na ativação, antes do onStart. Uma cadeia que tente castar a mesma skill no onStart já encontra o cooldown."],
  ["<code>End</code>", "No fim do runner (canalização, toggle)."],
  ["<code>Manual</code>", "Quando a skill chama <code>self:CommitCooldown()</code> (o cast de fato aconteceu). Sem confirmar, nada é cobrado."],
])}

<h2>recast</h2>
<p>Só para skill com <code>onRecast</code>. <code>Blocked</code>: espera o cooldown e não reinicia. <code>Restart</code>: espera e reinicia (é o ritmo do combo do M1). <code>Free</code>: ignora o cooldown. Número: intervalo próprio entre toques.</p>

<h2>refund</h2>
<p>No fim, devolve <code>refund[motivo] × duração</code>. Padrão (${L("enum.cooldown", "Enum.CooldownDefaults")}): <code>error</code>, <code>fizzle</code> e <code>refused</code> devolvem tudo (erro, desistência e recusa do motor não cobram). <code>self:Fizzle()</code> é a forma de desistir do cast (alvo não encontrado).</p>

<h2>Redução</h2>
<p>Stat <code>CooldownReduction</code> (fração). Aplicada quando uma contagem começa: <code>duração = cooldown × (1 − min(redução, teto))</code>. O teto padrão é 0,8. Mudar o stat não reescala contagens em andamento; para isso, <code>entity.ReduceCooldown(nome, segundos)</code>.</p>

<h2>API</h2>
<p>Na entidade (Combat): ${L("api.Combat.HasCooldown", "HasCooldown")}, ${L("api.Combat.GetCooldown", "GetCooldown")}, ${L("api.Combat.ReduceCooldown", "ReduceCooldown")}, ${L("api.Combat.GrantCooldownCharge", "GrantCooldownCharge")}, ${L("api.Combat.ResetCooldown", "ResetCooldown")}, ${L("api.Combat.ExportCooldown", "ExportCooldown")}/${L("api.Combat.ImportCooldown", "ImportCooldown")}. Herança (skill roubada, possessão): ${L("api.CooldownPolicy.Transfer", "CooldownPolicy.Transfer")}.</p>
<p>Status não usam o CooldownPolicy: o cooldown de reaplicação deles é <code>data.cooldown</code> do status.</p>
`,
});

// ------------------------------------------------------------------ loadout
DOCS.page({
  id: "conceitos.loadout",
  parent: "basico",
  order: 100,
  title: "Loadout em camadas",
  kw: "loadout slot skills equipadas kit personagem forma modo transformação camada layer equipar trocar roubar skill",
  lead: "O loadout efetivo (slot → skill) é a mesclagem de camadas, da Base para cima: a de cima vence no slot. Trocar de forma, de modo de arma ou ganhar uma skill temporária mexe só na camada dele.",
  html: `
<h2>Camadas</h2>
${T(["Camada", "Quem usa"], [
  ["<code>Base</code>", "A forma do personagem (CharacterDatabase) e todo <code>EquipSkill</code> sem camada. Não sai."],
  ["<code>WeaponMode</code>", "O modo da arma (WeaponTransform aplica o <code>Loadout</code> do modo)."],
  ["qualquer nome", "Camadas do jogo: buff que troca o Q, item, transformação temporária."],
])}
${C(`
-- troca só o Ability1 enquanto a camada existir
entity.ApplyLoadout({ Slots = { [Intents.Id.Ability1] = Keys.Schema.Skill3 } }, "Furia")
-- esvazia um slot de propósito nesta camada
entity.ApplyLoadout({ Slots = { [Intents.Id.Ultimate] = false } }, "Silenciado")
-- tira a camada: volta a valer o que estava embaixo
entity.RemoveLoadoutLayer("Furia")
`)}
<p>Formato do loadout: <code>{ Slots = { [Intents.Id] = chave | skill | false } }</code> ou <code>{ List = { chave, ... } }</code> (ocupa os slots na ordem de <code>Intents.SkillOrder</code>).</p>

<h2>Personagem e forma</h2>
<p><code>ServerStorage/DataBase/CharacterDatabase/&lt;Kit&gt;/&lt;Modo&gt;</code> declara <code>Stats</code>, <code>Loadout</code> e <code>Weapon</code>. O Combat carrega <code>ChosenChar</code>/<code>Mode</code> no OnAdded (padrão ${L("enum.personagem", "Enum.CombatDefaults")}). <code>Combat = { ChosenChar = false }</code> cria a entidade sem personagem (kit montado em runtime). Veja ${L("receitas.personagem")}.</p>

<h2>Skills soltas</h2>
<p><code>entity.EquipSkill(slot, chaveOuTabela, camada?)</code> equipa uma skill; <code>AddSkill</code> ocupa o próximo slot livre; <code>UnequipSlot</code> esvazia. A UI é por <b>slot</b>, não por skill: trocar a skill do slot não exige nada novo na HUD.</p>
`,
});

// ------------------------------------------------------------------ input
DOCS.page({
  id: "conceitos.input",
  parent: "basico",
  order: 110,
  title: "Input: intents, gestos e alvo",
  kw: "input entrada botão tecla teclado mouse gamepad mobile intent intenção gesto tap hold segurar double tap duplo carregar charge payload alvo target point ponto mira rebind",
  lead: "O cliente não manda tecla nem nome de skill: manda a intenção (\"quero usar o slot X\"). Gestos (tap, hold, double tap) e um alvo/ponto opcional viajam junto. NPC usa o mesmo caminho.",
  html: `
<h2>O caminho</h2>
<ol class="flow">
  <li><b>Cliente</b> (${L("api.InputService", "InputService")}): tecla, mouse, gamepad ou botão de tela vira <code>Press/Release</code> da intent, pelo ${L("api.InputConfig", "InputConfig")}.</li>
  <li><b>Rede</b>: <code>RequestIntent(intent, isDown, payload?)</code>.</li>
  <li><b>Servidor</b> (InputValidator): valida tipo, taxa (por intent) e o payload; descobre a entidade dirigida (respeita Lock e possessão).</li>
  <li>${L("api.GestureResolver", "GestureResolver")}: com o <code>data.input</code> da skill do slot, transforma Press/Release em eventos (Activate com Press/Tap/Hold/DoubleTap, e Release).</li>
  <li>${L("api.SkillHandler.HandleIntent", "SkillHandler.HandleIntent")}: ativa, faz recast ou entrega o Release ao runner certo.</li>
</ol>

<h2>Intents</h2>
<p><code>Primary, Dash, Ability1, Ability2, Ability3, Ultimate</code> (${L("api.Intents", "Intents.Id")}). Para mais botões: acrescente em <code>Intents.Id</code>, em <code>SkillOrder</code> (se for slot de skill) e dê um binding no InputConfig. Isso é conteúdo de jogo, não mudança de motor.</p>
<p>Eixos contínuos não são intents: direção de movimento (<code>RequestDir</code>) e de câmera (<code>RequestLook</code>) têm remotes próprios.</p>

<h2>Gestos</h2>
${C(`
data = {
    input = { Hold = 0.4, Tap = true },  -- Hold após 0,4 s; toque curto ainda ativa (Tap)
    -- input = { DoubleTap = true }      -- 2º toque na janela (Intents.Defaults.DoubleTapWindow)
}
callbacks = {
    onStart = function(self, ctx)
        if ctx.input.Gesture == Intents.Gesture.Hold then self.carregado = true end
    end,
    onRelease = function(self, ctx)
        local segurou = ctx.input.HeldTime -- segundos
    end,
}
`)}
<p>Sem <code>data.input</code> a skill ativa no Press, sem atraso. Só tem atraso a skill que declara DoubleTap (o resolver espera a janela).</p>
${T(["Gesto", "Contrato"], [
  ["Press (raw)", "Activate(Press) no Press → Release ao soltar."],
  ["Hold", "Activate(Hold) depois de N s segurando → Release; ou Activate(Tap) se soltar antes."],
  ["DoubleTap", "Activate(DoubleTap) no 2º Press → Release; ou Activate(Tap) depois da janela."],
])}

<h2>Alvo e ponto (payload)</h2>
<p>O cliente pode mandar <code>{ Target = idDaEntidade, Point = Vector3 }</code> no Press e no Release. O servidor só deixa passar Target string curta que existe (<code>DataManager.Exists</code>) e Point finito dentro do mundo. Alcance e linha de visão são com a skill.</p>
${C(`
-- cliente: um provider para todo envio
InputService.SetPayloadProvider(function(intent)
    local mouse = game.Players.LocalPlayer:GetMouse()
    local model = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
    return { Target = model and model:GetAttribute("EntityID"), Point = mouse.Hit.Position }
end)

-- servidor, na skill
onStart = function(self, ctx)
    local alvo = ctx.input.Target and DataManager.Get(ctx.input.Target)
    if not alvo then return self:Fizzle() end -- devolve o cooldown
end
`)}

<h2>NPC e scripts</h2>
${C(`
SkillHandler.HandleIntent(npc.ID, Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate, Intents.Gesture.Press))
SkillHandler.HandleMovementInput(npc.ID, direcao)
SkillHandler.HandleLookInput(npc.ID, olhar)
`)}

<h2>Botões de tela</h2>
<p>Qualquer GuiButton com a tag <code>InputButton</code> e o atributo <code>Intent</code> vira fonte da intent, sem código. A HUD de cooldown acha o botão pelo mesmo atributo.</p>
`,
});

// ------------------------------------------------------------------ movimento
DOCS.page({
  id: "conceitos.movimento",
  parent: "basico",
  order: 120,
  title: "Movimento e Forces",
  kw: "movimento movement force força dash knockback empurrar puxar vento voo voar gravidade hard soft prioridade eixo massa agarrar grab attach tether follow seguir",
  lead: "O MovementComponent guarda a intenção (direção, mira) e uma lista de Forces. O MovementController resolve tudo uma vez por passo de física, eixo a eixo, pelo ForceRig.",
  html: `
<h2>Uma Force</h2>
${C(`
local id = entity.AddForce({
    Type = "Dash",              -- rótulo livre
    Duration = 0.35,
    Speed = 80,                 -- número ou function(elapsed, duration) -> number
    Direction = dir,            -- Vector3 ou function(elapsed, duration, ctx) -> Vector3
    Hard = true,                -- fixa os eixos (ignora a caminhada)
    IgnoreGravity = true,       -- reivindica o Y (sem cair durante o dash)
    Priority = 10,              -- empate de eixo: maior vence
})
entity.RemoveForce(id)
`)}

<h2>Hard × Soft</h2>
<ul>
  <li><b>Hard</b>: fixa a velocidade nos eixos reivindicados (padrão: todos). Dash, ultimate, voo.</li>
  <li><b>Soft</b>: <b>soma</b> com a caminhada no eixo (padrão: X e Z). O alvo é caminhada pretendida + soma das Soft: dá para andar contra o vento.</li>
  <li>Empate de eixo: maior <code>Priority</code> vence.</li>
</ul>

<h2>Campos importantes</h2>
${T(["Campo", "O quê"], [
  ["<code>Key</code>", "Com uma Force ativa de mesma Key, o AddForce <b>renova</b> (zera o tempo, troca o dado, mesmo ID) em vez de empilhar. Para força reaplicada em loop (vento, esteira)."],
  ["<code>RequiresControl</code>", "Padrão true: cancelada se a entidade não pode se mover (Root/Stun). Externas (knockback, vento) usam false."],
  ["<code>External</code>", "Padrão = (RequiresControl == false). Externa é barrada por <code>canDisplace = false</code>; a própria (dash) não."],
  ["<code>Axes</code>", "<code>{ X, Y, Z }</code>: eixos do mundo reivindicados."],
  ["<code>TurnRate</code>", "Radianos/s: suaviza a mudança de direção."],
  ["<code>FaceDirection</code>", "Padrão = Hard: gira o corpo para a direção."],
  ["<code>FollowTarget</code>", "Persegue uma peça (tether elástico) em vez de andar numa Direction."],
  ["<code>MaxForce</code>", "Força absoluta (sem a escala por massa)."],
  ["<code>OnEnd</code>", "Chamado no fim da Force."],
])}
<p>Lista completa em ${L("api.Movement.AddForce")}.</p>

<h2>Direção pela câmera a cada frame</h2>
${C(`
Direction = function(elapsed, duration, ctx)
    local look = ctx.Entity.GetLookDirection()  -- câmera do player (plana)
    return look.Magnitude > 0.1 and look or ctx.Entity.GetDirection()
end,
`)}

<h2>Massa</h2>
<p>Com <code>Force_Mass_Scaling</code> (${L("api.Settings", "Physics/Settings")}), o orçamento padrão de uma Soft e a caminhada do NPC sem Humanoid saem de aceleração × massa: o vento empurra o dummy e o chefe igual. Por entidade: <code>Movement = { MassScaling = false }</code> volta aos números fixos (chefe "pesado" de propósito).</p>

<h2>Agarrão: AttachTo × FollowTarget</h2>
<p><code>entity.AttachTo(peçaDoLíder, offset)</code> põe o corpo no assembly do líder (WeldConstraint): anda junto <b>sem atraso</b>, também quando o líder é um player. Enquanto preso, as Forces e a caminhada dele ficam suspensas. <code>FollowTarget</code> persegue com elasticidade e é calculado no servidor (com a posição atrasada do player). Use AttachTo para carregar e FollowTarget para perseguir. Receita: ${L("receitas.agarrao")}.</p>

<h2>Zonas de vento</h2>
<p>Use ${L("api.AreaBehaviors.BindDirectionalForce", "AreaBehaviors.BindDirectionalForce")}: a força vale da entrada até a saída da zona (não sobra empurrão depois da borda). Veja ${L("conceitos.zonas")}.</p>
`,
});

// ------------------------------------------------------------------ rede
DOCS.page({
  id: "conceitos.rede",
  parent: "avancado",
  order: 40,
  title: "Rede: modelo B e NetworkView",
  kw: "rede network latência ping lag atraso anticheat anti-cheat validação movimento teleporte speed hack ownership dono de rede networkview cliente servidor",
  lead: "O corpo do player é simulado pelo cliente (resposta imediata) e o servidor valida a distância andada. O servidor vê esse corpo atrasado; o NetworkView corrige as decisões que dependem de posição.",
  html: `
<h2>Validação de movimento</h2>
<p>A cada Heartbeat, o ${L("api.GlobalAntiCheat", "GlobalAntiCheat")} compara o deslocamento do player com o que dava para andar: WalkSpeed do servidor, Forces ativas e chão móvel. Passou disso, o corpo volta à última posição aceita.</p>
<ul>
  <li><b>Crédito</b> (token bucket): enche na velocidade permitida até <code>Movement_Burst_Seconds</code>; absorve rajadas de replicação.</li>
  <li><b>Janela de latência</b>: uma velocidade maior (dash que acabou) segue valendo por <code>Movement_Latency_Window</code> + ping, porque o cliente ainda está aplicando a Force.</li>
  <li><b>Janela de confiança</b>: depois de o servidor mover o corpo (teleporte, volta da possessão), pacote antigo do cliente não vira correção.</li>
  <li>Fora de escopo: noclip, voo contínuo, empurrão físico fora das Forces, veículos.</li>
</ul>
<p>Tudo em ${L("api.Settings", "Physics/Settings")}. Com <code>Workspace.AuthorityMode = Server</code> a validação fica redundante: desligue <code>Movement_Validation_Enabled</code>.</p>

<h2>Atraso de visão</h2>
<p>O servidor vê o corpo do player cerca de 0,35 s atrás do que o cliente sente (sem contar o ping). Uma decisão do servidor tomada com essa posição chega tarde: uma zona de vento veria o player sair 0,35 s depois de ele sair de verdade. ${L("api.NetworkView", "NetworkView")} prevê onde o corpo está (<code>PredictedShift</code>), e o AreaEffect já usa isso.</p>
${N("<p>Para medir o que o player <b>vê</b>, teste no cliente (um LocalScript medindo por RenderStepped). Teste só de servidor não enxerga esse atraso.</p>")}

<h2>Corpos do servidor</h2>
<p>NPCs são simulados pelo servidor (sem atraso). Na possessão, o dono de rede do corpo passa para o player que o dirige, e volta na saída.</p>
`,
});

// ------------------------------------------------------------------ alvos
DOCS.page({
  id: "conceitos.alvos",
  parent: "basico",
  order: 130,
  title: "Alvos e times",
  kw: "alvo target time team equipe aliado inimigo neutro facção ally enemy neutral fogo amigo friendly fire affects relation canaffect affiliation",
  lead: "De que lado cada entidade está é dado (Affiliation); quem uma skill afeta é regra declarada (data.affects sobre Enum.AffectsDefaults). Quem resolve alvo (hitbox, zona) pergunta ao StateTable.",
  html: `
<h2>Relação</h2>
${T(["Relation", "Quando"], [
  ["<code>Self</code>", "A própria entidade."],
  ["<code>Ally</code>", "Mesmo time."],
  ["<code>Enemy</code>", "Times diferentes."],
  ["<code>Neutral</code>", "Um dos dois sem Affiliation (dummy, ambiente)."],
])}
${C(`
DataManager.Create(model, { ..., Component.Affiliation }, { Affiliation = { Team = "Azul" } })
StateTable.Relation(a, b)        -- "Ally" | "Enemy" | "Neutral" | "Self"
`)}

<h2>Quem a skill afeta</h2>
<p>Padrão (${L("enum.alvos", "Enum.AffectsDefaults")}): inimigo e neutro sim; aliado e si mesmo não. A skill sobrescreve: <code>data.affects = { Ally = true }</code> (cura em área). A hitbox da arma só entrega à skill os alvos que ela afeta; zona de skill usa <code>area:SetFilter(StateTable.AffectsFilter(runner))</code>.</p>
${W("<p><code>self:Damage</code> e <code>ApplyStatus</code> chamados direto <b>não</b> filtram por time: quem chama decide. Para conferir, use <code>StateTable.CanAffect(self, alvo)</code>.</p>")}
`,
});

// ------------------------------------------------------------------ controle
DOCS.page({
  id: "conceitos.controle",
  parent: "avancado",
  order: 50,
  title: "Possessão e controle",
  kw: "possessão possess controlar controle dirigir corpo release soltar lock unlock cutscene qte pilha stack swap ia brain mind control link espelhar",
  lead: "Quem manda numa entidade é um controlador: um player ou uma IA. O ControlComponent corta e redireciona a fonte do input; o que a entidade pode fazer (canMove, canCast) continua sendo dos status.",
  html: `
<h2>Possuir e soltar</h2>
${C(`
local Policy = require(game.ServerScriptService.EntityData.Components.ControlComponent).Policy

alvo.Possess({ Player = player })                              -- pilha; pausa a IA do alvo
alvo.Possess({ Player = player }, { Policy = Policy.Swap })    -- solta os anteriores
alvo.Possess({ Player = player }, { PauseAI = false })         -- a IA do alvo segue ligada
alvo.Possess({ AI = true, Brain = outraMente })                -- outra mente dirige o alvo
alvo.Release()                                                 -- devolve ao controlador nativo
`)}
<ul>
  <li><b>Stack</b> (padrão): possuir B estando em A empilha; soltar B volta para A; soltar A volta ao corpo nativo.</li>
  <li><b>Swap</b>: possuir solta os anteriores; soltar volta ao nativo.</li>
  <li>Possuído destruído ou morto devolve o player ao corpo anterior sozinho (<code>ReleaseOnDeath</code>).</li>
  <li>A IA original (Brain e estado) é guardada e restaurada exatamente.</li>
</ul>
<p>Padrões por entidade no config: <code>Control = { Policy = ..., PauseAI = ..., ReleaseOnDeath = ... }</code>.</p>

<h2>Lock (cutscene, QTE)</h2>
<p><code>entity.Lock()</code> corta o controlador atual sem reatribuir; <code>Unlock()</code> devolve exatamente o que foi cortado. Um Possess durante o Lock não fura o corte (só atualiza o que volta no Unlock).</p>

<h2>Link de input</h2>
<p><code>a.LinkTo(b, { MirrorMovement = true, MirrorLook = true })</code>: o input de movimento/mira que A recebe também vai para B (torre que gira junto, clone que imita).</p>
`,
});

// ------------------------------------------------------------------ hitbox
DOCS.page({
  id: "conceitos.hitbox",
  parent: "basico",
  order: 140,
  title: "Hitbox da arma e projéteis",
  kw: "hitbox colisão acerto raycast blockcast spherecast shapecast arma weapon projétil projectile homing teleguiado dmgpoint onhit",
  lead: "Cada skill liga, desliga e recebe os acertos da SUA hitbox da arma. Para projéteis e formas que se movem sozinhas, há o HitboxSpawner com Behaviors e Presets.",
  html: `
<h2>Hitbox da arma</h2>
<p>A arma (model em <code>ReplicatedStorage/Assets/Weapons/&lt;Kit&gt;/&lt;Arma&gt;</code>) tem uma pasta <code>Hitbox</code> com Parts. Cada Part vira uma hitbox (ShapecastHitbox) com os pontos de dano nos Attachments chamados (ou com a tag) <code>DmgPoint</code>. Atributos do Attachment escolhem a forma: <code>CastType</code> (Raycast | Blockcast | Spherecast), <code>CastSize</code>, <code>CastRadius</code>, <code>CastCFrame</code>. Atributo <code>Flags</code> na Part (lista separada por vírgula) chega em <code>hit.flags</code>.</p>
${C(`
onStart = function(self)
    self:StartHitbox(self.data.duration)  -- a hitbox desta skill
end,
onHit = function(self, hit)               -- { target, position, normal, instance, hitboxName, flags, ... }
    self:Damage(hit.target, 10, { Hit = hit })
end,
`)}
<ul>
  <li>Anti multi-hit por sessão: o mesmo alvo é acertado uma vez por StartHitbox. Para multi-hit, <code>StopHitbox()</code> e <code>StartHitbox()</code> de novo (o M1 faz isso no 2º golpe).</li>
  <li>Só os alvos que a skill afeta (time) chegam no onHit.</li>
  <li>A hitbox da skill sai sozinha no fim do runner.</li>
</ul>

<h2>Hitbox solta (projéteis, formas)</h2>
${C(`
local Presets = require(game.ServerStorage.Modules.Combat.Hitbox.HitboxPresets)
local hitbox, carrier = Presets.HomingBolt(self.Entity, origem, function()
    return alvo.GetRoot()
end, 60, 3, 2)
hitbox:OnHit(function(result)
    local atingido = DataManager.GetEntityFromInstance(result.Instance)
    if atingido then self:Damage(atingido, 15) end
end)
`)}
<p>${L("api.HitboxSpawner", "HitboxSpawner")} cria o hitbox e o carrier; ${L("api.HitboxBehaviors", "HitboxBehaviors")} move/cresce (LinearMove, Homing, ExpandUniform, ExpandDirectional); ${L("api.HitboxPresets", "HitboxPresets")} junta os dois em formas nomeadas. A skill referencia Presets e passa overrides: não monta spawner + behavior na mão.</p>
${N("<p>Hitbox solta não filtra por time nem faz anti multi-hit: faça na skill (<code>StateTable.CanAffect</code> e uma tabela de já acertados).</p>")}
`,
});

// ------------------------------------------------------------------ zonas
DOCS.page({
  id: "conceitos.zonas",
  parent: "basico",
  order: 150,
  title: "Zonas (AreaEffect)",
  kw: "zona area aoe área de efeito campo aura vento ventilador slow poll onenter onstay onexit filtro",
  lead: "Uma zona consulta uma forma (caixa ou esfera) numa taxa fixa e chama OnEnter, OnStay e OnExit por entidade. A forma pode seguir algo que se move.",
  html: `
${C(`
local AreaEffect = require(game.ServerStorage.Modules.Combat.AreaEffect)
local AreaBehaviors = require(game.ServerStorage.Modules.Combat.AreaBehaviors)

local zona = AreaEffect.new(function() return ventilador.CFrame end, "Box", Vector3.new(10, 8, 30), 15)
zona:SetFilter(StateTable.AffectsFilter(self))        -- respeita o data.affects da skill
    :OnEnter(function(e) e.AddModifier("Speed", zona.ID, "MultPercent", 0.5) end)
    :OnExit(function(e) e.RemoveModifier("Speed", zona.ID) end)
AreaBehaviors.BindDirectionalForce(zona, function() return ventilador.CFrame.LookVector end, 30, "Vento")
zona:Start()
self:Own(function() zona:Stop() end)                  -- quem está dentro sai pelo OnExit
`)}
<ul>
  <li><code>cframeProvider</code> é lido a cada poll: a zona acompanha algo que se move ou gira.</li>
  <li>Não usa <code>.Touched</code> (não confiável com objetos rápidos).</li>
  <li>Corpo de player é testado na posição prevista (NetworkView): a saída da zona vale quando ele sai de verdade.</li>
  <li><code>Stop()</code> faz quem estava dentro sair pelo OnExit: o efeito do OnEnter é desfeito.</li>
  <li>Modificadores de stat com o mesmo ID têm contagem de referência: duas zonas iguais não se anulam.</li>
</ul>
`,
});

// ------------------------------------------------------------------ cliente
DOCS.page({
  id: "conceitos.cliente",
  parent: "basico",
  order: 160,
  title: "Cliente: VFX, som, câmera e HUD",
  kw: "cliente client vfx efeito visual partícula som sound áudio câmera camera hud interface ui barra de vida cooldown",
  lead: "O servidor decide; o cliente mostra. VFX por nome registrado, som 3D, câmera de ombro e HUD por slot.",
  html: `
<h2>VFX</h2>
<p>Servidor: <code>VFXManager.PlayAll(nome, dados)</code> ou <code>PlayNear(posição, raio, nome, dados)</code>. Cliente: o <code>VFXPlayer</code> chama <code>VFXRegistry[nome](dados)</code>. Para um efeito novo, acrescente uma função no ${L("api.VFX", "VFXRegistry")}.</p>
<h2>Som</h2>
<p>${L("api.SoundManager", "SoundManager")}: <code>PlayOneShot3D(posição, id, config?)</code> e <code>PlayAttached(instância, id, config?, key?)</code>.</p>
<h2>Câmera</h2>
<p>${L("api.CameraOverride", "CameraOverride")}: ombro com soft lock na entidade mais próxima num cone (tecla C). Segue o corpo possuído. Ajuste em <code>Config</code> no topo do módulo.</p>
<h2>HUD</h2>
<p><code>HealthUIController</code> recebe <code>UpdateHealthBar(hp, max)</code> do corpo que o player dirige. <code>CooldownUIController</code> recebe <code>SkillFired(intent, cooldown, cargas)</code> e anima o botão com o atributo <code>Intent</code> igual: a HUD não conhece nome de skill.</p>
`,
});

// ------------------------------------------------------------------ logger
DOCS.page({
  id: "conceitos.logger",
  parent: "basico",
  order: 170,
  title: "Logger e depuração",
  kw: "log logger debug depurar depuração print warn saída output nível canal channel logconfig",
  lead: "Toda saída do framework passa pelo Logger: um canal por módulo, com nível configurável. Warns estruturais nunca se misturam com debug.",
  html: `
${C(`
local Log = require(game.ReplicatedStorage.Logger).Channel("MinhaSkill")
Log.Debug("entrou", alvo.ID)         -- some no nível padrão
Log.Info("fase 2")
Log.Warn("config faltando")
Log.WarnOnce("chave", "aviso uma vez") -- as repetições só em Debug
`)}
<p>Formato: <code>[Canal] mensagem</code>. Nível global e por canal em ${L("api.Logger", "Config/LogConfig")}; em runtime, <code>Logger.SetLevel("Debug", "Canal")</code>.</p>
<p>Debug temporário (de teste) usa o prefixo <code>[FW-DEBUG]</code>, para ser achado e removido em bloco.</p>
`,
});

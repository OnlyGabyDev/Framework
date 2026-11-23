/* Guias extras (básico e avançado) */

// ================================================================== BÁSICO
DOCS.page({
  id: "conceitos.centralizacao",
  parent: "basico",
  order: 15,
  title: "A regra de centralização",
  kw: "centralização regra dono único magic string string mágica valor solto enum config onde declarar dry duplicação shape formato",
  lead: "Todo valor, nome ou formato usado por mais de um lugar tem UM dono declarado. O resto lê de lá. É o que impede o jogo de virar uma coleção de números soltos e strings que só funcionam por coincidência.",
  html: `
<h2>A regra</h2>
<ul>
  <li><b>Nada de valor solto</b>: número de design (dano base de um sistema, duração padrão, teto, janela) vai num enum, config ou no <code>data</code> da skill/status, nunca no meio de uma função.</li>
  <li><b>Nada de string mágica</b>: nome de tag, trait, stat, breakpoint, camada, intent ou categoria vem de um enum. <code>Enum.Tags.canMove</code>, não <code>"canMove"</code>.</li>
  <li><b>Formato com dono único</b>: estrutura lida por mais de um módulo (Context, Subscription, data de skill, CharacterDatabase) tem o formato declarado num lugar. Todo mundo lê seguindo essa declaração.</li>
  <li><b>Uma ação, um lugar</b>: nada implementado igual (ou parecido) em dois lugares. Se duas skills precisam da mesma coisa, ela vira helper, status, preset ou enum.</li>
  <li><b>Efeito tem origem</b>: dano e status sempre com fonte (<code>self:Damage</code>, <code>Source = runner</code>), para crédito, cadeia e filtros funcionarem.</li>
</ul>

<h2>Onde mora cada coisa</h2>
${T(["O quê", "Dono"], [
  ["Tags, traits, breakpoints, roles, categorias, estados, motivos de fim", "<code>StateTable/Enum</code>"],
  ["Stats, padrões e limites de stat, fórmula de dano", "<code>StateTable/Enum</code> (Stats, StatDefaults, StatLimits, DamageMitigation)"],
  ["Regras do motor (morte, cura, alvos, cadeia, cooldown, efeitos on-hit)", "<code>StateTable/Enum</code> (*Defaults, ChainLimits)"],
  ["Formato de Context, Subscription, opções de dano e cura", "<code>Combat/Types</code>"],
  ["Formato de uma Force", "Cabeçalho do <code>MovementComponent</code>"],
  ["Formato do cooldownPolicy", "Cabeçalho do <code>CooldownPolicy</code>"],
  ["Números de física, anti-cheat e rede", "<code>Physics/Settings</code>"],
  ["Intents e gestos", "<code>ReplicatedStorage/Input/Intents</code>"],
  ["Bindings de input", "<code>ReplicatedStorage/Config/InputConfig</code>"],
  ["Nível de log", "<code>ReplicatedStorage/Config/LogConfig</code>"],
  ["Personagens (stats, loadout, arma)", "<code>DataBase/CharacterDatabase</code>"],
  ["Skills e chaves de skill", "<code>DataBase/SkillDatabase</code> (<code>Keys</code>)"],
  ["Status e estados", "<code>StateTable/Status</code>, <code>StateTable/States</code>"],
  ["Animações por kit", "<code>Animation/AnimationLib</code>"],
  ["Formas de hitbox prontas", "<code>Hitbox/HitboxPresets</code>"],
  ["Efeitos visuais", "<code>VFXRegistry</code> (cliente)"],
])}

<h2>Na prática</h2>
${C(`
-- errado: string mágica, número solto, efeito sem origem
alvo.ApplyStatus(require(path.Stun), 1.5)
if tags["canCast"] == false then ... end

-- certo
local Enum = StateTable.Enum
self:ApplyStatus(StateTable.States.Stun, { Target = alvo, Duration = self.data.stunTime })
if entity.GetActiveTags()[Enum.Tags.canCast] == false then ... end
`)}

<h2>Por que importa</h2>
<p>O framework não tem CI nem equipe revisando: a centralização é a rede de segurança. Quando um valor tem dono, trocar o design é mexer numa linha; quando está espalhado, cada cópia diverge um pouco e o bug aparece longe da causa. Antes de criar algo, procure o dono no manual (a busca ajuda). Se a coisa nova não tem dono ainda, crie no lugar da tabela acima e declare ali, não no arquivo que vai usar.</p>
${N("<p>Duplicação de nomes também é bug: duas pastas ou módulos com o mesmo nome (até só na capitalização, <code>martelo</code> × <code>Martelo</code>) quebram as buscas por nome. O Studio não avisa; confira ao criar.</p>")}
`,
});

DOCS.page({
  id: "conceitos.actionstates",
  parent: "basico",
  order: 25,
  title: "ActionStates: travas de ação",
  kw: "actionstate trava ação selfcast cast lockedcast globalcast cancelar skill anterior trocar de skill no meio interromper própria",
  lead: "O ActionState diz se a ação que a entidade está fazendo pode ser trocada por outra. É o que decide se apertar outra skill no meio do dash cancela o dash ou é recusado.",
  html: `
${T(["ActionState", "Efeito numa skill nova"], [
  ["<code>ActionStates.Self.selfCast</code>, <code>Self.globalCast</code>", "A skill atual é <b>auto-cancelável</b>: a nova cancela a atual e entra."],
  ["<code>ActionStates.Out.cast</code>, <code>Out.globalCast</code>", "A atual <b>não</b> é auto-cancelável: a nova é recusada."],
  ["<code>ActionStates.LockedCast</code>", "Travado: a nova é recusada."],
  ["nenhum", "A nova entra (sem cancelar nada)."],
])}
${C(`
onStart = function(self)
    local AS = self.statusTable.ActionStates
    self.Entity.SetActionState(AS.Self.selfCast, self.Runner) -- dash: pode ser trocado
end,
onEnd = function(self)
    self.Entity.RemoveActionState(self.Runner)  -- só remove se ainda for deste runner
end,
`)}
<ul>
  <li>Há um ActionState por entidade (o último Set vale).</li>
  <li><code>RemoveActionState(runner)</code> só remove se o estado ainda for daquele runner: a limpeza atrasada de uma skill antiga não apaga o da nova.</li>
  <li>O motor remove o ActionState do runner no fim dele, de qualquer jeito.</li>
  <li>O cancelamento passa pelo <code>onCancel</code>: a skill atual pode recusar (devolvendo false), e aí a nova é recusada.</li>
</ul>
<p>ActionState não é status: não tem tags nem duração. Para impedir cast por um tempo, use um estado (Silence) ou a tag <code>canCast</code>.</p>
`,
});

DOCS.page({
  id: "conceitos.criar",
  parent: "basico",
  order: 45,
  title: "Criando tags, traits, stats, estados e enums",
  kw: "criar nova tag trait stat estado state status enum adicionar novo valor customizado próprio custom intent breakpoint categoria",
  lead: "Quase toda extensão do jogo é acrescentar um valor num enum e um módulo de dado. Esta página mostra o passo a passo de cada uma, e o que o motor faz (ou não faz) sozinho com o valor novo.",
  html: `
<h2>Uma tag nova</h2>
<p>Tag é uma permissão booleana ligada por status. Exemplo: <code>canJump</code> (um debuff que impede pular).</p>
<ol class="flow">
  <li>Declare em <code>StateTable/Enum</code>: <code>Tags.canJump = "canJump"</code> e o padrão em <code>tagsBase.canJump = true</code>.</li>
  <li>Use num status: <code>tags = { [Enum.Tags.canJump] = false }</code>.</li>
  <li>Leia onde a regra se aplica: <code>entity.GetActiveTags()[Enum.Tags.canJump] == false</code>.</li>
</ol>
${C(`
-- StateTable/States/Grounded.luau
local Enum = require(script.Parent.Parent.Enum)
return {
    data = {
        name = "Grounded",
        category = Enum.Categories.Debuff,
        tags = { [Enum.Tags.canJump] = false },
    },
    callbacks = {},
}
`)}
${W("<p><strong>O motor só aplica as tags que conhece</strong> (canMove, canCast, canRotate, canDisplace, iFrame, block, interrupt). Uma tag nova é dado: <b>alguém precisa ler</b>. Leia no lugar que já decide aquilo (na skill de pulo, no Brain da IA, num listener) em vez de espalhar <code>if</code> pelo código. Se a tag precisa valer para todo o motor (ex.: bloquear um tipo de Force), isso é uma mudança pontual de motor: veja " + L("fluxo.finalizado") + ".</p>")}
<p>Uma tag de <b>imunidade</b> nova não precisa de código: um status da pasta <code>StateTable/Status</code> com a tag verdadeira e <code>bypassBy = { traits }</code> entra nas regras de imunidade do ValidateHit (o mapa é montado uma vez, a partir dos módulos de <code>Status</code>; <code>States</code> não entram). Enquanto o status estiver ativo, hit sem uma das traits de <code>bypassBy</code> é barrado.</p>

<h2>Uma trait nova</h2>
<ol class="flow">
  <li>Declare em <code>Enum.Traits</code>: <code>Fogo = "Fogo"</code>.</li>
  <li>Marque skills/status (<code>data.traits</code>) ou um hit (<code>opts.Traits</code>).</li>
  <li>Filtre com <code>Query</code> em listeners, <code>ShieldsFrom</code> em escudos, <code>bypassBy</code> em imunidades, <code>ignoredBy</code> numa proteção de dano.</li>
</ol>
${C(`
-- resistência a fogo sem código novo no motor: uma proteção a mais na fórmula
Enum.Stats.FireResist = "FireResist"
-- em Enum.DamageMitigation (a ordem importa):
table.freeze({ stat = Enum.Stats.FireResist, mode = Enum.MitigationModes.Multiplicative,
    ignoredBy = table.freeze({ Enum.Traits.TrueDamage }) })
`)}
${N("<p>A proteção acima vale para todo hit. Para valer só contra fogo, use um listener de <code>IN.PreDamage</code> com <code>Query = { All = { Traits.Fogo } }</code> lendo <code>GetStat(\"FireResist\")</code>.</p>")}

<h2>Um stat novo</h2>
<ol class="flow">
  <li>Declare em <code>Enum.Stats</code> e o padrão em <code>Enum.StatDefaults</code>.</li>
  <li>Se tem limite diferente de "não negativo", em <code>Enum.StatLimits</code>.</li>
  <li>Dê o valor base por personagem (<code>Stats</code> da forma) ou por entidade (<code>Attributes = { BaseStats = {...} }</code>).</li>
  <li>Leia com <code>entity.GetStat(Enum.Stats.X, Enum.StatDefaults.X)</code>; modifique com <code>AddModifier</code>.</li>
</ol>
${W("<p>O <code>AttributesComponent</code> carrega do personagem só os stats que conhece (Speed, JumpForce, MaxHP, Defense, DamageMult, GravityScale, Weapon). Um stat novo vem de <code>BaseStats</code> no config, de <code>SetStat</code>, ou do padrão passado no <code>GetStat</code>.</p>")}

<h2>Um estado ou status novo</h2>
<p>Crie um ModuleScript em <code>StateTable/States</code> (estado) ou <code>StateTable/Status/Buffs|Debuffs</code> (status). O StateTable carrega a pasta sozinho: o módulo fica em <code>StateTable.States.Nome</code> ou <code>StateTable.Status.Nome</code>. Formato em ${L("api.skill.statusdata")}.</p>

<h2>Uma intent (botão) nova</h2>
<ol class="flow">
  <li><code>Intents.Id.Ability4 = "Ability4"</code> e, se for slot de skill, em <code>Intents.SkillOrder</code>.</li>
  <li>Binding em <code>Config/InputConfig</code>: <code>[Id.Ability4] = { Enum.KeyCode.Five, Enum.KeyCode.ButtonL2 }</code>.</li>
  <li>Equipe uma skill no slot (<code>Loadout.Slots[Id.Ability4]</code>). Para botão de tela, um GuiButton com a tag <code>InputButton</code> e o atributo <code>Intent = "Ability4"</code>.</li>
</ol>
<p>O servidor valida a intent pela lista <code>Intents.Id</code>: nada mais muda.</p>

<h2>Um breakpoint novo</h2>
<p>Qualquer string serve. Declare em <code>Enum.Breakpoints</code> (centralização) e emita onde o momento acontece: <code>entity:Emit(Enum.Roles.OUT, Enum.Breakpoints.OnCardPlayed, ctx)</code>. Quem escuta usa <code>Listen</code> normalmente.</p>

<h2>Uma categoria, camada ou motivo</h2>
${T(["Valor", "Onde declarar", "Para quê"], [
  ["Categoria de status", "<code>Enum.Categories</code>", "Agrupar para <code>exclusive</code> e <code>ShieldsFrom</code>."],
  ["Camada de loadout", "<code>Enum.LoadoutLayers</code> (ou só usar o nome)", "<code>ApplyLoadout(dados, camada)</code>."],
  ["Relação/padrão de alvo", "<code>Enum.AffectsDefaults</code>", "Quem as skills afetam por padrão no jogo."],
  ["Motivo de fim próprio", "<code>Enum.EndReasons</code>", "<code>self:endSkill(false, Enum.EndReasons.X)</code> e um <code>refund</code> por motivo."],
])}
`,
});

DOCS.page({
  id: "conceitos.stats",
  parent: "basico",
  order: 85,
  title: "Stats e modificadores",
  kw: "stat stats atributo atributos modificador modifier buff debuff speed velocidade defense defesa armor damagemult multiplicador flat percent override fórmula base",
  lead: "Stats moram no AttributesComponent: um valor base por stat e modificadores por origem. Speed, JumpForce, GravityScale, MaxHP, Defense, Armor, DamageMult e CooldownReduction já são lidos pelo motor.",
  html: `
<h2>Fórmula</h2>
${C(`
valor = ((Base + somaFlat) * (1 + somaAddPercent)) * produtoMultPercent
-- um Override substitui a Base (com mais de um, vale o MENOR)
-- e o resultado fica dentro de Enum.StatLimits (padrão: não negativo; Defense pode ser negativa)
`)}
${C(`
local MT = StateTable.Enum.ModifierType
entity.AddModifier("Speed", "SlowGelo", MT.MultPercent, 0.5)   -- metade da velocidade
entity.AddModifier("Defense", "Armadura", MT.Flat, 25)
entity.AddModifier("DamageMult", "Furia", MT.AddPercent, 0.3)  -- +30%
entity.RemoveModifier("Speed", "SlowGelo")
`)}
<ul>
  <li><b>Contagem de referência</b>: o mesmo ID adicionado N vezes precisa de N RemoveModifier. Duas zonas iguais não se anulam.</li>
  <li>Use um ID por origem (o ID do status, da zona, do item) e remova no fim (no <code>onEnd</code> do status ou com <code>self:Own</code>).</li>
  <li>Leitura cacheada: o MovementController lê Speed/JumpForce/GravityScale todo frame sem custo.</li>
</ul>

<h2>Quem lê o quê</h2>
${T(["Stat", "Lido por"], [
  ["Speed, JumpForce, GravityScale", "MovementController (caminhada, pulo, gravidade)."],
  ["MaxHP", "HealthComponent (com Attributes, o MaxHP vem do stat)."],
  ["DamageMult", "ApplyDamage do atacante."],
  ["Defense, Armor", "Fórmula de dano do alvo (Enum.DamageMitigation)."],
  ["CooldownReduction", "CooldownPolicy, quando uma contagem começa."],
  ["Weapon", "WeaponComponent (arma inicial)."],
])}

<h2>Buff temporário como status</h2>
${C(`
return {
    data = { name = "Furia", category = Enum.Categories.Buff, duration = 6 },
    callbacks = {
        onStart = function(self)
            -- self.ID = o ID desta aplicação (o mesmo que ApplyStatus devolveu)
            self.Entity.AddModifier("DamageMult", self.ID, "AddPercent", 0.3)
        end,
        onEnd = function(self)
            self.Entity.RemoveModifier("DamageMult", self.ID)
        end,
    },
}
`)}
`,
});

DOCS.page({
  id: "conceitos.personagens",
  parent: "basico",
  order: 105,
  title: "Personagens, armas e animações",
  kw: "personagem char character kit forma modo transformação arma weapon criar arma model handle motor6d attach hitorigin weapondata animação animation animationlib charlib marker marcador",
  lead: "Um personagem (kit) é uma pasta em quatro lugares com o mesmo nome: o banco de personagens, o banco de skills, as armas e a biblioteca de animações.",
  html: `
<h2>O kit em quatro lugares</h2>
${T(["Lugar", "Conteúdo"], [
  ["<code>ServerStorage/DataBase/CharacterDatabase/&lt;Kit&gt;/&lt;Modo&gt;</code>", "Uma forma: <code>Stats</code>, <code>Loadout</code>, <code>Weapon</code>, <code>attachTo</code>."],
  ["<code>ServerStorage/DataBase/SkillDatabase/&lt;Kit&gt;/</code>", "As skills do kit (o kit vira o dono delas)."],
  ["<code>ReplicatedStorage/Assets/Weapons/&lt;Kit&gt;/&lt;Arma&gt;/</code>", "O model da arma e o <code>WeaponData</code>."],
  ["<code>ServerStorage/Modules/Animation/AnimationLib</code>", "<code>character.&lt;Kit&gt; = { M1 = { ... }, S1 = { ... } }</code>: IDs por conjunto."],
])}

<h2>Forma (CharacterDatabase)</h2>
${C(`
-- CharacterDatabase/Schema/Base.luau
local Intents = require(game.ReplicatedStorage.Input.Intents).Id
local Keys = require(game.ServerStorage.DataBase.SkillDatabase).Keys
return {
    Stats = { MaxHP = 100, Speed = 20, JumpForce = 10 },
    Loadout = {
        Slots = {
            [Intents.Primary] = Keys.Schema.M1,
            [Intents.Dash] = Keys.Schema.Dash,
            [Intents.Ultimate] = Keys.Schema.Ultimate,
        },
    },
    Weapon = "Martelo",       -- nome da pasta em Assets/Weapons/Schema
    attachTo = "Right Arm",   -- membro padrão da arma deste personagem
}
`)}
<p>O Combat carrega <code>ChosenChar</code> e <code>Mode</code> do config (padrão em <code>Enum.CombatDefaults</code>): aplica os stats e o loadout na camada Base. Mais formas = mais módulos na pasta do kit (<code>Base</code>, <code>Desperto</code>…).</p>

<h2>Arma</h2>
<p>Estrutura do model (pasta <code>Assets/Weapons/&lt;Kit&gt;/&lt;Arma&gt;/&lt;Arma&gt;</code>):</p>
${T(["Peça", "Obrigatória", "Para quê"], [
  ["<code>Handle</code>", "sim", "Onde o personagem segura. As outras peças são soldadas nela (WeldConstraint)."],
  ["<code>Handle_&lt;ponto&gt;</code>", "com mais de um ponto", "Peça de cada ponto extra (dual wield): <code>Handle_secondary</code>."],
  ["CFrameValue <code>Value</code> / <code>Value_&lt;ponto&gt;</code>", "recomendado", "O C1 do Motor6D (posicione com um Motor6D no Studio, copie o C1 para o Value e apague o motor)."],
  ["StringValue <code>AttachTo</code>", "não", "Membro que segura (vence o <code>attachTo</code> do personagem; padrão Right Arm)."],
  ["<code>hitOrigin</code>", "sim para hitbox criada em runtime", "Origem de hitboxes (<code>self.hitPoint</code>)."],
  ["Pasta <code>Hitbox</code> com Parts", "para hitbox de arma", "Cada Part vira uma hitbox; os pontos são Attachments <code>DmgPoint</code> (atributos CastType, CastSize, CastRadius, CastCFrame). Atributo <code>Flags</code> na Part."],
])}
<p>Prioridade do membro: arma (<code>AttachTo</code>) &gt; personagem (<code>attachTo</code>) &gt; <code>Right Arm</code>.</p>

<h3>Modos da arma (WeaponData)</h3>
${C(`
return {
    BaseName = "Martelo",
    DefaultMode = "Dual",
    Modes = {
        Dual = {
            AttachPoints = { primary = "Right Arm", secondary = "Left Arm" },
            AnimSet = "DualBlades",          -- conjunto no charLib
            Loadout = { Slots = { [Intents.Ability1] = Keys.Schema.Skill2 } }, -- camada WeaponMode
            TransformTime = 0.5,
            TransformAnim = "MergeBlades",
        },
        Merged = { AttachPoints = { primary = "Right Arm" }, TransformTime = 0.5 },
    },
}
`)}
<p>A skill <code>WeaponTransform</code> de exemplo troca o modo no fim da transformação e aplica o <code>Loadout</code> do modo na camada <code>WeaponMode</code>.</p>
<p>Entidade sem personagem pode receber a arma por config: <code>Weapon = { WeaponName = "X" }</code>, <code>{ WeaponModel = model }</code>, e <code>IsCosmetic = true</code> para não criar hitbox.</p>

<h2>Animações</h2>
${C(`
-- AnimationLib: lib.character.Schema = { M1 = { M1Start = "1092...", M1S2 = "1019..." } }
onStart = function(self)
    local id = self.charLib.M1.M1Start              -- do kit dono da skill
    local track = self.Entity.PlayAnimation(id)
    self.Entity.OnMarker(tostring(id), "Hit", function() self:StartHitbox(0.2) end)
    self.Entity.OnMarker(tostring(id), "End", function() self:Stop(false) end)
end,
`)}
<ul>
  <li><code>self.charLib</code> lê o conjunto do kit <b>dono</b> da skill e, na falta, do kit de quem casta: uma skill roubada segue com as animações dela.</li>
  <li>A chave da track é o próprio ID (ou a <code>key</code> passada no PlayAnimation): use-a no OnMarker/StopAnimation.</li>
  <li>Skill que depende de animação ou arma declara <code>data.requires = { Component.Animation, Component.Weapon }</code>: sem eles, o motor recusa o cast em vez de errar no onStart.</li>
</ul>
<p>Receita completa: ${L("receitas.personagem")}.</p>
`,
});

DOCS.page({
  id: "conceitos.ia",
  parent: "basico",
  order: 125,
  title: "IA e NPCs",
  kw: "ia ai npc inimigo bot brain cérebro comportamento patrulha perseguir mob monstro inteligência artificial",
  lead: "A IA não tem caminho próprio no combate: um Brain chamado a cada Heartbeat produz o mesmo input que um player produziria. O que funciona para o player funciona para o NPC.",
  html: `
${C(`
local SkillHandler = require(game.ServerScriptService.Modules.SkillHandler)
local Intents = require(game.ReplicatedStorage.Input.Intents)

local function brain(entity, dt)
    local alvo = acharAlvo(entity)                -- sua lógica
    if not alvo then
        SkillHandler.HandleMovementInput(entity.ID, Vector3.zero)
        return
    end
    local delta = alvo.GetPosition() - entity.GetPosition()
    SkillHandler.HandleMovementInput(entity.ID, delta.Unit)
    SkillHandler.HandleLookInput(entity.ID, delta.Unit)
    if delta.Magnitude < 6 then
        SkillHandler.HandleIntent(entity.ID,
            Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate, Intents.Gesture.Press))
    end
end

DataManager.Create(model, {
    Component.Character, Component.Health, Component.Status, Component.Movement,
    Component.Attributes, Component.Combat, Component.Animation, Component.Weapon, Component.AI,
}, { AI = { Brain = brain } })
`)}
<ul>
  <li>Todos os Brains rodam num Heartbeat único (AIScheduler): nada de uma conexão por NPC.</li>
  <li><code>entity.SetEnabled(false)</code> pausa; <code>SetBrain(fn)</code> troca a mente.</li>
  <li>Cooldown, canCast, Stun e ActionState valem igual para NPC (o mesmo HandleIntent).</li>
  <li>Hold/Release: mande <code>Intents.NewEvent(intent, Intents.Kind.Release, nil, segundos)</code> depois.</li>
  <li>Um player possuindo o NPC pausa o Brain e devolve no Release.</li>
</ul>
<p>Para invocar NPCs descartáveis, use ${L("api.MinionFactory", "MinionFactory")}.</p>
`,
});

DOCS.page({
  id: "conceitos.hud",
  parent: "basico",
  order: 165,
  title: "Integração com UI e HUD",
  kw: "ui hud interface gui tela botão barra de vida cooldown ícone status buff mostrar cliente remote remoteevent atributo billboard mobile celular screen",
  lead: "A HUD só mostra; quem decide é o servidor. O framework já entrega vida e cooldown por slot. Para qualquer outro estado (status, cargas, recurso), escute no servidor e mande ao cliente.",
  html: `
<h2>O que já vem pronto</h2>
${T(["Peça", "Como funciona"], [
  ["Barra de vida", "<code>RemoteEvents.UpdateHealthBar(hp, maxHp)</code> vai ao player que dirige o corpo (o dono ou quem possui). <code>HealthUIController</code> recebe."],
  ["Cooldown por slot", "<code>RemoteEvents.SkillFired(intent, cooldown, cargas, maxCargas, restante, duração)</code> a cada cast. <code>CooldownUIController</code> anima o botão com o atributo <code>Intent</code> igual."],
  ["Botões de tela", "Qualquer GuiButton com a tag <code>InputButton</code> e o atributo <code>Intent</code> vira fonte daquela intent (Press/Release), sem código."],
  ["Corpo dirigido", "<code>RemoteEvents.ControlStateChanged(isLocked, entityID, suspendNative, model)</code> quando o controle muda (possessão, Lock)."],
])}
${N("<p>A UI é por <b>slot</b> (intent), nunca por nome de skill: trocar de forma, de arma ou roubar uma skill não exige nada novo na interface.</p>")}

<h2>Botão de skill no celular</h2>
${C(`
-- um ImageButton qualquer na ScreenGui
local CollectionService = game:GetService("CollectionService")
botao:SetAttribute("Intent", "Ability1")
CollectionService:AddTag(botao, "InputButton")
-- o InputService passa a mandar Press/Release da Ability1, e a HUD de cooldown já acha o botão
`)}

<h2>Mostrando estado novo (ícones de status, cargas, recurso)</h2>
<p>O padrão: no servidor, escute o evento que muda o estado e mande ao cliente que precisa ver. Não ponha lógica de jogo no cliente.</p>
${C(`
-- servidor: ícones de buff/debuff do player
local StatusIcons = Instance.new("RemoteEvent")
StatusIcons.Name = "StatusIcons"
StatusIcons.Parent = game.ReplicatedStorage.RemoteEvents

local function watch(entity)
    if not entity.Player then return end
    local function push(ctx, ligado)
        local runner = ctx.sourceRunner
        if runner and runner.type == StateTable.Enum.Types.Status then
            StatusIcons:FireClient(entity.Player, runner.skillName, ligado, runner:GetRemainingTime())
        end
    end
    entity:Listen({ Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onStart,
        Action = function(ctx) push(ctx, true) end })
    entity:Listen({ Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onEnd,
        Action = function(ctx) push(ctx, false) end })
end
`)}
${C(`
-- cliente
game.ReplicatedStorage.RemoteEvents.StatusIcons.OnClientEvent:Connect(function(nome, ligado, restante)
    -- cria/remove o ícone 'nome' e anima 'restante'
end)
`)}
<ul>
  <li>Status e skills emitem <span class="badge out">OUT</span> <code>onStart</code>/<code>onEnd</code> na entidade dona (o portador, num status): é o gancho natural para ícones.</li>
  <li>Para valor contínuo (recurso, combo, estágio), um atributo no Model (<code>model:SetAttribute("Mana", v)</code>) replica sozinho e o cliente lê com <code>GetAttributeChangedSignal</code>.</li>
  <li>Vida de outras entidades (barra sobre a cabeça): escute <code>IN.PostDamage</code>/<code>OnHeal</code> e grave <code>HP</code> num atributo do Model; um BillboardGui no cliente lê.</li>
  <li>Quem está sendo dirigido: use o corpo do <code>ControlStateChanged</code>, não <code>player.Character</code> (na possessão eles diferem).</li>
</ul>

<h2>Números de dano e feedback</h2>
${C(`
-- servidor: número flutuante para quem bateu
EntityCore.ListenWorld({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.OnDamage,
    Action = function(ctx, dono)
        if dono.Player and ctx.targetEntity and ctx.targetEntity.Instance then
            VFXManager.PlayAll("DamageNumber", {
                Position = ctx.hit and ctx.hit.position or ctx.targetEntity.GetPosition(),
                Amount = ctx.actualDamage,
            })
        end
    end,
})
-- cliente: Registry.DamageNumber = function(data) ... end  (VFXRegistry)
`)}
`,
});

// ================================================================== AVANÇADO
DOCS.page({
  id: "conceitos.heranca",
  parent: "avancado",
  order: 30,
  title: "Herança de reações e limites de inscrição",
  kw: "herança herdar inherit generations fork minion filho pai limit scope holder branch tree ttdinheritremaining priority enginepriority owner token triggerset",
  lead: "Inscrições podem passar de uma entidade para as que ela gera (Fork do TriggerSet) e ter limite de disparos compartilhado de três jeitos. É assim que um minion herda o on-hit do invocador sem código no minion.",
  html: `
<h2>Inherit</h2>
${C(`
dono:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onHit,
    Inherit = { Generations = 2 },      -- filhos e netos herdam
    Action = function(ctx) ctx.damage += 5 end,
})
local minion = MinionFactory.Spawn("Lobo", cf, dono)   -- ou DataManager.Create(..., dono)
`)}
<ul>
  <li>O Fork acontece na criação do filho; inscrições feitas depois no pai não chegam ao filho já criado.</li>
  <li>A cada geração, <code>Generations</code> cai 1; com 0, para de herdar.</li>
  <li>TTD: o filho ganha o TTD cheio de novo. Com <code>TTDInheritRemaining = true</code> no sub, herda o tempo restante (o TTD só encolhe na linhagem).</li>
  <li>Inscrição já expirada não é copiada.</li>
  <li>A <code>Action</code> é a mesma função: o <code>ctx</code> diz quem disparou (no filho, <code>ctx.sourceEntity</code> é o filho).</li>
</ul>

<h2>Limit e Scope</h2>
${T(["Scope", "Contagem no filho"], [
  ["<code>Holder</code> (padrão)", "Começa do zero em cada entidade."],
  ["<code>Branch</code>", "Copia a contagem do pai no momento do Fork e segue sozinha."],
  ["<code>Tree</code>", "Uma contagem só para a árvore inteira (pai e todos os filhos)."],
])}
<p><code>OnExhaust = "Remove"</code> tira a inscrição ao esgotar; <code>"Disable"</code> mantém sem disparar.</p>
${C(`
-- "os 3 primeiros acertos da matilha inteira aplicam sangramento"
dono:Listen({
    Role = Enum.Roles.OUT, Breakpoint = Enum.Breakpoints.onHit,
    Inherit = { Generations = 1 },
    Limit = { Max = 3, Scope = "Tree", OnExhaust = "Remove" },
    Action = function(ctx) table.insert(ctx.effects, StateTable.Status.Bleed) end,
})
`)}

<h2>Prioridade e listeners do motor</h2>
<p>Maior <code>Priority</code> roda antes; empate segue a ordem de inscrição (inserção ordenada, custo baixo com milhares de listeners). O motor inscreve as próprias regras (a morte cancelando skills, a interrupção) com <code>Enum.EnginePriority</code> (infinito): rodam antes de qualquer conteúdo no mesmo breakpoint.</p>

<h2>Owner</h2>
<p><code>StateTable.OwnerToken(entidade, tag)</code> devolve sempre o mesmo token para o par: use para limpar em lote (<code>UnsubscribeByOwner</code>) sem afetar outra entidade. Owner em string é global (o motor avisa).</p>
`,
});

DOCS.page({
  id: "conceitos.inicializacao",
  parent: "avancado",
  order: 35,
  title: "Inicialização e destruição",
  kw: "ordem inicialização create onadded initpriority high componentsloaded destroy destruição ciclo de vida entidade setmovement respawn",
  lead: "A ordem em que uma entidade nasce e morre, para quem escreve componentes ou depende de que algo já exista.",
  html: `
<h2>DataManager.Create</h2>
<ol class="flow">
  <li>Valida a entrada (player, Model, ou nada para CreateData). Inválida: <code>nil</code>, nada registrado.</li>
  <li>Gera o ID. Respawn de player reaproveita o ID e destrói a entidade anterior.</li>
  <li><code>EntityCore.new</code>; com pai, o TriggerSet do filho nasce do Fork do pai.</li>
  <li><code>AddComponent</code> de cada componente (o <code>new</code> de cada um roda; a ExposeAPI é injetada).</li>
  <li>Character recebe o Model (<code>SetEntity</code>).</li>
  <li><code>ComponentsLoaded</code>: confere <code>Requires</code> (warn imediato), roda os <code>OnAdded</code> de <code>InitPriority = "High"</code> (Attributes) e depois os outros.</li>
  <li>Registra no mapa e grava o atributo <code>EntityID</code> no Model (e no Player).</li>
  <li>Com Movement, conecta o corpo ao MovementController (<code>SetMovement</code>).</li>
</ol>
${N("<p>No <code>OnAdded</code> todos os componentes do lote já existem. No <code>new</code>, não conte com os outros.</p>")}

<h2>Destroy</h2>
<p>A entidade fica inativa, os componentes são destruídos (skills e status encerrados com cancel, Forces limpas, hitbox devolvida à pool), as inscrições somem e a API volta ao stub. Ações adiadas pela cadeia que cheguem depois encontram a entidade fora e não fazem nada.</p>

<h2>Player</h2>
<p><code>Main.server</code>: a cada CharacterAdded cria a entidade com os componentes do player; registra no AntiCheat; se havia possessão, solta tudo depois que o corpo novo existe. No PlayerRemoving: devolve os corpos possuídos, remove a entidade e desregistra.</p>
`,
});

DOCS.page({
  id: "conceitos.estender",
  parent: "avancado",
  order: 60,
  title: "Estendendo sem mexer no motor",
  kw: "estender extensão extend customizar modificar sem editar motor engine ponto de extensão hook gancho regra jogo diferente gênero",
  lead: "Quase toda mecânica nova cabe num ponto de extensão que já existe. Esta página lista os pontos, do mais leve ao mais pesado, para você escolher o menor antes de pensar em mudar o motor.",
  html: `
${T(["Você quer…", "Use"], [
  ["Mudar um número de design do motor", "O enum/config dono (" + L("conceitos.centralizacao") + ")."],
  ["Reagir a um momento do combate", L("conceitos.eventos", "Listen") + " num breakpoint (IN/OUT), com Query, Priority, Limit, TTD."],
  ["Reagir em qualquer entidade", L("api.EntityCore.ListenWorld", "ListenWorld") + "."],
  ["Estado com duração (buff, marca, janela de combo)", "Um status (" + L("conceitos.status") + ") ou " + L("api.ComboWindow", "ComboWindow") + "."],
  ["Proibir uma ação por um tempo", "Um estado com a tag (canCast, canMove) ou uma " + L("conceitos.criar", "tag nova") + "."],
  ["Proteção de dano nova (resistência, escudo de stat)", "Uma entrada em <code>Enum.DamageMitigation</code> ou um listener de PreDamage."],
  ["Interceptar o que uma entidade causa", "<code>OUT.onHit</code> (dano) e <code>OUT.PreApplyStatus</code> (status)."],
  ["Passar dado de uma ação para o que ela gera", "<code>inherited</code> (" + L("conceitos.context") + ")."],
  ["Trocar skills temporariamente", "Uma camada de loadout própria."],
  ["Bloquear um tipo de Force numa entidade", "<code>entity.AddFilter(id, function(force) return force.Type ~= 'Knockback' end)</code> (filtro devolve false = recusa)."],
  ["Mecânica sem corpo (carta, turno, placar)", L("api.DataManager.CreateData", "CreateData") + " + status + Listen + breakpoints próprios."],
  ["Estado global do jogo", "Uma entidade de dado (gerente) ou ListenWorld."],
  ["Recurso (mana, energia)", "Um stat ou atributo + checagem no onStart com <code>self:Fizzle()</code> (" + L("receitas.recurso") + ")."],
  ["Componente realmente novo", L("conceitos.entidades", "Escrevendo um componente") + " (último recurso: veja se não é status ou config)."],
])}
<h2>Quando é motor</h2>
<p>É mudança de motor quando nenhum dos pontos acima resolve e a regra precisa valer em todo o jogo de dentro do pipeline (ex.: uma tag que o MovementController respeite). Nesse caso a mudança é pontual, no ponto de extensão mais próximo, e passa pelo dono do projeto. Veja ${L("fluxo.finalizado")}.</p>
`,
});

DOCS.page({
  id: "conceitos.desempenho",
  parent: "avancado",
  order: 70,
  title: "Desempenho",
  kw: "desempenho performance otimização lag custo frame heartbeat memória vazamento leak pool cache escala muitas entidades",
  lead: "O peso do jogo deve vir da complexidade que você adiciona, não do framework. Em 15/10/2026 o motor rodou uma arena de 32 entidades por 5 min e um soak de 15 min sem erro nem vazamento (esse teste de carga não foi refeito depois das últimas rodadas).",
  html: `
<h2>O que o motor já faz</h2>
<ul>
  <li><b>Heartbeats centrais</b>: um para todas as skills/status (SkillScheduler), um para o movimento (MovementController), um para os Brains (AIScheduler). Nada de conexão por entidade.</li>
  <li><b>onStep só quem tem</b>: skill sem onStep não monta contexto por frame.</li>
  <li><b>Custo zero sem ouvinte</b>: PreApplyStatus, ListenWorld e o Emit não montam nada se ninguém escuta.</li>
  <li><b>Stubs compartilhados</b>: componente ausente não custa closure por entidade.</li>
  <li><b>Stats cacheados</b> até um modificador mudar.</li>
  <li><b>Pool de hitboxes</b> por arma + peça.</li>
  <li><b>Inscrição ordenada</b> por busca binária (milhares de listeners sem reordenar a lista).</li>
  <li><b>Regras resolvidas uma vez</b> (morte, imunidade, cooldown policy).</li>
</ul>

<h2>O que fica com você</h2>
<ul>
  <li>Limpe o que criar: <code>self:Own(fn)</code> e <code>self:Listen</code> dentro de skill; IDs de modificador e status removidos no onEnd; zonas paradas.</li>
  <li>Prefira <code>onStep</code> com acumulador a <code>task.spawn</code> com loop.</li>
  <li>Zona: poll de 10–15 Hz basta; zonas grandes com muitas peças custam mais.</li>
  <li>Hitbox solta: chame <code>HitboxSpawner.Cleanup</code> (os Presets já fazem no OnStopped).</li>
  <li>Logs em Debug no caminho quente: deixe o nível padrão em produção.</li>
  <li>Cadeias gigantes adiam para o próximo frame (ChainLimits): isso protege o servidor, não é bug.</li>
</ul>
`,
});

DOCS.page({
  id: "conceitos.seguranca",
  parent: "avancado",
  order: 80,
  title: "Segurança e autoridade",
  kw: "segurança exploit hack cheater cheat confiar cliente servidor autoridade validação remote rate limit payload sanitize anticheat",
  lead: "O servidor decide tudo que importa. O cliente pede intenções; o servidor valida tipo, taxa, alvo e movimento.",
  html: `
<h2>Regras</h2>
<ul>
  <li><b>Cliente não decide dano, cooldown nem alvo final.</b> Ele manda intent + payload; a skill no servidor confere alcance e linha de visão.</li>
  <li><b>Uma borda de rede</b>: o InputValidator valida tudo que chega (intent conhecida, booleano, taxa por intent, payload sanitizado). Remote novo do jogo: valide do mesmo jeito.</li>
  <li><b>Payload</b>: só passa Target string curta que existe e Point finito dentro do mundo. Nunca confie que o alvo está perto: confira.</li>
  <li><b>Movimento</b>: validado pelo GlobalAntiCheat (velocidade, Forces, chão). Teleporte do servidor abre a janela de confiança: mova corpos de player pelo servidor (<code>Teleport</code>, <code>PivotTo</code>), não peça ao cliente.</li>
  <li><b>Atributos do cliente não replicam</b> para o servidor: nada que o cliente grave vale como verdade.</li>
  <li><b>Lock corta na fonte</b>: com o input travado, o servidor nem roteia o que chega.</li>
</ul>
<h2>Fora de escopo do anti-cheat</h2>
<p>Noclip, voo contínuo na velocidade de pulo, empurrão físico fora das Forces e veículos. Se o jogo precisar, é sistema de jogo sobre o AntiCheat, ou migração para <code>AuthorityMode = Server</code>.</p>
`,
});

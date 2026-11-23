/* Início: boas-vindas, primeiros passos, mapa de pastas, glossário */

DOCS.page({
  id: "inicio",
  title: "Início",
  kw: "bem-vindo manual documentação começar overview visão geral",
  lead: "Manual do framework de combate para Roblox, em Luau. Aqui estão os conceitos, a API de cada módulo, os enums, receitas prontas e o fluxo de trabalho com o Studio.",
  html: `
${N("<p><strong>O framework está finalizado.</strong> O motor está completo no escopo decidido. O trabalho daqui em diante é fazer jogo com o que já existe: skills, status, personagens, armas, IA e HUD são <em>conteúdo</em>. Mudança no motor só quando específica e inevitável. Leia " + L("fluxo.finalizado") + " antes de propor um sistema novo.</p>")}

<h2>Por onde começar</h2>
<div class="cards">
  <a class="card" href="#inicio.passos"><b>Primeiros passos</b><span>Abrir o projeto, ligar o sync e ver uma skill rodando.</span></a>
  <a class="card" href="#conceitos.entidades"><b>Entidades e componentes</b><span>O modelo de dados de tudo que existe no jogo.</span></a>
  <a class="card" href="#conceitos.skills"><b>Skills e o ciclo de vida</b><span>Como uma skill nasce, roda e termina.</span></a>
  <a class="card" href="#conceitos.eventos"><b>Eventos (Listen)</b><span>Reagir a dano, morte, cura e status sem tocar o motor.</span></a>
  <a class="card" href="#receitas"><b>Receitas</b><span>DoT, parry, lifesteal, projétil, zona, minion, card game…</span></a>
  <a class="card" href="#api"><b>Referência da API</b><span>Cada função, com sintaxe, argumentos e exemplo.</span></a>
</div>

<h2>O que o framework faz</h2>
<p>É uma base de combate e entidades que não pressupõe gênero de jogo. O único pressuposto é a existência de <b>skills</b>: regras de ciclo de vida aplicadas a um momento de ação (um golpe, um buff, um efeito on-hit, uma reação em cadeia). Sobre isso, o framework entrega:</p>
<ul>
  <li><b>Entidades por componentes</b>: um player, um NPC, uma torre ou uma carta são a mesma coisa (um ${L("api.EntityCore", "EntityCore")}) com componentes diferentes.</li>
  <li><b>Skills e status no mesmo motor</b>: o ${L("conceitos.skills", "SkillRunner")} roda os dois com o mesmo ciclo (onStart, onStep, onHit, onEnd…), num heartbeat central.</li>
  <li><b>Reações por eventos</b>: qualquer momento importante (antes do dano, depois do dano, morte, cura, início e fim de skill, entrada de status) é um breakpoint que você escuta com ${L("api.EntityCore.Listen", "Listen")}.</li>
  <li><b>Pipeline de dano declarado</b>: imunidade, bloqueio, proteções de stat, multiplicador do atacante e efeitos on-hit seguem regras de dados (enums), não código espalhado.</li>
  <li><b>Movimento por Forces</b>: dash, knockback, vento, voo e agarrão, com prioridade por eixo e escala por massa.</li>
  <li><b>Input por intenções</b>: o cliente manda "quero usar o slot X", com gestos (tap, hold, double tap) e alvo/ponto opcional. NPCs usam o mesmo caminho.</li>
  <li><b>Possessão e controle</b>: um player pode dirigir outro corpo, em pilha, com IA pausada e devolvida.</li>
  <li><b>Rede</b>: o corpo do player é simulado pelo cliente e validado pelo servidor (anti-cheat de movimento), com previsão do atraso de visão.</li>
</ul>

<h2>Como ler este manual</h2>
<ul>
  <li><b>Guia básico</b>: entidades, skills, status, eventos, dano, input, movimento, HUD, a regra de centralização e como criar tags e enums. Leia na ordem se você é novo.</li>
  <li><b>Guia avançado</b>: contexto e herança explícita, cadeias, rede, possessão, herança de reações, desempenho, segurança e como estender sem mexer no motor.</li>
  <li><b>Referência da API</b> tem uma página por função, no estilo do manual do GameMaker: sintaxe, argumentos, retorno e exemplos de uso em contexto, cada um seguido do parágrafo "O código acima..." que explica o que ele faz.</li>
  <li><b>Enums</b> lista os valores e padrões (todo número de design do motor mora num enum, não no código).</li>
  <li><b>Receitas</b> resolvem casos reais só com a API pública.</li>
  <li><b>Fluxo de trabalho</b> cobre sync com o Studio, testes, convenções e as decisões de design já tomadas.</li>
</ul>
<p>A busca no topo aceita sinônimos em português e inglês e ignora acentos: <i>empurrar</i> acha Forces, <i>atordoar</i> acha Stun, <i>carta</i> acha a receita de card game. Atalho: <kbd>/</kbd> ou <kbd>Ctrl</kbd>+<kbd>K</kbd>.</p>

<h2>Convenções de escrita</h2>
${T(["Forma", "Significa"], [
  ["<code>entity.TakeDamage(10)</code>", "API de componente exposta na entidade: chame com <b>ponto</b>, nunca com dois-pontos."],
  ["<code>entity:Listen(sub)</code>", "Método do próprio EntityCore: chame com <b>dois-pontos</b>."],
  ["<code>self:Damage(alvo, 10)</code>", "Dentro de uma skill ou status, <code>self</code> é a instância isolada da skill."],
  ["<code>arg?</code>", "Argumento opcional."],
  ["<code>StateTable.Enum.X</code>", "Enum do motor (pasta <code>ServerStorage/Modules/Combat/StateTable/Enum</code>)."],
])}
`,
});

DOCS.page({
  id: "inicio.passos",
  parent: "inicio",
  title: "Primeiros passos",
  kw: "começar setup instalar abrir studio sync clonar rodar play",
  lead: "Do clone até ver uma skill rodando no Studio.",
  html: `
<h2>1. O repositório</h2>
<p>O repositório tem três partes:</p>
${T(["Pasta", "O que é"], [
  ["<code>sync/</code>", "O código do jogo, espelhado pelo Script Sync do Studio (cada <code>.luau</code> é um script no place)."],
  ["<code>docs/</code>", "Este manual. Abre direto no navegador (<code>docs/index.html</code>), sem servidor e sem internet."],
  ["<code>tools/audit_suite/AUDITORIA.md</code>", "Histórico da auditoria do motor (achados e correções)."],
])}

<h2>2. Ligar o sync</h2>
<p>No Studio, abra o place e ligue o <b>Script Sync</b> apontando para a pasta <code>sync/</code> do repositório. O sync é <b>bidirecional</b>: um arquivo salvo no disco chega ao Studio em cerca de 2 s (também com o jogo em Play), e uma edição no Studio volta para o disco. Detalhes em ${L("fluxo.sync")}.</p>
${W("<p><strong>Cuidado:</strong> nunca rode comandos git que reescrevem arquivos em <code>sync/</code> (<code>git stash</code>, <code>git checkout -- arquivo</code>, <code>git reset --hard</code>) com o Studio aberto: o Studio recebe a mudança na hora.</p>")}

<h2>3. Dar Play</h2>
<p>Ao entrar no jogo, o <code>Main.server</code> cria a entidade do player com os componentes padrão (Character, Combat, Health, Weapon, Movement, Status, Animation, Attributes). O personagem padrão é o kit <code>Schema</code> (${L("enum.personagem", "Enum.CombatDefaults")}), com M1 no clique, Dash no Shift, Ultimate no 4.</p>

<h2>4. Ler uma skill de exemplo</h2>
<p>As skills de referência ficam em <code>ServerStorage/DataBase/SkillDatabase/Schema/</code>:</p>
${T(["Skill", "Mostra"], [
  ["<code>M1</code>", "Combo de dois golpes com recast, hitbox da arma por skill, marcador de animação, <code>requires</code>."],
  ["<code>Dash</code>", "Force Hard sem gravidade, ActionState Self, reações com <code>Listen</code> (combo com Bleed e cura na Ultimate)."],
  ["<code>Ultimate</code>", "Voo com direção reavaliada por frame, agarrão rígido com <code>AttachTo</code>, limpeza com <code>Own</code>."],
  ["<code>WeaponTransform</code>", "Troca de modo da arma no fim da transformação, camada de loadout <code>WeaponMode</code>, <code>ctx.reason</code>."],
])}
<p>Comece por ${L("receitas.skill")} para escrever a sua.</p>

<h2>5. Criar uma entidade em código</h2>
${C(`
local DataManager = require(game.ServerScriptService.EntityData.DataManager)
local Component = require(game.ServerScriptService.EntityData.ComponentsExport)

local boneco = workspace.Dummies.Alvo -- um Model com HumanoidRootPart
local entity = DataManager.Create(boneco, {
    Component.Character, Component.Health, Component.Status,
}, {
    Health = { MaxHP = 500 },
})

entity.TakeDamage(25)          -- API de componente: ponto
print(entity.GetHP())          -- 475
`)}
<p>Veja ${L("api.DataManager.Create")} e ${L("conceitos.entidades")}.</p>
`,
});

DOCS.page({
  id: "inicio.mapa",
  parent: "inicio",
  title: "Mapa de pastas",
  kw: "estrutura pastas arquivos onde fica localização path caminho hierarquia",
  lead: "Onde cada parte do framework mora no place (e em sync/).",
  html: `
<h2>ServerScriptService</h2>
${T(["Caminho", "Conteúdo"], [
  ["<code>EntityData/EntityCore</code>", "Núcleo da entidade, registro de componentes, eventos (Listen/Emit/ListenWorld)."],
  ["<code>EntityData/DataManager</code>", "Criar, buscar e remover entidades."],
  ["<code>EntityData/Components/*</code>", "Os componentes (auto-registrados pelo nome do arquivo, sem o sufixo <code>Component</code>)."],
  ["<code>EntityData/ComponentsExport</code>", "Atalho para <code>EntityCore.ComponentKey</code> (nomes dos componentes)."],
  ["<code>EntityData/EntityWrapper</code>", "Abstração Humanoid × rig sem Humanoid (caminhada, pulo, Forces)."],
  ["<code>Modules/SkillRunner</code>, <code>SkillScheduler</code>, <code>SkillHandler</code>, <code>SkillFactory</code>", "Ciclo de vida de skills/status, heartbeat central, borda do input."],
  ["<code>Modules/CooldownPolicy</code>", "Regras de cooldown (cargas, recast, refund, redução, herança)."],
  ["<code>Modules/GlobalAntiCheat</code>", "Validação de movimento do player e roteamento do input (Lock, possessão)."],
  ["<code>Modules/Physics/*</code>", "MovementController, ForceRig, Settings, NetworkView, CollisionGroups."],
  ["<code>Modules/AI/AIScheduler</code>", "Heartbeat único dos Brains de IA."],
  ["<code>Modules/VFX/VFXManager</code>, <code>Modules/Audio/SoundManager</code>", "Disparo de VFX nos clientes e som 3D."],
  ["<code>Scripts/Main.server</code>", "Cria a entidade do player a cada spawn."],
  ["<code>Scripts/InputValidator.server</code>", "Única borda de rede do input (valida e encaminha)."],
])}

<h2>ServerStorage</h2>
${T(["Caminho", "Conteúdo"], [
  ["<code>DataBase/CharacterDatabase/&lt;Kit&gt;/&lt;Modo&gt;</code>", "Stats, loadout e arma de cada forma de personagem."],
  ["<code>DataBase/SkillDatabase/&lt;Kit&gt;/&lt;Skill&gt;</code>", "As skills. A pasta de 1º nível é o kit dono. Chaves em <code>SkillDatabase.Keys</code>."],
  ["<code>DataBase/SkillDatabase/BaseSkills</code>", "Utilitários de skill (ComboWindow)."],
  ["<code>Modules/Combat/StateTable</code>", "Status, estados, ActionStates, Enum e Helper (regras transversais)."],
  ["<code>Modules/Combat/TriggerSet</code>, <code>TraitQuery</code>, <code>Lineage</code>, <code>Types</code>", "Pub/sub, filtro por traits, árvore de cadeia, tipos (Context, Subscription)."],
  ["<code>Modules/Combat/Hitbox/*</code>", "HitboxWrapper (arma), HitboxSpawner/Behaviors/Presets (projéteis), ShapecastHitbox (biblioteca)."],
  ["<code>Modules/Combat/AreaEffect</code>, <code>AreaBehaviors</code>", "Zonas e forças de ambiente."],
  ["<code>Modules/Animation/AnimationLib</code>", "IDs de animação por kit."],
  ["<code>Modules/MinionFactory</code>", "Invocar entidades por blueprint."],
  ["<code>Assets/Hitboxes</code>", "Peças de hitbox de referência."],
])}

<h2>ReplicatedStorage</h2>
${T(["Caminho", "Conteúdo"], [
  ["<code>Input/Intents</code>, <code>Input/GestureResolver</code>", "Intenções, gestos, payload de alvo/ponto."],
  ["<code>Config/InputConfig</code>", "Bindings (tecla, mouse, gamepad) e o atributo dos botões de tela."],
  ["<code>Config/LogConfig</code>", "Quanto do framework aparece no Output."],
  ["<code>Logger</code>, <code>Utils</code>", "Saída por canal e utilitários de vetor/direção."],
  ["<code>Assets/Weapons/&lt;Kit&gt;/&lt;Arma&gt;</code>", "Model da arma e <code>WeaponData</code> (modos, pontos de attach, loadout do modo)."],
  ["<code>RemoteEvents</code>", "RequestIntent, RequestDir, RequestLook, RequestJump, SkillFired, UpdateHealthBar, PlayVFX, ControlStateChanged."],
])}

<h2>StarterPlayer</h2>
${T(["Caminho", "Conteúdo"], [
  ["<code>StarterPlayerScripts/InputService</code>", "Input do cliente (bindings, botões de tela, payload, rebind)."],
  ["<code>StarterPlayerScripts/LookDirectionBroadcaster</code>", "Manda a direção da câmera ao servidor."],
  ["<code>StarterPlayerScripts/CameraOverride</code>", "Câmera de ombro com soft lock (tecla C)."],
  ["<code>StarterPlayerScripts/VFXPlayer</code>, <code>VFXRegistry</code>", "Recebe e constrói os VFX."],
  ["<code>StarterPlayerScripts/TeleportSmoother</code>", "Suaviza a câmera em saltos de posição."],
  ["<code>StarterCharacterScripts/HealthUIController</code>, <code>CooldownUIController</code>", "HUD de vida e de cooldown por slot."],
])}

<h2>ServerStorage/!DOC</h2>
<p>Notas originais do projeto, em texto. Este manual é a referência atual; se algo divergir, vale o manual.</p>
`,
});

DOCS.page({
  id: "inicio.glossario",
  parent: "inicio",
  title: "Glossário",
  kw: "termos definição vocabulário significado o que é",
  lead: "Os termos que aparecem em todo o manual.",
  html: T(["Termo", "Definição"], [
    ["<b>Entidade</b>", "Qualquer coisa do jogo com componentes: player, NPC, torre, projétil com vida, carta. É um " + L("api.EntityCore", "EntityCore") + ", criado pelo " + L("api.DataManager", "DataManager") + "."],
    ["<b>Componente</b>", "Módulo que dá dados e API a uma entidade (Health, Status, Combat…). A API dele vira função da entidade: <code>entity.Heal(10)</code>."],
    ["<b>Skill</b>", "Módulo <code>{ data, callbacks }</code> que descreve uma ação. Cada ativação é uma instância isolada."],
    ["<b>Status</b>", "Buff/debuff com duração, rodado pelo mesmo motor da skill (tem onStart, onStep, onEnd…)."],
    ["<b>Estado (State)</b>", "Status especial de controle: Stun, Root, Silence, NoControl. Fica num grupo separado."],
    ["<b>ActionState</b>", "Trava de execução de uma ação (Self, Out, LockedCast): diz se a skill atual pode ser auto-cancelada por outra."],
    ["<b>Runner</b>", "O " + L("api.SkillRunner", "SkillRunner") + " de uma ativação: estado (Idle → Casting → Running → Ended), tempo, cadeia."],
    ["<b>Tag</b>", "Permissão booleana que um status liga ou desliga na entidade: canMove, canCast, iFrame, block, interrupt…"],
    ["<b>Trait</b>", "Marca de comportamento de uma skill/status/hit: DOT, Melee, TrueDamage, Uninterruptible… Usada em filtros (Query)."],
    ["<b>Breakpoint</b>", "Momento nomeado do ciclo (PreDamage, OnDeath, onHit…) em que listeners rodam."],
    ["<b>IN / OUT</b>", "Papel do evento: IN = o que acontece COM a entidade (apanhou, morreu); OUT = o que a entidade CAUSA (acertou, matou)."],
    ["<b>Listener / Subscription</b>", "Inscrição num breakpoint: <code>{ Role, Breakpoint, Action, Query?, Priority?, Owner?, Limit?, TTD?, Inherit? }</code>."],
    ["<b>Context (ctx)</b>", "Tabela que o motor monta e entrega em cada breakpoint. Dois formatos: RunnerContext (ciclo de vida) e HitContext (dano/status)."],
    ["<b>inherited</b>", "Payload explícito que uma skill passa para o que ela gera (status, hit, skill filha). Só leitura no filho."],
    ["<b>Lineage</b>", "Árvore de quem causou o quê: profundidade, raiz, origem. Base do " + L("conceitos.cadeias", "limite de cadeia") + " e do crédito de morte."],
    ["<b>Dono do efeito</b>", "Quem causou um efeito, não onde ele roda: a morte por Bleed credita quem aplicou o Bleed (" + L("api.StateTable.EffectOwner", "EffectOwner") + ")."],
    ["<b>Loadout</b>", "Mapa slot → skill. Em camadas: a de cima vence no slot (Base, WeaponMode, ou camadas do jogo)."],
    ["<b>Intent</b>", "Intenção de input (Primary, Dash, Ability1…): o que o player quer fazer, independente da tecla."],
    ["<b>Gesto</b>", "Como a intent foi acionada: Press, Tap, Hold, DoubleTap."],
    ["<b>Kit</b>", "Personagem dono de skills e animações: o nome da pasta em SkillDatabase/CharacterDatabase/AnimationLib (ex.: Schema)."],
    ["<b>Force</b>", "Pedido de movimento com duração (dash, knockback, vento). Hard fixa o eixo; Soft soma com a caminhada."],
    ["<b>Modelo B</b>", "Arquitetura de rede: o cliente simula o próprio corpo; o servidor valida e corrige."],
    ["<b>Possessão</b>", "Um controlador (player ou IA) assume outro corpo. Em pilha: soltar volta ao anterior."],
  ]),
});

/* Fluxo de trabalho: framework finalizado, sync, testes, convenções, decisões, limitações */

DOCS.page({
  id: "fluxo", title: "Fluxo de trabalho", kw: "fluxo trabalho workflow processo",
  lead: "Como trabalhar no projeto: a diretriz de framework finalizado, o sync com o Studio, testes, convenções, decisões e limitações conhecidas.",
  html: "",
});

DOCS.page({
  id: "fluxo.finalizado", parent: "fluxo", order: 1, title: "Trabalhando com o framework finalizado",
  kw: "finalizado pronto completo mudar motor novo sistema redundante diretriz regra",
  lead: "O motor está completo no escopo decidido (23/11/2026, 116 achados de auditoria, 0 abertos). O trabalho agora é fazer jogo com o que existe.",
  html: `
<ol class="flow">
  <li><b>Quase tudo se faz com o que já existe.</b> Antes de escrever código novo, procure aqui o sistema que resolve: Listen para reação, status para estado com duração, inherited para passar dado, camadas de loadout, CreateData, ListenWorld, AffectsFilter, Forces e AttachTo. Veja ${L("conceitos.estender")}.</li>
  <li><b>Evite criar sistemas novos.</b> Um sistema que repete um existente quebra a regra de centralização e quase sempre é redundante. Skills, status, personagens, armas, IA, HUD, recursos e mais intents são conteúdo, não motor.</li>
  <li><b>Mudança no motor só quando específica e inevitável.</b> Mostre por que nenhum sistema atual resolve, proponha a menor mudança no ponto de extensão existente e só implemente com o ok do dono do projeto.</li>
  <li><b>Valor de jogo é config.</b> Limites e padrões ficam nos ${L("enum", "Enums")} e em ${L("api.Settings", "Physics/Settings")}.</li>
</ol>`,
});

DOCS.page({
  id: "fluxo.sync", parent: "fluxo", title: "Sync com o Studio",
  kw: "sync script sync studio rojo pasta disco hash bidirecional",
  lead: "sync/ é o Script Sync nativo do Studio, bidirecional.",
  html: `
<ul>
  <li>Um <code>.luau</code> salvo no disco chega ao Studio em ~2 s (também em Play); edição no Studio volta ao disco.</li>
  <li>Confira qual pasta o Studio lê comparando hash (FNV-1a do Source sem <code>\\r</code>) dos dois lados.</li>
  <li>Arquivo novo pode não ficar ligado ao sync: confira o hash depois de cada edição.</li>
  <li>Nunca rode <code>git stash</code>, <code>git checkout -- arquivo</code> ou <code>git reset --hard</code> em <code>sync/</code> com o Studio aberto.</li>
  <li><code>.gitattributes</code> fixa LF; <code>sourcemap.json</code> é gerado pelo Studio (fora do git).</li>
</ul>`,
});

DOCS.page({
  id: "fluxo.testes", parent: "fluxo", title: "Testando mudanças",
  kw: "teste testar play mcp execute_luau mutação cliente sonda",
  lead: "O repositório não tem mais suíte (último resultado antes da remoção: 136/136 no Play, StaticChecks 4/4). Teste cada mudança no Studio.",
  html: `
<ul>
  <li>Script temporário em ServerScriptService (servidor) ou LocalScript no PlayerGui (cliente), apagado no fim. A suíte antiga está no histórico do git (commit <code>bf1eb77</code>).</li>
  <li>Um teste que passa com o código antigo não protege nada: confira por mutação.</li>
  <li>O que o player vê só aparece medindo no cliente (RenderStepped): o servidor vê o corpo ~0,35 s atrasado.</li>
  <li>Atributo setado pelo cliente não replica ao servidor. O place roda com sinais Deferred.</li>
  <li>Pare o Play quando o teste acabar.</li>
</ul>`,
});

DOCS.page({
  id: "fluxo.convencoes", parent: "fluxo", title: "Convenções",
  kw: "convenções commit mensagem padrão estilo nomes debug prefixo",
  html: `
<ul>
  <li>Commits em português, um por item: <code>fix:</code>, <code>feat:</code>, <code>chore:</code>, <code>docs:</code>.</li>
  <li>Saída pelo Logger; debug temporário com <code>[FW-DEBUG]</code>.</li>
  <li>Nada de nomes duplicados (nem só na capitalização).</li>
  <li>Comentários descrevem o código atual e o porquê; histórico fica no git.</li>
</ul>`,
});

DOCS.page({
  id: "fluxo.decisoes", parent: "fluxo", title: "Decisões de design",
  kw: "decisões design escolhas não reabrir hp acima do máximo possessão modelo b",
  lead: "Escolhas fechadas. Só se reabrem com justificativa técnica nova.",
  html: `<ul>
<li>HP acima do MaxHP é design (sobrevida); SetHP/Revive definem o valor exato; o teto da cura é HealCap.</li>
<li>HP 0 não mata o Humanoid nem força respawn (regras em Enum.DeathDefaults).</li>
<li>Possessão em pilha (Stack/Swap), IA pausada e restaurada.</li>
<li>Rede no modelo B; Server Authority nativo fica para uma reescrita futura do movimento.</li>
<li>Força Soft aditiva à caminhada; Hard absoluta.</li>
<li>Uma partida por servidor (sem singleton de mundo).</li>
<li>Interrupção por CC é uma tag (interrupt) e a trait Uninterruptible.</li>
<li>Mais intents, recurso (mana) e HUD são jogo, não motor.</li>
<li>Enum.ChainLimits fica como está; aumente na config se um jogo precisar.</li>
</ul>`,
});

DOCS.page({
  id: "fluxo.limitacoes", parent: "fluxo", title: "Limitações conhecidas",
  kw: "limitações bugs conhecidos não testado pendente problema",
  html: `<ul>
<li><b>SetCharMode em runtime com Attributes</b>: a troca de forma não atualiza os stats base do AttributesComponent (Speed, JumpForce, Defense, DamageMult, GravityScale ficam os da forma inicial; o MovementController relê Speed/JumpForce do Attributes todo frame). MaxHP e loadout trocam. O <code>_ApplyStats</code> lê <code>JumpPower</code>, mas a forma declara <code>JumpForce</code>. Contorno: <code>entity.SetStat</code> depois do SetCharMode. Correção pendente de decisão.</li>
<li>Nunca testado: mais de um player ao mesmo tempo, latência real (simulador de rede), carga depois de 15/10/2026.</li>
<li>A arma é achada pelo kit (<code>Assets/Weapons/&lt;Kit&gt;</code>): uma skill de arma roubada por outro kit só funciona se a arma estiver equipada.</li>
<li>Anti-cheat fora de escopo: noclip, voo contínuo, empurrão físico fora das Forces, veículos.</li>
</ul>`,
});

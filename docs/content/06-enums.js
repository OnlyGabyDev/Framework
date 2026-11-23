/* Enums do framework (StateTable.Enum) */

DOCS.page({
  id: "enum",
  title: "Enums",
  kw: "enum enums valores constantes padrões defaults configuração statetable",
  src: "ServerStorage/Modules/Combat/StateTable/Enum",
  lead: "Todo nome e número de design do motor mora aqui. Para mudar um padrão do jogo, troque o valor no Enum; para um valor novo, acrescente aqui (regra de centralização).",
  html: C(`
local Enum = require(game.ServerStorage.Modules.Combat.StateTable).Enum
-- ou, dentro de skill/status: self.statusTable.Enum
`) + N("<p>Este Enum é do framework. O <code>Enum</code> global do Roblox (KeyCode, Material…) continua existindo; nos módulos do framework, o do framework costuma ser importado como <code>Enum</code> ou <code>StateEnum</code>.</p>"),
});

DOCS.page({
  id: "enum.categorias", parent: "enum", title: "Categories, States e Types",
  kw: "categories categoria buff debuff hybrid internal actionstate states stun root silence nocontrol types skill status state",
  html: `
<h3>Enum.Categories</h3>
${T(["Valor", "Uso"], [
  ["<code>Buff</code>", "Buff."], ["<code>Debuff</code>", "Debuff."], ["<code>Hybrid</code>", "Buff e debuff."],
  ["<code>ActionState</code>", "Trava de ação (não use em status)."], ["<code>Internal</code>", "Interno (marcadores, blocks de motor): evita interação inesperada."],
])}
<h3>Enum.States</h3>
${T(["Valor", "Efeito (tags)"], [
  ["<code>Stun</code>", "canMove, canRotate, canCast = false; interrupt = true."],
  ["<code>NoControl</code>", "canMove, canRotate = false."],
  ["<code>Root</code>", "canMove = false."],
  ["<code>Silence</code>", "Impede skills (canCast = false)."],
])}
<h3>Enum.Types</h3>
<p><code>Skill</code>, <code>State</code>, <code>Status</code>: tipo do runner.</p>`,
});

DOCS.page({
  id: "enum.traits", parent: "enum", title: "Traits",
  kw: "traits dot effectshield stackable melee ultimate unbreakable blockbreak trueblock truehit truedamage uninterruptible softcancel heavycancel",
  html: T(["Chave", "Valor", "O quê"], [
    ["<code>DOT</code>", "DamageOverTime", "Dano periódico."],
    ["<code>EffectShield</code>", "EffectShield", "Escudo de efeito (reservado)."],
    ["<code>Stackable</code>", "stackable", "Status empilhável."],
    ["<code>Melee</code>", "Melee", "Corpo a corpo."],
    ["<code>Ultimate</code>", "Ultimate", "Ultimate."],
    ["<code>Unbreakable</code>", "Unbreakable", "Bloqueio que não quebra."],
    ["<code>BlockBreak</code>", "BlockBreak", "Quebra bloqueio."],
    ["<code>TrueBlock</code>", "TrueBlock", "Bloqueio que TrueHit não ignora."],
    ["<code>TrueHit</code>", "TrueHit", "Fura iFrame e ignora bloqueio comum."],
    ["<code>TrueDamage</code>", "TrueDamage", "Fura Defense/Armor."],
    ["<code>Uninterruptible</code>", "Uninterruptible", "Skill não cancelada pela tag interrupt."],
    ["<code>SoftCancel</code>", "LightCancel", "Reservado."],
    ["<code>HeavyCancel</code>", "HeavyCancel", "Reservado."],
  ]) + "<p>Também: <code>Enum.BlockIgnore</code> (traits que ignoram bloqueio: TrueHit) e <code>Enum.BlockBreak</code> (traits que quebram: BlockBreak).</p>",
});

DOCS.page({
  id: "enum.breakpoints", parent: "enum", title: "Breakpoints, Roles e EnginePriority",
  kw: "breakpoints onheal ondamage predamage postdamage preapplystatus ondeath onrevive oninterrupt onstart ontrigger onrecast onhit onrelease onend onforceincoming roles in out enginepriority",
  html: `
${T(["Breakpoint", "Papel", "Quando"], [
  ["<code>onHit</code>", "OUT", "Atacante, antes do dano."],
  ["<code>PreDamage</code>", "IN", "Alvo, antes do HP mudar (cancelável)."],
  ["<code>PostDamage</code>", "IN", "Alvo, depois do HP mudar."],
  ["<code>OnDamage</code>", "OUT", "Dono do dano, depois."],
  ["<code>OnHeal</code>", "IN / OUT", "Curado antes; dono da cura depois."],
  ["<code>OnDeath</code>", "IN / OUT", "Morto; dono do que matou."],
  ["<code>OnRevive</code>", "IN", "Revivido."],
  ["<code>PreApplyStatus</code>", "OUT", "Dono do efeito, antes de um status entrar (cancelável)."],
  ["<code>OnInterrupt</code>", "IN", "Entrou estado com a tag interrupt."],
  ["<code>onStart</code>, <code>onEnd</code>", "OUT", "Início e fim de skill/status na entidade dona."],
  ["<code>onTrigger</code>, <code>onRecast</code>, <code>onRelease</code>", "—", "Nomes dos callbacks."],
  ["<code>OnForceIncoming</code>", "—", "Reservado."],
])}
<p><code>Enum.Roles</code> = <code>{ IN = "IN", OUT = "OUT" }</code>. <code>Enum.EnginePriority</code> = <code>math.huge</code>: prioridade dos listeners internos do motor.</p>
<p>Detalhes em ${L("conceitos.eventos")}.</p>`,
});

DOCS.page({
  id: "enum.fim", parent: "enum", title: "EndReasons",
  kw: "endreasons motivo fim reason cancel duration stop error fizzle refused interrupted",
  html: T(["Chave", "Valor", "Quando"], [
    ["<code>Cancel</code>", "cancel", "Cancelado (Stop(true), remoção do status, morte)."],
    ["<code>Duration</code>", "duration", "A duração acabou."],
    ["<code>Stop</code>", "stop", "A skill se encerrou sem cancelar."],
    ["<code>Error</code>", "error", "Erro no onStart/onStep."],
    ["<code>Fizzle</code>", "fizzle", "<code>self:Fizzle()</code>: o cast não aconteceu."],
    ["<code>Refused</code>", "refused", "O motor não deixou começar (requires, ChainLimits)."],
    ["<code>Interrupted</code>", "interrupted", "Cancelada por estado com a tag interrupt."],
  ]) + "<p>Chega em <code>ctx.reason</code> no onCancel, onEnd e OUT.onEnd, e é a chave do <code>refund</code> do cooldown.</p>",
});

DOCS.page({
  id: "enum.tags", parent: "enum", title: "Tags e tagsBase",
  kw: "tags tagsbase canmove cancast canrotate candisplace interrupt iframe block exclusive padrão",
  html: T(["Tag", "Padrão (tagsBase)", "O quê"], [
    ["<code>canMove</code>", "true", "Pode se mover."],
    ["<code>canCast</code>", "true", "Pode usar skills."],
    ["<code>canRotate</code>", "true", "Pode girar."],
    ["<code>canDisplace</code>", "true", "Pode ser deslocado por forças externas."],
    ["<code>interrupt</code>", "false", "Ao entrar, cancela as skills (menos Uninterruptible)."],
    ["<code>iFrame</code>", "false", "Imune (com bypassBy)."],
    ["<code>block</code>", "false", "Bloqueia (status dono decide)."],
    ["<code>exclusive</code>", "—", "Nome usado em ActionStates."],
  ]) + "<p>Criar uma tag: " + L("conceitos.criar") + ".</p>",
});

DOCS.page({
  id: "enum.stats", parent: "enum", title: "Stats, StatDefaults, StatLimits e ModifierType",
  kw: "stats statdefaults statlimits statlimitdefault modifiertype flat addpercent multpercent override speed maxhp jumpforce defense damagemult weapon gravityscale cooldownreduction armor",
  html: `
${T(["Stat", "Padrão", "Limite"], [
  ["<code>Speed</code>", "16", "≥ 0"], ["<code>JumpForce</code>", "50", "≥ 0"], ["<code>MaxHP</code>", "100", "≥ 0"],
  ["<code>Defense</code>", "0", "livre (negativa amplifica)"], ["<code>DamageMult</code>", "1", "≥ 0"],
  ["<code>GravityScale</code>", "1", "≥ 0"], ["<code>CooldownReduction</code>", "0", "≥ 0 (fração)"], ["<code>Armor</code>", "0", "≥ 0"],
  ["<code>Weapon</code>", "—", "texto (nome da arma)"],
])}
<p><code>Enum.StatLimitDefault = { min = 0, max = math.huge }</code>; exceções em <code>Enum.StatLimits</code>.</p>
<h3>Enum.ModifierType</h3>
${T(["Tipo", "Efeito"], [
  ["<code>Flat</code>", "Soma na base."], ["<code>AddPercent</code>", "Soma percentuais: × (1 + soma)."],
  ["<code>MultPercent</code>", "Multiplica no final."], ["<code>Override</code>", "Substitui a base (vale o menor)."],
])}
<p>Veja ${L("conceitos.stats")}.</p>`,
});

DOCS.page({
  id: "enum.dano", parent: "enum", title: "DamageMitigation, MitigationModes e BlockModes",
  kw: "damagemitigation mitigationmodes multiplicative flat blockmodes full percent custom fórmula dano proteção",
  html: `
${C(`
Enum.DamageMitigation = {
    { stat = "Defense", mode = "Multiplicative", ignoredBy = { "TrueDamage" } },
    { stat = "Armor",   mode = "Flat",           ignoredBy = { "TrueDamage" } },
}
-- Multiplicative: dano * 100 / (100 + stat)   (stat negativo: dano * (2 - 100 / (100 - stat)))
-- Flat:           dano - stat
`)}
<h3>Enum.BlockModes</h3>
${T(["Modo", "Efeito"], [
  ["<code>Full</code>", "Zera o dano; num escudo de status, barra o status."],
  ["<code>Flat</code>", "Tira <code>value</code> do dano."],
  ["<code>Percent</code>", "Tira a fração <code>value</code>."],
  ["<code>Custom</code>", "O onTrigger decide (obrigatório)."],
])}`,
});

DOCS.page({
  id: "enum.efeitos", parent: "enum", title: "EffectDefaults",
  kw: "effectdefaults efeitos on-hit onblocked onzerodamage effectpolicy",
  html: C(`
Enum.EffectDefaults = {
    onBlocked = false,    -- hit zerado pelo bloqueio NÃO aplica os efeitos
    onZeroDamage = true,  -- hit de 0 de dano (slow puro, marca) aplica
}
-- por skill: data.effectPolicy = { onBlocked = ..., onZeroDamage = ... }
-- por efeito: { status = X, onBlocked = ..., onZeroDamage = ... }
`),
});

DOCS.page({
  id: "enum.morte", parent: "enum", title: "DeathDefaults",
  kw: "deathdefaults morte cancelskillsondeath refusestatusondeath refusecastondeath",
  html: C(`
Enum.DeathDefaults = {
    CancelSkillsOnDeath = true, -- Combat: a morte cancela as skills ativas
    RefuseStatusOnDeath = true, -- Status: morto não recebe status (data.allowOnDead fura)
    RefuseCastOnDeath = true,   -- Combat: morto não casta
}
-- por entidade: no config do componente, com a mesma chave
`),
});

DOCS.page({
  id: "enum.cura", parent: "enum", title: "HealthDefaults",
  kw: "healthdefaults healcap teto cura sobrevida",
  html: C(`
Enum.HealthDefaults = { HealCap = 1 }   -- teto da cura em × MaxHP; math.huge = sem teto
-- por entidade: Health = { HealCap = ... }; por cura: Heal(n, { Cap = ... })
`),
});

DOCS.page({
  id: "enum.alvos", parent: "enum", title: "Relations e AffectsDefaults",
  kw: "relations self ally enemy neutral affectsdefaults alvo time",
  html: C(`
Enum.Relations = { Self = "Self", Ally = "Ally", Enemy = "Enemy", Neutral = "Neutral" }
Enum.AffectsDefaults = { Self = false, Ally = false, Enemy = true, Neutral = true }
-- por skill: data.affects = { Ally = true }
`),
});

DOCS.page({
  id: "enum.personagem", parent: "enum", title: "CombatDefaults e LoadoutLayers",
  kw: "combatdefaults chosenchar mode personagem padrão loadoutlayers base weaponmode camada",
  html: C(`
Enum.CombatDefaults = { ChosenChar = "Schema", Mode = "Base" }  -- personagem quando o config não diz
Enum.LoadoutLayers = { Base = "Base", WeaponMode = "WeaponMode" } -- o jogo pode usar qualquer nome a mais
`),
});

DOCS.page({
  id: "enum.cooldown", parent: "enum", title: "CooldownStart, RecastPolicy e CooldownDefaults",
  kw: "cooldownstart cast end manual recastpolicy blocked restart free cooldowndefaults refund maxreduction recastlegacy",
  html: C(`
Enum.CooldownStart = { Cast = "Cast", End = "End", Manual = "Manual" }
Enum.RecastPolicy = { Blocked = "Blocked", Restart = "Restart", Free = "Free" } -- ou um número (s)
Enum.CooldownDefaults = {
    start = "Cast",
    recastLegacy = "Restart",                          -- skill com onRecast sem recast declarado (avisa)
    refund = { error = 1, fizzle = 1, refused = 1 },   -- erro, desistência e recusa não cobram
    maxReduction = 0.8,                                -- teto padrão do CooldownReduction
}
`),
});

DOCS.page({
  id: "enum.cadeia", parent: "enum", title: "MAX_RECURSION, ChainLimits e ChainOutcomes",
  kw: "max_recursion chainlimits deferatmaxdepth maxdeferrals deferredperframe maxliverunnersperroot chainoutcomes deferred maxrecursion error cadeia",
  html: C(`
Enum.MAX_RECURSION = 50
Enum.ChainLimits = {
    deferAtMaxDepth = true,       -- acima de MAX_RECURSION: adia (false = recusa)
    maxDeferrals = 20,            -- gerações de adiamento
    deferredPerFrame = 256,       -- orçamento da fila por frame
    maxLiveRunnersPerRoot = 256,  -- largura da cadeia assíncrona
}
Enum.ChainOutcomes = { Deferred = "Deferred", MaxRecursion = "MaxRecursion", Error = "Error" }
`) + "<p>Veja " + L("conceitos.cadeias") + ".</p>",
});

local Intents = require(game:GetService("ReplicatedStorage").Input.Intents)

local enum = {}

             --=====ENUM PRINCIPAL=====-

    --Categoria de status, runners que ficam armazenados rodando na própia entidade
enum.Categories = {
        Buff = "Buff",          --Buff
        Hybrid = "Hybrid",      --Status relacionado com buff e debuff
        Debuff = "Debuff",      --Debuff
        ActionState = "ActionState", --Trava de execução de ação (Self/Out/Locked)
        Internal = "Internal",  --Categoria interna pra impedir interações inesperadas
    }

    --Estados, status tratados de forma especial pelo sistema
enum.States = {
        Stun = "Stun",          --Perde todo e qualquer input
        NoControl = "NoControl",--Perde controle de input de movimentação
        Root = "Root",          --Imobiliza o personagem
        Silence = "Silence",    --Impede de usar skills
    }

    --Comportamentos especiais pra runners
enum.Traits = {

        --STATUS
        DOT = "DamageOverTime",         --Dot
        EffectShield = "EffectShield",  --Escudo de efeito (ignora pre entrada)
        Stackable = "stackable",        --Status pode stackar.
        Melee = "Melee",                --Dono único da trait usada por M1/Dash (era string solta em 2 arquivos)
        Ultimate = "Ultimate",          --Substitui o campo ad-hoc `Tags = {"Ultimate"}` de Ultimate.luau

        
        --BLOCKS
        Unbreakable = "Unbreakable",    --Block impossível de quebrar
        BlockBreak = "BlockBreak",      --Quebra o block do adversário
        TrueBlock = "TrueBlock",        --Block impossível de ignorar

        --INTERAÇÕES
        TrueHit = "TrueHit",            --Ignora iFrame
        TrueDamage = "TrueDamage",      --Ignora as proteções de stat (Defense, Armor: D11)
        Uninterruptible = "Uninterruptible", --A skill não é cancelada por estado com a tag interrupt
        SoftCancel = "LightCancel",     --Cancelamento fraco (TODO)
        HeavyCancel = "HeavyCancel",    --Cancelamento forte (TODO)
    }


        --====BREAKPOINTS=====--


        --Breakpoints unificados do ciclo de vida (Pub/Sub)
enum.Breakpoints = {
        OnHeal = "OnHeal",
        OnDamage = "OnDamage",   -- canal OUT (atacante), disparado depois do hit já ter acontecido
        PreDamage = "PreDamage", -- canal IN (alvo), ANTES do HP mudar — ponto de extensão pra cancelar/mutar
        PostDamage = "PostDamage", -- canal IN (alvo), DEPOIS do HP mudar — reação do lado de quem apanhou
        PreApplyStatus = "PreApplyStatus", -- canal OUT (dono do efeito), ANTES de um status entrar: checagem
                                           -- pré-output (F112). Pode cancelar e injetar context.inherited
        OnDeath = "OnDeath",
        OnRevive = "OnRevive",
        OnInterrupt = "OnInterrupt", -- canal IN: entrou um estado com a tag interrupt (o Combat cancela as skills)
        
        onStart = "onStart",
        onTrigger = "onTrigger",
        onRecast = "onRecast",
        onHit = "onHit",
        onRelease = "onRelease",
        onEnd = "onEnd",
        
        OnForceIncoming = "OnForceIncoming" -- Preparação futura
    }

enum.Roles = {
    IN = "IN",
    OUT = "OUT"
}

--Prioridade dos listeners internos do motor (ex.: a morte cancelando skills): rodam antes de
--qualquer listener de conteúdo inscrito no mesmo breakpoint
enum.EnginePriority = math.huge

--Motivo do fim de um runner, entregue em ctx.reason no onCancel/onEnd (e no OUT.onEnd)
enum.EndReasons = {
    Cancel = "cancel",      --Cancelado (Stop(true), remoção do status, morte)
    Duration = "duration",  --A duração acabou
    Stop = "stop",          --A própria skill se encerrou sem cancelar (Stop(false))
    Error = "error",        --Erro num callback (onStart/onStep): o motor encerrou o runner
    Fizzle = "fizzle",      --A skill desistiu do cast (self:Fizzle()): o cast não aconteceu
    Refused = "refused",    --O motor não deixou o runner começar (ChainLimits): nenhum callback rodou
    Interrupted = "interrupted", --Cancelada por um estado com a tag interrupt (Stun)
}

--==== EFEITOS ON-HIT (D6, F41) ====--
-- Quando os efeitos de um hit (context.effects) são aplicados. Padrão do motor declarado aqui; a
-- skill sobrescreve em data.effectPolicy = { onBlocked = ..., onZeroDamage = ... }, e cada efeito
-- pode sobrescrever se declarado como { status = X, onBlocked = ..., onZeroDamage = ... }.
enum.EffectDefaults = table.freeze({
    onBlocked = false,    --Hit zerado pelo bloqueio NÃO aplica os efeitos
    onZeroDamage = true,  --Hit de 0 de dano (slow puro, marca) aplica os efeitos
})

--==== CAMADAS DE LOADOUT (D5, F16) ====--
-- O loadout efetivo é a mesclagem das camadas, da Base para cima (a de cima vence no slot). O jogo
-- pode criar camadas próprias com qualquer nome; estas são as que o motor usa.
enum.LoadoutLayers = table.freeze({
    Base = "Base",              --Forma do personagem (SetCharMode) e EquipSkill sem camada
    WeaponMode = "WeaponMode",  --Modo da arma (WeaponTransform)
})

--==== COOLDOWN DE SKILL (D13; regras em ServerScriptService.Modules.CooldownPolicy) ====--
enum.CooldownStart = table.freeze({
    Cast = "Cast",          --Começa na ativação, antes do onStart
    End = "End",            --Começa no fim do runner
    Manual = "Manual",      --Começa quando a skill chama self:CommitCooldown()
})

enum.RecastPolicy = table.freeze({
    Blocked = "Blocked",    --Recast espera o cooldown e não o reinicia
    Restart = "Restart",    --Recast espera o cooldown e o reinicia
    Free = "Free",          --Recast ignora o cooldown e não o reinicia
    -- ou um número: intervalo próprio entre cast/recasts, em segundos
})

-- Padrões explícitos da política (a skill sobrescreve no data.cooldownPolicy)
enum.CooldownDefaults = table.freeze({
    start = "Cast",
    recastLegacy = "Restart",  --só para skill com onRecast que não declarou recast (com aviso)
    refund = table.freeze({ error = 1, fizzle = 1, refused = 1 }), --erro, desistência e recusa não cobram
    maxReduction = 0.8,        --teto PADRÃO da redução de cooldown (design de jogo: troque aqui ou
                               --por skill em cooldownPolicy.maxReduction, 0..1; 1 = sem teto)
})

--==== BLOQUEIO (D14) ====--
-- Quem tem a tag block declara o que faz: data.block = { mode = BlockModes.X, value = n? }.
-- Sem block e sem onTrigger, NÃO bloqueia (avisa uma vez). onTrigger, quando existe, decide.
enum.BlockModes = table.freeze({
    Full = "Full",          --Zera o dano; barra o status (escudo de status)
    Flat = "Flat",          --Tira `value` do dano (não barra status)
    Percent = "Percent",    --Tira a fração `value` (0..1) do dano (não barra status)
    Custom = "Custom",      --Decidido pelo onTrigger (obrigatório)
})




    --=====TAGS=====--


--tags são dados envolvendo comportamento da entidade.
enum.Tags = {
    canMove = "canMove",         --Pode se mover
    canCast = "canCast",         --Pode usar skills
    canRotate = "canRotate",     --Pode rotacionar o char
    canDisplace = "canDisplace", --Pode ser deslocado por forças externas
    interrupt = "interrupt",     --Ao entrar, cancela as skills ativas (menos as Uninterruptible)

    iFrame = "iFrame",
    block = "block",

    exclusive = "exclusive"
}


--fallback pra caso de não declaração dessas tags
enum.tagsBase = {
	canMove = true,
	canCast = true,
	canRotate = true,
    canDisplace = true,
	iFrame = false,
    block = false,
    interrupt = false,
	}


--====OUTROS====--

--Tipos de runner
enum.Types = {
    Skill = "Skill",
    State = "State",
    Status = "Status"
}


--Modificadores de atributos
enum.ModifierType = {
    Flat = "Flat",                      -- Soma flat
    AddPercent = "AddPercent",          -- Stack de somas percentuais (percent += 0.2,0.5)
    MultPercent = "MultPercent",        -- Multiplicação no final da fórmula (Total * 0.5)
    Override = "Override",              -- Substitui o valor por inteiro
}


--Tipos de atributos
enum.Stats = {
    Speed = "Speed",
    MaxHP = "MaxHP",
    JumpForce = "JumpForce",
    Defense = "Defense",
    DamageMult = "DamageMult",
    Weapon = "Weapon",
    GravityScale = "GravityScale",
    CooldownReduction = "CooldownReduction", --fração (0..1) tirada de toda contagem de cooldown que começa
    Armor = "Armor",                         --proteção subtrativa (dano − Armor), ver DamageMitigation
}

enum.StatDefaults = table.freeze({
    Speed = 16,
    JumpForce = 50,
    MaxHP = 100,
    Defense = 0,
    DamageMult = 1,
    GravityScale = 1,
    CooldownReduction = 0,
    Armor = 0,
})

-- Limites dos stats numéricos (F100), aplicados pelo AttributesComponent:GetStat ao valor final,
-- tenha ele modificador ou não. Stat sem declaração usa StatLimitDefault (não fica negativo).
-- Antes o piso 0 só valia quando havia modificador: Defense −50 na base amplificava o dano, a
-- mesma −50 vinda de um debuff era cortada para 0. Declare aqui o stat que pode ficar negativo.
enum.StatLimitDefault = table.freeze({ min = 0, max = math.huge })
enum.StatLimits = table.freeze({
    Defense = table.freeze({ min = -math.huge, max = math.huge }), --negativa amplifica (D1)
})

--==== FÓRMULA DE DANO (D11, F43) ====--
-- Proteções do ALVO aplicadas em ordem, cada uma ligada a um stat (o jogo troca, reordena ou
-- acrescenta). mode: Multiplicative = dano × 100 / (100 + stat) (stat negativo amplifica:
-- dano × (2 − 100 / (100 − stat))); Flat = dano − stat. ignoredBy = traits que furam a proteção.
-- O DamageMult do ATACANTE multiplica o dano antes (CombatComponent:ApplyDamage).
enum.MitigationModes = table.freeze({
    Multiplicative = "Multiplicative",
    Flat = "Flat",
})

enum.DamageMitigation = table.freeze({
    table.freeze({ stat = enum.Stats.Defense, mode = enum.MitigationModes.Multiplicative,
        ignoredBy = table.freeze({ enum.Traits.TrueDamage }) }),
    table.freeze({ stat = enum.Stats.Armor, mode = enum.MitigationModes.Flat,
        ignoredBy = table.freeze({ enum.Traits.TrueDamage }) }),
})

-- O que o MOTOR faz quando o HP zera. O resto (Humanoid, animação, respawn) é do jogo: o
-- framework não mata o Humanoid, de propósito. Override por entidade no config do componente
-- dono, com a mesma chave; cada componente resolve UMA vez no new() (StateTable.ResolveDeathPolicy),
-- então uma regra desligada custa zero.
enum.DeathDefaults = table.freeze({
    CancelSkillsOnDeath = true, -- CombatComponent: a morte cancela as skills ativas (F20)
    RefuseStatusOnDeath = true, -- StatusComponent: morto não recebe status novo (F39); data.allowOnDead fura por status
    RefuseCastOnDeath = true, -- CombatComponent: morto não inicia cast novo (F75)
})

--==== CURA (F107) ====--
-- HP acima do MaxHP é escolha de design (sobrevida): o motor não corta o HP. O Heal só não leva o
-- HP além de HealCap × MaxHP, e NUNCA reduz (antes, com o HP acima do teto, a cura o cortava).
-- Override por entidade (config do Health: HealCap) e por cura (Heal(n, { Cap = ... })).
-- math.huge = sem teto (toda cura vira sobrevida).
enum.HealthDefaults = table.freeze({
    HealCap = 1,
})

--==== ALVOS E AFILIAÇÃO (F105) ====--
-- Relação entre quem age e quem é atingido. Sem AffiliationComponent dos dois lados = Neutral.
enum.Relations = table.freeze({
    Self = "Self",          --a própria entidade
    Ally = "Ally",          --mesmo time
    Enemy = "Enemy",        --times diferentes
    Neutral = "Neutral",    --um dos dois sem time (dummy, ambiente)
})
-- Quem uma skill afeta por padrão, quando a acerta pela hitbox/zona (o mesmo de antes do F105:
-- todo mundo menos ela mesma). A skill sobrescreve em data.affects = { Ally = true, ... }.
-- Damage/ApplyStatus chamados direto pela skill NÃO passam por aqui: a skill decidiu o alvo.
enum.AffectsDefaults = table.freeze({
    Self = false,
    Ally = false,
    Enemy = true,
    Neutral = true,
})

--==== PERSONAGEM (F106) ====--
-- Personagem do CombatComponent quando o config não diz (dado do JOGO: troque aqui). O player
-- nasce sem config, então é este. ChosenChar = false no config = entidade sem personagem (kit
-- montado em runtime com EquipSkill/ApplyLoadout, sem aviso e sem loadout do banco).
enum.CombatDefaults = table.freeze({
    ChosenChar = "Schema",
    Mode = "Base",
})

-- Profundidade SÍNCRONA máxima de uma cadeia dano<->status na mesma pilha. Acima dela a ação NÃO
-- roda nesta pilha: vai para a fila de ChainLimits (ou é recusada, com deferAtMaxDepth = false).
-- Ver StateTable.RunInChain.
enum.MAX_RECURSION = 50

--==== LIMITES DE CADEIA (F62; dono: StateTable/Helper RunInChain e SkillRunner:start) ====--
-- SÍNCRONA (dano -> morte -> dano... na mesma pilha): passou de MAX_RECURSION, a ação vai para uma
-- fila e roda no próximo frame, numa pilha nova, em vez de ser descartada. Ação adiada que adia
-- outra soma uma geração; acima de maxDeferrals a ação é recusada (e avisa). É isso que para o
-- ping-pong infinito de dois reflexos, sem cortar a cadeia longa e finita (80 alvos em linha).
-- ASSÍNCRONA (runner que cria runner): o perigo é a LARGURA, não a profundidade. Uma cadeia linear
-- é um laço legítimo (status que se renova sozinho) e não tem limite; uma árvore que dobra a cada
-- geração tem: runners vivos ao mesmo tempo sob a mesma raiz da Lineage.
enum.ChainOutcomes = table.freeze({
    Deferred = "Deferred",          --a ação foi para a fila e roda no próximo frame (sem retorno)
    MaxRecursion = "MaxRecursion",  --a ação foi recusada (limite de gerações, ou sem fila)
    Error = "Error",                --a ação deu erro (warn com traceback)
})

enum.ChainLimits = table.freeze({
    deferAtMaxDepth = true,       --false = acima de MAX_RECURSION recusa na hora (o comportamento antigo)
    maxDeferrals = 20,            --gerações de adiamento por cadeia: 20 × 50 = ~1000 ações em linha
    deferredPerFrame = 256,       --orçamento da fila por frame; o que sobra espera o próximo
    maxLiveRunnersPerRoot = 256,  --runners vivos ao mesmo tempo sob a mesma raiz da Lineage
})


--Lista de traits que ignoram block
enum.BlockIgnore = {
    [enum.Traits.TrueHit] = enum.Traits.TrueHit,
}

--Lista de traits que podem quebrar o block
enum.BlockBreak = {
    [enum.Traits.BlockBreak] = enum.Traits.BlockBreak,
}

enum.Gestures = Intents.Gesture

return enum 


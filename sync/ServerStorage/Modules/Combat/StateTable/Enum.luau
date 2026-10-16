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
        OnDeath = "OnDeath",
        OnRevive = "OnRevive",
        
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
    Cancel = "cancel",      --Cancelado (Stop(true), remoção do status, morte) ou erro no onStart/onStep
    Duration = "duration",  --A duração acabou
    Stop = "stop",          --A própria skill se encerrou sem cancelar (Stop(false))
}




    --=====TAGS=====--


--tags são dados envolvendo comportamento da entidade.
enum.Tags = {
    canMove = "canMove",         --Pode se mover
    canCast = "canCast",         --Pode usar skills
    canRotate = "canRotate",     --Pode rotacionar o char
    canDisplace = "canDisplace", --Pode ser deslocado por forças externas

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
}

enum.StatDefaults = table.freeze({
    Speed = 16,
    JumpForce = 50,
    MaxHP = 100,
    Defense = 0,
    DamageMult = 1,
    GravityScale = 1,
})

-- O que o MOTOR faz quando o HP zera. O resto (Humanoid, animação, respawn) é do jogo: o
-- framework não mata o Humanoid, de propósito. Override por entidade no config do componente
-- dono, com a mesma chave; cada componente resolve UMA vez no new() (StateTable.ResolveDeathPolicy),
-- então uma regra desligada custa zero.
enum.DeathDefaults = table.freeze({
    CancelSkillsOnDeath = true, -- CombatComponent: a morte cancela as skills ativas (F20)
    RefuseStatusOnDeath = true, -- StatusComponent: morto não recebe status novo (F39); data.allowOnDead fura por status
})

-- Limite de profundidade SÍNCRONA de uma cadeia dano<->status (TakeDamage/ApplyStatus se
-- recusam a continuar acima disso). Ver StateTable.RunInChain.
enum.MAX_RECURSION = 50


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


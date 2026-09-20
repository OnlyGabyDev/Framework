local Intents = require(game:GetService("ReplicatedStorage").Input.Intents)

enum = {}

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
        noControl = "noControl",--Perde controle de input de movimentação
        Root = "Root",          --Imobiliza o personagem
        Silence = "Silence",    --Impede de usar skills
    }

    --Comportamentos especiais pra runners
enum.Traits = {

        --STATUS
        DOT = "DamageOverTime",         --Dot
        EffectShield = "EffectShield",  --Escudo de efeito (ignora pre entrada)
        Stackable = "stackable",        --Status pode stackar.

        
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


        --Breakpoints do healthComponent (interações internas na entidade)
enum.reactTags = {
	    onHeal = "OnHeal",              --Ativa o status quando o alvo recebe cura
	    onDamage = "OnDamage",          --Ativa o status quando o alvo recebe dano
	    onDeath = "OnDeath",            --Ativa o status quando o alvo morre
    }


    --Breakpoints de runners
enum.SkillBreakpoints = {
        onTrigger = "onTrigger",
        onRecast = "onRecast",
		onHit = "onHit",
		onRelease = "onRelease",
        onEnd = "onEnd"
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
}

enum.MAX_RECURSION = 50 -- limite de ações recursivas de uma chain em um segundo


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


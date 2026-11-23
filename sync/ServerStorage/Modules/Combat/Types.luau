--!strict

export type TraitQuery = {
	All: {string}?,
	Any: {string}?,
	None: {string}?
}

export type ActionRef = any

export type SubscriptionLimit = {
	Max: number,
	Scope: "Holder" | "Branch" | "Tree",
	OnExhaust: "Disable" | "Remove"
}

-- Inscrição no TriggerSet (Entity:Listen / runner:Listen / EntityCore.ListenWorld).
export type Subscription = {
	Role: "IN" | "OUT",              -- StateTable.Enum.Roles
	Breakpoint: string,              -- StateTable.Enum.Breakpoints
	Query: TraitQuery?,
	Priority: number?,               -- maior roda antes; empate = ordem de inscrição
	Owner: any?,                     -- UnsubscribeByOwner; use StateTable.OwnerToken(entidade, tag), não string
	Action: ActionRef | (...any) -> any,
	Limit: SubscriptionLimit?,
	Inherit: { Generations: number }?,
	TTD: number?,                    -- segundos até expirar
}

export type Lineage = {
	Parent: Lineage?,
	Root: Lineage,
	Depth: number,
	Origin: any,
	Cause: string,
	LiveRunners: number?,            -- só na raiz: runners vivos sob ela (SkillRunner:start)
	Runner: any?,                    -- o runner dono do elo (nil no elo de um hit): Context.sourceRunner
}

--[[
Dois contextos:
- RunnerContext: o do ciclo de vida, que os callbacks da skill recebem (onStart, onStep, onRecast,
  onRelease, onEnd...). Montado por SkillRunner:BuildContext.
- HitContext: o da ação ofensiva (dano/status), que passa por ValidateHit, ApplyMitigation,
  proteções de stat, PreDamage/PostDamage e os listeners de onHit. Montado por
  StateTable.BuildContext (Helper.BuildContext).
]]
-- Context por Breakpoint (design em .agents/rules/01)
export type RunnerContext = {
	depth: number,                   -- profundidade na Lineage (cast por input = 1)
	history: {string},               -- trilha de nomes, raiz -> ... -> este runner (só leitura)
	rootOrigin: any,                 -- entidade que iniciou a cadeia
	sourceRunner: any?,              -- o runner IMEDIATAMENTE anterior: nos callbacks do runner, quem o
	                                 -- aplicou/criou (nil na raiz, cast por input); no evento que o runner
	                                 -- emite (OUT.onStart/onEnd), o próprio runner (o anterior de quem escuta)
	input: any?,                     -- Intents.InputEvent que originou o cast
	inherited: {[string]: any},      -- payload explícito do pai, decidido no ponto de injeção (só leitura):
	                                 -- ApplyStatus(..., { Inherited }), Damage(..., { Inherited }),
	                                 -- SkillRunner.new(..., inherited). Nada herda sozinho
	reason: string?,                 -- só no onCancel/onEnd/OUT.onEnd: StateTable.Enum.EndReasons
}

export type HitContext = {
	damage: number,                  -- mutável: mitigação, proteções e listeners alteram
	source: any?,                    -- o SkillRunner (ou status) que causou
	sourceEntity: any?,              -- onde o runner de origem roda (num DOT/reflexo, o portador)
	ownerEntity: any?,               -- DONO do efeito (StateTable.EffectOwner): recebe o OUT.OnDamage/OnDeath
	targetEntity: any?,
	type: string?,                   -- tipo do runner de origem (StateTable.Enum.Types)
	secondaryType: string?,
	traits: {string},
	effects: {any},                  -- status, ou { status, onBlocked?, onZeroDamage? }
	direction: {
		Id: any?,
		World: Vector3?,
		Local: Vector3?,
		Magnitude: number?
	}?,
	incomingStatus: any?,            -- o status entrando: no escudo de status (_TriggerShield) e no
	                                 -- OUT.PreApplyStatus
	inherited: {[string]: any},      -- payload para o que este hit/aplicação gerar: mutável aqui,
	                                 -- os listeners da checagem pré-output (OUT.onHit, OUT.PreApplyStatus)
	                                 -- injetam; o status on-hit recebe como ctx.inherited
	blocked: boolean?,               -- o bloqueio zerou um hit que tinha dano
	actualDamage: number?,           -- depois do HP mudar (PostDamage)
	actualHeal: number?,             -- só no OnHeal (IN e OUT): quanto o HP subiu de fato
	hit: {                           -- ponto do impacto, quando o hit veio de hitbox (opts.Hit)
		instance: Instance?,
		position: Vector3?,
		normal: Vector3?,
	}?,
	cancelled: boolean,              -- listener de PreDamage pode cancelar
	reason: string?,                 -- motivo do cancelamento
}

-- Opções de um hit: runner:Damage(alvo, n, opts) / ApplyDamage(n, source, alvo, opts)
export type DamageOptions = {
	Traits: {string}?,               -- traits só deste hit (somadas às da skill, sem repetir)
	Effects: {any}?,                 -- efeitos on-hit só deste hit (mesmo formato de data.effects)
	Hit: any?,                       -- o hitResult da hitbox (position, normal, instance) -> context.hit
	Prescaled: boolean?,             -- o dano já vem escalado: não aplica o DamageMult do atacante
	Inherited: {[string]: any}?,     -- payload para os status on-hit deste hit (context.inherited)
}

-- Opções de uma cura: entity.Heal(n, opts)
export type HealOptions = {
	Source: any?,                    -- runner de quem curou: recebe o OUT.OnHeal (context.ownerEntity)
	Traits: {string}?,
	Cap: number?,                    -- teto desta cura em × MaxHP (padrão: HealCap da entidade)
}

-- Nome antigo, mantido para quem já anotava com ele
export type Context = RunnerContext & HitContext

return {}

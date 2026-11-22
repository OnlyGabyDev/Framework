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

-- Inscrição no TriggerSet (Entity:Listen / runner:Listen). Dono do formato (regra 17, F68).
export type Subscription = {
	Role: "IN" | "OUT",              -- StateTable.Enum.Roles (antes o tipo dizia Target/Source)
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
	LiveRunners: number?,            -- só na raiz: runners vivos sob ela (SkillRunner:start, F62)
}

--[[
Dois contextos diferentes (F68: antes um tipo só misturava os dois e não batia com nenhum):
- RunnerContext: o do ciclo de vida, que os callbacks da skill recebem (onStart, onStep, onRecast,
  onRelease, onEnd...). Montado por SkillRunner:BuildContext.
- HitContext: o da ação ofensiva (dano/status), que passa por ValidateHit, ApplyMitigation,
  proteções de stat, PreDamage/PostDamage e os listeners de onHit. Montado por
  StateTable.BuildContext (Helper.BuildContext).
]]
export type RunnerContext = {
	depth: number,                   -- profundidade na Lineage (cast por input = 1)
	history: {string},               -- mantido por compatibilidade
	rootOrigin: any,                 -- entidade que iniciou a cadeia
	sourceRunner: any,               -- o SkillRunner
	input: any?,                     -- Intents.InputEvent que originou o cast
	inherited: {[string]: any},
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
	effects: {any},                  -- status, ou { status, onBlocked?, onZeroDamage? } (D6)
	direction: {
		Id: any?,
		World: Vector3?,
		Local: Vector3?,
		Magnitude: number?
	}?,
	incomingStatus: any?,            -- só no escudo de status (_TriggerShield)
	blocked: boolean?,               -- o bloqueio zerou um hit que tinha dano (D6)
	actualDamage: number?,           -- depois do HP mudar (PostDamage)
	actualHeal: number?,             -- só no OnHeal (IN e OUT): quanto o HP subiu de fato
	hit: {                           -- ponto do impacto, quando o hit veio de hitbox (opts.Hit, F108)
		instance: Instance?,
		position: Vector3?,
		normal: Vector3?,
	}?,
	cancelled: boolean,              -- listener de PreDamage pode cancelar
	reason: string?,                 -- motivo do cancelamento
}

-- Opções de um hit: runner:Damage(alvo, n, opts) / ApplyDamage(n, source, alvo, opts) (F108)
export type DamageOptions = {
	Traits: {string}?,               -- traits só deste hit (somadas às da skill, sem repetir)
	Effects: {any}?,                 -- efeitos on-hit só deste hit (mesmo formato de data.effects)
	Hit: any?,                       -- o hitResult da hitbox (position, normal, instance) -> context.hit
	Prescaled: boolean?,             -- o dano já vem escalado: não aplica o DamageMult do atacante
}

-- Opções de uma cura: entity.Heal(n, opts) (F107)
export type HealOptions = {
	Source: any?,                    -- runner de quem curou: recebe o OUT.OnHeal (context.ownerEntity)
	Traits: {string}?,
	Cap: number?,                    -- teto desta cura em × MaxHP (padrão: HealCap da entidade)
}

-- Nome antigo, mantido para quem já anotava com ele
export type Context = RunnerContext & HitContext

return {}

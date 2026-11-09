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
	Cause: string
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
	sourceEntity: any?,
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
	cancelled: boolean,              -- listener de PreDamage pode cancelar
	reason: string?,                 -- motivo do cancelamento
}

-- Nome antigo, mantido para quem já anotava com ele
export type Context = RunnerContext & HitContext

return {}

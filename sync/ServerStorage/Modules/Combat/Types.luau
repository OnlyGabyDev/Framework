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

export type Subscription = {
	ID: string,
	Role: "Target" | "Source",
	Breakpoint: string,
	Query: TraitQuery?,
	Priority: number?,
	Owner: any?,
	Action: ActionRef | (...any) -> any,
	Limit: SubscriptionLimit?,
	Inherit: { Generations: number }?
}

export type Lineage = {
	Parent: Lineage?,
	Root: Lineage,
	Depth: number,
	Origin: any,
	Cause: string
}

export type Context = {
	depth: number,
	history: {string},
	rootOrigin: any,
	sourceRunner: any?,
	inherited: {[string]: any},
	traits: {string}?,
	damage: number?,
	effects: {any}?,
	source: any?,
	direction: {
		Id: any?,
		World: Vector3?,
		Local: Vector3?,
		Magnitude: number?
	}?,
	input: {
		Modifiers: {[string]: boolean}?
	}?
}

return {}

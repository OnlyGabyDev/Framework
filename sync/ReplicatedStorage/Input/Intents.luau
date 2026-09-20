--[[
	Intents — dicionário de intenções pra input
	
	aqui, trabalhamos com o que o jogador quer fazer, sua intenção, que é o que o sistema interno utiliza, inputs ficam na camada externa/client.

	Eixos contínuos (Move, Look) NÃO são Intents: carregam Vector3 e não têm
	Press/Release, então têm remotes próprios (RequestDir, RequestLook).

	CRIAR UMA INTENT: adicione em Id, (se for slot de skill) em SkillOrder e dê
	um binding em Config/InputConfig
]]

export type Kind = "Activate" | "Release"
export type Gesture = "Press" | "Tap" | "DoubleTap" | "Hold"

--[[ O que a skill declara em data.input, se não declarado ativa insta ]]
export type GestureSpec = {
	Hold: (boolean | number)?, -- true = Defaults.HoldTime | number = segundos
	DoubleTap: (boolean | number)?, -- true = Defaults.DoubleTapWindow | number = segundos
	Tap: boolean?, -- default true: toque simples também ativa
}

--[[ ÚNICO formato que trafega do resolver até a skill. Imutável. ]]
export type InputEvent = {
	Intent: string,
	Kind: Kind,
	Gesture: Gesture?, -- só em Activate
	HeldTime: number?, -- Release e Activate(Tap/Hold): segundos pressionado
}

local Intents = {}

Intents.Id = table.freeze({
	Primary = "Primary", 
	Dash = "Dash",
	Ability1 = "Ability1",
	Ability2 = "Ability2",
	Ability3 = "Ability3",
	Ultimate = "Ultimate",
})

Intents.Kind = table.freeze({
	Activate = "Activate",
	Release = "Release",
})

Intents.Gesture = table.freeze({
	Press = "Press", 
	Tap = "Tap",
	DoubleTap = "DoubleTap",
	Hold = "Hold",
})

Intents.Defaults = table.freeze({
	HoldTime = 0.3, -- segundos apertado para virar Hold
	DoubleTapWindow = 0.25, -- janela para o 2º toque
	TapMaxTime = 0.35, -- toque mais longo que isso não arma DoubleTap
})

-- Ordem dos slots para loadouts em modo List (CombatComponent:AddSkill)
Intents.SkillOrder = table.freeze({
	Intents.Id.Primary,
	Intents.Id.Dash,
	Intents.Id.Ability1,
	Intents.Id.Ability2,
	Intents.Id.Ability3,
	Intents.Id.Ultimate,
})

local validIds = {}
for _, id in Intents.Id do
	validIds[id] = true
end
table.freeze(validIds)

--[[
Valida uma intent vinda da rede ou de config. Aceita qualquer tipo.
@return BOOLEAN
]]
function Intents.IsButton(id: any): boolean
	return validIds[id] == true
end

--[[
ÚNICO construtor de InputEvent (resolver pra permitir NPCs funcionando sem input fisico.)
IA/NPC: SkillHandler.HandleIntent(ID, Intents.NewEvent(Id.Primary, Kind.Activate, Gesture.Press))
]]
function Intents.NewEvent(intent: string, kind: Kind, gesture: Gesture?, heldTime: number?): InputEvent
	return table.freeze({
		Intent = intent,
		Kind = kind,
		Gesture = gesture,
		HeldTime = heldTime,
	})
end

return table.freeze(Intents)

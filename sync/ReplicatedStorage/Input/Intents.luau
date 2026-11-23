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

--[[ Alvo do input, opcional: o que o player apontou ao apertar/soltar ]]
export type InputPayload = {
	Target: string?, -- ID de uma entidade (atributo EntityID do model)
	Point: Vector3?, -- ponto no mundo (mira no chão, posição de colocação)
}

--[[ ÚNICO formato que trafega do resolver até a skill. Imutável. ]]
export type InputEvent = {
	Intent: string,
	Kind: Kind,
	Gesture: Gesture?, -- só em Activate
	HeldTime: number?, -- Release e Activate(Tap/Hold): segundos pressionado
	Target: string?, -- InputPayload.Target (o servidor confere que a entidade existe)
	Point: Vector3?, -- InputPayload.Point
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
@param payload - InputPayload? (alvo/ponto); já validado por SanitizePayload
]]
function Intents.NewEvent(intent: string, kind: Kind, gesture: Gesture?, heldTime: number?, payload: InputPayload?): InputEvent
	return table.freeze({
		Intent = intent,
		Kind = kind,
		Gesture = gesture,
		HeldTime = heldTime,
		Target = payload and payload.Target,
		Point = payload and payload.Point,
	})
end

local MAX_TARGET_LENGTH = 64
local MAX_COORDINATE = 1e6

--[[
Valida um payload vindo da rede: só os campos de tipo certo passam (Target string curta, Point
Vector3 finito). Qualquer outra coisa vira nil. Se o alvo existe e está ao alcance é com quem usa.
@return InputPayload ou nil
]]
function Intents.SanitizePayload(raw: any): InputPayload?
	if type(raw) ~= "table" then
		return nil
	end
	local target = raw.Target
	if type(target) ~= "string" or #target == 0 or #target > MAX_TARGET_LENGTH then
		target = nil
	end
	local point = raw.Point
	if typeof(point) ~= "Vector3" or point ~= point
		or math.abs(point.X) > MAX_COORDINATE or math.abs(point.Y) > MAX_COORDINATE or math.abs(point.Z) > MAX_COORDINATE then
		point = nil
	end
	if target == nil and point == nil then
		return nil
	end
	return { Target = target, Point = point }
end

return table.freeze(Intents)

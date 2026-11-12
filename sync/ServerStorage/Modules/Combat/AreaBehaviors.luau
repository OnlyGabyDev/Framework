local AreaBehaviors = {}

-- Key da força de zona: dona única do formato, usada para aplicar (AddForce renova pela Key) e
-- para remover na saída. Type + zona quando opts.Area vem; sem a zona, uma por entidade e Type.
-- opts.Key sobrescreve as duas.
local function forceKey(forceType: string, opts): string
	return opts.Key or ("Area:" .. forceType .. ":" .. (opts.Area and opts.Area.ID or "Any"))
end

local function hasMovement(entity): boolean
	-- O stub do componente ausente também é função: o guarda olha o componente
	return entity:HasComponent(entity.ComponentKey.Movement)
end

-- Empurra/puxa quem está na zona, na direção fornecida (função ou fixa) —
-- mesmo contrato de Behaviors.LinearMove: aceita função pra permitir origem
-- que se move/gira.
-- A Force tem Key (F29): cada chamada RENOVA a mesma força em vez de empilhar outra.
-- Força de ambiente é externa: por padrão empurra mesmo quem não pode se mover (Root/Stun),
-- como a doc do MovementComponent pede para vento e knockback (F30). RequiresControl = true
-- é opt-in.
-- Chamada solta (sem BindDirectionalForce), a força só acaba pelo Duration: quem sai da zona
-- segue sendo empurrado até 0,5 s. Para zona, use BindDirectionalForce.
-- opts = { Area: AreaEffect?, Key: string?, Duration: number?, Hard: boolean?, RequiresControl: boolean?, MaxForce: number? }
function AreaBehaviors.DirectionalForce(entity, direction, speed, forceType, opts)
	opts = opts or {}
	forceType = forceType or "AreaWind"

	if not hasMovement(entity) then
		return nil
	end

	return entity.AddForce({
		Type = forceType,
		Key = forceKey(forceType, opts),
		Duration = opts.Duration or 0.5, -- renovado a cada poll; na zona ligada, a saída encerra antes
		Speed = speed,
		Direction = direction, -- função () -> Vector3, reavaliada pelo MovementController
		Hard = opts.Hard or false,
		RequiresControl = opts.RequiresControl == true,
		MaxForce = opts.MaxForce,
	})
end

--[[
Liga uma DirectionalForce a uma zona: vale do primeiro poll em que a entidade está dentro
(OnEnter) até o poll em que ela sai (OnExit, inclusive o do zone:Stop). Antes a zona só aplicava
no OnStay: o 1º poll dentro não empurrava, e a força sobrevivia à saída pelo resto do Duration
(até 0,5 s, ~12 studs além da borda a 30 studs/s). Com um dash Hard no meio, o vento ficava
contido até o fim do dash e o resto saía de uma vez, já fora da zona.
@param zone AreaEffect
@param direction Vector3 | () -> Vector3
@param opts os mesmos do DirectionalForce; Area é sempre a zona
@return zone (encadeável)
]]
function AreaBehaviors.BindDirectionalForce(zone, direction, speed, forceType, opts)
	forceType = forceType or "AreaWind"
	local bound = table.clone(opts or {})
	bound.Area = zone
	local key = forceKey(forceType, bound)

	local function apply(entity)
		AreaBehaviors.DirectionalForce(entity, direction, speed, forceType, bound)
	end
	zone:OnEnter(apply)
	zone:OnStay(apply)
	zone:OnExit(function(entity)
		if entity.Active ~= false and hasMovement(entity) then
			entity.RemoveForceByKey(key)
		end
	end)
	return zone
end

return AreaBehaviors

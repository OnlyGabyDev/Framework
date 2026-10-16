local AreaBehaviors = {}

-- Empurra/puxa quem está na zona, na direção fornecida (função ou fixa) —
-- mesmo contrato de Behaviors.LinearMove: aceita função pra permitir origem
-- que se move/gira.
-- A Force tem Key (F29): cada OnStay RENOVA a mesma força em vez de empilhar outra. A Key é
-- Type + zona quando opts.Area vem (2º argumento dos callbacks do AreaEffect); sem a zona, é
-- uma força por entidade e Type. opts.Key sobrescreve as duas.
-- opts = { Area: AreaEffect?, Key: string?, Duration: number?, Hard: boolean?, RequiresControl: boolean?, MaxForce: number? }
function AreaBehaviors.DirectionalForce(entity, direction, speed, forceType, opts)
    opts = opts or {}
    forceType = forceType or "AreaWind"

    if type(entity.AddForce) ~= "function" then
        warn("[AreaBehaviors] Entidade não possui método AddForce")
        return nil
    end

    return entity.AddForce({
        Type = forceType,
        Key = opts.Key or ("Area:" .. forceType .. ":" .. (opts.Area and opts.Area.ID or "Any")),
        Duration = opts.Duration or 0.5, -- curto, renovado a cada OnStay
        Speed = speed,
        Direction = direction, -- função () -> Vector3, reavaliada pelo MovementController
        Hard = opts.Hard or false,
        RequiresControl = opts.RequiresControl ~= false,
        MaxForce = opts.MaxForce,
    })
end

return AreaBehaviors

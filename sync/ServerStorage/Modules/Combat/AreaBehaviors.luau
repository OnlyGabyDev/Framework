local AreaBehaviors = {}

-- Empurra/puxa quem está na zona, na direção fornecida (função ou fixa) —
-- mesmo contrato de Behaviors.LinearMove: aceita função pra permitir origem
-- que se move/gira.
function AreaBehaviors.DirectionalForce(entity, direction, speed, forceType, opts)
    opts = opts or {}
    
    if type(entity.AddForce) ~= "function" then
        warn("[AreaBehaviors] Entidade não possui método AddForce")
        return nil
    end

    return entity.AddForce({
        Type = forceType or "AreaWind",
        Duration = opts.Duration or 0.5, -- curto, reaplicado a cada OnStay
        Speed = speed,
        Direction = direction, -- função () -> Vector3, reavaliada pelo MovementController
        Hard = opts.Hard or false,
        RequiresControl = opts.RequiresControl ~= false,
        MaxForce = opts.MaxForce,
    })
end

return AreaBehaviors

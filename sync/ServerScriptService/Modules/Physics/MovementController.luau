local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local MovementController = {}
local trackedEntitys = {}

function MovementController.Register(entity)
    trackedEntitys[entity] = true
end

function MovementController.Unregister(entity)
    trackedEntitys[entity] = nil
end

function MovementController.ProcessEntity(comp, dt)
    local wrapper = comp:GetMovementWrapper()
    local entity = comp.Entity
    
    if not wrapper or not entity then return end

    -- Congelamento total
    if entity.IsFrozen then
        wrapper:SetFrozen(true)
        return
    else
        wrapper:SetFrozen(false)
    end

    -- Busca tags relacionadas a movimentação
    local tags = { canMove = true, canDisplace = true }
    if entity.HasComponent(entity.ComponentKey.Status) then
        local activeTags = entity.GetActiveTags()
        if activeTags[StateTable.Enum.Tags.canMove] ~= nil then
            tags.canMove = activeTags[StateTable.Enum.Tags.canMove]
        end
        if activeTags[StateTable.Enum.Tags.canDisplace] ~= nil then
            tags.canDisplace = activeTags[StateTable.Enum.Tags.canDisplace]
        end
    end

    -- ============================================================
    -- 3. MOVIMENTO + STATS SYSTEM
    -- ============================================================
    
    -- Busca os Stats calculados do frame atual
    local currentSpeed = entity:GetStat(StateTable.Enum.Stats.Speed, 16)
    local currentJump = entity:GetStat(StateTable.Enum.Stats.JumpForce, 50)

    -- Aplica os valores físicos no Wrapper
    wrapper:SetSpeed(currentSpeed)
    wrapper:SetJumpForce(currentJump)

    -- Executa Movimento se permitido
    if tags.canMove then
        wrapper:Move(entity:GetDirection())
    else
        wrapper:Move(Vector3.zero) 
    end

    -- ============================================================
    -- 4. FORÇAS FÍSICAS (DASH / KNOCKBACK)
    -- ============================================================
    
    local totalVelocity = Vector3.zero
    local hasActiveForce = false
    local gravityOverride = nil 

    if tags.canDisplace then
        for id, forceEntry in pairs(entity.ActiveForces) do
            
            -- Cancelamento de Dash por Root (se for skill de movimento)
            if not tags.canMove and forceEntry.Type == "Dash" then
                entity:RemoveForce(id)
                continue
            end

            hasActiveForce = true
            forceEntry.ElapsedTime += dt
            local data = forceEntry.Data
            local duration = data.Duration or 0.5

            if forceEntry.ElapsedTime >= duration then
                entity:RemoveForce(id)
                continue
            end

            -- Velocidade da força
            local speed = 0
            if type(data.Speed) == "function" then
                speed = data.Speed(forceEntry.ElapsedTime, duration)
            else
                speed = data.Speed
            end

            -- Gravidade da força
            if data.GravityScale ~= nil then
                local gScale = (type(data.GravityScale) == "function") 
                    and data.GravityScale(forceEntry.ElapsedTime, duration) 
                    or data.GravityScale
                
                if gravityOverride == nil or gScale < gravityOverride then
                    gravityOverride = gScale
                end
            end

            totalVelocity += (data.Direction * speed)
        end
    else
        -- Se não pode ser deslocado (Unstoppable), limpa forças
        if next(entity.ActiveForces) then entity:ClearForces() end
    end

    -- 5. APLICAÇÃO FINAL
    if hasActiveForce then
        wrapper:ApplyVelocity(totalVelocity)
        if gravityOverride ~= nil then
            wrapper:SetGravityScale(gravityOverride)
        else
            wrapper:SetGravityScale(1)
        end
    else
        wrapper:SetGravityScale(1)
    end
end


RunService.Heartbeat:Connect(function(dt)
    for entity, _ in pairs(trackedEntitys) do
        MovementController.ProcessEntity(entity, dt)
    end
end)

return MovementController
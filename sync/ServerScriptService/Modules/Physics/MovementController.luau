local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local MovementController = {}
local trackedEntitys = {}

function MovementController.Register(comp)
    if comp and comp.Entity then
        trackedEntitys[comp.Entity] = comp
    end
end

function MovementController.Unregister(comp)
    if comp and comp.Entity then
        trackedEntitys[comp.Entity] = nil
    end
end

function MovementController.ProcessEntity(comp, dt)
    local wrapper = comp.MovementWrapper
    local entity = comp.Entity
    
    if not wrapper or not entity then return end

    if comp.IsFrozen then
        wrapper:SetFrozen(true)
        return
    else
        wrapper:SetFrozen(false)
    end

    -- Dependência Opcional Explícita: StatusComponent (Regra 16)
    local tags = { canMove = true, canDisplace = true }
    if entity:HasComponent(entity.ComponentKey.Status) then
        local activeTags = entity.GetActiveTags()
        if activeTags[StateTable.Enum.Tags.canMove] ~= nil then
            tags.canMove = activeTags[StateTable.Enum.Tags.canMove]
        end
        if activeTags[StateTable.Enum.Tags.canDisplace] ~= nil then
            tags.canDisplace = activeTags[StateTable.Enum.Tags.canDisplace]
        end
    end

    -- Atualiza Speed e Jump
    local currentSpeed = comp:GetSpeed()
    local currentJump = comp:GetJumpForce()

    wrapper:SetSpeed(currentSpeed)
    wrapper:SetJumpForce(currentJump)

    -- Direção Intencional (Não interfere se a intenção for 0 para não dessincronizar o client local)
    if comp.Direction ~= Vector3.zero then
        if tags.canMove then
            wrapper:Move(comp.Direction)
        else
            wrapper:Move(Vector3.zero) 
        end
    end

    -- Processamento de Forças Externas
    local totalVelocity = Vector3.zero
    local hasActiveForce = false
    local gravityOverride = nil 
    local highestPriority = -1
    local hasHardForce = false

    if tags.canDisplace then
        for forceId, forceEntry in pairs(comp.ActiveForces) do
            local data = forceEntry.Data
            
            -- Cancelamento de Dash "Mole" se rootado (canMove == false)
            if not tags.canMove and forceEntry.Type == "Dash" and not data.Hard then
                comp:RemoveForce(forceId)
                continue
            end

            forceEntry.ElapsedTime += dt
            local duration = data.Duration or 0.5

            if forceEntry.ElapsedTime >= duration then
                comp:RemoveForce(forceId)
                continue
            end

            hasActiveForce = true
            
            local speed = 0
            if type(data.Speed) == "function" then
                speed = data.Speed(forceEntry.ElapsedTime, duration)
            else
                speed = data.Speed or 0
            end

            -- Resolução de Gravidade
            if data.IgnoreGravity then
                gravityOverride = 0
            elseif data.GravityScale ~= nil then
                local gScale = (type(data.GravityScale) == "function") 
                    and data.GravityScale(forceEntry.ElapsedTime, duration) 
                    or data.GravityScale
                
                if gravityOverride == nil or gScale < gravityOverride then
                    gravityOverride = gScale
                end
            end

            -- Resolução de Velocidade (Hard vs Soft)
            local priority = data.Priority or 0
            if data.Hard then
                if priority >= highestPriority then
                    highestPriority = priority
                    hasHardForce = true
                    -- Forças "Duras" sobrescrevem vetores menores
                    totalVelocity = (data.Direction * speed)
                end
            else
                if not hasHardForce then
                    totalVelocity += (data.Direction * speed)
                end
            end
        end
    else
        -- Se Unstoppable/Rooted absoluto, limpa forças "moles"
        for forceId, forceEntry in pairs(comp.ActiveForces) do
            if not forceEntry.Data.Unstoppable then
                comp:RemoveForce(forceId)
            end
        end
    end

    -- Aplicação final no Wrapper
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
    
    -- TODO: Anti-Cheat & Sync log logic (posições antigas, validações)
end

RunService.Heartbeat:Connect(function(dt)
    for entity, comp in pairs(trackedEntitys) do
        MovementController.ProcessEntity(comp, dt)
    end
end)

return MovementController
local MovementComponent = {}
MovementComponent.__index = MovementComponent

local ServerScript = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local MovementController = require(ServerScript.Modules.Physics.MovementController) 

function MovementComponent.new(entity, config)
    local self = setmetatable({}, MovementComponent)
    self.Entity = entity

    -- Intenção de Input
    self.Direction = Vector3.zero
    self.IsFrozen = false

    -- Forças externas e Filtros
    self.ActiveForces = {} 
    self.Filters = {} -- Filtros de interação/força
    self.ForceCounter = 0

    self.MovementWrapper = nil
    return self
end

function MovementComponent:SetSpeed(value)
    if self.MovementWrapper then
        self.MovementWrapper:SetSpeed(value)
    end
end

function MovementComponent:SetJumpForce(value)
    if self.MovementWrapper then
        self.MovementWrapper:SetJumpForce(value)
    end
end

function MovementComponent:GetSpeed()
    return self.Entity.GetStat(StateTable.Enum.Stats.Speed, 16)
end

function MovementComponent:GetJumpForce()
    return self.Entity.GetStat(StateTable.Enum.Stats.JumpForce, 50)
end

function MovementComponent:SetMovement()
    if self.MovementWrapper then return false end 
    
    local EntityWrapper = require(ServerScript.EntityData.EntityWrapper)
    local wrapper = self.Entity.GetCharacterWrapper()
    
    -- Criamos o wrapper de movimentação.
    self.MovementWrapper = EntityWrapper.CreateMovement(wrapper)

    -- Regra 16: Dependência Opcional Explícita
    if not self.Entity:HasComponent(self.Entity.ComponentKey.Status) then
        warn("[MovementComponent] Entidade sem StatusComponent. Tags como canMove/canDisplace serão ignoradas.")
    end

    MovementController.Register(self)
    return true
end

--CleanUp
function MovementComponent:Destroy()
    MovementController.Unregister(self)
    self.MovementWrapper = nil
    self.Entity = nil
    table.clear(self.ActiveForces)
    table.clear(self.Filters)
end

-- ==========================================
-- FILTROS ORGÂNICOS
-- ==========================================
function MovementComponent:AddFilter(id, filterFunc)
    self.Filters[id] = filterFunc
end

function MovementComponent:RemoveFilter(id)
    self.Filters[id] = nil
end

-- ==========================================
-- APLICAÇÃO DE FORÇAS
-- ==========================================
function MovementComponent:AddForce(forceData)
    -- Aplica os filtros orgânicos (Rejeita se algum retornar false)
    for filterId, filterFunc in pairs(self.Filters) do
        if filterFunc(forceData) == false then
            return nil
        end
    end

    self.ForceCounter += 1
    local forceId = "F_" .. tostring(self.ForceCounter)
    self.ActiveForces[forceId] = { ID = forceId, Data = forceData, ElapsedTime = 0, Type = forceData.Type or "UnnamedForce" }
    return forceId
end

function MovementComponent:RemoveForce(forceId)
    local entry = self.ActiveForces[forceId]
    if entry then
        if entry.Data.OnEnd then task.spawn(entry.Data.OnEnd) end
        self.ActiveForces[forceId] = nil
    end
end

function MovementComponent:ClearForces()
    for forceId, _ in pairs(self.ActiveForces) do
        self:RemoveForce(forceId)
    end
end

local ExposeAPI = {
    SetDirection = function(Component, dir) Component.Direction = dir end,
    GetDirection = function(Component) return Component.Direction end,
    AddForce = function(Component, ...) return Component:AddForce(...) end,
    RemoveForce = function(Component, ...) return Component:RemoveForce(...) end,
    ClearForces = function(Component) return Component:ClearForces() end,
    SetFrozen = function(Component, f) Component.IsFrozen = f end,
    SetMovement = function(Component) return Component:SetMovement() end,
    GetMovementWrapper = function(Component) return Component.MovementWrapper end,
    SetSpeed = function(Component,...) return Component:SetSpeed(...) end,
    SetJumpForce = function(Component,...) return Component:SetJumpForce(...) end,
    AddFilter = function(Component, ...) return Component:AddFilter(...) end,
    RemoveFilter = function(Component, ...) return Component:RemoveFilter(...) end,
}

return { new = MovementComponent.new, ExposeAPI = ExposeAPI }
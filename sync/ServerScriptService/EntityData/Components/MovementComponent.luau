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

    -- Forças externas
    self.ActiveForces = {} 
    self.ForceCounter = 0

    self.MovementWrapper = nil
    return self
end

function MovementComponent:SetSpeed(value)
    self.MovementWrapper:SetSpeed(value)
end

function MovementComponent:SetJumpForce(value)
    self.MovementWrapper:SetJumpForce(value)
end

function MovementComponent:GetSpeed()
    return self.Entity:GetStat(StateTable.Enum.Stats.Speed)
end

function MovementComponent:GetJumpForce()
    return self.Entity:GetStat(StateTable.Enum.Stats.JumpForce)
end

function MovementComponent:SetMovement()
    if self.MovementWrapper then return false end 
    
    local EntityWrapper = require(ServerScript.EntityData.EntityWrapper)
    local wrapper = self.Entity.GetCharacterWrapper()
    
    -- Criamos o wrapper de movimentação.
    self.MovementWrapper = EntityWrapper.CreateMovement(wrapper)

    MovementController.Register(self)
    return true
end

--CleanUp
function MovementComponent:Destroy()
    MovementController.Unregister(self)
    self.MovementWrapper = nil
    self.Entity = nil
    table.clear(self.ActiveForces)
end

-- Aplicação de forças
function MovementComponent:AddForce(forceData)
    self.ForceCounter += 1
    local id = "F_" .. tostring(self.ForceCounter)
    self.ActiveForces[id] = { ID = id, Data = forceData, ElapsedTime = 0, Type = forceData.Type or "UnnamedForce" }
    return id
end

function MovementComponent:RemoveForce(id)
    local entry = self.ActiveForces[id]
    if entry then
        if entry.Data.OnEnd then task.spawn(entry.Data.OnEnd) end
        self.ActiveForces[id] = nil
    end
end


local ExposeAPI = {
    SetDirection = function(Component, dir) Component.Direction = dir end,
    GetDirection = function(Component) return Component.Direction end,
    AddForce = function(Component, ...) return Component:AddForce(...) end,
    RemoveForce = function(Component, ...) return Component:RemoveForce(...) end,
    SetFrozen = function(Component, f) Component.IsFrozen = f end,
    SetMovement = function(Component) return Component:SetMovement() end,
    GetMovementWrapper = function(Component) return Component.MovementWrapper end,
    SetSpeed = function(Component,...) return Component.SetSpeed end,
}

return { new = MovementComponent.new, ExposeAPI = ExposeAPI }
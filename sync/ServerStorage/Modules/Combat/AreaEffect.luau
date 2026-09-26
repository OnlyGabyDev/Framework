local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local DataManager = require(ServerScriptService.EntityData.DataManager)

local AreaEffect = {}
AreaEffect.__index = AreaEffect

--[[
@param cframeProvider () -> CFrame  -- lido a cada poll, permite zona que
    acompanha algo que se move/gira (o ventilador, por exemplo)
@param shape "Box" | "Sphere"
@param size Vector3 (Box) ou number (Sphere, raio)
@param pollRate number -- Hz. NÃO use .Touched (não-confiável com objetos
    rápidos/pequenos — mesma razão pela qual o resto do combate já usa raycast
    em vez de Touched).
]]
function AreaEffect.new(cframeProvider, shape, size, pollRate)
    local self = setmetatable({}, AreaEffect)
    self.CFrameProvider = cframeProvider
    self.Shape = shape
    self.Size = size
    self.PollRate = pollRate or 10
    
    self.OverlapParams = OverlapParams.new()
    self.OverlapParams.FilterType = Enum.RaycastFilterType.Exclude
    
    self.Inside = {} -- [EntityCore] = true, pra distinguir OnEnter de OnStay
    self.CallbacksEnter = {}
    self.CallbacksStay = {}
    self.CallbacksExit = {}
    
    self.Active = false
    return self
end

function AreaEffect:OnEnter(cb) table.insert(self.CallbacksEnter, cb); return self end
function AreaEffect:OnStay(cb)  table.insert(self.CallbacksStay, cb);  return self end
function AreaEffect:OnExit(cb)  table.insert(self.CallbacksExit, cb);  return self end

function AreaEffect:_Query(): {any} -- devolve lista de EntityCore atualmente dentro
    local cframe = self.CFrameProvider()
    local parts
    if self.Shape == "Box" then
        parts = workspace:GetPartBoundsInBox(cframe, self.Size, self.OverlapParams)
    else
        parts = workspace:GetPartBoundsInRadius(cframe.Position, self.Size, self.OverlapParams)
    end

    local found = {}
    for _, part in ipairs(parts) do
        local entity = DataManager.GetEntityFromInstance(part)
        if entity then found[entity] = true end
    end
    return found
end

function AreaEffect:Start()
    if self.Active then return end
    self.Active = true
    local lastPoll = 0
    self._conn = RunService.Heartbeat:Connect(function(dt)
        lastPoll += dt
        if lastPoll < (1 / self.PollRate) then return end
        lastPoll = 0

        local current = self:_Query()
        for entity in pairs(current) do
            if self.Inside[entity] then
                for _, cb in ipairs(self.CallbacksStay) do task.spawn(cb, entity) end
            else
                self.Inside[entity] = true
                for _, cb in ipairs(self.CallbacksEnter) do task.spawn(cb, entity) end
            end
        end
        for entity in pairs(self.Inside) do
            if not current[entity] then
                self.Inside[entity] = nil
                for _, cb in ipairs(self.CallbacksExit) do task.spawn(cb, entity) end
            end
        end
    end)
end

function AreaEffect:Stop()
    self.Active = false
    if self._conn then self._conn:Disconnect(); self._conn = nil end
    table.clear(self.Inside)
end

return AreaEffect

local AttributeComponents = {}
AttributeComponents.__index = AttributeComponents

local ServerStorage = game:GetService("ServerStorage")
local Enum = require(ServerStorage.Modules.Combat.StateTable.Enum)
local DB = require(ServerStorage.DataBase.CharacterDatabase)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

function AttributeComponents.new(entity, config)
    local self = setmetatable({}, AttributeComponents)
    self.Entity = entity

    -- Busca por config padrão (override)
    self.BaseStats = config.BaseStats or {}

    -- Modificadores ativos
    -- Ex: table["Speed"]["BuffID"] = { Type = "Flat", Value = -0.5 }
    self.Modifiers = {} 

    return self
end

--=============================================================================
--  PIPELINE ATRIBUTOS
--=============================================================================

function AttributeComponents:GetStat(AttributeName, default)
    
    local base = self.BaseStats[AttributeName] or default or 0
    local mods = self.Modifiers[AttributeName]


    --Se não for um status complexo, retorne apenas o valor encontrado no DB
    if not mods then return base end

    local finalBase = base
    local flatSum = 0
    local AddPercentSum = 0
    local MultPercentTotal = 1
    
    local activeOverride = nil

    --Busca o método de alteração e soma/subtrai no atributo.
    for _, mod in pairs(mods) do
        if mod.Type == Enum.ModifierType.Override then
            --Se o modificador for override, guarde o menor valor 
            if activeOverride == nil or mod.Value < activeOverride then
                activeOverride = mod.Value
            end
        elseif mod.Type == Enum.ModifierType.Flat then
            flatSum += mod.Value
        elseif mod.Type == Enum.ModifierType.AddPercent then
            AddPercentSum += mod.Value
        elseif mod.Type == Enum.ModifierType.MultPercent then
            MultPercentTotal *= mod.Value
        end
    end

    -- Se houver um Override, ele substitui o valor base original
    if activeOverride ~= nil then
        finalBase = activeOverride
    end


    -- Fórmula: ((Base + Flat) * (1 + %Add)) * %Mult)
    local result = ((finalBase + flatSum) * (1 + AddPercentSum)) * MultPercentTotal
    
    return math.max(0, result) -- Impede que atributos fiquem negativos
end

function AttributeComponents:SetStat(AttributeName, value)
    self.BaseStats[AttributeName] = value
end

--[[
Retorna a tabela de Stats do personagem
@return tabela de Stats TABLE
]]
function AttributeComponents:GetStats() : {}
	if not self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then return {Speed = 16, JumpForce = 20, GravityScale = 1} end
	local char = self.Entity.GetChosenChar()
	local mode = self.Entity.GetCharMode()
	local charData = DB[char][mode]

	return charData
end

--=============================================================================
--  GERENCIAMENTO
--=============================================================================

--Adiciona um modificador com base num ID e nome de atributo
function AttributeComponents:AddModifier(AttributeName, sourceID, type, value)
    if not self.Modifiers[AttributeName] then
        self.Modifiers[AttributeName] = {}
    end
    self.Modifiers[AttributeName][sourceID] = { Type = type, Value = value }
end

--Remove o modificador pelo ID da origem
function AttributeComponents:RemoveModifier(AttributeName, sourceID)
    if self.Modifiers[AttributeName] then
        self.Modifiers[AttributeName][sourceID] = nil
    end
end


function AttributeComponents:OnAdded()

		local charData = self:GetStats()
        if not next(self.BaseStats) then
             local DefaultStats =  
                {
                    Speed = 16,
                    JumpForce = 50,
                    MaxHP = 100,
                    Defense = 0,
                    DamageMult = 1,
                }

            if not charData then

                self.BaseStats = DefaultStats
            end

            self.BaseStats = {
                Speed = charData["Stats"][StateTable.Enum.Stats.Speed] or DefaultStats.Speed,
                JumpForce = charData["Stats"][StateTable.Enum.Stats.JumpForce] or DefaultStats.JumpForce,
                MaxHP = charData["Stats"][StateTable.Enum.Stats.MaxHP] or DefaultStats.MaxHP,
                Defense = charData["Stats"][StateTable.Enum.Stats.Defense] or DefaultStats.Defense,
                DamageMult = charData["Stats"][StateTable.Enum.Stats.DamageMult] or DefaultStats.DamageMult,
                Weapon = charData[StateTable.Enum.Stats.Weapon],
            }
        end
end

local ExposeAPI = {
    GetStats = function(component, ...) return component:GetStats(...) end,
    GetStat = function(component, ...) return component:GetStat(...) end,
    SetStat = function(component, ...) return component:SetStat(...) end,
    AddModifier = function(component, ...) return component:AddModifier(...) end,
    RemoveModifier = function(component, ...) return component:RemoveModifier(...) end,
}

return {
    InitPriority = "High",
    new = AttributeComponents.new,
    ExposeAPI = ExposeAPI
}
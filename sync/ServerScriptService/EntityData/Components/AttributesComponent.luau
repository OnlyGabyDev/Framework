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
	local entity = self.Entity

	-- Sem Combat não há char/forma: devolve o MESMO shape do registro, só com defaults
	if not entity:HasComponent(entity.ComponentKey.Combat) then
		return { Stats = table.clone(StateTable.Enum.StatDefaults) }
	end

	local charData = DB[entity.GetChosenChar()]
	local formData = charData and charData[entity.GetCharMode()]

	return formData or { Stats = table.clone(StateTable.Enum.StatDefaults) }
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
	if next(self.BaseStats) then return end -- override por config: respeita

	local charData = self:GetStats()
	local stats = charData.Stats or {}
	local Stat = StateTable.Enum.Stats
	local Defaults = StateTable.Enum.StatDefaults

	self.BaseStats = {
		Speed = stats[Stat.Speed] or Defaults.Speed,
		JumpForce = stats[Stat.JumpForce] or Defaults.JumpForce,
		MaxHP = stats[Stat.MaxHP] or Defaults.MaxHP,
		Defense = stats[Stat.Defense] or Defaults.Defense,
		DamageMult = stats[Stat.DamageMult] or Defaults.DamageMult,
		GravityScale = stats[Stat.GravityScale] or Defaults.GravityScale,
		Weapon = charData[Stat.Weapon],
	}
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
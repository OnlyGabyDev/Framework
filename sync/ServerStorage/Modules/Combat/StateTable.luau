

local StateTable = {}


local Enum = require(script.Enum)
local Helper = require(script.Helper)


StateTable.Enum = Enum
StateTable.Categories = Enum.categories
StateTable.reactTags  = Enum.reactTags

StateTable.Status = {}       -- Buffs, Debuffs
StateTable.States = {}       -- Stun, Root, Silence
StateTable.PlayerStates = {} -- SelfCast, GlobalCast, LockedCast

Helper.LoadModules(script, "States", StateTable.States) 
Helper.LoadModules(script, "Status", StateTable.Status)
Helper.LoadModules(script, "PlayerStates", StateTable.PlayerStates)



--[[
Retorna todas as tags de controle de um estado
@param stateName - STRING
@return tags - TABLE
]]
function StateTable:GetTags(stateName : string) : {}
	return Helper.GetTags(self, stateName)
end


--[[
Devolve se o efeito fornecido é um estado
@param meta - dados do state
@return boolean
]]
function StateTable:IsState(meta : {}) : boolean
	return Helper.IsState(self, meta)
end


--[[
Injeta a função fornecida num clone do efeito escolhido.
@param spell - Spell escolhida da table de efeitos TABLE
@param callbackName - nome do breakpoint a ser utilizado (fornecido em Enum.Skillbreakpoints) STRING
@param action - função anonima a ser armazenada no breakpoint de escolha
@return efeito alterado TABLE
]]
function StateTable:BuildEffect(spell : {}, callbackName : string, action: () -> nil)
	return Helper.BuildEffect(spell, callbackName, action)
end

function StateTable.CheckBlockFilter(runner,context)
	return Helper.CheckBlockFilter(runner,context)
end 

function StateTable.BuildContext(source,amount)
	return Helper.BuildContext(source,amount)
end

function StateTable.BuildHistory(data)
	return Helper.BuildHistory(data)
end

return StateTable
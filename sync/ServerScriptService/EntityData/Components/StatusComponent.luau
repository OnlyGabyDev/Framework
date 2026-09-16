--[[
    StatusComponent.module.lua
    Componente para gerenciar status (buffs, debuffs, estados) em uma entidade.
]]


local ServerStorage = game:GetService("ServerStorage")
local ServerScript = game:GetService("ServerScriptService")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local SkillRunner = require(game.ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(ServerScript.Modules.SkillFactory)

local StatusComponent = {}
StatusComponent.__index = StatusComponent

function StatusComponent.new(entity, config)
	local self = setmetatable({}, StatusComponent)
	
	self.Entity = entity
	
	-- Effects ativos
	self.Effects = {
		status = {}, -- Buffs/debuffs 
		state = {}   -- Estados 
	}
	
	-- Cache de tags combinadas
	self._cachedTags = nil
	self._tagsDirty = true
	
	-- Cache de regras de imunidade
	self._immunityRules = nil

	--Cooldown de status
	self.StatusCooldowns = {} -- [statusName] = timestamp
	
	return self
end


--=============================================================================
--  STATUS COOLDOWN
--=============================================================================

--[[
Checa se o status está em cooldown
@param name - nome do status STRING
@return está em cooldown BOOLEAN
]]
function StatusComponent:HasStatusCooldown(name)
	return (self.StatusCooldowns[name] or 0) > tick()
end


--[[
Seta o cooldown de um status
@param name - nome do status STRING
@param duration - duração do cooldown NUMBER
]]
function StatusComponent:SetStatusCooldown(name : string, duration : number)
	self.StatusCooldowns[name] = tick() + duration
end


--[[
Devolve o tempo restante do cooldown de um status
@param name - nome do status STRING
@return tempo restante do cooldown NUMBER
]]
function StatusComponent:GetStatusCooldown(name : string) : number
	return math.max(0, (self.StatusCooldowns[name] or 0) - tick())
end


--=============================================================================
--  APLICAÇÃO DE STATUS
--=============================================================================

--[[
Aplica um status à entidade
@param statusData - Dados do status TABLE
@param duration - Duração do status NUMBER (opcional, pode ser definido em statusData)
@param sourceSkill - SkillRunner responsável pela skill que aplicou o status ANY (opcional)
@param ID - ID único do status STRING (opcional)
@return ID do status STRING ou nil se não aplicado
]]
function StatusComponent:ApplyStatus(statusData, duration : number?, sourceSkill : any?, ID : string?,targetEntity: {}?) : string?
	statusData["Entity"] = sourceSkill.Entity or nil
	local canApply= self:_ValidateApplication(statusData, sourceSkill)

	if not canApply then
		return nil
	end


	-- Gera ID único se não fornecido
	if not ID then
		ID = self:GenerateUniqueEffectID(statusData.data.name or "Generic")
	end

	local factoryData = SkillFactory.GetStatus(statusData)


	-- Preparação do Contexto para o novo Status
    local nextChainHistory
    if sourceSkill and sourceSkill.ChainHistory then
		local ch = sourceSkill.ChainHistory
		table.insert(ch.history, factoryData.data.name or "Unknown")
		ch.depth += 1

		nextChainHistory = ch
    else
    -- Se não tiver sourceSkill, cria novo
    data = {
        rootSkill = factoryData.data.name,
        history = {factoryData.data.name},
        depth = 1,
    }
	nextChainHistory = StateTable.BuildHistory(data)
    end


	-- Prepara dados
	local data = table.clone(factoryData)
	data.ID = ID
	data.data.castTime = 0
    data.ChainHistory = nextChainHistory
	data.data.Entity = sourceSkill and sourceSkill.Entity or nil
	
	if data.data.category == "PlayerState" then
		warn("[StatusComponent] PlayerState settado com função errada!")
		return nil
	end

	local meta = data.data
	if not meta or not meta.name then
		warn("[StatusComponent] Status sem nome ou .data")
		return nil
	end
	
	-- Determina se é estado ou status
	local isState = StateTable:IsState(meta)
	local group = isState and self.Effects.state or self.Effects.status

	
	-- Verifica cooldown (se aplicável)
	if meta.cooldown and meta.cooldown > 0 and sourceSkill then
		local sourceEntity = sourceSkill.ED -- EntityData
		if sourceEntity and sourceEntity.hasStatusCooldown then
			if self:hasStatusCooldown(meta.name) then
				return nil -- Em cooldown
			end
			self:setStatusCooldown(meta.name, meta.cooldown)
		end
	end
	
	-- ===== STACK NA MESMA INSTÂNCIA =====

	if meta.traits and meta.traits[StateTable.Enum.Traits.Stackable] and meta.stackOnSelf then
		local existing = group[meta.name]
		if existing then
			if existing.counter >= (meta.maxStacks or math.huge) then
				return ID -- Limite atingido
			end

			
			existing.runner.counter += 1

			if existing.runner then
				existing.runner.elapsedTime = 0 -- Reset timer
				if existing.runner.Recast then
					existing.runner:Recast()
				end
			end
			return ID
		end
		
		-- Cria novo runner
		local runner = self:_CreateRunner(data, meta.name, duration,targetEntity)
		group[meta.name] = {
			data = data,
			counter = 1,
			runner = runner,
			sourceSkill = sourceSkill,
			ID = ID,
		}
		
		self:_MarkTagsDirty()
		return ID
	end
	
	-- ===== STACK EM INSTÂNCIAS DIFERENTES =====
	if meta.traits and meta.traits[StateTable.Enum.Traits.Stackable] and not meta.stackOnSelf then
   	 if not group[meta.name] then
      	  group[meta.name] = {}
    	end
    
    local list = group[meta.name]
    if #list >= (meta.maxStacks or math.huge) then
        return nil
    end
		
		local runner = self:_CreateRunner(data, meta.name, duration,targetEntity)
		table.insert(list, {
			data = data,
			runner = runner,
			sourceSkill = sourceSkill,
			ID = ID,
		})
		
		group[meta.name] = list
		self:_MarkTagsDirty()
		return ID
	end
	
	-- ===== EXCLUSIVO (substitui outros da mesma categoria) =====
	if meta.exclusive then
		for name, entry in pairs(group) do
			local entryMeta = entry.data and entry.data.data
			if entryMeta and entryMeta.category == meta.category then
				self:RemoveStatus(name)
			end
		end
	end
	
	-- ===== STATUS ÚNICO =====
	local runner = self:_CreateRunner(data, meta.name, duration,targetEntity)
	group[meta.name] = {
		data = data,
		runner = runner,
		sourceSkill = sourceSkill,
		ID = ID,
	}
	
	self:_MarkTagsDirty()
	return ID
end

--[[
Cria um SkillRunner para o status
@param data - Dados do status TABLE
@param name - Nome do status STRING
@param duration - Duração do status NUMBER (opcional)
@return SkillRunner criado SkillRunner
]]
function StatusComponent:_CreateRunner(data : {[string]: any}, name : string, duration : number?,target)
	
	-- Injeta duração se fornecida
	if duration then
		data.runtimeDuration = duration
	end
	

	local targetEntity = target and target.Entity or self.Entity
	local runner = SkillRunner.new(data, targetEntity, name,StateTable.Enum.Types.Status)
	
	-- Callback de finalização
	if runner then
		runner.onFinish = function()
			self:_OnRunnerFinished(name, runner)
			self:_MarkTagsDirty()
		end
		runner:start()
	end
	return runner
end


--[[
Função interna, valida a aplicação de um status/estado
@param statusData - Dados do status TABLE
@param sourceSkill - SkillRunner que aplicou o status ANY (opcional)
@return sucesso,motivo(se falseo) BOOLEAN,STRING
]]
function StatusComponent:_ValidateApplication(statusData, sourceSkill)
	local activeShields = self:_GetShields()
	local effectCategory = statusData.data.category
	local effectTraits = statusData.data.traits and statusData.data.traits or {}
    local effectName = statusData.data.name
	local foundShield = nil

    -- Ordem de prioridade: Categoria > Traits > Nome
    if effectCategory and activeShields[effectCategory] then
        foundShield = effectCategory end
	for v,name in pairs(effectTraits) do

		if name and activeShields[name] then
			foundShield = name end
	end

    if effectName and activeShields[effectName] then
        foundShield = effectName
    end

    if foundShield then
        local blocked, reason = self:_TriggerShield(foundShield, activeShields, statusData, sourceSkill)
        
        if blocked then
            return false, reason 
        end
    end
    
    if activeShields["All"] then
        return false, "GlobalImmunity"
    end

    return true
end

function StatusComponent:_TriggerShield(immunityTag, activeShields,incomingData,sourceSkill)

	local runner = activeShields[immunityTag]

	if runner then
		local context = StateTable.BuildContext(incomingData)
		context.incomingStatus = incomingData
		context.targetEntity = self.Entity
		
		 --Chama a ação de trigger no shield com a skill que está tentando aplicar o status
		local blocked = runner:TriggerAction(context)
			if blocked then return true end
	end
	
	return false 
end



--[[
Gera um ID único para um status
@param sourceName - Nome da fonte STRING (opcional)
@return ID único STRING
]]
function StatusComponent:GenerateUniqueEffectID(sourceName : string) : string
	sourceName = sourceName or "Generic"
	return sourceName .. "_" .. tostring(tick()):gsub("%.", "") .. "_" .. math.random(100, 9999)
end


--=============================================================================
--  REMOÇÃO DE STATUS
--=============================================================================

--[[
RemoveStatus um status completamente pelo nome
@param name - Nome do status STRING
]]
function StatusComponent:RemoveStatus(name : string)
	for _, group in pairs(self.Effects) do
		local entry = group[name]
		if not entry then continue end
		
		-- Single runner
		if entry.runner then
			entry.runner:endSkill(true)
		-- Multiple runners
		elseif type(entry) == "table" then
			for _, item in ipairs(entry) do
				if item.runner then
					item.runner:endSkill(true)
				end
			end
		end
		
		group[name] = nil
		self:_MarkTagsDirty()
	end
end


--[[
RemoveAmount
@param name - Nome do status
@param amount - Quantidade de instâncias a serem removidas
RemoveStatus uma quantidade específica de instâncias de um status por nome
]]

function StatusComponent:RemoveAmount(name: string, amount: number): boolean
	if amount <= 0 then
		return false
	end
	local removed = false

	-- busca por status
	local group = self.Effects.status
	local entry = group[name]
	if not entry then
		return false
	end

	--Remoção de stacks na mesma instância
	if entry.runner and entry.runner.counter then
		entry.runner.counter -= amount
		removed = true

		if entry.runner.counter <= 0 then
			entry.runner:endSkill(true)
			group[name] = nil
		end

	--Remoção de múltiplas instâncias
	elseif type(entry) == "table" then
		local toRemove = math.min(amount, #entry)

		for i = 1, toRemove do
			local item = table.remove(entry,1)
			if item.runner then
				item.runner:endSkill(true)
			end
		end

		if #entry == 0 then
			group[name] = nil
		end

		removed = toRemove > 0
	end

	if removed then
		self:_MarkTagsDirty()
	end

	return removed
end

--[[
RemoveStatusByID
@param id - ID único do status/estado STRING
@return sucesso BOOLEAN
RemoveStatus um status/estado completamente pelo ID único
]]
function StatusComponent:RemoveStatusByID(id : string) : boolean
	local removed = false
	
	for groupName, group in pairs(self.Effects) do
		if groupName == "state" then
			for name, entry in pairs(group) do
				if entry.ID == id then
					self:RemoveStatus(name)
					removed = true
				end
			end
		elseif groupName == StateTable.Enum.Status then
			for name, list in pairs(group) do
				-- single entry
				if list.ID == id then
					self:RemoveStatus(name)
					removed = true

				-- multiple entries (array-only)
				elseif type(list) == "table" and list[1] ~= nil then
					for i = #list, 1, -1 do
						local entry = list[i]
						if entry.ID == id then
							if entry.runner then
								entry.runner:Stop(true)
							end
							table.remove(list, i)
							removed = true
						end
					end

					if list[1] == nil then
						group[name] = nil
					end
				end
			end
		end
	end

	if removed then
		self:_MarkTagsDirty()
	end
	return removed
end

	

--[[
Limpa referências ao runner finalizar
@param name - Nome do status STRING
@param runner - SkillRunner que finalizou SkillRunner
]]
function StatusComponent:_OnRunnerFinished(name : string, runner)
	local entry = self.Effects.status[name]
	if not entry then return end

	-- Caso único
	if entry.runner == runner then
		self.Effects.status[name] = nil
		self:_MarkTagsDirty()
		return
	end

	-- Caso múltiplas instâncias
	if type(entry) == "table" then
		for i = #entry, 1, -1 do
			if entry[i].runner == runner then
				table.remove(entry, i)
			end
		end

		if #entry == 0 then
			self.Effects.status[name] = nil
		end
	end

	self:_MarkTagsDirty()
end

--=============================================================================
--  TAGS
--=============================================================================

--[[
Obtém as tags ativas combinadas da entidade
@return tabela de tags TABLE]]
function StatusComponent:GetActiveTags()
    if not self._tagsDirty and self._cachedTags then
        return self._cachedTags,self._tagRunners
    end
    
    local mergedTags = {}
    local tagOwners = {} 
    
    for _, group in pairs(self.Effects) do 
        for _, entry in pairs(group) do
            local items = (entry.runner or entry.data) and {entry} or entry
            
            for _, item in ipairs(items) do
                local runner = item.runner
                local metaData = runner and runner.data.data or item.data.data
                local tags = metaData and metaData.tags or {}
                
                for tagName, val in pairs(tags) do
                    if val == false then
                        mergedTags[tagName] = false
                    elseif mergedTags[tagName] ~= false then
                        mergedTags[tagName] = val
                    end
                    
                    if runner and val then 
                        tagOwners[tagName] = runner 
                    end
                end
            end
        end
    end
    
    self._cachedTags = mergedTags
    self._tagRunners = tagOwners 
    self._tagsDirty = false

    return mergedTags,tagOwners
end

--[[
Salva que uma mudança de tags ocorreu.
]]
function StatusComponent:_MarkTagsDirty()
	self._tagsDirty = true
end

--=============================================================================
--  VALIDAÇÃO DE HIT
--=============================================================================

--[[
Inicializa e retorna as regras de imunidade baseadas na StateTable
@return tabela de regras TABLE
]]
function StatusComponent:GetImmunityRules()
	local rules = {}
	
	for name, def in pairs(StateTable.Status) do
		local data = def.data or def
		local tags = data.tags or {}
		
		for tagName, isTrue in pairs(tags) do
			if isTrue and data.bypassBy then
				rules[tagName] = {
					name = name,
					bypassableBy = data.bypassBy,
				}
			end
		end
	end
	
	self._immunityRules = rules
	return rules
end

--[[
Retorna os efeitos a ser ignorados.
]]
function StatusComponent:_GetShields()

	local shields = {}
	local effectRunner

	for _,effect in pairs(self.Effects.status) do
		effectRunner = effect.runner     
		if effect.data.data.ShieldsFrom ~= nil then 
			for _,StatusName in pairs(effect.data.data.ShieldsFrom) do
				shields[StatusName] = effectRunner
			end
		end
	end

	return shields
end

--=============================================================================
--  GETTERS
--=============================================================================

--[[
Retorna um status especifico por nome
@param name - Nome do status STRING
@return lista de entradas do status TABLE ou nil se não encontrado
]]
function StatusComponent:GetStatus(name : string) : {}?
	local entry = self.Effects.status[name] or self.Effects.state[name]
	if not entry then return nil end
	
	if entry.runner or entry.data then
		return {entry}
	end
	return entry
end

--[[
Retorna o contador de stacks de um status por nome
@param name - Nome do status STRING
@return contador - NUMBER
]]
function StatusComponent:GetStatusCounter(name : string) : number
	local list = self:GetStatus(name)
	if not list then return 0 end
	
	local entry = list[1]
	if entry.runner and entry.data.data.stackOnSelf then
		return entry.runner.counter
	else
		return #list
	end
end

--[[
Busca por um estado especifico
]]
function StatusComponent:GetState(stateName : string)
	return self.Effects.state[stateName]
end

--[[
 Retorna todos os estados ativos atualmente na entidade.
@return Tabela de estados ativos { [Nome] = Dados }
]]
function StatusComponent:GetActiveStates()
	return self.Effects.state
end

--[[
Verifica se a entidade possui algum estado de uma categoria específica.
@param category - String da categoria
@return boolean
]]
function StatusComponent:HasStateCategory(category : string) : boolean
	for _, entry in pairs(self.Effects.state) do
		local items = (entry.runner or entry.data) and {entry} or entry
		
		for _, item in ipairs(items) do
			if item.data and item.data.data and item.data.data.category == category then
				return true
			end
		end
	end
	return false
end

--=============================================================================
--  LIFECYCLE
--=============================================================================

--[[
Limpa todos os STATUS ativos e devolve quantos foram removidos
@return quantidade de instancias removidas NUMBER
]]
function StatusComponent:ClearAll() : number
	local removed = 0
	for _, group in pairs(self.Effects) do
		for name in pairs(group) do
			self:RemoveStatus(name)
			removed += 1
		end
	end
	return removed
end

--[[
Destroi o componente, limpando referências e parando processos
]]
function StatusComponent:Destroy()
	table.clear(self.StatusCooldowns)
	self:ClearAll()
	self.Entity = nil
	self._cachedTags = nil
	self._immunityRules = nil
end

--=============================================================================
--  API EXPOSE
--=============================================================================

local ExposeAPI = {

	--Status/entidade
	ApplyStatus = function(component, ...) return component:ApplyStatus(...) end,
	RemoveStatus = function(component, ...) return component:RemoveStatus(...) end,
	RemoveStatusByID = function(component, ...) return component:RemoveStatusByID(...) end,
	GetStatus = function(component, ...) return component:GetStatus(...) end,
	RemoveAmount = function(component,...) return component:RemoveAmount(...)end,

	--Tags
	GetImmunityRules = function(component) return component:GetImmunityRules() end,
	GetActiveTags = function(component) return component:GetActiveTags() end,               
	GetStatusCounter = function(component) return component:GetStatusCounter() end,
	GenerateUniqueEffectID = function(component, ...) return component:GenerateUniqueEffectID(...) end,         

	--Status Cooldown
	HasStatusCooldown = function(component, ...) return component:HasStatusCooldown(...) end,
	SetStatusCooldown = function(component, ...) return component:SetStatusCooldown(...) end,
	GetStatusCooldown = function(component, ...) return component:GetStatusCooldown(...) end,

	GetActiveStates = function(component) return component:GetActiveStates() end,
	HasStateCategory = function(component, ...) return component:HasStateCategory(...) end,
}

return {
	new = StatusComponent.new,
	ExposeAPI = ExposeAPI
}
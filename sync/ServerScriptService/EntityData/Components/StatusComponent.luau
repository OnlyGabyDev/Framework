--[[
    StatusComponent.module.lua
    Componente para gerenciar status (buffs, debuffs, estados) em uma entidade.
]]


local ServerStorage = game:GetService("ServerStorage")
local ServerScript = game:GetService("ServerScriptService")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local StateEnum = StateTable.Enum
local SkillRunner = require(game.ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(ServerScript.Modules.SkillFactory)

local StatusComponent = {}
StatusComponent.__index = StatusComponent

local function nextSeq(self)
	self._effectSeq += 1
	return self._effectSeq
end

local function asItems(entry)
	return (entry.runner or entry.data) and { entry } or entry
end

function StatusComponent.new(entity, config)
	local self = setmetatable({}, StatusComponent)
	
	self.Entity = entity
	
	-- Effects ativos
	self.Effects = {
		[StateTable.Enum.Types.Status] = {}, -- Buffs/debuffs 
		[StateTable.Enum.Types.State] = {}   -- Estados 
	}
	
	-- Cache de tags combinadas
	self._cachedTags = nil
	self._tagsDirty = true
	self._effectSeq = 0 -- NOVO: contador monotônico, usado pra desempate determinístico em GetActiveTags

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
--[[
Aplica um status à entidade.
@param statusData - Dados do status TABLE
@param durationOrOpts - NUMBER (duração, estilo legado) OU TABLE de opções:
	{ Duration: number?, Source: Runner|SkillProxy?, ID: string?, Target: EntityCore? }
@param sourceSkill - (só no estilo legado) Runner ou proxy de skill responsável
@param ID - (só no estilo legado) ID único do status
@param targetEntity - (só no estilo legado) EntityCore alvo, se != self.Entity
@return ID do status STRING ou nil se não aplicado
]]
function StatusComponent:ApplyStatus(statusData, durationOrOpts, sourceSkill, ID, targetEntity)
	if not StateTable.TryEnterChain() then
		warn("[StatusComponent] MAX_RECURSION excedido, aplicação recusada. Entidade:", tostring(self.Entity.ID))
		return nil
	end

	local resultID = self:_ApplyStatusInner(statusData, durationOrOpts, sourceSkill, ID, targetEntity)
	StateTable.ExitChain()

	return resultID
end

function StatusComponent:_ApplyStatusInner(statusData, durationOrOpts, sourceSkill, ID, targetEntity)
	-- Aceita opts (estilo novo) OU os parâmetros posicionais antigos (compatibilidade)
	local opts
	if type(durationOrOpts) == "table" then
		opts = durationOrOpts
	else
		opts = { Duration = durationOrOpts, Source = sourceSkill, ID = ID, Target = targetEntity }
	end

	local duration = opts.Duration
	local source = StateTable.ResolveRunner(opts.Source)
	local target = opts.Target
	local suppliedID = opts.ID

	local canApply = self:_ValidateApplication(statusData, source)
	if not canApply then
		return nil
	end

	if not suppliedID then
		suppliedID = self:GenerateUniqueEffectID(statusData.data and statusData.data.name or "Generic")
	end

	local factoryData = SkillFactory.GetStatus(statusData)

	local data = table.clone(factoryData)
	data.ID = suppliedID

	if data.data.category == "ActionState" then
		warn("[StatusComponent] ActionState settado com função errada!")
		return nil
	end

	local meta = data.data
	if not meta or not meta.name then
		warn("[StatusComponent] Status sem nome ou .data")
		return nil
	end

	local isState = StateTable:IsState(meta)
	local group = isState and self.Effects[StateEnum.Types.State] or self.Effects[StateEnum.Types.Status]

	-- Verifica cooldown de re-aplicação (se o status declarar data.cooldown)
	if meta.cooldown and meta.cooldown > 0 then
		if self:HasStatusCooldown(meta.name) then
			return nil -- Em cooldown
		end
		self:SetStatusCooldown(meta.name, meta.cooldown)
	end

	-- ===== STACK NA MESMA INSTÂNCIA =====
	if StateTable.HasTrait(meta, StateEnum.Traits.Stackable) and meta.stackOnSelf then
		local existing = group[meta.name]
		if existing then
			if existing.runner.skill.counter >= (meta.maxStacks or math.huge) then
				return suppliedID
			end

			existing.runner.skill.counter += 1

			if existing.runner then
				existing.runner.elapsedTime = 0
				if existing.runner.Recast then
					existing.runner:Recast()
				end
			end
			return suppliedID
		end

		local runner = self:_CreateRunner(data, meta.name, duration, target, source)
		group[meta.name] = { data = data, counter = 1, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) }

		self:_MarkTagsDirty()
		return suppliedID
	end

	-- ===== STACK EM INSTÂNCIAS DIFERENTES =====
	if StateTable.HasTrait(meta, StateEnum.Traits.Stackable) and not meta.stackOnSelf then
		if not group[meta.name] then
			group[meta.name] = {}
		end

		local list = group[meta.name]
		if #list >= (meta.maxStacks or math.huge) then
			return nil
		end

		local runner = self:_CreateRunner(data, meta.name, duration, target, source)
		table.insert(list, { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) })

		group[meta.name] = list
		self:_MarkTagsDirty()
		return suppliedID
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
	local previous = group[meta.name]
	if previous and previous.runner then
		previous.runner:endSkill(true)
	end

	local runner = self:_CreateRunner(data, meta.name, duration, target, source)
	group[meta.name] = { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) }

	self:_MarkTagsDirty()
	return suppliedID
end

--[[
Cria um SkillRunner para o status
@param data - Dados do status TABLE
@param name - Nome do status STRING
@param duration - Duração do status NUMBER (opcional)
@return SkillRunner criado SkillRunner
]]
--[[
Cria um SkillRunner para o status.
@param source - Runner original que aplicou o status (opcional). Vira runner.Source
	(acessível como self.Source dentro dos callbacks) e alimenta a Lineage do novo
	runner, corrigindo Lineage.Origin (antes sempre virava o portador, nunca o caster).
]]
function StatusComponent:_CreateRunner(data, name, duration, target, source)

	if duration then
		data.runtimeDuration = duration
	end

	local targetEntity = target and target.Entity or self.Entity
	local runner = SkillRunner.new(data, targetEntity, name, StateEnum.Types.Status, source and source.Lineage)

	if runner then
		runner.Source = source
		runner.skill.Source = source -- Opção A: acesso direto por self.Source dentro dos callbacks

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

	local item = activeShields[immunityTag]
	local runner = item and item.runner

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
	local group = self.Effects[StateTable.Enum.Types.Status]
	local entry = group[name]
	if not entry then
		return false
	end

	--Remoção de stacks na mesma instância
	if entry.runner and entry.runner.skill.counter then
		entry.runner.skill.counter -= amount
		removed = true

		if entry.runner.skill.counter <= 0 then
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
		if groupName == StateTable.Enum.Types.State then
			for name, entry in pairs(group) do
				if entry.ID == id then
					self:RemoveStatus(name)
					removed = true
				end
			end
		elseif groupName == StateTable.Enum.Types.Status then
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
	for _, groupName in ipairs({StateTable.Enum.Types.Status, StateTable.Enum.Types.State}) do
		local group = self.Effects[groupName]
		local entry = group[name]
		if not entry then continue end

		-- Caso único
		if entry.runner == runner then
			group[name] = nil
			self:_MarkTagsDirty()
			return
		end

		-- Caso múltiplas instâncias (LISTA). Entrada única de outro runner NÃO entra aqui.
		if entry[1] ~= nil then
			local removed = false
			for i = #entry, 1, -1 do
				if entry[i].runner == runner then
					table.remove(entry, i)
					removed = true
				end
			end

			if #entry == 0 then
				group[name] = nil
			end
			
			if removed then
				self:_MarkTagsDirty()
				return
			end
		end
	end
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
    local tagOwnerSeq = {} -- [tagName] = seq do dono atual, resolve empate multi-fonte deterministicamente
    
    for _, group in pairs(self.Effects) do 
        for _, entry in pairs(group) do
            local items = asItems(entry)
            
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
                        local itemSeq = item.seq or 0
                        -- Dono da tag = aplicação mais recente (maior seq). Sem isso, pairs()
                        -- decidia o "vencedor" de forma não-determinística a cada rehash da hash table.
                        if tagOwnerSeq[tagName] == nil or itemSeq >= tagOwnerSeq[tagName] then
                            tagOwners[tagName] = item
                            tagOwnerSeq[tagName] = itemSeq
                        end
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
	-- Calculado uma única vez pro servidor inteiro em StateTable.luau (dado estático)
	return StateTable.ImmunityRules
end

--[[
Valida se um ataque pode afetar a entidade baseado em suas tags de imunidade (iFrame e afins).
Relocado de HealthComponent: Health não deveria conhecer o conceito de imunidade.
@return sucesso BOOLEAN, razão STRING (nome da imunidade que bloqueou o hit)
]]
function StatusComponent:ValidateHit(context)
	local targetTags = self:GetActiveTags()
	local immunityRules = self:GetImmunityRules()
	local attackTraits = context.traits

	for immunityName, rule in pairs(immunityRules) do
		if targetTags[immunityName] and immunityName ~= StateEnum.Tags.block then
			local allowed = false

			for _, trait in ipairs(attackTraits or {}) do
				if table.find(rule.bypassableBy, trait) then
					allowed = true
					break
				end
			end

			if not allowed then
				return false, immunityName
			end
		end
	end

	return true
end

--[[
Aplica a mitigação de block/parry (se a entidade tiver a tag `block` ativa).
Comportamento IDÊNTICO ao que estava em HealthComponent:TakeDamage — só relocado.
Pode reduzir/zerar context.damage; não retorna nada (muta o context).
]]
function StatusComponent:ApplyMitigation(context)
	local activeTags, owners = self:GetActiveTags()
	local blockTag = StateEnum.Tags.block

	if not activeTags[blockTag] then return end

	local ignore = false
	for _, value in pairs(context.traits or {}) do
		if StateEnum.BlockIgnore[value] then
			ignore = true
			break
		end
	end

	local blockRunner = owners[blockTag]
	if not blockRunner then return end

	local skipBlock = (
		not (blockRunner.data.traits and table.find(blockRunner.data.traits, StateEnum.Traits.TrueBlock))
		and ignore
	)
	if skipBlock then return end

	local canInteract = StateTable.CheckBlockFilter(blockRunner, context)
	if not canInteract then return end

	local broke = false
	if context.source and context.traits then
		local blockBreak = nil
		for _, trait in context.traits do
			blockBreak = StateEnum.BlockBreak[trait]
			if blockBreak then break end
		end

		local unbreakable = blockRunner.data.traits and table.find(blockRunner.data.traits, StateEnum.Traits.Unbreakable)
		if blockBreak and not unbreakable then
			if blockRunner.runner then blockRunner.runner:Stop(true) end
			broke = true
		end
	end

	if not broke and blockRunner.runner then
		local resultDamage = blockRunner.runner:TriggerAction(context)
		if resultDamage then
			context.damage = resultDamage
		end
	end
end

--[[
Retorna os efeitos a ser ignorados.
]]
function StatusComponent:_GetShields()
	local shields = {}

	for _, entry in pairs(self.Effects[StateTable.Enum.Types.Status]) do
		for _, item in ipairs(asItems(entry)) do
			local shieldsFrom = item.data.data.ShieldsFrom
			if shieldsFrom ~= nil then
				for _, statusName in pairs(shieldsFrom) do
					shields[statusName] = item.runner
				end
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
	local entry = self.Effects[StateTable.Enum.Types.Status][name] or self.Effects[StateTable.Enum.Types.State][name]
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
		return entry.runner.skill.counter
	else
		return #list
	end
end

--[[
Busca por um estado especifico
]]
function StatusComponent:GetState(stateName : string)
	return self.Effects[StateTable.Enum.Types.State][stateName]
end

--[[
 Retorna todos os estados ativos atualmente na entidade.
@return Tabela de estados ativos { [Nome] = Dados }
]]
function StatusComponent:GetActiveStates()
	return self.Effects[StateTable.Enum.Types.State]
end

--[[
Verifica se a entidade possui algum estado de uma categoria específica.
@param category - String da categoria
@return boolean
]]
function StatusComponent:HasStateCategory(category : string) : boolean
	for _, entry in pairs(self.Effects[StateTable.Enum.Types.State]) do
		local items = asItems(entry)
		
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
	ValidateHit = function(component, ...) return component:ValidateHit(...) end,
	ApplyMitigation = function(component, ...) return component:ApplyMitigation(...) end,
	GetActiveTags = function(component) return component:GetActiveTags() end,               
	GetStatusCounter = function(component, ...) return component:GetStatusCounter(...) end,
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
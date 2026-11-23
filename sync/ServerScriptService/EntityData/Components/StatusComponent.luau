--[[
StatusComponent: status (buffs, debuffs) e estados (Stun, Root...) da entidade. Cada status é um
SkillRunner registrado em self.Effects; as tags dos ativos viram as permissões da entidade
(canMove, canCast, block, iFrame...).
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

-- Dependência opcional de Health: sem ela a entidade não morre, então nunca recusa status por isso
local function isDead(entity)
	return StateTable.IsDead(entity)
end

-- Encerra runners que já saíram do registro (o onFinish deles não mexe em lista nenhuma)
local function endDetached(items)
	for _, item in items do
		if item.runner then
			item.runner:endSkill(true)
		end
	end
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
	self._effectSeq = 0 -- contador monotônico: desempate determinístico em GetActiveTags

	--Cooldown de status
	self.StatusCooldowns = {} -- [statusName] = timestamp

	-- Regra de morte do motor: padrão em Enum.DeathDefaults, override no config
	self._refuseStatusOnDeath = StateTable.ResolveDeathPolicy(config, "RefuseStatusOnDeath")

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
Aplica um status à entidade (sempre nesta entidade: para mirar outra, use o ApplyStatus dela ou
runner:ApplyStatus(status, { Target = alvo })).
@param statusData - o status { data, callbacks } TABLE
@param durationOrOpts - { Duration?, Source?, ID?, Inherited? } ou a duração NUMBER (forma posicional)
@param sourceSkill, ID, targetEntity - só na forma posicional
@return ID do status STRING, ou nil se não entrou (também quando a cadeia estava funda demais e o
	status vai entrar no próximo frame)
]]
function StatusComponent:ApplyStatus(statusData, durationOrOpts, sourceSkill, ID, targetEntity)
	local ran, resultID = StateTable.RunInChain(
		"[StatusComponent] ApplyStatus", self.Entity and self.Entity.ID,
		self._ApplyStatusInner, self, statusData, durationOrOpts, sourceSkill, ID, targetEntity)
	return ran and resultID or nil
end

function StatusComponent:_ApplyStatusInner(statusData, durationOrOpts, sourceSkill, ID, targetEntity)
	-- Entidade saindo não recebe status (um status adiado pela cadeia roda no frame seguinte)
	if self._destroying then return nil end

	-- Aceita opts (estilo novo) OU os parâmetros posicionais antigos (compatibilidade)
	local opts
	if type(durationOrOpts) == "table" then
		opts = durationOrOpts
	else
		opts = { Duration = durationOrOpts, Source = sourceSkill, ID = ID, Target = targetEntity }
	end

	local duration = opts.Duration
	local source = StateTable.ResolveRunner(opts.Source)
	local suppliedID = opts.ID

	-- O alvo é sempre esta entidade
	if opts.Target and opts.Target ~= self.Entity then
		warn("[StatusComponent] ApplyStatus ignora Target de outra entidade; use runner:ApplyStatus(status, { Target = alvo }):",
			statusData.data and statusData.data.name)
	end

	-- Morto não recebe status. Configurável por entidade (RefuseStatusOnDeath = false no config) e por
	-- status (data.allowOnDead = true)
	if self._refuseStatusOnDeath and isDead(self.Entity) and not (statusData.data and statusData.data.allowOnDead) then
		return nil
	end

	local canApply = self:_ValidateApplication(statusData, source)
	if not canApply then
		return nil
	end

	-- Checagem pré-output: o dono do efeito recebe OUT.PreApplyStatus (traits do status, alvo,
	-- inherited) e pode cancelar ou injetar no inherited. Sem ouvinte, nenhum contexto é montado
	local inherited = opts.Inherited
	local owner = StateTable.EffectOwner(source)
	if owner and owner:HasListeners(StateEnum.Roles.OUT, StateEnum.Breakpoints.PreApplyStatus) then
		local context = StateTable.BuildContext(source, 0)
		context.traits = table.clone(statusData.data and statusData.data.traits or {})
		context.incomingStatus = statusData
		context.targetEntity = self.Entity
		for key, value in inherited or {} do
			context.inherited[key] = value
		end
		owner:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.PreApplyStatus, context)
		if context.cancelled then
			return nil
		end
		inherited = context.inherited
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
	-- A reaplicação soma um stack na instância existente e devolve o ID dela. O Source não muda: o
	-- crédito fica com quem aplicou o 1º stack. O contador é runner.skill.counter.
	if StateTable.HasTrait(meta, StateEnum.Traits.Stackable) and meta.stackOnSelf then
		local existing = group[meta.name]
		-- Runner encerrado ainda listado (reaplicação durante o próprio teardown, antes do
		-- onFinish) não recebe stack: a aplicação vira uma instância nova
		if existing and not existing.runner:IsEnded() then
			local runner = existing.runner
			local atMax = runner.skill.counter >= (meta.maxStacks or math.huge)
			-- No máximo de stacks a reaplicação só renova a duração (data.refreshOnMax = false desliga)
			if atMax and meta.refreshOnMax == false then
				return existing.ID
			end
			if duration then
				runner.skill.runtimeDuration = duration -- a duração da reaplicação passa a valer
			end
			runner.elapsedTime = 0
			if not atMax then
				runner.skill.counter += 1
				runner:Recast()
			end
			return existing.ID
		end

		local runner = self:_CreateRunner(data, meta.name, duration, source, inherited)
		group[meta.name] = { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) }
		return self:_StartRunner(runner, suppliedID)
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

		local runner = self:_CreateRunner(data, meta.name, duration, source, inherited)
		table.insert(list, { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) })

		group[meta.name] = list
		return self:_StartRunner(runner, suppliedID)
	end

	-- ===== EXCLUSIVO (substitui outros da mesma categoria) =====
	if meta.exclusive then
		-- Snapshot dos nomes: RemoveStatus encerra runners, e os callbacks de fim podem
		-- aplicar status neste mesmo grupo enquanto o pairs ainda percorre ele.
		local sameCategory = {}
		for name, entry in pairs(group) do
			-- Stack em instâncias é uma lista de entradas: o meta vem da 1ª
			local first = asItems(entry)[1]
			local entryMeta = first and first.data and first.data.data
			if entryMeta and entryMeta.category == meta.category then
				table.insert(sameCategory, name)
			end
		end
		for _, name in sameCategory do
			self:RemoveStatus(name)
		end
	end

	-- ===== STATUS ÚNICO =====
	local previous = group[meta.name]
	if previous and previous.runner then
		previous.runner:endSkill(true)
	end

	local runner = self:_CreateRunner(data, meta.name, duration, source, inherited)
	group[meta.name] = { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) }
	return self:_StartRunner(runner, suppliedID)
end

--[[
Inicia um runner cuja entrada já está registrada em self.Effects: um status que falha ou se encerra
no próprio onStart passa pelo onFinish e sai do registro.
@return o ID, ou nil se o onStart falhou
]]
function StatusComponent:_StartRunner(runner, suppliedID)
	self:_MarkTagsDirty()
	if not runner:start() then
		return nil
	end
	-- Estado com a tag interrupt: avisa a entidade (o Combat escuta e cancela as skills ativas)
	local tags = runner.data and runner.data.tags
	if tags and tags[StateEnum.Tags.interrupt] and self.Entity then
		local context = StateTable.BuildContext(runner.Source, 0)
		context.incomingStatus = runner.data
		self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnInterrupt, context)
	end
	return suppliedID
end

--[[
Cria o runner do status. Não inicia: quem chama registra a entrada em self.Effects e só então
chama _StartRunner.
@param source - runner que aplicou o status: vira runner.Source (self.Source nos callbacks) e o
	pai na Lineage
@param inherited - payload explícito (ctx.inherited do status)
]]
function StatusComponent:_CreateRunner(data, name, duration, source, inherited)

	if duration then
		data.runtimeDuration = duration
	end

	-- O runner age na entidade que registra o status (é o portador: self.Entity nos callbacks)
	local runner = SkillRunner.new(data, self.Entity, name, StateEnum.Types.Status, source and source.Lineage, nil, inherited)

	if runner then
		runner.Source = source
		runner.skill.Source = source -- self.Source dentro dos callbacks

		runner.onFinish = function()
			self:_OnRunnerFinished(name, runner)
			self:_MarkTagsDirty()
		end
	end
	return runner
end


--[[
Confere os escudos de status (ShieldsFrom) contra o status que está entrando.
@return pode aplicar BOOLEAN
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
RemoveStatus um status completamente pelo nome (todas as instâncias, nos dois grupos)
@param name - Nome do status STRING
@return removeu alguma instância BOOLEAN
]]
function StatusComponent:RemoveStatus(name : string) : boolean
	-- Desregistra antes de encerrar: o onFinish de cada runner mexe nas listas
	local detached = {}
	for _, group in pairs(self.Effects) do
		local entry = group[name]
		if entry then
			group[name] = nil
			for _, item in ipairs(asItems(entry)) do
				table.insert(detached, item)
			end
		end
	end
	if #detached == 0 then return false end

	self:_MarkTagsDirty()
	endDetached(detached)
	return true
end


--[[
Remove `amount` stacks (stackOnSelf) ou instâncias de um status.
@param name - nome do status STRING
@param amount - quantos NUMBER
@return removeu algo BOOLEAN
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

	-- Desregistra antes de encerrar: um status que se reaplica no onEnd grava a entrada nova, e ela
	-- não pode ser apagada depois
	local detached = {}

	--Remoção de stacks na mesma instância
	if entry.runner and entry.runner.skill.counter then
		entry.runner.skill.counter -= amount
		removed = true

		if entry.runner.skill.counter <= 0 then
			group[name] = nil
			table.insert(detached, entry)
		end

	--Remoção de múltiplas instâncias
	elseif type(entry) == "table" then
		local toRemove = math.min(amount, #entry)

		for _ = 1, toRemove do
			table.insert(detached, table.remove(entry, 1))
		end

		if #entry == 0 then
			group[name] = nil
		end

		removed = toRemove > 0
	end

	if removed then
		self:_MarkTagsDirty()
	end
	endDetached(detached)

	return removed
end

--[[
Remove o status/estado com este ID (todas as entradas dele).
@param id - ID STRING
@return removeu BOOLEAN
]]
function StatusComponent:RemoveStatusByID(id : string) : boolean
	-- 1ª passada só coleta: encerrar runners roda callbacks que podem mexer em self.Effects
	local found = {}
	for _, group in pairs(self.Effects) do
		for name, entry in pairs(group) do
			for _, item in ipairs(asItems(entry)) do
				if item.ID == id then
					table.insert(found, { group = group, name = name, item = item })
				end
			end
		end
	end
	if #found == 0 then return false end

	-- Desregistra antes de encerrar (mesmo motivo do RemoveStatus)
	local detached = {}
	for _, hit in found do
		local entry = hit.group[hit.name]
		if entry == hit.item then
			hit.group[hit.name] = nil
		elseif entry then
			local index = table.find(entry, hit.item)
			if index then table.remove(entry, index) end
			if entry[1] == nil then hit.group[hit.name] = nil end
		end
		table.insert(detached, hit.item)
	end

	self:_MarkTagsDirty()
	endDetached(detached)
	return true
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
                        -- Dono da tag = aplicação mais recente (maior seq)
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
Valida se um ataque pode afetar a entidade pelas tags de imunidade (iFrame e afins).
@return pode BOOLEAN, motivo STRING (a imunidade que barrou)
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
Aplica a mitigação de bloqueio (tag block ativa). Pode reduzir ou zerar context.damage.
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

	-- As traits do bloqueio moram no meta (entry.data.data)
	local blockMeta = StateTable.BlockerMeta(blockRunner)

	local skipBlock = (
		not StateTable.HasTrait(blockMeta, StateEnum.Traits.TrueBlock)
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

		local unbreakable = StateTable.HasTrait(blockMeta, StateEnum.Traits.Unbreakable)
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

--[[ Escudos de status ativos: [categoria | trait | nome] = entrada do status ]]
function StatusComponent:_GetShields()
	local shields = {}

	for _, entry in pairs(self.Effects[StateTable.Enum.Types.Status]) do
		for _, item in ipairs(asItems(entry)) do
			local shieldsFrom = item.data.data.ShieldsFrom
			if shieldsFrom ~= nil then
				-- Guarda a entrada: o _TriggerShield lê entry.runner
				for _, statusName in pairs(shieldsFrom) do
					shields[statusName] = item
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
	-- Desregistra tudo antes de encerrar: os callbacks de fim não podem ver (nem mexer em)
	-- uma tabela que o pairs ainda está percorrendo.
	local detached = {}
	for _, group in pairs(self.Effects) do
		for _, entry in pairs(group) do
			for _, item in ipairs(asItems(entry)) do
				table.insert(detached, item)
			end
		end
		table.clear(group)
	end
	if #detached == 0 then return 0 end

	self:_MarkTagsDirty()
	endDetached(detached)
	return #detached
end

--[[
Destroi o componente, limpando referências e parando processos
]]
function StatusComponent:Destroy()
	self._destroying = true -- callbacks de fim não aplicam status novos numa entidade que está saindo
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
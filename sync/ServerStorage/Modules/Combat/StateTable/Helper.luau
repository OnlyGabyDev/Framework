
local Helper = {}

local Enum = require(script.Parent.Enum)
local LineageModule = require(script.Parent.Parent.Lineage)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)



local function DeepFreeze(tbl)
	if table.isfrozen(tbl) then return tbl end
	for k, v in pairs(tbl) do
		if type(v) == "table" then
			DeepFreeze(v)
		end
	end
	return table.freeze(tbl)
end

--[[
Verifica se o data de um efeito/skill declara a trait. `traits` é SEMPRE array de strings.
(dono único dessa checagem: não use traits[Trait] em lugar nenhum)
]]
function Helper.HasTrait(meta, trait)
	return meta ~= nil and meta.traits ~= nil and table.find(meta.traits, trait) ~= nil
end

--[[
Skills recebem um proxy (`self`) que aponta pro SkillRunner via `.Runner`.
Toda API que guarda/compara identidade de runner ou usa `source` normaliza aqui.
]]
function Helper.ResolveRunner(runnerOrProxy)
	if type(runnerOrProxy) == "table" and runnerOrProxy.Runner then
		return runnerOrProxy.Runner
	end
	return runnerOrProxy
end

--[[
Disjuntor de recursão SÍNCRONA. Cadeias dano->status->dano (ex: parry devolvendo
dano na hora) não tinham nenhum limite real — MAX_RECURSION existia no Enum mas
nada olhava pra ele. Isso é global (não por entidade) de propósito: o risco é
estouro de call stack do SERVIDOR inteiro, não só de uma entidade.
]]
local activeChainDepth = 0

function Helper.TryEnterChain(): boolean
	if activeChainDepth >= Enum.MAX_RECURSION then
		return false
	end
	activeChainDepth += 1
	return true
end

function Helper.ExitChain()
	activeChainDepth = math.max(0, activeChainDepth - 1)
end

local function finishChain(label: string, subject: any, ok: boolean, ...: any)
	Helper.ExitChain()
	if not ok then
		warn(label, "erro dentro da cadeia, ação abortada. Entidade:", tostring(subject), "\n" .. tostring((...)))
		return false, "Error"
	end
	return true, ...
end

--[[
Dono único do par TryEnterChain/ExitChain: roda `fn(...)` dentro do disjuntor e
SEMPRE sai da cadeia, mesmo se `fn` lançar erro. Antes TakeDamage e ApplyStatus
faziam o par à mão e um erro no miolo pulava o ExitChain: depois de MAX_RECURSION
erros o servidor inteiro passava a recusar dano e status.

A profundidade continua global de propósito: ela mede o aninhamento SÍNCRONO real
da pilha (o risco é estourar a pilha do servidor). Um contador no context não
enxergaria reentradas que não repassam o context — ex.: um block que reflete dano
chamando attacker.TakeDamage(dano, self.Runner) monta um context novo a cada nível.

@param label - prefixo dos warns, ex. "[HealthComponent] TakeDamage" STRING
@param subject - identificação da entidade, só usada nos warns ANY
@return true, ...retornos de fn | false, "MaxRecursion" | false, "Error"
]]
function Helper.RunInChain(label: string, subject: any, fn: (...any) -> ...any, ...: any)
	if not Helper.TryEnterChain() then
		warn(label, "MAX_RECURSION excedido, ação recusada. Entidade:", tostring(subject))
		return false, "MaxRecursion"
	end
	return finishChain(label, subject, xpcall(fn, debug.traceback, ...))
end

--[[
Resolve uma regra de morte do motor pra uma entidade: o valor do config do componente ou, na
falta, Enum.DeathDefaults (dono único dos padrões). Chamado UMA vez, no new() do componente.
@param config - config do componente na criação da entidade TABLE?
@param key - chave de Enum.DeathDefaults STRING
]]
function Helper.ResolveDeathPolicy(config: {[string]: any}?, key: string): boolean
	local default = Enum.DeathDefaults[key]
	assert(default ~= nil, "[StateTable] regra de morte desconhecida: " .. tostring(key))
	local value = config and config[key]
	if value == nil then
		return default
	end
	return value and true or false
end

--[[
Morte do ponto de vista do motor. Dependência OPCIONAL de Health (regra 16): sem Health a
entidade não morre, então nenhuma regra de morte vale para ela.
]]
function Helper.IsDead(entity): boolean
	return entity:HasComponent(entity.ComponentKey.Health) and not entity.IsAlive()
end

--[[
Meta (data.data) de quem bloqueia. Aceita os dois formatos que chegam aqui: a entrada do
StatusComponent ({ data = módulo, runner }) e o próprio SkillRunner (runner.data já É o
meta). Antes o filtro lia runner.data.data no SkillRunner, achava nil e era pulado (F11).
]]
function Helper.BlockerMeta(blocker)
	if type(blocker) ~= "table" then return nil end
	if blocker.skill ~= nil then
		return blocker.data
	end
	return (blocker.data and blocker.data.data) or (blocker.skillData and blocker.skillData.data)
end

local ownerTokens = setmetatable({}, { __mode = "k" }) -- [entidade] = { [tag] = token }

--[[
Dono de inscrição (Listen/UnsubscribeByOwner) por entidade (F51). Devolve SEMPRE o mesmo token
para a mesma entidade e tag, e tokens diferentes para entidades diferentes. Um Owner em string é
global: limpar o combo de um atacante num alvo removia também o combo de outro atacante.
]]
function Helper.OwnerToken(entity, tag: string)
	local byTag = ownerTokens[entity]
	if not byTag then
		byTag = {}
		ownerTokens[entity] = byTag
	end
	local token = byTag[tag]
	if not token then
		token = table.freeze({ tag = tag })
		byTag[tag] = token
	end
	return token
end

local warnedBlocks = {} -- [nome do bloqueio] = true: aviso uma vez por servidor

--[[
Resultado de um bloqueio SEM onTrigger, a partir do data.block declarado (D14). Chamado pelo
SkillRunner:TriggerAction. Devolve o dano novo (bloqueio de dano), true (status barrado) ou nil
(não bloqueia). Nada implícito: sem block declarado, não bloqueia.
]]
function Helper.ResolveBlock(meta, context)
	local name = meta and meta.name or "?"
	local block = meta and meta.block
	local function warnOnce(message)
		if warnedBlocks[name] then return end
		warnedBlocks[name] = true
		warn("[StateTable] Bloqueio '" .. tostring(name) .. "': " .. message)
	end

	if not block then
		warnOnce("sem data.block e sem onTrigger; não bloqueia nada. Declare block = { mode = ... }")
		return nil
	end

	local modes = Enum.BlockModes
	local isStatus = context.incomingStatus ~= nil
	local damage = context.damage or 0

	if block.mode == modes.Full then
		return if isStatus then true else 0
	elseif block.mode == modes.Flat then
		if type(block.value) ~= "number" or block.value < 0 then
			warnOnce("mode Flat exige value >= 0")
			return nil
		end
		if isStatus then return nil end
		return math.max(0, damage - block.value)
	elseif block.mode == modes.Percent then
		if type(block.value) ~= "number" or block.value < 0 or block.value > 1 then
			warnOnce("mode Percent exige value entre 0 e 1")
			return nil
		end
		if isStatus then return nil end
		return damage * (1 - block.value)
	elseif block.mode == modes.Custom then
		warnOnce("mode Custom exige onTrigger")
		return nil
	end

	warnOnce("block.mode desconhecido: " .. tostring(block.mode))
	return nil
end

local function registerModule(module, targetTable)
	local success, data = pcall(require, module)
	if not success then
		warn("[StateTable] Erro ao carregar " .. module.Name .. ": " .. tostring(data))
		return
	end

	targetTable[module.Name] = data
	if type(data) ~= "table" then return end

	if data.data and not data.data.name then
		data.data.name = module.Name
	end
	if data.data then DeepFreeze(data.data) end
	if data.callbacks then DeepFreeze(data.callbacks) end
end

function Helper.LoadModules(rootScript, folderName, targetTable)
	local folder = rootScript:FindFirstChild(folderName)
	if not folder then
		warn("[StateTable] Pasta não encontrada: " .. folderName)
		return
	end

	-- GetDescendants cobre módulos soltos E em subpastas (Buffs/Debuffs) numa única passada
	for _, module in ipairs(folder:GetDescendants()) do
		if module:IsA("ModuleScript") then
			registerModule(module, targetTable)
		end
	end
end

function Helper.GetTags(stateTable, stateName)
	local tags = table.clone(Enum.tagsBase)
	local state = stateTable.States[stateName] or stateTable.Status[stateName]

	if state and state.data and state.data.tags then
		for tagName, value in pairs(state.data.tags) do
			tags[tagName] = value
		end
	end

	return tags
end

function Helper.IsState(stateTable, meta)
	if not meta or not meta.name then return false end
	
	if stateTable.States[meta.name] then return true end
	
	for _, group in pairs(stateTable.ActionStates) do
		if type(group) == "table" then
			for _, state in pairs(group) do
				if state.data and state.data.name == meta.name then
					return true
				end
			end
		elseif group.data and group.data.name == meta.name then
			return true
		end
	end

	if meta.category == Enum.Categories.ActionState then
		return true
	end
	
	return false
end



function Helper.BuildEffect(baseStatus, callbackName, actionFunc)
	if not baseStatus then return nil end
	
	local newStatus = table.clone(baseStatus)
	
	if newStatus.callbacks then
		newStatus.callbacks = table.clone(newStatus.callbacks)
	else
		newStatus.callbacks = {}
	end
	
	newStatus.callbacks[callbackName] = actionFunc
	
	return newStatus
end

function Helper.CheckBlockFilter(runner, context)

    local data = Helper.BlockerMeta(runner)

    if not data then return true end
    local source = context.source
    local incomingTraits = context.traits or {}

    if data.ShieldsFromType then
        local sourceType = source and source.type 
        local typeMatch = false
        for _, Type in pairs(data.ShieldsFromType) do
            if sourceType == Type then
                typeMatch = true
                break 
            end
        end
        if not typeMatch then
            return false 
        end
    end

	local shieldsFrom = data.ShieldsFrom

    if shieldsFrom and next(shieldsFrom) then
        local traitMatch = false
        
        for _, requiredTrait in ipairs(shieldsFrom) do
            if table.find(incomingTraits, requiredTrait) then
                traitMatch = true
                break 
            end
        end
        
        if not traitMatch then
            return false 
        end
    end

    return true 
end

--[[
Monta o mapa de imunidades (tag -> quais traits furam ela) a partir de TODOS os
Status cadastrados. É dado ESTÁTICO (não muda por entidade nem em runtime), então
isso deve rodar UMA VEZ pro servidor inteiro — antes, cada entidade recomputava
isso a cada hit que sofria (StatusComponent:GetImmunityRules era chamado, mas o
cache que ele preenchia nunca era lido de volta).
]]
function Helper.BuildImmunityRules(stateTable)
	local rules = {}

	for name, def in pairs(stateTable.Status) do
		local data = def.data or def
		local tags = data.tags or {}

		for tagName, isTrue in pairs(tags) do
			if isTrue and data.bypassBy then
				local existing = rules[tagName]
				if not existing then
					rules[tagName] = {
						name = name,
						bypassableBy = table.clone(data.bypassBy),
					}
				else
					-- Dois status com a mesma tag de imunidade: a regra mesclada só deixa passar a
					-- trait que AMBOS deixam (interseção, independe da ordem). Antes vencia a última
					-- do pairs(), não determinístico (F74)
					local merged = {}
					for _, trait in existing.bypassableBy do
						if table.find(data.bypassBy, trait) then table.insert(merged, trait) end
					end
					existing.bypassableBy = merged
					local names = string.split(existing.name, "+")
					table.insert(names, name)
					table.sort(names)
					existing.name = table.concat(names, "+")
				end
			end
		end
	end

	return table.freeze(rules)
end

--[[
@param source - Runner (ou proxy de skill) responsável pela ação
@param amount - dano/cura base
@param parentContext - Context de quem originou esta ação (opcional). Sem isso,
	a lineage é forkada a partir de `source.Lineage`, que já é o caso comum
	(um Runner de skill/status sempre carrega sua própria Lineage).
]]
function Helper.BuildContext(source, amount, parentContext)
	source = Helper.ResolveRunner(source)

	local context = {
		damage = amount or 0,
		direction = nil,
		source = source,
		sourceEntity = nil,
		traits = {},
		effects = {},
		cancelled = false,
		reason = nil,
	}

	if source then
		if source.Entity then
			context.sourceEntity = source.Entity
		end
		local data = source.skill and source.skill.data or source.data
		if data then
			context.damage = amount or data.damage or 0
			context.traits = table.clone(data.traits or {})
			context.effects = table.clone(data.effects or {})
			context.type = source.type
			context.secondaryType = source.secondaryType or nil
		end
	end

	-- Direção de intenção de quem originou a ação. Regra 16 (dependência
	-- opcional explícita): sem MovementComponent, direction fica nil — quem
	-- ler isso precisa checar por nil.
	if context.sourceEntity and context.sourceEntity:HasComponent(context.sourceEntity.ComponentKey.Movement) then
		local worldDir = context.sourceEntity.GetDirection()
		local facing = context.sourceEntity.GetLookDirection()
		context.direction = {
			Id = Utils.classifyDirection(worldDir, facing),
			World = worldDir,
			Local = Utils.worldToLocalPlanar(worldDir, facing),
			Magnitude = worldDir.Magnitude,
		}
	end

	-- Lineage: dono único é Combat/Lineage.luau (antes essa função não trackeava nada disso)
	local parentLineage = (parentContext and parentContext.Lineage) or (source and source.Lineage)
	context.Lineage = LineageModule.Fork(parentLineage, context.sourceEntity, (source and source.skillName) or "Unknown")

	return context
end



function Helper.BuildHistory(data)
	return LineageModule.Fork(data.ParentLineage, data.Entity, data.name)
end



return Helper
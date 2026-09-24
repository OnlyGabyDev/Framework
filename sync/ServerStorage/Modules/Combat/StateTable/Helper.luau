
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

    local data = (runner.data and runner.data.data) or (runner.skillData and runner.skillData.data)

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
				rules[tagName] = {
					name = name,
					bypassableBy = data.bypassBy,
				}
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
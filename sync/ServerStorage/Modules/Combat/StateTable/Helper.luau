
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
O meta (data) de um efeito/skill declara a trait? `traits` é sempre um array de strings.
]]
function Helper.HasTrait(meta, trait)
	return meta ~= nil and meta.traits ~= nil and table.find(meta.traits, trait) ~= nil
end

--[[
Skills recebem um proxy (`self`) que aponta pro SkillRunner via `.Runner`: quem guarda ou compara
identidade de runner normaliza aqui.
]]
function Helper.ResolveRunner(runnerOrProxy)
	if type(runnerOrProxy) == "table" and runnerOrProxy.Runner then
		return runnerOrProxy.Runner
	end
	return runnerOrProxy
end

local MAX_OWNER_HOPS = 8 -- limite de saltos pelo Source (ciclo não trava)

--[[
Entidade dona de um efeito: quem causou, não onde ele roda. Um status (DOT, reflexo, aura) roda no
portador, mas foi aplicado por alguém (runner.Source): sobe o Source até um runner de skill. O
BuildContext grava o dono em context.ownerEntity; o OUT.OnDamage, o OUT.OnHeal e o OUT.OnDeath vão
para ele.
@param source - runner, proxy de skill ou nil
@return EntityCore? (nil sem runner, ou se o dono já saiu do jogo)
]]
function Helper.EffectOwner(source)
	local runner = Helper.ResolveRunner(source)
	if type(runner) ~= "table" then return nil end
	for _ = 1, MAX_OWNER_HOPS do
		local parent = Helper.ResolveRunner(runner.Source)
		if runner.type == Enum.Types.Skill or type(parent) ~= "table" or parent == runner then break end
		runner = parent
	end
	local owner = runner.Entity
	if owner == nil or owner.Active == false then return nil end
	return owner
end

-- Time da entidade (AffiliationComponent, dependência opcional: sem ele, neutra)
local function teamOf(entity)
	if entity and entity:HasComponent(entity.ComponentKey.Affiliation) then
		return entity.GetTeam()
	end
	return nil
end

--[[
Relação entre duas entidades: Self, Ally (mesmo time), Enemy (times diferentes) ou Neutral (um
dos dois sem time).
@return Enum.Relations
]]
function Helper.Relation(a, b): string
	if a == b then return Enum.Relations.Self end
	local teamA, teamB = teamOf(a), teamOf(b)
	if teamA == nil or teamB == nil then return Enum.Relations.Neutral end
	return if teamA == teamB then Enum.Relations.Ally else Enum.Relations.Enemy
end

--[[
A ação de `source` afeta `targetEntity`? Pergunta de quem resolve alvo (hitbox da arma, zona com
filtro): vale o data.affects da skill por cima de Enum.AffectsDefaults.
@param source - runner/proxy de skill (vale o dono do efeito e o data.affects dele), entidade, ou
	nil (ambiente: afeta todos)
@param targetEntity - EntityCore
@param affects - sobrescreve o data.affects { [Enum.Relations]: boolean }?
]]
function Helper.CanAffect(source, targetEntity, affects): boolean
	if not targetEntity then return false end
	local runner = Helper.ResolveRunner(source)
	local sourceEntity, data = nil, nil
	if type(runner) == "table" and runner.skill ~= nil then -- SkillRunner: o dono do efeito age
		sourceEntity = Helper.EffectOwner(runner)
		data = runner.skill.data
	elseif type(runner) == "table" and type(runner.HasComponent) == "function" then -- entidade
		sourceEntity = runner
	end
	-- Sem dono identificável (ambiente, callback cru): afeta todos
	if sourceEntity == nil then return true end
	local relation = Helper.Relation(sourceEntity, targetEntity)
	local declared = affects or (data and data.affects)
	local allowed = declared and declared[relation]
	if allowed == nil then allowed = Enum.AffectsDefaults[relation] end
	return allowed == true
end

--[[ Predicado pronto para quem filtra uma lista de entidades (AreaEffect:SetFilter) ]]
function Helper.AffectsFilter(source, affects)
	return function(entity)
		return Helper.CanAffect(source, entity, affects)
	end
end

--[[
Disjuntor de recursão síncrona (dano -> status -> dano na mesma pilha). Global de propósito: o
risco é estourar a pilha do servidor, não de uma entidade.
]]
local activeChainDepth = 0

--[[
Fila das ações adiadas: acima de MAX_RECURSION a ação entra aqui e roda no próximo Heartbeat, com a
pilha zerada. A conexão só existe enquanto a fila tem ação.
Formato de um item: { reserve, label, subject, fn, args = table.pack(...), gen }
- gen: gerações de adiamento da cadeia; acima de ChainLimits.maxDeferrals, a ação é recusada.
]]
local CHAIN = Enum.ChainLimits
local OUTCOME = Enum.ChainOutcomes
local RunService = game:GetService("RunService")
local deferredQueue = {}
local queueHead, queueTail = 1, 1 -- itens válidos em [head, tail)
local currentGeneration = 0
local drainConnection = nil

-- Entra um nível, desde que caibam `reserve` níveis a partir daqui (a ação e as de dentro dela)
local function enterChain(reserve: number): boolean
	if activeChainDepth + reserve > Enum.MAX_RECURSION then
		return false
	end
	activeChainDepth += 1
	return true
end

function Helper.TryEnterChain(): boolean
	return enterChain(1)
end

function Helper.ExitChain()
	activeChainDepth = math.max(0, activeChainDepth - 1)
end

local function finishChain(label: string, subject: any, ok: boolean, ...: any)
	Helper.ExitChain()
	if not ok then
		warn(label, "erro dentro da cadeia, ação abortada. Entidade:", tostring(subject), "\n" .. tostring((...)))
		return false, OUTCOME.Error
	end
	return true, ...
end

--[[
Roda `fn(...)` dentro do disjuntor e sempre sai da cadeia, mesmo se `fn` lançar erro.
A profundidade é global porque mede o aninhamento síncrono real da pilha: um contador no context
não enxergaria reentradas que não repassam o context (um reflexo monta um context novo a cada nível).
Acima de MAX_RECURSION a ação vai para a fila e roda no próximo frame; quem chama recebe false,
Deferred. Como a ação adiada pode rodar com o alvo já morto ou fora do jogo, `fn` confere o estado
da entidade no começo.
@param label - prefixo dos warns, ex. "[HealthComponent] TakeDamage" STRING
@param subject - identificação da entidade, só usada nos warns ANY
@return true, ...retornos de fn | false, Enum.ChainOutcomes (Deferred | MaxRecursion | Error)
]]
local deferChain

local function runReserving(reserve: number, label: string, subject: any, fn: (...any) -> ...any, ...: any)
	if not enterChain(reserve) then
		return deferChain(reserve, label, subject, fn, ...)
	end
	return finishChain(label, subject, xpcall(fn, debug.traceback, ...))
end

function Helper.RunInChain(label: string, subject: any, fn: (...any) -> ...any, ...: any)
	return runReserving(1, label, subject, fn, ...)
end

--[[
Igual ao RunInChain, para uma ação que chama outra ação da cadeia por dentro e precisa das duas na
mesma pilha (o ApplyDamage reserva 2: ele e o TakeDamage do alvo).
@param levels - níveis que a ação usa NUMBER
]]
function Helper.RunInChainReserving(levels: number, label: string, subject: any, fn: (...any) -> ...any, ...: any)
	return runReserving(levels, label, subject, fn, ...)
end

local function drainDeferred()
	local budget = CHAIN.deferredPerFrame
	-- Só o que já estava na fila: o que for adiado agora é do próximo frame (uma geração por frame)
	local stop = queueTail
	while budget > 0 and queueHead < stop do
		local job = deferredQueue[queueHead]
		deferredQueue[queueHead] = nil
		queueHead += 1
		budget -= 1
		currentGeneration = job.gen
		runReserving(job.reserve, job.label, job.subject, job.fn, table.unpack(job.args, 1, job.args.n))
		currentGeneration = 0
	end
	if queueHead >= queueTail then
		queueHead, queueTail = 1, 1
		if drainConnection then
			drainConnection:Disconnect()
			drainConnection = nil
		end
	end
end

--[[
Põe a ação na fila do próximo frame, ou recusa (Enum.ChainLimits). Chamado quando a pilha não tem
mais os níveis que a ação pede.
@return false, Enum.ChainOutcomes.Deferred | false, Enum.ChainOutcomes.MaxRecursion
]]
function deferChain(reserve: number, label: string, subject: any, fn: (...any) -> ...any, ...: any)
	if not CHAIN.deferAtMaxDepth then
		warn(label, "MAX_RECURSION excedido, ação recusada. Entidade:", tostring(subject))
		return false, OUTCOME.MaxRecursion
	end
	if currentGeneration >= CHAIN.maxDeferrals then
		warn(label, "a cadeia passou de", CHAIN.maxDeferrals, "adiamentos de", Enum.MAX_RECURSION,
			"níveis (laço infinito?), ação recusada. Entidade:", tostring(subject))
		return false, OUTCOME.MaxRecursion
	end
	deferredQueue[queueTail] = { reserve = reserve, label = label, subject = subject, fn = fn,
		args = table.pack(...), gen = currentGeneration + 1 }
	queueTail += 1
	if not drainConnection then
		drainConnection = RunService.Heartbeat:Connect(drainDeferred)
	end
	return false, OUTCOME.Deferred
end

--[[ Ações esperando na fila (0 = nenhuma cadeia adiada). Para teste e diagnóstico ]]
function Helper.GetDeferredCount(): number
	return queueTail - queueHead
end

--[[
Regra de morte do motor para uma entidade: o valor do config do componente ou, na falta,
Enum.DeathDefaults. Chamado uma vez, no new() do componente.
@param config - config do componente TABLE?
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
Morte do ponto de vista do motor. Dependência opcional de Health: sem ela a entidade não morre.
]]
function Helper.IsDead(entity): boolean
	return entity:HasComponent(entity.ComponentKey.Health) and not entity.IsAlive()
end

--[[
Meta (data.data) de quem bloqueia. Aceita a entrada do StatusComponent ({ data = módulo, runner })
e o próprio SkillRunner (runner.data já é o meta).
]]
function Helper.BlockerMeta(blocker)
	if type(blocker) ~= "table" then return nil end
	if blocker.skill ~= nil then
		return blocker.data
	end
	return (blocker.data and blocker.data.data) or (blocker.skillData and blocker.skillData.data)
end

--[[
Resolve um efeito on-hit: o status e se ele vale para hit bloqueado e para hit de 0 de dano.
Precedência: o próprio efeito > data.effectPolicy da skill de origem > Enum.EffectDefaults.
@param entry - o status, ou { status = status, onBlocked = bool?, onZeroDamage = bool? }
@param sourceData - data da skill/status que causou o hit TABLE?
@return status, onBlocked BOOLEAN, onZeroDamage BOOLEAN
]]
function Helper.ResolveEffect(entry, sourceData)
	local status, own = entry, nil
	if type(entry) == "table" and entry.status ~= nil then
		status, own = entry.status, entry
	end
	local skillPolicy = sourceData and sourceData.effectPolicy or nil
	local function pick(key)
		if own and own[key] ~= nil then return own[key] end
		if skillPolicy and skillPolicy[key] ~= nil then return skillPolicy[key] end
		return Enum.EffectDefaults[key]
	end
	return status, pick("onBlocked"), pick("onZeroDamage")
end

--[[
Dano depois das proteções de stat do alvo, na ordem de Enum.DamageMitigation.
@param damage NUMBER
@param getStat - (statName, default) -> number (o GetStat do alvo)
@param traits - traits do hit {string}
@return dano mitigado NUMBER (nunca negativo)
]]
function Helper.MitigateDamage(damage: number, getStat, traits): number
	for _, protection in Enum.DamageMitigation do
		local pierced = false
		for _, trait in protection.ignoredBy or {} do
			if table.find(traits or {}, trait) then pierced = true break end
		end
		if not pierced then
			local value = getStat(protection.stat, Enum.StatDefaults[protection.stat] or 0)
			if protection.mode == Enum.MitigationModes.Multiplicative then
				if value >= 0 then
					damage *= 100 / (100 + value)
				else
					damage *= 2 - 100 / (100 - value)
				end
			elseif protection.mode == Enum.MitigationModes.Flat then
				damage -= value
			end
		end
	end
	return math.max(0, damage)
end

local ownerTokens = setmetatable({}, { __mode = "k" }) -- [entidade] = { [tag] = token }

--[[
Dono de inscrição (Listen/UnsubscribeByOwner) por entidade: sempre o mesmo token para a mesma
entidade e tag. Use no lugar de Owner em string, que é global entre entidades.
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
Resultado de um bloqueio sem onTrigger, a partir do data.block declarado. Devolve o dano novo
(bloqueio de dano), true (status barrado) ou nil (não bloqueia). Sem block declarado, não bloqueia.
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
Mapa de imunidades (tag -> traits que furam) a partir de todos os status cadastrados. Dado
estático: roda uma vez para o servidor inteiro.
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
					-- Dois status com a mesma tag de imunidade: só passa a trait que ambos deixam passar
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
Monta o contexto de uma ação ofensiva (Types.HitContext).
@param source - runner (ou proxy de skill) responsável
@param amount - dano/cura base
@param parentContext - contexto de quem originou esta ação (opcional; sem ele, a Lineage sai de
	source.Lineage)
]]
function Helper.BuildContext(source, amount, parentContext)
	source = Helper.ResolveRunner(source)

	local context = {
		damage = amount or 0,
		direction = nil,
		source = source,
		sourceEntity = nil,  -- onde o runner que causou roda (num DOT, a própria vítima)
		ownerEntity = Helper.EffectOwner(source), -- quem causou: dono do efeito
		traits = {},
		effects = {},
		-- Payload explícito para o que este hit gerar (status on-hit). Começa vazio; quem dispara põe
		-- (opts.Inherited) e a checagem pré-output (OUT.onHit, OUT.PreApplyStatus) pode injetar
		inherited = {},
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

	-- Direção de intenção de quem originou (dependência opcional de Movement: sem ele, nil)
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

	-- Lineage: dono do formato é Combat/Lineage.luau
	local parentLineage = (parentContext and parentContext.Lineage) or (source and source.Lineage)
	context.Lineage = LineageModule.Fork(parentLineage, context.sourceEntity, (source and source.skillName) or "Unknown")

	return context
end



function Helper.BuildHistory(data)
	return LineageModule.Fork(data.ParentLineage, data.Entity, data.name, data.Runner)
end



return Helper
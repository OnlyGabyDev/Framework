
Sprints — Hitbox Desacoplada + Módulos Bônus

Prompts prontos pra colar em sequência no AntiGravity. Entregue um de cada vez, na ordem abaixo — a ordem respeita dependências (ex: Fork de TriggerSet precisa existir antes do MinionFactory usar parentEntity).
Índice

    Fix determinismo no Block (StatusComponent)
    Fix TTD/expiração no Fork do TriggerSet
    HitboxSpawner
    HitboxBehaviors + HitboxPresets
    Ground/Air State (IMovement)
    Floating — patch do Sprint 5
    Direção relativa + AimDirection (pitch)
    Tether Force (grab/drag)
    Network Ownership — patch do Sprint 8
    Fork automático de TriggerSet no spawn (DataManager.Create)
    ComboWindow (BaseSkills)
    ControlComponent (Lock/Unlock)
    Link/Unlink (extensão do ControlComponent)
    CameraOverride
    AIComponent (base)
    SoundManager
    VFXManager
    Dynamic AddComponent + MinionFactory
    TestHarness
    IntegrationTests (testes isolados automatizados)
    GrandIntegrationDemo (IA possuível, caça, combo, tether, fork — tudo junto)

Sprint 1 — Fix de determinismo no Block

Contexto: StatusComponent:GetActiveTags decide o "dono" de uma tag (block, por exemplo) iterando pairs() sobre hash table — ordem não garantida entre execuções. Corrigido com um contador monotônico, mesmo princípio que TriggerSet._seq já usa pra desempate.

ARQUIVO: sync/ServerScriptService/EntityData/Components/StatusComponent.luau

-- 1) No StatusComponent.new, adicione o contador:
function StatusComponent.new(entity, config)
	local self = setmetatable({}, StatusComponent)
	
	self.Entity = entity
	
	self.Effects = {
		[StateTable.Enum.Types.Status] = {},
		[StateTable.Enum.Types.State] = {}
	}
	
	self._cachedTags = nil
	self._tagsDirty = true
	self._effectSeq = 0 -- NOVO: contador monotônico, usado pra desempate determinístico em GetActiveTags

	self.StatusCooldowns = {}
	
	return self
end

-- 2) Adicione esta função local, logo abaixo dos requires no topo do arquivo:
local function nextSeq(self)
	self._effectSeq += 1
	return self._effectSeq
end

-- 3) Em _ApplyStatusInner, SUBSTITUA as 3 linhas de criação de entry por estas
--    (adicionando `seq = nextSeq(self)` em cada uma — são 3 pontos diferentes no arquivo):

-- 3a) Stack-on-self, instância nova:
local runner = self:_CreateRunner(data, meta.name, duration, target, source)
group[meta.name] = { data = data, counter = 1, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) }

-- 3b) Stack em instâncias diferentes:
local runner = self:_CreateRunner(data, meta.name, duration, target, source)
table.insert(list, { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) })

-- 3c) Status único (exclusive ou normal):
local runner = self:_CreateRunner(data, meta.name, duration, target, source)
group[meta.name] = { data = data, runner = runner, sourceSkill = source, ID = suppliedID, seq = nextSeq(self) }

-- 4) SUBSTITUA GetActiveTags inteira por esta versão:
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
                            tagOwners[tagName] = runner
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

VALIDAÇÃO: aplique duas fontes de block na mesma entidade em sequência (ex: GenericBlock seguido de um shield custom) e confirme, via print em ApplyMitigation, que o blockRunner resolvido é sempre o da aplicação mais recente, em execuções repetidas.
Sprint 2 — Fix TTD/expiração no Fork do TriggerSet

Contexto: TTD ("Time To Die") não é typo, é nome intencional. Mas a expiração é checada de forma preguiçosa só em Emit, pro Role+Breakpoint exato. Isso causa dois problemas: (1) um sub expirado num breakpoint raro fica pendurado indefinidamente; (2) Fork() copiava subs SEM checar expiração — uma reação já morta podia "ressuscitar" no filho com countdown novo do zero.

ARQUIVO: sync/ServerStorage/Modules/Combat/TriggerSet.luau (substitua o arquivo inteiro por este)

local TraitQuery = require(script.Parent.TraitQuery)

local TriggerSet = {}
TriggerSet.__index = TriggerSet

function TriggerSet.new()
	local self = setmetatable({}, TriggerSet)
	self.Subscriptions = {}
	self._seq = 0 -- desempate determinístico de prioridade (ordem de inscrição)
	return self
end

-- Dono único da checagem de expiração de TTD (Regra 1) — usado tanto em Emit
-- quanto em Fork. Antes só Emit sabia disso, e Fork podia "ressuscitar" um
-- sub cujo TTD já tinha estourado, herdando um countdown novo do zero.
local function isExpired(sub: any): boolean
	return sub._expirationTime ~= nil and os.clock() >= sub._expirationTime
end

function TriggerSet:Subscribe(sub: any)
	if not self.Subscriptions[sub.Role] then
		self.Subscriptions[sub.Role] = {}
	end
	if not self.Subscriptions[sub.Role][sub.Breakpoint] then
		self.Subscriptions[sub.Role][sub.Breakpoint] = {}
	end

	if not sub._sharedState then
		sub._sharedState = { Count = 0 }
	end
	
	-- TTD (Time To Die): expiração por tempo. Avaliação preguiçosa em Emit,
	-- avaliação ATIVA em Fork (ver TriggerSet:Fork) — sem a segunda, uma
	-- reação já morta podia ser copiada pro filho com clock novo.
	if sub.TTD then
		sub._expirationTime = os.clock() + sub.TTD
	end

	sub._removed = nil
	self._seq += 1
	sub._seq = self._seq

	local list = self.Subscriptions[sub.Role][sub.Breakpoint]
	table.insert(list, sub)

	table.sort(list, function(a, b)
		local pa, pb = a.Priority or 0, b.Priority or 0
		if pa ~= pb then
			return pa > pb
		end
		return a._seq < b._seq
	end)

	return function()
		self:Unsubscribe(sub)
	end
end

function TriggerSet:Unsubscribe(subToRemove: any)
	local byRole = self.Subscriptions[subToRemove.Role]
	local list = byRole and byRole[subToRemove.Breakpoint]
	if list then
		local index = table.find(list, subToRemove)
		if index then
			table.remove(list, index)
		end
	end
	subToRemove._removed = true
end

function TriggerSet:UnsubscribeByOwner(owner: any)
	for _, breakpoints in pairs(self.Subscriptions) do
		for _, list in pairs(breakpoints) do
			for i = #list, 1, -1 do
				if list[i].Owner == owner then
					list[i]._removed = true
					table.remove(list, i)
				end
			end
		end
	end
end

function TriggerSet:Emit(role: string, breakpoint: string, context: any, ...)
	local byRole = self.Subscriptions[role]
	local list = byRole and byRole[breakpoint]
	if not list or #list == 0 then
		return
	end

	for _, sub in table.clone(list) do
		if sub._removed then continue end

		-- 0. TTD (Time To Die) - Avaliação Preguiçosa
		if isExpired(sub) then
			self:Unsubscribe(sub)
			continue
		end

		local matched = TraitQuery.Match(sub.Query, context.traits)
		if not matched then continue end

		local limit = sub.Limit
		if limit and sub._sharedState.Count >= limit.Max then
			if limit.OnExhaust == "Remove" then
				self:Unsubscribe(sub)
			end
			continue
		end

		sub._sharedState.Count += 1

		if type(sub.Action) == "function" then
			local ok, err = xpcall(sub.Action, debug.traceback, context, ...)
			if not ok then
				warn(`[TriggerSet] erro em {role}.{breakpoint}: {err}`)
			end
		end

		if limit and limit.OnExhaust == "Remove" and sub._sharedState.Count >= limit.Max then
			self:Unsubscribe(sub)
		end
	end
end

-- Clona assinaturas que devem ser herdadas
function TriggerSet:Fork()
	local newSet = TriggerSet.new()
	for role, breakpoints in pairs(self.Subscriptions) do
		for bp, list in pairs(breakpoints) do
			-- Clona ANTES de iterar: Unsubscribe (chamado abaixo pra podar
			-- subs expirados encontrados aqui) muda `list` por remoção de
			-- índice — iterar com ipairs sobre a tabela viva ao mesmo tempo
			-- pularia elementos. Mesmo idioma que Emit já usa.
			for _, sub in ipairs(table.clone(list)) do
				if sub._removed then continue end

				-- FIX: sem isso, um sub cujo TTD já estourou (mas que ainda
				-- não foi podado por falta de Emit nesse breakpoint
				-- específico) era copiado pro filho com um countdown NOVO,
				-- do zero — "ressuscitando" uma reação que já devia estar
				-- morta. Aproveita a passagem pra podar do PAI também, de graça.
				if isExpired(sub) then
					self:Unsubscribe(sub)
					continue
				end

				if sub.Inherit and sub.Inherit.Generations > 0 then
					local inheritedTTD = sub.TTD
					if sub.TTD and sub.TTDInheritRemaining and sub._expirationTime then
						-- Opt-in: filho herda o TEMPO RESTANTE, não a duração
						-- cheia de novo. Default é duração cheia (cada
						-- geração da árvore tem sua própria janela plena) —
						-- marque TTDInheritRemaining=true no sub original se
						-- quiser um TTD que só encolhe ao longo da linhagem.
						inheritedTTD = math.max(0, sub._expirationTime - os.clock())
					end

					local inheritedSub = {
						Role = sub.Role,
						Breakpoint = sub.Breakpoint,
						Query = sub.Query,
						Action = sub.Action,
						Priority = sub.Priority,
						Owner = sub.Owner,
						Limit = sub.Limit,
						Inherit = { Generations = sub.Inherit.Generations - 1 },
						TTD = inheritedTTD,
						TTDInheritRemaining = sub.TTDInheritRemaining,
					}

					if inheritedSub.Limit and inheritedSub.Limit.Scope == "Branch" then
						inheritedSub._sharedState = { Count = sub._sharedState.Count }
					elseif inheritedSub.Limit and inheritedSub.Limit.Scope == "Tree" then
						inheritedSub._sharedState = sub._sharedState
					else
						inheritedSub._sharedState = { Count = 0 }
					end

					newSet:Subscribe(inheritedSub)
				end
			end
		end
	end
	return newSet
end

return TriggerSet

VALIDAÇÃO: crie um sub com TTD=0.1 e Inherit={Generations=1} num breakpoint que nunca mais dispara. Espere 0.2s, force um Fork() manual — o filho NÃO deve receber essa inscrição, e o pai também não deve mais listá-la depois do Fork.
Sprint 3 — HitboxSpawner (motor desacoplado)

Contexto: o stub já existe no caminho certo. O motor de baixo nível (Hitbox.luau, Solvers/*, Visualizers/*) já é desacoplado de arma — só quer um Instance com descendentes taggeados DmgPoint. Preenchendo o stub com o mínimo necessário.

ARQUIVO: sync/ServerStorage/Modules/Combat/Hitbox/HitboxSpawner.luau (substituir conteúdo inteiro)

--!strict
--!native
--!optimize 2

-- HitboxSpawner
-- Cria hitboxes desacopladas de arma: usadas quando a fonte do dano NÃO é uma
-- arma equipada (magias, minions, hitbox de chão, etc). Não decide CastType,
-- Size, Radius nem ativa nada — só monta o objeto. Quem chama configura via
-- hitbox:SetCastData(...) e ativa via hitbox:HitStart(...).

local ShapecastHitbox = require(script.Parent.ShapecastHitbox)
local Settings = require(script.Parent.ShapecastHitbox.Settings)

local HitboxSpawner = {}

local CARRIER_NAME = "_DecoupledHitboxCarrier"

--[[
Monta o RaycastParams padrão de exclusão pra hitboxes desacopladas: exclui o
Instance do caster (se fornecido) e qualquer extra pedido. ÚNICO ponto que
monta esse filtro fora do HitboxWrapper (Regra 1 — não duplique "monta filtro
de exclusão" em mais um lugar com pequenas divergências).
]]
function HitboxSpawner.BuildDefaultFilter(casterEntity: any?, extraExclude: {Instance}?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local filter = {}
	if casterEntity and casterEntity.Instance then
		table.insert(filter, casterEntity.Instance)
	end
	if extraExclude then
		for _, inst in ipairs(extraExclude) do
			table.insert(filter, inst)
		end
	end
	params.FilterDescendantsInstances = filter

	return params
end

--[[
Cria um hitbox desacoplado. `pointOffsets` são CFrames LOCAIS ao carrier — um
Attachment "DmgPoint" por offset, todos se movendo juntos quando você mover o
carrier (ver SetCarrierCFrame). Múltiplos offsets = múltiplos pontos de dano
no MESMO hitbox (ex: 3 pontos ao longo de um leque de espada).

@param casterEntity any? - EntityCore de quem está criando (só pro filtro default; pode ser nil se você passar raycastParamsOverride)
@param cframe CFrame - posição/orientação inicial do carrier, no mundo
@param pointOffsets {CFrame}? - default: { CFrame.identity } (1 ponto na origem do carrier)
@param raycastParamsOverride RaycastParams? - se fornecido, ignora BuildDefaultFilter
@return (Types.Hitbox, Instance) - guarde os dois: precisa do carrier pra mover/limpar depois
]]
function HitboxSpawner.Spawn(casterEntity: any?, cframe: CFrame, pointOffsets: {CFrame}?, raycastParamsOverride: RaycastParams?): (any, Instance)
	pointOffsets = pointOffsets or { CFrame.identity }

	local carrier = Instance.new("Part")
	carrier.Name = CARRIER_NAME
	carrier.Size = Vector3.one
	carrier.Transparency = 1
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CanTouch = false
	carrier.Anchored = true
	carrier.CFrame = cframe

	for _, offset in ipairs(pointOffsets :: {CFrame}) do
		local point = Instance.new("Attachment")
		point.Name = Settings.Tag -- "DmgPoint" — Hitbox:AddSegment identifica por NOME, não CollectionService
		point.CFrame = offset
		point.Parent = carrier
	end

	carrier.Parent = workspace

	local raycastParams = raycastParamsOverride or HitboxSpawner.BuildDefaultFilter(casterEntity)
	local hitbox = ShapecastHitbox.new(carrier, raycastParams)

	return hitbox, carrier
end

--[[
Move o carrier de um hitbox Móvel. Use isso DENTRO de um hitbox:OnUpdate(dt)
(ver HitboxBehaviors) — nunca escreva carrier.CFrame direto de outro lugar,
pra isso continuar sendo o único ponto que move um carrier.
]]
function HitboxSpawner.SetCarrierCFrame(carrier: Instance, cframe: CFrame)
	if carrier and carrier.Parent then
		(carrier :: BasePart).CFrame = cframe
	end
end

--[[
Destrói hitbox E carrier juntos. ShapecastHitbox:Destroy() só desconecta o
PostSimulation dela — NÃO destrói o Instance. Sem chamar isso, o carrier vaza
pra sempre no workspace.
]]
function HitboxSpawner.Cleanup(hitbox: any, carrier: Instance)
	if hitbox and hitbox.Destroy then
		hitbox:Destroy()
	end
	if carrier then
		carrier:Destroy()
	end
end

return HitboxSpawner

VALIDAÇÃO: HitboxSpawner.Spawn(nil, CFrame.new(0,10,0)) seguido de hitbox:SetCastData({CastType="Spherecast", Radius=5}) e hitbox:HitStart(2) deve funcionar sem depender de nenhuma arma equipada em nenhuma entidade.
Sprint 4 — HitboxBehaviors + HitboxPresets

Contexto: antes de escrever isso, extraia a rotação suave (que hoje só existe local dentro de MovementController) pra um lugar compartilhado em Utils.luau, pois o Homing de hitbox precisa da mesma lógica — copiá-la seria duplicação (Regra 1).

ARQUIVO 1: sync/ReplicatedStorage/Utils.luau (adicionar função, não é edição de linha existente)

--[[
Rotaciona `current` em direção a `target` (Vector3, não precisam ser unitários),
respeitando um ângulo máximo por chamada. DONO ÚNICO dessa lógica (Regra 1) —
usado por MovementController (giro de personagem em Force) e por
HitboxBehaviors.Homing (giro de projétil). Não duplique isto em nenhum lugar.
]]
function Utils.rotateTowards(current, target, maxRadians)
	if current.Magnitude < 1e-6 then
		return target.Unit
	end

	local currentUnit = current.Unit
	local targetUnit = target.Unit

	local dot = math.clamp(currentUnit:Dot(targetUnit), -1, 1)
	local angle = math.acos(dot)

	if angle <= maxRadians or angle < 1e-4 then
		return targetUnit
	end

	local axis = currentUnit:Cross(targetUnit)
	if axis.Magnitude < 1e-6 then
		axis = currentUnit:Cross(Vector3.yAxis)
		if axis.Magnitude < 1e-6 then
			axis = Vector3.xAxis
		end
	end

	local rotation = CFrame.fromAxisAngle(axis.Unit, maxRadians)
	return (rotation * currentUnit).Unit
end

ARQUIVO 2: sync/ServerScriptService/Modules/Physics/MovementController.luau (edição)

-- No topo do arquivo, adicione o require:
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)

-- REMOVA inteiramente a função local:
-- local function RotateTowards(current: Vector3, target: Vector3, maxRadians: number): Vector3
--     ... (todo o corpo)
-- end

-- E troque a ÚNICA chamada existente:
-- ANTES:
direction = RotateTowards(forceEntry.CurrentDirection, rawDirection, data.TurnRate * dt)
-- DEPOIS:
direction = Utils.rotateTowards(forceEntry.CurrentDirection, rawDirection, data.TurnRate * dt)

ARQUIVO 3: sync/ServerStorage/Modules/Combat/Hitbox/HitboxBehaviors.luau (novo)

--!strict
--!native
--!optimize 2

-- HitboxBehaviors: comportamentos pós-nascimento reutilizáveis. Nenhuma
-- função aqui CRIA hitbox — recebe um hitbox/carrier já spawnado (ver
-- HitboxSpawner) e devolve um callback pronto pra hitbox:OnUpdate(callback).
-- Composição, não caso especial: um preset combina 1+ desses.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)
local HitboxSpawner = require(script.Parent.HitboxSpawner)

local Behaviors = {}

--[[ Aumenta o Radius (Spherecast) uniformemente em todas as direções. ]]
function Behaviors.ExpandUniform(hitbox: any, ratePerSecond: number, maxRadius: number?)
	return function(dt: number)
		local newRadius = hitbox.CastData.Radius + ratePerSecond * dt
		if maxRadius then
			newRadius = math.min(newRadius, maxRadius)
		end
		hitbox.CastData.Radius = newRadius
	end
end

--[[ Aumenta o Size (Blockcast) só no eixo local pedido ("X"|"Y"|"Z"). ]]
function Behaviors.ExpandDirectional(hitbox: any, axis: string, ratePerSecond: number, maxSize: number?)
	assert(axis == "X" or axis == "Y" or axis == "Z", "[HitboxBehaviors] axis precisa ser 'X', 'Y' ou 'Z'")
	return function(dt: number)
		local size = hitbox.CastData.Size
		local growth = ratePerSecond * dt
		local current = (size :: any)[axis]
		local target = maxSize and math.min(current + growth, maxSize) or (current + growth)

		if axis == "X" then
			hitbox.CastData.Size = Vector3.new(target, size.Y, size.Z)
		elseif axis == "Y" then
			hitbox.CastData.Size = Vector3.new(size.X, target, size.Z)
		else
			hitbox.CastData.Size = Vector3.new(size.X, size.Y, target)
		end
	end
end

--[[
Move o carrier em linha reta. Direction/Speed aceitam valor FIXO ou função
(elapsed, duration) -> valor — MESMO PADRÃO de MovementComponent:AddForce.
Não reinvente essa convenção, reuse-a (consistência cognitiva pra quem ler depois).
]]
function Behaviors.LinearMove(carrier: Instance, direction: any, speed: any, duration: number)
	local elapsed = 0
	return function(dt: number)
		elapsed += dt

		local dir = direction
		if type(dir) == "function" then
			dir = dir(elapsed, duration)
		end
		if dir.Magnitude > 1e-4 then
			dir = dir.Unit
		end

		local spd = speed
		if type(spd) == "function" then
			spd = spd(elapsed, duration)
		end

		local currentPosition = (carrier :: BasePart).Position
		local newPosition = currentPosition + dir * spd * dt
		HitboxSpawner.SetCarrierCFrame(carrier, CFrame.lookAt(newPosition, newPosition + dir))
	end
end

--[[
Homing: mesmo contrato de LinearMove, mas Direction é recalculada a cada frame
mirando `getTarget()`. Se getTarget() devolver nil (alvo morreu/saiu), mantém
a última direção conhecida — não trava, não erra.
@param getTarget () -> BasePart? - ex: function() return targetEntity.GetRoot() end
@param turnRateRadPerSec number? - se omitido, homing perfeito (vira instantâneo)
]]
function Behaviors.Homing(carrier: Instance, getTarget: () -> BasePart?, speed: any, turnRateRadPerSec: number?)
	local elapsed = 0
	local currentDirection: Vector3? = nil

	return function(dt: number)
		elapsed += dt
		local carrierPart = carrier :: BasePart
		local targetPart = getTarget()

		local desiredDirection = currentDirection
		if targetPart then
			local toTarget = targetPart.Position - carrierPart.Position
			if toTarget.Magnitude > 1e-3 then
				desiredDirection = toTarget.Unit
			end
		end
		desiredDirection = desiredDirection or carrierPart.CFrame.LookVector

		if currentDirection == nil or not turnRateRadPerSec then
			currentDirection = desiredDirection
		else
			currentDirection = Utils.rotateTowards(currentDirection, desiredDirection, turnRateRadPerSec * dt)
		end

		local spd = speed
		if type(spd) == "function" then
			spd = spd(elapsed, math.huge)
		end

		local newPosition = carrierPart.Position + (currentDirection :: Vector3) * spd * dt
		HitboxSpawner.SetCarrierCFrame(carrier, CFrame.lookAt(newPosition, newPosition + (currentDirection :: Vector3)))
	end
end

return Behaviors

ARQUIVO 4: sync/ServerStorage/Modules/Combat/Hitbox/HitboxPresets.luau (novo — o "helper" que guarda as configs prontas)

--!strict
-- HitboxPresets: combinações prontas de Spawner + Behaviors, NOMEADAS. Regra 2
-- do framework: a skill só referencia Presets.X e passa overrides pontuais —
-- nunca monta spawner+behavior na mão dentro de uma skill.

local HitboxSpawner = require(script.Parent.HitboxSpawner)
local Behaviors = require(script.Parent.HitboxBehaviors)

local Presets = {}

--[[
Anel de esferas se expandindo radialmente a partir de `center`.
@return { {hitbox: any, carrier: Instance} } - uma entrada por ponto do anel (conecte OnHit em cada uma)
]]
function Presets.ExpandingRing(casterEntity: any, center: CFrame, count: number, startRadius: number, expandRate: number, sphereRadius: number, duration: number)
	local results = {}

	for i = 1, count do
		local angle = (i / count) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * startRadius
		local pointCFrame = center + offset

		local hitbox, carrier = HitboxSpawner.Spawn(casterEntity, pointCFrame)
		hitbox:SetCastData({ CastType = "Spherecast", Radius = sphereRadius })

		local direction = offset.Magnitude > 1e-3 and offset.Unit or Vector3.xAxis
		local move = Behaviors.LinearMove(carrier, direction, expandRate, duration)
		local grow = Behaviors.ExpandUniform(hitbox, expandRate * 0.5)

		hitbox:OnUpdate(function(dt)
			move(dt)
			grow(dt)
		end)
		hitbox:OnStopped(function()
			HitboxSpawner.Cleanup(hitbox, carrier)
		end)

		hitbox:HitStart(duration)
		table.insert(results, { hitbox = hitbox, carrier = carrier })
	end

	return results
end

--[[ Projétil teleguiado: Spherecast homing num alvo, TTL fixo. ]]
function Presets.HomingBolt(casterEntity: any, origin: CFrame, getTarget: () -> BasePart?, speed: number, radius: number, duration: number, turnRateRadPerSec: number?)
	local hitbox, carrier = HitboxSpawner.Spawn(casterEntity, origin)
	hitbox:SetCastData({ CastType = "Spherecast", Radius = radius })

	hitbox:OnUpdate(Behaviors.Homing(carrier, getTarget, speed, turnRateRadPerSec))
	hitbox:OnStopped(function()
		HitboxSpawner.Cleanup(hitbox, carrier)
	end)

	hitbox:HitStart(duration)
	return hitbox, carrier
end

--[[ Leque parado que abre em Size num eixo — ex: corte de espada. ]]
function Presets.ExpandingCone(casterEntity: any, originCFrame: CFrame, axis: string, expandRate: number, maxSize: number, duration: number)
	local hitbox, carrier = HitboxSpawner.Spawn(casterEntity, originCFrame)
	hitbox:SetCastData({ CastType = "Blockcast", Size = Vector3.new(0.1, 0.1, 0.1) })

	hitbox:OnUpdate(Behaviors.ExpandDirectional(hitbox, axis, expandRate, maxSize))
	hitbox:OnStopped(function()
		HitboxSpawner.Cleanup(hitbox, carrier)
	end)

	hitbox:HitStart(duration)
	return hitbox, carrier
end

return Presets

VALIDAÇÃO: com Settings.Debug_Visible = true, Presets.ExpandingRing deve mostrar esferas crescendo E se afastando do centro ao mesmo tempo; Presets.HomingBolt contra um alvo em movimento deve curvar suave, não teleportar direção.
Sprint 5 — Ground/Air state em IMovement

ARQUIVO: sync/ServerScriptService/EntityData/EntityWrapper.luau

-- Na interface IMovement, adicione a assinatura:
function IMovement:GetAirState(): string end -- "Grounded" | "Jumping" | "Falling"

-- Em HumanoidMovement, adicione (perto de SetJumpForce):
local StateToAir = {
	[Enum.HumanoidStateType.Jumping] = "Jumping",
	[Enum.HumanoidStateType.Freefall] = "Falling",
}

function HumanoidMovement:GetAirState(): string
	local hum = self._character:GetHumanoid()
	if not hum then return "Grounded" end
	return StateToAir[hum:GetState()] or "Grounded"
end

-- Em NPCMovement, adicione:
function NPCMovement:GetAirState(): string
	local root = self._character:GetRoot()
	if not root then return "Grounded" end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }

	local rayLength = (root.Size.Y / 2) + 0.3
	local result = workspace:Raycast(root.Position, Vector3.new(0, -rayLength, 0), params)
	if result then
		return "Grounded"
	end

	-- Sem Humanoid não existe state machine nativa: aproxima por velocidade
	-- vertical. ATENÇÃO: isso raycasta a cada chamada — se algum dia virar
	-- hot-path chamado todo Heartbeat pra centenas de NPCs, cacheie o
	-- resultado por frame (hoje nada chama isso automaticamente, só quando
	-- uma skill pergunta).
	local verticalVelocity = root.AssemblyLinearVelocity.Y
	if verticalVelocity > 0.5 then
		return "Jumping"
	end
	return "Falling"
end

ARQUIVO: sync/ServerScriptService/EntityData/Components/MovementComponent.luau (adicionar ao ExposeAPI — será SUBSTITUÍDO no Sprint 6 abaixo, então trate esse trecho como transitório)

GetAirState = function(Component)
	return Component.MovementWrapper and Component.MovementWrapper:GetAirState() or "Grounded"
end,

VALIDAÇÃO: entity.GetAirState() deve retornar "Jumping" no frame exato após pular, "Falling" durante a queda, "Grounded" parado/andando. Repita pra um NPC sem Humanoid.
Sprint 6 — Floating (patch do Sprint 5)

Contexto: o Sprint 5 sozinho ignora entidades no ar sem velocidade vertical (flutuando de propósito — gravidade zerada, ou seguradas por uma Force IgnoreGravity). O wrapper não sabe de ActiveForces/GravityScale, então essa decisão precisa subir uma camada, pro MovementComponent.

ARQUIVO: sync/ServerScriptService/EntityData/EntityWrapper.luau

-- SUBSTITUA a função HumanoidMovement:GetAirState inteira por:

function HumanoidMovement:GetAirState(): string
	local hum = self._character:GetHumanoid()
	if not hum then return "Grounded" end

	local mapped = StateToAir[hum:GetState()]
	if mapped then
		return mapped
	end

	-- Humanoid:GetState() só distingue Jumping/Freefall explicitamente; outros
	-- estados (Running, Physics — usado quando uma Force externa toma conta —
	-- etc.) não dizem sozinhos se há contato com o chão. FloorMaterial é a
	-- forma barata e confiável do próprio Humanoid responder isso sem raycast.
	if hum.FloorMaterial == Enum.Material.Air then
		return "Falling"
	end
	return "Grounded"
end

-- NPCMovement:GetAirState() continua igual (raycast + heurística de
-- velocidade) — ela só responde "toco o chão? senão, parece subindo ou
-- descendo". A decisão de "Floating" fica numa camada acima.

ARQUIVO: sync/ServerScriptService/EntityData/Components/MovementComponent.luau

-- No topo, adicione (se ainda não tiver StateTable importado — confira antes
-- de duplicar):
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

-- Adicione este método:

--[[
Sobrepõe o palpite do wrapper (Grounded/Jumping/Falling, só física bruta) com
"Floating" quando algo está DELIBERADAMENTE suspendendo o eixo Y — uma Force
Hard com IgnoreGravity/Axes.Y, ou GravityScale <= 0 via Attributes. Sem isso,
uma entidade flutuando parada (velocidade vertical ~0) seria confundida com
"acabou de começar a cair", que é exatamente o furo reportado.
Grounded sempre vence — flutuar não anula estar de pé em cima de algo.
]]
function MovementComponent:GetAirState(): string
	local wrapperState = self.MovementWrapper and self.MovementWrapper:GetAirState() or "Grounded"
	if wrapperState == "Grounded" then
		return "Grounded"
	end

	for _, forceEntry in pairs(self.ActiveForces) do
		local data = forceEntry.Data
		local axes = data.Axes
		local claimsY = data.IgnoreGravity or (axes and axes.Y)
		if data.Hard and claimsY then
			return "Floating"
		end
	end

	if self.Entity:HasComponent(self.Entity.ComponentKey.Attributes) then
		if self.Entity.GetStat(StateTable.Enum.Stats.GravityScale, 1) <= 0 then
			return "Floating"
		end
	end

	return wrapperState
end

-- No ExposeAPI, TROQUE a linha antiga:
GetAirState = function(Component)
	return Component.MovementWrapper and Component.MovementWrapper:GetAirState() or "Grounded"
end,
-- POR:
GetAirState = function(Component) return Component:GetAirState() end,

VALIDAÇÃO: entidade com Force Hard+IgnoreGravity e velocidade vertical travada em 0 deve reportar "Floating", não "Falling". Parada no chão com GravityScale 0 deve reportar "Grounded".
Sprint 7 — Direção relativa + AimDirection (pitch)

Contexto: dois problemas resolvidos juntos. (1) Direction (intenção W/A/S/D) já existe como Vector3 mas nada classifica relativo ao facing. (2) LookDirection é achatada por contrato — bom pra combate, ruim pra skills de voo (Ult), que precisam do pitch da câmera. Solução: AimDirection (3D, cru) vira a fonte; LookDirection (plana) passa a ser DERIVADA dela, sem quebrar nenhum consumidor existente.

ARQUIVO 1: sync/ReplicatedStorage/Utils.luau (adicione estas duas funções)

--[[
Projeta moveDirection no espaço LOCAL 2D de facingDirection: X = componente
lateral (direita positiva), Z = componente frontal (frente positiva). Plano
XZ só (é INTENÇÃO de combate, não voo). Dono único da matemática de projeção
— tanto classifyDirection quanto Helper.BuildContext usam isto, não duplique.
]]
function Utils.worldToLocalPlanar(moveDirection, facingDirection)
	local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
	if flatMove.Magnitude < 0.1 then
		return Vector3.zero
	end
	flatMove = flatMove.Unit

	local flatFacing = Vector3.new(facingDirection.X, 0, facingDirection.Z)
	flatFacing = flatFacing.Magnitude < 0.1 and Vector3.new(0, 0, -1) or flatFacing.Unit

	local right = Vector3.new(flatFacing.Z, 0, -flatFacing.X)
	local forwardDot = flatMove:Dot(flatFacing)
	local rightDot = flatMove:Dot(right)

	return Vector3.new(rightDot, 0, forwardDot)
end

--[[
Classifica em octante: "Forward","ForwardRight","Right","BackRight","Back",
"BackLeft","Left","ForwardLeft", ou "None" se moveDirection for ~zero.
]]
function Utils.classifyDirection(moveDirection, facingDirection)
	local localVec = Utils.worldToLocalPlanar(moveDirection, facingDirection)
	if localVec.Magnitude < 0.05 then
		return "None"
	end

	local angle = math.deg(math.atan2(localVec.X, localVec.Z))

	if angle >= -22.5 and angle < 22.5 then return "Forward"
	elseif angle >= 22.5 and angle < 67.5 then return "ForwardRight"
	elseif angle >= 67.5 and angle < 112.5 then return "Right"
	elseif angle >= 112.5 and angle < 157.5 then return "BackRight"
	elseif angle >= 157.5 or angle < -157.5 then return "Back"
	elseif angle >= -157.5 and angle < -112.5 then return "BackLeft"
	elseif angle >= -112.5 and angle < -67.5 then return "Left"
	else return "ForwardLeft" end
end

ARQUIVO 2: sync/ServerScriptService/EntityData/Components/MovementComponent.luau

-- No topo, adicione:
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)

-- No MovementComponent.new, ADICIONE este campo (não remova LookDirection):
self.AimDirection = Vector3.new(0, 0, -1) -- 3D cru, inclui pitch da câmera

-- Adicione o método:
function MovementComponent:GetIntentDirection(): string
	local facing = self.LookDirection
	if facing.Magnitude < 0.1 then
		facing = self.LastDirection
	end
	if facing.Magnitude < 0.1 then
		facing = Vector3.new(0, 0, -1)
	end
	return Utils.classifyDirection(self.Direction, facing)
end

-- No ExposeAPI: REMOVA a linha "SetLookDirection = function(Component, dir) Component.LookDirection = dir end,"
-- e SUBSTITUA por:

SetAimDirection = function(Component, dir)
	Component.AimDirection = dir
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude > 1e-3 then
		Component.LookDirection = flat.Unit
	end
	-- Se flat.Magnitude for ~0 (olhando reto pra cima/baixo), mantém o último
	-- LookDirection válido: classificação de combo não pode ficar com vetor zero.
end,
GetAimDirection = function(Component) return Component.AimDirection end,
GetIntentDirection = function(Component) return Component:GetIntentDirection() end,

-- GetLookDirection continua EXATAMENTE como está (só que agora é derivado,
-- não escrito direto).

ARQUIVO 3: sync/StarterPlayer/StarterPlayerScripts/LookDirectionBroadcaster.client.luau

-- SUBSTITUA o corpo do RunService.RenderStepped:Connect por:

RunService.RenderStepped:Connect(function(dt)
	accumulated += dt
	if accumulated < SEND_RATE then
		return
	end
	accumulated = 0

	-- Antes achatava aqui (Y=0) antes de enviar. Agora manda o vetor 3D
	-- cheio — LookDirection (combate, plano) continua existindo, mas é
	-- DERIVADO no servidor a partir deste vetor. Isso é o que permite Ults
	-- de voo considerarem o pitch da câmera sem duplicar remote/rate-limit.
	local aim = camera.CFrame.LookVector

	if (aim - lastSent).Magnitude > MIN_DELTA then
		lastSent = aim
		RequestLook:FireServer(aim)
	end
end)

ARQUIVO 4: sync/ServerScriptService/Modules/SkillHandler.luau

-- SUBSTITUA HandleLookInput inteira por:

function SkillHandler.HandleLookInput(ID, look)
	local entityCore = DataManager.Get(ID)
	if not entityCore then return false end
	if typeof(look) ~= "Vector3" then return false end
	if look.Magnitude < 0.01 then return false end

	-- SetAimDirection guarda o vetor 3D cheio (pitch incluso) E deriva
	-- LookDirection (plano) internamente. Não achate aqui de novo — isso
	-- reintroduziria a mesma limitação que motivou essa mudança.
	entityCore.SetAimDirection(look.Unit)
	return true
end

-- Não mude InputValidator.server.luau — a validação de magnitude lá já
-- aceita vetores unitários 3D sem alteração nenhuma.

ARQUIVO 5: sync/ServerStorage/Modules/Combat/StateTable/Helper.luau

-- No topo, adicione:
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)

-- Em Helper.BuildContext, na declaração inicial de `context`, adicione o campo:
		direction = nil,

-- Logo depois do bloco "if source then ... end" e ANTES do cálculo de
-- parentLineage, adicione:

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

ARQUIVO 6: sync/ServerStorage/DataBase/SkillDatabase/Schema/Ultimate.luau

-- Na função Direction (dentro de self.forceID = self.Entity.AddForce({...})),
-- TROQUE:
	local look = ctx.Entity.GetLookDirection()
-- POR:
	local look = ctx.Entity.GetAimDirection()

-- Não mude Dash.luau — dash é intencionalmente plano (dash aéreo virando voo
-- não é o comportamento esperado por padrão), continua usando GetLookDirection.

VALIDAÇÃO: numa skill de teste, leia context.direction.Id andando pra frente/trás/lados enquanto ataca — deve bater com a tecla segurada. Aponte a câmera pra cima/baixo e use a Ult da Schema — ela deve agora subir/descer, não só andar plano.
Sprint 8 — Tether Force (grab/drag)

Contexto: AddForce só sabe "ande nessa direção nessa velocidade" (Direction × Speed). Isso serve pra dash, knockback, voo — mas NÃO serve pra "grude nesta posição relativa a outra entidade" (arrastar um alvo agarrado), porque isso é controle de POSIÇÃO, não de velocidade. Sem isso o resultado é "atrair", não "grudar": as duas entidades divergem com o tempo. Adicione um modo FollowTarget que usa um controlador proporcional de posição, reaproveitando 100% do orçamento de força/prioridade/eixos que já existe.

ARQUIVO: sync/ServerScriptService/Modules/Physics/MovementController.luau

-- Dentro de MovementController.ProcessEntity, no loop "for _, forceId in
-- orderedForceIds do", localize este trecho:

			hasAnyForce = true

			local elapsed = forceEntry.ElapsedTime
			local speed = data.Speed
			if type(speed) == "function" then
				speed = speed(elapsed, duration)
			end
			speed = speed or 0

			local rawDirection = data.Direction
			if type(rawDirection) == "function" then
				rawDirection = rawDirection(elapsed, duration, {
					Entity = entity,
					MovementComponent = comp,
				})
			end
			rawDirection = (rawDirection :: Vector3?) or Vector3.zero
			if rawDirection.Magnitude > 1e-4 then
				rawDirection = rawDirection.Unit -- servidor nunca confia na magnitude vinda de skill/rede
			end

			local direction = rawDirection
			if data.TurnRate and rawDirection.Magnitude > 1e-4 then
				forceEntry.CurrentDirection = forceEntry.CurrentDirection or rawDirection.Unit
				direction = Utils.rotateTowards(forceEntry.CurrentDirection, rawDirection, data.TurnRate * dt)
				forceEntry.CurrentDirection = direction
			elseif rawDirection.Magnitude > 1e-4 then
				forceEntry.CurrentDirection = rawDirection.Unit
			end

			local velocity = direction * speed

-- SUBSTITUA esse trecho inteiro por este (a lógica antiga vira o branch "else"):

			hasAnyForce = true

			local elapsed = forceEntry.ElapsedTime
			local velocity: Vector3
			local direction: Vector3

			if data.FollowTarget then
				-- Modo TETHER: em vez de "ande nessa direção nessa
				-- velocidade", persegue uma posição-alvo (outra entidade +
				-- offset) com um controlador proporcional. Direction como
				-- função sozinha NÃO consegue isso: sempre normaliza e usa
				-- Speed constante, então vira "atrair", não "grudar" — sem
				-- isso, arrastar um alvo diverge com o tempo porque as duas
				-- entidades resolvem força de forma independente.
				local followPart = data.FollowTarget
				if type(followPart) == "function" then
					followPart = followPart()
				end

				if followPart then
					local anchor = (followPart :: BasePart)
					local desiredPosition = data.FollowOffsetIsLocal
						and anchor.CFrame:PointToWorldSpace(data.FollowOffset or Vector3.zero)
						or (anchor.Position + (data.FollowOffset or Vector3.zero))

					local ownRoot = entity.GetRoot and entity.GetRoot()
					local currentPosition = ownRoot and ownRoot.Position or desiredPosition
					local toDesired = desiredPosition - currentPosition

					velocity = toDesired * (data.FollowResponsiveness or 10)

					if data.FollowMaxSpeed and velocity.Magnitude > data.FollowMaxSpeed then
						velocity = velocity.Unit * data.FollowMaxSpeed
					end

					direction = toDesired.Magnitude > 1e-4 and toDesired.Unit or (forceEntry.CurrentDirection or Vector3.new(0, 0, -1))
					forceEntry.CurrentDirection = direction
				else
					-- Alvo sumiu (morreu/destruído): zera velocidade até a Force expirar pelo Duration
					velocity = Vector3.zero
					direction = forceEntry.CurrentDirection or Vector3.new(0, 0, -1)
				end
			else
				local speed = data.Speed
				if type(speed) == "function" then
					speed = speed(elapsed, duration)
				end
				speed = speed or 0

				local rawDirection = data.Direction
				if type(rawDirection) == "function" then
					rawDirection = rawDirection(elapsed, duration, {
						Entity = entity,
						MovementComponent = comp,
					})
				end
				rawDirection = (rawDirection :: Vector3?) or Vector3.zero
				if rawDirection.Magnitude > 1e-4 then
					rawDirection = rawDirection.Unit
				end

				direction = rawDirection
				if data.TurnRate and rawDirection.Magnitude > 1e-4 then
					forceEntry.CurrentDirection = forceEntry.CurrentDirection or rawDirection.Unit
					direction = Utils.rotateTowards(forceEntry.CurrentDirection, rawDirection, data.TurnRate * dt)
					forceEntry.CurrentDirection = direction
				elseif rawDirection.Magnitude > 1e-4 then
					forceEntry.CurrentDirection = rawDirection.Unit
				end

				velocity = direction * speed
			end

-- NÃO mude mais nada no arquivo — o resto do loop (axes, IgnoreGravity,
-- priority, budget, faceRequest) já usa `velocity`/`direction` genéricos e
-- funciona sem alteração pros dois modos.

NOTA DE USO: FollowTarget é sobre PERSEGUIR UMA POSIÇÃO com física real (colide, tem massa) — diferente de HitboxBehaviors.Homing (Sprint 4), que move um carrier CINEMÁTICO sem colisão pra projéteis. São camadas diferentes de propósito, não duplicação.

VALIDAÇÃO: numa skill de teste, aplique em uma entidade B:

targetEntity.AddForce({
	Type = "Grabbed", Duration = 2, Hard = true, IgnoreGravity = true,
	RequiresControl = false,
	FollowTarget = function() return casterEntity.GetRoot() end,
	FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
	FollowResponsiveness = 15, FollowMaxSpeed = 60,
})

Ande com o caster em círculos — B deve se manter grudado 3 studs na frente dele, convergindo suave, sem divergir com o tempo.
Sprint 9 — Network Ownership (patch do Sprint 8)

Contexto: nenhum lugar do código chama SetNetworkOwner. Por padrão o Roblox atribui ownership física ao client mais próximo de uma part destravada. Durante um Dash ou um Tether ativo, se o client dono ainda tiver ownership, é ELE quem resolve as constraints que o servidor está tentando aplicar — abre desync visível e, no pior caso, um client modificado pode ignorar a força. Sério pra um framework "server-first" (Regra 10).

ARQUIVO: sync/ServerScriptService/Modules/Physics/ForceRig.luau

-- Adicione estes dois métodos (perto de Release):

--[[
Força ownership de física pro SERVIDOR enquanto uma Force Hard estiver ativa.
Sem isso, se o client dono da part ainda tiver ownership automática (padrão
do Roblox pra parts destravadas), é ELE quem resolve as constraints que o
servidor está tentando aplicar — abre desync visível e, no pior caso, um
client modificado pode simplesmente ignorar a força.
]]
function ForceRig:ClaimServerOwnership()
	if not self._ownershipClaimed then
		self._ownershipClaimed = true
		local ok = pcall(function()
			self.Root:SetNetworkOwner(nil)
		end)
		if not ok then
			self._ownershipClaimed = false
		end
	end
end

function ForceRig:ReleaseServerOwnership()
	if self._ownershipClaimed then
		self._ownershipClaimed = false
		pcall(function()
			self.Root:SetNetworkOwnershipAuto()
		end)
	end
end

ARQUIVO: sync/ServerScriptService/EntityData/EntityWrapper.luau

-- Na interface IMovement, adicione:
function IMovement:ClaimServerOwnership() end
function IMovement:ReleaseServerOwnership() end

-- Em HumanoidMovement, adicione:
function HumanoidMovement:ClaimServerOwnership()
	if self._rig then self._rig:ClaimServerOwnership() end
end
function HumanoidMovement:ReleaseServerOwnership()
	if self._rig then self._rig:ReleaseServerOwnership() end
end

-- Em NPCMovement, adicione (mesmo corpo — os dois wrappers guardam o rig no
-- mesmo campo _rig, não há o que abstrair sem acoplar as duas classes uma na
-- outra à toa):
function NPCMovement:ClaimServerOwnership()
	if self._rig then self._rig:ClaimServerOwnership() end
end
function NPCMovement:ReleaseServerOwnership()
	if self._rig then self._rig:ReleaseServerOwnership() end
end

ARQUIVO: sync/ServerScriptService/Modules/Physics/MovementController.luau

-- Dentro de ProcessEntity, logo ANTES do "local orderedForceIds = {}", adicione:
	local hasHardForceThisFrame = false

-- Dentro do loop "for _, forceId in orderedForceIds do", logo ONDE JÁ EXISTE
-- a linha "hasAnyForce = true" (depois dos `continue`s de força
-- expirada/sem controle), adicione na linha seguinte:
			hasHardForceThisFrame = hasHardForceThisFrame or hard

-- Logo DEPOIS do bloco inteiro "if tags.canDisplace then ... else ... end"
-- (antes do "for _, axis in AXES do" que soma softAccum), adicione:

	-- Reivindica ownership de servidor sempre que uma Force Hard está ativa
	-- (Dash, Tether/grab, voo). Cobre tanto o próprio caster quanto qualquer
	-- alvo sendo arrastado por outra entidade via AddForce cross-entity.
	if hasHardForceThisFrame then
		wrapper:ClaimServerOwnership()
	else
		wrapper:ReleaseServerOwnership()
	end

VALIDAÇÃO: durante um Dash ou um Tether ativo, root:GetNetworkOwner() deve retornar nil (servidor). Ao terminar a Force, deve voltar a permitir ownership automática.
Sprint 10 — Fork automático de TriggerSet em spawn

ARQUIVO: sync/ServerScriptService/EntityData/DataManager.luau

-- Troque a assinatura de DataManager.Create pra aceitar o 4º parâmetro:
function DataManager.Create(Entity, components : {}, configs : {[string]: any}?, parentEntity : any?)

	warn("===========VITALS============")

	if not Entity then
		warn("[DataManager] Entidade não recebida, func Create")
		return nil
	end
	if not components then
		warn("[DataManager] Componentes não recebidos, func Create")
		return nil
	end

	local id,entityType = DataManager.CreateID(Entity)
	warn(entityType,"Registrado, ID:",id)
	
	local previous = entityMap.players[id]
	if previous then
		previous:Destroy()
		entityMap.players[id] = nil
	end
	
	local Model
	local Player

	if typeof(Entity) == "table" then Model = Entity.Model; Player = Entity.Player
	else
		Model = Entity; Player = nil
	end
	local core = EntityCore.new(Model,entityType,id,Player)

	-- NOVO: herança de reações (Regra 4). TriggerSet.Fork() já suporta
	-- Inherit.Generations/Limit.Scope — só faltava alguém chamar isso na
	-- criação.
	if parentEntity and parentEntity._triggerSet then
		core._triggerSet = parentEntity._triggerSet:Fork()
	end

	local compList = {}
	for _,comp in pairs(components) do
		core:AddComponent(comp, configs and configs[comp] or {})
		compList[#compList + 1] = comp
	end
	warn("[DataManager] Componentes adicionados:", compList)

	if core:HasComponent(core.ComponentKey.Character) then
		core.SetEntity(Entity)
	end

	core:ComponentsLoaded()

	if typeof(Entity) == "table" then
		entityMap.players[id] = core
		Entity.Model:SetAttribute("EntityID",id)
		Entity.Player:SetAttribute("EntityID",id)
	elseif Entity:IsA("Model") then
		entityMap.NPCs[id] = core
		Entity:SetAttribute("EntityID",id)
	else
		warn("[DataManager] Entidade inválida, func Create")
		return nil
	end

	if core:HasComponent(core.ComponentKey.Movement) then
		core.SetMovement()
	end

	warn("===========VITALS END=============")
	return core
end

NOTA DE USO: Lineage (atribuição de dano pra quem começou a cadeia) é mecanismo SEPARADO do Fork acima. Pra funcionar junto num minion, a skill que cria o minion precisa passar Lineage = summonerRunner.Lineage ao chamar SkillRunner.new(...) pras habilidades DELE — isso já é suportado hoje, é disciplina de uso, não gap de framework.

VALIDAÇÃO: DataManager.Create(minionModel, comps, nil, summonerEntity) seguido de summonerEntity:Listen({Role=OUT, Breakpoint=onHit, Inherit={Generations=1}, Action=fn}) ANTES de criar o minion — fn deve disparar quando o MINION emite OUT.onHit, não só o summoner.
Sprint 11 — ComboWindow em BaseSkills

AÇÃO PRÉVIA OBRIGATÓRIA: existem DOIS arquivos BaseSkills.luau idênticos — sync/ServerStorage/DataBase/SkillDatabase/BaseSkills.luau e sync/ServerStorage/Modules/BaseSkills/BaseSkills.luau. Busque no projeto INTEIRO por "Modules.BaseSkills" ou qualquer require apontando pra ServerStorage.Modules.BaseSkills. Se ZERO resultados, delete a pasta sync/ServerStorage/Modules/BaseSkills/ inteira. Se achar algum uso, PARE e reporte antes de deletar qualquer coisa — não presuma.

ARQUIVO 1 (novo): sync/ServerStorage/DataBase/SkillDatabase/BaseSkills/ComboWindow.luau

--!strict
--[[
ComboWindow: marca/consome uma janela de combo curta e genérica. Skill A
declara "acabei de fazer algo", skill B lê e consome, sem acoplamento direto
entre A e B. Implementado em cima do Status genérico já existente — não
inventa sistema de tags paralelo.
]]

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local Enum = StateTable.Enum

local ComboWindow = {}

local function BuildMarkerStatus(markerName: string)
	return {
		data = {
			name = markerName,
			category = Enum.Categories.Internal,
			duration = 0,
		},
		callbacks = {},
	}
end

function ComboWindow.Mark(entity: any, markerName: string, window: number, payload: {[string]: any}?, source: any?): string?
	local statusData = BuildMarkerStatus(markerName)
	local id = entity.ApplyStatus(statusData, { Duration = window, Source = source, ID = markerName .. "_ComboWindow" })

	if id and payload then
		local entries = entity.GetStatus(markerName)
		local entry = entries and entries[1]
		if entry and entry.runner then
			entry.runner.skill.ComboPayload = payload
		end
	end

	return id
end

function ComboWindow.Consume(entity: any, markerName: string): {[string]: any}?
	local entries = entity.GetStatus(markerName)
	local entry = entries and entries[1]
	if not entry then
		return nil
	end

	local payload = (entry.runner and entry.runner.skill.ComboPayload) or {}
	entity.RemoveStatus(markerName)
	return payload
end

function ComboWindow.Peek(entity: any, markerName: string): boolean
	return entity.GetStatus(markerName) ~= nil
end

return ComboWindow

ARQUIVO 2: sync/ServerStorage/DataBase/SkillDatabase/BaseSkills.luau (substituir conteúdo inteiro)

local baseSkills = {
	ComboWindow = require(script.ComboWindow),

	dash = function(dir,speed)
		if not dir or dir.Magnitude == 0 then
			return Vector3.zero
		end
		return dir.Unit * speed
	end,

	CreateProjectile = function()
	end,

	MeleeHit = function()
	end,
}

return baseSkills

VALIDAÇÃO: no onEnd de um Dash existente, chame BaseSkills.ComboWindow.Mark(self.Entity, "RecentMobility", 0.6, {Direction=dir}, self.Runner). Numa segunda skill, no onStart, chame .Consume(...) — deve vir preenchido dentro de 0.6s, nil depois.
Sprint 12 — ControlComponent com Lock/Unlock

ARMADILHA CRÍTICA — LEIA ANTES DE ESCREVER: EntityCore.luau faz AutoRegisterComponents() na própria inicialização, que requer TODOS os arquivos de Components/, incluindo o novo. Se ControlComponent.luau tiver require(GlobalAntiCheat) no TOPO do arquivo, fecha um ciclo: EntityCore -> ControlComponent -> GlobalAntiCheat -> DataManager -> EntityCore, que quebra o boot inteiro. HitboxWrapper.new() já evita exatamente isso fazendo o require DENTRO da função — replique esse padrão aqui.

PRÉ-REQUISITO MANUAL: crie um RemoteEvent chamado ControlStateChanged dentro de ReplicatedStorage.RemoteEvents, no mesmo lugar dos outros RemoteEvents já existentes.

ARQUIVO 1: sync/ServerScriptService/Modules/GlobalAntiCheat.luau (substitua o arquivo inteiro por este)

--====================== GLOBAL ANTI CHEAT ======================--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local DataManager = require(Server.EntityData.DataManager)
local RunService = game:GetService("RunService")

local MIN_INPUT_INTERVAL = 0.015

local RemoteEvents = ReplicatedStorage.RemoteEvents
local ControlStateChanged = RemoteEvents:WaitForChild("ControlStateChanged")

local function notifyControlState(player: Player, isLocked: boolean)
	ControlStateChanged:FireClient(player, isLocked)
end

local AntiCheat = {}
local TrackedPlayers = {}
local connection

function AntiCheat.Init()
	if not connection then
		connection = RunService.Heartbeat:Connect(function(dt)
			AntiCheat._Update(dt)
		end)
		warn("[AntiCheat] Iniciado")
	end
end

--=====REGISTRO DE PLAYERS=====--

function AntiCheat.Register(Player)
	local ID = Player.Character and Player.Character:GetAttribute("EntityID")
	if not ID then return end
	local entityCore = DataManager.Get(ID)
	if not entityCore then return end

	TrackedPlayers[Player] = {
		LastPosition = nil,
		ID = ID,
		NativeID = ID,
		Locked = false,
		PreLockID = nil,
	}
end

function AntiCheat.Unregister(Player)
	TrackedPlayers[Player] = nil
end

--=====FUNÇÕES UTILITARIAS=====--

function AntiCheat.GetEntityID(Player)
	local tracked = TrackedPlayers[Player]
	return tracked and tracked.ID
end

function AntiCheat.GetControlledEntityId(Player)
	local tracked = TrackedPlayers[Player]
	if not tracked then return nil end
	if tracked.Locked then
		return tracked.PreLockID
	end
	return tracked.ID
end

--[[
Redireciona pra qual entidade o input desse player vai. Se o player estiver
Locked, NÃO deixa vazar input agora — só atualiza o que será restaurado no
Unlock. Sem essa checagem, um Possess acidental durante um Lock (cutscene)
furaria o corte.
]]
function AntiCheat.SetControlledEntity(Player, entityID)
	local tracked = TrackedPlayers[Player]
	if not tracked then return false end

	if tracked.Locked then
		tracked.PreLockID = entityID
		return true
	end

	tracked.ID = entityID
	return true
end

--[[
Corta TODO input desse player na raiz: GetEntityID passa a devolver nil, e
todo handler (HandleMovementInput, HandleLookInput, HandleIntent) já tem
guard "if not ID then return end" — zero verificação nova precisa ser
espalhada pelo resto do código.
]]
function AntiCheat.LockPlayerInput(Player)
	local tracked = TrackedPlayers[Player]
	if not tracked or tracked.Locked then return false end
	tracked.Locked = true
	tracked.PreLockID = tracked.ID
	tracked.ID = nil
	notifyControlState(Player, true)
	return true
end

function AntiCheat.UnlockPlayerInput(Player)
	local tracked = TrackedPlayers[Player]
	if not tracked or not tracked.Locked then return false end
	tracked.Locked = false
	tracked.ID = tracked.PreLockID
	tracked.PreLockID = nil
	notifyControlState(Player, false)
	return true
end

function AntiCheat.CheckInput(Player, LastInput)
	if os.clock() - LastInput < MIN_INPUT_INTERVAL then return nil end
	return AntiCheat.GetEntityID(Player)
end

--=====FUNÇÕES INTERNAS=====--

function AntiCheat.CheckPosition()
end

function AntiCheat.CheckNoClip()
end

function AntiCheat.UpdatePlayerInputData()
end

--=====HEARTBEAT=====--

function AntiCheat._Update(dt)
end

AntiCheat.Init()

return AntiCheat

ARQUIVO 2 (novo): sync/ServerScriptService/EntityData/Components/ControlComponent.luau

--[[
ControlComponent
================
Responsabilidade ÚNICA: identidade de QUEM manda numa entidade, e AUTORIDADE
de input (cortar a fonte, não a capacidade — canMove/canCast continuam
sendo trabalho do StatusComponent, de propósito, pra não duplicar autoridade).

Suporta: Player possui NPC, NPC/IA possui Player, Player troca em tempo real
entre 2 corpos seus (só chame Possess na entidade nova, a antiga fica sem
receber input sozinha).
]]

local ControlComponent = {}
ControlComponent.__index = ControlComponent

export type Controller = {
	Player: Player?,
	AI: boolean?,
	Brain: any?,
}

-- NÃO mova este require pro topo do arquivo — ver nota de require circular.
local function getAntiCheat()
	return require(game.ServerScriptService.Modules.GlobalAntiCheat)
end

-- Índice reverso GLOBAL: qual componente este Player está possuindo agora,
-- fora do próprio corpo nativo. Existe só pra cleanup em respawn/disconnect
-- sem iterar toda entidade viva.
local ActivePossessions: { [Player]: any } = {}

function ControlComponent.new(entity, config)
	local self = setmetatable({}, ControlComponent)
	self.Entity = entity
	self._native = entity.Player and { Player = entity.Player } or { AI = true }
	self.Controller = self._native
	self._priorControllerEntityId = nil
	self._locked = false
	return self
end

--[[
Transfere o controle desta entidade pro `controller` informado. Se esta
entidade tem um player NATIVO e quem está tomando conta NÃO é esse player
nativo, o nativo é cortado da própria entidade automaticamente (senão o WASD
dele corre em paralelo com quem tomou posse — condição de corrida real).
]]
function ControlComponent:Possess(controller: Controller)
	if self._native.Player and controller.Player ~= self._native.Player then
		getAntiCheat().LockPlayerInput(self._native.Player)
	end

	if controller.Player then
		-- Lembra o que esse player controlava ANTES, pra Release() devolver
		-- certo mesmo em possessão encadeada (A possui B, depois A possui C
		-- — Release de C devolve A pra B, não direto pro nativo de A).
		self._priorControllerEntityId = getAntiCheat().GetControlledEntityId(controller.Player)

		if self.Controller.Player and self.Controller.Player ~= controller.Player then
			ActivePossessions[self.Controller.Player] = nil
		end

		getAntiCheat().SetControlledEntity(controller.Player, self.Entity.ID)
		ActivePossessions[controller.Player] = self
	end

	self.Controller = controller
end

function ControlComponent:Release()
	if self.Controller.Player then
		ActivePossessions[self.Controller.Player] = nil
		if self._priorControllerEntityId then
			getAntiCheat().SetControlledEntity(self.Controller.Player, self._priorControllerEntityId)
			self._priorControllerEntityId = nil
		end
	end

	if self._native.Player then
		getAntiCheat().UnlockPlayerInput(self._native.Player)
	end

	self.Controller = self._native
end

--[[
Corta o controlador ATUAL sem reatribuir a ninguém (cutscene, QTE, etc). Se
o controlador for Player, corta na fonte via AntiCheat. Se for AI, desliga o
Brain (SetEnabled é stub-seguro via ComponentStubs mesmo antes do AIComponent
existir — chama warn e não faz nada, não quebra).
]]
function ControlComponent:Lock()
	if self._locked then return end
	self._locked = true

	if self.Controller.Player then
		getAntiCheat().LockPlayerInput(self.Controller.Player)
	end
	if self.Controller.AI and self.Entity:HasComponent(self.Entity.ComponentKey.AI) then
		self.Entity.SetEnabled(false)
	end
end

function ControlComponent:Unlock()
	if not self._locked then return end
	self._locked = false

	if self.Controller.Player then
		getAntiCheat().UnlockPlayerInput(self.Controller.Player)
	end
	if self.Controller.AI and self.Entity:HasComponent(self.Entity.ComponentKey.AI) then
		self.Entity.SetEnabled(true)
	end
end

function ControlComponent:GetController(): Controller
	return self.Controller
end

function ControlComponent:IsControlledBy(player: Player): boolean
	return self.Controller.Player == player
end

function ControlComponent:IsAIControlled(): boolean
	return self.Controller.AI == true
end

function ControlComponent:Destroy()
	if self.Controller.Player then
		ActivePossessions[self.Controller.Player] = nil
	end
	self.Entity = nil
end

local ExposeAPI = {
	Possess = function(component, ...) return component:Possess(...) end,
	Release = function(component) return component:Release() end,
	Lock = function(component) return component:Lock() end,
	Unlock = function(component) return component:Unlock() end,
	GetController = function(component) return component:GetController() end,
	IsControlledBy = function(component, ...) return component:IsControlledBy(...) end,
	IsAIControlled = function(component) return component:IsAIControlled() end,
}

return {
	new = ControlComponent.new,
	ExposeAPI = ExposeAPI,
	GetPossessionOf = function(player: Player)
		return ActivePossessions[player]
	end,
}

LIMITAÇÃO CONHECIDA (documente, não resolva agora): se uma entidade JÁ possuída for possuída de novo por OUTRO controller ("roubo" de possessão), o controller anterior perde o tracking de retorno. Se seu jogo permitir esse roubo, chame Release() no controller anterior explicitamente ANTES de possuir de novo.

ARQUIVO 3: sync/ServerScriptService/Scripts/Main.server.luau

-- No topo, adicione:
local ControlComponent = require(ServerScriptService.EntityData.Components.ControlComponent)

-- Em onCharacterAdded, ANTES de DataManager.Create, adicione:
	local possessed = ControlComponent.GetPossessionOf(player)
	if possessed then
		possessed:Release()
	end

-- Em Players.PlayerRemoving, ANTES de DataManager.Remove, adicione:
	local possessed = ControlComponent.GetPossessionOf(player)
	if possessed then
		possessed:Release()
	end

VALIDAÇÃO: PlayerA possui NPC via npcCore.Possess({Player=PlayerA}) — input de A deve mover o NPC. Chame npcCore.Lock() — nem A nem o NPC devem responder a input algum. Unlock() deve devolver exatamente como estava. Mate PlayerA (respawn) enquanto possui o NPC — GetPossessionOf deve limpar sozinho.
Sprint 13 — Link/Unlink (extensão do ControlComponent)

Contexto: primitivo genérico pra "2 corpos sob a mesma intenção de input" sem mexer no modelo de 1-ID-por-player do AntiCheat. MirrorMovement/MirrorLook cobrem o caso "stick compartilhado"; comando discreto pra um 2º corpo (ex: minions) já funciona hoje chamando SkillHandler.HandleIntent nele direto, sem precisar de Link nenhum.

ARQUIVO: sync/ServerScriptService/EntityData/Components/ControlComponent.luau (adicione estes métodos — o resto do arquivo do Sprint 12 continua igual)

--[[
Linka outra entidade a esta: MirrorMovement/MirrorLook fazem o input de
movimento/mira que ESTA entidade recebe também ser aplicado na `otherEntity`,
sem duplicar handler nenhum — é um fan-out opcional em cima do pipeline já
existente. Precisa que otherEntity já tenha ControlComponent.
]]
function ControlComponent:LinkTo(otherEntity: any, opts: {MirrorMovement: boolean?, MirrorLook: boolean?}?)
	local otherControl = otherEntity:GetComponent(otherEntity.ComponentKey.Control)
	if not otherControl then
		warn("[ControlComponent] LinkTo: entidade alvo não tem ControlComponent")
		return
	end

	opts = opts or {}
	self._links = self._links or {}
	self._links[otherControl] = {
		MirrorMovement = opts.MirrorMovement or false,
		MirrorLook = opts.MirrorLook or false,
		TargetEntity = otherEntity,
	}
end

function ControlComponent:Unlink(otherEntity: any)
	local otherControl = otherEntity:GetComponent(otherEntity.ComponentKey.Control)
	if self._links and otherControl then
		self._links[otherControl] = nil
	end
end

--[[ @param filterKey "MirrorMovement" | "MirrorLook" | nil (nil = todos os links) ]]
function ControlComponent:GetLinkedEntities(filterKey: string?): {any}
	if not self._links then return {} end
	local result = {}
	for _, linkData in pairs(self._links) do
		if not filterKey or linkData[filterKey] then
			table.insert(result, linkData.TargetEntity)
		end
	end
	return result
end

-- No ExposeAPI, adicione:
	LinkTo = function(component, ...) return component:LinkTo(...) end,
	Unlink = function(component, ...) return component:Unlink(...) end,
	GetLinkedEntities = function(component, ...) return component:GetLinkedEntities(...) end,

-- Em Destroy, adicione a limpeza:
	self._links = nil

ARQUIVO: sync/ServerScriptService/Modules/SkillHandler.luau

-- SUBSTITUA HandleMovementInput inteira por:

function SkillHandler.HandleMovementInput(ID, dir)
	local entityCore = DataManager.Get(ID)
	if not entityCore then return false end
	if typeof(dir) ~= "Vector3" then return false end

	local flat = Vector3.new(dir.X, 0, dir.Z)
	local n = flat.Magnitude > 0.01 and flat.Unit or Vector3.zero

	entityCore.SetDirection(n)

	-- Fan-out opcional pra corpos linkados. Custo zero quando ninguém usa
	-- Link — HasComponent é um lookup de tabela.
	if entityCore:HasComponent(entityCore.ComponentKey.Control) then
		for _, linkedEntity in ipairs(entityCore.GetLinkedEntities("MirrorMovement")) do
			if linkedEntity:HasComponent(linkedEntity.ComponentKey.Movement) then
				linkedEntity.SetDirection(n)
			end
		end
	end

	return n.Magnitude > 0
end

-- SUBSTITUA HandleLookInput inteira por:

function SkillHandler.HandleLookInput(ID, look)
	local entityCore = DataManager.Get(ID)
	if not entityCore then return false end
	if typeof(look) ~= "Vector3" then return false end
	if look.Magnitude < 0.01 then return false end

	entityCore.SetAimDirection(look.Unit)

	if entityCore:HasComponent(entityCore.ComponentKey.Control) then
		for _, linkedEntity in ipairs(entityCore.GetLinkedEntities("MirrorLook")) do
			if linkedEntity:HasComponent(linkedEntity.ComponentKey.Movement) then
				linkedEntity.SetAimDirection(look.Unit)
			end
		end
	end

	return true
end

-- (Isso pressupõe o Sprint 7 — SetAimDirection — já aplicado. Se ainda não
-- aplicou, troque "SetAimDirection" por "SetLookDirection" nos dois lugares.)

VALIDAÇÃO: primaryEntity.LinkTo(secondaryEntity, {MirrorMovement=true}) e mande HandleMovementInput na primária — a secundária deve receber a mesma direção. Unlink deve parar o espelhamento imediatamente.
Sprint 14 — CameraOverride (shiftlock + soft target-lock)

ARQUIVO 1 (novo): sync/StarterPlayer/StarterPlayerScripts/CameraOverride.luau

--[[
CameraOverride (CLIENTE)
========================
Over-the-shoulder com soft target-lock na entidade mais próxima num cone
frontal. Soft = suaviza a MIRA, não trava a rotação como MOBA — travamento
duro conflitaria com LookDirectionBroadcaster (Sprint 7), que manda a
direção da câmera pro servidor como INTENÇÃO de combate/voo.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraOverride = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Config = {
	ShoulderOffset = Vector3.new(1.8, 0.4, 0),
	Distance = 4.5,
	FollowResponsiveness = 12,
	TargetLockRadius = 45,
	TargetLockConeAngleDeg = 35,
	TargetLockSoftness = 6,
	TargetSearchInterval = 0.15,
}

local active = false
local currentTarget: Model? = nil
local connection: RBXScriptConnection? = nil
local toggleKey = Enum.KeyCode.C -- AJUSTE conforme seu InputConfig
local lastTargetSearch = 0

local function getCharacterParts()
	local character = player.Character
	if not character then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function findSoftLockTarget(root: BasePart): Model?
	local bestTarget: Model? = nil
	local bestScore = -math.huge
	local camDirection = camera.CFrame.LookVector

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj ~= player.Character and obj:GetAttribute("EntityID") then
			local targetRoot = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
			if targetRoot then
				local toTarget = (targetRoot :: BasePart).Position - root.Position
				local distance = toTarget.Magnitude
				if distance > 0.1 and distance <= Config.TargetLockRadius then
					local angle = math.deg(math.acos(math.clamp(camDirection:Dot(toTarget.Unit), -1, 1)))
					if angle <= Config.TargetLockConeAngleDeg then
						local score = -angle - (distance * 0.1)
						if score > bestScore then
							bestScore = score
							bestTarget = obj
						end
					end
				end
			end
		end
	end

	return bestTarget
end

local function update(dt: number)
	local root, humanoid = getCharacterParts()
	if not root or not humanoid then return end

	local facing = root.CFrame
	local desiredPosition = facing.Position
		+ facing.RightVector * Config.ShoulderOffset.X
		+ Vector3.new(0, Config.ShoulderOffset.Y, 0)
		- facing.LookVector * Config.Distance

	local lookAtPosition = root.Position + Vector3.new(0, 1.5, 0)

	local now = os.clock()
	if now - lastTargetSearch >= Config.TargetSearchInterval then
		lastTargetSearch = now
		currentTarget = findSoftLockTarget(root)
	end

	if currentTarget then
		local targetRoot = currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget.PrimaryPart
		if targetRoot then
			local blend = 1 - math.exp(-Config.TargetLockSoftness * dt)
			lookAtPosition = lookAtPosition:Lerp((targetRoot :: BasePart).Position, blend)
		end
	end

	local followBlend = 1 - math.exp(-Config.FollowResponsiveness * dt)
	local newPosition = camera.CFrame.Position:Lerp(desiredPosition, followBlend)

	camera.CFrame = CFrame.lookAt(newPosition, lookAtPosition)
end

function CameraOverride.Enable()
	if active then return end
	active = true
	camera.CameraType = Enum.CameraType.Scriptable
	connection = RunService.RenderStepped:Connect(update)
end

function CameraOverride.Disable()
	if not active then return end
	active = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	camera.CameraType = Enum.CameraType.Custom
end

function CameraOverride.Toggle()
	if active then CameraOverride.Disable() else CameraOverride.Enable() end
end

function CameraOverride.IsActive(): boolean
	return active
end

function CameraOverride.GetCurrentTarget(): Model?
	return currentTarget
end

function CameraOverride.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == toggleKey then
			CameraOverride.Toggle()
		end
	end)

	-- Reage ao ControlComponent:Lock() (Sprint 12): se o server travar o
	-- controle desse player, desliga a câmera custom e lembra se ela estava
	-- ligada, pra devolver do jeito que estava no Unlock — não força ligado.
	local ControlStateChanged = ReplicatedStorage.RemoteEvents:WaitForChild("ControlStateChanged")
	local activeBeforeLock = false

	ControlStateChanged.OnClientEvent:Connect(function(isLocked: boolean)
		if isLocked then
			activeBeforeLock = active
			CameraOverride.Disable()
		elseif activeBeforeLock then
			CameraOverride.Enable()
		end
	end)
end

return CameraOverride

ARQUIVO 2 (novo): sync/StarterPlayer/StarterPlayerScripts/CameraOverrideLoader.client.luau

require(script.Parent.CameraOverride).Init()

VALIDAÇÃO: tecla de toggle assume over-the-shoulder; perto de um NPC com EntityID, mira gruda suave no cone frontal sem travar rotação inteira. Chame ControlComponent:Lock() nesse player do servidor — câmera deve voltar sozinha pra Custom; Unlock() deve reativar se estava ativa antes.
Sprint 15 — AIComponent (base)

ARQUIVO 1 (novo): sync/ServerScriptService/Modules/AI/AIScheduler.luau

--[[ Roda o Brain de todo AIComponent ativo num único Heartbeat (Regra 6 —
mesmo padrão de MovementController: nada de 1 conexão por entidade). ]]
local RunService = game:GetService("RunService")

local AIScheduler = {}
local tracked = {}

function AIScheduler.Register(component)
	tracked[component] = true
end

function AIScheduler.Unregister(component)
	tracked[component] = nil
end

RunService.Heartbeat:Connect(function(dt)
	for component in pairs(tracked) do
		if component.Enabled and component.Brain then
			local ok, err = pcall(component.Brain, component.Entity, dt)
			if not ok then
				warn("[AIScheduler] Erro no Brain de", tostring(component.Entity and component.Entity.ID), ":", err)
			end
		end
	end
end)

return AIScheduler

ARQUIVO 2 (novo): sync/ServerScriptService/EntityData/Components/AIComponent.luau

--[[
AIComponent
===========
Base MÍNIMA: um "Brain" (function(entity, dt)) chamado a cada Heartbeat, cuja
responsabilidade é produzir InputEvents exatamente como um player faria:

	SkillHandler.HandleIntent(entity.ID, Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate))
	SkillHandler.HandleMovementInput(entity.ID, direction)
	SkillHandler.HandleLookInput(entity.ID, lookDirection)

Mesmo pipeline que o InputValidator usa pro player — zero hardcode de "isso é
NPC" no framework de combate.
]]

local AIScheduler = require(game.ServerScriptService.Modules.AI.AIScheduler)

local AIComponent = {}
AIComponent.__index = AIComponent

function AIComponent.new(entity, config)
	local self = setmetatable({}, AIComponent)
	self.Entity = entity
	self.Brain = config.Brain or nil
	self.Enabled = config.Enabled ~= false
	return self
end

function AIComponent:SetBrain(brainFn: ((any, number) -> ())?)
	self.Brain = brainFn
end

function AIComponent:SetEnabled(enabled: boolean)
	self.Enabled = enabled
end

function AIComponent:OnAdded()
	AIScheduler.Register(self)
end

function AIComponent:Destroy()
	AIScheduler.Unregister(self)
	self.Entity = nil
	self.Brain = nil
end

local ExposeAPI = {
	SetBrain = function(component, ...) return component:SetBrain(...) end,
	SetEnabled = function(component, ...) return component:SetEnabled(...) end,
}

return {
	new = AIComponent.new,
	ExposeAPI = ExposeAPI,
}

NOTA DE INTEGRAÇÃO COM SPRINT 12: quando um Player possui uma entidade com AIComponent, o ControlComponent:Possess NÃO desliga o Brain automaticamente de propósito (Regra 20 — nem toda entidade possuível tem IA, não presuma). Se quiser esse comportamento, chame entity.SetEnabled(false) manualmente no momento do Possess do seu jogo, e SetEnabled(true) no Release.

VALIDAÇÃO: entity.SetBrain(function(e, dt) print("penso, logo existo", e.ID) end) deve printar todo Heartbeat até SetEnabled(false) ou Destroy().
Sprint 16 — SoundManager

ARQUIVO (novo): sync/ServerScriptService/Modules/Audio/SoundManager.luau

local Debris = game:GetService("Debris")

local SoundManager = {}

local DEFAULT_ROLLOFF_MIN = 5
local DEFAULT_ROLLOFF_MAX = 150

local function normalizeId(soundId: string): string
	if soundId:sub(1, 13) == "rbxassetid://" then
		return soundId
	end
	return "rbxassetid://" .. soundId
end

local function buildSound(soundId: string, config: {[string]: any}): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = normalizeId(soundId)
	sound.Volume = config.Volume or 0.65
	sound.Pitch = config.Pitch or 1
	sound.RollOffMinDistance = config.RollOffMin or DEFAULT_ROLLOFF_MIN
	sound.RollOffMaxDistance = config.RollOffMax or DEFAULT_ROLLOFF_MAX
	sound.Looped = config.Looped or false
	return sound
end

function SoundManager.PlayOneShot3D(position: Vector3, soundId: string, config: {[string]: any}?)
	config = config or {}

	local anchor = Instance.new("Part")
	anchor.Name = "_SoundManagerAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local sound = buildSound(soundId, config)
	sound.Parent = anchor
	sound.Ended:Once(function() anchor:Destroy() end)
	sound:Play()

	Debris:AddItem(anchor, config.MaxLifetime or 10)
end

function SoundManager.PlayAttached(instance: Instance, soundId: string, config: {[string]: any}?, key: string?)
	config = config or {}

	local sound = key and instance:FindFirstChild(key)

	if not sound then
		sound = buildSound(soundId, config)
		if key then sound.Name = key end
		sound.Parent = instance
	else
		(sound :: Sound).SoundId = normalizeId(soundId)
	end

	(sound :: Sound):Play()

	if not key then
		(sound :: Sound).Ended:Once(function() sound:Destroy() end)
		Debris:AddItem(sound, config.MaxLifetime or 10)
	end

	return sound
end

return SoundManager

NOTA: som 2D/UI (stinger global sem posição no mundo) precisa de um RemoteEvent — mesmo padrão exato do UpdateHealthBar que já existe.

VALIDAÇÃO: SoundManager.PlayOneShot3D(Vector3.new(0,5,0), "SEU_ID_AQUI") deve tocar posicional e limpar o anchor sozinho depois.
Sprint 17 — VFXManager

PRÉ-REQUISITO MANUAL: adicione um RemoteEvent chamado PlayVFX dentro de ReplicatedStorage.RemoteEvents, no mesmo lugar dos outros já existentes.

ARQUIVO 1 (novo, servidor): sync/ServerScriptService/Modules/VFX/VFXManager.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayVFX = ReplicatedStorage.RemoteEvents:WaitForChild("PlayVFX")

local VFXManager = {}

function VFXManager.PlayAll(effectName: string, data: {[string]: any})
	PlayVFX:FireAllClients(effectName, data)
end

function VFXManager.PlayNear(position: Vector3, radius: number, effectName: string, data: {[string]: any})
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and ((root :: BasePart).Position - position).Magnitude <= radius then
			PlayVFX:FireClient(player, effectName, data)
		end
	end
end

return VFXManager

ARQUIVO 2 (novo, cliente): sync/StarterPlayer/StarterPlayerScripts/VFXRegistry.luau

local Debris = game:GetService("Debris")

local Registry = {}

Registry.GenericImpact = function(data: {[string]: any})
	local position = data.Position :: Vector3?
	if not position then return end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparks_main.dds"
	emitter.Lifetime = NumberRange.new(0.2, 0.4)
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(8, 14)
	emitter.Parent = anchor

	emitter:Emit(data.Count or 12)
	Debris:AddItem(anchor, 1)
end

return Registry

ARQUIVO 3 (novo, cliente): sync/StarterPlayer/StarterPlayerScripts/VFXPlayer.client.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(script.Parent.VFXRegistry)

local PlayVFX = ReplicatedStorage.RemoteEvents:WaitForChild("PlayVFX")

PlayVFX.OnClientEvent:Connect(function(effectName: string, data: {[string]: any})
	local builder = Registry[effectName]
	if not builder then
		warn("[VFXPlayer] Efeito não registrado:", effectName)
		return
	end

	local ok, err = pcall(builder, data)
	if not ok then
		warn("[VFXPlayer] Erro construindo efeito", effectName, ":", err)
	end
end)

VALIDAÇÃO: VFXManager.PlayAll("GenericImpact", {Position=Vector3.new(0,5,0)}) do servidor deve estourar partículas em todos os clientes, na posição certa.
Sprint 18 — Dynamic AddComponent + MinionFactory

ARQUIVO: sync/ServerScriptService/EntityData/EntityCore.luau

-- SUBSTITUA a assinatura e o corpo de AddComponent por:

function EntityCore:AddComponent(componentName : string, config : {[string]: any}?, callOnAddedNow: boolean?)
	if self.Components[componentName] then
		warn("[EntityCore] Componente já existe:", componentName)
		return self.Components[componentName]
	end

	if not ComponentRegistry[componentName] then
		warn("[EntityCore] Componente não registrado:", componentName)
		return nil
	end

	local component = ComponentRegistry[componentName].new(self, config or {})
	self.Components[componentName] = component

	if ComponentRegistry[componentName].ExposeAPI then
		for methodName, method in pairs(ComponentRegistry[componentName].ExposeAPI) do
			self[methodName] = function(...)
				local n = select("#", ...)
				if n > 0 and (...) == self then
					error(
						string.format(
							"[EntityCore] '%s' é API de componente — chame com '.' (entity.%s(...)), não ':' (entity:%s(...))",
							methodName, methodName, methodName
						),
						2
					)
				end
				return method(component, ...)
			end
		end
	end

	-- Add dinâmico PÓS-criação (entidade já passou por ComponentsLoaded): sem
	-- isso, um componente adicionado depois nunca teria seu OnAdded chamado,
	-- diferente do lote inicial. Callers existentes (DataManager.Create)
	-- continuam passando só 2 args — zero mudança de comportamento pra eles;
	-- ComponentsLoaded continua sendo quem dispara OnAdded do lote inicial.
	if callOnAddedNow and component.OnAdded then
		component:OnAdded()
	end

	return component
end

VALIDAÇÃO: entidade JÁ criada, chame entity:AddComponent("AI", {}, true) — o AIComponent deve aparecer registrado no AIScheduler imediatamente (Brain rodando no próximo Heartbeat), sem precisar recriar a entidade inteira.

ARQUIVO (novo): sync/ServerStorage/Modules/MinionFactory.luau

--!strict
--[[
MinionFactory: reduz o boilerplate de "invocar uma entidade descartável"
SEM decidir por você quais componentes ela deve ter — você declara um
Blueprint (Regra 2: reutilizável) numa pasta Blueprints/, a factory só monta
o Model+DataManager.Create com base nele. Mesmo padrão de auto-scan que
SkillDatabase/CharacterDatabase já usam, não invento convenção nova.
NÃO substitui DataManager.Create: se seu caso não encaixa num Blueprint,
chame DataManager.Create direto — sem bloqueio nenhum (Regra 3).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local DataManager = require(ServerScriptService.EntityData.DataManager)

export type Blueprint = {
	Components: {string},
	Configs: {[string]: any}?,
	Model: Instance?,
	BuildModel: ((cframe: CFrame) -> Model)?,
}

local MinionFactory = {}
local Blueprints: {[string]: Blueprint} = {}

local blueprintsFolder = script:FindFirstChild("Blueprints")
if blueprintsFolder then
	for _, moduleScript in ipairs(blueprintsFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") then
			local ok, blueprint = pcall(require, moduleScript)
			if ok then
				Blueprints[moduleScript.Name] = blueprint :: Blueprint
			else
				warn("[MinionFactory] Erro carregando blueprint", moduleScript.Name, blueprint)
			end
		end
	end
end

--[[ Registro em runtime, se preferir não usar a pasta Blueprints/. ]]
function MinionFactory.Register(name: string, blueprint: Blueprint)
	Blueprints[name] = blueprint
end

--[[
@param blueprintName - nome do módulo em Blueprints/ (ou registrado via Register)
@param cframe - onde spawnar
@param parentEntity any? - se fornecido, faz Fork de TriggerSet (Sprint 10)
@return EntityCore ou nil
]]
function MinionFactory.Spawn(blueprintName: string, cframe: CFrame, parentEntity: any?): any?
	local blueprint = Blueprints[blueprintName]
	if not blueprint then
		warn("[MinionFactory] Blueprint não registrado:", blueprintName)
		return nil
	end

	local model: Model
	if blueprint.BuildModel then
		model = blueprint.BuildModel(cframe)
	elseif blueprint.Model then
		model = (blueprint.Model :: Instance):Clone() :: Model
		model:PivotTo(cframe)
	else
		warn("[MinionFactory] Blueprint sem Model nem BuildModel:", blueprintName)
		return nil
	end
	model.Parent = workspace

	local components = {}
	for _, name in ipairs(blueprint.Components) do
		components[name] = name
	end

	return DataManager.Create(model, components, blueprint.Configs, parentEntity)
end

return MinionFactory

ARQUIVO (novo): sync/ServerStorage/Modules/MinionFactory/Blueprints/TestMinion.luau

return {
	Components = { "Character", "Health", "Movement" },
	Configs = {},
	BuildModel = function(cframe: CFrame): Model
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(1.5, 1.5, 1)
		root.Color = Color3.fromRGB(230, 180, 60)
		root.CFrame = cframe
		root.Parent = model
		model.PrimaryPart = root
		return model
	end,
}

VALIDAÇÃO: MinionFactory.Spawn("TestMinion", CFrame.new(0,5,0), summonerEntity) deve devolver um EntityCore válido, com Fork de TriggerSet já aplicado.
Sprint 19 — TestHarness (script de automação)

ARQUIVO (novo): sync/ServerScriptService/Scripts/Tests/TestHarness.luau

--!strict
-- TestHarness: runner mínimo de testes server-side, assert+warn, mesmo
-- estilo que o resto do projeto já usa (não traz TestEZ nem dependência
-- nova — Regra 3, não presuma que você quer isso).

local TestHarness = {}
local results = { passed = 0, failed = 0 }

function TestHarness.Run(name: string, fn: (t: any) -> ())
	local t = {}
	function t.assert(condition: boolean, message: string?)
		if not condition then
			error(message or "assertion failed", 0)
		end
	end
	function t.wait(seconds: number)
		task.wait(seconds)
	end
	function t.log(...)
		print("  ", ...)
	end

	print(string.format("[TEST] %s...", name))
	local ok, err = pcall(fn, t)

	if ok then
		results.passed += 1
		print(string.format("[PASS] %s", name))
	else
		results.failed += 1
		warn(string.format("[FAIL] %s — %s", name, tostring(err)))
	end
end

function TestHarness.Summary(): boolean
	print(string.format("[TestHarness] %d passou, %d falhou", results.passed, results.failed))
	return results.failed == 0
end

return TestHarness

Sprint 20 — IntegrationTests (testes isolados automatizados)

ARQUIVO (novo): sync/ServerScriptService/Scripts/Tests/IntegrationTests.server.luau

--[[
Roda uma vez no boot (Studio/PlayEmpty). Cada teste cria e limpa suas
próprias entidades descartáveis. Ferramenta de sprint — não deixe isso
rodando num lugar que vá pra produção real.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local TestHarness = require(script.Parent.TestHarness)
local DataManager = require(ServerScriptService.EntityData.DataManager)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)

local function makeDummy(cframe: CFrame, components: {string}?, configs: {[string]: any}?, parentEntity: any?)
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = cframe
	root.Anchored = false
	root.Parent = model
	model.PrimaryPart = root
	model.Parent = workspace

	return DataManager.Create(model, components or { "Character", "Health", "Movement" }, configs, parentEntity)
end

local function cleanup(entity: any)
	if entity and entity.Instance then
		entity.Instance:Destroy()
	end
end

task.wait(2) -- deixa o resto do jogo terminar de bootar

TestHarness.Run("Sprint 1 — Block determinístico", function(t)
	local dummy = makeDummy(CFrame.new(0, 10, 0), { "Character", "Health", "Movement", "Status" })

	dummy.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "FirstBlock" })
	task.wait(0.05)
	dummy.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 5, ID = "SecondBlock" })

	local _, owners = dummy.GetActiveTags()
	local blockOwner = owners[StateTable.Enum.Tags.block]

	t.assert(blockOwner ~= nil, "Nenhum dono de block resolvido")
	t.assert(blockOwner.data.ID == "SecondBlock", "Dono resolvido não é o mais recente")

	cleanup(dummy)
end)

TestHarness.Run("Sprint 6 — Floating não confunde com Falling", function(t)
	local dummy = makeDummy(CFrame.new(0, 50, 0), { "Character", "Health", "Movement" })
	dummy.SetMovement()
	task.wait(0.1)

	local stateBeforeForce = dummy.GetAirState()
	t.log("Estado sem Force:", stateBeforeForce)
	t.assert(stateBeforeForce == "Falling" or stateBeforeForce == "Jumping", "Esperava queda livre sem Force ativa")

	local forceId = dummy.AddForce({
		Type = "TestHover", Duration = 2, Hard = true, IgnoreGravity = true,
		Direction = Vector3.zero, Speed = 0, RequiresControl = false,
	})
	task.wait(0.2)

	local stateDuringHover = dummy.GetAirState()
	t.log("Estado hovering:", stateDuringHover)
	t.assert(stateDuringHover == "Floating", "Deveria reportar Floating com Hard force + IgnoreGravity, mesmo sem velocidade")

	dummy.RemoveForce(forceId)
	cleanup(dummy)
end)

TestHarness.Run("Sprint 8/9 — Tether gruda posição + reivindica ownership de servidor", function(t)
	local caster = makeDummy(CFrame.new(0, 5, 0))
	local victim = makeDummy(CFrame.new(10, 5, 0))
	caster.SetMovement()
	victim.SetMovement()

	local forceId = victim.AddForce({
		Type = "TestGrab", Duration = 1, Hard = true, IgnoreGravity = true, RequiresControl = false,
		FollowTarget = function() return caster.GetRoot() end,
		FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
		FollowResponsiveness = 20, FollowMaxSpeed = 100,
	})

	task.wait(0.5)

	local expected = caster.GetCFrame():PointToWorldSpace(Vector3.new(0, 0, -3))
	local actual = victim.GetRoot().Position
	local drift = (expected - actual).Magnitude
	t.log("Drift após convergência:", drift, "studs")
	t.assert(drift < 1.5, "Vítima não convergiu — modo Tether não está funcionando")

	local owner = victim.GetRoot():GetNetworkOwner()
	t.assert(owner == nil, "Root da vítima deveria estar sob ownership do SERVIDOR enquanto Hard force ativa")

	victim.RemoveForce(forceId)
	task.wait(0.1)
	cleanup(caster)
	cleanup(victim)
end)

TestHarness.Run("Sprint 10 — Fork de TriggerSet propaga OUT.onHit do minion pro pai", function(t)
	local summoner = makeDummy(CFrame.new(0, 5, 0))
	local heard = false

	local unsubscribe = summoner:Listen({
		Role = StateTable.Enum.Roles.OUT,
		Breakpoint = StateTable.Enum.Breakpoints.onHit,
		Inherit = { Generations = 1 },
		Priority = 0,
		Action = function() heard = true end,
	})

	local minion = makeDummy(CFrame.new(5, 5, 0), nil, nil, summoner)
	minion:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onHit, StateTable.BuildContext(nil, 1))
	task.wait(0.05)

	t.assert(heard, "Listener do summoner não disparou quando o MINION emitiu onHit")

	unsubscribe()
	cleanup(summoner)
	cleanup(minion)
end)

TestHarness.Run("Sprint 11 — ComboWindow marca e consome dentro da janela", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0))

	BaseSkills.ComboWindow.Mark(dummy, "TestMarker", 0.3, { Foo = "bar" })
	local immediate = BaseSkills.ComboWindow.Consume(dummy, "TestMarker")
	t.assert(immediate and immediate.Foo == "bar", "Consume imediato deveria trazer o payload")

	BaseSkills.ComboWindow.Mark(dummy, "TestMarker", 0.1, { Foo = "baz" })
	task.wait(0.3)
	local expired = BaseSkills.ComboWindow.Consume(dummy, "TestMarker")
	t.assert(expired == nil, "Consume após expirar deveria vir nil")

	cleanup(dummy)
end)

TestHarness.Run("Sprint 13 — Link espelha movimento, Unlink corta", function(t)
	local primary = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Control" })
	local secondary = makeDummy(CFrame.new(3, 5, 0), { "Character", "Health", "Movement", "Control" })
	primary.SetMovement()
	secondary.SetMovement()

	primary.LinkTo(secondary, { MirrorMovement = true })

	local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
	SkillHandler.HandleMovementInput(primary.ID, Vector3.new(1, 0, 0))
	task.wait(0.05)
	t.assert(secondary.GetDirection().Magnitude > 0.5, "Secundário deveria ter recebido a direção espelhada")

	primary.Unlink(secondary)
	SkillHandler.HandleMovementInput(primary.ID, Vector3.new(0, 0, 1))
	task.wait(0.05)
	t.assert(secondary.GetDirection().X > 0.5, "Após Unlink, secundário não deveria mais atualizar")

	cleanup(primary)
	cleanup(secondary)
end)

TestHarness.Run("Sprint 18 — AddComponent dinâmico dispara OnAdded", function(t)
	local dummy = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement" })
	dummy:AddComponent(dummy.ComponentKey.AI, {}, true)

	local ranBrain = false
	dummy.SetBrain(function() ranBrain = true end)
	task.wait(0.1)

	t.assert(ranBrain, "Brain nunca rodou — AIComponent.OnAdded não foi chamado no add dinâmico")
	cleanup(dummy)
end)

task.wait(1)
TestHarness.Summary()

Sprint 21 — GrandIntegrationDemo (IA possuível, caça, combo, tether, fork)

ARQUIVO (novo): sync/ServerScriptService/Scripts/Tests/GrandIntegrationDemo.server.luau

--[[
Prova de integração ampla, não demo de produção: um Hunter guiado por
AIComponent caça a entidade viva mais próxima usando o MESMO pipeline de
input que um player usa (SkillHandler), invoca 2 minions (Fork de
TriggerSet via MinionFactory), executa Dash->Finisher (ComboWindow) e prende
o alvo (Tether) no finisher quando combado. Demonstra possessão real
(ControlComponent) se houver um player conectado.

Ignora CombatComponent/loadout de propósito — chamar SkillRunner direto é
válido: SkillHandler.activate só RESOLVE qual skill rodar a partir de um
loadout, não é o único caminho legítimo de iniciar uma. Fabricar uma pasta
CharData inteira só pra este smoke test seria esforço fora de escopo.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.EntityData.DataManager)
local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
local SkillRunner = require(ServerScriptService.Modules.SkillRunner)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)
local MinionFactory = require(ServerStorage.Modules.MinionFactory)

local function findNearestHealthEntity(fromEntity: any, maxRange: number): any?
	local myPos = fromEntity.GetCFrame().Position
	local best, bestDist = nil, maxRange
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:GetAttribute("EntityID") then
			local core = DataManager.Get(obj)
			if core and core ~= fromEntity and core:HasComponent(core.ComponentKey.Health) then
				local root = core.GetRoot and core.GetRoot()
				if root then
					local dist = (root.Position - myPos).Magnitude
					if dist < bestDist then
						best, bestDist = core, dist
					end
				end
			end
		end
	end
	return best
end

-- ===== Skills inline =====

local HunterDash = {
	data = { cooldown = 2, duration = 0.4, castTime = 0 },
	callbacks = {
		onStart = function(self)
			local dir = self.Entity.GetDirection()
			if dir.Magnitude < 0.1 then dir = self.Entity.GetLastDirection() end
			self.forceID = self.Entity.AddForce({
				Type = "HunterDash", Duration = self.data.duration, Speed = 45,
				Direction = dir, Hard = true, IgnoreGravity = true, Priority = 10,
			})
			BaseSkills.ComboWindow.Mark(self.Entity, "HunterCombo", 1, { Direction = dir }, self.Runner)
		end,
		onEnd = function(self)
			if self.forceID then self.Entity.RemoveForce(self.forceID) end
		end,
	},
}

local HunterFinisher = {
	data = { cooldown = 0.5, duration = 1.5, castTime = 0 },
	callbacks = {
		onStart = function(self)
			self.comboed = BaseSkills.ComboWindow.Consume(self.Entity, "HunterCombo") ~= nil
			self.target = findNearestHealthEntity(self.Entity, 8)
			if not self.target then self:Stop(false); return end

			if self.comboed then
				self.grabForceID = self.target.AddForce({
					Type = "HunterGrab", Duration = self.data.duration, Hard = true,
					IgnoreGravity = true, RequiresControl = false,
					FollowTarget = function() return self.Entity.GetRoot() end,
					FollowOffset = Vector3.new(0, 0, -3), FollowOffsetIsLocal = true,
					FollowResponsiveness = 18, FollowMaxSpeed = 80,
				})
			end

			local damage = self.comboed and 15 or 5
			local success = self.target.TakeDamage(damage, self.Runner)
			warn(string.format("[HunterFinisher] Combo=%s DanoAplicado=%s", tostring(self.comboed), tostring(success)))
		end,
		onEnd = function(self)
			if self.grabForceID and self.target then
				self.target.RemoveForce(self.grabForceID)
			end
		end,
	},
}

-- ===== Setup =====

local function buildDummyModel(cframe: CFrame, color: Color3): Model
	local model = Instance.new("Model")
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Color = color
	root.CFrame = cframe
	root.Parent = model
	model.PrimaryPart = root
	return model
end

local hunterModel = buildDummyModel(CFrame.new(0, 5, 0), Color3.fromRGB(200, 40, 40))
hunterModel.Parent = workspace
local hunter = DataManager.Create(hunterModel, {
	Character = "Character", Health = "Health", Movement = "Movement",
	Status = "Status", Control = "Control", AI = "AI",
})
hunter.SetMovement()

local targetModel = buildDummyModel(CFrame.new(0, 5, -20), Color3.fromRGB(40, 200, 40))
targetModel.Parent = workspace
local target = DataManager.Create(targetModel, { Character = "Character", Health = "Health", Movement = "Movement", Status = "Status" })
target.SetMovement()
target.ApplyStatus(StateTable.Status.GenericBlock, { Duration = 30 })

for i = 1, 2 do
	local minion = MinionFactory.Spawn("TestMinion", CFrame.new(i * 3, 5, 5), hunter)
	if minion then
		minion.SetMovement()
		minion:AddComponent(minion.ComponentKey.AI, {}, true)
		minion.SetBrain(function(entity, dt)
			local nearestTarget = findNearestHealthEntity(entity, 30)
			if nearestTarget then
				local dir = nearestTarget.GetRoot().Position - entity.GetRoot().Position
				SkillHandler.HandleMovementInput(entity.ID, dir)
			end
		end)
	end
end

hunter:Listen({
	Role = StateTable.Enum.Roles.OUT,
	Breakpoint = StateTable.Enum.Breakpoints.onHit,
	Inherit = { Generations = 1 },
	Priority = 0,
	Action = function()
		warn("[GrandDemo] Hunter OUVIU um hit herdado de um minion — Fork de TriggerSet confirmado")
	end,
})

local sinceLastAction = 0
hunter.SetBrain(function(entity, dt)
	sinceLastAction += dt

	local nearestTarget = findNearestHealthEntity(entity, 40)
	if not nearestTarget then return end

	local toTarget = nearestTarget.GetRoot().Position - entity.GetRoot().Position
	local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)

	SkillHandler.HandleMovementInput(entity.ID, flatToTarget)
	SkillHandler.HandleLookInput(entity.ID, flatToTarget)

	if flatToTarget.Magnitude > 6 then return end
	if sinceLastAction < 2 then return end
	sinceLastAction = 0

	SkillRunner.new(HunterDash, entity, "HunterDash", StateTable.Enum.Types.Skill):start()

	task.delay(0.5, function()
		SkillRunner.new(HunterFinisher, entity, "HunterFinisher", StateTable.Enum.Types.Skill):start()
	end)
end)

task.delay(5, function()
	local player = Players:GetPlayers()[1]
	if not player then
		warn("[GrandDemo] Nenhum player conectado — pulando demo de possessão real")
		return
	end

	warn("[GrandDemo] Possuindo Hunter com", player.Name, "por 4 segundos (IA pausa)")
	hunter.Possess({ Player = player })
	task.wait(4)
	warn("[GrandDemo] Devolvendo Hunter pra IA")
	hunter.Release()
end)

warn("[GrandDemo] Cenário no ar: Hunter (vermelho) caça alvo (verde), minions auxiliares, dash+finisher com combo/tether.")

O que observar rodando isso: Hunter anda em linha reta até o alvo (Sprint 7/15), Dash marca combo e desloca com ownership de servidor (Sprint 9), Finisher consome o combo e agarra o alvo (Sprint 8), dano aplica através do GenericBlock resolvendo de forma determinística (Sprint 1), minions perseguem em paralelo e qualquer hit deles ecoa no Hunter via Fork (Sprint 10 + facilitador Sprint 18), e se você entrar como player, aos 5s o controle do Hunter passa pra você por 4 segundos e volta sozinho pra IA (Sprint 12/13).

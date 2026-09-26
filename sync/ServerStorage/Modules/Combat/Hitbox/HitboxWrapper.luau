local IHitbox = {}

function IHitbox:StartHitbox(duration: number) end
function IHitbox:StopHitbox() end

function IHitbox:AddOwner(owner: any) end
function IHitbox:RemoveOwner(owner: any) end

function IHitbox:IsHitboxActive() end
function IHitbox:DestroyHitbox() end
 
 local HitboxWrapper = {}
HitboxWrapper.__index = HitboxWrapper

local ShapecastModule = require(script.Parent.ShapecastHitbox)

-- Pool global
local hitboxPool = {}
local POOL_MAX_SIZE = 50 -- Limite



--TIPAGEM
type HitboxConfig = {
	name: string,
	part: Part,
	flags: {string},
}

type HitResult = {
	target: any,
	hitboxName: string,
	position: Vector3,
	normal: Vector3,
	distance: number,
	instance: Instance,
	segment: any,
	flags: {string},
}

--Inicializa a hitbox, podendo receber um excludeSelf como parâmetro, o padrão é True caso não declarado
function HitboxWrapper.new(Entity, excludeSelf: boolean?)
	
	--Se não receber nada informando se a hitbox deveria ou não excluir o usuário, então a hitbox vai ignorar o usuário por padrão
	if excludeSelf == nil then
		excludeSelf = true
	end
	
	local self = setmetatable({}, HitboxWrapper)
	self.Entity = Entity
	
	self.weapon = Entity.GetWeapon()
	self.activeHitboxes = {} -- [nome] = hitbox ativo. "Ativo" é DERIVADO daqui (ver IsHitboxActive)
	self.hitboxConfigs = {}
	self.hitTargets = {}
	
	self.owners = {} --Será setado pelo SkillRunner, informando quem está rodando a skill

	-- RaycastParams, inicia a configuração de exclusão
	self.raycastParams = RaycastParams.new()
	self.raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local filter = { self.weapon }
	if excludeSelf then
		table.insert(filter, Entity.Instance)
	end
	self.raycastParams.FilterDescendantsInstances = filter

	-- Descobre hitboxes
	self:_discoverHitboxes()

		self.DataManager = require(game.ServerScriptService.EntityData.DataManager)

	return self
end


--Mostra as hitboxes encontradas na arma, assim como as flags, e as guarda nas configurações da hitbox
function HitboxWrapper:_discoverHitboxes()
	local hitboxFolder = self.weapon:FindFirstChild("Hitbox")
	if not hitboxFolder then
		warn("[HitboxWrapper] Pasta de hitboxes não encontrada para: ", self.weapon.Name)
		return
	end

	--Loopa por todas as hitboxes no modelo (dentro da pasta hitboxes)
	for _, hitboxModel in ipairs(hitboxFolder:GetChildren()) do
		if hitboxModel:IsA("Part") then
			hitboxModel.CanQuery = false -- volume de hitbox nunca bloqueia raycast alheio
			hitboxModel.CanTouch = false
			local flags = {}

			
			--Busca por flags (tags) especiais dentro da hitbox
			if hitboxModel:GetAttribute("Flags") then
				flags = string.split(hitboxModel:GetAttribute("Flags"), ",")
			end

			self.hitboxConfigs[hitboxModel.Name] = {
				name = hitboxModel.Name,
				part = hitboxModel,
				flags = flags,
			}
		end
	end
end


--Informa a skill que está rodando pra facilitar aceso a função "onHit" sem código extra na skill
function HitboxWrapper:AddOwner(owner)
	if not self.owners then self.owners = {} end
	if owner == nil then return self end
	self.owners[owner] = owner

	-- cria callback que chama todos os owners (executa todos os onHit pra todos as skills linkadas a hitbox atual)
	self.callback = function(hitResult)
		for _, o in pairs(self.owners) do
			if type(o.onHit) == "function" then
				local ok, err = pcall(function() o:onHit(hitResult) end)
				if not ok then warn("[HitboxWrapper] owner:onHit erro:", err) end
			end
		end
	end

	return self
end


--Remove um dono da hitbox, caso ninguém esteja mais, limpa a callback
function HitboxWrapper:RemoveOwner(owner)
    if not self.owners then return self end
    self.owners[owner] = nil

    -- se ficou vazio, remove callback e para a hitbox
    local empty = true
    for _ in pairs(self.owners) do empty = false; break end
    if empty then
        self.callback = nil
		self:StopHitbox()
    end

    return self
end


--Inicia a hitbox (caso ainda não ativa)
function HitboxWrapper:StartHitbox(duration)

	if self:IsHitboxActive() then return false end
	if next(self.hitboxConfigs) == nil then
		warn("[HitboxWrapper] Nenhuma hitbox configurada")
		return false
	end

	table.clear(self.hitTargets)

	--Pra cada dado na tabela de configuração das hitboxes (flags, nome e parte)
	for name, config in pairs(self.hitboxConfigs) do

		--Cria (ou reutiliza) uma hitbox
		local hitbox = self:_createOrReuseHitbox(config.part)

		if hitbox then
			-- Registra ANTES do HitStart: o OnStopped precisa encontrar a entrada
			self.activeHitboxes[name] = hitbox

			hitbox:OnHit(function(result, segment)
				self:_handleHit(result, segment, config, self.callback)
			end)

			hitbox:OnStopped(function(clearCallbacks)
				clearCallbacks()
				self:_returnHitbox(name, hitbox)
			end)

			hitbox:HitStart(duration)
		end
	end

	return next(self.activeHitboxes) ~= nil
end

--Criação e/ou reutilização de hitboxes na pool global
function HitboxWrapper:_createOrReuseHitbox(part: Part)

	-- Chave por ARMA+PARTE (não por GetFullName, que embute o nome do personagem e vazava hitbox por entidade)
	local poolKey = self.weapon.Name .. "/" .. part.Name

	local pool = hitboxPool[poolKey]
	if pool and #pool > 0 then
		local hitbox = table.remove(pool)
		hitbox.Instance = part
		hitbox.RaycastParams = self.raycastParams
		hitbox:Reconcile() --E atualiza os segmentos pra nova parte
		return hitbox
	end

	--Se não existente, cria uma nova hitbox
	local success, hitbox = pcall(function()
		return ShapecastModule.new(part, self.raycastParams)
	end)

	if not success then
		warn("[HitboxWrapper] Falha ao criar hitbox:", part.Name, hitbox)
		return nil
	end

	hitbox._poolKey = poolKey
	return hitbox
end

--Devolve a hitbox à pool global. IDEMPOTENTE: OnStopped e StopHitbox podem chamar pro mesmo hitbox.
function HitboxWrapper:_returnHitbox(name: string, hitbox)
	if not hitbox then return end
	if self.activeHitboxes[name] ~= hitbox then return end
	self.activeHitboxes[name] = nil

	hitbox:HitStop()

	local poolKey = hitbox._poolKey
	local pool = hitboxPool[poolKey]
	if not pool then
		pool = {}
		hitboxPool[poolKey] = pool
	end

	-- Limite de pool
	if #pool < POOL_MAX_SIZE then
		table.insert(pool, hitbox)
	else
		hitbox:Destroy()
	end
end


--Callback do onHit
function HitboxWrapper:_handleHit(result: RaycastResult, segment, config: HitboxConfig, callback)
	if not result then return end


	--Busca o Entity do alvo atingido
	local targetEntity = self.DataManager.GetEntityFromInstance(result.Instance)
	if not targetEntity then return end

	-- Anti multi-hit
	--Vale notar que, caso a skill seja feita pra ter multi hit é necessário desligar a hitbox a cada hit e reativar depois do cooldown/ticks entre hits!
	local targetId = targetEntity.ID
	if self.hitTargets[targetId] then return end
	self.hitTargets[targetId] = true

	local hitResult: HitResult = {
		target = targetEntity,
		hitboxName = config.name,
		position = result.Position,
		normal = result.Normal,
		distance = result.Distance,
		instance = result.Instance,
		segment = segment,
		flags = config.flags,
	}

	--Se tiver um callback, executa (provavelmente onHit da skill)
	if self.callback then
		local success, err = pcall(self.callback, hitResult)
		if not success then
			warn("[HitboxWrapper] Erro no callback:", err)
		end
	end
end


--Desativa a hitbox
function HitboxWrapper:StopHitbox()
	-- Snapshot: HitStop dispara OnStopped, que mexe em activeHitboxes durante a iteração
	for name, hitbox in table.clone(self.activeHitboxes) do
		hitbox:HitStop()                 -- dispara OnStopped -> _returnHitbox
		self:_returnHitbox(name, hitbox) -- no-op se o OnStopped já devolveu
	end

	table.clear(self.hitTargets)
end

--Derivado do estado real: não existe mais flag isActive pra ficar presa quando o timer expira sozinho
function HitboxWrapper:IsHitboxActive(): boolean
	return next(self.activeHitboxes) ~= nil
end

function HitboxWrapper:GetActiveHitboxes()
	return self.activeHitboxes
end

function HitboxWrapper:GetHitboxConfigs()
	return self.hitboxConfigs
end


--Destrói a hitbox
function HitboxWrapper:DestroyHitbox()
	self:StopHitbox()
	self.Entity = nil
	self.weapon = nil
	self.raycastParams = nil
	table.clear(self.hitboxConfigs)
end
-- Limpa pool global
function HitboxWrapper.ClearPool()
	local totalDestroyEntity = 0
	for poolKey, pool in pairs(hitboxPool) do
		for _, hitbox in ipairs(pool) do
			hitbox:Destroy()
			totalDestroyEntity += 1
		end
	end

	table.clear(hitboxPool)
	print("[HitboxWrapper] Pool limpo. Destruídas:", totalDestroyEntity)
end
-- Debug
function HitboxWrapper.GetPoolStats()
	local Stats = {
		totalPools = 0,
		totalHitboxes = 0,
		byType = {}
	}
	for poolKey, pool in pairs(hitboxPool) do
		Stats.totalPools += 1
		Stats.totalHitboxes += #pool
		Stats.byType[poolKey] = #pool
	end

	return Stats
end

local ExposeAPI = {

	-- Lifecycle
	StartHitbox = function(component, ...) return component:StartHitbox(...) end,
	StopHitbox = function(component) return component:StopHitbox() end,
	DestroyHitbox = function(component) return component:DestroyHitbox() end,

	-- Owner (referência pra callback onHit da skill que inicializou a hitbox)
	AddOwner = function(component, owner) return component:AddOwner(owner) end,
	RemoveOwner = function(component, owner) return component:RemoveOwner(owner) end,

	-- State
	IsHitboxActive = function(component) return component:IsHitboxActive() end,

	-- Debug / Utils
	GetActiveHitboxes = function(component) return component:GetActiveHitboxes() end,
	GetHitboxConfigs = function(component) return component:GetHitboxConfigs() end,
}

return {
	new = HitboxWrapper.new,
	ExposeAPI = ExposeAPI,
	IHitbox = IHitbox,
	GetPoolStats = HitboxWrapper.GetPoolStats, -- debug
	ClearPool = HitboxWrapper.ClearPool,
}
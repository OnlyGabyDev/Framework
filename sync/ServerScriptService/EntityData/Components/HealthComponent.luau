--[[
============================Componente de HP============================
- Entrada principal de dano e cura
- Pub/Sub de entrada de dano pra garantir que efeitos como rupture ativem ao ser atingido e devolva a informação ao atacante/status
- Callbacks para eventos de dano, cura e morte
- Histórico de dano
======================================================================================================================
]]

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local StateEnum = StateTable.Enum
local RS = game:GetService("ReplicatedStorage")
local UpdateHPBar = RS.RemoteEvents:WaitForChild("UpdateHealthBar")

local HealthComponent = {}
HealthComponent.__index = HealthComponent


--[[
Cria uma nova instância do HealthComponent
@param entity - Entidade dona do componente Entity, enviar EntityData
@param config - Configurações iniciais do componente TABLE { MaxHP: number, StartHP: number Events:{OnDamage,OnHeal,onDeath,onRevive}}
@return nova instância do HealthComponent HealthComponent]]
function HealthComponent.new(entity, config)
	local self = setmetatable({}, HealthComponent)
	
	self.Entity = entity
	self.MaxHP = config.MaxHP or StateEnum.StatDefaults.MaxHP
	self.HP = config.StartHP or self.MaxHP
	self.Subscription = config.Events or false
	self.IsDead = false
	self._lastDamageTime = 0
	
	-- Histórico de dano
	self.DamageHistory = {}
	self.MaxHistorySize = 10

	
	return self
end

function HealthComponent:_UsesAttributes() : boolean
	return self.Entity:HasComponent(self.Entity.ComponentKey.Attributes)
end

function HealthComponent:_SyncClient()
	if self.Entity:IsPlayer() then
		UpdateHPBar:FireClient(self.Entity.Player, self.HP, self:GetMaxHP())
	end
end



--=============================================================================
--  VALIDAÇÃO DE HIT
--=============================================================================

--[[
FUNÇÃO INTERNA!
Valida se um ataque pode afetar a entidade baseado em suas tags de imunidade
@return sucesso BOOLEAN, razão STRING (nome da imunidade que bloqueou o hit)]]


--=============================================================================
--  DANO
--=============================================================================


--[[
Aplica dano à entidade
@param amount - Quantidade de dano a ser aplicada NUMBER
@param source - Fonte do dano ANY
@return sucesso BOOLEAN, quantidade real de dano aplicada NUMBER]]
function HealthComponent:TakeDamage(amountOrContext : number | {}, source : any?)
	if self.IsDead then return false end

	if not StateTable.TryEnterChain() then
		warn("[HealthComponent] MAX_RECURSION excedido, dano recusado. Entidade:", tostring(self.Entity.ID))
		return false, "MaxRecursion"
	end

	local success, actualDamage, context = self:_TakeDamageInner(amountOrContext, source)
	StateTable.ExitChain()

	return success, actualDamage, context
end

function HealthComponent:_TakeDamageInner(amountOrContext, source)
	local context
	if type(amountOrContext) == "table" then
		context = amountOrContext
	else
		context = StateTable.BuildContext(source, amountOrContext)
	end

	if context.damage <= 0 then return false, 0 end

	-- Se tem StatusComponent, valida imunidades e aplica mitigação (block/parry).
	-- Toda a lógica de "o que é block/iFrame" mora no StatusComponent agora (Regra 20).
	local statusComp = self.Entity:HasComponent(self.Entity.ComponentKey.Status)
	if statusComp then
		local canHit, reason = self.Entity.ValidateHit(context)
		if not canHit then
			return false, reason
		end
		self.Entity.ApplyMitigation(context) -- pode reduzir/zerar context.damage
	end

	-- Ponto de extensão declarativo (novo): cancelamento/mutação simples ANTES do HP mudar.
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.PreDamage, context)
	if context.cancelled then
		return false, context.reason or "Cancelled"
	end
	context.damage = math.max(0, context.damage) -- listener não pode transformar dano em cura

	-- Aplica dano
	local lastHP = self.HP
	self.HP = math.max(0, self.HP - context.damage)
	self:_SyncClient()
	local actualDamage = lastHP - self.HP

	self:_RecordDamage(actualDamage, context.source)
	self._lastDamageTime = tick()

	if self.HP <= 0 and not self.IsDead then
		self:Die(context.source)
	end

	if context.effects ~= nil and statusComp then
		for _, effectData in ipairs(context.effects) do
			self.Entity.ApplyStatus(effectData, { Source = context.source })
		end
	end

	context.actualDamage = actualDamage

	-- Hook reativo do lado do ALVO (novo): dispara DEPOIS do HP já ter mudado
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.PostDamage, context)

	return true, actualDamage, context
end





--[[
Cura a entidade por uma quantidade específica
@param amount - Quantidade de HP a ser curada NUMBER
@return quantidade total de HP curada NUMBER
]]
function HealthComponent:Heal(amount : number) : number
	if self.IsDead or amount <= 0 then return 0 end

	local context = StateTable.BuildContext(nil, amount)
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnHeal, context)
	context.damage = math.max(0, context.damage)

	local oldHP = self.HP
	self.HP = math.min(self:GetMaxHP(), self.HP + context.damage)
	self:_SyncClient()

	return self.HP - oldHP
end

--[[
Mata a entidade
@param killer - Quem matou a entidade, recebe any, pois pode ser ED ou Nil
]]
function HealthComponent:Die(killer : any)
	if self.IsDead then return end
	
	self.IsDead = true
	self.HP = 0
	
	local context = StateTable.BuildContext(killer, 0)
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnDeath, context)

	-- Emite OUT.OnDeath no atacante (se killer for um Runner e tiver Entity associada)
	if killer and type(killer) == "table" and killer.Entity then
		local outContext = StateTable.BuildContext(killer, 0)
		outContext.targetEntity = self.Entity
		killer.Entity:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.OnDeath, outContext)
	end

end

function HealthComponent:Revive(hpAmount : number?) : boolean
	if not self.IsDead then return false end

	self.IsDead = false
	local maxHP = self:GetMaxHP()
	self.HP = math.min(hpAmount or maxHP, maxHP)
	self:_SyncClient()

	local context = StateTable.BuildContext(nil, 0)
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnRevive, context)

	return true
end



--=============================================================================
--  GETTERS/SETTERS
--=============================================================================

function HealthComponent:GetHP()
	return self.HP
end

function HealthComponent:GetMaxHP()
	-- Com Attributes o teto vem do GetStat (inclui buffs); sem ele, self.MaxHP é a fonte
	if self:_UsesAttributes() then
		self.MaxHP = self.Entity.GetStat(StateEnum.Stats.MaxHP, self.MaxHP)
	end
	return self.MaxHP
end

function HealthComponent:SetHP(value)
	if self.IsDead then return end

	local oldHP = self.HP
	self.HP = math.clamp(value, 0, self:GetMaxHP())

	if self.HP <= 0 then
		self:Die(nil)
	elseif self.HP > oldHP then
		local context = StateTable.BuildContext(nil, self.HP - oldHP)
		self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnHeal, context)
	end

	self:_SyncClient()
end

function HealthComponent:SetMaxHP(value)
	value = math.max(1, value)

	-- Ratio calculado ANTES de trocar o teto (bug antigo: ratio saía 2 e o HP ficava acima do MaxHP)
	local ratio = self.HP / math.max(1, self:GetMaxHP())

	if self:_UsesAttributes() then
		self.Entity.SetStat(StateEnum.Stats.MaxHP, value)
	end
	self.MaxHP = value

	local newMax = self:GetMaxHP() -- relê (com Attributes inclui modificadores ativos)
	self.HP = math.clamp(math.floor(newMax * ratio), 0, newMax)
	self:_SyncClient()
end


function HealthComponent:GetHealthRatio()
	return self.HP / math.max(1, self:GetMaxHP())
end


function HealthComponent:IsAlive()
	return not self.IsDead
end

--=============================================================================
--  UTILITY
--=============================================================================

--[[
Registra o dano no histórico interno
@param amount - Quantidade de dano NUMBER
@param source - Fonte do dano ANY
]]
function HealthComponent:_RecordDamage(amount, source)
	table.insert(self.DamageHistory, 1, {
		amount = amount,
		source = source,
		time = tick()
	})
	
	-- Limita tamanho do histórico
	if #self.DamageHistory > self.MaxHistorySize then
		table.remove(self.DamageHistory)
	end
end

function HealthComponent:GetDamageHistory()
	return self.DamageHistory
end

function HealthComponent:GetTotalDamageTaken()
	local total = 0
	for _, record in ipairs(self.DamageHistory) do
		total += record.amount
	end
	return total
end

--=============================================================================
--  LIFECYCLE
--=============================================================================


--[[
Registra os callbacks recebidos pro pub/sub de eventos reativos
]]
function HealthComponent:OnAdded()
	if self.Subscription then
		for key, callback in pairs(self.Subscription) do
			self.Entity:Listen({
				Role = StateEnum.Roles.IN,
				Breakpoint = StateEnum.Breakpoints[key] or key,
				Priority = 0,
				Action = callback
			})
		end
	end
end


--[[
Destroi o componente, limpando referências e parando processos
]]
function HealthComponent:Destroy()
	self.Entity = nil
	table.clear(self.DamageHistory)
end

--=============================================================================
--  API EXPOSE
--=============================================================================

local ExposeAPI = {
	TakeDamage = function(component, ...) return component:TakeDamage(...) end,
	Heal = function(component, ...) return component:Heal(...) end,
	Die = function(component, ...) return component:Die(...) end,
	Revive = function(component, ...) return component:Revive(...) end,
	GetHP = function(component) return component:GetHP() end,
	GetMaxHP = function(component) return component:GetMaxHP() end,
	SetHP = function(component, ...) return component:SetHP(...) end,
	SetMaxHP = function(component, ...) return component:SetMaxHP(...) end,
	GetHealthRatio = function(component) return component:GetHealthRatio() end,
	IsAlive = function(component) return component:IsAlive() end,
	GetDamageHistory = function(component) return component:GetDamageHistory() end,
	GetTotalDamageTaken = function(component) return component:GetTotalDamageTaken() end,
}

return {
	new = HealthComponent.new,
	ExposeAPI = ExposeAPI,
	EventKey = {
		onDamage = StateEnum.Breakpoints.OnDamage,
		onHeal = StateEnum.Breakpoints.OnHeal,
		onDeath = StateEnum.Breakpoints.OnDeath,
		onRevive = StateEnum.Breakpoints.OnRevive,
	}
}
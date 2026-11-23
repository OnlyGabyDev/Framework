--[[
HealthComponent: vida, dano e cura da entidade.
- TakeDamage: pipeline do lado do alvo (imunidade, bloqueio, proteções de stat, IN.PreDamage,
  HP, efeitos on-hit, IN.PostDamage, OUT.OnDamage no dono do dano)
- Heal com teto declarado (HealCap); HP acima do máximo é permitido (sobrevida)
- Morte (IN.OnDeath, OUT.OnDeath no dono do efeito) e histórico de dano
]]

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local StateEnum = StateTable.Enum
local RS = game:GetService("ReplicatedStorage")
local UpdateHPBar = RS.RemoteEvents:WaitForChild("UpdateHealthBar")

local HealthComponent = {}
HealthComponent.__index = HealthComponent

--[[
Eventos do config (Events = { onDamage = fn, ... }) e de EntityCore.Events, do lado de quem apanha
(canal IN). onDamage é o PostDamage.
]]
local EVENT_KEY = table.freeze({
	onDamage = StateEnum.Breakpoints.PostDamage,
	onHeal = StateEnum.Breakpoints.OnHeal,
	onDeath = StateEnum.Breakpoints.OnDeath,
	onRevive = StateEnum.Breakpoints.OnRevive,
})


--[[
@param entity - entidade dona
@param config - { MaxHP?, StartHP?, HealCap?, Events? = { onDamage, onHeal, onDeath, onRevive } }
]]
function HealthComponent.new(entity, config)
	local self = setmetatable({}, HealthComponent)
	
	self.Entity = entity
	self.MaxHP = config.MaxHP or StateEnum.StatDefaults.MaxHP
	self.HP = config.StartHP or self.MaxHP
	self.Subscription = config.Events or false
	-- Teto da cura em × MaxHP (Enum.HealthDefaults.HealCap); math.huge = sem teto
	self.HealCap = config.HealCap or StateEnum.HealthDefaults.HealCap
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

local function getAntiCheat()
	return require(game:GetService("ServerScriptService").Modules.GlobalAntiCheat)
end

--[[
Quem vê a barra de vida deste corpo: o player que está com ele roteado (o dono nativo ou quem o
possui). Antes de o AntiCheat registrar o player (spawn), vale o dono nativo.
]]
function HealthComponent:_HudViewers(): {Player}
	local entity = self.Entity
	local candidates = {}
	if entity.Player then candidates[entity.Player] = true end
	if entity:HasComponent(entity.ComponentKey.Control) then -- dependência opcional
		local controller = entity.GetController()
		if controller and controller.Player then candidates[controller.Player] = true end
	end

	local AC = getAntiCheat()
	local viewers = {}
	for player in candidates do
		local routed = AC.GetControlledEntityId(player)
		if routed == nil and AC.GetNativeEntityId(player) == nil and player == entity.Player then
			routed = entity.ID
		end
		if routed == entity.ID then table.insert(viewers, player) end
	end
	return viewers
end

function HealthComponent:_SyncClient()
	for _, player in self:_HudViewers() do
		UpdateHPBar:FireClient(player, self.HP, self:GetMaxHP())
	end
end



--=============================================================================
--  VALIDAÇÃO DE HIT
--=============================================================================



--=============================================================================
--  DANO
--=============================================================================


--[[
Aplica dano à entidade.
@param amountOrContext - dano NUMBER ou um HitContext pronto
@param source - runner que causou ANY?
@return sucesso BOOLEAN, dano real NUMBER, contexto | false, Enum.ChainOutcomes (Deferred: a
	cadeia estava funda demais e o dano roda no próximo frame)]]
function HealthComponent:TakeDamage(amountOrContext : number | {}, source : any?)
	local ran, success, actualDamage, context = StateTable.RunInChain(
		"[HealthComponent] TakeDamage", self.Entity and self.Entity.ID,
		self._TakeDamageInner, self, amountOrContext, source)
	if not ran then
		return false, success -- `success` traz o motivo (StateTable.Enum.ChainOutcomes)
	end

	return success, actualDamage, context
end

function HealthComponent:_TakeDamageInner(amountOrContext, source)
	-- Aqui e não no TakeDamage: um dano adiado pela cadeia roda no frame seguinte, quando o alvo pode
	-- ter morrido ou saído do jogo
	if self.IsDead or not self.Entity then return false, 0 end

	local context
	if type(amountOrContext) == "table" then
		context = amountOrContext
	else
		context = StateTable.BuildContext(source, amountOrContext)
	end

	-- Hit de 0 de dano só continua se tiver efeitos para aplicar (slow puro, marca)
	local hasEffects = context.effects ~= nil and #context.effects > 0
	local zeroDamageHit = context.damage <= 0
	if zeroDamageHit and not hasEffects then return false, 0 end

	-- Imunidade e bloqueio são do StatusComponent (dependência opcional)
	local statusComp = self.Entity:HasComponent(self.Entity.ComponentKey.Status)
	if statusComp then
		local canHit, reason = self.Entity.ValidateHit(context)
		if not canHit then
			return false, reason
		end
		local before = context.damage
		self.Entity.ApplyMitigation(context) -- pode reduzir/zerar context.damage
		-- Bloqueado = o bloqueio zerou um hit que tinha dano (listeners e efeitos leem isso)
		context.blocked = before > 0 and context.damage <= 0
	end

	-- Proteções de stat do alvo (Defense, Armor: Enum.DamageMitigation). Dependência opcional de Attributes
	if context.damage > 0 and self.Entity:HasComponent(self.Entity.ComponentKey.Attributes) then
		context.damage = StateTable.MitigateDamage(context.damage, self.Entity.GetStat, context.traits)
	end

	-- Ponto de extensão: listeners mudam ou cancelam o dano antes do HP mudar
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

	-- Efeitos on-hit pela política declarada (Enum.EffectDefaults / data.effectPolicy)
	if hasEffects and statusComp then
		local source = context.source
		local sourceData = source and (source.skill and source.skill.data or source.data) or nil
		for _, entry in ipairs(context.effects) do
			local status, onBlocked, onZeroDamage = StateTable.ResolveEffect(entry, sourceData)
			local skip = (context.blocked and not onBlocked) or (zeroDamageHit and not onZeroDamage)
			if status and not skip then
				-- O inherited do hit (o que quem atacou pôs e o OUT.onHit injetou) segue para o status
				self.Entity.ApplyStatus(status, { Source = source, Inherited = context.inherited })
			end
		end
	end

	context.actualDamage = actualDamage
	context.targetEntity = context.targetEntity or self.Entity

	-- Reação do lado do alvo, depois do HP mudar
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.PostDamage, context)

	-- OUT.OnDamage no dono do dano, para todo dano (direto e indireto: DOT, reflexo), com as traits do
	-- efeito no contexto (quem não quer DOT filtra com Query = { None = { DOT } })
	local owner = context.ownerEntity or StateTable.EffectOwner(context.source)
	if owner then
		owner:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.OnDamage, context)
	end

	return true, actualDamage, context
end





--[[
Cura a entidade.
@param amount - quanto curar NUMBER
@param opts - Types.HealOptions? { Source (recebe o OUT.OnHeal), Traits, Cap (teto em × MaxHP) }
@return quanto o HP subiu NUMBER
]]
function HealthComponent:Heal(amount : number, opts : any?) : number
	if self.IsDead or amount <= 0 then return 0 end

	local context = StateTable.BuildContext(opts and opts.Source, amount)
	for _, trait in (opts and opts.Traits) or {} do
		if not table.find(context.traits, trait) then table.insert(context.traits, trait) end
	end
	context.targetEntity = self.Entity
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnHeal, context)
	context.damage = math.max(0, context.damage)

	-- Teto: HealCap × MaxHP, e nunca abaixo do HP atual (a cura não corta a sobrevida)
	local cap = (opts and opts.Cap) or self.HealCap
	local ceiling = math.max(self.HP, cap * self:GetMaxHP())
	local oldHP = self.HP
	self.HP = math.min(ceiling, self.HP + context.damage)
	self:_SyncClient()

	local healed = self.HP - oldHP
	context.actualHeal = healed
	-- OUT.OnHeal no dono da cura (lifesteal, cura de aliado)
	local owner = context.ownerEntity
	if owner then
		owner:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.OnHeal, context)
	end
	return healed
end

--[[
Mata a entidade.
@param killer - runner que matou ANY?
]]
function HealthComponent:Die(killer : any)
	if self.IsDead then return end
	
	self.IsDead = true
	self.HP = 0
	
	local context = StateTable.BuildContext(killer, 0)
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnDeath, context)

	-- OUT.OnDeath no dono do que matou (StateTable.EffectOwner): numa morte por DOT, quem aplicou o DOT
	local owner = StateTable.EffectOwner(killer)
	if owner then
		local outContext = StateTable.BuildContext(killer, 0)
		outContext.targetEntity = self.Entity
		owner:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.OnDeath, outContext)
	end

end

function HealthComponent:Revive(hpAmount : number?) : boolean
	if not self.IsDead then return false end

	self.IsDead = false
	-- Sem valor, volta com o MaxHP; com valor, exatamente ele
	self.HP = math.max(0, hpAmount or self:GetMaxHP())
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

--[[
Define o HP exato, sem corte no MaxHP (o teto é do SetMaxHP e do HealCap). Só não fica negativo;
0 ou menos mata.
]]
function HealthComponent:SetHP(value)
	if self.IsDead then return end

	local oldHP = self.HP
	self.HP = math.max(0, value)

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

	-- Proporção calculada antes de trocar o teto
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
			-- onDamage e OnDamage valem o mesmo (EVENT_KEY); outra chave vale como breakpoint cru
			local eventName = string.lower(string.sub(key, 1, 1)) .. string.sub(key, 2)
			self.Entity:Listen({
				Role = StateEnum.Roles.IN,
				Breakpoint = EVENT_KEY[eventName] or StateEnum.Breakpoints[key] or key,
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
	-- Manda a vida atual para quem dirige este corpo (chamado na troca de corpo da possessão)
	SyncHealthHUD = function(component) return component:_SyncClient() end,
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
	EventKey = EVENT_KEY,
}
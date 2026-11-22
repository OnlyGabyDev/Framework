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
Eventos do config (Events = { onDamage = fn, ... }) e de EntityCore.Events: são do lado de quem
APANHA (canal IN). onDamage é o PostDamage (F99): antes virava IN.OnDamage, que o motor nunca emite
(o OnDamage é do dono do dano, canal OUT), e o callback nunca rodava. Dono único deste mapa.
]]
local EVENT_KEY = table.freeze({
	onDamage = StateEnum.Breakpoints.PostDamage,
	onHeal = StateEnum.Breakpoints.OnHeal,
	onDeath = StateEnum.Breakpoints.OnDeath,
	onRevive = StateEnum.Breakpoints.OnRevive,
})


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
	-- Teto da cura em × MaxHP (F107): padrão em Enum.HealthDefaults; math.huge = sem teto
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
Quem vê a barra de vida deste corpo: o player que está com ELE roteado (D15, F56). Candidatos: o
dono nativo e quem o possui. Durante a possessão a HUD mostra o corpo controlado; antes mostrava
sempre o corpo original. Antes do AntiCheat registrar o player (spawn), vale o dono nativo.
]]
function HealthComponent:_HudViewers(): {Player}
	local entity = self.Entity
	local candidates = {}
	if entity.Player then candidates[entity.Player] = true end
	if entity:HasComponent(entity.ComponentKey.Control) then -- dependência opcional (regra 16)
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
@return sucesso BOOLEAN, quantidade real de dano aplicada NUMBER | false, Enum.ChainOutcomes
	(Deferred: a cadeia estava funda demais e o dano roda no próximo frame, F62)]]
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
	-- Aqui e não no TakeDamage: um dano adiado pela cadeia (F62) roda no frame seguinte, quando o
	-- alvo pode ter morrido ou saído do jogo (Destroy zera self.Entity)
	if self.IsDead or not self.Entity then return false, 0 end

	local context
	if type(amountOrContext) == "table" then
		context = amountOrContext
	else
		context = StateTable.BuildContext(source, amountOrContext)
	end

	-- Hit de 0 de dano só continua se tiver efeitos para aplicar (slow puro, marca: D6, F41)
	local hasEffects = context.effects ~= nil and #context.effects > 0
	local zeroDamageHit = context.damage <= 0
	if zeroDamageHit and not hasEffects then return false, 0 end

	-- Se tem StatusComponent, valida imunidades e aplica mitigação (block/parry).
	-- Toda a lógica de "o que é block/iFrame" mora no StatusComponent agora (Regra 20).
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

	-- Proteções de stat do alvo (Defense, Armor...: D11, F43). Dependência opcional de Attributes
	-- (regra 16): sem ele não há stat de proteção. Antes Defense existia e nunca entrava no dano
	if context.damage > 0 and self.Entity:HasComponent(self.Entity.ComponentKey.Attributes) then
		context.damage = StateTable.MitigateDamage(context.damage, self.Entity.GetStat, context.traits)
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

	-- Efeitos on-hit pela política declarada (D6, F41): antes um hit 100% bloqueado aplicava os
	-- efeitos, e um hit de 0 de dano nunca chegava aqui (slow puro era impossível)
	if hasEffects and statusComp then
		local source = context.source
		local sourceData = source and (source.skill and source.skill.data or source.data) or nil
		for _, entry in ipairs(context.effects) do
			local status, onBlocked, onZeroDamage = StateTable.ResolveEffect(entry, sourceData)
			local skip = (context.blocked and not onBlocked) or (zeroDamageHit and not onZeroDamage)
			if status and not skip then
				self.Entity.ApplyStatus(status, { Source = source })
			end
		end
	end

	context.actualDamage = actualDamage
	context.targetEntity = context.targetEntity or self.Entity

	-- Hook reativo do lado do ALVO (novo): dispara DEPOIS do HP já ter mudado
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.PostDamage, context)

	-- OUT.OnDamage no DONO do dano (D3, F101), para todo dano: direto (skill) e indireto (DOT,
	-- reflexo, área de status), com as traits do efeito no contexto (quem não quer DOT filtra com
	-- Query = { None = { DOT } }). Antes só o ApplyDamage emitia, e o dano de status não tinha OUT
	-- ownerEntity vem do BuildContext; contexto montado à mão (sem ele) resolve aqui
	local owner = context.ownerEntity or StateTable.EffectOwner(context.source)
	if owner then
		owner:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.OnDamage, context)
	end

	return true, actualDamage, context
end





--[[
Cura a entidade por uma quantidade específica
@param amount - Quantidade de HP a ser curada NUMBER
@param opts - Types.HealOptions? (F107): Source (runner de quem curou: OUT.OnHeal nele), Traits, Cap
	(teto em × MaxHP só desta cura)
@return quantidade total de HP curada NUMBER
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

	-- Teto da cura: HealCap × MaxHP, e NUNCA abaixo do HP atual (F107). HP acima do máximo é escolha
	-- de design (sobrevida); antes, com o HP acima do teto, a cura o cortava e devolvia valor negativo
	local cap = (opts and opts.Cap) or self.HealCap
	local ceiling = math.max(self.HP, cap * self:GetMaxHP())
	local oldHP = self.HP
	self.HP = math.min(ceiling, self.HP + context.damage)
	self:_SyncClient()

	local healed = self.HP - oldHP
	context.actualHeal = healed
	-- OUT.OnHeal no dono da cura (lifesteal, cura de aliado), simétrico ao OUT.OnDamage (D3)
	local owner = context.ownerEntity
	if owner then
		owner:Emit(StateEnum.Roles.OUT, StateEnum.Breakpoints.OnHeal, context)
	end
	return healed
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

	-- OUT.OnDeath no DONO do que matou (StateTable.EffectOwner): numa morte por DOT o runner do
	-- status roda na própria vítima, e antes ela recebia o crédito da própria morte
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
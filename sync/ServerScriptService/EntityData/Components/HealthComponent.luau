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
function HealthComponent:_ValidateHit(context)

	--Se não tiver componente de status, não existem tags de ivulnerabilidade e valida o hit.
	if not self.Entity:HasComponent(self.Entity.ComponentKey.Status) then return true end

	local targetTags = self.Entity.GetActiveTags()
	local immunityRules = self._immunityRules or self.Entity.GetImmunityRules() 
	local attackTraits = context.traits
	
	for immunityName, rule in pairs(immunityRules) do
		if targetTags[immunityName] and immunityName ~= StateTable.Enum.Tags.block then
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

	-- Aceita um context pronto (vindo do pipeline OUT do atacante) ou (amount, source)
	local context
	if type(amountOrContext) == "table" then
		context = amountOrContext
	else
		context = StateTable.BuildContext(source, amountOrContext)
	end
	source = context.source -- já normalizado (Runner) pelo BuildContext

	if context.damage <= 0 then return false, 0 end

	-- Se tem StatusComponent, valida o hit e aplica modificadores
	local statusComp = self.Entity:HasComponent(self.Entity.ComponentKey.Status)
	if statusComp then
		local ignore
		local canHit, reason = self:_ValidateHit(context)
		if not canHit then
			return false, reason
		end

		--busca por todas as TAGS ativas na entidade
		local ActiveTags,owner = self.Entity.GetActiveTags()
		local blockTag = StateTable.Enum.Tags.block

		--se encontrar a tag de block ativa, e se a source não ignorar block 
		--então roda o trigger do runner do block
		if ActiveTags[blockTag] then
			for _,value in pairs(context.traits) do
				if StateTable.Enum.BlockIgnore[value] then
					ignore = true
					break
				end
				ignore = false
			end

			local blockRunner = owner[blockTag]

			--Skippa o block se tiver trait de ignorar block e o block não for TrueBlock
			local skipBlock = (
				not (blockRunner.data.traits and table.find(blockRunner.data.traits, StateTable.Enum.Traits.TrueBlock))
				and ignore
		)

			--se não encontrou trait de ignore block e se o block não é TrueBlock
			if not skipBlock then
				if blockRunner then
					local canInteract = StateTable.CheckBlockFilter(blockRunner, context)
					local blockBreak
					local broke
					if context.source and context.traits and canInteract then
						for _,trait in context.traits do	--busca por algum trait que se encaixe em BlockBreak
							blockBreak = StateTable.Enum.BlockBreak[trait]
							if blockBreak then break end
						end
						local unbreakable = blockRunner.data.traits and table.find(blockRunner.data.traits, StateTable.Enum.Traits.Unbreakable)
						--Se o block não for inquebravel e eu tiver a intenção de quebrar, quebre/finalize o runner
						if blockBreak and not unbreakable then
							blockRunner:Stop(true)
							broke = true
						end
					end
					
					if not broke and canInteract then
						local resultDamage = blockRunner:TriggerAction(context)
						if resultDamage then context.damage = resultDamage end
					end
				end
			end
		end
	end

			-- Alterações de dano pós block (via canal IN)
	self.Entity:Emit(StateEnum.Roles.IN, StateEnum.Breakpoints.OnDamage, context)
	context.damage = math.max(0, context.damage) -- listener não pode transformar dano em cura

	-- Aplica dano
	local lastHP = self.HP
	self.HP = math.max(0, self.HP - context.damage)
	self:_SyncClient()
	local actualDamage = lastHP - self.HP
	
	-- Registra no histórico
	self:_RecordDamage(actualDamage, source)
	
	-- Marca tempo do último dano 
	self._lastDamageTime = tick()
	
	
	-- Checa morte
	if self.HP <= 0 and not self.IsDead then
		self:Die(source)
	end

	if context.effects ~= nil then
		if statusComp then
			for _, effectData in ipairs(context.effects) do
				self.Entity.ApplyStatus(effectData,nil, source)
			end
		end
	end
	
	context.actualDamage = actualDamage
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
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
	self.MaxHP = config.MaxHP or 10
	self.HP = config.StartHP or self.MaxHP
	self.Subscription = config.Events or false
	self.IsDead = false
	self._lastDamageTime = 0
	
	-- Callbacks de eventos
	self.OnDamage = self:_Trigger(self, StateTable.reactTags.onDamage)
	self.OnHeal = self:_Trigger(self, StateTable.reactTags.onHeal)
	self.OnDeath = self:_Trigger(self, StateTable.reactTags.onDeath)
	self.OnRevive = self:_Trigger(self, StateTable.reactTags.onRevive)


	-- Histórico de dano
	self.DamageHistory = {}
	self.MaxHistorySize = 10

	
	return self
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
function HealthComponent:TakeDamage(amount : number, source : any)
	if self.IsDead then return false end

	if amount <= 0 then return false, 0 end

	local context = StateTable.BuildContext(source,amount)

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

			-- Alterações de dano pós block
	if self.OnDamage then
		local preMitigationAmount = self.OnDamage(self, context.damage, source)
		if preMitigationAmount then
			context.damage = preMitigationAmount
		end
	end

	
	-- Aplica dano
	local lastHP = self.HP
	self.HP = math.max(0, self.HP - context.damage)
	print(self.HP)
	if self.Entity:IsPlayer() then UpdateHPBar:FireClient(self.Entity.Player,self.HP,self.MaxHP) end
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
	
	return true, context
end



--[[
Inscreve um listener para um evento específico
@param eventType - Tipo do evento ("OnDamage", "OnHeal", "OnDeath") STRING,
@param callback - Função callback a ser chamada quando o evento ocorrer FUNCTION
@return função de cancelamento da inscrição FUNCTION
]]
function HealthComponent:Subscribe(eventType: string, callback: (...any) -> ()): () -> ()
	if not self.EventListeners then
		self.EventListeners = {}
	end
	if not self.EventListeners[eventType] then
		self.EventListeners[eventType] = {}
	end
	table.insert(self.EventListeners[eventType], callback)

	return function()
		self:Unsubscribe(eventType, callback)
	end
end

--[[
Função para ativar listeners inscritos em um evento específico
@param breakPoint - Tipo do evento a ser disparado STRING]]
function HealthComponent:_Trigger(breakPoint : string)

	if not self.EventListeners or not self.EventListeners[breakPoint] then
		return
	end
	
	for _, callback in ipairs(self.EventListeners[breakPoint]) do
		 return task.spawn(callback, self) 
	end
	return false
end


--[[
Cura a entidade por uma quantidade específica
@param amount - Quantidade de HP a ser curada NUMBER
@return quantidade total de HP curada NUMBER
]]
function HealthComponent:Heal(amount : number) : number
	if self.IsDead or amount <= 0 then return 0 end
	
	local oldHP = self.HP
	self.HP = math.min(self.MaxHP, self.HP + amount)
	local actualHeal = self.HP - oldHP
	
	if actualHeal > 0 and self.OnHeal then
		task.spawn(self.OnHeal, self, actualHeal)
	end
	
	return actualHeal
end

--[[
Mata a entidade
@param killer - Quem matou a entidade, recebe any, pois pode ser ED ou Nil
]]
function HealthComponent:Die(killer : any)
	if self.IsDead then return end
	
	self.IsDead = true
	self.HP = 0
	
	if self.OnDeath then
		task.spawn(self.OnDeath, self, killer)
	end

end

--[[
Revive a entidade
@param hpAmount - Quantidade de HP ao reviver NUMBER, se nil, revive com MaxHP
@return sucesso BOOLEAN
]]
function HealthComponent:Revive(hpAmount : number) : boolean
	if not self.IsDead then return false end
	
	self.IsDead = false
	self.HP = math.min(hpAmount or self.MaxHP, self.MaxHP)
	
	if self.OnRevive then
		task.spawn(self.OnRevive, self)
	end
	
	return true
end



--=============================================================================
--  GETTERS/SETTERS
--=============================================================================

function HealthComponent:GetHP()
	return self.HP
end

function HealthComponent:GetMaxHP()
	self.MaxHP = self.Entity.GetStat("MaxHP", 100)
	--warn(self.Entity.GetStat("MaxHP",100))
	return self.maxHP
end

function HealthComponent:SetHP(value)
	if self.IsDead then return end
	
	local oldHP = self.HP
	self.HP = math.clamp(value, 0, self.MaxHP)
	
	if self.HP <= 0 then
		self:Die(nil)
	elseif self.HP > oldHP and self.OnHeal then
		task.spawn(self.OnHeal, self, self.HP - oldHP)
	end
end

function HealthComponent:SetMaxHP(value)
	self.Entity.SetStat("MaxHP", value)
	self:GetMaxHP()

	local ratio = self.HP / self.MaxHP
	self.MaxHP = math.max(1, value)
	self.HP = math.floor(self.MaxHP * ratio)
end


function HealthComponent:GetHealthRatio()
	return self.HP / self.MaxHP
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
		for key,callback in pairs(self.Subscription) do
			self:Subscribe(key,callback)
		end
	end

end


--[[
Destroi o componente, limpando referências e parando processos
]]
function HealthComponent:Destroy()
	self.Entity = nil
	self.OnDamage = nil
	self.OnHeal = nil
	self.OnDeath = nil
	self.OnRevive = nil
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
	Subscribe = function(component, ...) return component:Subscribe(...) end,
}

return {
	new = HealthComponent.new,
	ExposeAPI = ExposeAPI,
	EventKey = {onDamage = "onDamage",onHeal = "onHeal",onDeath = "onDeath",onRevive = "onRevive"}
}
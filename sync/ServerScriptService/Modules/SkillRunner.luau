--=================Esse módulo controla o ciclo de vida das skills, TODAS as skills e modificadores são gerados com um SR base=================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScript = game:GetService("ServerScriptService")
local Storage = game:GetService("ServerStorage")
local StateTable = require(Storage.Modules.Combat.StateTable)
local Utils = require(ReplicatedStorage.Utils)

local SkillRunner = {}
SkillRunner.__index = SkillRunner


local STATES = {  				--Breakpoints do ciclo de vida da skill
	Idle = "Idle",
	Casting = "Casting",
	Running = "Running",
	Ended = "Ended",
}

-- Motivo do fim, entregue em ctx.reason no onCancel/onEnd (dono: StateTable.Enum.EndReasons)
local REASONS = StateTable.Enum.EndReasons

--[[
Dono único do isolamento de erro dos callbacks do ciclo de vida (onStart, onCancel, onEnd
e Own): um erro no código da skill vira warn com traceback e nunca interrompe a sequência
do motor (registro, limpeza, desregistro, onFinish).
]]
local function protect(runner, label, fn, ...)
	local ok, result = xpcall(fn, debug.traceback, ...)
	if not ok then
		warn("[SkillRunner] Erro em " .. label .. ":", runner.skillName, result)
	end
	return ok, result
end

local function endContext(runner, reason)
	local context = runner:BuildContext()
	context.reason = reason
	return context
end


function SkillRunner.new(skillModule,Entity,name,SRtype,Lineage,input) --Instancia o SkillRunner como um objeto responsável de criar a habilidade junto do EntityData para as skills utilizarem


	--================VÁRIAVEIS(FACILITAÇÃO DE ACESSO)===================--

	local self = setmetatable({}, SkillRunner)


	--======REQUIRES======--
	self.lib = require(Storage.Modules.Animation.AnimationLib) 							--Prepara a lib de animações
	self.connection = require(ServerScript.Modules.SkillScheduler) 							--Heartbeat global
	self.statusTable = require(Storage.Modules.Combat.StateTable) 						--Facilita acesso a aplicação de estados pelas skills
	self.weaponHitboxModule = require(Storage.Modules.Combat.Hitbox.ShapecastHitbox)   --Prepara o modulo do shapecast para facil acesso e criação de hitboxes


	--Remove Lineage antes de copiar os dados.
    local originalLineage = skillModule.Lineage
    skillModule.Lineage = nil

	--=====DADOS VITAIS=====--

	-- Instancia a skill como uma classe isolada usando o módulo como __index
	self.skill = setmetatable({}, { __index = skillModule })
	self.Entity = Entity		 				 --Tabela de dados do player que usou a habilidade
	self.skill.Runner = self                     --Opção A: Skill tem acesso ao Runner
	self.skill.Entity = Entity                   --Opção A: Skill continua acessando Entity pelo self


	--=====INICIALIZAÇÃO SR=====--
	local runnerType = self.skill.data.type or SRtype

	self.state = STATES.Idle 	 		--Estado do lifetime skill
	self.elapsedTime = 0    	 		--Tempo de vida atual da skill
	self.skill.counter = 1      		--Pode ser utilizado por skills e/ou status pra manter controle de dados de runtime internos, como número de balas, stage, ou stacks aplicados
	self.type = runnerType		 		--Tipo de SR, Skill, Status
	self.skillName = name  		 		--Guarda o nome da skill pra controle de runners ativos
	self.input = input					--Input/intenção que originou o chamado (permitindo hold e release)


	--=====FACILITADORES DE ACESSO=====--

	if self.Entity then
		
		if Entity:HasComponent(Entity.ComponentKey.Animation) then
			self.charLib = self.lib.character[self.Entity.GetChosenChar()] 	--Biblioteca de animações do char escolhido
			self.skill.charLib = self.charLib                               --Opção A
		end

		if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then

			self.hitPoint = self.Entity.GetHitOrigin() 							--Origem de hitboxes criadas em runtime pela arma
			self.weapon = self.Entity.GetWeapon()						   	    --Arma sendo utilizada pelo player
			
			self.skill.hitPoint = self.hitPoint                                 --Opção A
			self.skill.weapon = self.weapon                                     --Opção A
		end
	end


	self.data      = skillModule.data
	self.callbacks = skillModule.callbacks
	self.utils     = skillModule.utils or {}
	
	self.skill.statusTable = self.statusTable                                   --Opção A
	self.skill.weaponHitboxModule = self.weaponHitboxModule                     --Opção A

	-- Injeção de métodos do Runner na Skill (Opção A - Seamless)
	self.skill.Stop = function(_, ...) return self:Stop(...) end
	self.skill.TriggerAction = function(_, ...) return self:TriggerAction(...) end
	self.skill.Recast = function(_, ...) return self:Recast(...) end
	self.skill.endSkill = function(_, ...) return self:endSkill(...) end

	-- Ownership automático (Regra 2): a skill registra limpezas/inscrições aqui em vez de
	-- montar seu próprio "self.cleanUp" chamado à mão em onEnd E onCancel.
	self._ownedCleanups = {}
	self.skill.Own = function(_, cleanupFn) return self:Own(cleanupFn) end
	self.skill.Listen = function(_, sub) return self:Listen(sub) end
	self.skill.Damage = function(_, targetEntity, amount) return self:Damage(targetEntity, amount) end
	self.skill.ApplyStatus = function(_, statusData, opts) return self:ApplyStatus(statusData, opts) end

	--=====HISTÓRICO DE INTERAÇÕES SEQUENCIAIS=====--

	skillModule.Lineage = originalLineage
	local parentLineage = Lineage or originalLineage

	local lineageData = {
		Entity = Entity,
		name = name,
		ParentLineage = parentLineage
	}
	self.Lineage = self.statusTable.BuildHistory(lineageData)

	return self
end




--================================================
--				 LIFECYCLE
--================================================

function SkillRunner:BuildContext()
	return {
		depth = self.Lineage and self.Lineage.Depth or 1,
		history = {}, -- mantido por compatibilidade temporária
		rootOrigin = self.Lineage and self.Lineage.Root.Origin or nil,
		sourceRunner = self,
		input = self.input,
		inherited = {}
	}
end

function SkillRunner:_fire(breakpoint, context, ...)
	if self.skill.callbacks[breakpoint] then
		return self.skill.callbacks[breakpoint](self.skill, context, ...)
	end
	return nil
end

--[[
Registra e inicia o runner.
@return false se o onStart falhou (o runner já foi cancelado e limpo) BOOLEAN
]]
function SkillRunner:start(): boolean
	--Conecta com a skill ao heartbeat global.
		self.connection.Register(self,self.type)

	
	self.state = STATES.Casting --Estado de inicialização da skill


	-- Só skills são "ativas" e donas da hitbox da arma. Um status homônimo de uma skill aparecia
	-- em GetActiveSkills e o SkillHandler o tratava como a skill já ativa; e um status no
	-- portador recebia o onHit de todo golpe da arma
	if self.Entity and self.type == StateTable.Enum.Types.Skill then
		if self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
			self.Entity.AddActiveSkill(self.skillName,self)
		end

		 if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then
			self.Entity.AddHitboxOwner(self) --Informa que o dono da skill é esse skillRunner, permitindo que o wrapper chame o onHit direto por aqui
		end
	end

	
	--Confere se existe onStart na skill, se sim, roda. Erro no onStart cancela o runner na
	--hora (F14): antes o erro escapava do SkillHandler e o runner ficava registrado, com o
	--que o onStart tivesse feito até ali.
	if not protect(self, "onStart", self._fire, self, "onStart", self:BuildContext()) then
		self:endSkill(true)
		-- Erro não aceita veto: se o onCancel recusou o cancel, encerra mesmo assim
		if not self:IsEnded() then self:endSkill(false, REASONS.Cancel) end
		return false
	end

	-- A skill pode ter se encerrado dentro do próprio onStart: não anuncia início depois do fim
	if self.state == STATES.Ended then return true end

	if self.Entity then
		self.Entity:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onStart, self:BuildContext())
	end
	return true
end


--[[
Controla o tempo de execução do SkillRunner (atualizado pelo Heartbeat global)
]]
function SkillRunner:_internalUpdate(dt)

	-- TODO: reintroduzir Pipeline/Limites de fila aqui em vez do MAX_RECURSION global

	--Se a skill não tiver onStep, nao rode heartbeat
	if self.connection == nil then return end


	--Controle do timer da skill
	 self.elapsedTime += dt


	--Se estiver castando algo, confere se já terminou a duração do cast, se sim, mude o estado para "rodando"
	if self.state == STATES.Casting then
		local castTime = self.skill.data.castTime or 0
		if self.elapsedTime >= castTime then
			self.state  = STATES.Running 
			self.elapsedTime = 0
		end

	--Se estiver running:
	elseif self.state == STATES.Running then
		self:_fire("onStep", dt, self:BuildContext())
	end

	local duration = self.skill.runtimeDuration or self.skill.data.duration

	--Se a skill tiver zerado sua duração, então: 
	if duration and self.elapsedTime >= duration then
		self:endSkill(false, REASONS.Duration)
	end
	
end

--[[Callback ao atingir algo]]
function SkillRunner:onHit(data)
	self:_fire("onHit", data, self:BuildContext())
end


--[[Recast de runner. Runner encerrado não aceita recast: o SkillHandler já filtra os vivos,
mas quem guardou a referência (stack de status, script de jogo) cairia no onRecast de uma
skill morta]]
function SkillRunner:Recast(checkOnly : boolean?,input)
	if self.state == STATES.Ended then return false end

	if self.skill.callbacks.onRecast ~= nil then
		
		if checkOnly then return true end
		
		if input then self.input = input end
		
		self:_fire("onRecast", self:BuildContext())
		return true
	end
	return false
end


--[[
Release do botão que startou a skill: se existir onRelease, executa; se não, NÃO faz nada (retorna false) e a skill segue até a duração/cleanup próprios
@param input - InputEvent (Kind = Release, HeldTime = segundos segurado)
@return rodou onRelease BOOLEAN
]]
function SkillRunner:Release(input)
	if self.state == STATES.Ended then return false end

	if not self.skill.callbacks.onRelease then return false end

	self.input = input
	self:_fire("onRelease", self:BuildContext())
	return true
end

--[[
Trigger externo, usado especialmente mas não exclusivamente por blocks e shields de efeitos
@param data - dados de quem deu trigger
]]
function SkillRunner:TriggerAction(context)
	-- Escudo/block encerrado não reage. Durante o próprio teardown (onEnd, OUT.onEnd) o cache de
	-- tags do StatusComponent ainda aponta para este runner: ele só é invalidado no onFinish
	if self.state == STATES.Ended then return nil end

    local skillSettings = self.skill.data
    local hasFilterConfig = skillSettings.ShieldsFrom or skillSettings.ShieldsFromType

    if hasFilterConfig then
        if not self.statusTable.CheckBlockFilter(self, context) then
            return nil 
        end
    end
											--Então cancela o trigger
		if self.skill.callbacks.onTrigger then
    	    return self:_fire("onTrigger", context, self:BuildContext())
    	end
    
    return nil
end


--[[Cancela a skill
@param cancel - boolean, se a skill foi cancelada forçadamente de forma externa
]]
function SkillRunner:IsEnded()
	return self.state == STATES.Ended
end

--[[
Registra uma função de limpeza que roda automaticamente em endSkill (onEnd OU onCancel).
]]
function SkillRunner:Own(cleanupFn: () -> ())
	-- Já encerrado (ex.: um onHit que chegou depois do fim): não existe fim futuro para rodar
	-- a limpeza, então ela roda agora em vez de vazar (um grab que nunca seria solto)
	if self.state == STATES.Ended then
		protect(self, "Own() cleanup", cleanupFn)
		return
	end
	table.insert(self._ownedCleanups, cleanupFn)
end

--[[
Atalho pra Entity:Listen que já marca Owner = este runner: a inscrição é removida
sozinha quando a skill terminar (UnsubscribeByOwner em endSkill), sem precisar de
um "comboOwner" montado à mão pelo autor da skill.
]]
function SkillRunner:Listen(sub: any)
	sub.Owner = sub.Owner or self
	if self.Entity then
		return self.Entity:Listen(sub)
	end
	return function() end
end

--[[
Aplica dano com ESTE runner como source. Existe pra acabar com a inconsistência de
skills passando `self` (o proxy) em vez de `self.Runner` — o que fazia ShieldsFromType
e outras checagens de trait nunca casarem (source.type não existia no proxy).
]]
function SkillRunner:Damage(targetEntity, amount)
	if not self.Entity or not self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
		warn("[SkillRunner] Damage chamado sem CombatComponent na entidade de origem:", self.skillName)
		return false, 0
	end
	return self.Entity.ApplyDamage(amount, self, targetEntity)
end

--[[
Aplica um status com Source = este runner por padrão (a skill pode sobrescrever via
opts.Source, ou opts.Target pra mirar outra entidade). O opts do chamador não é alterado: uma
skill que reusa uma tabela constante (local OPTS = { Duration = 2 }) fazia o primeiro runner
gravar nela o próprio Source, que passava a valer para todo cast seguinte.
]]
function SkillRunner:ApplyStatus(statusData, opts)
	local statusOpts = table.clone(opts or {})
	statusOpts.Source = statusOpts.Source or self
	local target = statusOpts.Target or self.Entity
	-- Target só escolhe a entidade: o StatusComponent aplica sempre na própria entidade
	statusOpts.Target = nil
	if not target then
		warn("[SkillRunner] ApplyStatus sem entidade alvo:", self.skillName)
		return nil
	end
	-- Assinatura de opts. A posicional legada recebia `opts` no lugar do ID: o ID virava a
	-- própria tabela e opts.ID era ignorado.
	return target.ApplyStatus(statusData, statusOpts)
end

function SkillRunner:Stop(cancel : boolean?)
	self:endSkill(cancel)
end


--[[
Finaliza a skill.
@param cancel - true = cancelamento: roda o onCancel antes (que pode recusar devolvendo false)
@param reason - motivo entregue em ctx.reason no onCancel/onEnd e no OUT.onEnd
	(StateTable.Enum.EndReasons; padrão: Cancel se cancel, senão Stop)
]]
function SkillRunner:endSkill(cancel, reason)

	-- _ending protege contra re-entrada (onCancel chamando Stop)
	if self.state == STATES.Ended or self._ending then return end

	reason = reason or (cancel and REASONS.Cancel or REASONS.Stop)

	if cancel then
		-- state só vira Ended DEPOIS: se a skill recusar o cancel (onCancel == false), ela continua viva
		self._ending = true
		local ok, result = protect(self, "onCancel", self._fire, self, "onCancel", endContext(self, reason))
		self._ending = nil

		if ok and result == false then
			return
		end
	end

	self.state = STATES.Ended

	-- Ownership automático: desinscreve os Listen() e roda os Own() antes do onEnd
	if self.Entity then
		self.Entity:UnsubscribeByOwner(self)
	end
	for _, cleanupFn in self._ownedCleanups do
		protect(self, "Own() cleanup", cleanupFn)
	end
	table.clear(self._ownedCleanups)

	--Sequência de finalização padrão. onEnd SEMPRE roda (também depois do onCancel) e recebe
	--ctx.reason (F54). Um erro nele não pode pular a limpeza abaixo: era o "runner fantasma"
	--do F13, que ficava em ActiveSkills e recebia o recast do próximo toque.
	protect(self, "onEnd", self._fire, self, "onEnd", endContext(self, reason))

	if self.Entity and self.type == StateTable.Enum.Types.Skill then
		if self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
			self.Entity.RemoveActiveSkill(self.skillName, self)
		end
		-- Simétrico ao start: com Weapon e sem Combat o runner ficava dono da hitbox para sempre
		if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then
			self.Entity.RemoveHitboxOwner(self) --Limpa a hitbox
		end
	end

	if self.Entity and self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
		-- A trava de ação deste runner sai com ele (só remove se for dele; idempotente). Uma skill
		-- que esquecesse o RemoveActionState, ou desse erro antes dele, deixava o ActionState
		-- apontando para um runner morto, e o TrySelfCancel recusava toda skill nova da entidade.
		-- Antes do OUT.onEnd: um listener de fim pode castar outra skill
		self.Entity.RemoveActionState(self)
	end

	-- Par do OUT.onStart, que vale para qualquer entidade: emitido também sem Combat
	if self.Entity then
		self.Entity:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onEnd, endContext(self, reason))
	end

	if self.connection then
		self.connection.Unregister(self,self.type) --Sai do heartbeat global
		self.connection = nil
	end

	-- Sempre limpar o runner e notificar
	if self.onFinish then self.onFinish() end
end

return SkillRunner

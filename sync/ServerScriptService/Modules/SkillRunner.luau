-- SkillRunner: ciclo de vida de uma ativação de skill ou status (Idle -> Casting -> Running -> Ended)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScript = game:GetService("ServerScriptService")
local Storage = game:GetService("ServerStorage")
local StateTable = require(Storage.Modules.Combat.StateTable)
local Utils = require(ReplicatedStorage.Utils)
local CooldownPolicy = require(ServerScript.Modules.CooldownPolicy)
local LineageModule = require(Storage.Modules.Combat.Lineage) -- dono do formato dos nós (Types.Lineage)

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
local CHAIN = StateTable.Enum.ChainLimits
local Log = require(ReplicatedStorage.Logger).Channel("SkillRunner")

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

local function endContext(runner, reason, forListeners)
	local context = runner:BuildContext(forListeners)
	context.reason = reason
	return context
end

local NOTHING_INHERITED = table.freeze({})


--[[
Cria o runner de uma ativação (skill ou status). Não inicia: chame :start().
@param skillModule - { data, callbacks } da skill (SkillFactory)
@param Entity - entidade dona (quem casta, ou o portador do status)
@param name - nome da skill/status
@param SRtype - StateTable.Enum.Types (Skill | Status)
@param Lineage - nó pai na cadeia (nil = raiz)
@param input - Intents.InputEvent que originou o cast
@param inherited - payload explícito do pai (ctx.inherited), copiado e congelado
]]
function SkillRunner.new(skillModule,Entity,name,SRtype,Lineage,input,inherited)


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
	self.Entity = Entity		 				 --Entidade dona do runner
	self.skill.Runner = self                     --a skill acessa o runner por self.Runner
	self.skill.Entity = Entity                   --e a entidade por self.Entity


	--=====INICIALIZAÇÃO SR=====--
	local runnerType = self.skill.data.type or SRtype

	self.state = STATES.Idle 	 		--Estado do lifetime skill
	self.elapsedTime = 0    	 		--Tempo de vida atual da skill
	self.skill.counter = 1      		--Pode ser utilizado por skills e/ou status pra manter controle de dados de runtime internos, como número de balas, stage, ou stacks aplicados
	self.type = runnerType		 		--Tipo de SR, Skill, Status
	self.skillName = name  		 		--Guarda o nome da skill pra controle de runners ativos
	self.input = input					--Input/intenção que originou o chamado (permitindo hold e release)
	-- Payload do pai (Context.inherited): cópia rasa congelada, para o pai não mudar o que o filho lê
	self._inherited = inherited and table.freeze(table.clone(inherited)) or NOTHING_INHERITED


	--=====FACILITADORES DE ACESSO=====--

	if self.Entity then
		
		if Entity:HasComponent(Entity.ComponentKey.Animation) then
			-- Animações do kit dono da skill (data.kit) e, na falta, do kit de quem casta
			local casterKit = Entity:HasComponent(Entity.ComponentKey.Combat) and Entity.GetChosenChar() or nil
			self.charLib = self.lib.ForSkill(self.skill.data.kit, casterKit)
			self.skill.charLib = self.charLib
		end

		if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then

			self.hitPoint = self.Entity.GetHitOrigin() 							--Origem de hitboxes criadas em runtime pela arma
			self.weapon = self.Entity.GetWeapon()						   	    --Arma sendo utilizada pelo player
			
			self.skill.hitPoint = self.hitPoint
			self.skill.weapon = self.weapon
		end
	end


	self.data      = skillModule.data
	self.callbacks = skillModule.callbacks
	self.utils     = skillModule.utils or {}
	
	self.skill.statusTable = self.statusTable
	self.skill.weaponHitboxModule = self.weaponHitboxModule

	-- Métodos do runner expostos na skill (self:Stop(), self:Damage()...)
	self.skill.Stop = function(_, ...) return self:Stop(...) end
	self.skill.TriggerAction = function(_, ...) return self:TriggerAction(...) end
	self.skill.Recast = function(_, ...) return self:Recast(...) end
	self.skill.endSkill = function(_, ...) return self:endSkill(...) end
	self.skill.Fizzle = function(_) return self:Fizzle() end
	self.skill.GetRemainingTime = function(_) return self:GetRemainingTime() end
	self.skill.StartHitbox = function(_, duration) return self:StartHitbox(duration) end
	self.skill.StopHitbox = function(_) return self:StopHitbox() end
	self.skill.CommitCooldown = function(_) return self:CommitCooldown() end

	-- Limpezas (Own) e inscrições (Listen) da skill saem sozinhas no fim do runner
	self._ownedCleanups = {}
	self.skill.Own = function(_, cleanupFn) return self:Own(cleanupFn) end
	self.skill.Listen = function(_, sub) return self:Listen(sub) end
	self.skill.Damage = function(_, targetEntity, amount, opts) return self:Damage(targetEntity, amount, opts) end
	self.skill.ApplyStatus = function(_, statusData, opts) return self:ApplyStatus(statusData, opts) end

	--=====HISTÓRICO DE INTERAÇÕES SEQUENCIAIS=====--

	skillModule.Lineage = originalLineage
	local parentLineage = Lineage or originalLineage

	local lineageData = {
		Entity = Entity,
		name = name,
		ParentLineage = parentLineage,
		Runner = self, -- o filho acha o runner anterior pelo nó (ctx.sourceRunner)
	}
	self.Lineage = self.statusTable.BuildHistory(lineageData)

	return self
end




--================================================
--				 LIFECYCLE
--================================================

--[[
Monta o contexto do ciclo de vida (Types.RunnerContext). history e inherited são congelados e
calculados uma vez por runner (o onStep monta um contexto por frame).
@param forListeners - true no evento que este runner emite (OUT.onStart/onEnd): para quem escuta,
	o runner anterior é este. Nos callbacks do próprio runner, é quem o aplicou/criou
]]
function SkillRunner:BuildContext(forListeners: boolean?)
	local lineage = self.Lineage
	if not self._history then
		self._history = table.freeze(lineage and LineageModule.GetHistoryArray(lineage) or { self.skillName })
	end
	local parent = lineage and lineage.Parent
	return {
		depth = lineage and lineage.Depth or 1,
		history = self._history,
		rootOrigin = lineage and lineage.Root.Origin or nil,
		sourceRunner = if forListeners then self else (parent and parent.Runner),
		input = self.input,
		inherited = self._inherited,
	}
end

function SkillRunner:_fire(breakpoint, context, ...)
	if self.skill.callbacks[breakpoint] then
		return self.skill.callbacks[breakpoint](self.skill, context, ...)
	end
	return nil
end

-- Primeiro componente de data.requires que a entidade não tem (nil = todos presentes)
local function missingRequirement(runner)
	local requires = runner.skill.data.requires
	if not requires then return nil end
	local entity = runner.Entity
	for _, componentName in requires do
		if not entity or not entity:HasComponent(componentName) then
			return componentName
		end
	end
	return nil
end

--[[
Registra e inicia o runner.
@return false se o onStart falhou ou o motor recusou o início (o runner já foi encerrado e limpo) BOOLEAN
]]
function SkillRunner:start(): boolean
	-- data.requires: sem os componentes declarados a skill não começa (em vez de errar no onStart)
	local missing = missingRequirement(self)
	if missing then
		return self:_RefuseStart("Requires:" .. tostring(self.skillName) .. ":" .. missing,
			tostring(self.skillName) .. " declara requires = { " .. missing .. " }, e a entidade "
				.. tostring(self.Entity and self.Entity.ID) .. " não tem o componente")
	end

	-- Largura da cadeia assíncrona: no máximo ChainLimits.maxLiveRunnersPerRoot vivos por raiz da Lineage
	local root = self.Lineage and self.Lineage.Root
	if root then
		local live = root.LiveRunners or 0
		if live >= CHAIN.maxLiveRunnersPerRoot then
			return self:_RefuseStart("ChainWidth:" .. tostring(root.Cause),
				"cadeia assíncrona larga demais: " .. live .. " runners vivos sob a raiz " .. tostring(root.Cause)
					.. " (Enum.ChainLimits.maxLiveRunnersPerRoot); não iniciou: " .. tostring(self.skillName))
		end
		root.LiveRunners = live + 1
		self._chainRoot = root
	end

	--Conecta com a skill ao heartbeat global.
		self.connection.Register(self,self.type)

	
	self.state = STATES.Casting --Estado de inicialização da skill


	-- Só skills entram em ActiveSkills e recebem os acertos da arma (status não)
	if self.Entity and self.type == StateTable.Enum.Types.Skill then
		if self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
			self.Entity.AddActiveSkill(self.skillName,self)
		end

		 if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then
			self.Entity.AddHitboxOwner(self) --Informa que o dono da skill é esse skillRunner, permitindo que o wrapper chame o onHit direto por aqui
		end
	end

	
	-- Erro no onStart encerra o runner na hora (motivo error)
	if not protect(self, "onStart", self._fire, self, "onStart", self:BuildContext()) then
		self:Abort()
		return false
	end

	-- A skill pode ter se encerrado dentro do próprio onStart: não anuncia início depois do fim
	if self.state == STATES.Ended then return true end

	if self.Entity then
		self.Entity:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onStart, self:BuildContext(true))
	end
	return true
end

--[[
O motor não deixa o runner começar (data.requires ausente, Enum.ChainLimits). Nenhum callback roda e
nada é registrado; o cooldown cobrado na ativação volta pelo refund do motivo refused (padrão:
inteiro), e o onFinish tira o status do registro do StatusComponent. Um aviso por `warnKey` (as
repetições saem em Debug).
]]
function SkillRunner:_RefuseStart(warnKey: string, message: string): boolean
	Log.WarnOnce(warnKey, message)
	self.state = STATES.Ended
	if self._cooldownState then
		protect(self, "CooldownPolicy.OnEnd", CooldownPolicy.OnEnd, self, REASONS.Refused)
	end
	if self.onFinish then self.onFinish() end
	return false
end


--[[
Controla o tempo de execução do SkillRunner (atualizado pelo Heartbeat global)
]]
function SkillRunner:_internalUpdate(dt)

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
		-- Só monta contexto para quem tem onStep (custo por frame)
		if self.skill.callbacks.onStep then
			self:_fire("onStep", dt, self:BuildContext())
		end
	end

	local duration = self.skill.runtimeDuration or self.skill.data.duration

	--Se a skill tiver zerado sua duração, então: 
	if duration and self.elapsedTime >= duration then
		self:endSkill(false, REASONS.Duration)
	end
	
end

--[[
Callbacks de evento pontual (onHit, onRecast, onRelease, onTrigger): um erro vira warn com
traceback e a skill segue. (Erro no onStep encerra a skill: SkillScheduler.)
]]
function SkillRunner:_fireEvent(breakpoint, ...)
	local ok, result = protect(self, breakpoint, self._fire, self, breakpoint, ...)
	if ok then return result end
	return nil
end

--[[Callback ao atingir algo]]
function SkillRunner:onHit(data)
	self:_fireEvent("onHit", data, self:BuildContext())
end


--[[
Recast do runner (o SkillHandler chama no toque seguinte). Runner encerrado recusa.
@param checkOnly - true = só responde se a skill tem onRecast
@param input - InputEvent do toque
]]
function SkillRunner:Recast(checkOnly : boolean?,input)
	if self.state == STATES.Ended then return false end

	if self.skill.callbacks.onRecast ~= nil then
		
		if checkOnly then return true end
		
		if input then self.input = input end
		
		self:_fireEvent("onRecast", self:BuildContext())
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
	self:_fireEvent("onRelease", self:BuildContext())
	return true
end

--[[
Trigger externo (bloqueios e escudos de efeito). Com onTrigger, ele decide; sem onTrigger, vale o
data.block declarado (StateTable.ResolveBlock); sem nenhum dos dois, não bloqueia e avisa uma vez.
@param context - HitContext de quem disparou
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
		if self.skill.callbacks.onTrigger then
    	    return self:_fireEvent("onTrigger", context, self:BuildContext())
    	end

    return self.statusTable.ResolveBlock(self.data, context)
end


--[[ O runner já terminou? ]]
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
Atalho para Entity:Listen com Owner = este runner: a inscrição sai sozinha quando a skill termina.
]]
function SkillRunner:Listen(sub: any)
	sub.Owner = sub.Owner or self
	if self.Entity then
		return self.Entity:Listen(sub)
	end
	return function() end
end

--[[
Aplica dano com este runner como source (CombatComponent:ApplyDamage).
@param targetEntity - EntityCore
@param amount - dano base NUMBER
@param opts - Types.DamageOptions? (traits e efeitos deste hit, ponto do impacto, Prescaled, Inherited)
]]
function SkillRunner:Damage(targetEntity, amount, opts)
	if not self.Entity or not self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
		warn("[SkillRunner] Damage chamado sem CombatComponent na entidade de origem:", self.skillName)
		return false, 0
	end
	return self.Entity.ApplyDamage(amount, self, targetEntity, opts)
end

--[[
Aplica um status com Source = este runner. opts.Target escolhe outra entidade (padrão: a própria);
o opts do chamador não é alterado.
@param opts - { Duration?, ID?, Target?, Source?, Inherited? }
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
	return target.ApplyStatus(statusData, statusOpts)
end

function SkillRunner:Stop(cancel : boolean?)
	self:endSkill(cancel)
end

--[[
Encerra por erro: tenta o cancel normal e, se o onCancel recusar, encerra mesmo assim (erro não
aceita veto: onStart no start, onStep no SkillScheduler).
]]
function SkillRunner:Abort()
	self:endSkill(true, REASONS.Error)
	if not self:IsEnded() then self:endSkill(false, REASONS.Error) end
end

--[[
Hitbox da arma deste runner: liga, desliga e recebe os acertos sem afetar a de outra skill.
A skill chama self:StartHitbox(duração) / self:StopHitbox(); a do runner sai sozinha no fim.
]]
function SkillRunner:StartHitbox(duration: number)
	if not self.Entity or not self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then return false end
	return self.Entity.StartHitbox(duration, self)
end

function SkillRunner:StopHitbox()
	if not self.Entity or not self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then return end
	self.Entity.StopHitbox(self)
end

--[[
Segundos até o fim pela duração (runtimeDuration ou data.duration); nil se a skill não tem
duração. Durante o castTime devolve a duração inteira (ela só começa a contar no Running).
]]
function SkillRunner:GetRemainingTime(): number?
	local duration = self.skill.runtimeDuration or self.skill.data.duration
	if not duration then return nil end
	if self.state ~= STATES.Running then return duration end
	return math.max(0, duration - self.elapsedTime)
end

--[[
A skill desiste do cast (alvo não encontrado, condição que não bateu). Encerra com o motivo
fizzle, que por padrão devolve o cooldown inteiro (Enum.CooldownDefaults.refund).
]]
function SkillRunner:Fizzle()
	self:endSkill(false, REASONS.Fizzle)
end

--[[
Confirma o cooldown de uma skill com cooldownPolicy.start = Manual (o cast de fato aconteceu).
@return confirmou BOOLEAN
]]
function SkillRunner:CommitCooldown(): boolean
	return CooldownPolicy.Commit(self)
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

	-- Devolve a vaga na raiz da cadeia logo no fim: nada abaixo pode pular isto
	if self._chainRoot then
		self._chainRoot.LiveRunners -= 1
		self._chainRoot = nil
	end

	-- Ownership automático: desinscreve os Listen() e roda os Own() antes do onEnd
	if self.Entity then
		self.Entity:UnsubscribeByOwner(self)
	end
	for _, cleanupFn in self._ownedCleanups do
		protect(self, "Own() cleanup", cleanupFn)
	end
	table.clear(self._ownedCleanups)

	-- onEnd sempre roda (também depois do onCancel) e recebe ctx.reason; um erro nele não pula a limpeza abaixo
	protect(self, "onEnd", self._fire, self, "onEnd", endContext(self, reason))

	-- Cooldown do fim (start = End) e devolução por motivo (refund). Só runners de cast
	if self._cooldownState then
		protect(self, "CooldownPolicy.OnEnd", CooldownPolicy.OnEnd, self, reason)
	end

	if self.Entity and self.type == StateTable.Enum.Types.Skill then
		if self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
			self.Entity.RemoveActiveSkill(self.skillName, self)
		end
		-- Simétrico ao start (vale também sem Combat)
		if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then
			self.Entity.RemoveHitboxOwner(self) --Limpa a hitbox
		end
	end

	if self.Entity and self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
		-- A trava de ação deste runner sai com ele (só se for dele), antes do OUT.onEnd: um listener
		-- de fim pode castar outra skill
		self.Entity.RemoveActionState(self)
	end

	-- Par do OUT.onStart, que vale para qualquer entidade: emitido também sem Combat
	if self.Entity then
		self.Entity:Emit(StateTable.Enum.Roles.OUT, StateTable.Enum.Breakpoints.onEnd, endContext(self, reason, true))
	end

	if self.connection then
		self.connection.Unregister(self,self.type) --Sai do heartbeat global
		self.connection = nil
	end

	-- Sempre limpar o runner e notificar
	if self.onFinish then self.onFinish() end
end

return SkillRunner

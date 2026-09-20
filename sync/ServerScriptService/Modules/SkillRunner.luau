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


function SkillRunner.new(skillModule,Entity,name,SRtype,ChainHistory) --Instancia o SkillRunner como um objeto responsável de criar a habilidade junto do EntityData para as skills utilizarem


	--================VÁRIAVEIS(FACILITAÇÃO DE ACESSO)===================--

	local self = setmetatable({}, SkillRunner)


	--======REQUIRES======--
	self.lib = require(Storage.Modules.Animation.AnimationLib) 							--Prepara a lib de animações
	self.connection = require(ServerScript.Modules.SkillScheduler) 							--Heartbeat global
	self.statusTable = require(Storage.Modules.Combat.StateTable) 						--Facilita acesso a aplicação de estados pelas skills
	self.weaponHitboxModule = require(Storage.Modules.Combat.Hitbox.ShapecastHitbox)   --Prepara o modulo do shapecast para facil acesso e criação de hitboxes


	--Remove ChainHistory antes de copiar os dados.
    local originalChainHistory = skillModule.ChainHistory
    skillModule.ChainHistory = nil

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

	--=====HISTÓRICO DE INTERAÇÕES SEQUENCIAIS=====--

	--Retorna o ChainHistory
	skillModule.ChainHistory = originalChainHistory

	--Se a skill já tem um histórico, então salve no runner e adicione mais no contexto
    if skillModule.ChainHistory then
		skillModule.ChainHistory.depth += 1
		table.insert(skillModule.ChainHistory.history,name)
        self.ChainHistory = skillModule.ChainHistory
	elseif ChainHistory then -- se não tiver mas foi fornecido, salve na skill aqui
		skillModule.ChainHistory = ChainHistory
		self.ChainHistory = ChainHistory
	else
     -- Por fim, se não existe ChainHistory e nem foi fornecido, crie um aqui
        local data = {
			rootOrigin = Entity and Entity or nil,
			rootSkill = name or nil,
		}
		self.ChainHistory = StateTable.BuildHistory(data)

    end

	if tick() - self.ChainHistory.lastInteraction >= 1 then
		self.ChainHistory.lastInteraction = tick()
		self.ChainHistory.tempDepth = 1 
	else
		self.ChainHistory.tempDepth += 1
	end

	self.data.ChainHistory = self.ChainHistory


	if self.ChainHistory.tempDepth >= self.statusTable.Enum.MAX_RECURSION then
		return nil
	end

	return self
end




--================================================
--				 LIFECYCLE
--================================================

function SkillRunner:BuildContext()
	return {
		depth = self.ChainHistory and self.ChainHistory.tempDepth or 1,
		history = self.ChainHistory and self.ChainHistory.history or {},
		rootOrigin = self.ChainHistory and self.ChainHistory.rootOrigin or nil,
		sourceRunner = self,
		inherited = {}
	}
end

function SkillRunner:start()
	--Conecta com a skill ao heartbeat global.
		self.connection.Register(self,self.type)

	
	self.state = STATES.Casting --Estado de inicialização da skill


	if self.Entity then
		if self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
			self.Entity.AddActiveSkill(self.skillName,self)	
		end
		
		 if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then
			self.Entity.AddHitboxOwner(self) --Informa que o dono da skill é esse skillRunner, permitindo que o wrapper chame o onHit direto por aqui
		end
	end

	
	--Confere se existe onStart na skill, se sim, roda
	if self.skill.callbacks.onStart then
		self.skill.callbacks.onStart(self.skill, self:BuildContext()) --Executa onStart tendo acesso a propria classe e o contexto
	end
	
end


--[[
Controla o tempo de execução do SkillRunner (atualizado pelo Heartbeat global)
]]
function SkillRunner:_internalUpdate(dt)

	--Se muitas interações acontecerem em pouco tempo, corta a execução
	if self.ChainHistory.tempDepth >= self.statusTable.Enum.MAX_RECURSION then
		self:endSkill(false)
	end

	--Se a skill não tiver onStep, nao rode heartbeat
	if self.connection == nil then return end


	--Controle do timer da skill
	 self.elapsedTime += dt


	--Se estiver castando algo, confere se já terminou a duração do cast, se sim, mude o estado para "rodando"
	if self.state == STATES.Casting then
		if self.skill.data.castTime and self.elapsedTime >= self.skill.data.castTime then
			self.state  = STATES.Running 
			self.elapsedTime = 0
		end

	--Se estiver running:
	elseif self.state == STATES.Running then
		if self.skill.callbacks.onStep then  --confere  se o skill tem onStep para rodar scripts em frames/tempos especificos, se tiver, rode o onStep do frame atual
			self.skill.callbacks.onStep(self.skill, dt, self:BuildContext())
		end
	
	end

	local duration = self.skill.runtimeDuration or self.skill.data.duration

	--Se a skill tiver zerado sua duração, então: 
	if duration and self.elapsedTime >= duration then
		self:endSkill(false)
	end
	
end

--[[Callback ao atingir algo]]
function SkillRunner:onHit(data)
	if self.skill.callbacks.onHit then
		self.skill.callbacks.onHit(self.skill, data, self:BuildContext())
	end
	
end


--[[Recast de runner]]
function SkillRunner:Recast(checkOnly : boolean?)
	
	--Procura se tem onRecast, se tiver, roda e fala que encontrou
	if self.skill.callbacks.onRecast ~= nil then
		
		--Se for um pedido de teste, retorna antes de rodar o recast
		if checkOnly then return true end
		
		--roda o onRecast com contexto pra permitir informar o motivo/origem do recast
		self.skill.callbacks.onRecast(self.skill, self:BuildContext())
		return true
	end
	return false
end


--[[
Trigger externo, usado especialmente mas não exclusivamente por blocks e shields de efeitos
@param data - dados de quem deu trigger
]]
function SkillRunner:TriggerAction(context)
    local skillSettings = self.skill.data
    local hasFilterConfig = skillSettings.ShieldsFrom or skillSettings.ShieldsFromType

    if hasFilterConfig then
        if not self.statusTable.CheckBlockFilter(self, context) then
            return nil 
        end
    end
											--Então cancela o trigger
		if self.skill.callbacks.onTrigger then
    	    return self.skill.callbacks.onTrigger(self.skill, context, self:BuildContext())
    	end
    
    return nil
end


--[[Cancela a skill
@param cancel - boolean, se a skill foi cancelada forçadamente de forma externa
]]
function SkillRunner:Stop(cancel : boolean?)
	self:endSkill(cancel)
end


--Finaliza a skill
function SkillRunner:endSkill(cancel)
	
	if self.state == STATES.Ended then return end
	self.state = STATES.Ended

	--Se foi cancelada externamente
	if cancel then
		if self.skill.callbacks.onCancel then
   			if self.skill.callbacks.onCancel(self.skill, self:BuildContext()) == false then return end --Permita que somente a ação ocorra sem parar a skill.
		end
	end	


	--Sequência de finalização padrão
	if self.skill.callbacks.onEnd then
		self.skill.callbacks.onEnd(self.skill, self:BuildContext())
	end
	
	if self.Entity and self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then
		self.Entity.RemoveActiveSkill(self.skillName, self)
		if self.Entity:HasComponent(self.Entity.ComponentKey.Weapon) then
			self.Entity.RemoveHitboxOwner(self) --Limpa a hitbox
	end
end


	if self.connection then
		self.connection.Unregister(self,self.type) --Sai do heartbeat global
		self.connection = nil
	end

	-- Sempre limpar o runner e notificar
	if self.onFinish then self.onFinish() end
	
end

return SkillRunner

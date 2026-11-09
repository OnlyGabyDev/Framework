local SkillHandler = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local Storage = game:GetService("ServerStorage")

local SkillRunner = require(Server.Modules.SkillRunner)
local DataManager = require(Server.EntityData.DataManager)
local SkillFactory = require(Server.Modules.SkillFactory)
local StateTable = require(Storage.Modules.Combat.StateTable)
local Intents = require(ReplicatedStorage.Input.Intents)
local Log = require(ReplicatedStorage.Logger).Channel("SkillHandler")
local CooldownPolicy = require(Server.Modules.CooldownPolicy)

--=============================================================================
--  EIXOS (Move / Look)
--=============================================================================

function SkillHandler.HandleMovementInput(ID, dir)
	local entityCore = DataManager.Get(ID)
	if not entityCore then return false end
	if typeof(dir) ~= "Vector3" then return false end

	local flat = Vector3.new(dir.X, 0, dir.Z)
	local n = flat.Magnitude > 0.01 and flat.Unit or Vector3.zero

	-- Corpo sem Movement (ex.: torre possuída) ignora o próprio eixo em vez de cair no stub e
	-- gerar um warn por RequestDir (F58); os corpos linkados continuam recebendo
	if entityCore:HasComponent(entityCore.ComponentKey.Movement) then
		entityCore.SetDirection(n)
	end

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

--[[
Mesmo padrão de HandleMovementInput. LookDirection é "plana" por contrato
(ver LookDirectionBroadcaster.client.luau e MovementComponent:SetLookDirection).
]]
function SkillHandler.HandleLookInput(ID, look)
	local entityCore = DataManager.Get(ID)
	if not entityCore then return false end
	if typeof(look) ~= "Vector3" then return false end
	if look.Magnitude < 0.01 then return false end

	if entityCore:HasComponent(entityCore.ComponentKey.Movement) then
		entityCore.SetAimDirection(look.Unit)
	end

	if entityCore:HasComponent(entityCore.ComponentKey.Control) then
		for _, linkedEntity in ipairs(entityCore.GetLinkedEntities("MirrorLook")) do
			if linkedEntity:HasComponent(linkedEntity.ComponentKey.Movement) then
				linkedEntity.SetAimDirection(look.Unit)
			end
		end
	end

	return true
end

--=============================================================================
--  INTENTS
--=============================================================================

--[[
Gestos que a skill do slot declarou em data.input (nil = ativa no Press).
O InputValidator precisa disso ANTES de alimentar o GestureResolver: a spec define quais gestos existem
e, portanto, quanto tempo a ativação espera.
@param entityCore - EntityCore
@param intent - Intents.Id
@return Intents.GestureSpec ou nil
]]
function SkillHandler.GetGestureSpec(entityCore, intent)
	if not entityCore:HasComponent(entityCore.ComponentKey.Combat) then return nil end

	local skill = entityCore.GetSkillFromSlot(intent)
	return skill and skill.data and skill.data.input or nil
end

--[[
Guarda qual runner a intent está segurando, para o Release chegar no runner certo
]]
local function track(entityCore, event, runner)
	if event.Gesture ~= Intents.Gesture.Tap then
		entityCore.SetIntentRunner(event.Intent, runner)
	end
end

--[[
Runners vivos da skill. Um runner Ended que ainda esteja listado (limpeza que falhou no
passado) sai do registro aqui em vez de receber recast: era o "runner fantasma" do F13, que
fazia o próximo toque cair no onRecast de uma skill morta.
]]
local function liveRunners(entityCore, skillName)
	local live = {}
	for _, runner in ipairs(table.clone(entityCore.GetActiveSkills(skillName))) do
		if runner:IsEnded() then
			entityCore.RemoveActiveSkill(skillName, runner)
		else
			table.insert(live, runner)
		end
	end
	return live
end

local function activate(entityCore, event)
	local skillData = entityCore.GetSkillFromSlot(event.Intent)
	if not skillData then return false end

	local skill = SkillFactory.GetSkill(skillData)
	local skillName = skill.data.name
	local maxInstances = skill.data.maxInstances --Guarda a quantidade máximas de instâncias permitida daquela skill
	local activeRunners = liveRunners(entityCore, skillName) --Busca instâncias ativas (vivas) da skill na entidade

	--Busca por tags que impossibilitem a entidade de castar essa skill
	if not entityCore.CanContinue(skill) then
		Log.Debug("skill não pode rodar (canCast):", skillName)
		return false
	end

	--Se já tiver uma instância ativa dessa skill e for maior do que o máximo
	if #activeRunners > 0 and #activeRunners >= maxInstances then
		if maxInstances == 1 then
			local runner = activeRunners[1]
			-- Tenta recast primeiro (runner permanece vivo, sem Stop). Se o recast espera ou
			-- reinicia o cooldown é a política declarada da skill (cooldownPolicy.recast, D13)
			if runner:Recast(true) then
				if not CooldownPolicy.CanRecast(entityCore, runner) then return false end
				runner:Recast(nil, event)
				CooldownPolicy.OnRecast(entityCore, runner)
				track(entityCore, event, runner)
				return true, skillName, entityCore.GetCooldown(skillName)
			end
			-- Sem onRecast: tenta cancelar e recriar a skill
			if not entityCore.TrySelfCancel() then
				return false
			end
			-- O TrySelfCancel só derruba quem segura um ActionState Self. Se ninguém liberou a
			-- vaga, o cast novo passaria do maxInstances (e, com start = End ou Manual, sem
			-- cooldown nenhum): recusa
			if #liveRunners(entityCore, skillName) >= maxInstances then
				return false
			end
		else
			return false
		end
	end

	if entityCore.HasCooldown(skillName) then return false end --Cast novo respeita o cooldown

	--Cancela a skill anterior se ela for responsável por um state Self
	--Se obtiver retorno false (estado encontrado mas não é Self), sai do código
	if not entityCore.TrySelfCancel() then return false end

	--inicializa o runner da skill. Cast por input é a raiz da cadeia: sem Lineage pai, o próprio
	--runner vira a raiz (Depth 1, Origin = quem castou). Antes um nó raiz montado aqui com campos
	--que o BuildHistory não lê deixava Root.Origin nil e Depth começando em 2
	local runner = SkillRunner.new(
		skill,
		entityCore,
		skillName,
		StateTable.Enum.Types.Skill,
		nil,
		event)

	if not runner then return false end -- stack overflow: nada foi cobrado

	-- O cooldown começa (ou não) conforme a política declarada, ANTES do onStart: uma cadeia
	-- que tente castar a mesma skill dentro do onStart já encontra o cooldown. onStart com erro
	-- encerra o runner com o motivo error, e o refund padrão devolve o cooldown (F14, D13)
	CooldownPolicy.OnActivate(entityCore, runner)
	if not runner:start() then
		return false
	end
	track(entityCore, event, runner)
	return true, skillName, entityCore.GetCooldown(skillName)
end

local function release(entityCore, event)
	local runner = entityCore.TakeIntentRunner(event.Intent)
	return runner ~= nil and runner:Release(event)
end

--[[
Ponto único de entrada de input de botão. Player, NPC/IA e scripts de jogo chamam a mesma função:
a skill recebe a origem.
@param ID - ID da entidade
@param event - Intents.InputEvent (construa com Intents.NewEvent)
@return sucesso BOOLEAN, skillName STRING?, cooldown NUMBER? (skillName/cooldown só em Activate)
]]
function SkillHandler.HandleIntent(ID, event)
	if type(event) ~= "table" then return false end -- F49: HandleIntent(id, nil) dava erro
	local entityCore = DataManager.Get(ID) 	--Salva o EntityCore da entidade que chamou a função
	if not entityCore then return false end

	if not entityCore:HasComponent(entityCore.ComponentKey.Combat) then return false end

	if event.Kind == Intents.Kind.Release then
		return release(entityCore, event)
	end

	return activate(entityCore, event)
end



return SkillHandler

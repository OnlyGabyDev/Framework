local SkillHandler = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local Storage = game:GetService("ServerStorage")

local SkillRunner = require(Server.Modules.SkillRunner)
local DataManager = require(Server.EntityData.DataManager)
local SkillFactory = require(Server.Modules.SkillFactory)
local StateTable = require(Storage.Modules.Combat.StateTable)
local Intents = require(ReplicatedStorage.Input.Intents)

--=============================================================================
--  EIXOS (Move / Look)
--=============================================================================

function SkillHandler.HandleMovementInput(ID, dir)

	local entityCore = DataManager.Get(ID) 	--Salva o EntityCore do player que chamou a função
	if not entityCore then return false end

	local n = (typeof(dir) == "Vector3" and dir.Magnitude > 0) and dir.Unit or Vector3.zero

	entityCore.SetDirection(n)
	return n.Magnitude > 0
end

--[[
Mesmo padrão de HandleMovementInput, Ver
InputValidator.server.luau (RequestLook) e MovementComponent:SetLookDirection.
]]
function SkillHandler.HandleLookInput(ID, look)
	local entityCore = DataManager.Get(ID)
	if not entityCore then return false end

	entityCore.SetLookDirection(look)
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

local function startCooldown(entityCore, skillName)
	entityCore.SetCooldown(skillName)
	return entityCore.GetCooldown(skillName)
end

--[[
Guarda qual runner a intent está segurando, para o Release chegar no runner certo
]]
local function track(entityCore, event, runner)
	if event.Gesture ~= Intents.Gesture.Tap then
		entityCore.SetIntentRunner(event.Intent, runner)
	end
end

local function activate(entityCore, event)
	local skillData = entityCore.GetSkillFromSlot(event.Intent)
	if not skillData then return false end

	local skill = SkillFactory.GetSkill(skillData)
	local skillName = skill.data.name
	local maxInstances = skill.data.maxInstances --Guarda a quantidade máximas de instâncias permitida daquela skill
	local activeRunners = entityCore.GetActiveSkills(skillName) --Busca instâncias ativas da skill na entidade

	if entityCore.HasCooldown(skillName) then return false end --Se estiver em cooldown, retorne false.

	--Busca por tags que impossibilitem a entidade de castar essa skill
	if not entityCore.CanContinue(skill) then 
		warn("[SkillHandler] Skill não pode rodar (canCast):", skillName)
		return false
	end

	local ChainHistory
	if not skill.data.ChainHistory then
		local data = {
			rootOrigin = entityCore,
			rootSkill = skillName,
			history = {skillName},
			depth = 1,
			chainStart = tick()
		}
		ChainHistory = StateTable.BuildHistory(data)
	end

	--Se já tiver uma instância ativa dessa skill e for maior do que o máximo
	if #activeRunners > 0 and #activeRunners >= maxInstances then 
		if maxInstances == 1 then
			local runner = activeRunners[1]
			-- Tenta recast primeiro (runner permanece vivo, sem Stop)
			if runner:Recast(true) then
				runner:Recast(nil, event)
				track(entityCore, event, runner)
				return true, skillName, startCooldown(entityCore, skillName)
			end
			-- Sem onRecast: tenta cancelar e recriar a skill
			if not entityCore.TrySelfCancel() then
				return false
			end
			-- TrySelfCancel matou o runner antigo, cai pro fluxo de criação abaixo
		else
			return false
		end
	end

	--Cancela a skill anterior se ela for responsável por um state Self
	--Se obtiver retorno false (estado encontrado mas não é Self), sai do código
	if not entityCore.TrySelfCancel() then return false end

	local cooldown = startCooldown(entityCore, skillName)

	--inicializa o runner da skill
	local runner = SkillRunner.new(
		skill,
		entityCore,
		skillName,
		StateTable.Enum.Types.Skill,
		ChainHistory,
		event)

	if not runner then return false end --caso o runner seja apagado na criação devido a stack overflow.

	runner:start()
	track(entityCore, event, runner)
	return true, skillName, cooldown
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
	local entityCore = DataManager.Get(ID) 	--Salva o EntityCore da entidade que chamou a função
	if not entityCore then return false end

	if not entityCore:HasComponent(entityCore.ComponentKey.Combat) then return false end

	if event.Kind == Intents.Kind.Release then
		return release(entityCore, event)
	end

	return activate(entityCore, event)
end

return SkillHandler

local SkillHandler = {}
local Server = game:GetService("ServerScriptService")
local Storage = game:GetService("ServerStorage")

local SkillRunner = require(Server.Modules.SkillRunner)
local DataManager = require(Server.EntityData.DataManager)
local SkillFactory = require(Server.Modules.SkillFactory)
local StateTable = require(Storage.Modules.Combat.StateTable)

function SkillHandler.HandleMovementInput(ID, dir)

	local entityCore = DataManager.Get(ID) 	--Salva o EntityCore do player que chamou a função
	local dirNormal = (dir and dir.Magnitude > 0) and dir.Unit or Vector3.zero --normaliza direção

	if dirNormal.Magnitude > 0 then
		entityCore.SetDirection(dirNormal) --se tiver uma nova direção, então dê update, caso contrário mantenha a antiga
		return true
	end
	return false
end

function SkillHandler.HandleSkillInput(ID,skillIndex)

	local entityCore = DataManager.Get(ID) 	--Salva o EntityCore da entidade que chamou a função
	if not entityCore then return false end

	if not entityCore:HasComponent(entityCore.ComponentKey.Combat) then return false end


	local skillData = entityCore.GetSkillFromSlot(skillIndex)
	if not skillData then return false end

	local skill = SkillFactory.GetSkill(skillData)

	local skillName = skill.data.name

	local max = skill.data.maxInstances--Guarda a quantidade máximas de instâncias permitida daquela skill

	local maxCooldown 
	local ChainHistory
	local activeRunners = entityCore.GetActiveSkills(skillName) --Busca instâncias ativas da skill na entidade

	if entityCore.HasCooldown(skillName) then return false end --Se estiver em cooldown, retorne false.

	--Busca por tags que impossibilitem o player de castar essa skill
	if not entityCore.CanContinue(skill) then 
		warn("Skill não pode rodar")
		return false
	end

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

	maxCooldown = entityCore.GetCooldown(skillName) --Pega o cooldown total da skill
	
	--Se já tiver uma instância ativa dessa skill e for maior do que o máximo
	if #activeRunners > 0 and #activeRunners >= max then 
		--Se o máximo for 1 (padrão de skill de recast apenas, sem spawns)
		if max == 1 then
		--Pego o primeiro runner da lista
			local runner = activeRunners[1]
			if entityCore:TrySelfCancel() then --tenta cancelar a skill atual
				runner:Recast() 				--Roda o recast
				entityCore.SetCooldown(skillName)
				return true,skillName 
			end
		end
		return false
	end
		
	--Cancela a skill anterior se ela for responsável por um state Self
	--Se obtiver retorno false (estado encontrado mas não é Self), sai do código
	if not entityCore.TrySelfCancel() then return false end
	
	entityCore.SetCooldown(skillName)

	--inicializa o runner da skill
	local runner = SkillRunner.new(
		skill,
		entityCore,
		skillName,
		StateTable.Enum.Types.Skill,
		ChainHistory)

	if not runner then return false end --caso o runner seja apagado na criação devido a stack overflow.

	runner:start()
	return true,skillName,maxCooldown
end



return SkillHandler
-- ====================== O SCRIPT ABAIXO EXECUTA UM HEARTBEAT GLOBAL, TODAS AS REQUISIÇÕES DE UPDATE POR FRAME SERÃO DIRECIONADAS PRA CÁ==========


local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local SkillScheduler = {}


local activeSkills = {} -- SkillRunners
local activeStatus = {} -- StatusRunners
local activeTasks = {} -- Tasks genéricas

local connection = nil
local frameCount = 0

-- Registra runner
function SkillScheduler.Register(runner, runnerType)
	runnerType = runnerType or StateTable.Enum.Types.Skill

	-- Adiciona na lista certa
	local list
	if runnerType == StateTable.Enum.Types.Status then
		list = activeStatus
	elseif runnerType == StateTable.Enum.Types.Skill then
		list = activeSkills
	else
		list = activeTasks
	end


	--Se ainda não estiver registrado, registre.
	if not table.find(list, runner) then
		table.insert(list, runner)
	end


	-- Inicia conexão se ainda não iniciada
	if not connection then
		connection = RunService.Heartbeat:Connect(function(dt)
			SkillScheduler._Update(dt)
		end)
	end

	return true
end



-- Remove runner
function SkillScheduler.Unregister(runner, runnerType)
	runnerType = runnerType or StateTable.Enum.Types.Skill

	local list
	if runnerType == StateTable.Enum.Types.Status then
		list = activeStatus
	elseif runnerType == StateTable.Enum.Types.Skill then
		list = activeSkills
	else
		list = activeTasks
	end


	--Se encontrar na lista, remove.
	local index = table.find(list, runner)
	if index then
		table.remove(list, index)
	end

	-- Desconecta se não há mais runners
	local totalRunners = #activeSkills + #activeStatus + #activeTasks
	if totalRunners == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end


-- Update loop principal
function SkillScheduler._Update(dt)
	frameCount += 1

	-- Update de skills normais (todo frame)
	-- Pra cada skill ativa executa a update
	for i = #activeSkills, 1, -1 do

		
		--Busca o runner da skill atual
		local runner = activeSkills[i]


		--Se o runner estiver no estado de finalização, remove da lista
		if runner and runner.state ~= "Ended" then
			local success, err = pcall(runner._internalUpdate, runner, dt) --Executa a atualização, captura e retorna erros caso encontrados
			if not success then
				warn("[SkillScheduler] Erro em skill:", runner.skillName, err)
				runner:endSkill(true) -- Força término
			end
		else
			table.remove(activeSkills, i) 
		end
	end

	-- Update de status (a cada 2 frames)
	if frameCount % 2 == 0 then
		for i = #activeStatus, 1, -1 do
			local runner = activeStatus[i]

			if runner and runner.state ~= "Ended" then
				local success, err = pcall(runner._internalUpdate, runner, dt*2)
				if not success then
					warn("[SkillScheduler] Erro em status:", runner.skillName, err)
					runner:endSkill(true)
				end
			else
				table.remove(activeStatus, i)
			end
		end
	end


end

-- Debug
function SkillScheduler:GetStats()
	return {
		skills = #activeSkills,
		status = #activeStatus,
		tasks = #activeTasks,
		total = #activeSkills + #activeStatus + #activeTasks,
		frameCount = frameCount
	}
end

return SkillScheduler
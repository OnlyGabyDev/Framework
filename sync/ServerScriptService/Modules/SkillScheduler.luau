-- ====================== O SCRIPT ABAIXO EXECUTA UM HEARTBEAT GLOBAL, TODAS AS REQUISIÇÕES DE UPDATE POR FRAME SERÃO DIRECIONADAS PRA CÁ==========

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)

local Types = StateTable.Enum.Types

local SkillScheduler = {}

local activeSkills = {} -- SkillRunners
local activeStatus = {} -- StatusRunners
local activeTasks  = {} -- Tasks genéricas (Types.State e outros)

local connection = nil
local frameCount = 0
local statusAccumulator = 0 -- tempo REAL acumulado desde o último tick de status (roda a cada 2 frames)

-- Único lugar que decide em qual lista cada tipo de runner vive
local function listFor(runnerType)
	if runnerType == Types.Status then
		return activeStatus
	elseif runnerType == Types.Skill then
		return activeSkills
	end
	return activeTasks
end

local function updateList(list, dt, label)
	for i = #list, 1, -1 do
		local runner = list[i]

		--Se o runner estiver no estado de finalização, remove da lista
		if runner and runner.state ~= "Ended" then
			local success, err = pcall(runner._internalUpdate, runner, dt)
			if not success then
				warn("[SkillScheduler] Erro em " .. label .. ":", runner.skillName, err)
				runner:endSkill(true) -- Força término
			end
		else
			table.remove(list, i)
		end
	end
end

-- Registra runner
function SkillScheduler.Register(runner, runnerType)
	local list = listFor(runnerType or Types.Skill)

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
	local list = listFor(runnerType or Types.Skill)

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
	statusAccumulator += dt

	-- Skills e tasks: todo frame
	updateList(activeSkills, dt, "skill")
	updateList(activeTasks, dt, "task")

	-- Status: a cada 2 frames, com o tempo real acumulado
	if frameCount % 2 == 0 then
		updateList(activeStatus, statusAccumulator, "status")
		statusAccumulator = 0
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
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

-- Durante o update nenhuma lista muda de tamanho: Unregister só marca o runner (_unscheduled)
-- e a lista é compactada no fim. Antes o Unregister removia na hora; encerrar um runner de
-- índice menor deslocava a lista e o runner atual rodava 2 vezes no frame (F15).
local updating = false

local function isLive(runner)
	return runner ~= nil and not runner._unscheduled and runner.state ~= "Ended"
end

local function compact(list)
	local write = 0
	for read = 1, #list do
		local runner = list[read]
		if isLive(runner) then
			write += 1
			list[write] = runner
		elseif runner then
			runner._unscheduled = nil
		end
	end
	for i = #list, write + 1, -1 do
		list[i] = nil
	end
end

local function totalRunners()
	return #activeSkills + #activeStatus + #activeTasks
end

local function updateList(list, dt, label)
	-- O limite é lido uma vez: runner registrado durante o update roda a partir do próximo frame
	for i = 1, #list do
		local runner = list[i]
		if isLive(runner) then
			local success, err = pcall(runner._internalUpdate, runner, dt)
			if not success then
				warn("[SkillScheduler] Erro em " .. label .. ":", runner.skillName, err)
				runner:Abort() -- erro não aceita veto do onCancel (F78)
			end
		end
	end
	compact(list)
end

-- Registra runner
function SkillScheduler.Register(runner, runnerType)
	local list = listFor(runnerType or Types.Skill)

	-- Desregistrado e registrado de novo no mesmo frame: continua na lista, só perde a marca
	runner._unscheduled = nil
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

	if updating then
		runner._unscheduled = true -- sai no compact do fim do frame
		return
	end

	local index = table.find(list, runner)
	if index then
		table.remove(list, index)
	end

	-- Desconecta se não há mais runners
	if totalRunners() == 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

-- Update loop principal
function SkillScheduler._Update(dt)
	frameCount += 1
	statusAccumulator += dt

	updating = true
	-- Skills e tasks: todo frame
	updateList(activeSkills, dt, "skill")
	updateList(activeTasks, dt, "task")

	-- Status: a cada 2 frames, com o tempo real acumulado
	if frameCount % 2 == 0 then
		updateList(activeStatus, statusAccumulator, "status")
		statusAccumulator = 0
	else
		compact(activeStatus) -- status encerrados por skills neste frame saem da lista
	end
	updating = false

	if totalRunners() == 0 and connection then
		connection:Disconnect()
		connection = nil
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
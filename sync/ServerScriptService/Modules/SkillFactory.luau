local SkillFactory = {}

-- Funções padrão para as skills
local SkillDefaults = {
	onStart = function() end,
	--onStep = function() end, --Necessário para manter heartbeat da skill rodando
	onEnd = function() end,
	--onHit = function() end,
	onCancel = function()end,
	
	
	--onRecast = function()return false end,
}


-- Cache simples para evitar múltiplos require da mesma skill
local skillCache = {}



-- Prepara e devolve o módulo da skill com callbacks garantidos
function SkillFactory.GetSkill(skillInput)
	local skill
	
	-- Se for um moduleScript não carregado
	if typeof(skillInput) == "Instance" and skillInput:IsA("ModuleScript") then
		if skillCache[skillInput] then return skillCache[skillInput] end
		
		local success, res = pcall(require, skillInput)
		if not success then return nil end
		skill = res
		skillCache[skillInput] = skill
		
	-- Se for uma tabela de dados
	elseif type(skillInput) == "table" then
		skill = skillInput
	else
		return nil
	end

	-- Injeta callbacks padrão se faltar
	if not skill.callbacks then skill.callbacks = {} end
	setmetatable(skill.callbacks, { __index = SkillDefaults })
	
	if not skill.data.maxInstances then skill.data.maxInstances = 1 end

	return skill
end




function SkillFactory.GetStatus(originalData)
	local defaults = {
		onStart = function() end,
		onStep = function() end,
		onEnd = function() end,
		onCancel = function() end,
		onStop = function() end,
		onRecast = function() return false end, -- fallback
	}

	-- Criamos um novo container superficial para não mutar a tabela estática congelada
	local status = {
		data = originalData.data,
		ID = originalData.ID,
		StatusController = originalData.StatusController
	}

	local originalCallbacks = originalData.callbacks or {}
	local newCallbacks = {}

	newCallbacks.onEnd = function(selfRunner)
		if originalCallbacks.onEnd then originalCallbacks.onEnd(selfRunner) end
		if status.StatusController then
			status.StatusController:RemoveById(status.ID)
		end
	end
	
	newCallbacks.onCancel = function(selfRunner)
		if originalCallbacks.onCancel then originalCallbacks.onCancel(selfRunner) end
		if status.StatusController then
			status.StatusController:RemoveById(status.ID)
		end
	end

	-- Delega chamadas não interceptadas para o original, ou depois pros fallbacks
	setmetatable(newCallbacks, {
		__index = function(t, key)
			if originalCallbacks[key] then return originalCallbacks[key] end
			return defaults[key]
		end
	})

	status.callbacks = newCallbacks

	return status
end



return SkillFactory

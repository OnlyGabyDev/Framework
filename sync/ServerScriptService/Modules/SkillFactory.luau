local SkillFactory = {}

-- Funções padrão para as skills
local SkillDefaults = {
	onStart = function() end,
	--onStep = function() end,
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




function SkillFactory.GetStatus(data)
	local defaults = {
		onStart = function() end,
		onStep = function() end,
		onEnd = function() end,
		onCancel = function() end,
		onStop = function() end,
		onRecast = function() return false end, -- fallback
	}

	if not data.callbacks then
		data.callbacks = {}
	end
	if not data.data.castTime then 
		data.data.castTime = 0
	end

	data.callbacks.onEnd = function(selfRunner)
		if data.StatusController then
			data.StatusController:RemoveById(data.ID)
			print("[StatusController] Status removido ao final:", data.ID)
		end
	end
	

	data.callbacks.onCancel = function(selfRunner)
		if data.StatusController then
			data.StatusController:RemoveById(data.ID)
			print("[StatusController] Status removido por cancelamento:", data.ID)
		end
	end


	-- Garantir que todos os callbacks sejam injetados
	setmetatable(data.callbacks, { __index = defaults })

	return data
end



return SkillFactory

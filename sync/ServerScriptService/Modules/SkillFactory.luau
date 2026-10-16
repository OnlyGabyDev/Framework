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




-- Funções padrão dos status (dado estático: antes a tabela era recriada a cada ApplyStatus)
local StatusDefaults = {
	onStart = function() end,
	onStep = function() end,
	onEnd = function() end,
	onCancel = function() end,
	onStop = function() end,
	onRecast = function() return false end, -- fallback
}

function SkillFactory.GetStatus(originalData)
	local originalCallbacks = originalData.callbacks or {}

	-- Status NÃO pode recusar cancelamento: o onCancel repassa o ctx (com ctx.reason, F54) e
	-- descarta o retorno. O RemoveStatus tira a entrada do registro antes de encerrar o runner;
	-- se um status pudesse vetar, o runner seguiria vivo fora do registro. Para permitir veto um
	-- dia, o RemoveStatus teria de respeitá-lo (só desregistrar depois do fim confirmado).
	local newCallbacks = {
		onCancel = function(selfRunner, ...)
			if originalCallbacks.onCancel then originalCallbacks.onCancel(selfRunner, ...) end
		end,
	}

	-- O resto vem do original, ou dos fallbacks
	setmetatable(newCallbacks, {
		__index = function(_, key)
			local original = originalCallbacks[key]
			if original then return original end
			return StatusDefaults[key]
		end
	})

	-- Container raso novo: não muta a tabela estática (congelada) do status
	return {
		data = originalData.data,
		ID = originalData.ID,
		callbacks = newCallbacks,
	}
end



return SkillFactory

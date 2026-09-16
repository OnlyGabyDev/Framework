
local Helper = {}

local Enum = require(script.Parent.Enum)



function Helper.LoadModules(rootScript, folderName, targetTable)
	local folder = rootScript:FindFirstChild(folderName) 

	
	for _, module in ipairs(folder:GetChildren()) do
		if module:IsA("ModuleScript") then
			local success, data = pcall(require, module)
			
			if success then
				targetTable[module.Name] = data
				
				if data.data and not data.data.name then
					data.data.name = module.Name
				end
			else
				warn("[StateTable] Erro ao carregar " .. module.Name .. ": " .. tostring(data))
			end
		else
			for _,Folder in ipairs(folder:GetChildren()) do
				for _,module in ipairs(Folder:GetChildren()) do
					if module:IsA("ModuleScript") then
						local success,data = pcall(require,module)

						if success then
							targetTable[module.name] = data

							if data.data and not data.data.name then
								data.data.name = module.name
							end
						else
							warn("[StateTable] Erro ao carregar " .. module.Name .. ": " .. tostring(data))
						end
					end
				end
			end
		end
	end
end

function Helper.GetTags(stateTable, stateName)
	local state = stateTable.States[stateName] or stateTable.Status[stateName]
	
	if not state or not state.data.tags then 
		return Enum.Defaults 
	end

	return setmetatable(state.data.tags, { __index = Enum.Defaults })
end

function Helper.IsState(stateTable, meta)
	if not meta or not meta.name then return false end
	
	if stateTable.States[meta.name] then return true end
	
	for _, group in pairs(stateTable.PlayerStates) do
		if type(group) == "table" then
			for _, state in pairs(group) do
				if state.data and state.data.name == meta.name then
					return true
				end
			end
		elseif group.data and group.data.name == meta.name then
			return true
		end
	end

	if meta.category == Enum.Categories.PlayerState then
		return true
	end
	
	return false
end



function Helper.BuildEffect(baseStatus, callbackName, actionFunc)
	if not baseStatus then return nil end
	
	local newStatus = table.clone(baseStatus)
	
	if newStatus.callbacks then
		newStatus.callbacks = table.clone(newStatus.callbacks)
	else
		newStatus.callbacks = {}
	end
	
	newStatus.callbacks[callbackName] = actionFunc
	
	return newStatus
end

function Helper.CheckBlockFilter(runner, context)

    local data = (runner.data and runner.data.data) or (runner.skillData and runner.skillData.data)
    

    if not data then return true end
    local source = context.source
    local incomingTraits = context.traits or {}

    if data.ShieldsFromType then
        local sourceType = source and source.type 
        local typeMatch = false
        
		--warn(data.ShieldsFromType)
        for _, Type in pairs(data.ShieldsFromType) do
            if sourceType == Type then
                typeMatch = true
                break 
            end
        end
		
        if not typeMatch then
            return false 
        end
    end

	local HasTraitFilter = next(data.ShieldsFrom)
	
    if HasTraitFilter then
        local traitMatch = false
        
        for _, requiredTrait in ipairs(data.ShieldsFrom) do
            if table.find(incomingTraits, requiredTrait) then
                traitMatch = true
                break 
            end
        end
        
        if not traitMatch then
            return false 
        end
    end

    return true 
end

function Helper.BuildContext(source,amount)
	local context = {
		damage = 0,
		source = source,
		sourceEntity = nil,
		traits = {},
		effects = {},
	}

	if source then
		if source.Entity then
			context.sourceEntity = source.Entity
		end
		if source.data then
			context.damage = amount or source.damage or 0
			context.traits = table.clone(source.data.traits or {})
			context.effects = table.clone(source.data.effects or {})
			context.type = source.type
			context.secondaryType = source.secondaryType or nil
		end
	end
	return context
end

function Helper.BuildHistory(data)
    local History = {
        rootOrigin = data.Entity and data.Entity or "Unknown",
        rootSkill = data.name or "Unknown",
        history = {data.name or "Uknown"},
        depth = data.depth or 1,
        uniqueChainID = data.uniqueChainID or data.name and data.name .. tostring(tick()) or "SYSTEM_" .. tostring(tick()),
		chainStart = data.chainStart or tick(),
		lastInteraction = data.lastInteraction or tick(),
		tempDepth = data.tempDepth or 0,
    }
	return History
end

return Helper
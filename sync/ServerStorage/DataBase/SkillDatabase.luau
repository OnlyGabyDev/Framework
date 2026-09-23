local SkillDatabase = {
	_Registry = {}, -- Referencia ao modulo da skill
	Keys = {}       -- Enum de nome das skills
}

-- Cria subKeys no enum
local function GetOrCreateTable(parentTable, name)
	if not parentTable[name] then
		parentTable[name] = {}
	end
	return parentTable[name]
end

local IGNORED = { BaseSkills = true } -- módulos utilitários que vivem na pasta mas não são skills

-- Scanner recursivo, busca por todos os filhos da hierarquia, enumera e salva o modulo
local function ScanFolder(folder, currentKeyTable, prefixID)
	for _, child in ipairs(folder:GetChildren()) do
		
		if child:IsA("ModuleScript") then
			if IGNORED[child.Name] then continue end
			local skillName = child.Name
			
			-- Cria um nome baseado na profundidade da pasta,com os prefixos sendo os nomes das pastas 
			local uniqueID = (prefixID == "" and skillName) or (prefixID .. "_" .. skillName)
			
			SkillDatabase._Registry[uniqueID] = child
			
            --salva no enum
			currentKeyTable[skillName] = uniqueID
			
		elseif child:IsA("Folder") then
			local folderName = child.Name
			
			local nextKeyTable = GetOrCreateTable(currentKeyTable, folderName)
			
			--Atualiza o prefixo
			local nextPrefix = (prefixID == "" and folderName) or (prefixID .. "_" .. folderName)
			
            --recursivo!
			ScanFolder(child, nextKeyTable, nextPrefix)
		end
	end
end


ScanFolder(script, SkillDatabase.Keys, "")


table.freeze(SkillDatabase.Keys)
table.freeze(SkillDatabase._Registry)


return SkillDatabase

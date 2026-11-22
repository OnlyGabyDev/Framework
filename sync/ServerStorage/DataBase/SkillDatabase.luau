local SkillDatabase = {
	_Registry = {}, -- Referencia ao modulo da skill
	_Kits = {},     -- [chave da skill] = kit dono (a pasta de 1º nível: SkillDatabase/<Kit>/...)
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
local function ScanFolder(folder, currentKeyTable, prefixID, kit)
	for _, child in ipairs(folder:GetChildren()) do

		if child:IsA("ModuleScript") then
			if IGNORED[child.Name] then continue end
			local skillName = child.Name

			-- Cria um nome baseado na profundidade da pasta,com os prefixos sendo os nomes das pastas
			local uniqueID = (prefixID == "" and skillName) or (prefixID .. "_" .. skillName)

			SkillDatabase._Registry[uniqueID] = child
			SkillDatabase._Kits[uniqueID] = kit

            --salva no enum
			currentKeyTable[skillName] = uniqueID

		elseif child:IsA("Folder") then
			local folderName = child.Name

			local nextKeyTable = GetOrCreateTable(currentKeyTable, folderName)

			--Atualiza o prefixo
			local nextPrefix = (prefixID == "" and folderName) or (prefixID .. "_" .. folderName)

            --recursivo! A pasta de 1º nível é o kit dono de tudo que está abaixo dela
			ScanFolder(child, nextKeyTable, nextPrefix, kit or folderName)
		end
	end
end


ScanFolder(script, SkillDatabase.Keys, "", nil)


table.freeze(SkillDatabase.Keys)
table.freeze(SkillDatabase._Registry)
table.freeze(SkillDatabase._Kits)

--[[
Kit dono da skill (o nome da pasta de 1º nível, que é também a chave dela no AnimationLib e nos
assets). É de onde a skill tira as animações em qualquer corpo (F55). nil = skill solta.
@param skillKey - chave da skill (SkillDatabase.Keys) STRING
]]
function SkillDatabase.KitOf(skillKey: string): string?
	return SkillDatabase._Kits[skillKey]
end


return SkillDatabase

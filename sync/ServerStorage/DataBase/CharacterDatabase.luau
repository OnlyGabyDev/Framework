local CharacterDatabase = {}

-- Scanneia as pastas da hierarquia
for _, charFolder in ipairs(script:GetChildren()) do
	if charFolder:IsA("Folder") then
		local charName = charFolder.Name
		CharacterDatabase[charName] = {}

		-- Scanneia os modulos da hierarquia (modos/transformações)
		for _, formModule in ipairs(charFolder:GetChildren()) do
			if formModule:IsA("ModuleScript") then
				local formName = formModule.Name

				-- Carrega os dados
				local success, formData = pcall(require, formModule)

				if success then
					CharacterDatabase[charName][formName] = formData
				else
					warn("[CharacterDatabase] Erro na forma:", charName, formName)
				end
			end
		end
	end
end

return table.freeze(CharacterDatabase)

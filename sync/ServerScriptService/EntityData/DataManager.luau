local EntityCore = require(script.Parent.EntityCore)
local CharacterDatabase = require(game.ServerStorage.DataBase.CharacterDatabase)

local DataManager = {}
local entityMap = {
	players = {},
	NPCs = {}
}

--Cria o EntityCore do jogador

--[[
DataManager.Create(Entity)
Caso Player, passar o Player Character (modelo do player), caso NPC, passar o modelo da entidade
@param Entity - Player.Character ou modelo de entidade MODEL
@param components - tabela de componentes a serem adicionados {}
@return void
]]
function DataManager.Create(Entity,components : {})


	warn("===========VITALS============")

	if not Entity then
		warn("[DataManager] Entidade não recebida, func Create")
		return nil
	end
	if not components then
		warn("[DataManager] Componentes não recebidos, func Create")
		return nil
	end

	--Gera um ID único pra entidade
	local id,entityType = DataManager.CreateID(Entity)
	
	warn(entityType,"Registrado, ID:",id)
	
	local Model
	local Player

	--Salva esse ID no mapa de entidades
	if typeof(Entity) == "table" then Model = Entity.Model; Player = Entity.Player
	else
		Model = Entity; Player = nil
	end
	local core = EntityCore.new(Model,entityType,id,Player)


	--DEBUG
	local compList = {}

	--Adiciona os componentes recebidos como argumento
	for _,comp in pairs(components) do
		core:AddComponent(comp)
		compList[#compList + 1] = comp
	end
	warn("[DataManager] Componentes adicionados:", compList)

	--Setta o wrapper no componente Character (vital)
	if core:HasComponent(core.ComponentKey.Character) then
	core:SetEntity(Entity)
	end

	-- inicializa o wrapper e guarda o modelo/character da entidade
	core:ComponentsLoaded()

	--Salva o EntityCore no mapa correto
	if typeof(Entity) == "table"  then

		entityMap.players[id] = core
		Entity.Model:SetAttribute("EntityID",id)
		Entity.Player:SetAttribute("EntityID",id)

	elseif Entity:IsA("Model") then
		entityMap.NPCs[id] = core
		Entity:SetAttribute("EntityID",id)
		
	else
		warn("[DataManager] Entidade inválida, func Create")
		return nil
	end



	--inicializa o wrapper de movimentação
	if core:HasComponent(core.ComponentKey.Movement) then
	core:SetMovement()
	end

	warn("===========VITALS END========")
	
	return core

end


--[[
Retorna o EntityCore da entidade,se possível, passe ID
@param Entity - Modelo atingido ou ID da entidade.
]]
function DataManager.Get(Entity)

	local id 

	if typeof(Entity) ~= "string" then
	id = Entity:GetAttribute("EntityID")
	elseif typeof(Entity) == "string" then
	id = Entity
	end

	
	if typeof(id) ~= "string" then
	warn("[DataManager] Entidade inválida, func Get")
	return nil 
	end


	if entityMap.NPCs[id] or entityMap.players[id] then
		local mapCore = entityMap.NPCs[id] or entityMap.players[id]
		return mapCore
	else
		warn("[DataManager] Recebido ID invalido,",id,"func get")
		return nil
	end

end

--[[
Remove o EntityCore da entidade
@param Entity - Player ou entidade
]]
function DataManager.Remove(Entity)
	
		if typeof(Entity) == "Instance" and Entity:IsA("Player") then
			local ID = Entity:GetAttribute("EntityID")
			entityMap.players[ID]:Destroy()
			entityMap.players[ID] = nil
		else
			local ID = Entity:GetAttribute("EntityID")
			entityMap.NPCs[ID]:Destroy()
			entityMap.NPCs[ID] = nil
		end
end

--Cria os IDS pra redirecionamento ao ED
function DataManager.CreateID(Entity)
	
	--Se não existir uma entidade, saia da função e retorne nil
	if not Entity then return nil end

	--Se a entidade for um player, então:

	if typeof(Entity) == "table"  then

		--Gera um ID baseado no UserID do Player
		local id = "Player_" .. Entity.Player.UserId
			if entityMap.players[id] then
				warn("[DataManager]ID já existe para o jogador:", Entity.Player.Name)
				return nil
			end
		return id,"Player"
			

		--Se for uma entidade genérica, então:
	else
		--Gera um ID único baseado no DebugId da entidade
		local id = "Entity_" ..  tostring(math.random(100000,999999))

			--Se o ID já existir, gere um novo até achar um único
		   while entityMap.NPCs[id] do
			   id = "Entity_" .. tostring(math.random(100000,999999))
		   end
		return id,"Entity"
	end
end

return DataManager
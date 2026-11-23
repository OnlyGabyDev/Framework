local EntityCore = require(script.Parent.EntityCore)
local Log = require(game:GetService("ReplicatedStorage").Logger).Channel("DataManager")
local CharacterDatabase = require(game.ServerStorage.DataBase.CharacterDatabase)

local DataManager = {}
local entityMap = {
	players = {},
	NPCs = {}
}

--[[
Tipo da entrada do Create: "player" ({ Model, Player }), "model" (NPC/objeto) ou nil (inválida).
]]
local function entityKind(Entity): string?
	if typeof(Entity) == "table" then
		local ok = typeof(Entity.Model) == "Instance" and Entity.Model:IsA("Model") and typeof(Entity.Player) == "Instance"
		return if ok then "player" else nil
	end
	if typeof(Entity) == "Instance" and Entity:IsA("Model") then
		return "model"
	end
	return nil
end

-- Monta o EntityCore, os componentes e registra no mapa. `kind` já validado; Entity é nil numa
-- entidade só de dado (CreateData)
local function build(Entity, kind: string?, components, configs, parentEntity)
	local id, entityType
	if kind == nil then
		id, entityType = DataManager.CreateID(nil), EntityCore.EntityTypes.Generic
	else
		id, entityType = DataManager.CreateID(Entity)
	end
	Log.Debug(entityType, "registrado, ID:", id)

	-- Respawn reaproveita o ID do player: destrói a entidade anterior antes de sobrescrever
	local previous = entityMap.players[id]
	if previous then
		previous:Destroy()
		entityMap.players[id] = nil
	end

	local Model, Player
	if kind == "player" then
		Model, Player = Entity.Model, Entity.Player
	else
		Model = Entity
	end
	local core = EntityCore.new(Model, entityType, id, Player)

	-- Herança de reações (regra 4): o filho nasce com o Fork do TriggerSet do pai
	if parentEntity and parentEntity._triggerSet then
		core._triggerSet = parentEntity._triggerSet:Fork()
	end

	for _, comp in pairs(components) do
		core:AddComponent(comp, configs and configs[comp] or {})
	end
	if core:HasComponent(core.ComponentKey.Character) then
		core.SetEntity(Entity)
	end
	core:ComponentsLoaded()

	if kind == "player" then
		entityMap.players[id] = core
		Model:SetAttribute("EntityID", id)
		Player:SetAttribute("EntityID", id)
	else
		entityMap.NPCs[id] = core
		if Model then Model:SetAttribute("EntityID", id) end
	end

	if core:HasComponent(core.ComponentKey.Movement) then
		core.SetMovement()
	end
	return core
end

--[[
Cria a entidade de um corpo.
@param Entity - { Model = character, Player = player } (player) ou um Model (NPC, objeto)
@param components - nomes dos componentes (ComponentKey) {string}
@param configs - config por componente { [nome]: table }?
@param parentEntity - entidade pai: o filho herda as reações dela (Fork do TriggerSet)
@return EntityCore, ou nil se a entrada for inválida (nada é registrado)
]]
function DataManager.Create(Entity, components : {}, configs : {[string]: any}?, parentEntity : any?)
	if not components then
		Log.Warn("Componentes não recebidos, func Create")
		return nil
	end
	local kind = entityKind(Entity)
	if not kind then
		Log.Warn("Entidade inválida, func Create (use um Model, { Model, Player } ou DataManager.CreateData)")
		return nil
	end
	return build(Entity, kind, components, configs, parentEntity)
end

--[[
Cria uma entidade só de dado, sem Instance (baralho, gerente de turno, aura invisível). Componentes
que dependem de corpo (Character, Movement, Weapon, Animation) não servem nela. Remova com
DataManager.Remove(entidade) ou Remove(ID).
@return EntityCore
]]
function DataManager.CreateData(components : {}, configs : {[string]: any}?, parentEntity : any?)
	if not components then
		Log.Warn("Componentes não recebidos, func CreateData")
		return nil
	end
	return build(nil, nil, components, configs, parentEntity)
end


--[[
Retorna o EntityCore da entidade,se possível, passe ID
@param Entity - Modelo atingido ou ID da entidade.
]]
function DataManager.Get(Entity)

	local id 

	-- Entrada inválida (nil, número, tabela) devolve nil com warn em vez de erro: uma IA com
	-- bug chamando Get(nil) derrubava o próprio loop (F49)
	if typeof(Entity) == "Instance" then
		id = Entity:GetAttribute("EntityID")
	elseif typeof(Entity) == "string" then
		id = Entity
	end

	
	if typeof(id) ~= "string" then
	Log.Warn("Entidade inválida, func Get")
	return nil 
	end


	if entityMap.NPCs[id] or entityMap.players[id] then
		local mapCore = entityMap.NPCs[id] or entityMap.players[id]
		return mapCore
	else
		Log.Warn("Recebido ID inválido,", id, "func Get")
		return nil
	end

end

--[[ Existe entidade com este ID? Sem warn: serve para validar entrada da rede ]]
function DataManager.Exists(ID: any): boolean
	return typeof(ID) == "string" and (entityMap.NPCs[ID] ~= nil or entityMap.players[ID] ~= nil)
end

--[[
Busca o Entity do alvo atingido subindo a hierarquia até achar um Model com EntityID
]]
function DataManager.GetEntityFromInstance(hitInstance: Instance)
	local current = hitInstance

	while current and current ~= workspace do
		if current:IsA("Model") then
			local hitID = current:GetAttribute("EntityID")
			if hitID then
				return DataManager.Get(hitID)
			end
		end
		current = current.Parent
	end

	return nil
end

--[[
Remove o EntityCore da entidade
@param Entity - o Player, o Model, o ID da entidade ou o próprio EntityCore
]]
function DataManager.Remove(Entity)
	local ID
	if typeof(Entity) == "Instance" then
		ID = Entity:GetAttribute("EntityID")
	elseif typeof(Entity) == "string" then
		ID = Entity
	elseif typeof(Entity) == "table" then
		ID = Entity.ID
	end
	if typeof(ID) ~= "string" then return end

	local map = if entityMap.players[ID] then entityMap.players else entityMap.NPCs
	local core = map[ID]
	if not core then return end -- player saiu antes de ter entidade, ou já removido

	core:Destroy()
	map[ID] = nil
end

--Cria os IDS pra redirecionamento ao ED
function DataManager.CreateID(Entity)
	

	--Se a entidade for um player, então:

	if typeof(Entity) == "table"  then

		--Gera um ID baseado no UserID do Player
		local id = "Player_" .. Entity.Player.UserId
		return id, EntityCore.EntityTypes.Player
			

		--Se for uma entidade genérica, então:
	else
		--Gera um ID único baseado no DebugId da entidade
		local id = "Entity_" ..  tostring(math.random(100000,999999))

			--Se o ID já existir, gere um novo até achar um único
		   while entityMap.NPCs[id] do
			   id = "Entity_" .. tostring(math.random(100000,999999))
		   end
		-- Tipo do enum único (F38): antes gravava "Entity", e IsNPC() era sempre falso
		return id, EntityCore.EntityTypes.NPC
	end
end

return DataManager
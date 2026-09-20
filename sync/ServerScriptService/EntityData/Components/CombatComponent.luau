
--=====TIPAGEM=====--

type PlayerStatesType = {
    Self: {
        selfCast: any,
        globalCast: any,
    },
    Out: {
        cast: any,
        globalCast: any,
    }
}

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local SkillData = require(ServerStorage.DataBase.SkillDatabase)
local CharData = require(ServerStorage.DataBase.CharacterDatabase)
local Intents = require(game:GetService("ReplicatedStorage").Input.Intents)

local CombatComponent = {}
CombatComponent.__index = CombatComponent

--[[
Inicializa o componente de combate na entidade
@param entity - Entidade dona do componente Entity, enviar EntityData
@param config - Configurações iniciais do componente TABLE { ChosenChar: string, Mode: string }
@return nova instância do CombatComponent CombatComponent
]]
function CombatComponent.new(entity, config)
	local self = setmetatable({}, CombatComponent)

	self.Entity = entity

	-- Skills disponíveis
	self.Loadout = {}

	--Cache pra evitar require duplicado
	self.SkillCache = {}

	-- Cooldown de skills
	self.Cooldowns = {} -- [skillName] = tick() + cooldown

	-- Skills ativas (runners)
	self.ActiveSkills = {} -- [skillName] = {runner1, runner2, ...}
	
	-- Runner que cada intent está segurando (ver SkillHandler.track). Dá ao Release o runner CERTO.
	self.IntentRunners = {} -- [intent] = runner

	-- Personagem e modo
	self.ChosenChar = config.ChosenChar or "Schema"
	self.Mode = config.Mode or "Base"
	self.baseStats = {}

	--Estado de cast
	self.PlayerState = {
		name = nil,
		runner = nil
	}

	return self
end

--=============================================================================
--  SKILL DATA LOADING
--=============================================================================

--[[
Inicializa a pasta de skills, carrega dados e inicializa cooldowns
@return sucesso BOOLEAN
]]
function CombatComponent:LoadSkillsData() : boolean

	if not self:_LoadFolders() then return false end

	local skillsModule = self._formFolder:FindFirstChild("Skills")
		and self._formFolder.Skills:FindFirstChild("Skills")

	if not skillsModule then return false end

	local success, skillsData = pcall(require, skillsModule)
	if not success then return false end

	self.SkillsData = skillsData

	-- Inicializa cooldowns
	for _, skillName in pairs(skillsData) do
		self.Cooldowns[skillName] = 0
	end

	return true
end

--[[
Carrega as pastas de dados do personagem
@return sucesso BOOLEAN
]]
function CombatComponent:_LoadFolders() : boolean

	local charFolder = ServerStorage.Modules.CharData:FindFirstChild(self.ChosenChar)
	if not charFolder then
		warn("[CharacterComponent] Personagem não encontrado:", self.ChosenChar)
		return false
	end

	local formFolder = charFolder:FindFirstChild(self.Mode)
	if not formFolder then
		warn("[CharacterComponent] Forma não encontrada:", self.Mode)
		return false
	end

	self.charFolder = charFolder
	self._formFolder = formFolder

	return true
end


--=============================================================================
--  SKILL GETTERS
--=============================================================================

--[[
Devolve o nome da skill no índice fornecido
@param index - índice da skill NUMBER
@return nome da skill STRING ou nil se não encontrada
]]
function CombatComponent:GetSkillName(index : number) : string?
	if not self.SkillsData then
		warn("[CombatComponent] SkillsData não carregado")
		return nil
	end

	return self.SkillsData[index]
end

--[[
Devevolve o script (não requirido) da skill no índice fornecido
@param index - índice da skill (opcional se fornecer name) NUMBER
@param name - nome da skill STRING (opcional, se fornecido, ignora index)
]]
function CombatComponent:GetSkillScript(index : number?, name : string?)
	local charComp = self.Entity:GetComponent(self.Entity.ComponentKey.Character)
	if not charComp then return nil end

		local skillName = name or self:GetSkillName(index)
		if not skillName then 
			warn("[CombatComponent] GetSkillScript não recebeu um parametro!")
			 return nil end


	local skillScript = self._formFolder:FindFirstChild("Script")
		and self._formFolder.Script:FindFirstChild(skillName)

	return skillScript
end


--[[
Devevolve o módulo (requirido) da skill pelo nome ou index
@param skillName - nome da skill (opcional, se fornecer index) STRING
@param index - índice da skill NUMBER (opcional se fornecer name)
@return módulo da skill TABLE ou nil se não encontrado
]]
function CombatComponent:GetSkillData(skillName : string, index : number?) : any?
	local charComp = self.Entity:HasComponent(self.Entity.ComponentKey.Character)
	if not charComp then return nil end

	skillName = skillName or self:GetSkillName(index)
	if not skillName then
		warn("[CombatComponent] GetSkillData não recebeu um parametro!")
		return nil end

	local skillScript = self._formFolder:FindFirstChild("Script")
		and self._formFolder.Script:FindFirstChild(skillName)

	if not skillScript then return nil end

	local success, skillModule = pcall(require, skillScript)
	if not success or not skillModule then return nil end

	return skillModule
end

--=============================================================================
--  COOLDOWN
--=============================================================================


--[[
Checa se a skill está em cooldown
@param skillName - nome da skill STRING
@return está em cooldown BOOLEAN
]]
function CombatComponent:HasCooldown(skillName : string) : boolean
	return (self.Cooldowns[skillName] or 0) > tick()
end

--[[
Define o cooldown de uma skill
@param skillName - nome da skill STRING
@param customCooldown - cooldown customizado NUMBER (opcional, se não fornecido, busca no módulo da skill)
]]
function CombatComponent:SetCooldown(skillName : string, customCooldown : number?)
	local cd = customCooldown

	-- Se não forneceu cooldown customizado, busca no módulo
	if not cd then
		if self.SkillCache and self.SkillCache[skillName].data then
			local skill = self.SkillCache[skillName]
			cd = skill.data.cooldown
		end
	end

	if cd then
		self.Cooldowns[skillName] = tick() + cd
	end
end

--[[
Devolve o tempo restante do cooldown de uma skill
@param skillName - nome da skill STRING
@return tempo restante do cooldown NUMBER
]]
function CombatComponent:GetCooldown(skillName : string) : number
	return math.max(0, (self.Cooldowns[skillName] or 0) - tick())
end


--[[
Reseta o cooldown de uma skill
@param skillName - nome da skill STRING
]]
function CombatComponent:ResetCooldown(skillName : string)
	self.Cooldowns[skillName] = 0
end

--[[
Reseta todos os cooldowns de skills registrados
]]
function CombatComponent:ResetAllCooldowns()
	for skillName in pairs(self.Cooldowns) do
		self.Cooldowns[skillName] = 0
	end
end

--=============================================================================
--  PLAYER STATE (Cast, GlobalCast, SelfCast, LockedCast)
--=============================================================================

--[[
Retorna o PlayerState atual
]]
function CombatComponent:GetPlayerState()
	return self.PlayerState
end

function CombatComponent:SetPlayerState(state,runner)

	if not self.PlayerState then self.PlayerState = {name = state, runner} end

	self.PlayerState.name = state.data.name
	self.PlayerState.runner = runner
end

function CombatComponent:RemovePlayerState()
	self.PlayerState = nil
end


--[[
Cancelamento interno de skills buscando por estados do tipo SelfCast
@return sucesso BOOLEAN
]]
function CombatComponent:TrySelfCancel() : boolean
		if self.PlayerState and next(self.PlayerState) then
			local playerStates = StateTable.PlayerStates :: PlayerStatesType

			-- Checa se é Self
			for _, v in pairs(playerStates.Self) do
				if self.PlayerState.name == v.data.name then
					local runner = self.PlayerState.runner 
					if runner and typeof(runner) == "table" then
						runner:Stop(true)
						return true 
					end
				end
			end
			warn("Skill não pode rodar!")
			return false -- Encontrou PlayerState mas não é Self
		end
	
	return true -- Nenhum PlayerState ativo
end


--=============================================================================
--  VALIDAÇÃO
--=============================================================================

--[[
valida se a entidade pode continuar a ação
@return sucesso BOOLEAN
]]
function CombatComponent:CanContinue(skill) : boolean

	--Busca por tag de impedimento
	if self.Entity:HasComponent(self.Entity.ComponentKey.Status) then
		local tags = self.Entity.GetActiveTags()
		if tags["canCast"] == false then
			return false
		end
	end
	
	return true
end


--=============================================================================
--  SKILLS E RUNNERS
--=============================================================================

--[[
Adiciona uma skill pra lista de habilidades ativas
@param skillName - nome da skill STRING
@param runner - instância do runner da skill TABLE
]]
function CombatComponent:AddActiveSkill(skillName : string, runner)
	
assert(typeof(skillName) == "string","[CombatComponent] skillName precisa ser string, recebeu " .. typeof(skillName))

	if not self.ActiveSkills[skillName] then
		self.ActiveSkills[skillName] = {}
	end
	table.insert(self.ActiveSkills[skillName], runner)
end

--[[
Remove uma skill da lista de habilidades ativas
@param skillName - nome da skill STRING
@param runner - instância do runner da skill TABLE
]]
function CombatComponent:RemoveActiveSkill(skillName : string, runner)
	local list = self.ActiveSkills[skillName]
	if not list then return end

	for i = #list, 1, -1 do
		if list[i] == runner then
			table.remove(list, i)
			break
		end
	end

	-- Remove lista se vazia
	if #list == 0 then
		self.ActiveSkills[skillName] = nil
	end
end

--[[
Retorna uma ou várias habilidades ativas, junto de seus runners responsáveis
@param skillName - nome da skill STRING (opcional, se fornecido, devolve só essa skill)
@return lista de runners TABLE ou tabela com todas as skills ativas TABLE
]]
function CombatComponent:GetActiveSkills(skillName : string?)
	if skillName then
		return self.ActiveSkills[skillName] or {}
	end
	return self.ActiveSkills
end

--[[
Retorna a quantidade de runners ativos para uma skill específica
@param skillName - nome da skill STRING
@return quantidade de runners NUMBER
]]
function CombatComponent:GetActiveSkillCount(skillName : string) : number
	local list = self.ActiveSkills[skillName]
	return list and #list or 0
end

--[[
Verifica se a skill especificada está ativa
@param skillName - nome da skill STRING
@return está ativa BOOLEAN
]]
function CombatComponent:HasActiveSkill(skillName : string) : boolean
	return self:GetActiveSkillCount(skillName) > 0
end


--[[
Para cada skill ativa, para todos os runners, chama o método Stop ou endSkill
@param cancel - se true, indica que a skill foi cancelada (opcional, padrão false) BOOLEAN
]]
function CombatComponent:StopAllActiveSkills(cancel : boolean?)
	for skillName, runners in pairs(self.ActiveSkills) do
		for _, runner in ipairs(runners) do
			if runner.Stop then
				runner:Stop(cancel or false)
			elseif runner.endSkill then
				runner:endSkill(cancel or false)
			end
		end
	end
	table.clear(self.ActiveSkills)
end


--[[
Atualiza o loadout de Skills (func interna)
]]
function CombatComponent:_ApplyLoadout(loadoutData)
	if typeof(loadoutData) ~= "table" then warn("[CombatComponent],ApplyFunc, Loadout =~ table"); return end

	local StructureCheck = loadoutData.Slots ~= nil or loadoutData.List ~= nil
	assert(StructureCheck,"[CombatComponent] formatação de loadout inválida, confira tipo (slots ou list)") 
	if not StructureCheck then return end


	-- Limpa o atual
	table.clear(self.Loadout)

	local isList = loadoutData.List or false


	if isList then
		warn(loadoutData)
		for _, skillKey in ipairs(loadoutData.List) do
			self:AddSkill(skillKey) -- Salva no próximo slot livre
		end
	else
		for slot, skillKey in pairs(loadoutData.Slots) do
			self:EquipSkill(slot, skillKey) -- Override no slot definido
		end
	end
end

--[[
Adiciona uma nova skill no loadout que ocupará o próximo slot livre
]]
function CombatComponent:AddSkill(skillKey)
	for _, slot in ipairs(Intents.SkillOrder) do
		if self.Loadout[slot] == nil then
			return self:EquipSkill(slot, skillKey) and slot or nil
		end
	end
	warn("[CombatComponent] Loadout cheio, skill ignorada:", skillKey)
	return nil
end


--[[
Equipa uma skill em um slot dedicado/especificado.
]]
function CombatComponent:EquipSkill(slotIndex, skillKey)
	
	if not Intents.IsButton(slotIndex) then
		warn("[CombatComponent] Slot inválido (use Intents.Id):", slotIndex)
		return false
	end
	
	local skillPointer

	-- Se for string, procura no database
	if type(skillKey) == "string" then
		--Verifica Cache
		if self.SkillCache[skillKey] then
			skillPointer = self.SkillCache[skillKey]
		else
			--Busca o Script Físico
			local scriptInstance = SkillData._Registry[skillKey]
			if not scriptInstance then 
				warn("Skill Key inválida:", skillKey) 
				return false 
			end
			
			--Require
			local success, result = pcall(require, scriptInstance)
			if not success then return warn("Erro no script da skill:", skillKey) end
			
			--Aplica nome caso não tenha
			if not result.data then result.data = {} end
			if not result.data.name then result.data.name = skillKey end
			
			--Salva no cache
			self.SkillCache[skillKey] = result
			skillPointer = result
		end
	
	--Se for skill criada via código (table)
	elseif type(skillKey) == "table" then
		skillPointer = skillKey
	end

	if not skillPointer then return false end

	-- Inicializa cooldown se precisar
	local name = skillPointer.data.name
	if not self.Cooldowns[name] then self.Cooldowns[name] = 0 end

	-- Salva no slot
	self.Loadout[slotIndex] = skillPointer
	
	return true
end

--[[
Remove uma skill de um slot
]]
function CombatComponent:UnequipSlot(slotIndex)
	self.Loadout[slotIndex] = nil
end

--[[
Retorna a skill no slot caso presente
]]
function CombatComponent:GetSkillFromSlot(slot)
	return self.Loadout[slot] or nil
end


--[[
Guarda o runner que a intent ativou/reciclou, para o Release chegar no runner certo
(e não em "todos os runners da skill"), mesmo que o slot mude no meio do gesto.
@param intent - Intents.Id STRING
@param runner - SkillRunner
]]
function CombatComponent:SetIntentRunner(intent : string, runner)
	self.IntentRunners[intent] = runner
end

--[[
Devolve E limpa o runner da intent.
@return SkillRunner ou nil
]]
function CombatComponent:TakeIntentRunner(intent : string)
	local runner = self.IntentRunners[intent]
	self.IntentRunners[intent] = nil
	return runner
end

--=============================================================================
--  CHARACTER E FORMAS
--=============================================================================

function CombatComponent:SetChosenChar(Char)
 if self.ChosenChar == Char then return false end

    self.ChosenChar = Char

    -- Recarrega folders
    if not self:_LoadFolders() then
        return false
    end

    self:LoadSkillsData()

    -- Atualiza stats
    local stats = self.Entity.GetStats()
    self.Entity.SetAttribute(StateTable.Enum.Stats.Speed, stats.speed or StateTable.Enum.Stats.Speed, 16)
    self.Entity.SetAttribute(StateTable.Enum.Stats.JumpForce, stats.JumpPower or StateTable.Enum.Stats.JumpForce, 50)

    -- Atualiza HP
    local health = self.Entity:GetComponent(self.Entity.ComponentKey.Health)
    if health and stats.MaxHP then
        local ratio = self.Entity.GetHealthRatio()
        health.MaxHP = stats.MaxHP
        self.Entity.SetHP(stats.MaxHP * ratio) -- Mantém proporção
    end

    return true
end


function CombatComponent:GetChosenChar()
	return self.ChosenChar
end


function CombatComponent:SetCharMode(charName : string, modeName : string)

	--Busca a string no database de char config
	local charData = CharData[charName]
	if not charData then return warn("Char não existe:", charName) end
	
	local formData = charData[modeName]
	if not formData then return warn("Modo não existe:", modeName) end

	-- Atualiza estado
	self.ChosenChar = charName
	self.Mode = modeName
	self.BaseStats = formData.Stats

	-- Aplica Stats
	self:_ApplyStats(formData.Stats)

	-- Aplica Skills
	self:_ApplyLoadout(formData.Loadout)
	
	return true
end


function CombatComponent:GetCharMode()
	return self.Mode
end

--[[
Retorna as postas de forma e dados do personagem escolhido.
@return FormFolder, CharFolder
]]
function CombatComponent:GetCharFolders()
	return self._formFolder,self.charFolder
end

-- Aplica Stats
function CombatComponent:_ApplyStats(stats)
	if stats.Speed then self.Entity.SetSpeed(stats.Speed) end
	if stats.JumpPower then self.Entity.SetJumpForce(stats.JumpPower) end
	
	local health = self.Entity:GetComponent("Health")
	if health and stats.MaxHP then
		local ratio = self.Entity.GetHealthRatio()
		self.Entity.SetMaxHP(stats.MaxHP)
		self.Entity.SetHP(stats.MaxHP * ratio)
	end
end


--=============================================================================
--  LIFECYCLE
--=============================================================================

--[[
Função de inicialização do componente, tenta carregar skills automaticamente
]]
function CombatComponent:OnAdded()
	-- Carrega personagem padrão
		self:SetCharMode(self.ChosenChar, self.Mode)
end



--[[
Função de destruição do componente, para todas as skills ativas e limpa tabelas
]]
function CombatComponent:Destroy()
	self:StopAllActiveSkills(true)
	table.clear(self.Cooldowns)
	table.clear(self.ActiveSkills)
	table.clear(self.Loadout)
	table.clear(self.SkillCache)
	table.clear(self.IntentRunners)
	self.Entity = nil
end


--=============================================================================
--  API EXPOSE
--=============================================================================

local ExposeAPI = {
	-- Getters skills
	GetSkillName = function(component, ...) return component:GetSkillName(...) end,
	GetSkillScript = function(component, ...) return component:GetSkillScript(...) end,
	GetSkillData = function(component, ...) return component:GetSkillData(...) end,
	GetSkillFromSlot = function(component, ...) return component:GetSkillFromSlot(...) end,

	-- Cooldowns
	HasCooldown = function(component, ...) return component:HasCooldown(...) end,
	SetCooldown = function(component, ...) return component:SetCooldown(...) end,
	GetCooldown = function(component, ...) return component:GetCooldown(...) end,
	ResetCooldown = function(component, ...) return component:ResetCooldown(...) end,

	-- Active Skills
	AddActiveSkill = function(component, ...) return component:AddActiveSkill(...) end,
	RemoveActiveSkill = function(component, ...) return component:RemoveActiveSkill(...) end,
	GetActiveSkills = function(component, ...) return component:GetActiveSkills(...) end,
	GetActiveSkillCount = function(component,...) return component:GetActiveSkillCount(...) end,
	HasActiveSkill = function(component, ...) return component:HasActiveSkill(...) end,
	StopAllActiveSkills = function(component, ...) return component:StopAllActiveSkills(...) end,

	--Personagem/modo
	GetChosenChar = function(component,...) return component:GetChosenChar(...) end,
	SetChosenChar = function(component,...) return component:SetChosenChar(...) end,
	GetCharMode = function(component,...) return component:GetCharMode(...) end,
	SetCharMode = function(component,...) return component:SetCharMode(...) end,

	--Loadout
	EquipSkill = function(component, ...) return component:EquipSkill(...) end,
	AddSkill = function(component, ...) return component:AddSkill(...) end,
	UnequipSlot = function(component, ...) return component:UnequipSlot(...) end,


	--Validação
	CanContinue = function(component,...) return component:CanContinue(...) end,
	TrySelfCancel = function(component,...) return component:TrySelfCancel(...) end,     

	--PlayerState
	GetPlayerState = function(component,...) return component:GetPlayerState(...)end,
	SetPlayerState = function(component,...) return component:SetPlayerState(...)end,
	RemovePlayerState = function(component,...) return component:RemovePlayerState(...)end,

	GetCharFolders = function(component,...) return component:GetCharFolders(...)end,
	
	
	--Intents (hold, release) (NÃO é obrigação desse component, mas por precisar do redirect pra skill mantivemos aqui)
	TakeIntentRunner = function(component,...) return component:TakeIntentRunner(...)end,
	SetIntentRunner = function(component,...) return component:SetIntentRunner(...)end,
}


return {
	new = CombatComponent.new,
	ExposeAPI = ExposeAPI
}
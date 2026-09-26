--[[
	- Equipar/desequipar armas
	- Hitbox wrapper
	- HitOrigin
]]

local RS = game:GetService("ReplicatedStorage")
local Storage = game:GetService("ServerStorage")
local HitboxWrapper = require(Storage.Modules.Combat.Hitbox.HitboxWrapper)
local StateTable = require(Storage.Modules.Combat.StateTable)

local WeaponComponent = {}
WeaponComponent.__index = WeaponComponent

--[[
Inicializa o componente de arma na entidade
@param entity - Entidade dona do componente Entity, enviar EntityData
@param config - Configurações iniciais do componente TABLE { WeaponName: string }
@return nova instância do WeaponComponent WeaponComponent
]]
function WeaponComponent.new(entity, config)
	local self = setmetatable({}, WeaponComponent)

	self.Entity = entity

	-- Arma atual
	self.Weapon = nil
	self.WeaponName =  config.WeaponName or nil		--Busca por nome na pasta do char selecionado
	self.WeaponModel = config.WeaponModel or nil	--Cria direto com base no modelo fornecido.
	self.WeaponMode = nil
	self.WeaponData = nil
	self.IsCosmetic =  config.IsCosmetic or false	--Ignora a criação de hitboxes

	-- Hitbox
	self.HitOrigin = nil
	self.Hitbox = nil

	-- Modes and Motors
	self.Motors = {}
	self.CurrentMode = nil
	self.CurrentModeData = nil

	return self
end

--=============================================================================
--  WEAPON EQUIP
--=============================================================================

--[[
Equipar uma arma ao personagem
@param weaponName - nome da arma a ser equipada STRING
@return sucesso BOOLEAN
]]
function WeaponComponent:EquipWeapon(weaponName : string) : boolean

	local char = self.Entity.Instance

	local weaponModel

	--Se tiver componente de combate:
	if self.Entity:HasComponent(self.Entity.ComponentKey.Combat) then


		local chosenChar = self.Entity.GetChosenChar()

		-- Busca arma na pasta de assets
		local weaponsFolder = RS.Assets.Weapons:FindFirstChild(chosenChar)
		if not weaponsFolder then
			warn("[WeaponComponent] Pasta de armas não encontrada:", chosenChar)
			return false
		end


		local weaponFolder = weaponsFolder:FindFirstChild(weaponName)
		if not weaponFolder then
			warn("[WeaponComponent] Arma não encontrada:", weaponName)
			return false
		end

		weaponModel = weaponFolder:FindFirstChild(weaponName)


	--Se não tiver, aceite modelo informado por config
	elseif self.WeaponModel then
		weaponModel = self.WeaponModel
	else
		return false 
	end

		-- Remove arma antiga
		self:UnequipWeapon()

	-- Clona arma
	local weaponClone = weaponModel:Clone()
	weaponClone.Name = weaponModel.Name
	weaponClone.Parent = char

	local handle = weaponClone:FindFirstChild("Handle")
	if not handle then
		warn("[WeaponComponent] Arma sem Handle")
		weaponClone:Destroy()
		return false
	end

	-- Salva referências primárias (antes do attach/modo)
	self.Weapon = weaponClone
	self.WeaponName = weaponName
	self.HitOrigin = weaponClone:FindFirstChild("hitOrigin")
	
	self.Motors = {}

	local weaponData = self:_GetWeaponData()
	if weaponData and weaponData.Modes then
		self:SetMode(weaponData.DefaultMode or "Default")
	else
		-- Determina ponto de attach (fallback)
		local attachTo = self:_GetAttachPoint(weaponModel)
		local charAttach = char:FindFirstChild(attachTo)

		if not charAttach then
			warn("[WeaponComponent] Ponto de attach não encontrado:", attachTo)
			weaponClone:Destroy()
			return false
		end

		-- Cria Motor6D
		local motor = Instance.new("Motor6D")
		motor.Part0 = charAttach
		motor.Part1 = handle
		motor.C1 = self:_GetCFrameFor(weaponClone, "primary")
		motor.Parent = handle
		self.Motors["primary"] = motor
	end

	-- Cria wrapper de hitbox caso não seja modelo cosmético
	if not self.IsCosmetic then
		self.Hitbox = HitboxWrapper.new(self.Entity)
	end
	
	print(string.format("[WeaponComponent] Arma '%s' equipada com sucesso na entidade %s!", weaponName, tostring(self.Entity.ID)))

	return true
end

--[[
Retorna o ponto de attach para a arma seguindo a prioridade:
Arma > Personagem > fallback default (right arm)
@param weaponModel - modelo da arma
@return nome do ponto de attach STRING
]]
function WeaponComponent:_GetAttachPoint(weaponModel : Instance) : string
	-- Prioridade: Arma > Personagem > Padrão

	-- 1. Busca na arma
	local attachValue = weaponModel:FindFirstChild("AttachTo")
	if attachValue and attachValue.Value then
		return attachValue.Value
	end

	-- 2. Busca no personagem
	local Stats = self.Entity.GetStats()
	if Stats.attachTo then
		return Stats.attachTo
	end

	-- 3. Padrão
	return "Right Arm"
end

function WeaponComponent:_GetCFrameFor(weaponClone: Instance, key: string): CFrame
	local cframeValue = weaponClone:FindFirstChild("Value_" .. key)
		or weaponClone:FindFirstChild("Value")
	return cframeValue and cframeValue.Value or CFrame.identity
end

function WeaponComponent:_AttachAllPoints(weaponClone, attachPoints)
	for key, attachName in pairs(attachPoints) do
		local charAttach = self.Entity.Instance:FindFirstChild(attachName)
		local handle = weaponClone:FindFirstChild(key == "primary" and "Handle" or ("Handle_" .. key))
						or weaponClone:FindFirstChild("Handle")

		if not charAttach or not handle then
			warn("[WeaponComponent] Attach point ou handle não encontrado:", key, attachName)
			continue
		end

		local motor = Instance.new("Motor6D")
		motor.Part0 = charAttach
		motor.Part1 = handle
		motor.C1 = self:_GetCFrameFor(weaponClone, key)
		motor.Parent = handle
		self.Motors[key] = motor
	end
end

function WeaponComponent:_ClearMotors()
	for key, motor in pairs(self.Motors) do
		motor:Destroy()
	end
	table.clear(self.Motors)
end

function WeaponComponent:_GetWeaponData(): {}?
	if self.WeaponData then return self.WeaponData end
	
	if not self.WeaponName then return nil end
	
	local chosenChar = self.Entity.GetChosenChar and self.Entity.GetChosenChar()
	if not chosenChar then return nil end
	
	local weaponsFolder = RS.Assets.Weapons:FindFirstChild(chosenChar)
	if not weaponsFolder then return nil end
	
	local weaponFolder = weaponsFolder:FindFirstChild(self.WeaponName)
	if not weaponFolder then return nil end
	
	local dataModule = weaponFolder:FindFirstChild("WeaponData")
	if not dataModule then return nil end
	
	local success, data = pcall(require, dataModule)
	if success then
		self.WeaponData = data
		return data
	end
	
	return nil
end

function WeaponComponent:SetMode(modeName: string): boolean
	local weaponData = self:_GetWeaponData()
	if not weaponData or not weaponData.Modes or not weaponData.Modes[modeName] then
		warn("[WeaponComponent] Modo inválido ou arma sem Modes:", modeName)
		return false
	end

	local modeData = weaponData.Modes[modeName]

	self:_ClearMotors()
	self:_AttachAllPoints(self.Weapon, modeData.AttachPoints)

	self.CurrentMode = modeName
	self.CurrentModeData = modeData

	return true
end

function WeaponComponent:GetCurrentMode(): string?
	return self.CurrentMode
end

function WeaponComponent:GetModeData(): {}?
	return self.CurrentModeData
end

function WeaponComponent:GetWeaponData(): {}?
	return self:_GetWeaponData()
end

--[[
Desequipar a arma atual
]]
function WeaponComponent:UnequipWeapon()
	self:DestroyHitbox()
	self:_ClearMotors()

	if self.Weapon then
		self.Weapon:Destroy()
		self.Weapon = nil
	end

	self.WeaponName = nil
	self.HitOrigin = nil
	self.Hitbox = nil
	self.CurrentMode = nil
	self.CurrentModeData = nil
	self.WeaponData = nil
end

--=============================================================================
--  GETTERS
--=============================================================================

--[[
Retorna o modelo da arma equipada
]]
function WeaponComponent:GetWeapon()
	return self.Weapon
end

--[[
Retorna o nome da arma equipada
]]
function WeaponComponent:GetWeaponName()
	return self.WeaponName
end


--[[
Retorna a origem do hitbox da arma equipada
]]
function WeaponComponent:GetHitOrigin()
	return self.HitOrigin
end

--[[
Retorna o hitbox da arma equipada
]]
function WeaponComponent:GetHitbox()
	return self.Hitbox
end

--[[
Verifica se a entidade possui uma arma equipada
@return possui arma BOOLEAN
]]
function WeaponComponent:HasWeapon()
	return self.Weapon ~= nil
end

--=============================================================================
--  HITBOX PROXY
--=============================================================================

function WeaponComponent:StartHitbox(...)
	return self.Hitbox and self.Hitbox:StartHitbox(...)
end

function WeaponComponent:StopHitbox()
	if self.Hitbox then
		self.Hitbox:StopHitbox()
	end
end

function WeaponComponent:AddHitboxOwner(owner)
	return self.Hitbox and self.Hitbox:AddOwner(owner)
end

function WeaponComponent:RemoveHitboxOwner(owner)
	return self.Hitbox and self.Hitbox:RemoveOwner(owner)
end

function WeaponComponent:IsHitboxActive()
	return self.Hitbox and self.Hitbox:IsHitboxActive()
end

function WeaponComponent:DestroyHitbox()
	if self.Hitbox then
		self.Hitbox:DestroyHitbox()
		self.Hitbox = nil
	end
end

function WeaponComponent:GetActiveHitboxes()
	return self.Hitbox and self.Hitbox:GetActiveHitboxes() or {}
end

function WeaponComponent:GetHitboxConfigs()
	return self.Hitbox and self.Hitbox:GetHitboxConfigs() or {}
end


--=============================================================================
--  UTILITY
--=============================================================================

--[[
Retorna a posição da arma equipada
@return posição VECTOR3
]]
function WeaponComponent:GetWeaponPosition() : Vector3
	return self.Weapon and self.Weapon:GetPivot().Position or Vector3.zero
end

--[[
Retorna o CFrame da arma equipada
@return CFrame
]]
function WeaponComponent:GetWeaponCFrame() : CFrame
	return self.Weapon and self.Weapon:GetPivot() or CFrame.identity
end

--=============================================================================
--  LIFECYCLE
--=============================================================================

--[[
Destrói o componente de armas, removendo a arma equipada e limpando referências
]]
function WeaponComponent:Destroy()
	self:UnequipWeapon()
	self.Entity = nil
end

function WeaponComponent:OnAdded()
	local weaponToEquip = self.WeaponName or self.Entity.GetStat(StateTable.Enum.Stats.Weapon)

	
	if weaponToEquip and type(weaponToEquip) == "string" and weaponToEquip ~= "" and weaponToEquip ~= "None" then
		self:EquipWeapon(weaponToEquip)
	else
		warn(string.format("[WeaponComponent] Nenhuma arma equipada na entidade %s. (Weapon: %s)", tostring(self.Entity.ID), tostring(weaponToEquip)))
	end
end

--=============================================================================
--  API EXPOSE
--=============================================================================

local ExposeAPI = {
	-- Weapon 
	EquipWeapon   = function(component, ...) return component:EquipWeapon(...) end,
	UnequipWeapon = function(component) return component:UnequipWeapon() end,
	GetWeapon     = function(component) return component:GetWeapon() end,
	GetWeaponName = function(component) return component:GetWeaponName() end,
	GetHitOrigin  = function(component) return component:GetHitOrigin() end,
	GetHitbox     = function(component) return component:GetHitbox() end,
	HasWeapon     = function(component) return component:HasWeapon() end,
	SetMode       = function(component, ...) return component:SetMode(...) end,
	GetCurrentMode= function(component) return component:GetCurrentMode() end,
	GetModeData   = function(component) return component:GetModeData() end,
	GetWeaponData = function(component) return component:GetWeaponData() end,

	-- Utility 
	GetWeaponPosition = function(component) return component:GetWeaponPosition() end,
	GetWeaponCFrame   = function(component) return component:GetWeaponCFrame() end,

	-- Hitbox proxy 
	StartHitbox        = function(component, ...) return component:StartHitbox(...) end,
	StopHitbox         = function(component) return component:StopHitbox() end,
	DestroyHitbox      = function(component) return component:DestroyHitbox() end,
	AddHitboxOwner     = function(component, owner) return component:AddHitboxOwner(owner) end,
	RemoveHitboxOwner  = function(component, owner) return component:RemoveHitboxOwner(owner) end,
	IsHitboxActive     = function(component) return component:IsHitboxActive() end,
	GetActiveHitboxes  = function(component) return component:GetActiveHitboxes() end,
	GetHitboxConfigs   = function(component) return component:GetHitboxConfigs() end,
}


return {
	new = WeaponComponent.new,
	ExposeAPI = ExposeAPI
}
--[[
	- Equipar/desequipar armas
	- Hitbox wrapper
	- HitOrigin
]]

local RS = game:GetService("ReplicatedStorage")
local Storage = game:GetService("ServerStorage")
local HitboxWrapper = require(Storage.Modules.Combat.Hitbox.HitboxWrapper)
local StateTable = require(Storage.Modules.Combat.StateTable)
local Log = require(RS.Logger).Channel("WeaponComponent")

local WeaponComponent = {}
WeaponComponent.__index = WeaponComponent

local warnedDuplicates = {} -- [pasta da arma] = true: o aviso de duplicata sai uma vez por servidor

--[[
Pasta da arma pelo nome. Nome duplicado (inclusive só na capitalização) é erro: avisa e usa a
pasta completa (com o model).
]]
local function findWeaponFolder(weaponsFolder: Instance, weaponName: string): Instance?
	local lowered = string.lower(weaponName)
	local matches = {}
	for _, child in weaponsFolder:GetChildren() do
		if string.lower(child.Name) == lowered then
			table.insert(matches, child)
		end
	end
	if #matches <= 1 then
		return matches[1]
	end

	local key = weaponsFolder:GetFullName() .. "." .. lowered
	if not warnedDuplicates[key] then
		warnedDuplicates[key] = true
		warn(string.format("[WeaponComponent] %d pastas de arma com o nome '%s' em %s (regra 19): apague a legada",
			#matches, weaponName, weaponsFolder:GetFullName()))
	end
	for _, folder in matches do
		if folder.Name == weaponName and folder:FindFirstChild(weaponName) then
			return folder
		end
	end
	for _, folder in matches do
		if folder:FindFirstChildWhichIsA("Model") then
			return folder
		end
	end
	return matches[1]
end

--[[
Pasta da arma: primeiro no kit preferido (o pedido no EquipWeapon, ou o personagem de quem equipa);
se ele não tiver a arma, no único kit que tiver uma com esse nome. Nome em mais de um kit é ambíguo:
não escolhe, avisa e pede o kit.
@param weaponName - nome da arma STRING
@param preferredKit - kit onde procurar primeiro STRING?
@param strict - true = só no preferredKit (kit pedido explicitamente) BOOLEAN?
@return pasta da arma, ou nil e o motivo
]]
local function resolveWeaponFolder(weaponName: string, preferredKit: string?, strict: boolean?): (Instance?, string?)
	local root = RS.Assets.Weapons
	if preferredKit then
		local kitFolder = root:FindFirstChild(preferredKit)
		local found = kitFolder and findWeaponFolder(kitFolder, weaponName)
		if found then return found end
		if strict then return nil, "a arma não está no kit " .. preferredKit end
	end
	local folders, kits = {}, {}
	for _, kitFolder in root:GetChildren() do
		local found = findWeaponFolder(kitFolder, weaponName)
		if found then
			table.insert(folders, found)
			table.insert(kits, kitFolder.Name)
		end
	end
	if #folders == 1 then return folders[1] end
	if #folders == 0 then return nil, "nenhum kit tem essa arma" end
	return nil, "a arma existe em " .. #folders .. " kits (" .. table.concat(kits, ", ") .. "): passe o kit no EquipWeapon"
end

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
@param kit - kit dono da arma (pasta em Assets.Weapons), se o nome existir em mais de um STRING?
@return sucesso BOOLEAN
]]
function WeaponComponent:EquipWeapon(weaponName : string, kit : string?) : boolean

	local char = self.Entity.Instance

	local weaponModel, weaponFolder

	-- Modelo informado por config (entidade sem personagem); senão, a pasta da arma pelo kit. O
	-- personagem (Combat, dependência opcional) só diz em que kit procurar primeiro
	local hasCombat = self.Entity:HasComponent(self.Entity.ComponentKey.Combat)
	if self.WeaponModel and not hasCombat and not kit then
		weaponModel = self.WeaponModel
	else
		local ownKit = hasCombat and self.Entity.GetChosenChar() or nil
		local why
		weaponFolder, why = resolveWeaponFolder(weaponName, kit or ownKit, kit ~= nil)
		if not weaponFolder then
			warn("[WeaponComponent] Arma não encontrada:", weaponName, "-", why)
			return false
		end
		weaponModel = weaponFolder:FindFirstChild(weaponName)
		if not weaponModel then
			warn("[WeaponComponent] Pasta da arma sem o model:", weaponFolder:GetFullName())
			return false
		end
	end

		-- Remove arma antiga
		self:UnequipWeapon()
		self.WeaponFolder = weaponFolder -- de onde o _GetWeaponData lê o WeaponData

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
	
	Log.Debug(string.format("arma '%s' equipada na entidade %s", weaponName, tostring(self.Entity.ID)))

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

		-- Ponto secundário exige a sua peça (Handle_<key>): dois Motor6D na mesma peça brigam
		if not handle and key ~= "primary" then
			warn(string.format("[WeaponComponent] %s sem Handle_%s: o ponto '%s' fica sem arma",
				weaponClone.Name, key, tostring(attachName)))
			continue
		end

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
	
	-- A pasta que o EquipWeapon resolveu
	local weaponFolder = self.WeaponFolder
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
	self.WeaponFolder = nil
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

-- owner = o runner (cada skill tem a sua hitbox); sem owner, a sessão compartilhada
function WeaponComponent:StopHitbox(owner)
	if self.Hitbox then
		self.Hitbox:StopHitbox(owner)
	end
end

function WeaponComponent:AddHitboxOwner(owner)
	return self.Hitbox and self.Hitbox:AddOwner(owner)
end

function WeaponComponent:RemoveHitboxOwner(owner)
	return self.Hitbox and self.Hitbox:RemoveOwner(owner)
end

function WeaponComponent:IsHitboxActive(owner)
	return self.Hitbox and self.Hitbox:IsHitboxActive(owner)
end

function WeaponComponent:DestroyHitbox()
	if self.Hitbox then
		self.Hitbox:DestroyHitbox()
		self.Hitbox = nil
	end
end

-- Com owner, as hitboxes ativas da sessão dele; sem owner, as de todas as sessões (debug)
function WeaponComponent:GetActiveHitboxes(owner)
	return self.Hitbox and self.Hitbox:GetActiveHitboxes(owner) or {}
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
		Log.Debug(string.format("nenhuma arma equipada na entidade %s (Weapon: %s)", tostring(self.Entity.ID), tostring(weaponToEquip)))
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
	-- owner = o runner dono da sessão (self:StopHitbox passa o dele); sem owner, a sessão compartilhada
	StopHitbox         = function(component, owner) return component:StopHitbox(owner) end,
	DestroyHitbox      = function(component) return component:DestroyHitbox() end,
	AddHitboxOwner     = function(component, owner) return component:AddHitboxOwner(owner) end,
	RemoveHitboxOwner  = function(component, owner) return component:RemoveHitboxOwner(owner) end,
	IsHitboxActive     = function(component, owner) return component:IsHitboxActive(owner) end,
	GetActiveHitboxes  = function(component, owner) return component:GetActiveHitboxes(owner) end,
	GetHitboxConfigs   = function(component) return component:GetHitboxConfigs() end,
}


return {
	new = WeaponComponent.new,
	ExposeAPI = ExposeAPI,
	_findWeaponFolder = findWeaponFolder, -- interno, exposto para os testes
}
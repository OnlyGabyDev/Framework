-- ============================= SCRIPT USADO PRA ABSTRAÇÃO ENTRE CUSTOM MODELS E HUMANOIDS =====================================


local EntityWrapper = {}

-- ========== INTERFACES (Contratos) ========== --

--[[
    ICharacter - Interface de dados de char
]]
local ICharacter = {}

function ICharacter:GetRoot() 	  end
function ICharacter:SetRoot() 	  end
function ICharacter:SetHumanoid() end
function ICharacter:GetHumanoid() end

--[[
IMovement - Interface de dados de movimentação
]]

local IMovement = {}
function IMovement:Move(direction: Vector3) end
function IMovement:ApplyVelocity(velocity: Vector3) end
function IMovement:SetGravityScale(scale: number) end
function IMovement:SetFrozen(isFrozen: boolean) end
function IMovement:SetSpeed(amount: number) end
function IMovement:SetJumpForce(amount: number) end


--====================CHARACTER==========================--


--====HUMANOIDS=======--
local HumanoidCharacter = {}
HumanoidCharacter.__index = HumanoidCharacter

function HumanoidCharacter.new(humanoid,root)
	local self = setmetatable({}, HumanoidCharacter)

	self._humanoid = humanoid
	self._root = root


	return self
end


function HumanoidCharacter:GetRoot()
	return self._root
end


function HumanoidCharacter:SetRoot(root)
	self._root = root
end


function HumanoidCharacter:SetHumanoid(humanoid)
	self._humanoid = humanoid
end


function HumanoidCharacter:GetHumanoid()
	return self._humanoid
end




--========NPCS========--
local NPChar = {}
NPChar.__index = NPChar

function NPChar.new(root)
	local self = setmetatable({}, NPChar)

	self._humanoid = nil

	self._root = root

	return self
end

function NPChar:GetRoot()
	return self._root
end

function NPChar:SetRoot(root)
	self._root = root
end

function NPChar:SetHumanoid()
	--Função vazia apenas pra manter a padronização dos contatos, warn de boas práticas acompanha.
	warn("[EntityWrapper]Tentativa de settar Humanoid em entidade sem humanoid")
end

function NPChar:GetHumanoid()
	return nil
end



--====================MOVIMENTAÇÃO=======================--
-- ==================== HUMANOID IMPLEMENTATION ==================== --

local HumanoidMovement = {}
HumanoidMovement.__index = HumanoidMovement

function HumanoidMovement.new(characterWrapper)
    local self = setmetatable({}, HumanoidMovement)
    self._character = characterWrapper
    self._gravityForce = nil
    return self
end

function HumanoidMovement:Move(direction: Vector3)
    local hum = self._character:GetHumanoid()
    if hum then hum:Move(direction, false) end
end

function HumanoidMovement:ApplyVelocity(velocity: Vector3)
    local root = self._character:GetRoot()
    if root then root.AssemblyLinearVelocity = velocity end
end

function HumanoidMovement:SetSpeed(speed)
    local hum = self._character:GetHumanoid()
    if hum then hum.WalkSpeed = speed end
end

function HumanoidMovement:SetJumpForce(jump)
    local hum = self._character:GetHumanoid()
    if hum then hum.JumpHeight = jump end
end

function HumanoidMovement:SetFrozen(isFrozen)
    local hum = self._character:GetHumanoid()
    local root = self._character:GetRoot()
    if not hum or not root then return end

    if isFrozen then
        hum.WalkSpeed = 0
        hum.JumpHeight = 0
        root.Anchored = true
    else
        root.Anchored = false
        -- Nota: A velocidade será restaurada pelo Controller no próximo frame
    end
end

function HumanoidMovement:SetGravityScale(scale)
    local root = self._character:GetRoot()
    if not root then return end

    if scale >= 0.99 and scale <= 1.01 then
        if self._gravityForce then self._gravityForce:Destroy() self._gravityForce = nil end
        return
    end

    if not self._gravityForce then
        local att = root:FindFirstChild("RootAttachment") or Instance.new("Attachment", root)
        att.Name = "RootAttachment"
        self._gravityForce = Instance.new("VectorForce")
        self._gravityForce.Name = "GravityControl"
        self._gravityForce.Attachment0 = att
        self._gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
        self._gravityForce.Parent = root
    end

    local mass = root.AssemblyMass
    local gravity = workspace.Gravity
    self._gravityForce.Force = Vector3.new(0, mass * gravity * (1 - scale), 0)
end

-- ==================== NPC (NON-HUMANOID) IMPLEMENTATION ==================== --

local NPCMovement = {}
NPCMovement.__index = NPCMovement

function NPCMovement.new(characterWrapper)
    local self = setmetatable({}, NPCMovement)
    self._character = characterWrapper
    return self
end

function NPCMovement:SetSpeed(speed)
    -- Se for NPC físico, pode usar LinearVelocity ou BodyVelocity
    self._currentSpeed = speed 
end

function NPCMovement:Move(direction: Vector3)
    local root = self._character:GetRoot()
    if root and not root.Anchored and self._currentSpeed then
        root.CFrame = root.CFrame + (direction * self._currentSpeed * 0.016)
    end
end

-- Stubs para compatibilidade
function NPCMovement:ApplyVelocity(v) end
function NPCMovement:SetJumpForce(j) end
function NPCMovement:SetGravityScale(s) end
function NPCMovement:SetFrozen(f) 
    local root = self._character:GetRoot()
    if root then root.Anchored = f end
end

-- ========== FACTORY ========== --


--[[
CreateCharacter, Função de criação de um novo wrapper de referências a partes essenciais da entidade
@params tabela de dados {humanoid[1],root[2]} TABLE
@return tabela de funções.
]]
EntityWrapper.CreateCharacter = function(params)
	--[[
	PARAMS
	1 - Humanoid
	2 -- Root
	]]

	if params[1] ~= nil then
		warn("WRAPPER DE CHARACTER HUMANOIDE INSTANCIADO")
		return HumanoidCharacter.new(params[1],params[2])
	else
		-- NPC sem Humanoid
		warn("WRAPPER DE CHARACTER NPC INSTANCIADO")
		return NPChar.new(params[2])
	end
end




--[[
CreateMovement, Função de criação de um novo wrapper de movimentação
@params Character Wrapper
@return tabela de funções.
]]
EntityWrapper.CreateMovement = function(characterWrapper)
    if characterWrapper:GetHumanoid() then 
        return HumanoidMovement.new(characterWrapper)
    else
        return NPCMovement.new(characterWrapper)
    end
end

-- ========== EXPORTS ========== --
EntityWrapper.ICharacter = ICharacter
EntityWrapper.IMovement = IMovement

return EntityWrapper
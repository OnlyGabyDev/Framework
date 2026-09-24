-- ============================= SCRIPT USADO PRA ABSTRAÇÃO ENTRE CUSTOM MODELS E HUMANOIDS =====================================

local ServerScriptService = game:GetService("ServerScriptService")
local ForceRig = require(ServerScriptService.Modules.Physics.ForceRig)

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

Regra 17 (dono único do shape): esse é o contrato que TODO wrapper de
movimentação (Humanoid ou NPC) precisa cumprir. O MovementController só fala
com essa interface — nunca deve saber se está lidando com um Humanoid ou não.
]]

local IMovement = {}
function IMovement:Move(direction: Vector3) end
function IMovement:SetSpeed(amount: number) end
function IMovement:SetJumpForce(amount: number) end
function IMovement:SetFrozen(isFrozen: boolean) end
function IMovement:SetAmbientGravityScale(scale: number) end
function IMovement:ApplyForceFrame(targetVelocity: Vector3, maxAxesForce: Vector3) end
function IMovement:ReleaseForces() end
function IMovement:FaceDirection(direction: Vector3, responsiveness: number?) end
function IMovement:ReleaseFaceDirection() end
function IMovement:Destroy() end
function IMovement:GetAirState(): string end -- "Grounded" | "Jumping" | "Falling"

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

--[[
	HumanoidMovement
	----------------
	Toda a movimentação "orgânica" (WASD, pulo, colisão com rampas/degraus)
	continua 100% por conta do Humanoid nativo — não faz sentido reinventar
	isso. O que essa classe adiciona é a camada de Forces (dashes, knockback,
	zero-G) via ForceRig, que só entra em ação quando uma Force está
	ativa, sem nunca tocar em AssemblyLinearVelocity diretamente.
]]
local HumanoidMovement = {}
HumanoidMovement.__index = HumanoidMovement

function HumanoidMovement.new(characterWrapper)
	local self = setmetatable({}, HumanoidMovement)
	self._character = characterWrapper

	local root = characterWrapper:GetRoot()
	self._rig = (root and not root.Anchored) and ForceRig.new(root) or nil

	return self
end

function HumanoidMovement:Move(direction: Vector3)
	local hum = self._character:GetHumanoid()
	if hum then hum:Move(direction, false) end
end

function HumanoidMovement:SetSpeed(speed)
	local hum = self._character:GetHumanoid()
	if hum then hum.WalkSpeed = speed end
end

function HumanoidMovement:SetJumpForce(jump)
	local hum = self._character:GetHumanoid()
	if hum then hum.JumpHeight = jump end
end

local StateToAir = {
	[Enum.HumanoidStateType.Jumping] = "Jumping",
	[Enum.HumanoidStateType.Freefall] = "Falling",
}

function HumanoidMovement:GetAirState(): string
	local hum = self._character:GetHumanoid()
	if not hum then return "Grounded" end

	local mapped = StateToAir[hum:GetState()]
	if mapped then
		return mapped
	end

	-- Humanoid:GetState() só distingue Jumping/Freefall explicitamente; outros
	-- estados (Running, Physics — usado quando uma Force externa toma conta —
	-- etc.) não dizem sozinhos se há contato com o chão. FloorMaterial é a
	-- forma barata e confiável do próprio Humanoid responder isso sem raycast.
	if hum.FloorMaterial == Enum.Material.Air then
		return "Falling"
	end
	return "Grounded"
end

function HumanoidMovement:SetFrozen(isFrozen)
	local hum = self._character:GetHumanoid()
	local root = self._character:GetRoot()
	if not hum or not root then return end

	if isFrozen then
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
		root.Anchored = true
		if self._rig then self._rig:Release() end
		if self._rig then self._rig:ReleaseFaceDirection() end
	else
		root.Anchored = false
	end
end

function HumanoidMovement:SetAmbientGravityScale(scale)
	if self._rig then self._rig:SetAmbientGravityScale(scale) end
end

function HumanoidMovement:ApplyForceFrame(targetVelocity: Vector3, maxAxesForce: Vector3)
	if not self._rig then return end
	self._rig:ApplyFrame(targetVelocity, maxAxesForce)

	local silenceNativeXZ = maxAxesForce.X > 0 or maxAxesForce.Z > 0
	if silenceNativeXZ then
		local hum = self._character:GetHumanoid()
		if hum then hum:Move(Vector3.zero, false) end
	end
end

function HumanoidMovement:ReleaseForces()
	if self._rig then self._rig:Release() end
end

function HumanoidMovement:FaceDirection(direction: Vector3, responsiveness: number?)
	if self._rig then self._rig:FaceDirection(direction, responsiveness) end
end

function HumanoidMovement:ReleaseFaceDirection()
	if self._rig then self._rig:ReleaseFaceDirection() end
end

function HumanoidMovement:Destroy()
	if self._rig then self._rig:Destroy() end
	self._rig = nil
	self._character = nil
end

-- ==================== NPC (NON-HUMANOID) IMPLEMENTATION ==================== --

--[[
	NPCMovement
]]
local NPCMovement = {}
NPCMovement.__index = NPCMovement

local NATIVE_WALK_FORCE = 2000

function NPCMovement.new(characterWrapper)
	local self = setmetatable({}, NPCMovement)
	self._character = characterWrapper

	local root = characterWrapper:GetRoot()
	self._rig = (root and not root.Anchored) and ForceRig.new(root) or nil
	self._currentSpeed = 0
	self._desiredWalk = Vector3.zero 

	return self
end

function NPCMovement:SetSpeed(speed)
	self._currentSpeed = speed
end

--[[
IMPORTANTE: isso NÃO escreve no ForceRig diretamente. Se escrevesse, e o
MovementController chamasse ApplyForceFrame/ReleaseForces logo em seguida no
MESMO frame (que é exatamente o que sempre acontece — Move() roda primeiro,
Forces depois), o que essa função escrevesse seria apagado sem efeito nenhum
antes mesmo do próximo passo de física rodar. Por isso só guardamos a
intenção aqui; quem efetivamente escreve no rig, compondo isso com o
resultado das Forces eixo a eixo, é ApplyForceFrame/ReleaseForces abaixo.
]]
function NPCMovement:Move(direction: Vector3)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	self._desiredWalk = flat * self._currentSpeed
end

function NPCMovement:GetAirState(): string
	local root = self._character:GetRoot()
	if not root then return "Grounded" end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }

	local rayLength = (root.Size.Y / 2) + 0.3
	local result = workspace:Raycast(root.Position, Vector3.new(0, -rayLength, 0), params)
	if result then
		return "Grounded"
	end

	-- Sem Humanoid não existe state machine nativa: aproxima por velocidade
	-- vertical. ATENÇÃO: isso raycasta a cada chamada — se algum dia virar
	-- hot-path chamado todo Heartbeat pra centenas de NPCs, cacheie o
	-- resultado por frame (hoje nada chama isso automaticamente, só quando
	-- uma skill pergunta).
	local verticalVelocity = root.AssemblyLinearVelocity.Y
	if verticalVelocity > 0.5 then
		return "Jumping"
	end
	return "Falling"
end

function NPCMovement:SetJumpForce(_jump) end -- NPCs sem Humanoid não pulam por padrão; sobrescreva se precisar

function NPCMovement:SetFrozen(isFrozen)
	local root = self._character:GetRoot()
	if root then root.Anchored = isFrozen end
	if isFrozen and self._rig then
		self._rig:Release()
		self._rig:ReleaseFaceDirection()
	end
end

function NPCMovement:SetAmbientGravityScale(scale)
	if self._rig then self._rig:SetAmbientGravityScale(scale) end
end

function NPCMovement:ApplyForceFrame(targetVelocity: Vector3, maxAxesForce: Vector3)
	if not self._rig then return end

	local finalVelocity, finalForce = targetVelocity, maxAxesForce

	if maxAxesForce.X == 0 then
		finalVelocity = Vector3.new(self._desiredWalk.X, finalVelocity.Y, finalVelocity.Z)
		finalForce = Vector3.new(NATIVE_WALK_FORCE, finalForce.Y, finalForce.Z)
	end
	if maxAxesForce.Z == 0 then
		finalVelocity = Vector3.new(finalVelocity.X, finalVelocity.Y, self._desiredWalk.Z)
		finalForce = Vector3.new(finalForce.X, finalForce.Y, NATIVE_WALK_FORCE)
	end

	self._rig:ApplyFrame(finalVelocity, finalForce)
end


function NPCMovement:ReleaseForces()
	self:ApplyForceFrame(Vector3.zero, Vector3.zero)
end

function NPCMovement:FaceDirection(direction: Vector3, responsiveness: number?)
	if self._rig then self._rig:FaceDirection(direction, responsiveness) end
end

function NPCMovement:ReleaseFaceDirection()
	if self._rig then self._rig:ReleaseFaceDirection() end
end

function NPCMovement:Destroy()
	if self._rig then self._rig:Destroy() end
	self._rig = nil
	self._character = nil
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
EntityWrapper.CreateMovement = function(characterWrapper, config)
	local wrapper
	if characterWrapper:GetHumanoid() then 
		wrapper = HumanoidMovement.new(characterWrapper)
	else
		wrapper = NPCMovement.new(characterWrapper)
	end

	if config then
		for k, v in pairs(config) do
			wrapper[k] = v
		end
	end
	return wrapper
end

-- ========== EXPORTS ========== --
EntityWrapper.ICharacter = ICharacter
EntityWrapper.IMovement = IMovement

return EntityWrapper

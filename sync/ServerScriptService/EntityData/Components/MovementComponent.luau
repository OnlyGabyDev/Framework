--[[
	MovementComponent
	=================
	Guarda a INTENÇÃO de movimento da entidade (direção de input, direção de
	mira/câmera) e a lista de Forces ativas (dashes, knockback, vento, etc).

	Esse componente NÃO aplica física nenhuma — quem faz isso é o
	MovementController (Modules/Physics/MovementController.luau), que roda
	1x por passo de física e resolve todas as Forces + o Humanoid nativo
	através do ForceRig (Modules/Physics/ForceRig.luau)

	--------------------------------------------------------------------------
	FORMA DE UMA Force (passada em AddForce)
	--------------------------------------------------------------------------
	{
		Type: string,                 -- rótulo LIVRE/identificador
		Priority: number?,            -- default 0. Empate de eixo = maior prioridade vence.
		Hard: boolean?,               -- default false. true = fixo nos eixos reivindicados.
		Axes: {X:boolean?, Y:boolean?, Z:boolean?}?,
		          -- eixos do MUNDO reivindicados. Default: Hard -> todos | Soft -> X,Z (Y livre pra gravidade/pulo)
		IgnoreGravity: boolean?,      -- atalho: força Axes.Y = true (zera a gravidade nesse eixo enquanto a Force durar)
		RequiresControl: boolean?,    -- default true. Force "mole" que precisa de controle é
		                              -- cancelada se a entidade não puder se mover (Root/Stun).
		                              -- Forces externas (knockback, vento) devem setar false.
		Duration: number,
		Speed: number | (elapsed: number, duration: number) -> number,
		Direction: Vector3 | (elapsed: number, duration: number, ctx) -> Vector3,
		          -- ctx = { Entity = <EntityCore>, MovementComponent = <self> }
		          -- Usar função aqui é o que permite dashes "estilo ult do Sion":
		          -- reavalie a direção lendo ctx.MovementComponent.LookDirection
		          -- (ver LookDirectionBroadcaster.client.luau) a cada frame.
		TurnRate: number?,            -- radianos/seg. Suaviza mudança de Direction ao invés de aplicar instantâneo.
		MaxForce: number?,            -- override de "quão inquebrável". Default: Settings.Hard/Soft_Force_Strength.
		FaceDirection: boolean?,      -- default = Hard. Gira o personagem pra encarar a direção.
		Responsiveness: number?,
		OnEnd: (() -> ())?,
	}

]]

local MovementComponent = {}
MovementComponent.__index = MovementComponent

local ServerScript = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local MovementController = require(ServerScript.Modules.Physics.MovementController)

function MovementComponent.new(entity, config)
	local self = setmetatable({}, MovementComponent)
	self.Entity = entity

	-- Intenção de Input
	self.Direction = Vector3.zero      -- direção normalizada de WASD
	self.LookDirection = Vector3.zero  -- direção "plana" da câmera do dono (ver SetLookDirection)
	self.IsFrozen = false              -- USE SÓ pra hard-stop (cutscene/loading).
	-- CC de combate = StateTable (Root/Stun/canMove), que já
	-- compõe corretamente com o sistema de Forces abaixo.

	-- Forças externas e Filtros
	self.ActiveForces = {}
	self.Filters = {} -- Filtros de interação/força
	self.ForceCounter = 0

	self.MovementWrapper = nil
	return self
end

function MovementComponent:SetSpeed(value)
	if self.MovementWrapper then
		self.MovementWrapper:SetSpeed(value)
	end
end

function MovementComponent:SetJumpForce(value)
	if self.MovementWrapper then
		self.MovementWrapper:SetJumpForce(value)
	end
end

function MovementComponent:GetSpeed()
	return self.Entity.GetStat(StateTable.Enum.Stats.Speed, 16)
end

function MovementComponent:GetJumpForce()
	return self.Entity.GetStat(StateTable.Enum.Stats.JumpForce, 50)
end

function MovementComponent:GetDirection()
	return self.Direction
end

function MovementComponent:SetMovement()
	if self.MovementWrapper then return false end 

	local EntityWrapper = require(ServerScript.EntityData.EntityWrapper)
	local wrapper = self.Entity.GetCharacterWrapper()

	-- Criamos o wrapper de movimentação.
	self.MovementWrapper = EntityWrapper.CreateMovement(wrapper)

	-- Regra 16: Dependência Opcional Explícita
	if not self.Entity:HasComponent(self.Entity.ComponentKey.Status) then
		warn("[MovementComponent] Entidade sem StatusComponent. Tags como canMove/canDisplace serão ignoradas.")
	end

	MovementController.Register(self)
	return true
end

--CleanUp
function MovementComponent:Destroy()
	MovementController.Unregister(self)
	if self.MovementWrapper and self.MovementWrapper.Destroy then
		self.MovementWrapper:Destroy()
	end
	self.MovementWrapper = nil
	self.Entity = nil
	table.clear(self.ActiveForces)
	table.clear(self.Filters)
end

-- ==========================================
-- FILTROS ORGÂNICOS
-- ==========================================
function MovementComponent:AddFilter(id, filterFunc)
	self.Filters[id] = filterFunc
end

function MovementComponent:RemoveFilter(id)
	self.Filters[id] = nil
end

-- ==========================================
-- APLICAÇÃO DE FORÇAS
-- ==========================================
function MovementComponent:AddForce(forceData)
	-- Aplica os filtros orgânicos (Rejeita se algum retornar false)
	for filterId, filterFunc in pairs(self.Filters) do
		if filterFunc(forceData) == false then
			return nil
		end
	end

	self.ForceCounter += 1
	local forceId = "F_" .. tostring(self.ForceCounter)
	self.ActiveForces[forceId] = {
		ID = forceId,
		Type = forceData.Type or "UnnamedForce",
		Data = forceData,
		ElapsedTime = 0,
		CurrentDirection = nil,
	}
	return forceId
end

function MovementComponent:RemoveForce(forceId)
	local entry = self.ActiveForces[forceId]
	if entry then
		if entry.Data.OnEnd then task.spawn(entry.Data.OnEnd) end
		self.ActiveForces[forceId] = nil
	end
end

function MovementComponent:ClearForces()
	for forceId, _ in pairs(self.ActiveForces) do
		self:RemoveForce(forceId)
	end
end

local ExposeAPI = {
	SetDirection = function(Component, dir) Component.Direction = dir end,
	GetDirection = function(Component) return Component.Direction end,
	SetLookDirection = function(Component, dir) Component.LookDirection = dir end,
	GetLookDirection = function(Component) return Component.LookDirection end,
	AddForce = function(Component, ...) return Component:AddForce(...) end,
	RemoveForce = function(Component, ...) return Component:RemoveForce(...) end,
	ClearForces = function(Component) return Component:ClearForces() end,
	SetFrozen = function(Component, f) Component.IsFrozen = f end,
	SetMovement = function(Component) return Component:SetMovement() end,
	GetMovementWrapper = function(Component) return Component.MovementWrapper end,
	SetSpeed = function(Component,...) return Component:SetSpeed(...) end,
	SetJumpForce = function(Component,...) return Component:SetJumpForce(...) end,
	AddFilter = function(Component, ...) return Component:AddFilter(...) end,
	RemoveFilter = function(Component, ...) return Component:RemoveFilter(...) end,
}

return { new = MovementComponent.new, ExposeAPI = ExposeAPI }

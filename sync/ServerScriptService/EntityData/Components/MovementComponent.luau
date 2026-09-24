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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(ReplicatedStorage.Utils)

function MovementComponent.new(entity, config)
	local self = setmetatable({}, MovementComponent)
	self.Entity = entity

	-- Intenção de Input
	self.Direction = Vector3.zero      -- input AO VIVO (zero = soltou tudo)
	self.LastDirection = Vector3.zero  -- último não-zero (fallback de dash/facing)
	self.LookDirection = Vector3.zero  -- direção "plana" da câmera do dono (ver SetLookDirection)
	self.AimDirection = Vector3.new(0, 0, -1) -- 3D cru, inclui pitch da câmera
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

-- Regra 16: dependência OPCIONAL de Attributes, declarada aqui num único ponto.
-- Sem Attributes, usa StatDefaults (sem chamar o stub, que dava warn por frame).
local function statOrDefault(self, stat)
	local entity = self.Entity
	local default = StateTable.Enum.StatDefaults[stat]
	if not entity:HasComponent(entity.ComponentKey.Attributes) then
		return default
	end
	return entity.GetStat(stat, default)
end

function MovementComponent:GetSpeed()
	return statOrDefault(self, StateTable.Enum.Stats.Speed)
end

function MovementComponent:GetJumpForce()
	return statOrDefault(self, StateTable.Enum.Stats.JumpForce)
end

function MovementComponent:GetDirection()
	return self.Direction
end

function MovementComponent:GetIntentDirection(): string
	local facing = self.LookDirection
	if facing.Magnitude < 0.1 then
		facing = self.LastDirection
	end
	if facing.Magnitude < 0.1 then
		facing = Vector3.new(0, 0, -1)
	end
	return Utils.classifyDirection(self.Direction, facing)
end

--[[
Sobrepõe o palpite do wrapper (Grounded/Jumping/Falling, só física bruta) com
"Floating" quando algo está DELIBERADAMENTE suspendendo o eixo Y — uma Force
Hard com IgnoreGravity/Axes.Y, ou GravityScale <= 0 via Attributes. Sem isso,
uma entidade flutuando parada (velocidade vertical ~0) seria confundida com
"acabou de começar a cair", que é exatamente o furo reportado.
Grounded sempre vence — flutuar não anula estar de pé em cima de algo.
]]
function MovementComponent:GetAirState(): string
	local wrapperState = self.MovementWrapper and self.MovementWrapper:GetAirState() or "Grounded"
	if wrapperState == "Grounded" then
		return "Grounded"
	end

	for _, forceEntry in pairs(self.ActiveForces) do
		local data = forceEntry.Data
		local axes = data.Axes
		local claimsY = data.IgnoreGravity or (axes and axes.Y)
		if data.Hard and claimsY then
			return "Floating"
		end
	end

	if self.Entity:HasComponent(self.Entity.ComponentKey.Attributes) then
		if self.Entity.GetStat(StateTable.Enum.Stats.GravityScale, 1) <= 0 then
			return "Floating"
		end
	end

	return wrapperState
end

function MovementComponent:SetMovement()
	if self.MovementWrapper then return false end 

	local EntityWrapper = require(ServerScript.EntityData.EntityWrapper)
	local wrapper = self.Entity.GetCharacterWrapper()

	-- Criamos o wrapper de movimentação.
	self.MovementWrapper = EntityWrapper.CreateMovement(wrapper, {DrivesInput = self.Entity.Player == nil})

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
	
	if forceData.Hard then
		local root = self.Entity.GetRoot and self.Entity.GetRoot()
		if root and self.Entity.Player == nil then
			pcall(function()
				root:SetNetworkOwner(nil)
			end)
		end
	end

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
	GetAirState = function(Component) return Component:GetAirState() end,
	SetDirection = function(Component, dir) 
		Component.Direction = dir 
		if dir.Magnitude > 0 then Component.LastDirection = dir end
	end,
	GetLastDirection = function(Component) return Component.LastDirection end,
	GetDirection = function(Component) return Component.Direction end,
	SetAimDirection = function(Component, dir)
		Component.AimDirection = dir
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 1e-3 then
			Component.LookDirection = flat.Unit
		end
		-- Se flat.Magnitude for ~0 (olhando reto pra cima/baixo), mantém o último
		-- LookDirection válido: classificação de combo não pode ficar com vetor zero.
	end,
	GetAimDirection = function(Component) return Component.AimDirection end,
	GetIntentDirection = function(Component) return Component:GetIntentDirection() end,
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

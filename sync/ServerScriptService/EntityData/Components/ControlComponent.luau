--[[
ControlComponent
================
Responsabilidade ÚNICA: identidade de QUEM manda numa entidade, e AUTORIDADE
de input (cortar a fonte, não a capacidade — canMove/canCast continuam
sendo trabalho do StatusComponent, de propósito, pra não duplicar autoridade).

Um controlador é um Player ({ Player = p }) ou uma IA ({ AI = true, Brain = fn? }).
Cada player tem uma PILHA de controle: possuir B estando em A empilha B; o
Release de B volta pra A e o de A volta pro corpo nativo. O que muda o
comportamento vem por opção, sem código extra no jogo:

	alvo.Possess({ Player = p })                                 -- pilha; pausa a IA do alvo
	alvo.Possess({ Player = p }, { Policy = Policy.Swap })       -- troca: solta os anteriores
	alvo.Possess({ Player = p }, { PauseAI = false })            -- a IA do alvo segue ligada
	alvo.Possess({ AI = true, Brain = fn })                      -- outra mente dirige o alvo
	alvo.Release()                                               -- devolve ao controlador nativo

Padrão por entidade no config do componente (DataManager.Create(..., { Control = {...} }))
e, na falta, DEFAULTS abaixo (dono único). Possuído destruído ou morto devolve
o player ao corpo anterior sozinho.

Regra 16 — dependências opcionais declaradas: Movement (direção e DrivesInput do
corpo) e AI (o AIComponent É o mecanismo do controlador IA: estruturalmente
inevitável, Regra 20).
]]

local ServerStorage = game:GetService("ServerStorage")
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local StateEnum = StateTable.Enum

local ControlComponent = {}
ControlComponent.__index = ControlComponent

export type Controller = {
	Player: Player?,
	AI: boolean?,
	Brain: any?,
	Suspended: boolean?, -- está na pilha de um player, mas fora do topo: ninguém dirige agora
}

export type PossessOptions = {
	Policy: string?,          -- Policy.Stack | Policy.Swap
	PauseAI: boolean?,        -- player assumindo pausa a IA do alvo (o Release devolve o estado)
	ReleaseOnDeath: boolean?, -- a morte do possuído devolve o controlador
}

local Policy = table.freeze({
	Stack = "Stack", -- Release volta pro corpo anterior da pilha
	Swap = "Swap",   -- Possess solta os anteriores; Release volta pro corpo nativo
})

local DEFAULTS = table.freeze({
	Policy = Policy.Stack,
	PauseAI = true,
	ReleaseOnDeath = true,
})

-- NÃO mova estes requires pro topo do arquivo — ver nota de require circular.
local function getAntiCheat()
	return require(game.ServerScriptService.Modules.GlobalAntiCheat)
end

local function getDataManager()
	return require(game.ServerScriptService.EntityData.DataManager)
end

local function getInputSessions()
	return require(game.ServerScriptService.Modules.InputSessions)
end

-- Pilha de controle por player: componentes possuídos, do mais antigo (base) ao atual
-- (topo). O corpo nativo (NativeID do AntiCheat) fica implícito embaixo de tudo.
local Stacks: { [Player]: { any } } = {}

local function topOf(player: Player)
	local stack = Stacks[player]
	return stack and stack[#stack]
end

--=============================================================================
--  CORPO (ownership, direção, IA)
--=============================================================================

-- Só mexe em ownership de peça que está no workspace, não ancorada e que aceita ownership.
-- A falta disso lançava erro no meio do Possess/Release (F04: raiz ancorada da torre; F02:
-- corpo antigo já fora do workspace no respawn) e deixava a rota presa.
local function setOwnerIfValid(part: BasePart?, owner: Player?): boolean
	if not part or part.Anchored or not part:IsDescendantOf(workspace) then return false end
	if not part:CanSetNetworkOwnership() then return false end
	return (pcall(part.SetNetworkOwner, part, owner))
end

-- Troca o dono de um corpo. toPlayer = nil: o servidor dirige (DrivesInput) e simula a
-- física; toPlayer = p: o cliente de p volta a dirigir e simular. A direção é zerada nos
-- dois sentidos: corpo que troca de dono nunca segue andando com o último input (F23).
local function handBody(core, toPlayer: Player?)
	if not core or not core.Active then return end
	if core:HasComponent(core.ComponentKey.Movement) then
		core.SetDirection(Vector3.zero)
		core.SetDrivesInput(toPlayer == nil)
	end
	if core:HasComponent(core.ComponentKey.Character) then
		setOwnerIfValid(core.GetRoot(), toPlayer)
	end
end

-- Guarda a mente e o estado do AIComponent UMA vez, antes do primeiro controlador
-- estrangeiro; a volta ao nativo restaura exatamente isso (F24 e a pausa da IA).
local function snapshotAI(entity, possession)
	if possession.AI == nil and entity:HasComponent(entity.ComponentKey.AI) then
		possession.AI = { Brain = entity.GetBrain(), Enabled = entity.IsAIEnabled() }
	end
end

local function restoreAI(entity, possession)
	if not entity:HasComponent(entity.ComponentKey.AI) then return end
	if possession.AddedAI then
		entity:RemoveComponent(entity.ComponentKey.AI)
	elseif possession.AI then
		entity.SetBrain(possession.AI.Brain)
		entity.SetEnabled(possession.AI.Enabled)
	end
end

--=============================================================================
--  ROTEAMENTO POR PLAYER
--=============================================================================

local function nativeCoreOf(player: Player)
	local id = getAntiCheat().GetNativeEntityId(player)
	return id and getDataManager().Get(id)
end

-- Manda o input do player pro topo da pilha, ou de volta pro corpo nativo. UMA mensagem pro
-- cliente com o estado completo (F22: antes o suspendNative=true vinha seguido de outra
-- mensagem com false, e o cliente religava o WASD nativo no meio da possessão).
local function route(player: Player)
	local AC = getAntiCheat()
	getInputSessions().CancelActiveGestures(player)
	local top = topOf(player)
	if top then
		AC.SetControlledEntity(player, top.Entity.ID, true)
	else
		handBody(nativeCoreOf(player), player)
		AC.SetControlledEntity(player, AC.GetNativeEntityId(player), false)
	end
end

-- Tira `component` da pilha do player. Se ele era o topo, o player volta pro anterior (que
-- retoma) ou pro corpo nativo. restore = devolve o componente ao controlador nativo dele.
local function popFromStack(component, player: Player, restore: boolean)
	local stack = Stacks[player]
	local index = stack and table.find(stack, component)
	if not index then return end
	local wasTop = index == #stack
	table.remove(stack, index)
	if #stack == 0 then Stacks[player] = nil end

	if restore then component:_RestoreNative() end
	if wasTop then
		local newTop = topOf(player)
		if newTop then newTop:_Resume(player) end
		route(player)
	end
end

-- Solta tudo que o player possui. keepNative = não devolve o input ao corpo nativo (Swap
-- vai possuir outro em seguida; um player saindo do jogo não recebe mais nada).
local function releasePlayer(player: Player, keepNative: boolean?): boolean
	local stack = Stacks[player]
	if not stack then return false end
	Stacks[player] = nil
	for i = #stack, 1, -1 do
		stack[i]:_RestoreNative()
	end
	if not keepNative then route(player) end
	return true
end

--=============================================================================
--  COMPONENTE
--=============================================================================

function ControlComponent.new(entity, config)
	local self = setmetatable({}, ControlComponent)
	self.Entity = entity
	self._native = entity.Player and { Player = entity.Player } or { AI = true }
	self.Controller = self._native
	self._config = config or {}
	self._possession = nil -- controle não-nativo em curso: { Player?, Opts, AI?, AddedAI? }
	self._locked = false
	self._lockedPlayer = nil
	self._links = {}
	return self
end

function ControlComponent:OnAdded()
	-- Possuído que morre devolve o controlador (F03), reagindo ao IN.OnDeath da própria
	-- entidade: o Control não conhece o Health (Regra 20)
	self._unsubscribeDeath = self.Entity:Listen({
		Role = StateEnum.Roles.IN,
		Breakpoint = StateEnum.Breakpoints.OnDeath,
		Priority = StateEnum.EnginePriority,
		Owner = self,
		Action = function()
			local possession = self._possession
			if possession and possession.Opts.ReleaseOnDeath then
				self:Release()
			end
		end,
	})
end

-- opts da chamada > config da entidade > DEFAULTS
function ControlComponent:_ResolveOptions(opts: PossessOptions?)
	local resolved = {}
	for key, default in DEFAULTS do
		local value = opts and opts[key]
		if value == nil then value = self._config[key] end
		if value == nil then value = default end
		resolved[key] = value
	end
	return resolved
end

function ControlComponent:_BeginPossession(opts, player: Player?)
	self._possession = self._possession or {}
	self._possession.Opts = opts
	self._possession.Player = player
	snapshotAI(self.Entity, self._possession)
end

-- Um controlador não-nativo assume o corpo: o servidor passa a dirigir, e o player nativo do
-- corpo (se houver) perde o input dele — senão o WASD dele corre em paralelo com quem tomou posse
function ControlComponent:_TakeBody(controller: Controller)
	if self._native.Player and controller.Player ~= self._native.Player then
		getAntiCheat().LockPlayerInput(self._native.Player)
	end
	handBody(self.Entity, nil)
end

-- O player que tinha este corpo (no topo ou suspenso) perde o controle dele. O registro da
-- IA original continua: um novo controlador assume em seguida.
function ControlComponent:_DetachPlayer()
	local possession = self._possession
	local owner = possession and possession.Player
	if not owner then return end
	possession.Player = nil
	popFromStack(self, owner, false)
end

function ControlComponent:_Suspend()
	self.Controller = { Suspended = true }
	handBody(self.Entity, nil)
end

function ControlComponent:_Resume(player: Player)
	self.Controller = { Player = player }
	handBody(self.Entity, nil)
end

-- Devolve o corpo ao controlador nativo (IA original, ou o player dono do corpo)
function ControlComponent:_RestoreNative()
	local possession = self._possession
	self._possession = nil
	self.Controller = self._native
	if not possession or not self.Entity then return end

	restoreAI(self.Entity, possession)
	handBody(self.Entity, self._native.Player)
	if self._native.Player then
		getAntiCheat().UnlockPlayerInput(self._native.Player)
	end
end

function ControlComponent:_PossessByPlayer(player: Player, opts): boolean
	-- O corpo nativo do próprio player: possuir = voltar pra ele
	if self._native.Player == player then
		releasePlayer(player)
		return true
	end
	if topOf(player) == self then return true end

	-- Quem tinha este corpo perde o controle (outro player recua na pilha dele; o mesmo
	-- player, com este corpo suspenso no meio da pilha, tira de lá e traz pro topo)
	self:_DetachPlayer()
	if opts.Policy == Policy.Swap then
		releasePlayer(player, true)
	end

	local previous = topOf(player)
	if previous then
		previous:_Suspend()
	else
		handBody(nativeCoreOf(player), nil) -- saindo do corpo nativo: o servidor assume (F23)
	end

	self:_BeginPossession(opts, player)
	if opts.PauseAI and self.Entity:HasComponent(self.Entity.ComponentKey.AI) then
		self.Entity.SetEnabled(false)
	end
	self:_TakeBody({ Player = player })
	self.Controller = { Player = player }

	local stack = Stacks[player] or {}
	Stacks[player] = stack
	table.insert(stack, self)
	route(player)
	return true
end

function ControlComponent:_PossessByAI(controller: Controller, opts): boolean
	local entity = self.Entity
	if not controller.Brain then
		-- { AI = true } sem Brain num corpo de IA nativa = devolver pra IA dele
		if self._native.AI then
			self:Release()
			return true
		end
		if not entity:HasComponent(entity.ComponentKey.AI) then
			warn("[ControlComponent] Possess({ AI = true }) sem Brain numa entidade sem AIComponent:", tostring(entity.ID))
			return false
		end
	end

	self:_DetachPlayer()
	self:_BeginPossession(opts, nil)
	if entity:HasComponent(entity.ComponentKey.AI) then
		if controller.Brain then entity.SetBrain(controller.Brain) end
		entity.SetEnabled(true)
	else
		-- Corpo sem IA: o AIComponent existe só enquanto durar esta posse (Regra 5)
		entity:AddComponent(entity.ComponentKey.AI, { Brain = controller.Brain }, true)
		self._possession.AddedAI = true
	end
	self:_TakeBody(controller)
	self.Controller = controller
	return true
end

--[[
Transfere o controle desta entidade pro `controller` informado.
@param controller - { Player = p } ou { AI = true, Brain = fn? }
@param opts - PossessOptions (opcional; ver DEFAULTS)
@return assumiu o controle BOOLEAN
]]
function ControlComponent:Possess(controller: Controller, opts: PossessOptions?): boolean
	if not self.Entity or not self.Entity.Active then return false end
	local resolved = self:_ResolveOptions(opts)
	if controller.Player then
		return self:_PossessByPlayer(controller.Player, resolved)
	elseif controller.AI then
		return self:_PossessByAI(controller, resolved)
	end
	warn("[ControlComponent] Possess sem controlador válido: use { Player = p } ou { AI = true, Brain = fn? }")
	return false
end

--[[
Devolve esta entidade ao controlador nativo. Se um player a possuía, ele volta pro corpo
anterior da pilha (ou pro nativo).
@return havia controle não-nativo pra soltar BOOLEAN
]]
function ControlComponent:Release(): boolean
	local possession = self._possession
	if not possession then return false end
	if possession.Player then
		popFromStack(self, possession.Player, true)
	else
		self:_RestoreNative()
	end
	return true
end

--[[
Corta o controlador ATUAL sem reatribuir a ninguém (cutscene, QTE, etc). Se
o controlador for Player, corta na fonte via AntiCheat. Se for AI, desliga o
Brain. O Unlock devolve exatamente o que ESTE Lock cortou, mesmo que o player já
tenha trocado de corpo no meio (antes o Unlock perguntava o controlador atual).
]]
function ControlComponent:Lock()
	if self._locked then return end
	self._locked = true

	local player = self.Controller.Player
	if player and getAntiCheat().LockPlayerInput(player) then
		self._lockedPlayer = player
	end
	if self.Controller.AI and self.Entity:HasComponent(self.Entity.ComponentKey.AI) then
		self.Entity.SetEnabled(false)
	end
end

function ControlComponent:Unlock()
	if not self._locked then return end
	self._locked = false

	if self._lockedPlayer then
		getAntiCheat().UnlockPlayerInput(self._lockedPlayer)
		self._lockedPlayer = nil
	end
	if self.Controller.AI and self.Entity:HasComponent(self.Entity.ComponentKey.AI) then
		self.Entity.SetEnabled(true)
	end
end

function ControlComponent:GetController(): Controller
	return self.Controller
end

function ControlComponent:IsControlledBy(player: Player): boolean
	return self.Controller.Player == player
end

function ControlComponent:IsAIControlled(): boolean
	return self.Controller.AI == true
end

--[[
Linka outra entidade a esta: MirrorMovement/MirrorLook fazem o input de
movimento/mira que ESTA entidade recebe também ser aplicado na `otherEntity`,
sem duplicar handler nenhum — é um fan-out opcional em cima do pipeline já
existente. Precisa que otherEntity já tenha ControlComponent.
]]
function ControlComponent:LinkTo(otherEntity: any, opts: {MirrorMovement: boolean?, MirrorLook: boolean?}?)
	local otherControl = otherEntity:GetComponent(otherEntity.ComponentKey.Control)
	if not otherControl then
		warn("[ControlComponent] LinkTo: entidade alvo não tem ControlComponent")
		return
	end

	opts = opts or {}
	self._links = self._links or {}
	self._links[otherControl] = {
		MirrorMovement = opts.MirrorMovement or false,
		MirrorLook = opts.MirrorLook or false,
		TargetEntity = otherEntity,
	}
end

function ControlComponent:Unlink(otherEntity: any)
	local otherControl = otherEntity:GetComponent(otherEntity.ComponentKey.Control)
	if self._links and otherControl then
		self._links[otherControl] = nil
	end
end

--[[ @param filterKey "MirrorMovement" | "MirrorLook" | nil (nil = todos os links) ]]
function ControlComponent:GetLinkedEntities(filterKey: string?): {any}
	if not self._links then return {} end
	local result = {}
	for _, linkData in pairs(self._links) do
		if not filterKey or linkData[filterKey] then
			table.insert(result, linkData.TargetEntity)
		end
	end
	return result
end

function ControlComponent:Destroy()
	if self._unsubscribeDeath then self._unsubscribeDeath() end
	-- Possuído destruído devolve o player ao corpo anterior/nativo (F03); um Lock dele não
	-- pode sobreviver à entidade e prender o player
	self:Release()
	self:Unlock()
	self._links = nil
	self.Entity = nil
end

local ExposeAPI = {
	Possess = function(component, ...) return component:Possess(...) end,
	Release = function(component) return component:Release() end,
	Lock = function(component) return component:Lock() end,
	Unlock = function(component) return component:Unlock() end,
	GetController = function(component) return component:GetController() end,
	IsControlledBy = function(component, ...) return component:IsControlledBy(...) end,
	IsAIControlled = function(component) return component:IsAIControlled() end,
	LinkTo = function(component, ...) return component:LinkTo(...) end,
	Unlink = function(component, ...) return component:Unlink(...) end,
	GetLinkedEntities = function(component, ...) return component:GetLinkedEntities(...) end,
}

return {
	new = ControlComponent.new,
	ExposeAPI = ExposeAPI,
	Policy = Policy,
	-- Topo da pilha de controle do player (o componente que ele dirige agora), ou nil
	GetPossessionOf = function(player: Player)
		return topOf(player)
	end,
	-- Solta tudo que o player possui e devolve o input ao corpo nativo (respawn). leaving =
	-- o player está saindo: só devolve os corpos, sem rotear nada pra ele.
	ReleasePlayer = function(player: Player, leaving: boolean?): boolean
		return releasePlayer(player, leaving)
	end,
}

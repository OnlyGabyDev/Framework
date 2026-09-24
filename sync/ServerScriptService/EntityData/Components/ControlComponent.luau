--[[
ControlComponent
================
Responsabilidade ÚNICA: identidade de QUEM manda numa entidade, e AUTORIDADE
de input (cortar a fonte, não a capacidade — canMove/canCast continuam
sendo trabalho do StatusComponent, de propósito, pra não duplicar autoridade).

Suporta: Player possui NPC, NPC/IA possui Player, Player troca em tempo real
entre 2 corpos seus (só chame Possess na entidade nova, a antiga fica sem
receber input sozinha).
]]

local ControlComponent = {}
ControlComponent.__index = ControlComponent

export type Controller = {
	Player: Player?,
	AI: boolean?,
	Brain: any?,
}

-- NÃO mova este require pro topo do arquivo — ver nota de require circular.
local function getAntiCheat()
	return require(game.ServerScriptService.Modules.GlobalAntiCheat)
end

-- Índice reverso GLOBAL: qual componente este Player está possuindo agora,
-- fora do próprio corpo nativo. Existe só pra cleanup em respawn/disconnect
-- sem iterar toda entidade viva.
local ActivePossessions: { [Player]: any } = {}

function ControlComponent.new(entity, config)
	local self = setmetatable({}, ControlComponent)
	self.Entity = entity
	self._native = entity.Player and { Player = entity.Player } or { AI = true }
	self.Controller = self._native
	self._priorControllerEntityId = nil
	self._locked = false
	self._links = {}
	return self
end

--[[
Transfere o controle desta entidade pro `controller` informado. Se esta
entidade tem um player NATIVO e quem está tomando conta NÃO é esse player
nativo, o nativo é cortado da própria entidade automaticamente (senão o WASD
dele corre em paralelo com quem tomou posse — condição de corrida real).
]]
function ControlComponent:Possess(controller: Controller)
	if self._native.Player and controller.Player ~= self._native.Player then
		getAntiCheat().LockPlayerInput(self._native.Player)
	end

	if controller.Player then
		-- Lembra o que esse player controlava ANTES, pra Release() devolver
		-- certo mesmo em possessão encadeada (A possui B, depois A possui C
		-- — Release de C devolve A pra B, não direto pro nativo de A).
		self._priorControllerEntityId = getAntiCheat().GetControlledEntityId(controller.Player)

		if self.Controller.Player and self.Controller.Player ~= controller.Player then
			ActivePossessions[self.Controller.Player] = nil
		end

		getAntiCheat().SetControlledEntity(controller.Player, self.Entity.ID)
		ActivePossessions[controller.Player] = self
	end

	self.Controller = controller
end

function ControlComponent:Release()
	if self.Controller.Player then
		ActivePossessions[self.Controller.Player] = nil
		if self._priorControllerEntityId then
			getAntiCheat().SetControlledEntity(self.Controller.Player, self._priorControllerEntityId)
			self._priorControllerEntityId = nil
		end
	end

	if self._native.Player then
		getAntiCheat().UnlockPlayerInput(self._native.Player)
	end

	self.Controller = self._native
end

--[[
Corta o controlador ATUAL sem reatribuir a ninguém (cutscene, QTE, etc). Se
o controlador for Player, corta na fonte via AntiCheat. Se for AI, desliga o
Brain (SetEnabled é stub-seguro via ComponentStubs mesmo antes do AIComponent
existir — chama warn e não faz nada, não quebra).
]]
function ControlComponent:Lock()
	if self._locked then return end
	self._locked = true

	if self.Controller.Player then
		getAntiCheat().LockPlayerInput(self.Controller.Player)
	end
	if self.Controller.AI and self.Entity:HasComponent(self.Entity.ComponentKey.AI) then
		self.Entity.SetEnabled(false)
	end
end

function ControlComponent:Unlock()
	if not self._locked then return end
	self._locked = false

	if self.Controller.Player then
		getAntiCheat().UnlockPlayerInput(self.Controller.Player)
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
	if self.Controller.Player then
		ActivePossessions[self.Controller.Player] = nil
	end
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
	GetPossessionOf = function(player: Player)
		return ActivePossessions[player]
	end,
}

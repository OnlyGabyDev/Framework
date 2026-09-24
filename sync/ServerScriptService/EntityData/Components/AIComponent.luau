--[[
AIComponent
===========
Base MÍNIMA: um "Brain" (function(entity, dt)) chamado a cada Heartbeat, cuja
responsabilidade é produzir InputEvents exatamente como um player faria:

	SkillHandler.HandleIntent(entity.ID, Intents.NewEvent(Intents.Id.Primary, Intents.Kind.Activate))
	SkillHandler.HandleMovementInput(entity.ID, direction)
	SkillHandler.HandleLookInput(entity.ID, lookDirection)

Mesmo pipeline que o InputValidator usa pro player — zero hardcode de "isso é
NPC" no framework de combate.
]]

local AIScheduler = require(game.ServerScriptService.Modules.AI.AIScheduler)

local AIComponent = {}
AIComponent.__index = AIComponent

function AIComponent.new(entity, config)
	local self = setmetatable({}, AIComponent)
	self.Entity = entity
	self.Brain = config.Brain or nil
	self.Enabled = config.Enabled ~= false
	return self
end

function AIComponent:SetBrain(brainFn: ((any, number) -> ())?)
	self.Brain = brainFn
end

function AIComponent:SetEnabled(enabled: boolean)
	self.Enabled = enabled
end

function AIComponent:OnAdded()
	AIScheduler.Register(self)
end

function AIComponent:Destroy()
	AIScheduler.Unregister(self)
	self.Entity = nil
	self.Brain = nil
end

local ExposeAPI = {
	SetBrain = function(component, ...) return component:SetBrain(...) end,
	SetEnabled = function(component, ...) return component:SetEnabled(...) end,
}

return {
	new = AIComponent.new,
	ExposeAPI = ExposeAPI,
}

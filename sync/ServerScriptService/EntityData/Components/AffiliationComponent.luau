--[[
AffiliationComponent
====================
De que lado a entidade está (time, facção). Guarda só o DADO: quem pode afetar quem é regra
declarada no StateTable (Relation, CanAffect, Enum.AffectsDefaults), e quem resolve alvo
(HitboxWrapper, AreaEffect com filtro) pergunta lá. Entidade sem este componente é Neutral.

	DataManager.Create(model, { ..., "Affiliation" }, { Affiliation = { Team = "Red" } })

O nome do time é dado do jogo (o jogo declara os seus); o motor só compara igualdade.
]]

local AffiliationComponent = {}
AffiliationComponent.__index = AffiliationComponent

function AffiliationComponent.new(entity, config)
	local self = setmetatable({}, AffiliationComponent)
	self.Entity = entity
	self.Team = config.Team
	return self
end

function AffiliationComponent:GetTeam(): any
	return self.Team
end

function AffiliationComponent:SetTeam(team: any)
	self.Team = team
end

function AffiliationComponent:Destroy()
	self.Entity = nil
end

local ExposeAPI = {
	GetTeam = function(component) return component:GetTeam() end,
	SetTeam = function(component, ...) return component:SetTeam(...) end,
}

return {
	new = AffiliationComponent.new,
	ExposeAPI = ExposeAPI,
}

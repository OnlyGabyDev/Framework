local TraitQuery = require(script.Parent.TraitQuery)

local TriggerSet = {}
TriggerSet.__index = TriggerSet

function TriggerSet.new()
	local self = setmetatable({}, TriggerSet)
	self.Subscriptions = {}
	self._seq = 0 -- desempate determinístico de prioridade (ordem de inscrição)
	return self
end

-- Dono único da checagem de expiração de TTD (Regra 1) — usado tanto em Emit
-- quanto em Fork. Antes só Emit sabia disso, e Fork podia "ressuscitar" um
-- sub cujo TTD já tinha estourado, herdando um countdown novo do zero.
local function isExpired(sub: any): boolean
	return sub._expirationTime ~= nil and os.clock() >= sub._expirationTime
end

function TriggerSet:Subscribe(sub: any)
	if not self.Subscriptions[sub.Role] then
		self.Subscriptions[sub.Role] = {}
	end
	if not self.Subscriptions[sub.Role][sub.Breakpoint] then
		self.Subscriptions[sub.Role][sub.Breakpoint] = {}
	end

	if not sub._sharedState then
		sub._sharedState = { Count = 0 }
	end
	
	-- TTD (Time To Die): expiração por tempo. Avaliação preguiçosa em Emit,
	-- avaliação ATIVA em Fork (ver TriggerSet:Fork) — sem a segunda, uma
	-- reação já morta podia ser copiada pro filho com clock novo.
	if sub.TTD then
		sub._expirationTime = os.clock() + sub.TTD
	end

	sub._removed = nil
	self._seq += 1
	sub._seq = self._seq

	local list = self.Subscriptions[sub.Role][sub.Breakpoint]
	table.insert(list, sub)

	table.sort(list, function(a, b)
		local pa, pb = a.Priority or 0, b.Priority or 0
		if pa ~= pb then
			return pa > pb
		end
		return a._seq < b._seq
	end)

	return function()
		self:Unsubscribe(sub)
	end
end

function TriggerSet:Unsubscribe(subToRemove: any)
	local byRole = self.Subscriptions[subToRemove.Role]
	local list = byRole and byRole[subToRemove.Breakpoint]
	if list then
		local index = table.find(list, subToRemove)
		if index then
			table.remove(list, index)
		end
	end
	subToRemove._removed = true
end

function TriggerSet:UnsubscribeByOwner(owner: any)
	for _, breakpoints in pairs(self.Subscriptions) do
		for _, list in pairs(breakpoints) do
			for i = #list, 1, -1 do
				if list[i].Owner == owner then
					list[i]._removed = true
					table.remove(list, i)
				end
			end
		end
	end
end

function TriggerSet:Emit(role: string, breakpoint: string, context: any, ...)
	local byRole = self.Subscriptions[role]
	local list = byRole and byRole[breakpoint]
	if not list or #list == 0 then
		return
	end

	for _, sub in table.clone(list) do
		if sub._removed then continue end

		-- 0. TTD (Time To Die) - Avaliação Preguiçosa
		if isExpired(sub) then
			self:Unsubscribe(sub)
			continue
		end

		local matched = TraitQuery.Match(sub.Query, context.traits)
		if not matched then continue end

		local limit = sub.Limit
		if limit and sub._sharedState.Count >= limit.Max then
			if limit.OnExhaust == "Remove" then
				self:Unsubscribe(sub)
			end
			continue
		end

		sub._sharedState.Count += 1

		if type(sub.Action) == "function" then
			local ok, err = xpcall(sub.Action, debug.traceback, context, ...)
			if not ok then
				warn(`[TriggerSet] erro em {role}.{breakpoint}: {err}`)
			end
		end

		if limit and limit.OnExhaust == "Remove" and sub._sharedState.Count >= limit.Max then
			self:Unsubscribe(sub)
		end
	end
end

-- Clona assinaturas que devem ser herdadas
function TriggerSet:Fork()
	local newSet = TriggerSet.new()
	for role, breakpoints in pairs(self.Subscriptions) do
		for bp, list in pairs(breakpoints) do
			-- Clona ANTES de iterar: Unsubscribe (chamado abaixo pra podar
			-- subs expirados encontrados aqui) muda `list` por remoção de
			-- índice — iterar com ipairs sobre a tabela viva ao mesmo tempo
			-- pularia elementos. Mesmo idioma que Emit já usa.
			for _, sub in ipairs(table.clone(list)) do
				if sub._removed then continue end

				-- FIX: sem isso, um sub cujo TTD já estourou (mas que ainda
				-- não foi podado por falta de Emit nesse breakpoint
				-- específico) era copiado pro filho com um countdown NOVO,
				-- do zero — "ressuscitando" uma reação que já devia estar
				-- morta. Aproveita a passagem pra podar do PAI também, de graça.
				if isExpired(sub) then
					self:Unsubscribe(sub)
					continue
				end

				if sub.Inherit and sub.Inherit.Generations > 0 then
					local inheritedTTD = sub.TTD
					if sub.TTD and sub.TTDInheritRemaining and sub._expirationTime then
						-- Opt-in: filho herda o TEMPO RESTANTE, não a duração
						-- cheia de novo. Default é duração cheia (cada
						-- geração da árvore tem sua própria janela plena) —
						-- marque TTDInheritRemaining=true no sub original se
						-- quiser um TTD que só encolhe ao longo da linhagem.
						inheritedTTD = math.max(0, sub._expirationTime - os.clock())
					end

					local inheritedSub = {
						Role = sub.Role,
						Breakpoint = sub.Breakpoint,
						Query = sub.Query,
						Action = sub.Action,
						Priority = sub.Priority,
						Owner = sub.Owner,
						Limit = sub.Limit,
						Inherit = { Generations = sub.Inherit.Generations - 1 },
						TTD = inheritedTTD,
						TTDInheritRemaining = sub.TTDInheritRemaining,
					}

					if inheritedSub.Limit and inheritedSub.Limit.Scope == "Branch" then
						inheritedSub._sharedState = { Count = sub._sharedState.Count }
					elseif inheritedSub.Limit and inheritedSub.Limit.Scope == "Tree" then
						inheritedSub._sharedState = sub._sharedState
					else
						inheritedSub._sharedState = { Count = 0 }
					end

					newSet:Subscribe(inheritedSub)
				end
			end
		end
	end
	return newSet
end

return TriggerSet

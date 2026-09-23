--!strict
local TraitQuery = require(script.Parent.TraitQuery)

local TriggerSet = {}
TriggerSet.__index = TriggerSet

function TriggerSet.new()
	local self = setmetatable({}, TriggerSet)
	self.Subscriptions = {}
	self._seq = 0 -- desempate determinístico de prioridade (ordem de inscrição)
	return self
end

function TriggerSet:Subscribe(sub: any)
	if not self.Subscriptions[sub.Role] then
		self.Subscriptions[sub.Role] = {}
	end
	if not self.Subscriptions[sub.Role][sub.Breakpoint] then
		self.Subscriptions[sub.Role][sub.Breakpoint] = {}
	end

	-- Estado de contagem compartilhado por referência (escopo "Tree" depende disso)
	if not sub._sharedState then
		sub._sharedState = { Count = 0 }
	end

	sub._removed = nil
	self._seq += 1
	sub._seq = self._seq

	local list = self.Subscriptions[sub.Role][sub.Breakpoint]
	table.insert(list, sub)

	table.sort(list, function(a, b)
		local pa, pb = a.Priority or 0, b.Priority or 0
		if pa ~= pb then
			return pa > pb -- maior prioridade roda primeiro
		end
		return a._seq < b._seq -- empate: ordem de inscrição
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
	-- Marca pra que um Emit em andamento (que trabalha num snapshot) pule esta inscrição
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

	-- Snapshot: Actions podem chamar Listen/Unsubscribe/UnsubscribeByOwner sem corromper esta iteração
	for _, sub in table.clone(list) do
		if sub._removed then continue end

		-- 1. Traits
		if not TraitQuery.Match(sub.Query, context.traits) then continue end

		-- 2. Limites
		local limit = sub.Limit
		if limit and sub._sharedState.Count >= limit.Max then
			if limit.OnExhaust == "Remove" then
				self:Unsubscribe(sub)
			end
			continue
		end

		sub._sharedState.Count += 1

		-- 3. Ação (síncrona: no pipeline ela pode mutar o context). Erro de um listener NÃO derruba o Emit.
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
			for _, sub in ipairs(list) do
				if sub.Inherit and sub.Inherit.Generations > 0 then
					local inheritedSub = {
						Role = sub.Role,
						Breakpoint = sub.Breakpoint,
						Query = sub.Query,
						Action = sub.Action,
						Priority = sub.Priority,
						Owner = sub.Owner,
						Limit = sub.Limit,
						Inherit = { Generations = sub.Inherit.Generations - 1 }
					}

					if inheritedSub.Limit and inheritedSub.Limit.Scope == "Branch" then
						-- Novo ramo tem sua própria contagem clone
						inheritedSub._sharedState = { Count = sub._sharedState.Count }
					elseif inheritedSub.Limit and inheritedSub.Limit.Scope == "Tree" then
						-- Tree compartilha a mesma referência de _sharedState
						inheritedSub._sharedState = sub._sharedState
					else
						-- Default/Holder: não compartilha (zerar é o seguro)
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

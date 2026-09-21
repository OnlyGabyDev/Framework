--!strict
local TraitQuery = require(script.Parent.TraitQuery)

local TriggerSet = {}
TriggerSet.__index = TriggerSet

function TriggerSet.new()
	local self = setmetatable({}, TriggerSet)
	self.Subscriptions = {}
	return self
end

function TriggerSet:Subscribe(sub: any)
	if not self.Subscriptions[sub.Role] then
		self.Subscriptions[sub.Role] = {}
	end
	if not self.Subscriptions[sub.Role][sub.Breakpoint] then
		self.Subscriptions[sub.Role][sub.Breakpoint] = {}
	end
	
	-- Initialize tracking (use shared state so "Tree" scope works by reference)
	if not sub._sharedState then
		sub._sharedState = { Count = 0 }
	end
	
	table.insert(self.Subscriptions[sub.Role][sub.Breakpoint], sub)
	
	-- Sort by Priority (higher runs first)
	table.sort(self.Subscriptions[sub.Role][sub.Breakpoint], function(a, b)
		return (a.Priority or 0) > (b.Priority or 0)
	end)
	
	return function()
		self:Unsubscribe(sub)
	end
end

function TriggerSet:Unsubscribe(subToRemove: any)
	if not self.Subscriptions[subToRemove.Role] or not self.Subscriptions[subToRemove.Role][subToRemove.Breakpoint] then return end
	
	local list = self.Subscriptions[subToRemove.Role][subToRemove.Breakpoint]
	for i, sub in ipairs(list) do
		if sub == subToRemove or sub.ID == subToRemove.ID then
			table.remove(list, i)
			break
		end
	end
end

function TriggerSet:UnsubscribeByOwner(owner: any)
	for role, breakpoints in pairs(self.Subscriptions) do
		for bp, list in pairs(breakpoints) do
			for i = #list, 1, -1 do
				if list[i].Owner == owner then
					table.remove(list, i)
				end
			end
		end
	end
end

function TriggerSet:Emit(role: string, breakpoint: string, context: any, ...)
	if not self.Subscriptions[role] or not self.Subscriptions[role][breakpoint] then
		return
	end
	
	local list = self.Subscriptions[role][breakpoint]
	
	for i = #list, 1, -1 do
		local sub = list[i]
		
		-- 1. Check Traits
		if TraitQuery.Match(sub.Query, context.traits) then
			
			-- 2. Check Limits
			local canRun = true
			if sub.Limit then
				if sub._sharedState.Count >= sub.Limit.Max then
					canRun = false
					if sub.Limit.OnExhaust == "Remove" then
						table.remove(list, i)
					end
				end
			end
			
			if canRun then
				sub._sharedState.Count += 1
				
				-- Pipeline calls modifying context (or Observer calls via task.spawn)
				if type(sub.Action) == "function" then
					-- Para Pipeline síncrono, a action deve mutar o context ou aplicar lógicas
					sub.Action(context, ...)
				end
				
				if sub.Limit and sub._sharedState.Count >= sub.Limit.Max and sub.Limit.OnExhaust == "Remove" then
					table.remove(list, i)
				end
			end
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
						-- Default/Holder: não compartilha ou zera (regras de herança podem variar, zerar é o seguro)
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

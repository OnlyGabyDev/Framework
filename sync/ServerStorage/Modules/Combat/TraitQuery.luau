--!strict
local TraitQuery = {}

--[[
	Avalia se uma lista de traits satisfaz as condições da query.
	A query usa Flat Composition de tags.
]]
function TraitQuery.Match(query: any, traits: {string}?): boolean
	local activeTraits = traits or {}
	
	if not query then return true end
	
	-- None: não pode ter nenhuma destas
	if query.None then
		for _, trait in ipairs(query.None) do
			if table.find(activeTraits, trait) then
				return false
			end
		end
	end
	
	-- All: TEM que ter TODAS estas
	if query.All then
		for _, requiredTrait in ipairs(query.All) do
			if not table.find(activeTraits, requiredTrait) then
				return false
			end
		end
	end
	
	-- Any: tem que ter PELO MENOS UMA destas
	if query.Any and #query.Any > 0 then
		local foundAny = false
		for _, allowedTrait in ipairs(query.Any) do
			if table.find(activeTraits, allowedTrait) then
				foundAny = true
				break
			end
		end
		if not foundAny then
			return false
		end
	end
	
	return true
end

return TraitQuery

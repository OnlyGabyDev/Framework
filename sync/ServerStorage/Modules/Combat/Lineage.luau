--!strict
local Lineage = {}

-- Cria um novo nó na árvore de histórico
function Lineage.Fork(parent: any?, origin: any, cause: string): any
	local newNode = {
		Parent = parent,
		Depth = parent and (parent.Depth + 1) or 1,
		Origin = origin,
		Cause = cause
	}
	
	newNode.Root = parent and parent.Root or newNode
	
	return newNode
end

-- Retorna a array sequencial deste histórico (Root -> ... -> Atual)
function Lineage.GetHistoryArray(lineageNode: any): {string}
	local history = {}
	local current = lineageNode
	while current do
		table.insert(history, 1, current.Cause)
		current = current.Parent
	end
	return history
end

return Lineage

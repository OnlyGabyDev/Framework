--!strict
local Lineage = {}

--[[
Cria um novo nó na árvore de histórico.
Origin SEMPRE propaga a partir da raiz (quem começou a cadeia), nunca do elo
imediato — assim um dano causado por um DoT aplicado por uma skill ainda
atribui corretamente ao personagem que lançou a skill original.
]]
function Lineage.Fork(parent: any?, origin: any, cause: string?): any
	local newNode = {
		Parent = parent,
		Depth = parent and (parent.Depth + 1) or 1,
		Origin = (parent and parent.Origin) or origin,
		Cause = cause or "Unknown",
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

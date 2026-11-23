--[[
	ComponentUtils: utilitários pequenos usados pelo EntityCore (validação e require num lugar só).
]]

local ComponentUtils = {}
local Log = require(game:GetService("ReplicatedStorage").Logger).Channel("EntityCore")

--[[
require protegido que loga o ERRO REAL: um componente com erro de sintaxe aparece no output na
hora com a razão, em vez de virar um HasComponent(nome) = false silencioso.
]]
function ComponentUtils.SafeRequire(moduleScript: ModuleScript)
	local success, result = pcall(require, moduleScript)
	if not success then
		warn(string.format("[SafeRequire] Falha ao carregar %s: %s", moduleScript:GetFullName(), tostring(result)))
	end
	return success, result
end

--[[
Gera uma ExposeAPI validando que cada método citado EXISTE de verdade na classe.
Uso opcional dentro de um componente:
	local Expose = require(...).Expose
	return { new = X.new, ExposeAPI = Expose(X, {"Foo", "Bar"}) }
Um nome errado vira erro de `require` na hora, não um `nil` descoberto em produção.
]]
function ComponentUtils.Expose(class: {[string]: any}, names: {string})
	local api = {}
	for _, methodName in names do
		assert(class[methodName] ~= nil, string.format("[ComponentUtils.Expose] método inexistente: %s", methodName))
		api[methodName] = function(component, ...)
			return class[methodName](component, ...)
		end
	end
	return api
end

--[[
Confere se as dependências declaradas em `Requires` (nomes de ComponentKey) estão presentes na
entidade. Só WARN: não bloqueia a criação, para não travar o jogo por um erro de setup.
]]
function ComponentUtils.CheckRequires(entity: any, componentName: string, requires: {string})
	for _, depName in requires do
		if not entity:HasComponent(depName) then
			warn(string.format(
				"[EntityCore] Componente '%s' declara Requires={'%s'}, mas a entidade '%s' não o possui.",
				componentName, depName, tostring(entity.ID)
			))
		end
	end
end

--[[
Popula a tabela COMPARTILHADA de stubs (uma função de warn por método exposto por qualquer
componente registrado). Chamado uma única vez, depois que todo componente já foi auto-registrado:
nenhuma entidade paga por criar closures ao nascer.
]]
function ComponentUtils.BuildStubs(componentRegistry: {[string]: any}, targetStubs: {[string]: any})
	for compName, compData in pairs(componentRegistry) do
		if compData.ExposeAPI then
			for funcName in pairs(compData.ExposeAPI) do
				if targetStubs[funcName] == nil then
					targetStubs[funcName] = function(...)
						-- 1ª chamada por componente+função em Warn; as seguintes só em Debug (um loop não inunda o
						-- output)
						Log.WarnOnce(compName .. "." .. funcName,
							"Componente ausente:", compName, "| Func:", funcName,
							"(as próximas chamadas iguais só aparecem em Debug)")
					end
				end
			end
		end
	end
end

return ComponentUtils

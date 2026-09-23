--[[
	ComponentUtils — utilitários pequenos usados pelo EntityCore.
	Tirar essa lógica de dentro do EntityCore (Regra 1: nada de repetir o mesmo
	padrão de validação/require em 3 lugares diferentes).
]]

local ComponentUtils = {}

--[[
require protegido que loga o ERRO REAL, não só "deu ruim". No lugar de um
pcall(require, ...) cru: um componente com erro de sintaxe aparece no output
NA HORA com a razão, em vez de virar um HasComponent(nome) = false silencioso
descoberto sprints depois (Regra 16).
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
Confere se as dependências declaradas em `Requires` (nomes de ComponentKey) estão
presentes na entidade. Só WARN — não bloqueia a criação, pra não travar o jogo
por um erro de setup. O objetivo é encurtar a distância entre "esqueci de
adicionar um componente" e "percebi que esqueci" (Regra 16).
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
Popula a tabela COMPARTILHADA de stubs (uma função de warn por método exposto por
qualquer componente registrado). Chamado uma única vez, depois que todo componente
já foi auto-registrado. Antes, EntityCore.new criava esse conjunto de closures
TODA VEZ que uma entidade nascia — parede, minion, jogador, todo mundo pagava
esse custo (Regra 6).
]]
function ComponentUtils.BuildStubs(componentRegistry: {[string]: any}, targetStubs: {[string]: any})
	for compName, compData in pairs(componentRegistry) do
		if compData.ExposeAPI then
			for funcName in pairs(compData.ExposeAPI) do
				if targetStubs[funcName] == nil then
					targetStubs[funcName] = function(...)
						warn("[EntityCore] Componente ignorado:", compName, "| Func:", funcName)
					end
				end
			end
		end
	end
end

return ComponentUtils

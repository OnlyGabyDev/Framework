--[[
StaticChecks: verificações sobre o código-fonte e a árvore do place, que um teste em jogo não
alcança (Script.Source só é legível com segurança de plugin). Roda no modo Edit, pela barra de
comando ou pelo MCP:
	require(game.ServerScriptService.Scripts.Tests.StaticChecks)()
Devolve { passed, failed, failures } e imprime o resumo. Não roda em jogo.
]]

local ROOTS = { "ServerScriptService", "ServerStorage", "ReplicatedStorage", "StarterPlayer", "StarterGui" }

local function scripts()
	local list = {}
	for _, serviceName in ROOTS do
		for _, inst in game:GetService(serviceName):GetDescendants() do
			if inst:IsA("LuaSourceContainer") then
				table.insert(list, inst)
			end
		end
	end
	return list
end

local checks = {}

-- Todo script compila (um erro de sintaxe derruba o módulo inteiro e só aparece no Play)
checks["Todos os scripts compilam"] = function()
	local bad = {}
	for _, s in scripts() do
		local fn, err = loadstring(s.Source)
		if not fn then table.insert(bad, s:GetFullName() .. ": " .. tostring(err)) end
	end
	return #bad == 0, table.concat(bad, "\n")
end

-- Regra 19 / F18: pastas, módulos, scripts e models irmãos com o mesmo nome (inclusive só na
-- capitalização) são achados pelo nome, e o FindFirstChild escolhe pela ordem. Nomes repetidos
-- de propósito (Attachment DmgPoint da hitbox, Keyframe de animação, partes de um model) ficam
-- de fora: ninguém os procura pelo nome.
local NAMED = { "Folder", "LuaSourceContainer", "Model", "Configuration", "ValueBase" }

local function isNamed(inst)
	for _, className in NAMED do
		if inst:IsA(className) then return true end
	end
	return false
end

checks["Regra 19 — sem pastas/módulos/models duplicados entre irmãos"] = function()
	local bad = {}
	for _, serviceName in ROOTS do
		local service = game:GetService(serviceName)
		local containers = service:GetDescendants()
		table.insert(containers, service)
		for _, parent in containers do
			local seen = {}
			for _, child in parent:GetChildren() do
				if isNamed(child) then
					local key = string.lower(child.Name)
					if seen[key] then
						table.insert(bad, parent:GetFullName() .. "." .. child.Name)
					else
						seen[key] = true
					end
				end
			end
		end
	end
	return #bad == 0, table.concat(bad, "\n")
end

-- F60: EntityCore não tem .Entity (o model é .Instance); target.Entity:<método> dá erro
checks["F60 — nada chama target.Entity:<método>"] = function()
	local bad = {}
	for _, s in scripts() do
		-- este arquivo cita o padrão no texto das checagens (comparado pelo caminho: quem roda
		-- costuma dar require num clone, para não pegar o cache do require)
		if s:GetFullName() == "ServerScriptService.Scripts.Tests.StaticChecks" then continue end
		local lineNo = 0
		for line in (s.Source .. "\n"):gmatch("(.-)\n") do
			lineNo += 1
			if line:find("target%.Entity:") then
				table.insert(bad, string.format("%s:%d", s:GetFullName(), lineNo))
			end
		end
	end
	return #bad == 0, table.concat(bad, "\n")
end

-- F83: o servidor manda o ID roteado com Lock (o cliente trata nil como "voltar ao próprio corpo")
checks["F83 — notify do AntiCheat não zera o ID no Lock"] = function()
	local src = game:GetService("ServerScriptService").Modules.GlobalAntiCheat.Source
	local zeroes = src:find("not tracked%.Locked and tracked%.ID or nil") ~= nil
	local routes = src:find("if tracked%.Locked then tracked%.PreLockID else tracked%.ID") ~= nil
	return routes and not zeroes, "o ControlStateChanged voltou a mandar nil no Lock"
end

return function()
	local results = { passed = 0, failed = 0, failures = {} }
	local names = {}
	for name in checks do table.insert(names, name) end
	table.sort(names)
	for _, name in names do
		local ok, pass, detail = pcall(checks[name])
		if ok and pass then
			results.passed += 1
			print("[STATIC PASS] " .. name)
		else
			results.failed += 1
			local why = ok and detail or pass
			table.insert(results.failures, name .. " — " .. tostring(why))
			warn("[STATIC FAIL] " .. name .. " — " .. tostring(why))
		end
	end
	print(string.format("[StaticChecks] %d passou, %d falhou", results.passed, results.failed))
	return results
end
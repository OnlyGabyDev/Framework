--!strict
-- TestHarness: runner mínimo de testes server-side, assert+warn, mesmo
-- estilo que o resto do projeto já usa (não traz TestEZ nem dependência
-- nova — Regra 3, não presuma que você quer isso).

local TestHarness = {}
local results = { passed = 0, failed = 0 }

function TestHarness.Run(name: string, fn: (t: any) -> ())
	local t = {}
	function t.assert(condition: boolean, message: string?)
		if not condition then
			error(message or "assertion failed", 0)
		end
	end
	function t.wait(seconds: number)
		task.wait(seconds)
	end
	function t.log(...)
		print("  ", ...)
	end

	print(string.format("[TEST] %s...", name))
	local ok, err = pcall(fn, t)

	if ok then
		results.passed += 1
		print(string.format("[PASS] %s", name))
	else
		results.failed += 1
		warn(string.format("[FAIL] %s — %s", name, tostring(err)))
	end
end

function TestHarness.Summary(): boolean
	print(string.format("[TestHarness] %d passou, %d falhou", results.passed, results.failed))
	return results.failed == 0
end

return TestHarness

--[[
Cenários de física medidos frame a frame: zonas de vento (AreaEffect + AreaBehaviors), dash
Hard por cima do vento, soma de zonas, caminhada contra o vento, status e o player real.

Cada teste mede posição/velocidade num Heartbeat e confere números, não só "rodou". Nascem do
bug de 11/11: o dash na frente do ventilador fazia o empurrão chegar DEPOIS do dash, já fora da
zona (a força sobrevivia à saída pelo resto do Duration).

Convenções: vento sempre na direção -Z da faixa; velocidades em studs/s; a zona faz poll a
10 Hz, então "na hora" é até 1 poll (0,1 s) mais alguns frames.
Chamado pelo IntegrationTests com os helpers dele (env), antes do Summary.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")

local SkillRunner = require(ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(ServerScriptService.Modules.SkillFactory)
local DataManager = require(ServerScriptService.EntityData.DataManager)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local AreaEffect = require(ServerStorage.Modules.Combat.AreaEffect)
local AreaBehaviors = require(ServerStorage.Modules.Combat.AreaBehaviors)
local DashModule = require(ServerStorage.DataBase.SkillDatabase.Schema.Dash)

local WIND = 30            -- velocidade do vento dos testes (a do ventilador da demo)
local WIND_FORCE = 35000   -- MaxForce do ventilador da demo
local POLL = 0.1           -- 10 Hz
local DASH_TIME = DashModule.data.duration
local WIND_DIR = Vector3.new(0, 0, -1)

-- Grava posição e velocidade da raiz a cada Heartbeat, com o tempo desde o início
local function record(entity: any, extra: ((any) -> any)?)
	local root = entity.GetRoot()
	local samples = {}
	local t0 = os.clock()
	local conn = RunService.Heartbeat:Connect(function()
		table.insert(samples, {
			t = os.clock() - t0,
			pos = root.Position,
			vel = root.AssemblyLinearVelocity,
			extra = extra and extra(entity),
		})
	end)
	local rec = { samples = samples, t0 = t0 }
	function rec.stop() conn:Disconnect() end
	function rec.now() return os.clock() - t0 end
	-- velocidade média no eixo Z (do vento) entre t1 e t2
	function rec.avgVz(t1: number, t2: number): number?
		local sum, n = 0, 0
		for _, s in samples do
			if s.t >= t1 and s.t <= t2 then sum += s.vel.Z; n += 1 end
		end
		return n > 0 and sum / n or nil
	end
	-- 1º instante a partir de t1 em que a condição vale
	function rec.firstWhere(t1: number, cond: (any) -> boolean): number?
		for _, s in samples do
			if s.t >= t1 and cond(s) then return s.t end
		end
		return nil
	end
	function rec.at(t: number)
		local best
		for _, s in samples do
			if s.t <= t then best = s else break end
		end
		return best or samples[1]
	end
	return rec
end

local function movement(entity: any)
	return entity:GetComponent(entity.ComponentKey.Movement)
end

local function dash(entity: any, direction: Vector3)
	entity.SetDirection(direction)
	local runner = SkillRunner.new(SkillFactory.GetSkill(DashModule), entity, "Dash", StateTable.Enum.Types.Skill)
	runner:start()
	entity.SetDirection(Vector3.zero) -- o dash fixa a direção no onStart
	return runner
end

-- Warns e erros do motor durante fn (para "não gera erro")
local function captureEngineWarnings(fn: () -> ()): { string }
	local caught = {}
	local conn = LogService.MessageOut:Connect(function(message, kind)
		if kind == Enum.MessageType.MessageWarning or kind == Enum.MessageType.MessageError then
			-- Só o que vem do caminho testado (zona, força, movimento, entidade) ou erro de script;
			-- warns de outros sistemas rodando no Play não contam
			local lower = message:lower()
			if lower:find("area") or lower:find("force") or lower:find("movement") or lower:find("entity")
				or lower:find("attempt to") or lower:find("stub") then
				table.insert(caught, message)
			end
		end
	end)
	local ok, err = pcall(fn)
	conn:Disconnect()
	if not ok then table.insert(caught, "erro no teste: " .. tostring(err)) end
	return caught
end

return function(env)
	local run, makeDummy, cleanup, origin, COMBAT = env.run, env.makeDummy, env.cleanup, env.origin, env.COMBAT

	-- Zona de vento na faixa atual. center e size relativos ao chão da faixa; o vento é -Z.
	local function windZone(center: Vector3, size: Vector3, opts: { [string]: any }?)
		opts = opts or {}
		local cframe = origin() * CFrame.new(center)
		local provider = opts.provider or function() return cframe end
		local zone = AreaEffect.new(provider, "Box", size, 10)
		local forceType = opts.forceType or "TestWind"
		AreaBehaviors.BindDirectionalForce(zone, opts.direction or WIND_DIR, opts.speed or WIND, forceType,
			{ MaxForce = opts.maxForce or WIND_FORCE })
		zone:Start()
		local key = "Area:" .. forceType .. ":" .. zone.ID
		return zone, key, cframe
	end

	local function hasWind(entity: any, key: string): boolean
		return movement(entity).ForcesByKey[key] ~= nil
	end

	-- Zona padrão: 10 x 10 x 20, de z = 0 a z = -20 (a da demo)
	local SMALL_CENTER, SMALL_SIZE = Vector3.new(0, 5, -10), Vector3.new(10, 10, 20)

	run("Física 1 — dentro da zona o vento empurra na velocidade dela", function(t)
		local e = makeDummy(CFrame.new(0, 2, -2), COMBAT)
		e.SetMovement()
		local zone = windZone(SMALL_CENTER, SMALL_SIZE)
		local rec = record(e)
		t.wait(0.5)
		rec.stop()
		local vz = rec.avgVz(0.25, 0.5)
		t.log(string.format("vz médio %.1f (esperado %d)", vz or 0, -WIND))
		t.assert(vz and math.abs(vz + WIND) < 4, string.format("Velocidade do vento %.1f, esperado %d", vz or 0, -WIND))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 2 — o vento começa no 1º poll dentro da zona (OnEnter)", function(t)
		local e = makeDummy(CFrame.new(0, 2, -10), COMBAT)
		e.SetMovement()
		t.wait(0.3)
		local rec = record(e)
		local zone = windZone(SMALL_CENTER, SMALL_SIZE)
		t.wait(0.5)
		rec.stop()
		local firstPush = rec.firstWhere(0, function(s) return s.vel.Z < -5 end)
		t.log(string.format("1º empurrão em %.3f s", firstPush or -1))
		-- 1 poll + aceleração; antes só o OnStay aplicava e o 1º poll dentro não empurrava (~0,2 s)
		t.assert(firstPush and firstPush < POLL + 0.08, string.format("O vento demorou %.3f s para começar", firstPush or -1))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 3 — sair da zona encerra o vento em até 1 poll", function(t)
		local e = makeDummy(CFrame.new(0, 2, -14), COMBAT)
		e.SetMovement()
		local zone, key = windZone(SMALL_CENTER, SMALL_SIZE)
		local rec = record(e, function(ent) return hasWind(ent, key) end)
		t.wait(1.2) -- o vento leva o corpo para fora pela borda z = -20
		rec.stop()
		local exitT = rec.firstWhere(0.05, function(s) return s.pos.Z < (origin().Position.Z - 20 - 1) end)
		t.assert(exitT, "O corpo não saiu da zona pela borda do vento")
		local goneT = rec.firstWhere(exitT, function(s) return s.extra == false end)
		t.log(string.format("saiu em %.2f s; força removida em %.2f s", exitT, goneT or -1))
		t.assert(goneT and goneT - exitT <= POLL + 0.05, string.format("A força durou %.2f s depois da saída", (goneT or 99) - exitT))
		-- Sem a força o corpo freia: 0,3 s depois de removida não pode seguir na velocidade do vento
		local after = rec.avgVz(goneT + 0.25, goneT + 0.4)
		t.assert(after and after > -WIND * 0.5, string.format("O corpo seguiu a %.1f studs/s fora da zona", after or 0))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 4 — dash de lado saindo da zona: nenhum empurrão depois do dash (bug de 11/11)", function(t)
		local e = makeDummy(CFrame.new(0, 2, -6), COMBAT)
		e.SetMovement()
		local zone, key = windZone(SMALL_CENTER, SMALL_SIZE)
		t.wait(0.3) -- já sendo empurrado
		t.assert(hasWind(e, key) and e.GetRoot().AssemblyLinearVelocity.Z < -WIND * 0.6,
			"Pré-condição: o vento deveria estar empurrando antes do dash")
		local rec = record(e)
		dash(e, Vector3.new(1, 0, 0))
		t.wait(DASH_TIME + 0.8)
		rec.stop()
		local atEnd = rec.at(DASH_TIME + 0.05)
		local final = rec.samples[#rec.samples]
		local dz = final.pos.Z - atEnd.pos.Z
		t.log(string.format("deslocamento no eixo do vento depois do dash: %.2f studs (antes da correção: ~8)", dz))
		t.assert(math.abs(dz) < 1, string.format("O vento empurrou %.2f studs depois do dash, já fora da zona", dz))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 5 — dash a favor do vento saindo da zona: a força sai na saída, não no fim do Duration", function(t)
		-- O embalo do dash vai na mesma direção do vento: a velocidade não separa os dois, então o
		-- teste confere a força em si (antes ela durava até 0,35 s depois da saída)
		local e = makeDummy(CFrame.new(0, 2, -4), COMBAT)
		e.SetMovement()
		local zone, key = windZone(SMALL_CENTER, SMALL_SIZE)
		t.wait(0.3)
		t.assert(hasWind(e, key), "Pré-condição: o vento deveria estar ativo antes do dash")
		local rec = record(e, function(ent) return hasWind(ent, key) end)
		dash(e, WIND_DIR)
		t.wait(DASH_TIME + 0.4)
		rec.stop()
		local edgeZ = origin().Position.Z - 20 - 1
		local exitT = rec.firstWhere(0, function(s) return s.pos.Z < edgeZ end)
		t.assert(exitT, "O dash não saiu da zona")
		local goneT = rec.firstWhere(exitT, function(s) return s.extra == false end)
		t.log(string.format("saiu em %.2f s; força removida em %.2f s; dash acaba em %.2f s", exitT, goneT or -1, DASH_TIME))
		t.assert(goneT and goneT - exitT <= POLL + 0.05, string.format("A força durou %.2f s depois da saída", (goneT or 99) - exitT))
		t.assert(goneT < DASH_TIME, "A força do vento ainda existia quando o dash acabou")
		zone:Stop()
		cleanup(e)
	end)

	run("Física 6 — dash dentro da zona: Hard ignora o vento durante, e o vento volta logo depois", function(t)
		-- Zona grande o bastante para o dash (28 studs) terminar dentro
		local e = makeDummy(CFrame.new(-14, 2, 20), COMBAT)
		e.SetMovement()
		local zone = windZone(Vector3.new(0, 5, 0), Vector3.new(44, 10, 100))
		t.wait(0.3)
		local rec = record(e)
		dash(e, Vector3.new(1, 0, 0))
		t.wait(DASH_TIME + 0.6)
		rec.stop()
		local during = rec.avgVz(0.05, DASH_TIME - 0.05)
		t.log(string.format("vz médio durante o dash: %.1f", during or 0))
		t.assert(during and math.abs(during) < 3, string.format("O vento vazou para dentro do dash Hard (vz %.1f)", during or 0))
		local back = rec.firstWhere(DASH_TIME, function(s) return s.vel.Z < -WIND * 0.6 end)
		t.log(string.format("vento de volta %.3f s depois do fim do dash", back and back - DASH_TIME or -1))
		t.assert(back and back - DASH_TIME < 0.2, "O vento não voltou logo depois do dash dentro da zona")
		zone:Stop()
		cleanup(e)
	end)

	run("Física 7 — atravessar a zona de dash não deixa vento para depois", function(t)
		local e = makeDummy(CFrame.new(-12, 2, -10), COMBAT)
		e.SetMovement()
		local zone, key = windZone(SMALL_CENTER, SMALL_SIZE)
		t.wait(0.3)
		local rec = record(e, function(ent) return hasWind(ent, key) end)
		dash(e, Vector3.new(1, 0, 0))
		t.wait(DASH_TIME + 0.7)
		rec.stop()
		local final = rec.samples[#rec.samples]
		local atEnd = rec.at(DASH_TIME + 0.05)
		-- A passagem dura ~0,15 s: dependendo da fase do poll a zona vê o corpo ou não (registrado)
		local seen = rec.firstWhere(0, function(s) return s.extra == true end)
		t.log("a zona viu a passagem: " .. (seen and string.format("sim, em %.2f s", seen) or "não (passou entre dois polls)"))
		t.assert(math.abs(final.pos.Z - atEnd.pos.Z) < 1, "O vento empurrou depois de atravessar a zona")
		t.assert(not atEnd.extra and not final.extra, "A força do vento ficou viva depois de atravessar")
		zone:Stop()
		cleanup(e)
	end)

	run("Física 8 — duas zonas sobrepostas somam (-30 e +20 = -10), uma força por zona", function(t)
		local e = makeDummy(CFrame.new(0, 2, 0), COMBAT)
		e.SetMovement()
		local big = Vector3.new(30, 10, 80)
		local zoneA, keyA = windZone(Vector3.new(0, 5, 0), big, { forceType = "TestWindA" })
		local zoneB, keyB = windZone(Vector3.new(0, 5, 0), big, { forceType = "TestWindB", direction = -WIND_DIR, speed = 20 })
		local rec = record(e)
		t.wait(0.7)
		rec.stop()
		local vz = rec.avgVz(0.4, 0.7)
		t.log(string.format("vz médio %.1f (esperado -10)", vz or 0))
		t.assert(hasWind(e, keyA) and hasWind(e, keyB), "As duas zonas deveriam ter uma força cada")
		t.assert(vz and math.abs(vz + 10) < 3, string.format("A soma deu %.1f, esperado -10", vz or 0))
		zoneA:Stop(); zoneB:Stop()
		cleanup(e)
	end)

	run("Física 9 — sair de uma de duas zonas tira só a força daquela", function(t)
		local e = makeDummy(CFrame.new(0, 2, 0), COMBAT)
		e.SetMovement()
		local zoneA, keyA = windZone(Vector3.new(0, 5, 0), Vector3.new(30, 10, 80), { forceType = "TestWindA" })
		local zoneB, keyB = windZone(Vector3.new(0, 5, 0), Vector3.new(30, 10, 80), { forceType = "TestWindB", direction = -WIND_DIR, speed = 20 })
		t.wait(0.4)
		zoneB:Stop()
		t.wait(0.1)
		t.assert(not hasWind(e, keyB), "A força da zona parada ficou")
		t.assert(hasWind(e, keyA), "Parar uma zona tirou a força da outra")
		local rec = record(e)
		t.wait(0.4)
		rec.stop()
		local vz = rec.avgVz(0.2, 0.4)
		t.assert(vz and math.abs(vz + WIND) < 4, string.format("Só com a zona A o vento deveria ser %d (deu %.1f)", -WIND, vz or 0))
		zoneA:Stop()
		cleanup(e)
	end)

	run("Física 10 — zone:Stop encerra o vento na hora", function(t)
		local e = makeDummy(CFrame.new(0, 2, -2), COMBAT)
		e.SetMovement()
		local zone, key = windZone(SMALL_CENTER, SMALL_SIZE)
		t.wait(0.3)
		t.assert(hasWind(e, key), "O vento não estava ativo antes do Stop")
		zone:Stop()
		t.wait(0.05)
		t.assert(not hasWind(e, key), "A força sobreviveu ao zone:Stop")
		cleanup(e)
	end)

	run("Física 11 — andar contra o vento: caminhada + vento (16 - 30 = -14)", function(t)
		local e = makeDummy(CFrame.new(0, 2, -20), COMBAT)
		e.SetMovement()
		local zone = windZone(Vector3.new(0, 5, 0), Vector3.new(30, 10, 100))
		e.SetDirection(-WIND_DIR) -- anda para o ventilador
		local walk = movement(e):GetSpeed()
		local rec = record(e)
		t.wait(0.8)
		rec.stop()
		e.SetDirection(Vector3.zero)
		local vz = rec.avgVz(0.4, 0.8)
		local expected = walk - WIND
		t.log(string.format("vz médio %.1f (esperado %.1f com caminhada %.1f)", vz or 0, expected, walk))
		t.assert(vz and math.abs(vz - expected) < 4, string.format("Contra o vento deu %.1f, esperado %.1f", vz or 0, expected))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 12 — Stun não segura o vento (força externa, F30)", function(t)
		local e = makeDummy(CFrame.new(0, 2, 20), COMBAT)
		e.SetMovement()
		e.ApplyStatus(StateTable.States.Stun, { Duration = 2 })
		local zone = windZone(Vector3.new(0, 5, 0), Vector3.new(30, 10, 100))
		local rec = record(e)
		t.wait(0.6)
		rec.stop()
		local vz = rec.avgVz(0.3, 0.6)
		t.assert(vz and math.abs(vz + WIND) < 4, string.format("Com Stun o vento deu %.1f, esperado %d", vz or 0, -WIND))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 13 — zona que gira: o vento segue a direção atual", function(t)
		local e = makeDummy(CFrame.new(0, 2, 0), COMBAT)
		e.SetMovement()
		local angle = 0
		local base = origin() * CFrame.new(0, 5, 0)
		local zone = windZone(Vector3.zero, Vector3.new(60, 10, 60), {
			provider = function() return base end,
			direction = function() return CFrame.Angles(0, angle, 0):VectorToWorldSpace(WIND_DIR) end,
		})
		t.wait(0.4)
		angle = math.rad(90) -- vento passa de -Z para -X
		t.wait(0.4)
		local v = e.GetRoot().AssemblyLinearVelocity
		t.log(string.format("velocidade depois do giro: (%.1f, %.1f)", v.X, v.Z))
		t.assert(v.X < -WIND * 0.7 and math.abs(v.Z) < 5, string.format("O vento não seguiu o giro (vx %.1f, vz %.1f)", v.X, v.Z))
		zone:Stop()
		cleanup(e)
	end)

	run("Física 14 — entidade destruída dentro da zona não gera erro e sai da zona", function(t)
		local zone
		local warnings = captureEngineWarnings(function()
			local e = makeDummy(CFrame.new(0, 2, -6), COMBAT)
			e.SetMovement()
			zone = windZone(SMALL_CENTER, SMALL_SIZE)
			task.wait(0.3)
			cleanup(e)
			task.wait(0.4)
			t.assert(next(zone.Inside) == nil, "A entidade destruída ficou na lista da zona")
		end)
		if zone then zone:Stop() end
		t.assert(#warnings == 0, "Warns do motor: " .. table.concat(warnings, " | "))
	end)

	run("Física 15 — DirectionalForce solta (sem zona) ainda dura o Duration", function(t)
		local e = makeDummy(CFrame.new(0, 2, 0), COMBAT)
		e.SetMovement()
		AreaBehaviors.DirectionalForce(e, WIND_DIR, WIND, "TestLoose", { MaxForce = WIND_FORCE, Duration = 0.3 })
		local key = "Area:TestLoose:Any"
		t.wait(0.15)
		t.assert(hasWind(e, key), "A força solta acabou antes do Duration")
		t.wait(0.3)
		t.assert(not hasWind(e, key), "A força solta passou do Duration")
		cleanup(e)
	end)

	run("Física 16 — player real: vento empurra, sai da zona sem resto, dash sem empurrão depois", function(t)
		local player = Players:GetPlayers()[1]
		local character = player and player.Character
		local body = character and character:GetAttribute("EntityID") and DataManager.Get(character)
		if not body then
			t.log("sem player com entidade neste Play: teste pulado")
			return
		end
		local root = body.GetRoot()
		local home = root.CFrame
		character:PivotTo(origin() * CFrame.new(0, 4, -6))
		t.wait(0.5)
		-- O corpo do player é do cliente: o servidor o vê pelo buffer de interpolação, ~0,3 s atrás
		-- do que o cliente sente (medido em 11/11: o cliente sente o vento 0,02 s e o dash 0,05 s
		-- depois da força; o servidor só vê ~0,35 s depois). As janelas abaixo descontam isso.
		local VIEW_LAG = 0.4
		character:PivotTo(origin() * CFrame.new(0, 4, -2))
		t.wait(0.5)
		-- Zona de 60 de comprimento: com o atraso de visão, o player precisa de mais tempo no vento
		local zone, key = windZone(Vector3.new(0, 5, -30), Vector3.new(10, 10, 60))
		local rec = record(body, function(ent) return hasWind(ent, key) end)
		local preDash = 0.6
		t.wait(preDash)
		t.assert(hasWind(body, key), "Pré-condição: o vento deveria estar ativo no player antes do dash")
		-- Mesmo perfil do dash da Schema, aplicado direto (o dash do player lê a direção do cliente)
		body.AddForce({ Type = "TestDash", Duration = DASH_TIME, Speed = DashModule.data.speed,
			Direction = Vector3.new(1, 0, 0), Hard = true, IgnoreGravity = true, Priority = 10 })
		t.wait(DASH_TIME + VIEW_LAG + 0.9)
		rec.stop()
		-- O vento que o servidor vê, no trecho entre a chegada dele e a do dash
		local push = rec.avgVz(0.1 + VIEW_LAG + 0.1, preDash + VIEW_LAG - 0.15)
		-- Assentado: do fim do dash visto pelo servidor em diante, o eixo do vento não pode andar
		local settled = rec.at(preDash + DASH_TIME + VIEW_LAG + 0.2)
		local final = rec.samples[#rec.samples]
		local dz = final.pos.Z - settled.pos.Z
		t.log(string.format("player: vento visto %.1f; deriva no eixo do vento depois de assentar %.2f studs; força viva no fim: %s",
			push or 0, dz, tostring(final.extra)))
		zone:Stop()
		character:PivotTo(home)
		t.assert(push and push < -WIND * 0.6, string.format("O vento não empurrou o player (vz %.1f)", push or 0))
		t.assert(not final.extra, "A força do vento ficou no player fora da zona")
		t.assert(math.abs(dz) < 0.5, string.format("O player derivou %.2f studs no eixo do vento depois do dash", dz))
	end)
end

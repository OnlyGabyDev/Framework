--[[
Testes duros de funcionalidade (22/11/2026). Cada um mede o contrato no limite: cadeia longa e
infinita (F62), skill fora do kit dono (F55), spam de input, morte e destruição no meio da skill,
troca rápida de status, a fórmula de dano por amostragem e o TriggerSet mudando durante o Emit.

Regras destes testes (as mesmas do PhysicsScenarios):
- toda asserção de "não aconteceu" vem com a pré-condição de que a situação existiu (a cadeia
  chegou mesmo no limite? a skill estava mesmo rodando quando a entidade morreu?);
- erro de motor é medido pelo Output (LogService), não só pelo pcall: o motor isola erro com warn.

Chamado pelo IntegrationTests com os helpers dele (env), antes do Summary.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LogService = game:GetService("LogService")

local DataManager = require(ServerScriptService.EntityData.DataManager)
local SkillRunner = require(ServerScriptService.Modules.SkillRunner)
local SkillFactory = require(ServerScriptService.Modules.SkillFactory)
local StateTable = require(ServerStorage.Modules.Combat.StateTable)
local AnimationLib = require(ServerStorage.Modules.Animation.AnimationLib)
local AreaEffect = require(ServerStorage.Modules.Combat.AreaEffect)
local HitboxWrapper = require(ServerStorage.Modules.Combat.Hitbox.HitboxWrapper)
local Intents = require(ReplicatedStorage.Input.Intents)

local E = StateTable.Enum
local CHAIN = E.ChainLimits
local Types = E.Types

-- Warns de erro do motor (callbacks isolados, cadeia, scheduler, TriggerSet) durante `fn`
local ENGINE_ERRORS = {
	"%[SkillRunner%] Erro em", "%[SkillScheduler%] Erro em", "erro dentro da cadeia", "%[TriggerSet%] erro",
	"%[AIScheduler%] Erro",
}
local function engineErrorsDuring(fn: () -> ()): { string }
	local found = {}
	local conn = LogService.MessageOut:Connect(function(message)
		for _, pattern in ENGINE_ERRORS do
			if string.find(message, pattern) then
				table.insert(found, string.sub(message, 1, 200))
				break
			end
		end
	end)
	fn()
	task.wait() -- sinais Deferred: o MessageOut do último warn chega no próximo ciclo
	task.wait()
	conn:Disconnect()
	return found
end

-- Níveis da cadeia síncrona ocupados agora (0 = fora de cadeia)
local function chainDepth(): number
	local free = 0
	while StateTable.TryEnterChain() do
		free += 1
		if free > E.MAX_RECURSION then break end
	end
	for _ = 1, free do StateTable.ExitChain() end
	return E.MAX_RECURSION - free
end

-- Conta os Heartbeats a partir de agora (para medir em frames uma coisa que começa numa chamada)
local function frameCounter()
	local counter = { count = 0 }
	counter.conn = RunService.Heartbeat:Connect(function() counter.count += 1 end)
	function counter.stop(): number
		counter.conn:Disconnect()
		return counter.count
	end
	return counter
end

local function frames(n: number)
	for _ = 1, n do RunService.Heartbeat:Wait() end
end

-- Espera a condição por até `timeout` s; devolve os frames que levou (nil = não aconteceu)
local function waitFrames(condition: () -> boolean, timeout: number): number?
	local count, t0 = 0, os.clock()
	while not condition() do
		if os.clock() - t0 > timeout then return nil end
		RunService.Heartbeat:Wait()
		count += 1
	end
	return count
end

return function(env)
	local run, makeDummy, cleanup, makeRunner, press, COMBAT = env.run, env.makeDummy, env.cleanup, env.makeRunner, env.press, env.COMBAT
	local LIGHT = { "Character", "Health", "Status" }

	-- Dummy parado (ancorado): os testes de cadeia não dependem de física
	local function still(cframe: CFrame, components: { string }?, configs: any?)
		local e = makeDummy(cframe, components or LIGHT, configs)
		e.GetRoot().Anchored = true
		return e
	end

	-- Corpo com Humanoid + Animator (para o AnimationComponent ter onde tocar)
	local function animated(cframe: CFrame, components: { string }, configs: any?)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Anchored = true
		root.CFrame = env.origin() * cframe
		root.Parent = model
		model.PrimaryPart = root
		local humanoid = Instance.new("Humanoid")
		Instance.new("Animator").Parent = humanoid
		humanoid.Parent = model
		model.Parent = workspace
		return DataManager.Create(model, components, configs)
	end

	local function equip(dummy, slot, name, data, callbacks)
		data.name = name
		dummy.EquipSkill(slot, { data = data, callbacks = callbacks or {} })
	end

	--=========================================================================
	--  F62 — CADEIAS
	--=========================================================================

	run("F62 — cadeia síncrona em linha de 80: termina inteira em poucos frames, sem sobra na fila", function(t)
		local N = 80
		local line = {}
		for i = 1, N do
			line[i] = still(CFrame.new(-27 + (i - 1) % 20 * 3, 5, -45 + (i - 1) // 20 * 4))
		end
		local src = makeRunner(line[1], "__HardChainLine", { duration = 5 }, {})
		src:start()
		for i = 1, N - 1 do
			local nextEntity = line[i + 1]
			line[i]:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.OnDeath, Action = function()
				nextEntity.TakeDamage(1000, src)
			end })
		end

		local deadSync, queued
		local clock = frameCounter()
		local errors = engineErrorsDuring(function()
			line[1].TakeDamage(1000, src)
			deadSync = 0
			for i = 1, N do if not line[i].IsAlive() then deadSync += 1 end end
			queued = StateTable.GetDeferredCount()
		end)
		-- Pré-condição: a cadeia chegou mesmo no limite da pilha (senão o teste não prova nada)
		t.assert(deadSync < N and queued > 0,
			string.format("A cadeia não chegou no MAX_RECURSION (mortos na hora %d, na fila %d)", deadSync, queued))
		t.assert(deadSync == E.MAX_RECURSION, "Mortos na mesma pilha: " .. deadSync .. " (esperado " .. E.MAX_RECURSION .. ")")

		local finished = waitFrames(function()
			for i = 1, N do if line[i].IsAlive() then return false end end
			return true
		end, 1)
		local took = clock.stop()
		t.log(string.format("na hora %d de %d; a cadeia inteira em %d frame(s)", deadSync, N, took))
		t.assert(finished ~= nil, "A cadeia não terminou: a sobra foi descartada")
		-- 50 na hora e 30 no frame seguinte (o 1º Heartbeat já roda a fila)
		t.assert(took <= 3, "A cadeia levou " .. took .. " frames (esperado 1 geração por frame)")
		t.assert(StateTable.GetDeferredCount() == 0, "Sobrou ação na fila: " .. StateTable.GetDeferredCount())
		t.assert(chainDepth() == 0, "A profundidade da cadeia vazou: " .. chainDepth())
		t.assert(#errors == 0, "Erro do motor na cadeia: " .. tostring(errors[1]))

		src:endSkill(false)
		for _, e in line do cleanup(e) end
	end)

	run("F62 — ping-pong infinito de reflexo para no limite de gerações, um lote por frame", function(t)
		local A = still(CFrame.new(-3, 5, 0), LIGHT, { Health = { MaxHP = 1e9 } })
		local B = still(CFrame.new(3, 5, 0), LIGHT, { Health = { MaxHP = 1e9 } })
		local reflects = 0
		local Reflect = { data = { name = "__HardReflect", category = E.Categories.Buff, tags = { [E.Tags.block] = true } },
			callbacks = { onTrigger = function(self, context)
				reflects += 1
				local attacker = context.sourceEntity
				if attacker and attacker ~= self.Entity then attacker.TakeDamage(1, self.Runner) end
				return context.damage
			end } }
		A.ApplyStatus(Reflect, { Duration = 10 })
		B.ApplyStatus(Reflect, { Duration = 10 })
		local poke = makeRunner(B, "__HardPoke", { duration = 10 }, {})
		poke:start()

		local okCall, syncReflects
		local clock = frameCounter()
		local errors = engineErrorsDuring(function()
			okCall = pcall(function() A.TakeDamage(1, poke) end)
			syncReflects = reflects
		end)
		t.assert(okCall, "A cadeia lançou erro para quem chamou")
		t.assert(syncReflects == E.MAX_RECURSION, "Reflexos na mesma pilha: " .. syncReflects)

		local emptied = waitFrames(function() return StateTable.GetDeferredCount() == 0 end, 3)
		local took = clock.stop()
		t.assert(emptied ~= nil, "A fila não esvaziou em 3 s: o laço infinito não para")
		local stopped = reflects
		frames(10)
		local expected = (CHAIN.maxDeferrals + 1) * E.MAX_RECURSION
		t.log(string.format("reflexos: %d na hora, %d no total em %d frames (esperado %d)", syncReflects, stopped, took, expected))
		t.assert(reflects == stopped, "Os reflexos continuaram depois de a fila esvaziar")
		t.assert(stopped == expected, string.format("Total de reflexos %d (esperado %d)", stopped, expected))
		-- Uma geração por frame: maxDeferrals frames (o 1º Heartbeat já roda a 1ª geração adiada)
		t.assert(took >= CHAIN.maxDeferrals and took <= CHAIN.maxDeferrals + 2,
			string.format("As %d gerações levaram %d frames (esperado 1 por frame)", CHAIN.maxDeferrals, took))
		t.assert(#errors == 0, "Erro do motor: " .. tostring(errors[1]))

		poke:endSkill(false)
		cleanup(A)
		cleanup(B)
	end)

	run("F62 — hit adiado pelo ApplyDamage mantém o OUT.OnDamage do atacante", function(t)
		local attacker = still(CFrame.new(0, 5, 20), COMBAT)
		local N = 60
		local victims = {}
		for i = 1, N do
			victims[i] = still(CFrame.new(-27 + (i - 1) % 20 * 3, 5, -45 + (i - 1) // 20 * 4))
		end
		local src = makeRunner(attacker, "__HardChainHit", { duration = 5 }, {})
		src:start()
		local onDamage = 0
		attacker:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDamage, Owner = src, Action = function()
			onDamage += 1
		end })
		for i = 1, N - 1 do
			local nextEntity = victims[i + 1]
			victims[i]:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.OnDeath, Action = function()
				src:Damage(nextEntity, 1000)
			end })
		end

		src:Damage(victims[1], 1000)
		local queued = StateTable.GetDeferredCount()
		t.assert(queued > 0, "Pré-condição: a cadeia de hits não chegou no limite")
		local took = waitFrames(function()
			for i = 1, N do if victims[i].IsAlive() then return false end end
			return true
		end, 1)
		t.log(string.format("%d hits, OUT.OnDamage %d, em %s frame(s)", N, onDamage, tostring(took)))
		t.assert(took ~= nil, "A cadeia de hits não terminou")
		t.assert(onDamage == N, string.format("OUT.OnDamage %d de %d hits: o hit adiado perdeu o evento do atacante", onDamage, N))

		src:endSkill(false)
		cleanup(attacker)
		for _, e in victims do cleanup(e) end
	end)

	run("F62 — árvore assíncrona para na largura (runners vivos por raiz); recusados não rodam callback", function(t)
		local e = still(CFrame.new(0, 5, 0))
		local started, ended, live, peak, refused, attempts = 0, 0, 0, 0, 0, 0
		local Fork
		Fork = SkillFactory.GetSkill({ data = { name = "__HardFork", duration = 0.6 }, callbacks = {
			onStart = function(self, ctx)
				started += 1
				live += 1
				peak = math.max(peak, live)
				if ctx.depth < 12 then
					local lineage = self.Runner.Lineage
					for _ = 1, 2 do
						task.defer(function()
							attempts += 1
							if not SkillRunner.new(Fork, e, "__HardFork", Types.Skill, lineage):start() then
								refused += 1
							end
						end)
					end
				end
			end,
			onEnd = function()
				live -= 1
				ended += 1
			end,
		} })
		local rootRunner = SkillRunner.new(Fork, e, "__HardFork", Types.Skill)
		rootRunner:start()
		local root = rootRunner.Lineage.Root
		t.wait(0.3)
		local livePeakSeen = root.LiveRunners
		t.wait(1)
		t.log(string.format("tentativas %d, iniciados %d, recusados %d, pico de vivos %d", attempts + 1, started, refused, peak))
		t.assert(refused > 0, "Pré-condição: a árvore não chegou no limite de largura")
		t.assert(peak == CHAIN.maxLiveRunnersPerRoot, "Pico de vivos " .. peak .. " (limite " .. CHAIN.maxLiveRunnersPerRoot .. ")")
		t.assert(livePeakSeen <= CHAIN.maxLiveRunnersPerRoot, "LiveRunners passou do limite: " .. tostring(livePeakSeen))
		t.assert(started + refused == attempts + 1, "Conta não fecha: iniciados + recusados ≠ tentativas")
		t.assert(ended == started, string.format("onEnd rodou %d vezes para %d iniciados (recusado rodou callback?)", ended, started))
		t.assert(root.LiveRunners == 0, "A raiz ficou com " .. tostring(root.LiveRunners) .. " vivos depois do fim")
		cleanup(e)
	end)

	run("F62 — cadeia assíncrona linear (laço que se renova) passa do limite de largura sem corte", function(t)
		local e = still(CFrame.new(0, 5, 0))
		local DEPTH = CHAIN.maxLiveRunnersPerRoot + 20
		local maxDepth, peakLive = 0, 0
		local Link
		Link = SkillFactory.GetSkill({ data = { name = "__HardLink", duration = 1 }, callbacks = {
			onStart = function(self, ctx)
				maxDepth = math.max(maxDepth, ctx.depth)
				local root = self.Runner.Lineage.Root
				peakLive = math.max(peakLive, root.LiveRunners or 0)
				if ctx.depth < DEPTH then
					local lineage = self.Runner.Lineage
					-- task.defer em cadeia para em 80 níveis no Roblox: a cada 50, um frame novo
					local schedule = (ctx.depth % 50 == 0) and function(f) task.delay(0, f) end or task.defer
					schedule(function() SkillRunner.new(Link, e, "__HardLink", Types.Skill, lineage):start() end)
				end
				self:Stop(false) -- uma vida por vez: é um laço, não uma árvore
			end,
		} })
		local first = SkillRunner.new(Link, e, "__HardLink", Types.Skill)
		first:start()
		local took = waitFrames(function() return maxDepth >= DEPTH end, 3)
		t.log(string.format("profundidade %d em %s frames; pico de vivos %d", maxDepth, tostring(took), peakLive))
		t.assert(took ~= nil, "O laço foi cortado na profundidade " .. maxDepth)
		t.assert(peakLive <= 2, "O laço linear teve " .. peakLive .. " vivos ao mesmo tempo")
		t.assert(first.Lineage.Root.LiveRunners == 0, "Sobrou vivo na raiz: " .. tostring(first.Lineage.Root.LiveRunners))
		cleanup(e)
	end)

	run("F62 — dano e status adiados: chegam no alvo vivo e somem no alvo destruído", function(t)
		local Mark = { data = { name = "__HardMark", category = E.Categories.Debuff }, callbacks = {} }
		local alive = still(CFrame.new(-4, 5, 0))
		local doomed = still(CFrame.new(4, 5, 0))

		-- Ocupa a pilha inteira, como uma cadeia de 50 níveis faria
		local occupied = 0
		while StateTable.TryEnterChain() do occupied += 1 end
		local idAlive = alive.ApplyStatus(Mark, { Duration = 5 })
		local okDamage, why = alive.TakeDamage(10)
		doomed.ApplyStatus(Mark, { Duration = 5 })
		doomed.TakeDamage(10)
		local queued = StateTable.GetDeferredCount()
		for _ = 1, occupied do StateTable.ExitChain() end

		t.assert(occupied == E.MAX_RECURSION, "Pré-condição: a pilha não estava livre no começo (" .. occupied .. ")")
		t.assert(idAlive == nil and okDamage == false and why == E.ChainOutcomes.Deferred,
			"Na pilha cheia o status e o dano deviam ser adiados (status " .. tostring(idAlive) .. ", dano " .. tostring(why) .. ")")
		t.assert(queued == 4, "Na fila: " .. queued .. " (esperado 4)")
		t.assert(alive.GetHP() == 100 and alive.GetStatus("__HardMark") == nil, "A ação adiada rodou na hora")

		local errors = engineErrorsDuring(function()
			cleanup(doomed) -- sai do jogo antes de a fila rodar
			frames(2)
		end)
		t.assert(alive.GetStatus("__HardMark") ~= nil, "O status adiado não chegou no alvo vivo")
		t.assert(alive.GetHP() == 90, "O dano adiado não chegou no alvo vivo (HP " .. alive.GetHP() .. ")")
		t.assert(StateTable.GetDeferredCount() == 0, "Sobrou ação na fila")
		t.assert(#errors == 0, "A ação adiada no alvo destruído deu erro: " .. tostring(errors[1]))
		cleanup(alive)
	end)

	--=========================================================================
	--  F55 — SKILL PORTÁVEL
	--=========================================================================

	run("F55 — skill de kit lê as animações do kit dono em qualquer corpo; skill solta, as de quem casta", function(t)
		local M1 = require(ServerStorage.DataBase.SkillDatabase.Schema.M1)
		local schemaBody = still(CFrame.new(-6, 5, 0), COMBAT) -- o loadout da Schema equipa o M1 pela chave
		t.assert(M1.data.kit == "Schema", "O EquipSkill não carimbou o kit do M1: " .. tostring(M1.data.kit))

		local thief = animated(CFrame.new(0, 5, 0), { "Character", "Health", "Status", "Combat", "Animation" },
			{ Combat = { ChosenChar = "__HardThief" } })
		local schemaLib = AnimationLib.character.Schema
		local stolen = SkillRunner.new(SkillFactory.GetSkill(M1), thief, M1.data.name, Types.Skill)
		t.assert(stolen.charLib ~= nil and stolen.charLib.M1 == schemaLib.M1,
			"No corpo de outro kit o M1 não achou as animações da Schema")
		t.assert(stolen.charLib.M1.M1Start == schemaLib.M1.M1Start, "ID de animação diferente do kit dono")

		local schemaAnimated = animated(CFrame.new(6, 5, 0), { "Character", "Health", "Status", "Combat", "Animation" })
		local loose = makeRunner(schemaAnimated, "__HardLoose", { duration = 1 }, {})
		t.assert(loose.charLib.S1 == schemaLib.S1, "A skill solta não usou a biblioteca de quem casta")
		local looseOnThief = makeRunner(thief, "__HardLoose2", { duration = 1 }, {})
		t.assert(looseOnThief.charLib.M1 == nil, "Skill solta num kit sem animações achou um conjunto")
		t.assert(not pcall(function() stolen.charLib.M1 = {} end), "A biblioteca da skill aceitou escrita")

		cleanup(schemaBody)
		cleanup(thief)
		cleanup(schemaAnimated)
	end)

	run("F55 — M1 num corpo sem Animation e sem Weapon é recusado: sem erro, sem cooldown, sem status preso", function(t)
		local body = still(CFrame.new(0, 5, 0), COMBAT) -- loadout da Schema: o M1 no Primary
		local M1 = require(ServerStorage.DataBase.SkillDatabase.Schema.M1)
		t.assert(body.GetSkillFromSlot(Intents.Id.Primary) == M1, "Pré-condição: o M1 não está no Primary")

		local ok
		local errors = engineErrorsDuring(function()
			ok = press(body, Intents.Id.Primary)
		end)
		t.assert(ok == false, "O cast foi aceito sem os componentes que o M1 declara")
		t.assert(#errors == 0, "O M1 deu erro em vez de ser recusado: " .. tostring(errors[1]))
		t.assert(not body.HasCooldown(M1.data.name), "O cooldown ficou cobrado")
		t.assert(#body.GetActiveSkills(M1.data.name) == 0, "Sobrou runner ativo")
		t.assert(body.GetStatus("NoControl") == nil, "O NoControl do M1 ficou preso no corpo")
		t.assert(body.GetActiveTags()[E.Tags.canMove] ~= false, "O corpo ficou sem andar")
		cleanup(body)
	end)

	--=========================================================================
	--  INPUT, MORTE E DESTRUIÇÃO
	--=========================================================================

	run("Duro — 60 toques no mesmo frame: 1 cast sem cargas; exatamente 3 com 3 cargas e 3 instâncias", function(t)
		local dummy = still(CFrame.new(0, 5, 0), COMBAT)
		local plain, charged = 0, 0
		equip(dummy, Intents.Id.Ability2, "__HardSpam", { cooldown = 5, duration = 0.2 }, {
			onStart = function() plain += 1 end })
		equip(dummy, Intents.Id.Ability3, "__HardSpamCharges", { cooldown = 5, duration = 0.2, maxInstances = 3,
			cooldownPolicy = { charges = 3 } }, { onStart = function() charged += 1 end })
		local accepted, acceptedCharged = 0, 0
		for _ = 1, 60 do
			if press(dummy, Intents.Id.Ability2) then accepted += 1 end
			if press(dummy, Intents.Id.Ability3) then acceptedCharged += 1 end
		end
		t.assert(plain == 1 and accepted == 1, string.format("Sem cargas: %d casts, %d aceitos", plain, accepted))
		t.assert(charged == 3 and acceptedCharged == 3, string.format("Com 3 cargas: %d casts, %d aceitos", charged, acceptedCharged))
		t.assert(dummy.GetCooldownCharges("__HardSpamCharges") == 0, "Sobrou carga depois de 3 casts")
		t.assert(#dummy.GetActiveSkills("__HardSpamCharges") == 3, "Instâncias vivas: " .. #dummy.GetActiveSkills("__HardSpamCharges"))
		t.wait(0.4)
		t.assert(#dummy.GetActiveSkills("__HardSpam") == 0 and #dummy.GetActiveSkills("__HardSpamCharges") == 0,
			"Runners ficaram ativos depois da duração")
		cleanup(dummy)
	end)

	run("Duro — morte no meio da skill: cancela com motivo, para o onStep, recusa cast; o Revive devolve", function(t)
		local dummy = still(CFrame.new(0, 5, 0), COMBAT)
		local steps, reason = 0, nil
		equip(dummy, Intents.Id.Ability2, "__HardDeath", { cooldown = 0, duration = 5 }, {
			onStep = function() steps += 1 end,
			onEnd = function(_, ctx) reason = ctx.reason end,
		})
		t.assert(press(dummy, Intents.Id.Ability2) == true, "O cast não começou")
		t.wait(0.15)
		local runner = dummy.GetActiveSkills("__HardDeath")[1]
		t.assert(runner ~= nil and steps > 0, "Pré-condição: a skill não estava rodando quando a entidade morreu")

		dummy.TakeDamage(10000)
		t.assert(not dummy.IsAlive(), "A entidade não morreu")
		local stepsAtDeath = steps
		t.wait(0.2)
		t.assert(runner:IsEnded() and reason == E.EndReasons.Cancel, "A morte não cancelou a skill (motivo " .. tostring(reason) .. ")")
		t.assert(steps == stepsAtDeath, string.format("O onStep seguiu depois da morte (%d -> %d)", stepsAtDeath, steps))
		t.assert(#dummy.GetActiveSkills("__HardDeath") == 0, "A skill ficou em ActiveSkills")
		t.assert(press(dummy, Intents.Id.Ability2) == false, "Morto castou")

		t.assert(dummy.Revive(100) == true and dummy.IsAlive(), "O Revive não devolveu a vida")
		t.assert(press(dummy, Intents.Id.Ability2) == true, "Depois do Revive o cast seguiu recusado")
		dummy.StopAllActiveSkills(true)
		cleanup(dummy)
	end)

	run("Duro — entidade destruída dentro do próprio onStep: sem erro, skill e status encerrados", function(t)
		local dummy = still(CFrame.new(0, 5, 0), COMBAT)
		local Long = { data = { name = "__HardLong", category = E.Categories.Buff }, callbacks = {} }
		dummy.ApplyStatus(Long, { Duration = 30 })
		local statusRunner = dummy.GetStatus("__HardLong")[1].runner
		local steps, destroyed = 0, false
		equip(dummy, Intents.Id.Ability2, "__HardSelfDestroy", { cooldown = 0, duration = 5 }, {
			onStep = function()
				steps += 1
				if steps == 3 and not destroyed then
					destroyed = true
					cleanup(dummy)
				end
			end,
		})
		local runner
		local errors = engineErrorsDuring(function()
			press(dummy, Intents.Id.Ability2)
			runner = dummy.GetActiveSkills("__HardSelfDestroy")[1]
			t.wait(0.3)
		end)
		t.assert(destroyed, "Pré-condição: a entidade não foi destruída no onStep")
		t.assert(#errors == 0, "Destruir no onStep deu erro: " .. tostring(errors[1]))
		t.assert(runner and runner:IsEnded(), "A skill seguiu viva depois da entidade sair")
		t.assert(statusRunner:IsEnded(), "O status seguiu vivo depois da entidade sair")
		t.assert(steps == 3, "O onStep rodou " .. steps .. " vezes (a entidade saiu no 3º)")
	end)

	--=========================================================================
	--  STATUS
	--=========================================================================

	run("Duro — 400 aplicações e remoções aleatórias de status: invariantes no meio e nada vivo no fim", function(t)
		local dummy = still(CFrame.new(0, 5, 0))
		local rng = Random.new(62)
		local Unique = { data = { name = "__HUnique", category = E.Categories.Buff, tags = { [E.Tags.canMove] = false } }, callbacks = {} }
		local Stack = { data = { name = "__HStack", category = E.Categories.Buff, maxStacks = 4,
			traits = { E.Traits.Stackable } }, callbacks = {} }
		local OnSelf = { data = { name = "__HOnSelf", category = E.Categories.Buff, maxStacks = 4, stackOnSelf = true,
			traits = { E.Traits.Stackable } }, callbacks = {} }
		local ExA = { data = { name = "__HExA", category = E.Categories.Debuff, exclusive = true }, callbacks = {} }
		local ExB = { data = { name = "__HExB", category = E.Categories.Debuff, exclusive = true }, callbacks = {} }
		local all = { Unique, Stack, OnSelf, ExA, ExB }
		local runners, ids, violations = {}, {}, {}

		local function remember()
			for _, s in all do
				for _, entry in dummy.GetStatus(s.data.name) or {} do
					if entry.runner then runners[entry.runner] = true end
				end
			end
		end
		local function check(step)
			local stacks = #(dummy.GetStatus("__HStack") or {})
			if stacks > 4 then table.insert(violations, step .. ": " .. stacks .. " instâncias (máx 4)") end
			local onSelf = dummy.GetStatusCounter("__HOnSelf")
			if onSelf > 4 then table.insert(violations, step .. ": stackOnSelf em " .. onSelf .. " (máx 4)") end
			if dummy.GetStatus("__HExA") and dummy.GetStatus("__HExB") then
				table.insert(violations, step .. ": dois exclusivos da mesma categoria juntos")
			end
		end

		local errors = engineErrorsDuring(function()
			for step = 1, 400 do
				local op = rng:NextInteger(1, 8)
				if op <= 4 then
					local s = all[rng:NextInteger(1, #all)]
					local id = dummy.ApplyStatus(s, { Duration = rng:NextNumber(0.02, 0.3) })
					if id then table.insert(ids, id) end
				elseif op == 5 then
					dummy.RemoveStatus(all[rng:NextInteger(1, #all)].data.name)
				elseif op == 6 and #ids > 0 then
					dummy.RemoveStatusByID(ids[rng:NextInteger(1, #ids)])
				elseif op == 7 then
					dummy.RemoveAmount(rng:NextInteger(0, 1) == 0 and "__HStack" or "__HOnSelf", rng:NextInteger(1, 3))
				else
					remember()
				end
				remember()
				check(step)
				if step % 25 == 0 then task.wait() end -- deixa parte expirar no meio
			end
		end)
		t.wait(0.5) -- tudo expira

		local alive = 0
		for runner in runners do if not runner:IsEnded() then alive += 1 end end
		local status = dummy:GetComponent(dummy.ComponentKey.Status)
		local leftover = 0
		for _, group in status.Effects do for _ in group do leftover += 1 end end
		local count = 0
		for _ in runners do count += 1 end
		t.log(string.format("%d runners de status vistos, %d IDs", count, #ids))
		t.assert(#violations == 0, "Invariante quebrada: " .. tostring(violations[1]))
		t.assert(#errors == 0, "Erro do motor: " .. tostring(errors[1]))
		t.assert(alive == 0, alive .. " runner(s) de status seguiram vivos depois de expirar tudo")
		t.assert(leftover == 0, leftover .. " entrada(s) sobraram no registro de status")
		t.assert(dummy.GetActiveTags()[E.Tags.canMove] ~= false, "A tag canMove ficou presa em false")
		cleanup(dummy)
	end)

	run("Duro — status que se renova no onEnd, tirado por RemoveAmount, não deixa instância órfã", function(t)
		local dummy = still(CFrame.new(0, 5, 0))
		local renewals = 0
		local Renew
		Renew = { data = { name = "__HardRenew", category = E.Categories.Buff, tags = { [E.Tags.canMove] = false } }, callbacks = {
			onEnd = function(self, ctx)
				if ctx.reason == E.EndReasons.Cancel and renewals < 1 then
					renewals += 1
					self.Entity.ApplyStatus(Renew, { Duration = 30 }) -- volta sozinho (ex.: maldição que não sai)
				end
			end,
		} }
		dummy.ApplyStatus(Renew, { Duration = 30 })
		dummy.RemoveAmount("__HardRenew", 1)
		t.assert(renewals == 1, "Pré-condição: o status não se reaplicou no onEnd")

		-- O que voltou tem de estar no registro: listado, com tags valendo e removível
		local entry = dummy.GetStatus("__HardRenew")
		t.assert(entry ~= nil and entry[1].runner and not entry[1].runner:IsEnded(),
			"O status reaplicado no onEnd sumiu do registro (runner órfão, rodando fora dele)")
		t.assert(dummy.GetActiveTags()[E.Tags.canMove] == false, "As tags do status reaplicado não valem")
		local runner = entry[1].runner
		dummy.RemoveStatus("__HardRenew")
		t.assert(runner:IsEnded(), "O status reaplicado não pôde ser removido")
		cleanup(dummy)
	end)

	--=========================================================================
	--  DANO E EVENTOS
	--=========================================================================

	run("Duro — fórmula de dano: 300 casos aleatórios batem com a referência (Defense, Armor, DamageMult, TrueDamage)", function(t)
		local attacker = still(CFrame.new(-4, 5, 0), COMBAT)
		-- HP de 1e6: 300 hits cabem, e o ulp do double em 1e6 (~1e-10) fica longe da tolerância
		local target = still(CFrame.new(4, 5, 0), { "Character", "Health", "Attributes" },
			{ Health = { MaxHP = 1e6 }, Attributes = { BaseStats = { MaxHP = 1e6 } } })
		local normal = makeRunner(attacker, "__HardHit", { duration = 30 }, {})
		local pierce = makeRunner(attacker, "__HardPierce", { duration = 30, traits = { E.Traits.TrueDamage } }, {})
		normal:start()
		pierce:start()
		local rng = Random.new(43)
		local worst, worstCase = 0, ""
		for i = 1, 300 do
			local base = rng:NextNumber(0, 200)
			local mult = rng:NextNumber(0, 3)
			local defense = rng:NextNumber(-80, 300)
			local armor = rng:NextNumber(0, 60)
			local trueDamage = rng:NextInteger(0, 3) == 0
			attacker.SetStat(E.Stats.DamageMult, mult)
			target.SetStat(E.Stats.Defense, defense)
			target.SetStat(E.Stats.Armor, armor)

			local expected = base * mult
			if not trueDamage then
				expected *= defense >= 0 and 100 / (100 + defense) or (2 - 100 / (100 - defense))
				expected = math.max(0, expected - armor)
			end
			local hp = target.GetHP()
			local _, dealt = (trueDamage and pierce or normal):Damage(target, base)
			local actual = hp - target.GetHP()
			local err = math.abs(actual - expected)
			if err > worst then
				worst = err
				worstCase = string.format("#%d base %.2f mult %.2f def %.1f armor %.1f true %s: %.4f vs %.4f (retorno %s)",
					i, base, mult, defense, armor, tostring(trueDamage), actual, expected, tostring(dealt))
			end
		end
		t.log("maior diferença: " .. string.format("%.2e", worst) .. (worst > 0 and (" em " .. worstCase) or ""))
		t.assert(worst < 1e-6, "O dano saiu da fórmula declarada: " .. worstCase)
		normal:endSkill(false)
		pierce:endSkill(false)
		cleanup(attacker)
		cleanup(target)
	end)

	run("Duro — DOT que mata credita quem aplicou: OUT.OnDeath no aplicador, não no portador", function(t)
		local caster = still(CFrame.new(-4, 5, 0), COMBAT)
		local victim = still(CFrame.new(4, 5, 0))
		local src = makeRunner(caster, "__HardBleeder", { duration = 10 }, {})
		src:start()
		local creditCaster, creditVictim, origin, dotTraits = 0, 0, nil, nil
		caster:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDeath, Owner = src, Action = function(ctx)
			if ctx.targetEntity == victim then creditCaster += 1 end
		end })
		victim:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDeath, Action = function() creditVictim += 1 end })
		victim:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.PostDamage, Action = function(ctx)
			origin = ctx.Lineage and ctx.Lineage.Origin
			dotTraits = ctx.traits
		end })
		victim.SetHP(2) -- Bleed: 1 de dano por tick (0,3 s): morre no 2º tick
		src:ApplyStatus(StateTable.Status.Bleed, { Target = victim, Duration = 5 })
		t.wait(1.2)
		t.assert(not victim.IsAlive(), "Pré-condição: o Bleed não matou")
		t.assert(origin == caster, "A raiz da cadeia do dano do Bleed não é quem aplicou")
		t.assert(dotTraits and table.find(dotTraits, E.Traits.DOT) ~= nil, "O dano do Bleed chegou sem a trait DOT")
		t.assert(creditCaster == 1 and creditVictim == 0, string.format(
			"Crédito da morte: aplicador %d, portador %d (esperado 1 e 0: a vítima se credita a própria morte)", creditCaster, creditVictim))
		src:endSkill(false)
		cleanup(caster)
		cleanup(victim)
	end)

	run("Duro — possessão IA em sequência (3 mentes), Release e posse sem AIComponent: volta exatamente ao nativo", function(t)
		local body = still(CFrame.new(-4, 5, 0), { "Character", "Health", "Movement", "Control", "AI" })
		local ticks = { native = 0, a = 0, b = 0, c = 0 }
		local native = function() ticks.native += 1 end
		body.SetBrain(native)
		for _, name in { "a", "b", "c" } do
			t.assert(body.Possess({ AI = true, Brain = function() ticks[name] += 1 end }), "Possess " .. name .. " recusado")
		end
		ticks.native, ticks.a, ticks.b, ticks.c = 0, 0, 0, 0
		t.wait(0.3)
		t.assert(ticks.c > 0 and ticks.native + ticks.a + ticks.b == 0,
			string.format("Na posse só a última mente dirige (nativa %d, a %d, b %d, c %d)", ticks.native, ticks.a, ticks.b, ticks.c))
		t.assert(body.Release(), "Release recusado")
		t.assert(not body.Release(), "2º Release achou posse para soltar")
		t.assert(body.GetBrain() == native and body.IsAIEnabled(), "O Release não devolveu a mente nativa (devolveu uma intermediária?)")
		ticks.native, ticks.c = 0, 0
		t.wait(0.3)
		t.assert(ticks.native > 0 and ticks.c == 0, "Depois do Release a mente nativa não voltou a rodar sozinha")

		-- Corpo sem AIComponent: a posse cria um e o Release o tira (Regra 5: entidade simples fica simples)
		local bare = still(CFrame.new(4, 5, 0), { "Character", "Health", "Movement", "Control" })
		local bareTicks = 0
		t.assert(bare.Possess({ AI = true, Brain = function() bareTicks += 1 end }), "Possess num corpo sem AI recusado")
		t.wait(0.2)
		t.assert(bareTicks > 0, "A mente não rodou no corpo sem AIComponent")
		t.assert(bare.Release() and not bare:HasComponent(bare.ComponentKey.AI), "O AIComponent da posse ficou no corpo")

		-- Corpo destruído no meio da posse: sem erro
		local doomedTicks = 0
		t.assert(bare.Possess({ AI = true, Brain = function() doomedTicks += 1 end }), "2ª posse recusada")
		local errors = engineErrorsDuring(function()
			cleanup(bare)
			t.wait(0.2)
		end)
		local after = doomedTicks
		t.wait(0.2)
		t.assert(#errors == 0, "Destruir o corpo possuído deu erro: " .. tostring(errors[1]))
		t.assert(doomedTicks == after, "A mente seguiu rodando num corpo destruído")
		cleanup(body)
	end)

	run("Duro — TriggerSet mudando durante o Emit: remoção, inscrição nova, prioridade, Limit, TTD e erro isolado", function(t)
		local e = still(CFrame.new(0, 5, 0))
		local BP = "__HardEmit"
		local order = {}
		local function listen(name, priority, extra)
			local sub = { Role = E.Roles.IN, Breakpoint = BP, Priority = priority, Action = function()
				table.insert(order, name)
				if extra then extra() end
			end }
			return e:Listen(sub), sub
		end
		local unsubscribeB
		local addedLate = false
		listen("A", 10, function()
			if unsubscribeB then unsubscribeB(); unsubscribeB = nil end
			if not addedLate then
				addedLate = true
				listen("Late", 100)
			end
		end)
		unsubscribeB = listen("B", 5)
		listen("C", 5)
		e:Listen({ Role = E.Roles.IN, Breakpoint = BP, Priority = 7, Action = function() error("falha de propósito") end })
		e:Listen({ Role = E.Roles.IN, Breakpoint = BP, Priority = 1, Limit = { Max = 2, OnExhaust = "Remove" },
			Action = function() table.insert(order, "Twice") end })
		e:Listen({ Role = E.Roles.IN, Breakpoint = BP, Priority = 1, Limit = { Max = 1, OnExhaust = "Disable" },
			Action = function() table.insert(order, "Once") end })
		e:Listen({ Role = E.Roles.IN, Breakpoint = BP, Priority = 0, TTD = 0.15, Action = function() table.insert(order, "TTD") end })

		local errorsSeen
		local errors = engineErrorsDuring(function()
			e:Emit(E.Roles.IN, BP, {})
		end)
		errorsSeen = #errors
		local first = table.concat(order, ",")
		table.clear(order)
		e:Emit(E.Roles.IN, BP, {})
		local second = table.concat(order, ",")
		table.clear(order)
		t.wait(0.2)
		e:Emit(E.Roles.IN, BP, {})
		local third = table.concat(order, ",")
		t.log("1º: " .. first .. " | 2º: " .. second .. " | 3º: " .. third)
		-- 1º: B saiu no meio (não roda), o Late entrou no meio (só no próximo); o erro não para a fila
		t.assert(first == "A,C,Twice,Once,TTD", "1º Emit: " .. first)
		t.assert(errorsSeen == 1, "O erro do listener não apareceu (ou apareceu " .. errorsSeen .. " vezes)")
		t.assert(second == "Late,A,C,Twice,TTD", "2º Emit: " .. second)
		t.assert(third == "Late,A,C", "3º Emit (Twice esgotado, Once desligado, TTD vencido): " .. third)
		cleanup(e)
	end)

	--=========================================================================
	--  EVENTOS, STATS, DANO INDIRETO E ARMA (2ª rodada de 22/11)
	--=========================================================================

	run("F99 — Events.onDamage do config do Health dispara quando a entidade apanha", function(t)
		local seen = { lower = 0, upper = 0, damage = nil }
		local a = still(CFrame.new(-4, 5, 0), LIGHT, { Health = { Events = {
			onDamage = function(ctx) seen.lower += 1; seen.damage = ctx.actualDamage end } } })
		local b = still(CFrame.new(4, 5, 0), LIGHT, { Health = { Events = {
			OnDamage = function() seen.upper += 1 end } } })
		a.TakeDamage(5)
		b.TakeDamage(5)
		t.assert(seen.lower == 1 and seen.damage == 5, string.format("Events.onDamage rodou %d vez(es) (dano %s)",
			seen.lower, tostring(seen.damage)))
		t.assert(seen.upper == 1, "Events.OnDamage (maiúscula) rodou " .. seen.upper .. " vez(es)")
		local Core = require(ServerScriptService.EntityData.EntityCore)
		t.assert(Core.Events.onDamage == E.Breakpoints.PostDamage,
			"EntityCore.Events.onDamage aponta para " .. tostring(Core.Events.onDamage) .. ", que não é emitido no canal IN")
		cleanup(a)
		cleanup(b)
	end)

	run("F100 — limite de stat igual com e sem modificador; Defense negativa amplifica também por debuff", function(t)
		local e = still(CFrame.new(0, 5, 0), { "Character", "Health", "Attributes" })
		e.SetStat(E.Stats.Defense, -50)
		t.assert(e.GetStat(E.Stats.Defense) == -50, "Defense −50 na base: " .. tostring(e.GetStat(E.Stats.Defense)))
		e.SetStat(E.Stats.Defense, 0)
		e.AddModifier(E.Stats.Defense, "__HardShred", E.ModifierType.Flat, -50)
		t.assert(e.GetStat(E.Stats.Defense) == -50,
			"Defense −50 por debuff virou " .. tostring(e.GetStat(E.Stats.Defense)) .. " (o piso só valia com modificador)")
		e.RemoveModifier(E.Stats.Defense, "__HardShred")
		e.SetStat(E.Stats.Speed, -5)
		t.assert(e.GetStat(E.Stats.Speed) == 0, "Speed −5 na base passou o piso: " .. tostring(e.GetStat(E.Stats.Speed)))
		e.SetStat(E.Stats.Speed, 16)
		e.AddModifier(E.Stats.Speed, "__HardSlow", E.ModifierType.Flat, -30)
		t.assert(e.GetStat(E.Stats.Speed) == 0, "Speed com slow de −30 ficou " .. tostring(e.GetStat(E.Stats.Speed)))
		e.SetStat(E.Stats.Weapon, "Martelo")
		t.assert(e.GetStat(E.Stats.Weapon) == "Martelo", "Stat de texto foi tratado como número")
		cleanup(e)
	end)

	run("F101 — dano indireto (DOT) emite OUT.OnDamage no dono, com a trait DOT; hit direto, uma vez só", function(t)
		local caster = still(CFrame.new(-4, 5, 0), COMBAT)
		local victim = still(CFrame.new(4, 5, 0), LIGHT, { Health = { MaxHP = 1000 } })
		local src = makeRunner(caster, "__HardOwner", { duration = 10 }, {})
		src:start()
		local dot, direct, noDot, wrongTarget, wrongOwner, sourceIsVictim = 0, 0, 0, 0, 0, 0
		caster:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDamage, Owner = src, Action = function(ctx)
			if table.find(ctx.traits, E.Traits.DOT) then dot += 1 else direct += 1 end
			if ctx.targetEntity ~= victim then wrongTarget += 1 end
			if ctx.ownerEntity ~= caster then wrongOwner += 1 end
			if table.find(ctx.traits, E.Traits.DOT) and ctx.sourceEntity == victim then sourceIsVictim += 1 end
		end })
		caster:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDamage, Owner = src,
			Query = { None = { E.Traits.DOT } }, Action = function() noDot += 1 end })

		src:Damage(victim, 5)
		t.assert(direct == 1, "Hit direto emitiu OUT.OnDamage " .. direct .. " vez(es) (esperado 1)")
		src:ApplyStatus(StateTable.Status.Bleed, { Target = victim, Duration = 1 })
		t.wait(1.2)
		t.log(string.format("ticks de DOT com OUT.OnDamage %d; hit direto %d; filtro None={DOT} %d", dot, direct, noDot))
		t.assert(dot >= 2, "O DOT não emitiu OUT.OnDamage no dono (" .. dot .. " ticks)")
		t.assert(noDot == 1, "O filtro None = { DOT } recebeu " .. noDot .. " evento(s) (esperado só o hit direto)")
		t.assert(wrongTarget == 0 and wrongOwner == 0, string.format("targetEntity errado %d, ownerEntity errado %d", wrongTarget, wrongOwner))
		t.assert(sourceIsVictim == dot, "sourceEntity do DOT mudou de significado (devia seguir sendo o portador)")
		src:endSkill(false)
		cleanup(caster)
		cleanup(victim)
	end)

	run("F102 — M1 da Schema roubado por um corpo de outro kit: equipa o Martelo e o golpe roda inteiro", function(t)
		local M1 = require(ServerStorage.DataBase.SkillDatabase.Schema.M1)
		local rig = workspace.Rig:Clone()
		rig:PivotTo(env.origin() * CFrame.new(0, 5, 0))
		rig.Parent = workspace
		local thief = DataManager.Create(rig, { "Character", "Health", "Status", "Attributes", "Combat", "Weapon", "Animation" },
			{ Combat = { ChosenChar = "__HardThief" }, Weapon = { WeaponName = "Martelo" } })
		t.assert(thief.HasWeapon(), "O corpo de outro kit não equipou o Martelo (arma presa ao nome do personagem)")
		local data = thief.GetWeaponData()
		t.assert(data and data.BaseName == "Martelo" and thief.GetCurrentMode() == data.DefaultMode,
			"A arma de outro kit ficou sem WeaponData ou sem modo")

		thief.EquipSkill(Intents.Id.Primary, M1)
		local ok, runner
		local errors = engineErrorsDuring(function()
			ok = press(thief, Intents.Id.Primary)
			runner = thief.GetActiveSkills(M1.data.name)[1]
		end)
		t.assert(ok == true and runner ~= nil, "O M1 roubado não foi castado no corpo de outro kit")
		t.assert(#errors == 0, "O M1 roubado deu erro: " .. tostring(errors[1]))
		t.assert(runner.charLib.M1 == AnimationLib.character.Schema.M1, "O M1 roubado não usou as animações da Schema")
		t.assert(thief.GetStatus("NoControl") ~= nil, "O onStart do M1 não chegou ao fim (NoControl não aplicado)")
		thief.StopAllActiveSkills(true)
		t.assert(thief.GetStatus("NoControl") == nil, "A limpeza do M1 não tirou o NoControl")

		-- Nome em dois kits é ambíguo: sem kit explícito não escolhe; com kit, equipa
		local fakeKit = Instance.new("Folder")
		fakeKit.Name = "__HardKit"
		local fakeWeapon = Instance.new("Folder")
		fakeWeapon.Name = "Martelo"
		fakeWeapon.Parent = fakeKit
		fakeKit.Parent = game:GetService("ReplicatedStorage").Assets.Weapons
		local ambiguous = thief.EquipWeapon("Martelo")
		local explicit = thief.EquipWeapon("Martelo", "Schema")
		fakeKit:Destroy()
		t.assert(ambiguous == false and thief.HasWeapon(), "Com o nome em dois kits, o EquipWeapon escolheu sozinho (ou soltou a arma)")
		t.assert(explicit == true, "Com o kit explícito o EquipWeapon falhou")
		cleanup(thief)
	end)

	--=========================================================================
	--  AGARRÃO, ALVO, PERSONAGEM, CURA E OPÇÕES DO HIT (3ª rodada de 22/11)
	--=========================================================================

	run("F103 — AttachTo: preso sem erro em movimento rápido; solta tudo no release e quando o líder some", function(t)
		local LIMB = { "Character", "Health", "Movement" }
		local leader = makeDummy(CFrame.new(-10, 3, 0), LIMB)
		local follower = makeDummy(CFrame.new(-10, 3, 4), LIMB)
		local root = follower.GetRoot()
		t.wait(0.3)
		local release = follower.AttachTo(leader.GetRoot(), CFrame.new(0, 0, 4))
		t.assert(release ~= nil, "O AttachTo recusou")
		leader.AddForce({ Type = "__HardRun", Duration = 1, Speed = 60, Direction = Vector3.new(1, 0, 0),
			Hard = true, IgnoreGravity = true, FaceDirection = false })
		t.wait(0.6)
		local speed = leader.GetRoot().AssemblyLinearVelocity.Magnitude
		local desired = leader.GetRoot().CFrame:PointToWorldSpace(Vector3.new(0, 0, 4))
		local err = (root.Position - desired).Magnitude
		t.log(string.format("líder a %.0f studs/s; erro do preso %.3f studs", speed, err))
		t.assert(speed > 40, "Pré-condição: o líder não estava em movimento rápido")
		t.assert(err < 0.05, string.format("O preso saiu do lugar: %.2f studs", err))
		t.assert(root.Massless, "O preso pesa no líder (não ficou sem massa)")

		release()
		release() -- idempotente
		t.assert(follower.GetAttachment() == nil and not root:FindFirstChild("_FWAttach"), "O release deixou o weld")
		t.assert(not root.Massless, "O release não devolveu a massa")

		-- Líder some com o preso: o weld quebra e o controller solta a entidade sozinho
		follower.AttachTo(leader.GetRoot(), CFrame.new(0, 0, 4))
		cleanup(leader)
		t.wait(0.2)
		t.assert(follower.GetAttachment() == nil, "Com o líder fora do jogo, o preso seguiu marcado como preso")
		t.assert(not root.Massless, "Com o líder fora do jogo, o preso ficou sem massa")
		cleanup(follower)
	end)

	run("F105 — alvo por time: a hitbox da skill pula aliado e ela mesma; data.affects muda; zona com filtro", function(t)
		local TEAMED = { "Character", "Health", "Status", "Affiliation" }
		local attacker = still(CFrame.new(0, 5, 6), { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "Affiliation" },
			{ Affiliation = { Team = "Red" }, Combat = { ChosenChar = false } })
		local ally = still(CFrame.new(-5, 5, -6), TEAMED, { Affiliation = { Team = "Red" } })
		local enemy = still(CFrame.new(5, 5, -6), TEAMED, { Affiliation = { Team = "Blue" } })
		local neutral = still(CFrame.new(0, 5, -6))
		local R = E.Relations
		t.assert(StateTable.Relation(attacker, ally) == R.Ally and StateTable.Relation(attacker, enemy) == R.Enemy
			and StateTable.Relation(attacker, neutral) == R.Neutral and StateTable.Relation(attacker, attacker) == R.Self,
			"Relações erradas")

		-- O caminho real de entrega do acerto da arma (_handleHit) com a skill como dona
		local hits = {}
		local runner = makeRunner(attacker, "__HardTeamHit", { duration = 5 }, {
			onHit = function(_, hitResult) table.insert(hits, hitResult.target) end })
		runner:start()
		local wrapper = { DataManager = DataManager }
		local session = { hitTargets = {} }
		local function hit(target)
			local r = target.GetRoot()
			HitboxWrapper._class._handleHit(wrapper, { Instance = r, Position = r.Position, Normal = Vector3.yAxis, Distance = 1 },
				nil, { name = "__HardBlade" }, session, runner)
		end
		for _, target in { ally, enemy, neutral, attacker } do hit(target) end
		t.assert(#hits == 2 and table.find(hits, enemy) and table.find(hits, neutral),
			"A hitbox entregou " .. #hits .. " acerto(s); esperado só o inimigo e o neutro")
		runner.skill.data.affects = { Ally = true } -- cura em área, buff de aliado
		hit(ally)
		t.assert(table.find(hits, ally) ~= nil, "Com affects.Ally a hitbox não acertou o aliado (ou o filtro gastou o acerto)")

		-- Zona com o filtro do atacante (padrão: inimigo e neutro)
		local zone = AreaEffect.new(function() return env.origin() * CFrame.new(0, 5, -6) end, "Box", Vector3.new(16, 10, 6), 20)
		zone:SetFilter(StateTable.AffectsFilter(attacker))
		local entered = {}
		zone:OnEnter(function(entity) entered[entity] = true end)
		zone:Start()
		t.wait(0.25)
		zone:Stop()
		t.assert(entered[enemy] and entered[neutral] and not entered[ally], "A zona com filtro não respeitou o time")
		runner:endSkill(false)
		for _, e in { attacker, ally, enemy, neutral } do cleanup(e) end
	end)

	run("F106 — Combat sem personagem: sem aviso e sem loadout do banco; o kit montado em runtime funciona", function(t)
		local warned = {}
		local conn = LogService.MessageOut:Connect(function(message)
			if string.find(message, "Char não existe") or string.find(message, "AnimLib não encontrada") then
				table.insert(warned, message)
			end
		end)
		local bare = still(CFrame.new(-4, 5, 0), COMBAT, { Combat = { ChosenChar = false } })
		task.wait()
		task.wait()
		conn:Disconnect()
		t.assert(bare.GetChosenChar() == nil, "ChosenChar = false virou " .. tostring(bare.GetChosenChar()))
		t.assert(bare.GetSkillFromSlot(Intents.Id.Primary) == nil, "A entidade sem personagem nasceu com o loadout do banco")
		t.assert(#warned == 0, "Aviso de personagem inexistente: " .. tostring(warned[1]))
		local started = 0
		equip(bare, Intents.Id.Ability2, "__HardBareSkill", { cooldown = 0, duration = 0.1 }, { onStart = function() started += 1 end })
		t.assert(press(bare, Intents.Id.Ability2) == true and started == 1, "O kit montado em runtime não castou")
		local default = still(CFrame.new(4, 5, 0), COMBAT)
		t.assert(default.GetChosenChar() == E.CombatDefaults.ChosenChar, "Sem config o personagem não é o padrão do jogo")
		cleanup(bare)
		cleanup(default)
	end)
end

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
end

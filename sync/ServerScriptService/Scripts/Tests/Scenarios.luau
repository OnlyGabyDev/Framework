--[[
Cenários de integração: substituem a GrandIntegrationDemo (removida em 11/11/2026).

A demo só imprimia warns e possuía o player por 30 s no meio do Play. Aqui cada parte vira um
teste com asserção, na faixa própria do IntegrationTests e com limpeza no fim:

	1. IA persegue o alvo pelo mesmo pipeline do input (SkillHandler.HandleMovementInput)
	2. Dash marca o combo, o finisher consome, agarra (FollowTarget) e bate mais forte
	3. IA possui IA: a mente nova dirige e o Release devolve a original
	4. Possessão dupla com o player: a IA do corpo possuído pausa, o corpo nativo ganha uma IA,
	   e o Release devolve tudo (pulado sem player)

O Fork de OUT.onHit do minion pro pai, que a demo também mostrava, já é o teste "Sprint 10".
Chamado pelo IntegrationTests com os helpers dele (env), antes do Summary.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.EntityData.DataManager)
local SkillHandler = require(ServerScriptService.Modules.SkillHandler)
local AntiCheat = require(ServerScriptService.Modules.GlobalAntiCheat)
local BaseSkills = require(ServerStorage.DataBase.SkillDatabase.BaseSkills)

local COMBO_KEY = "ScenarioCombo"
local GRAB_OFFSET = Vector3.new(0, 0, -3)
local DAMAGE_COMBO, DAMAGE_PLAIN = 5, 1

local function flatDistance(a: any, b: any): number
	local delta = a.GetRoot().Position - b.GetRoot().Position
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

-- Mente de perseguição: produz input exatamente como um player (Regra 7)
local function chaseBrain(target: any)
	return function(entity, _dt)
		local toTarget = target.GetRoot().Position - entity.GetRoot().Position
		SkillHandler.HandleMovementInput(entity.ID, Vector3.new(toTarget.X, 0, toTarget.Z))
	end
end

-- Skills inline do cenário 2 (mesmo desenho das da demo, com alvo e direção explícitos)
local function dashCallbacks(target: any)
	return {
		onStart = function(self)
			local toTarget = target.GetRoot().Position - self.Entity.GetRoot().Position
			local dir = Vector3.new(toTarget.X, 0, toTarget.Z).Unit
			self.forceID = self.Entity.AddForce({
				Type = "ScenarioDash", Duration = self.data.duration, Speed = 20,
				Direction = dir, Hard = true, IgnoreGravity = true, Priority = 10,
			})
			BaseSkills.ComboWindow.Mark(self.Entity, COMBO_KEY, 1, { Direction = dir }, self.Runner)
		end,
		onEnd = function(self)
			if self.forceID then self.Entity.RemoveForce(self.forceID) end
		end,
	}
end

local function finisherCallbacks(target: any, report: { [string]: any })
	return {
		onStart = function(self)
			local comboed = BaseSkills.ComboWindow.Consume(self.Entity, COMBO_KEY) ~= nil
			report.comboed = comboed
			if comboed then
				self.grabForceID = target.AddForce({
					Type = "ScenarioGrab", Duration = self.data.duration, Hard = true,
					IgnoreGravity = true, RequiresControl = false,
					FollowTarget = function() return self.Entity.GetRoot() end,
					FollowOffset = GRAB_OFFSET, FollowOffsetIsLocal = true,
					FollowResponsiveness = 18, FollowMaxSpeed = 80,
				})
			end
			report.hit = target.TakeDamage(comboed and DAMAGE_COMBO or DAMAGE_PLAIN, self.Runner)
		end,
		onEnd = function(self)
			if self.grabForceID then target.RemoveForce(self.grabForceID) end
		end,
	}
end

return function(env)
	local run, makeDummy, cleanup, makeRunner = env.run, env.makeDummy, env.cleanup, env.makeRunner
	local FIGHTER = { "Character", "Health", "Movement", "Status" }

	run("Cenário 1 — IA persegue o alvo pelo pipeline do input", function(t)
		local target = makeDummy(CFrame.new(0, 5, -20), FIGHTER)
		local hunter = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Status", "Control", "AI" })
		hunter.SetMovement()
		target.SetMovement()
		local before = flatDistance(hunter, target)
		hunter.SetBrain(chaseBrain(target))
		t.assert(hunter.IsAIEnabled(), "A IA nasceu desligada")
		t.wait(1.5)
		local after = flatDistance(hunter, target)
		t.log(string.format("distância %.1f -> %.1f", before, after))
		t.assert(after < before - 5, string.format("O hunter não se aproximou (%.1f -> %.1f)", before, after))
		cleanup(hunter)
		cleanup(target)
	end)

	run("Cenário 2 — dash marca o combo; o finisher consome, agarra e bate mais forte", function(t)
		local hunter = makeDummy(CFrame.new(0, 5, 0), FIGHTER)
		local target = makeDummy(CFrame.new(0, 5, -8), FIGHTER)
		hunter.SetMovement()
		target.SetMovement()
		t.wait(0.2)

		-- Sem combo: dano simples e nenhum grab
		local plain = {}
		local hp0 = target.GetHP()
		makeRunner(hunter, "ScenarioFinisherPlain", { cooldown = 0, duration = 0.3, castTime = 0 },
			finisherCallbacks(target, plain)):start()
		t.assert(plain.comboed == false, "Consumiu um combo que ninguém marcou")
		t.assert(plain.hit, "O golpe simples não conectou")
		t.assert(hp0 - target.GetHP() == DAMAGE_PLAIN, string.format("Dano simples %s, esperado %d", tostring(hp0 - target.GetHP()), DAMAGE_PLAIN))
		t.wait(0.4)

		-- Dash (marca) e finisher (consome, agarra, dano maior)
		makeRunner(hunter, "ScenarioDash", { cooldown = 0, duration = 0.2, castTime = 0 }, dashCallbacks(target)):start()
		t.wait(0.3)
		local combo = {}
		local hp1 = target.GetHP()
		makeRunner(hunter, "ScenarioFinisher", { cooldown = 0, duration = 1, castTime = 0 },
			finisherCallbacks(target, combo)):start()
		t.assert(combo.comboed == true, "O finisher não consumiu o combo do dash")
		t.assert(hp1 - target.GetHP() == DAMAGE_COMBO, string.format("Dano com combo %s, esperado %d", tostring(hp1 - target.GetHP()), DAMAGE_COMBO))
		t.assert(BaseSkills.ComboWindow.Consume(hunter, COMBO_KEY) == nil, "O combo sobrou depois de consumido")

		t.wait(0.6)
		local anchor = hunter.GetRoot().CFrame * GRAB_OFFSET
		-- Erro no plano, com o mesmo limite do teste do F19 (a altura de repouso dos dois difere)
		local grabError = ((target.GetRoot().Position - anchor) * Vector3.new(1, 0, 1)).Magnitude
		t.log(string.format("erro do grab: %.2f studs", grabError))
		t.assert(grabError < 2, string.format("O alvo não seguiu o ponto de grab (%.2f studs)", grabError))

		t.wait(0.6) -- o finisher acabou: o grab tem que ter saído junto
		local movement = target:GetComponent(target.ComponentKey.Movement)
		t.assert(next(movement.ActiveForces) == nil, "O grab ficou ativo depois do fim do finisher")
		cleanup(hunter)
		cleanup(target)
	end)

	run("Cenário 3 — IA possui IA: a mente nova dirige e o Release devolve a original", function(t)
		local body = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Control", "AI" })
		local nativeTicks, foreignTicks = 0, 0
		local nativeBrain = function() nativeTicks += 1 end
		local foreignBrain = function() foreignTicks += 1 end
		body.SetBrain(nativeBrain)

		t.assert(body.Possess({ AI = true, Brain = foreignBrain }), "Possess por IA recusado")
		t.assert(body.GetBrain() == foreignBrain, "A mente estrangeira não assumiu")
		nativeTicks = 0
		t.wait(0.3)
		t.assert(foreignTicks > 0 and nativeTicks == 0, string.format("Ticks durante a posse: estrangeira %d, nativa %d", foreignTicks, nativeTicks))

		t.assert(body.Release(), "Release sem posse ativa")
		t.assert(body.GetBrain() == nativeBrain and body.IsAIEnabled(), "O Release não devolveu a mente nativa ligada")
		foreignTicks = 0
		t.wait(0.3)
		t.assert(nativeTicks > 0 and foreignTicks == 0, "A mente estrangeira continuou rodando depois do Release")
		cleanup(body)
	end)

	run("Cenário 4 — possessão dupla com o player e volta ao normal", function(t)
		local player = Players:GetPlayers()[1]
		if not player or not player.Character or not player.Character:GetAttribute("EntityID") then
			t.log("sem player com entidade neste Play: teste pulado")
			return
		end
		local native = DataManager.Get(player.Character)
		local routedBefore = AntiCheat.GetControlledEntityId(player)
		t.assert(native and routedBefore == native.ID, "O player não estava no corpo nativo antes do teste")
		-- O teste põe e tira uma IA do corpo nativo: não pode remover uma que já existia
		t.assert(not native:HasComponent(native.ComponentKey.AI), "O corpo do player já nasce com AI: o teste precisa ser revisto")

		local hunterTicks = 0
		local hunterBrain = function() hunterTicks += 1 end
		local hunter = makeDummy(CFrame.new(0, 5, 0), { "Character", "Health", "Movement", "Status", "Control", "AI" })
		hunter.SetBrain(hunterBrain)

		t.assert(hunter.Possess({ Player = player }), "O player não possuiu o hunter")
		t.assert(AntiCheat.GetControlledEntityId(player) == hunter.ID, "O input não foi roteado para o hunter")
		t.assert(not hunter.IsAIEnabled(), "A IA do hunter seguiu ligada com o player no controle (PauseAI)")
		hunterTicks = 0

		-- O corpo nativo, sem dono, ganha uma IA enquanto o player está no hunter
		local nativeTicks = 0
		native:AddComponent(native.ComponentKey.AI, { Brain = function() nativeTicks += 1 end }, true)
		t.wait(0.3)
		t.assert(nativeTicks > 0, "A IA do corpo nativo não rodou")
		t.assert(hunterTicks == 0, "A IA do hunter rodou durante a posse")

		local released = hunter.Release()
		native:RemoveComponent(native.ComponentKey.AI)
		t.assert(released, "Release do hunter recusado")
		t.assert(AntiCheat.GetControlledEntityId(player) == routedBefore, "O input não voltou ao corpo nativo")
		t.assert(hunter.IsAIEnabled() and hunter.GetBrain() == hunterBrain, "A IA do hunter não voltou ligada e com a mesma mente")
		t.wait(0.2)
		t.assert(hunterTicks > 0, "A IA do hunter não voltou a rodar")
		cleanup(hunter)
	end)
end

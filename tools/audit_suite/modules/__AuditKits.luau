local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local Lib = require(SS.__AuditKitLib)
local E, Intents = Lib.E, Lib.Intents
local Id = Intents.Id
local StateTable = require(SS.Modules.Combat.StateTable)
local SkillHandler = require(SSS.Modules.SkillHandler)
local MinionFactory = require(SS.Modules.MinionFactory)
local Presets = require(SS.Modules.Combat.Hitbox.HitboxPresets)
local inc, wa = Lib.inc, Lib.wa

local Kits = {}

---------------------------------------------------------------- K1 PISTOLEIRA
do
	local K = { name = "Pistoleira", range = 10, think = 0.25, strafe = 0.6 }
	local Tambor = Lib.status("Tambor", { category = E.Categories.Internal }, {
		onStart = function(self) self.chamber = { "Normal", "Normal", "Normal", "_", "_", "_" }; self.cursor = 1; self.mode = "Melee" end })
	local function chamber(e)
		local en = e.GetStatus("Tambor")
		return en and en[1] and en[1].runner and en[1].runner.skill
	end
	K.chamber = chamber
	wa("Pistoleira", "Sem componente de recurso/estado (blackboard): tambor, cursor e modo vivem dentro de um status infinito 'Tambor', lido via GetStatus()[1].runner.skill")
	local function hud(e)
		local c = chamber(e); if not c or not e.Instance then return end
		local ammo = 0
		for _, b in ipairs(c.chamber) do if b ~= "_" then ammo += 1 end end
		e.Instance:SetAttribute("Chamber", table.concat(c.chamber, ","))
		e.Instance:SetAttribute("ChamberCursor", c.cursor)
		e.Instance:SetAttribute("Ammo", ammo)
		e.Instance:SetAttribute("Mode", c.mode)
	end
	K.hud = hud
	wa("Pistoleira", "Sem canal de replicação de estado customizado para HUD: tambor/munição/modo vão por Instance:SetAttribute no model")
	local function loadSpecial(e)
		local c = chamber(e); if not c then return end
		for i = 1, 6 do
			if c.chamber[i] == "_" or c.chamber[i] == "Normal" then
				c.chamber[i] = ({ "Incendiaria", "Perfurante", "Vampirica" })[math.random(1, 3)]
				inc(Lib.stats.notes, "Pistoleira:bala_especial_gerada")
				break
			end
		end
		hud(e)
	end
	K.loadSpecial = loadSpecial
	local Queimadura = Lib.status("Queimadura", { duration = 3, traits = { E.Traits.DOT } }, {
		onStart = function(self) self.acc = 0 end,
		onStep = function(self, dt) self.acc += dt; if self.acc >= 0.5 then self.acc = 0; self.Entity.TakeDamage(2, self.Runner) end end })
	local Foco = Lib.status("Foco", { category = E.Categories.Buff, duration = 5 }, {
		onStart = function(self)
			self:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.onHit, Action = function(ctx) ctx.damage = ctx.damage * 1.3 end })
		end })
	K.Foco = Foco
	local Adagas = Lib.skill("Pist_Adagas", { cooldown = 0.45, duration = 0.2, traits = { E.Traits.Melee } }, {
		onStart = function(self) for _, tgt in ipairs(Lib.inCone(self.Entity, 7, 110)) do Lib.hit(self, tgt, 6, "Pistoleira") end end })
	local Investida = Lib.skill("Pist_Investida", { cooldown = 3, duration = 0.25 }, {
		onStart = function(self)
			self.Entity.ApplyStatus(StateTable.Status.iFrame, { Duration = 0.25, Source = self.Runner })
			self.Entity.AddForce({ Type = "PistDash", Duration = 0.25, Speed = 60, Direction = self.Entity.GetLookDirection(), Hard = true, Priority = 10 })
		end })
	local Disparo = Lib.skill("Pist_Disparo", { cooldown = 0.35, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity; local c = chamber(e); if not c then return end
			local bullet = c.chamber[c.cursor]
			c.chamber[c.cursor] = "_"
			c.cursor = c.cursor % 6 + 1
			hud(e)
			if bullet == "_" then inc(Lib.stats.notes, "Pistoleira:clique_vazio"); return end
			local tgt = Lib.hitscan(e, 60)
			if not tgt then inc(Lib.stats.notes, "Pistoleira:tiro_errou"); return end
			inc(Lib.stats.notes, "Pistoleira:tiro_" .. bullet)
			if bullet == "Perfurante" then
				wa("Pistoleira", "Damage(target, amount) não aceita traits por hit: bala perfurante injeta TrueHit com um Listen OUT.onHit de uso único (Limit 1)")
				self:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.onHit, Priority = 100, Limit = { Max = 1, OnExhaust = "Remove" },
					Action = function(ctx) table.insert(ctx.traits, E.Traits.TrueHit) end })
				Lib.hit(self, tgt, 10, "Pistoleira")
			elseif bullet == "Incendiaria" then
				Lib.hit(self, tgt, 6, "Pistoleira")
				self:ApplyStatus(Queimadura, { Target = tgt })
			elseif bullet == "Vampirica" then
				local ok, dealt = Lib.hit(self, tgt, 6, "Pistoleira")
				if ok and dealt then e.Heal(dealt) end
			else
				Lib.hit(self, tgt, 8, "Pistoleira")
			end
		end })
	local Recarregar = Lib.skill("Pist_Recarregar", { cooldown = 2, duration = 1.2 }, {
		onStep = function(self)
			if self.Entity.GetActiveTags()[E.Tags.canCast] == false then
				wa("Pistoleira", "CC não interrompe skill em andamento: a recarga checa canCast a cada onStep e se cancela")
				inc(Lib.stats.notes, "Pistoleira:recarga_interrompida")
				self:Stop(true)
			end
		end,
		onEnd = function(self)
			local c = chamber(self.Entity); if not c then return end
			for i = 1, 6 do if c.chamber[i] == "_" then c.chamber[i] = "Normal" end end
			hud(self.Entity)
		end })
	K.Recarregar = Recarregar
	local Roleta = Lib.skill("Pist_Roleta", { cooldown = 0, duration = 2.5 }, {
		onStart = function(self) self.needle = 1; self.acc = 0; self.done = false; self.Entity.Instance:SetAttribute("RouletteActive", true) end,
		onStep = function(self, dt)
			self.acc += dt
			if self.acc >= 0.12 then self.acc = 0; self.needle = self.needle % 6 + 1; self.Entity.Instance:SetAttribute("RouletteNeedle", self.needle) end
		end,
		onRecast = function(self)
			if self.done then return end
			self.done = true
			local e = self.Entity; local c = chamber(e)
			if c then
				c.cursor = self.needle
				local b = c.chamber[self.needle]
				if b ~= "_" and b ~= "Normal" then self:ApplyStatus(Foco, { Target = e }); inc(Lib.stats.notes, "Pistoleira:skillcheck_otimo") else inc(Lib.stats.notes, "Pistoleira:skillcheck_ruim") end
				hud(e)
			end
			wa("Pistoleira", "Cooldown do SkillHandler bloqueia recast: a roleta usa cooldown 0 e aplica o cooldown real com task.defer (senão o startCooldown pós-recast sobrescreve)")
			task.defer(function() if e.Active then e.SetCooldown("Pist_Roleta", 4) end end)
			self:Stop(false)
		end,
		onEnd = function(self) if self.Entity.Instance then self.Entity.Instance:SetAttribute("RouletteActive", false) end end })
	local function equipMode(e, mode)
		wa("Pistoleira", "ApplyLoadout substitui o loadout inteiro: troca de modo feita slot a slot com EquipSkill/UnequipSlot")
		if mode == "Melee" then
			e.EquipSkill(Id.Primary, Adagas); e.EquipSkill(Id.Ability1, Investida); e.UnequipSlot(Id.Ability2)
		else
			e.EquipSkill(Id.Primary, Disparo); e.EquipSkill(Id.Ability1, Recarregar); e.EquipSkill(Id.Ability2, Roleta)
		end
		local c = chamber(e); if c then c.mode = mode end
		hud(e)
	end
	K.equipMode = equipMode
	local Trocar = Lib.skill("Pist_Trocar", { cooldown = 1, duration = 0.3 }, {
		onStart = function(self) self.Entity.SetActionState(StateTable.ActionStates.Self.selfCast, self.Runner) end,
		onEnd = function(self)
			self.Entity.RemoveActionState(self.Runner)
			local c = chamber(self.Entity)
			equipMode(self.Entity, (c and c.mode == "Melee") and "Ranged" or "Melee")
		end })
	local Marca = Lib.skill("Pist_Marca", { cooldown = 12, duration = 6 }, {
		onStart = function(self)
			local tgt = Lib.nearestEnemy(self.Entity, 50)
			if not tgt then self:Stop(false); return end
			self.target = tgt
			tgt.Instance:SetAttribute("MarkedBy", self.Entity.ID)
			self:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.onHit, Action = function(ctx)
				if ctx.targetEntity == self.target then ctx.damage = ctx.damage * 1.5; inc(Lib.stats.notes, "Pistoleira:hit_no_marcado") end end })
		end,
		onEnd = function(self) if self.target and self.target.Instance then self.target.Instance:SetAttribute("MarkedBy", nil) end end })
	function K.setup(e)
		e.ApplyStatus(Tambor, { ID = "Tambor" })
		e:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDamage, Query = { Any = { E.Traits.Melee } }, Action = function()
			if math.random() < 0.5 then loadSpecial(e) end end })
		e.EquipSkill(Id.Ability3, Trocar)
		e.EquipSkill(Id.Ultimate, Marca)
		equipMode(e, "Melee")
	end
	function K.decide(e, tgt, dist)
		local c = chamber(e); if not c then return end
		local ammo, specials = 0, 0
		for _, b in ipairs(c.chamber) do if b ~= "_" then ammo += 1 end; if b ~= "_" and b ~= "Normal" then specials += 1 end end
		if math.random() < 0.06 then Lib.press(e, Id.Ultimate) end
		if c.mode == "Melee" then
			if dist < 8 then Lib.press(e, Id.Primary) elseif dist < 22 and math.random() < 0.3 then Lib.press(e, Id.Ability1) end
			if specials >= 2 or (dist > 18 and ammo > 0) then Lib.press(e, Id.Ability3) end
		else
			if ammo == 0 then
				if math.random() < 0.5 then Lib.press(e, Id.Ability1) else Lib.press(e, Id.Ability3) end
			elseif specials > 0 and not e.Instance:GetAttribute("RouletteActive") and math.random() < 0.4 then
				if Lib.press(e, Id.Ability2) then task.delay(0.2 + math.random() * 1.2, function() if Lib.isAlive(e) then Lib.press(e, Id.Ability2) end end) end
			else
				Lib.press(e, Id.Primary)
			end
			if dist < 5 then Lib.press(e, Id.Ability3) end
		end
	end
	Kits.Pistoleira = K
end

---------------------------------------------------------------- K2 INVOCADOR
do
	local K = { name = "Invocador", range = 18, think = 0.35 }
	local MinionKit = { name = "Invocador_minion", range = 3, think = 0.4 }
	local Mordida = Lib.skill("Inv_Mordida", { cooldown = 0.8, duration = 0.1, traits = { E.Traits.Melee } }, {
		onStart = function(self) for _, tgt in ipairs(Lib.inCone(self.Entity, 4.5, 140)) do Lib.hit(self, tgt, 4, "Invocador_minion") end end })
	function MinionKit.decide(e, tgt, dist) if dist < 5 then Lib.press(e, Id.Primary) end end
	MinionFactory.Register("AuditMinion", {
		Components = { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "AI", "Control" },
		Configs = { Combat = { ChosenChar = "__Kit_Minion" }, Health = { MaxHP = 30 }, Attributes = { BaseStats = { Speed = 22, GravityScale = 1 } } },
		BuildModel = function(cf) return Lib.body(cf.Position, "AuditMinion", Vector3.new(1.2, 1.6, 1.2), Color3.fromRGB(90, 40, 160)) end,
	})
	local MarcaSombria = Lib.status("MarcaSombria", { duration = 4 }, {
		onStart = function(self) self:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.PreDamage, Action = function(ctx) ctx.damage = ctx.damage * 1.2 end }) end })
	local Invocar = Lib.skill("Inv_Invocar", { cooldown = 6, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity; local st = Lib.state[e]; st.minions = st.minions or {}
			for i = #st.minions, 1, -1 do if not Lib.isAlive(st.minions[i]) then table.remove(st.minions, i) end end
			if #st.minions >= 3 then return end
			local m = MinionFactory.Spawn("AuditMinion", CFrame.new(e.GetRoot().Position + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))), e)
			if not m then return end
			m.Team = e.Team
			Lib.state[m] = { kit = "Invocador_minion", t = 0, owner = e }
			table.insert(Lib.alive, m)
			m.EquipSkill(Id.Primary, Mordida)
			m.SetBrain(Lib.brain(MinionKit))
			table.insert(st.minions, m)
			inc(Lib.stats.notes, "Invocador:minion_invocado")
		end })
	local Rajada = Lib.skill("Inv_Rajada", { cooldown = 0.9, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity
			Lib.projectile(e, e.GetRoot().Position + Vector3.new(0, 1, 0), e.GetAimDirection(), 70, 1, 1.2, function(tgt) Lib.hit(self, tgt, 7, "Invocador") end)
		end })
	function K.setup(e)
		e.EquipSkill(Id.Primary, Rajada)
		e.EquipSkill(Id.Ability1, Invocar)
		e:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.onHit, Inherit = { Generations = 1 }, Action = function(ctx)
			local tgt = ctx.targetEntity
			if tgt and tgt:HasComponent("Status") then tgt.ApplyStatus(MarcaSombria, { Source = ctx.source }) end
			if ctx.sourceEntity ~= e then inc(Lib.stats.notes, "Invocador:marca_aplicada_pelo_minion(heranca)") end
		end })
		e:Listen({ Role = E.Roles.OUT, Breakpoint = E.Breakpoints.OnDeath, Inherit = { Generations = 1 }, Action = function(ctx)
			if ctx.source and ctx.source.Entity ~= e then inc(Lib.stats.notes, "Invocador:kill_do_minion_creditado(heranca)") end
		end })
		e:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.OnDeath, Action = function()
			local st = Lib.state[e]
			for _, m in ipairs(st and st.minions or {}) do if Lib.isAlive(m) then m.Die(nil); inc(Lib.stats.notes, "Invocador:minion_morto_com_o_dono") end end
		end })
		wa("Invocador", "Sem vínculo dono->minion no ciclo de vida: morte do invocador mata os minions via listener IN.OnDeath manual")
		wa("Invocador", "Lineage do runner do minion começa no minion: crédito de kill pro invocador só via listener OUT.OnDeath herdado")
	end
	function K.decide(e, tgt, dist)
		Lib.press(e, Id.Ability1)
		if dist < 60 then Lib.press(e, Id.Primary) end
	end
	Kits.Invocador = K
end

---------------------------------------------------------------- K3 DUELISTA
do
	local K = { name = "Duelista", range = 4, think = 0.2, strafe = 0.4 }
	local Parry = Lib.status("Parry", { category = E.Categories.Buff, duration = 0.35, tags = { [E.Tags.block] = true } }, {
		onTrigger = function(self, ctx)
			local attacker = ctx.sourceEntity
			if attacker and attacker ~= self.Entity and attacker:HasComponent("Status") then
				attacker.ApplyStatus(StateTable.States.Stun, { Duration = 0.8, Source = self.Runner })
			end
			self.Entity.ResetCooldown("Duel_Estocada")
			inc(Lib.stats.notes, "Duelista:parry_sucesso")
			return 0
		end })
	K.Parry = Parry
	local Aparar = Lib.skill("Duel_Aparar", { cooldown = 1.5, duration = 0.35 }, {
		onStart = function(self) self.Entity.ApplyStatus(Parry, { Duration = 0.35, Source = self.Runner }) end })
	local Estocada = Lib.skill("Duel_Estocada", { cooldown = 0.6, duration = 0.15, traits = { E.Traits.Melee } }, {
		onStart = function(self)
			for _, tgt in ipairs(Lib.inCone(self.Entity, 6, 80)) do
				local dmg = 9
				if tgt:HasComponent("Combat") then
					for _, list in pairs(tgt.GetActiveSkills()) do
						for _, r in ipairs(list) do if r.type == E.Types.Skill and r.state == "Casting" then dmg = 14 end end
					end
				end
				if dmg == 14 then inc(Lib.stats.notes, "Duelista:counter_hit") end
				Lib.hit(self, tgt, dmg, "Duelista")
			end
		end })
	local Quebra = Lib.skill("Duel_QuebraGuarda", { cooldown = 3, duration = 0.2, traits = { E.Traits.BlockBreak, E.Traits.Melee } }, {
		onStart = function(self) for _, tgt in ipairs(Lib.inCone(self.Entity, 6, 90)) do Lib.hit(self, tgt, 5, "Duelista") end end })
	function K.setup(e)
		e.EquipSkill(Id.Primary, Estocada); e.EquipSkill(Id.Ability1, Aparar); e.EquipSkill(Id.Ability2, Quebra)
	end
	function K.decide(e, tgt, dist)
		local threat = false
		if tgt:HasComponent("Combat") then
			for _, list in pairs(tgt.GetActiveSkills()) do for _, r in ipairs(list) do if r.type == E.Types.Skill and r.state ~= "Ended" then threat = true end end end
		end
		if threat and dist < 9 and math.random() < 0.5 then Lib.press(e, Id.Ability1) end
		if dist < 7 then
			if math.random() < 0.2 then Lib.press(e, Id.Ability2) else Lib.press(e, Id.Primary) end
		end
	end
	Kits.Duelista = K
end

---------------------------------------------------------------- K4 ALQUIMISTA
do
	local K = { name = "Alquimista", range = 16, think = 0.4 }
	local Instavel = Lib.status("Instavel", { duration = 4 }, {})
	K.Instavel = Instavel
	local function arm(alq, target)
		wa("Alquimista", "Sem evento global de morte: precisa assinar IN.OnDeath em CADA alvo marcado")
		local owner = "Alq_" .. alq.ID
		target:UnsubscribeByOwner(owner)
		target:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.OnDeath, Owner = owner, Limit = { Max = 1, OnExhaust = "Remove" }, Action = function(ctx)
			if not target.GetStatus("Instavel") then return end
			inc(Lib.stats.notes, "Alquimista:explosao")
			local root = target.GetRoot(); if not root then return end
			for _, o in ipairs(Lib.inRadius(root.Position, 12, alq.Team)) do
				if o ~= target and o:HasComponent("Status") then
					o.ApplyStatus(Instavel, { Source = ctx.source })
					arm(alq, o)
					local ok, why = o.TakeDamage(30, ctx.source)
					if not ok and why == "MaxRecursion" then inc(Lib.stats.notes, "Alquimista:explosao_recusada_MAX_RECURSION") end
				end
			end
		end })
	end
	K.arm = arm
	local Frasco = Lib.skill("Alq_Frasco", { cooldown = 1.2, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity
			Lib.projectile(e, e.GetRoot().Position + Vector3.new(0, 1, 0), e.GetAimDirection(), 60, 1.2, 1.5, function(tgt)
				Lib.hit(self, tgt, 8, "Alquimista")
				if Lib.isAlive(tgt) then tgt.ApplyStatus(Instavel, { Source = self.Runner }); arm(e, tgt) end
			end)
		end })
	function K.setup(e) e.EquipSkill(Id.Primary, Frasco) end
	function K.decide(e, tgt, dist) if dist < 50 then Lib.press(e, Id.Primary) end end
	Kits.Alquimista = K
end

---------------------------------------------------------------- K5 LADRÃO
do
	local K = { name = "Ladrao", range = 8, think = 0.3, strafe = 0.5 }
	local Arremesso = Lib.skill("Lad_Adaga", { cooldown = 0.7, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity
			Lib.projectile(e, e.GetRoot().Position + Vector3.new(0, 1, 0), e.GetAimDirection(), 90, 0.8, 0.8, function(tgt) Lib.hit(self, tgt, 6, "Ladrao") end)
		end })
	local Roubar = Lib.skill("Lad_Roubar", { cooldown = 8, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity
			local tgt = Lib.inCone(e, 15, 100)[1]
			if not tgt or not tgt:HasComponent("Combat") then return end
			local stolen = tgt.GetSkillFromSlot(Id.Primary)
			if not stolen then return end
			local remaining = tgt.GetCooldown(stolen.data.name)
			e.EquipSkill(Id.Ability2, stolen)
			e.SetCooldown(stolen.data.name, remaining)
			tgt.UnequipSlot(Id.Primary)
			inc(Lib.stats.notes, "Ladrao:roubou_" .. tostring(stolen.data.name))
			task.delay(10, function()
				if Lib.isAlive(tgt) and tgt.GetSkillFromSlot(Id.Primary) == nil then tgt.EquipSkill(Id.Primary, stolen) end
				if Lib.isAlive(e) then e.UnequipSlot(Id.Ability2) end
			end)
		end })
	local Possuir = Lib.skill("Lad_Possuir", { cooldown = 15, duration = 5 }, {
		onStart = function(self)
			local e = self.Entity
			local tgt = Lib.nearestEnemy(e, 30)
			if not tgt or not tgt:HasComponent("Control") then self:Stop(false); return end
			tgt.Possess({ AI = true, Brain = function() end })
			wa("Ladrao", "Possess({AI=true, Brain}) ignora o Brain e não suspende a IA do alvo: desliga com SetEnabled(false) e dirige o fantoche manualmente no onStep")
			if tgt:HasComponent("AI") then tgt.SetEnabled(false) end
			self.puppet = tgt; self.oldTeam = tgt.Team; tgt.Team = e.Team
			inc(Lib.stats.notes, "Ladrao:possuiu_" .. tostring(Lib.state[tgt] and Lib.state[tgt].kit))
		end,
		onStep = function(self)
			local p = self.puppet; if not p or not Lib.isAlive(p) then return end
			local enemy = Lib.nearestEnemy(p, 60); if not enemy then return end
			local to = enemy.GetRoot().Position - p.GetRoot().Position
			SkillHandler.HandleMovementInput(p.ID, Vector3.new(to.X, 0, to.Z)); SkillHandler.HandleLookInput(p.ID, to)
			if to.Magnitude < 7 and p:HasComponent("Combat") then Lib.press(p, Id.Primary) end
		end,
		onEnd = function(self)
			local p = self.puppet
			if p and Lib.isAlive(p) then p.Release(); if p:HasComponent("AI") then p.SetEnabled(true) end; p.Team = self.oldTeam end
		end })
	function K.setup(e) e.EquipSkill(Id.Primary, Arremesso); e.EquipSkill(Id.Ability1, Roubar); e.EquipSkill(Id.Ability3, Possuir) end
	function K.decide(e, tgt, dist)
		if dist < 14 then Lib.press(e, Id.Ability1) end
		if e.GetSkillFromSlot(Id.Ability2) and dist < 10 then Lib.press(e, Id.Ability2) end
		if math.random() < 0.08 then Lib.press(e, Id.Ability3) end
		if dist < 40 then Lib.press(e, Id.Primary) end
	end
	Kits.Ladrao = K
end

---------------------------------------------------------------- K6 CRONOMANTE
do
	local K = { name = "Cronomante", range = 14, think = 0.35 }
	local Ampulheta = Lib.status("Ampulheta", { category = E.Categories.Internal }, {
		onStart = function(self) self.hist = {}; self.acc = 0 end,
		onStep = function(self, dt)
			self.acc += dt
			if self.acc >= 0.1 then
				self.acc = 0
				local r = self.Entity.GetRoot(); if not r then return end
				table.insert(self.hist, { p = r.Position, hp = self.Entity.GetHP() })
				while #self.hist > 30 do table.remove(self.hist, 1) end
			end
		end })
	local Lentidao = Lib.status("Lentidao", { duration = 2 }, {
		onStart = function(self) if self.Entity:HasComponent("Attributes") then self.Entity.AddModifier("Speed", "Lentidao", E.ModifierType.MultPercent, 0.6) end end,
		onEnd = function(self) if self.Entity and self.Entity.Active and self.Entity:HasComponent("Attributes") then self.Entity.RemoveModifier("Speed", "Lentidao") end end })
	local Agulha = Lib.skill("Cro_Agulha", { cooldown = 0.8, duration = 0.1 }, {
		onStart = function(self)
			local tgt = Lib.hitscan(self.Entity, 50)
			if tgt then Lib.hit(self, tgt, 7, "Cronomante"); if Lib.isAlive(tgt) and tgt:HasComponent("Status") then self:ApplyStatus(Lentidao, { Target = tgt }) end end
		end })
	local Retroceder = Lib.skill("Cro_Retroceder", { cooldown = 10, duration = 0.1 }, {
		onStart = function(self)
			local en = self.Entity.GetStatus("Ampulheta")
			local amp = en and en[1] and en[1].runner and en[1].runner.skill
			local snap = amp and amp.hist[1]; if not snap then return end
			self.Entity.Teleport(snap.p)
			if snap.hp > self.Entity.GetHP() then self.Entity.SetHP(snap.hp) end
			inc(Lib.stats.notes, "Cronomante:rewind")
		end })
	K.Ampulheta = Ampulheta
	function K.setup(e) e.ApplyStatus(Ampulheta, { ID = "Ampulheta" }); e.EquipSkill(Id.Primary, Agulha); e.EquipSkill(Id.Ability1, Retroceder) end
	function K.decide(e, tgt, dist)
		if e.GetHealthRatio() < 0.45 then Lib.press(e, Id.Ability1) end
		if dist < 45 then Lib.press(e, Id.Primary) end
	end
	Kits.Cronomante = K
end

---------------------------------------------------------------- K7 CANALIZADOR
do
	local K = { name = "Canalizador", range = 18, think = 0.3 }
	local Raio = Lib.skill("Can_Raio", { cooldown = 1.2, duration = 3, input = { Hold = 0.3 } }, {
		onStart = function(self) self.t0 = os.clock() end,
		onStep = function(self)
			if self.Entity.GetActiveTags()[E.Tags.canCast] == false then inc(Lib.stats.notes, "Canalizador:canal_interrompido"); self:Stop(true) end
		end,
		onRelease = function(self, ctx)
			local held = (ctx and ctx.input and ctx.input.HeldTime) or (os.clock() - self.t0)
			local tgt = Lib.hitscan(self.Entity, 70)
			if tgt then Lib.hit(self, tgt, math.floor(5 + held * 10), "Canalizador"); inc(Lib.stats.notes, "Canalizador:raio_carregado") end
			self:Stop(false)
		end })
	local Feixe = Lib.skill("Can_Feixe", { cooldown = 4, duration = 2 }, {
		onStart = function(self) self.acc = 0 end,
		onStep = function(self, dt)
			if self.Entity.GetActiveTags()[E.Tags.canCast] == false then self:Stop(true); return end
			self.acc += dt
			if self.acc >= 0.2 then self.acc = 0; local tgt = Lib.hitscan(self.Entity, 40); if tgt then Lib.hit(self, tgt, 2, "Canalizador") end end
		end })
	function K.setup(e) e.EquipSkill(Id.Primary, Raio); e.EquipSkill(Id.Ability1, Feixe) end
	function K.decide(e, tgt, dist)
		local st = Lib.state[e]
		if st.charging then return end
		if math.random() < 0.3 then Lib.press(e, Id.Ability1); return end
		if Lib.press(e, Id.Primary, Intents.Gesture.Hold, 0.3) then
			st.charging = true
			local hold = 0.3 + math.random() * 1.6
			task.delay(hold, function() st.charging = false; if Lib.isAlive(e) then Lib.release(e, Id.Primary, hold) end end)
		end
	end
	Kits.Canalizador = K
end

---------------------------------------------------------------- K8 MESTRE DE CARTAS
do
	local K = { name = "Cartas", range = 16, think = 0.4 }
	local Fluxo = Lib.status("FluxoMana", { category = E.Categories.Internal }, {
		onStart = function(self) self.acc = 0 end,
		onStep = function(self, dt)
			self.acc += dt
			if self.acc >= 0.5 then self.acc = 0; local m = self.Entity.GetStat("Mana", 0); self.Entity.SetStat("Mana", math.min(10, m + 1)) end
		end })
	wa("Cartas", "Recurso (mana) guardado como stat do Attributes via SetStat; sem conceito de custo/recurso no SkillHandler")
	local function card(name, cost, fn)
		return Lib.skill("Card_" .. name, { cooldown = 0.5, duration = 0.1, mana = cost }, {
			onStart = function(self)
				local mana = self.Entity.GetStat("Mana", 0)
				if mana < cost then
					inc(Lib.stats.notes, "Cartas:sem_mana")
					wa("Cartas", "SkillHandler inicia o cooldown antes do onStart: carta sem mana precisa devolver o cooldown (ResetCooldown com task.defer)")
					local e = self.Entity
					task.defer(function() if e.Active then e.ResetCooldown(self.data.name) end end)
					self:Stop(false); return
				end
				self.Entity.SetStat("Mana", mana - cost)
				fn(self)
			end })
	end
	local deck = {
		card("Fogo", 3, function(self) local e = self.Entity; Lib.projectile(e, e.GetRoot().Position + Vector3.new(0, 1, 0), e.GetAimDirection(), 65, 1, 1.2, function(t) Lib.hit(self, t, 9, "Cartas") end) end),
		card("Gelo", 4, function(self) local t = Lib.hitscan(self.Entity, 45); if t then Lib.hit(self, t, 4, "Cartas"); if Lib.isAlive(t) and t:HasComponent("Status") then t.ApplyStatus(StateTable.States.Root, { Duration = 1, Source = self.Runner }) end end end),
		card("Cura", 4, function(self) self.Entity.Heal(15) end),
		card("Escudo", 5, function(self) self.Entity.ApplyStatus(StateTable.Status.iFrame, { Duration = 1, Source = self.Runner }) end),
		card("Raio", 6, function(self) local t = Lib.hitscan(self.Entity, 60); if t then Lib.hit(self, t, 12, "Cartas") end end),
		card("Veneno", 3, function(self) local t = Lib.hitscan(self.Entity, 45); if t and Lib.isAlive(t) and t:HasComponent("Status") then self:ApplyStatus(StateTable.Status.Bleed, { Target = t }) end end),
	}
	K.deck = deck
	function K.draw(e)
		for _, slot in ipairs({ Id.Ability1, Id.Ability2, Id.Ability3 }) do e.EquipSkill(slot, deck[math.random(1, #deck)]) end
		inc(Lib.stats.notes, "Cartas:compra")
	end
	function K.setup(e)
		e.SetStat("Mana", 5)
		e.ApplyStatus(Fluxo, { ID = "FluxoMana" })
		K.draw(e)
		Lib.state[e].lastDraw = os.clock()
	end
	function K.decide(e, tgt, dist)
		local st = Lib.state[e]
		if os.clock() - (st.lastDraw or 0) > 6 then st.lastDraw = os.clock(); K.draw(e) end
		local slot = ({ Id.Ability1, Id.Ability2, Id.Ability3 })[math.random(1, 3)]
		Lib.press(e, slot)
	end
	Kits.Cartas = K
end

---------------------------------------------------------------- E1 COLOSSO
do
	local K = { name = "Colosso", range = 6, think = 0.35, hp = 900, size = Vector3.new(5, 7, 4), color = Color3.fromRGB(120, 30, 30) }
	local Golpe = Lib.skill("Col_Golpe", { cooldown = 2, duration = 0.6, castTime = 0.5, traits = { E.Traits.BlockBreak, E.Traits.Melee } }, {
		onStep = function(self)
			if self.hit then return end
			self.hit = true
			wa("Colosso", "castTime só atrasa o onStep (não existe breakpoint de fim de cast): golpe aplicado no 1º onStep")
			for _, tgt in ipairs(Lib.inCone(self.Entity, 9, 120)) do Lib.hit(self, tgt, 18, "Colosso") end
			self:Stop(false)
		end })
	local Terremoto = Lib.skill("Col_Terremoto", { cooldown = 5, duration = 0.1 }, {
		onStart = function(self)
			for _, tgt in ipairs(Lib.inRadius(self.Entity.GetRoot().Position, 14, self.Entity.Team)) do
				Lib.hit(self, tgt, 12, "Colosso")
				if Lib.isAlive(tgt) and tgt:HasComponent("Status") then tgt.ApplyStatus(StateTable.States.Root, { Duration = 1, Source = self.Runner }) end
			end
		end })
	function K.setup(e)
		local st = Lib.state[e]; st.phase = 1
		e.EquipSkill(Id.Primary, Golpe)
		e:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.PostDamage, Action = function()
			local ratio = e.GetHealthRatio()
			if st.phase == 1 and ratio <= 0.66 then
				st.phase = 2
				inc(Lib.stats.notes, "Colosso:fase2")
				e.ApplyStatus(StateTable.Status.iFrame, { Duration = 1.5 })
				e.AddModifier("DamageMult", "Enrage", E.ModifierType.Flat, 0.5)
				e.EquipSkill(Id.Ability1, Terremoto)
				for i = 1, 2 do
					local add = Lib.spawn("Enxame", e.Team, e.GetRoot().Position + Vector3.new(i * 4, 0, 4), { size = Vector3.new(1, 1.4, 1), hp = 25, speed = 24 })
					Kits.Enxame.setup(add); add.SetBrain(Lib.brain(Kits.Enxame))
				end
			elseif st.phase == 2 and ratio <= 0.33 then
				st.phase = 3
				inc(Lib.stats.notes, "Colosso:fase3")
				e.AddModifier("Speed", "Fase3", E.ModifierType.MultPercent, 1.5)
			end
		end })
	end
	function K.decide(e, tgt, dist)
		if dist < 9 then Lib.press(e, Id.Primary) end
		if dist < 14 then Lib.press(e, Id.Ability1) end
	end
	Kits.Colosso = K
end

---------------------------------------------------------------- E2 TORRE
do
	local K = { name = "Torre", think = 1.4, hp = 300, comps = { "Character", "Health", "Status", "Combat", "AI" }, size = Vector3.new(3, 6, 3), color = Color3.fromRGB(60, 60, 70), anchored = true }
	local Disparo = Lib.skill("Tor_Disparo", { cooldown = 1.2, duration = 0.1 }, {
		onStart = function(self)
			local e = self.Entity
			local tgt = Lib.nearestEnemy(e, 70); if not tgt then return end
			local origin = e.GetRoot().CFrame * CFrame.new(0, 2, 0)
			local hb = Presets.HomingBolt(e, origin, function() return Lib.isAlive(tgt) and tgt.GetRoot() or nil end, 45, 1, 3, math.rad(180))
			local done = false
			hb:OnHit(function(result)
				if done or not result then return end
				local hitEnt = require(game.ServerScriptService.EntityData.DataManager).GetEntityFromInstance(result.Instance)
				if hitEnt and hitEnt.Team ~= e.Team and Lib.isAlive(hitEnt) then done = true; Lib.hit(self, hitEnt, 10, "Torre"); hb:HitStop() end
			end)
		end })
	function K.setup(e)
		e.EquipSkill(Id.Primary, Disparo)
		e:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.PreDamage, Action = function(ctx)
			local attacker = ctx.sourceEntity
			local ar = attacker and attacker.GetRoot and attacker:HasComponent("Character") and attacker.GetRoot()
			if not ar then return end
			local me = e.GetRoot()
			local to = (ar.Position - me.Position) * Vector3.new(1, 0, 1)
			if to.Magnitude > 0.1 and me.CFrame.LookVector:Dot(to.Unit) > 0.3 then
				ctx.cancelled = true; ctx.reason = "EscudoFrontal"
				inc(Lib.stats.notes, "Torre:bloqueio_frontal")
			end
		end })
		wa("Torre", "Contexto de dano não traz ponto/direção do impacto: escudo frontal usa a posição do atacante (projétil vindo de trás de um atacante na frente é bloqueado errado)")
	end
	function K.decide(e, tgt, dist)
		local me = e.GetRoot()
		local to = (tgt.GetRoot().Position - me.Position) * Vector3.new(1, 0, 1)
		if to.Magnitude > 0.1 then me.CFrame = CFrame.lookAt(me.Position, me.Position + to) end
		wa("Torre", "Entidade sem Movement não guarda AimDirection (SetAimDirection/HandleLookInput caem no stub): torre gira o próprio CFrame")
		Lib.press(e, Id.Primary)
	end
	Kits.Torre = K
end

---------------------------------------------------------------- E3 ESPELHO
do
	local K = { name = "Espelho", range = 8, think = 0.4, hp = 200, color = Color3.fromRGB(180, 220, 255) }
	local Toque = Lib.skill("Esp_Toque", { cooldown = 1, duration = 0.1 }, {
		onStart = function(self) for _, t in ipairs(Lib.inCone(self.Entity, 6, 90)) do Lib.hit(self, t, 5, "Espelho") end end })
	function K.setup(e)
		e.EquipSkill(Id.Primary, Toque)
		e:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.PostDamage, Action = function(ctx)
			local src = ctx.source
			if src and src.type == E.Types.Skill and src.data and src.callbacks and src.Entity ~= e then
				wa("Espelho", "Não há API para obter o módulo da skill a partir do runner: cópia remontada com { data = runner.data, callbacks = runner.callbacks }")
				e.EquipSkill(Id.Ability1, { data = src.data, callbacks = src.callbacks })
				Lib.state[e].copied = src.data.name
				inc(Lib.stats.notes, "Espelho:copiou_" .. tostring(src.data.name))
			end
		end })
	end
	function K.decide(e, tgt, dist)
		if e.GetSkillFromSlot(Id.Ability1) then Lib.press(e, Id.Ability1) end
		if dist < 7 then Lib.press(e, Id.Primary) end
	end
	Kits.Espelho = K
end

---------------------------------------------------------------- E4 ENXAME
do
	local K = { name = "Enxame", range = 2.5, think = 0.5, hp = 25, size = Vector3.new(1, 1.4, 1), color = Color3.fromRGB(230, 200, 40), speed = 24 }
	local Picada = Lib.status("Picada", { stackOnSelf = true, maxStacks = 5, duration = 3, traits = { E.Traits.Stackable, E.Traits.DOT } }, {
		onStart = function(self) self.acc = 0 end,
		onStep = function(self, dt) self.acc += dt; if self.acc >= 0.6 then self.acc = 0; self.Entity.TakeDamage(1 * (self.counter or 1), self.Runner) end end })
	local Ferrao = Lib.skill("Enx_Ferrao", { cooldown = 0.9, duration = 0.1, traits = { E.Traits.Melee } }, {
		onStart = function(self)
			for _, t in ipairs(Lib.inCone(self.Entity, 3.5, 160)) do
				Lib.hit(self, t, 2, "Enxame")
				if Lib.isAlive(t) and t:HasComponent("Status") then self:ApplyStatus(Picada, { Target = t }) end
			end
		end })
	function K.setup(e) e.EquipSkill(Id.Primary, Ferrao) end
	function K.decide(e, tgt, dist) if dist < 4 then Lib.press(e, Id.Primary) end end
	Kits.Enxame = K
end

---------------------------------------------------------------- E5 POSSESSOR (IA que possui IA)
do
	local K = { name = "Possessor", range = 12, think = 1.0, hp = 160, color = Color3.fromRGB(30, 30, 30) }
	function K.setup(e) Lib.state[e].tries = 0 end
	function K.decide(e, tgt, dist)
		local st = Lib.state[e]
		if st.puppet and Lib.isAlive(st.puppet) then return end
		if tgt:HasComponent("Control") and tgt:HasComponent("AI") and dist < 20 and math.random() < 0.3 then
			st.tries += 1
			tgt.Possess({ AI = true, Brain = function(p) SkillHandler.HandleMovementInput(p.ID, Vector3.zero) end })
			task.delay(1, function()
				if not Lib.isAlive(tgt) then return end
				local aiOn = tgt:GetComponent("AI") and tgt:GetComponent("AI").Enabled
				if aiOn then inc(Lib.stats.notes, "Possessor:possess_oficial_nao_assumiu_IA") else inc(Lib.stats.notes, "Possessor:possess_oficial_assumiu") end
				tgt.Release()
			end)
		end
	end
	Kits.Possessor = K
end

return Kits

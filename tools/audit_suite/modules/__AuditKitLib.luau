-- __AuditKitLib: helpers de teste + kits hipotéticos. Usa SOMENTE APIs públicas do framework.
-- Todo "WORKAROUND" registrado em Lib.workarounds é algo que o motor não oferece.
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")

local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)
local E = StateTable.Enum
local SkillHandler = require(SSS.Modules.SkillHandler)
local SkillRunner = require(SSS.Modules.SkillRunner)
local Intents = require(RS.Input.Intents)
local HitboxSpawner = require(SS.Modules.Combat.Hitbox.HitboxSpawner)
local Behaviors = require(SS.Modules.Combat.Hitbox.HitboxBehaviors)
local MinionFactory = require(SS.Modules.MinionFactory)
local AreaEffect = require(SS.Modules.Combat.AreaEffect)

local Lib = {}
Lib.E = E
Lib.Intents = Intents
Lib.alive = {}          -- combatentes vivos
Lib.state = setmetatable({}, { __mode = "k" }) -- estado de IA por entidade (fora da entidade)
Lib.stats = { casts = {}, castFails = {}, damage = {}, kills = {}, deaths = {}, notes = {} }
Lib.workarounds = {}    -- [kit] = { "descrição", ... }

local function wa(kit, text)
	Lib.workarounds[kit] = Lib.workarounds[kit] or {}
	for _, t in ipairs(Lib.workarounds[kit]) do if t == text then return end end
	table.insert(Lib.workarounds[kit], text)
end
Lib.wa = wa

local function inc(t, k, n) t[k] = (t[k] or 0) + (n or 1) end
Lib.inc = inc

function Lib.skill(name, data, callbacks)
	data.name = name
	data.cooldown = data.cooldown or 0
	data.duration = data.duration or 0.1
	data.castTime = data.castTime or 0
	return { data = data, callbacks = callbacks or {} }
end

function Lib.status(name, data, callbacks)
	data.name = name
	data.category = data.category or E.Categories.Debuff
	return { data = data, callbacks = callbacks or {} }
end

-- Corpo de teste sem Humanoid (NPCMovement), raiz desancorada
function Lib.body(pos, name, size, color)
	local m = Instance.new("Model"); m.Name = name
	local r = Instance.new("Part"); r.Name = "HumanoidRootPart"
	r.Size = size or Vector3.new(2, 3, 1.5); r.Color = color or Color3.fromRGB(200, 200, 200)
	r.CFrame = CFrame.new(pos); r.Parent = m
	m.PrimaryPart = r
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m.Parent = workspace
	return m
end

local BASE_COMPS = { "Character", "Health", "Status", "Movement", "Attributes", "Combat", "AI", "Control" }
Lib.BASE_COMPS = BASE_COMPS

function Lib.spawn(kitName, team, pos, opts)
	opts = opts or {}
	local model = Lib.body(pos, kitName .. "_" .. team, opts.size, opts.color)
	wa("geral", "Combat exige um personagem no CharacterDatabase (congelado com table.freeze): kits criados em runtime usam ChosenChar inexistente para ganhar loadout vazio")
	local e = DataManager.Create(model, opts.comps or BASE_COMPS, {
		Combat = { ChosenChar = "__Kit_" .. kitName },
		Health = { MaxHP = opts.hp or 120 },
		Attributes = { BaseStats = { Speed = opts.speed or 18, JumpForce = 0, MaxHP = opts.hp or 120, GravityScale = 1 } },
	}, opts.parent)
	e.Team = team -- WORKAROUND: framework não tem conceito de time/facção
	wa("geral", "Sem conceito de time/facção: campo ad-hoc entity.Team e filtro manual em todo alvo/hitbox")
	Lib.state[e] = { kit = kitName, t = 0, timers = {} }
	table.insert(Lib.alive, e)
	e:Listen({ Role = E.Roles.IN, Breakpoint = E.Breakpoints.OnDeath, Action = function(ctx)
		inc(Lib.stats.deaths, kitName)
		local src = ctx.source
		local killerEnt = src and src.Entity
		local origin = ctx.Lineage and ctx.Lineage.Origin
		local credit = origin or killerEnt
		local killerKit = credit and Lib.state[credit] and Lib.state[credit].kit
		if killerKit then inc(Lib.stats.kills, killerKit) end
	end })
	return e
end

function Lib.isAlive(e)
	return e and e.Active and e:HasComponent("Health") and e.IsAlive() and e.Instance and e.Instance.Parent ~= nil
end

function Lib.despawn(e)
	for i = #Lib.alive, 1, -1 do if Lib.alive[i] == e then table.remove(Lib.alive, i) end end
	local inst = e.Instance
	if inst then pcall(DataManager.Remove, inst); inst:Destroy() end
end

function Lib.enemies(e)
	local out = {}
	for _, o in ipairs(Lib.alive) do
		if o ~= e and o.Team ~= e.Team and Lib.isAlive(o) then table.insert(out, o) end
	end
	return out
end

function Lib.nearestEnemy(e, range)
	local root = e.GetRoot(); if not root then return nil end
	local best, bd = nil, range or math.huge
	for _, o in ipairs(Lib.enemies(e)) do
		local r = o.GetRoot()
		if r then
			local d = (r.Position - root.Position).Magnitude
			if d < bd then best, bd = o, d end
		end
	end
	return best, bd
end

-- WORKAROUND: framework não tem query de alvos (cone/raio/LOS) no servidor
function Lib.inCone(e, range, coneDeg)
	wa("geral", "Sem API de seleção de alvos no servidor (cone, raio, linha de visão): cada kit implementa a sua")
	local root = e.GetRoot(); if not root then return {} end
	local look = e.GetLookDirection()
	if look.Magnitude < 0.1 then look = root.CFrame.LookVector end
	look = Vector3.new(look.X, 0, look.Z).Unit
	local res = {}
	for _, o in ipairs(Lib.enemies(e)) do
		local r = o.GetRoot()
		if r then
			local to = r.Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude <= range and flat.Magnitude > 0.05 then
				local ang = math.deg(math.acos(math.clamp(flat.Unit:Dot(look), -1, 1)))
				if ang <= coneDeg / 2 then table.insert(res, o) end
			end
		end
	end
	return res
end

function Lib.inRadius(center, radius, exceptTeam)
	local res = {}
	for _, o in ipairs(Lib.alive) do
		if Lib.isAlive(o) and o.Team ~= exceptTeam then
			local r = o.GetRoot()
			if r and (r.Position - center).Magnitude <= radius then table.insert(res, o) end
		end
	end
	return res
end

-- Dano pelo pipeline oficial (OUT onHit -> TakeDamage -> OUT OnDamage)
function Lib.hit(skillSelf, target, amount, kit)
	local ok, dealt = skillSelf:Damage(target, amount)
	if ok and dealt then inc(Lib.stats.damage, kit, dealt) end
	return ok, dealt
end

-- Projétil via HitboxSpawner + Behaviors.LinearMove (sistema do framework)
function Lib.projectile(caster, origin, dir, speed, radius, life, onHitFn)
	local hb, carrier = HitboxSpawner.Spawn(caster, CFrame.lookAt(origin, origin + dir))
	hb:SetCastData({ CastType = "Spherecast", Radius = radius })
	hb:OnUpdate(Behaviors.LinearMove(carrier, dir, speed, life))
	local done = false
	hb:OnHit(function(result)
		if done or not result then return end
		local target = DataManager.GetEntityFromInstance(result.Instance)
		if target and target ~= caster and target.Team ~= caster.Team and Lib.isAlive(target) then
			done = true
			local ok, err = pcall(onHitFn, target, result)
			if not ok then warn("[KIT] onHit de projétil:", err) end
			hb:HitStop()
		end
	end)
	hb:OnStopped(function() HitboxSpawner.Cleanup(hb, carrier) end)
	hb:HitStart(life)
	return hb
end

-- Hitscan na direção de mira (AimDirection 3D)
function Lib.hitscan(caster, range)
	local root = caster.GetRoot()
	local aim = caster.GetAimDirection()
	if aim.Magnitude < 0.1 then aim = root.CFrame.LookVector end
	local params = HitboxSpawner.BuildDefaultFilter(caster)
	local res = workspace:Raycast(root.Position + Vector3.new(0, 1, 0), aim.Unit * range, params)
	if res then
		local tgt = DataManager.GetEntityFromInstance(res.Instance)
		if tgt and tgt.Team ~= caster.Team then return tgt, res end
	end
	return nil, res
end

function Lib.press(e, intent, gesture, held)
	local kit = Lib.state[e] and Lib.state[e].kit or "?"
	local ok = SkillHandler.HandleIntent(e.ID, Intents.NewEvent(intent, Intents.Kind.Activate, gesture or Intents.Gesture.Press, held))
	if ok then inc(Lib.stats.casts, kit .. ":" .. intent) else inc(Lib.stats.castFails, kit .. ":" .. intent) end
	return ok
end

function Lib.release(e, intent, held)
	return SkillHandler.HandleIntent(e.ID, Intents.NewEvent(intent, Intents.Kind.Release, nil, held))
end

-- IA genérica: anda até a distância preferida, mira e chama decide() no ritmo do kit
function Lib.brain(kit)
	return function(e, dt)
		if not Lib.isAlive(e) then return end
		local st = Lib.state[e]
		local tgt, dist = Lib.nearestEnemy(e, kit.sight or 120)
		if not tgt then SkillHandler.HandleMovementInput(e.ID, Vector3.zero); return end
		local to = tgt.GetRoot().Position - e.GetRoot().Position
		local flat = Vector3.new(to.X, 0, to.Z)
		SkillHandler.HandleLookInput(e.ID, to)
		local pref = kit.range or 5
		local move = Vector3.zero
		if flat.Magnitude > pref then move = flat elseif flat.Magnitude < pref * 0.4 then move = -flat end
		if kit.strafe then move += Vector3.new(-flat.Z, 0, flat.X).Unit * kit.strafe * math.sin(os.clock() * 2) end
		SkillHandler.HandleMovementInput(e.ID, move)
		st.t += dt
		if st.t >= (kit.think or 0.3) then
			st.t = 0
			local ok, err = pcall(kit.decide, e, tgt, flat.Magnitude)
			if not ok then warn("[KIT] decide " .. st.kit .. ":", err) end
		end
	end
end

return Lib

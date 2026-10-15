local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Lib = require(SS.__AuditKitLib)
local Kits = require(SS.__AuditKits)
local E, Intents = Lib.E, Lib.Intents
local Id = Intents.Id
local StateTable = require(SS.Modules.Combat.StateTable)
local SkillHandler = require(SSS.Modules.SkillHandler)
local SkillScheduler = require(SSS.Modules.SkillScheduler)
local HitboxWrapperMod = require(SS.Modules.Combat.Hitbox.HitboxWrapper)

local DURATION = tonumber(SS.__AUDIT:GetAttribute("ArenaDuration")) or 300
local folder = SS.__AUDIT
local out = folder:FindFirstChild("Arena") or Instance.new("StringValue")
out.Name = "Arena"; out.Parent = folder

local Arena = { samples = {}, events = {}, errors = {}, errorCount = 0, warnCount = 0, startedAt = os.clock() }
_G.__AuditArena = Arena
local function ev(s) table.insert(Arena.events, ("%.1f %s"):format(os.clock() - Arena.startedAt, s)); if #Arena.events > 300 then table.remove(Arena.events, 1) end end
Arena.ev = ev
local logConn = LogService.MessageOut:Connect(function(msg, t)
	if t == Enum.MessageType.MessageError then
		Arena.errorCount += 1
		local key = msg:gsub("%d+", "#"):sub(1, 160)
		Arena.errors[key] = (Arena.errors[key] or 0) + 1
	elseif t == Enum.MessageType.MessageWarning then
		Arena.warnCount += 1
	end
end)

local CENTER = Vector3.new(0, 103, 900)
local platform = Instance.new("Part"); platform.Name = "__AuditArenaFloor"; platform.Anchored = true
platform.Size = Vector3.new(380, 2, 380); platform.Position = CENTER - Vector3.new(0, 4, 0)
platform.Material = Enum.Material.Slate; platform.Parent = workspace

local frameDts = {}
local hb = RunService.Heartbeat:Connect(function(dt) table.insert(frameDts, dt) end)

local roster = {
	{ kit = "Pistoleira", team = "T_Pistoleira", pos = Vector3.new(-60, 0, -60), respawn = 5 },
	{ kit = "Invocador", team = "T_Invocador", pos = Vector3.new(60, 0, -60), respawn = 5 },
	{ kit = "Duelista", team = "T_Duelista", pos = Vector3.new(-60, 0, 60), respawn = 5 },
	{ kit = "Alquimista", team = "T_Alquimista", pos = Vector3.new(60, 0, 60), respawn = 5 },
	{ kit = "Ladrao", team = "T_Ladrao", pos = Vector3.new(0, 0, -80), respawn = 5 },
	{ kit = "Cronomante", team = "T_Cronomante", pos = Vector3.new(0, 0, 80), respawn = 5 },
	{ kit = "Canalizador", team = "T_Canalizador", pos = Vector3.new(-80, 0, 0), respawn = 5 },
	{ kit = "Cartas", team = "T_Cartas", pos = Vector3.new(80, 0, 0), respawn = 5 },
	{ kit = "Colosso", team = "T_Colosso", pos = Vector3.new(0, 0, 0), respawn = 15 },
	{ kit = "Torre", team = "T_Torre", pos = Vector3.new(30, 0, 30), respawn = 15 },
	{ kit = "Espelho", team = "T_Espelho", pos = Vector3.new(-30, 0, -30), respawn = 10 },
	{ kit = "Possessor", team = "T_Possessor", pos = Vector3.new(30, 0, -30), respawn = 10 },
}
Arena.byKit = {}

local function turretBrain(K)
	return function(e, dt)
		if not Lib.isAlive(e) then return end
		local st = Lib.state[e]
		st.t += dt
		if st.t < K.think then return end
		st.t = 0
		local tgt, dist = Lib.nearestEnemy(e, 90)
		if tgt then pcall(K.decide, e, tgt, dist) end
	end
end

local function spawnRole(r)
	local K = Kits[r.kit]
	local e = Lib.spawn(r.kit, r.team, CENTER + r.pos + Vector3.new(0, (K.size and K.size.Y or 3) / 2 + 0.5, 0),
		{ hp = K.hp, size = K.size, color = K.color, comps = K.comps, speed = K.speed })
	if K.anchored then e.GetRoot().Anchored = true end
	local ok, err = pcall(K.setup, e)
	if not ok then ev("setup falhou " .. r.kit .. ": " .. tostring(err)) end
	e.SetBrain(K.anchored and turretBrain(K) or Lib.brain(K))
	r.entity = e
	Arena.byKit[r.kit] = e
	ev("spawn " .. r.kit .. " " .. e.ID)
	return e
end

local swarm = {}
local function refillSwarm(n)
	for i = #swarm, 1, -1 do if not Lib.isAlive(swarm[i]) then table.remove(swarm, i) end end
	while #swarm < n do
		local a = math.random() * math.pi * 2
		local p = CENTER + Vector3.new(math.cos(a) * math.random(15, 120), 1.2, math.sin(a) * math.random(15, 120))
		local K = Kits.Enxame
		local e = Lib.spawn("Enxame", "T_Enxame", p, { hp = K.hp, size = K.size, color = K.color, speed = K.speed })
		K.setup(e)
		e.SetBrain(Lib.brain(K))
		table.insert(swarm, e)
	end
end
Arena.swarm = swarm

for _, r in ipairs(roster) do spawnRole(r) end
refillSwarm(20)

local nextSample, nextSwarm = 0, 15
local deadSince = {}
local peak = { runners = 0, mem = 0, alive = 0, frameMax = 0 }
local function chainDepth()
	local n = 0
	while StateTable.TryEnterChain() do n += 1; if n > 200 then break end end
	for _ = 1, n do StateTable.ExitChain() end
	return E.MAX_RECURSION - n
end

-- possessões automáticas IA x IA no meio da luta (oficial + workaround)
local aiPossessLog = {}
local function aiPossession(tag, host, victim)
	if not (Lib.isAlive(host) and Lib.isAlive(victim) and victim:HasComponent("Control")) then return end
	local aiBefore = victim:HasComponent("AI") and victim:GetComponent("AI").Enabled
	victim.Possess({ AI = true, Brain = function() end })
	task.wait(0.5)
	local aiAfter = victim:HasComponent("AI") and victim:GetComponent("AI").Enabled
	table.insert(aiPossessLog, ("%s: %s possui %s | IA da vítima antes=%s depois=%s"):format(tag, Lib.state[host].kit, Lib.state[victim].kit, tostring(aiBefore), tostring(aiAfter)))
	-- workaround: desliga a IA e troca o time pro lado do host por 6 s
	if victim:HasComponent("AI") then victim.SetEnabled(false) end
	local oldTeam = victim.Team
	victim.Team = host.Team
	local stop = os.clock() + 6
	while os.clock() < stop and Lib.isAlive(victim) do
		local enemy = Lib.nearestEnemy(victim, 80)
		if enemy then
			local to = enemy.GetRoot().Position - victim.GetRoot().Position
			if victim:HasComponent("Movement") then SkillHandler.HandleMovementInput(victim.ID, Vector3.new(to.X, 0, to.Z)); SkillHandler.HandleLookInput(victim.ID, to) end
			if victim:HasComponent("Combat") then Lib.press(victim, Id.Primary); Lib.press(victim, Id.Ability1) end
		end
		task.wait(0.3)
	end
	if Lib.isAlive(victim) then victim.Release(); victim.Team = oldTeam; if victim:HasComponent("AI") then victim.SetEnabled(true) end end
end
Arena.aiPossessLog = aiPossessLog

local schedule = {
	{ at = 30, fn = function() aiPossession("IA->Chefe", Arena.byKit.Possessor, Arena.byKit.Colosso) end },
	{ at = 50, fn = function() aiPossession("IA->Enxame", Arena.byKit.Ladrao, swarm[1]) end },
	{ at = 70, fn = function() aiPossession("IA->Torre", Arena.byKit.Possessor, Arena.byKit.Torre) end },
	{ at = 95, fn = function() aiPossession("IA->Espelho", Arena.byKit.Ladrao, Arena.byKit.Espelho) end },
	{ at = 120, fn = function() aiPossession("IA->Chefe(2)", Arena.byKit.Ladrao, Arena.byKit.Colosso) end },
	{ at = 160, fn = function() aiPossession("IA->Invocador", Arena.byKit.Possessor, Arena.byKit.Invocador) end },
}

local t0 = os.clock()
while os.clock() - t0 < DURATION do
	local el = os.clock() - t0
	for _, s in ipairs(schedule) do
		if not s.done and el >= s.at then s.done = true; task.spawn(function() local ok, err = pcall(s.fn); if not ok then ev("evento falhou: " .. tostring(err)) end end) end
	end
	for _, r in ipairs(roster) do
		local e = r.entity
		if e and not Lib.isAlive(e) then
			deadSince[r] = deadSince[r] or os.clock()
			if os.clock() - deadSince[r] >= r.respawn then
				ev("respawn " .. r.kit)
				Lib.despawn(e)
				deadSince[r] = nil
				spawnRole(r)
			end
		end
	end
	for i = #Lib.alive, 1, -1 do
		local o = Lib.alive[i]
		if o and not Lib.isAlive(o) and Lib.state[o] and (Lib.state[o].kit == "Enxame" or Lib.state[o].kit == "Invocador_minion") then
			Lib.state[o].deadAt = Lib.state[o].deadAt or os.clock()
			if os.clock() - Lib.state[o].deadAt > 2 then Lib.despawn(o) end
		end
	end
	if el >= nextSwarm then nextSwarm = el + 15; refillSwarm(20) end
	if el >= nextSample then
		nextSample = el + 5
		local stats = SkillScheduler:GetStats()
		local sum, mx = 0, 0
		for _, d in ipairs(frameDts) do sum += d; mx = math.max(mx, d) end
		local avg = #frameDts > 0 and sum / #frameDts or 0
		table.clear(frameDts)
		local forces, carriers, deadRunning = 0, 0, 0
		for _, o in ipairs(Lib.alive) do
			local mv = o:GetComponent("Movement")
			if mv then for _ in pairs(mv.ActiveForces) do forces += 1 end end
			if o:HasComponent("Combat") and o:HasComponent("Health") and not o.IsAlive() then
				for _, list in pairs(o.GetActiveSkills()) do for _, rr in ipairs(list) do if rr.type == E.Types.Skill and not rr:IsEnded() then deadRunning += 1 end end end
			end
		end
		for _, c in ipairs(workspace:GetChildren()) do if c.Name == "_DecoupledHitboxCarrier" then carriers += 1 end end
		local alive = 0
		for _, o in ipairs(Lib.alive) do if Lib.isAlive(o) then alive += 1 end end
		local sample = { t = math.floor(el), alive = alive, runners = stats.total, skills = stats.skills, status = stats.status,
			forces = forces, carriers = carriers, mem_kb = gcinfo(), frame_avg_ms = math.floor(avg * 10000) / 10, frame_max_ms = math.floor(mx * 10000) / 10,
			errors = Arena.errorCount, warns = Arena.warnCount, chain = chainDepth(), dead_with_running_skills = deadRunning }
		table.insert(Arena.samples, sample)
		peak.runners = math.max(peak.runners, stats.total); peak.mem = math.max(peak.mem, sample.mem_kb)
		peak.alive = math.max(peak.alive, alive); peak.frameMax = math.max(peak.frameMax, sample.frame_max_ms)
		out.Value = HttpService:JSONEncode({ done = false, samples = Arena.samples, events = Arena.events, peak = peak, aiPossess = aiPossessLog,
			stats = Lib.stats, errors = Arena.errors })
	end
	task.wait(0.2)
end

ev("fim da luta: limpando")
for i = #Lib.alive, 1, -1 do Lib.despawn(Lib.alive[i]) end
task.wait(4)
local stats = SkillScheduler:GetStats()
local carriers = 0
for _, c in ipairs(workspace:GetChildren()) do if c.Name == "_DecoupledHitboxCarrier" then carriers += 1 end end
local final = { runners_after_cleanup = stats.total, skills = stats.skills, status = stats.status, carriers_after_cleanup = carriers, mem_kb = gcinfo(),
	pool = HitboxWrapperMod.GetPoolStats().totalHitboxes, chain = chainDepth() }
hb:Disconnect(); logConn:Disconnect()
platform:Destroy()
out.Value = HttpService:JSONEncode({ done = true, samples = Arena.samples, events = Arena.events, peak = peak, final = final, aiPossess = aiPossessLog,
	stats = Lib.stats, errors = Arena.errors, workarounds = Lib.workarounds })
print("[AUDIT] Arena concluída")

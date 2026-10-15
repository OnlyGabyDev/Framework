--[[
	Sonda F43 (Defense/DamageMult sem efeito) + F62 (cadeia síncrona cortada em MAX_RECURSION).
	Resultado em ServerStorage.__AUDIT:GetAttribute("Extra2").
	Medido na auditoria: "dano 10 -> antes=10 depois=10" e "mortos=51/80".
	Depois das correções esperado: dano diferente de 10 com DamageMult x2/Defense 50 (conforme a fórmula escolhida)
	e 80/80 mortos (fila diferida em vez de corte silencioso).
]]

local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"
folder.Parent = SS

local Lib = require(SS.__AuditKitLib)
local Kits = require(SS.__AuditKits)
local SkillRunner = require(SSS.Modules.SkillRunner)
local E = Lib.E

local C = Vector3.new(300, 103, 700)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(500, 2, 120)
floor.Position = C - Vector3.new(0, 4, 0)
floor.Parent = workspace
local out = {}

-- 1) DamageMult / Defense isolados (sem adds nem fases)
local atk = Lib.spawn("AtkDM", "X1", C + Vector3.new(-200, 1.6, 0), { hp = 1000 })
local def = Lib.spawn("DefDM", "X2", C + Vector3.new(-200, 1.6, -4), { hp = 5000 })
local r = SkillRunner.new(Lib.skill("Aud_Base", { duration = 5 }, {}), atk, "Aud_Base", E.Types.Skill)
r:start()
local h0 = def.GetHP()
r:Damage(def, 10)
local d1 = h0 - def.GetHP()
atk.AddModifier("DamageMult", "Enrage", E.ModifierType.Flat, 1.0)
def.AddModifier("Defense", "Armadura", E.ModifierType.Flat, 50)
h0 = def.GetHP()
r:Damage(def, 10)
local d2 = h0 - def.GetHP()
table.insert(out, ("DamageMult x2 no atacante + Defense 50 no alvo: dano 10 -> antes=%s depois=%s"):format(d1, d2))
r:endSkill(false)
Lib.despawn(atk)
Lib.despawn(def)

-- 2) Cadeia em linha: 80 alvos a 5 studs, raio de explosão 12
local alq = Lib.spawn("Alquimista", "LA", C + Vector3.new(-220, 1.6, 30), { hp = 1000 })
local line = {}
for i = 1, 80 do
	local g = Lib.spawn("Alvo", "LB", C + Vector3.new(-200 + i * 5, 1.6, 30), { comps = { "Character", "Health", "Status" }, hp = 25 })
	g.GetRoot().Anchored = true
	g.ApplyStatus(Kits.Alquimista.Instavel, { Duration = 60 })
	Kits.Alquimista.arm(alq, g)
	table.insert(line, g)
end
task.wait(0.3)
local refused0 = Lib.stats.notes["Alquimista:explosao_recusada_MAX_RECURSION"] or 0
local runner = SkillRunner.new(Lib.skill("Aud_Det2", { duration = 1 }, {}), alq, "Aud_Det2", E.Types.Skill)
runner:start()
line[1].TakeDamage(1000, runner)
local dead = 0
for _, g in ipairs(line) do
	if not g.IsAlive() then dead += 1 end
end
table.insert(out, ("Cadeia em linha (80 alvos, raio 12, espaçamento 5): mortos=%d/80, explosões recusadas por MAX_RECURSION=%d"):format(
	dead, (Lib.stats.notes["Alquimista:explosao_recusada_MAX_RECURSION"] or 0) - refused0))
runner:endSkill(false)
for _, g in ipairs(line) do Lib.despawn(g) end
Lib.despawn(alq)
floor:Destroy()

folder:SetAttribute("Extra2", table.concat(out, "\n"))
print("[AUDIT] DamageStatsAndChainLine:\n" .. table.concat(out, "\n"))

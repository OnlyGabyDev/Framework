--[[
	Sonda F19 (Ultimate da Schema usada pelo player, agarrando 3 NPCs).
	Par do client/__AuditUltDriver.client.luau (instale o driver no PlayerGui antes ou logo depois).
	Resultado em ServerStorage.__AUDIT:GetAttribute("PlayerUlt").
	Medido na auditoria: voo a 82 studs/s, 2/3 agarrados, erro máximo 16.9 studs, 2 alvos presos 1 s após o cancel.
	Depois da correção esperado: 3/3 agarrados, erro < 2 studs, 0 presos após o cancel.
]]

local SS, RS = game:GetService("ServerStorage"), game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"
folder.Parent = SS

local Lib = require(SS.__AuditKitLib)
local DataManager = require(SSS.EntityData.DataManager)
local SkillHandler = require(SSS.Modules.SkillHandler)

RS:SetAttribute("UltGo", false)
local plr = game.Players:GetPlayers()[1] or game.Players.PlayerAdded:Wait()
local character = plr.Character or plr.CharacterAdded:Wait()
task.wait(1)
local pid = "Player_" .. plr.UserId
local body = DataManager.Get(pid)
local hrp = character:WaitForChild("HumanoidRootPart")
local out = {}

-- plataforma alta e limpa pro voo
local C = Vector3.new(600, 150, 0)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(80, 2, 500)
floor.Position = C - Vector3.new(0, 4, 0)
floor.Parent = workspace
body.Teleport(C + Vector3.new(0, 1, 200))
task.wait(1)
body.ResetCooldown("Schema_Ultimate")
local look = Vector3.new(0, 0, -1)
SkillHandler.HandleLookInput(pid, look)

local victims = {}
for i, dz in ipairs({ -10, -16, -22 }) do
	victims[i] = Lib.spawn("UltAlvo", "UV", hrp.Position + Vector3.new((i - 2) * 1.2, 0, dz), { comps = { "Character", "Health", "Status", "Movement" }, hp = 1e6, size = Vector3.new(2, 3, 1.5) })
end
task.wait(0.6)

local function grabbed(v)
	for _, f in pairs(v:GetComponent("Movement").ActiveForces) do
		if f.Type == "UltGrab" then return true end
	end
	return false
end

RS:SetAttribute("UltGo", true)
local t0 = os.clock()
local maxErr, nGrab, pPrev, spd = 0, {}, hrp.Position, {}
while os.clock() - t0 < 3.5 do
	SkillHandler.HandleLookInput(pid, look)
	local dp = hrp.CFrame:PointToWorldSpace(Vector3.new(0, 0, -4))
	for i, v in ipairs(victims) do
		if grabbed(v) then
			nGrab[i] = true
			maxErr = math.max(maxErr, (v.GetRoot().Position - dp).Magnitude)
		end
	end
	table.insert(spd, (hrp.Position - pPrev).Magnitude)
	pPrev = hrp.Position
	RunService.Heartbeat:Wait()
end
local n = 0
for _ in pairs(nGrab) do n += 1 end
local s = 0
for _, x in ipairs(spd) do s += x end
table.insert(out, ("player voando a %.0f studs/s (owner=%s) | alvos agarrados=%d/3 | erro máx do grab=%.1f studs"):format(s / 3.5, tostring(hrp:GetNetworkOwner()), n, maxErr))

body.StopAllActiveSkills(true)
task.wait(1)
local still = 0
for _, v in ipairs(victims) do
	if grabbed(v) then still += 1 end
end
table.insert(out, ("cancelando a Ultimate: %d alvo(s) continuam presos ao player 1 s depois"):format(still))

RS:SetAttribute("UltGo", false)
for _, v in ipairs(victims) do Lib.despawn(v) end
body.Teleport(Vector3.new(0, 10, 0))
floor:Destroy()
folder:SetAttribute("PlayerUlt", table.concat(out, "\n"))
print("[AUDIT] PlayerUlt:\n" .. table.concat(out, "\n"))

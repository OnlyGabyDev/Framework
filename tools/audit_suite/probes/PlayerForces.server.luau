--[[
	Sonda F32 (forças no player client-owned) + Stun no player.
	Precisa do player real no Play. Resultado em ServerStorage.__AUDIT:GetAttribute("PlayerForces").
	Medido na auditoria: Stun canMove=false/WalkSpeed=0; Hard 40x0.5s = 16.3 studs;
	Soft MaxForce 35000 = 2.6 studs; Soft padrão (2500) = 0.6 studs (esperado ~20).
]]

local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"
folder.Parent = SS

local DataManager = require(SSS.EntityData.DataManager)
local StateTable = require(SS.Modules.Combat.StateTable)

local plr = game.Players:GetPlayers()[1] or game.Players.PlayerAdded:Wait()
local character = plr.Character or plr.CharacterAdded:Wait()
task.wait(1)
local body = DataManager.Get("Player_" .. plr.UserId)
local hrp = character:WaitForChild("HumanoidRootPart")
local hum = character:WaitForChild("Humanoid")
local out = {}

local id = body.ApplyStatus(StateTable.States.Stun, { Duration = 2 })
task.wait(0.3)
local tags = body.GetActiveTags()
table.insert(out, ("Stun id=%s canMove=%s WalkSpeed(servidor)=%s"):format(tostring(id), tostring(tags.canMove), tostring(hum.WalkSpeed)))
body.RemoveStatus("Stun")
task.wait(0.3)

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local p0 = hrp.Position
body.AddForce({ Type = "HardPush", Duration = 0.5, Speed = 40, Direction = Vector3.xAxis, Hard = true, Axes = { X = true }, RequiresControl = false })
task.wait(0.7)
table.insert(out, ("Hard 40 studs/s por 0.5 s no player: %.1f studs (owner=%s)"):format(flat(hrp.Position - p0).Magnitude, tostring(hrp:GetNetworkOwner())))

p0 = hrp.Position
body.AddForce({ Type = "SoftBig", Duration = 0.5, Speed = 40, Direction = Vector3.xAxis, MaxForce = 35000, RequiresControl = false })
task.wait(0.7)
table.insert(out, ("Soft 40 studs/s MaxForce 35000 por 0.5 s no player: %.1f studs"):format(flat(hrp.Position - p0).Magnitude))

p0 = hrp.Position
body.AddForce({ Type = "SoftDefault", Duration = 0.5, Speed = 40, Direction = Vector3.xAxis, RequiresControl = false })
task.wait(0.7)
table.insert(out, ("Soft 40 studs/s (força padrão 2500) por 0.5 s no player: %.1f studs"):format(flat(hrp.Position - p0).Magnitude))

folder:SetAttribute("PlayerForces", table.concat(out, "\n"))
print("[AUDIT] PlayerForces:\n" .. table.concat(out, "\n"))

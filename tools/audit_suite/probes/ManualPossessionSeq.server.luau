--[[
	Sonda de possessão manual (F04, F21, F58 e conflito player x IA no mesmo corpo).
	Par do client/__AuditDriver.client.luau (instale o driver no PlayerGui; ele reage a ReplicatedStorage.AuditStep).
	Resultado em ServerStorage.__AUDIT:GetAttribute("ManualSeq").
	Na auditoria, o passo 2 (possuir o enxame estando na torre) lançou
	"Network Ownership API cannot be called on Anchored parts" em ControlComponent:76
	e a rota ficou presa na torre. Depois da correção, a sequência inteira deve rodar
	e terminar com a rota no corpo do player.
]]

local SS, RS = game:GetService("ServerStorage"), game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local LogService = game:GetService("LogService")
local HttpService = game:GetService("HttpService")
local folder = SS:FindFirstChild("__AUDIT") or Instance.new("Folder")
folder.Name = "__AUDIT"
folder.Parent = SS

local Lib = require(SS.__AuditKitLib)
local Kits = require(SS.__AuditKits)
local AC = require(SSS.Modules.GlobalAntiCheat)
local DataManager = require(SSS.EntityData.DataManager)
local ControlComponent = require(SSS.EntityData.Components.ControlComponent)

local plr = game.Players:GetPlayers()[1] or game.Players.PlayerAdded:Wait()
local pid = "Player_" .. plr.UserId
local function resetPlayer()
	pcall(function()
		AC.UnlockPlayerInput(plr)
		ControlComponent.ReleasePlayer(plr) -- a pilha de controle mora no ControlComponent (a PriorControlledID do AC saiu)
		AC.SetControlledEntity(plr, pid)
		AC.SetNativeControlSuspended(plr, false)
		local b = DataManager.Get(pid)
		if b then
			b.SetDrivesInput(false)
			b.SetDirection(Vector3.zero)
			b.GetRoot():SetNetworkOwner(plr)
		end
	end)
end
resetPlayer()

local log = {}
local function L(s) table.insert(log, ("%.1f %s"):format(workspace.DistributedGameTime, s)) end
local stub, dirs, intents = 0, 0, 0
local c1 = LogService.MessageOut:Connect(function(msg, t) if t == Enum.MessageType.MessageWarning and msg:find("Componente ignorado") then stub += 1 end end)
local c2 = RS.RemoteEvents.RequestDir.OnServerEvent:Connect(function() dirs += 1 end)
local c3 = RS.RemoteEvents.RequestIntent.OnServerEvent:Connect(function() intents += 1 end)

local C = Vector3.new(300, 103, -900)
local floor = Instance.new("Part")
floor.Anchored = true
floor.Size = Vector3.new(160, 2, 160)
floor.Position = C - Vector3.new(0, 4, 0)
floor.Parent = workspace
local function mk(kit, team, pos, comps)
	local K = Kits[kit]
	local e = Lib.spawn(kit, team, C + pos + Vector3.new(0, (K.size and K.size.Y or 3) / 2 + 0.5, 0), { hp = K.hp, size = K.size, color = K.color, comps = comps or K.comps, speed = K.speed })
	if K.anchored then e.GetRoot().Anchored = true end
	K.setup(e)
	return e
end
local T = mk("Torre", "Q_Torre", Vector3.new(0, 0, 0), { "Character", "Health", "Status", "Combat", "AI", "Control" })
T.SetBrain(function() end)
local S = mk("Enxame", "Q_Enxame", Vector3.new(-20, 0, 0))
S.SetBrain(Lib.brain(Kits.Enxame))
local bag = Lib.spawn("Saco", "Q_Saco", C + Vector3.new(0, 1.5, -12), { comps = { "Character", "Health", "Status" }, hp = 5000 })
bag.GetRoot().Anchored = true
local function step(name) RS:SetAttribute("AuditStep", name); L("STEP " .. name) end
task.wait(1)

local ok, err = pcall(function()
	-- 1) Torre (sem Movement)
	T.Possess({ Player = plr })
	L(("possuir torre: rota=%s"):format(tostring(AC.GetEntityID(plr) == T.ID)))
	local stub0, dirs0, int0 = stub, dirs, intents
	local bag0 = bag.GetHP()
	step("tower")
	local cdMax = 0
	local t0 = os.clock()
	while os.clock() - t0 < 5 do cdMax = math.max(cdMax, T.GetCooldown("Tor_Disparo")); task.wait(0.05) end
	L(("torre: RequestDir=%d RequestIntent=%d warns_de_stub=%d maior_cd_Disparo=%.2f dano_no_saco=%d"):format(dirs - dirs0, intents - int0, stub - stub0, cdMax, bag0 - bag.GetHP()))

	-- 2) Enxame sem soltar a torre (possessão aninhada a partir de raiz ancorada)
	local s0 = S.GetRoot().Position
	S.Possess({ Player = plr })
	L(("possuir enxame sem soltar torre: rota=%s torre.Controller.Player=%s"):format(tostring(AC.GetEntityID(plr) == S.ID), tostring(T.GetController().Player)))
	step("swarm")
	local cdS = 0
	t0 = os.clock()
	while os.clock() - t0 < 5 do cdS = math.max(cdS, S.GetCooldown("Enx_Ferrao")); task.wait(0.05) end
	L(("enxame: deslocamento=%.1f studs, IA_do_enxame_ligada=%s, maior_cd_Ferrao=%.2f"):format((S.GetRoot().Position - s0).Magnitude, tostring(S:GetComponent("AI").Enabled), cdS))

	-- 3) Solta enxame, depois torre
	S.Release(); task.wait(0.3)
	L("após S.Release: rota=" .. (AC.GetEntityID(plr) == T.ID and "TORRE" or (AC.GetEntityID(plr) == pid and "CORPO" or tostring(AC.GetEntityID(plr)))))
	T.Release(); task.wait(0.3)
	local r = AC.GetEntityID(plr)
	L("após T.Release: rota=" .. (r == T.ID and "TORRE (presa)" or (r == pid and "CORPO" or tostring(r))) .. " owner_corpo=" .. tostring(DataManager.Get(pid).GetRoot():GetNetworkOwner()))
	resetPlayer()

	-- 4) Conflito: player e IA possuindo o mesmo corpo
	S.Possess({ Player = plr }); task.wait(0.2)
	S.Possess({ AI = true, Brain = function() end }); task.wait(0.2)
	L(("conflito: rota_player=%s controller=%s"):format(tostring(AC.GetEntityID(plr) == S.ID), HttpService:JSONEncode({ P = tostring(S.GetController().Player), AI = S.GetController().AI })))
	S.Release(); task.wait(0.3)
	r = AC.GetEntityID(plr)
	L("após Release da IA: rota_player=" .. (r == S.ID and "ENXAME (player continua preso)" or (r == pid and "CORPO" or tostring(r))) .. " GetPossessionOf=" .. tostring(ControlComponent.GetPossessionOf(plr) ~= nil))
end)
if not ok then L("ERRO: " .. tostring(err)) end

step("done")
resetPlayer()
c1:Disconnect(); c2:Disconnect(); c3:Disconnect()
for _, e in ipairs({ T, S, bag }) do Lib.despawn(e) end
floor:Destroy()
folder:SetAttribute("ManualSeq", table.concat(log, "\n"))
print("[AUDIT] ManualPossessionSeq:\n" .. table.concat(log, "\n"))

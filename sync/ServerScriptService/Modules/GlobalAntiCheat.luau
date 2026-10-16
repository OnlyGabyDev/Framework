--====================== GLOBAL ANTI CHEAT ======================--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local DataManager = require(Server.EntityData.DataManager)
local RunService = game:GetService("RunService")

local MIN_INPUT_INTERVAL = 0.015

local RemoteEvents = ReplicatedStorage.RemoteEvents
local ControlStateChanged = RemoteEvents:WaitForChild("ControlStateChanged")

-- Sempre o estado COMPLETO numa mensagem só (F22): antes cada setter mandava a sua, e o
-- suspendNative=true do Possess era sobrescrito pela mensagem seguinte com false.
local function notifyControlState(player: Player, tracked)
	ControlStateChanged:FireClient(player, tracked.Locked, not tracked.Locked and tracked.ID or nil, tracked.SuspendNative)
end

local AntiCheat = {}
local TrackedPlayers = {}
local connection

function AntiCheat.Init()
	if not connection then
		connection = RunService.Heartbeat:Connect(function(dt)
			AntiCheat._Update(dt)
		end)
		warn("[AntiCheat] Iniciado")
	end
end

--=====REGISTRO DE PLAYERS=====--

function AntiCheat.Register(Player)
	local ID = Player.Character and Player.Character:GetAttribute("EntityID")
	if not ID then return end
	local entityCore = DataManager.Get(ID)
	if not entityCore then return end

	TrackedPlayers[Player] = {
		LastPosition = nil,
		ID = ID,
		NativeID = ID,
		Locked = false,
		PreLockID = nil,
		SuspendNative = false, -- o cliente desliga o WASD nativo (está dirigindo outro corpo)
	}
end

function AntiCheat.Unregister(Player)
	TrackedPlayers[Player] = nil
end

--=====FUNÇÕES UTILITARIAS=====--

function AntiCheat.GetEntityID(Player)
	local tracked = TrackedPlayers[Player]
	return tracked and tracked.ID
end

function AntiCheat.GetControlledEntityId(Player)
	local tracked = TrackedPlayers[Player]
	if not tracked then return nil end
	if tracked.Locked then
		return tracked.PreLockID
	end
	return tracked.ID
end

--[[ ID do corpo do próprio player (base da pilha de controle do ControlComponent) ]]
function AntiCheat.GetNativeEntityId(Player)
	local tracked = TrackedPlayers[Player]
	return tracked and tracked.NativeID
end

function AntiCheat.SetNativeControlSuspended(Player, suspended)
	local tracked = TrackedPlayers[Player]
	if not tracked then return false end
	tracked.SuspendNative = suspended == true
	notifyControlState(Player, tracked)
	return true
end

--[[
Redireciona pra qual entidade o input desse player vai. Se o player estiver
Locked, NÃO deixa vazar input agora — só atualiza o que será restaurado no
Unlock. Sem essa checagem, um Possess acidental durante um Lock (cutscene)
furaria o corte.
@param suspendNative - opcional: atualiza junto, na MESMA mensagem, se o cliente
	desliga o WASD nativo (nil mantém o estado atual)
]]
function AntiCheat.SetControlledEntity(Player, entityID, suspendNative)
	local tracked = TrackedPlayers[Player]
	if not tracked then return false end

	if suspendNative ~= nil then
		tracked.SuspendNative = suspendNative
	end

	if tracked.Locked then
		tracked.PreLockID = entityID
		return true
	end

	tracked.ID = entityID
	notifyControlState(Player, tracked)
	return true
end

--[[
Corta TODO input desse player na raiz: GetEntityID passa a devolver nil, e
todo handler (HandleMovementInput, HandleLookInput, HandleIntent) já tem
guard "if not ID then return end" — zero verificação nova precisa ser
espalhada pelo resto do código.
]]
function AntiCheat.LockPlayerInput(Player)
	local tracked = TrackedPlayers[Player]
	if not tracked or tracked.Locked then return false end
	tracked.Locked = true
	tracked.PreLockID = tracked.ID
	tracked.ID = nil
	notifyControlState(Player, tracked)
	return true
end

function AntiCheat.UnlockPlayerInput(Player)
	local tracked = TrackedPlayers[Player]
	if not tracked or not tracked.Locked then return false end
	tracked.Locked = false
	tracked.ID = tracked.PreLockID
	tracked.PreLockID = nil
	notifyControlState(Player, tracked)
	return true
end

function AntiCheat.CheckInput(Player, LastInput)
	if os.clock() - LastInput < MIN_INPUT_INTERVAL then return nil end
	return AntiCheat.GetEntityID(Player)
end

--=====FUNÇÕES INTERNAS=====--

function AntiCheat.CheckPosition()
end

function AntiCheat.CheckNoClip()
end

function AntiCheat.UpdatePlayerInputData()
end

--=====HEARTBEAT=====--

function AntiCheat._Update(dt)
end

AntiCheat.Init()

return AntiCheat

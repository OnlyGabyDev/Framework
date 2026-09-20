

--====================== GLOBAL ANTI CHEAT ======================--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local DataManager = require(Server.EntityData.DataManager)
local RunService = game:GetService("RunService")

local MIN_INPUT_INTERVAL = 0.015 -- 1 Frame = 0,0166... secs

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
		ID = ID
	}

end

function AntiCheat.Unregister(Player)
	TrackedPlayers[Player] = nil
end

--=====FUNÇÕES UTILITARIAS=====--

--[[
Devolve o ID da entidade do player (nil se ainda não registrado)
Único caminho de "player -> ID" para a camada de input.
@param Player - dono do input
@return ID STRING ou nil
]]
function AntiCheat.GetEntityID(Player)
	local tracked = TrackedPlayers[Player]
	return tracked and tracked.ID
end

--[[
Valida o intervalo mínimo entre dois inputs do mesmo tipo (o chamador decide o que é "mesmo tipo":
movimento, ou uma intent específica).
@param Player - dono do input
@param LastInput - os.clock() do último input aceito desse tipo
@return ID do player, ou nil se rejeitado
]]
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

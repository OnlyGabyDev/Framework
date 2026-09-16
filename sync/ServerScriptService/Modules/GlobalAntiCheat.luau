


--====================== GLOBAL ANTI CHEAT ======================--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local DataManager = require(Server.EntityData.DataManager)
local RunService = game:GetService("RunService")

local AntiCheat = {}
local TrackedPlayers = {}
local connection
local valid

function AntiCheat.Init()
    if not connection then
		connection = RunService.Heartbeat:Connect(function(dt)
			AntiCheat._Update(dt)
		end)
	print("[AntiCheat] Iniciado")
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
Valida a diferença entre último input de movimento e o atual
@param Player - dono do input
@return ID - ID do player
]]
function AntiCheat.CheckMovementInput(Player,LastInput)
    valid = tick() - LastInput >= 0.015 -- 1 Frame = 0,0166... secs
    return valid and TrackedPlayers[Player].ID
end


--[[
Valida a diferença entre último input de skill e o atual
@param Player - dono do input
@return ID - ID do player
]]
function AntiCheat.CheckSkillInput(Player,LastInput)
    valid = tick() - LastInput >= 0.015 -- 1 Frame = 0,0166... secs
    return valid and TrackedPlayers[Player].ID
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
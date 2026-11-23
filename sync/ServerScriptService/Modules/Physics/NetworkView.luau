--[[
NetworkView: dono único de "quanto atrasado o servidor vê um corpo simulado por um cliente".

O corpo do player (e o que ele possui) é simulado pelo cliente e replicado para o servidor com
atraso: o servidor vê o corpo ~0,35 s atrás do que o cliente sente, sem contar o ping. Uma decisão
do servidor tomada com essa posição chega tarde no cliente (ex.: uma zona de vento veria o player
sair 0,35 s depois de ele sair de verdade, e o vento seguiria empurrando no cliente).

Corpo do servidor (NPC, ancorado) não tem atraso: as funções devolvem nil para ele.
]]

local Settings = require(script.Parent.Settings)

local NetworkView = {}

--[[ Segundos de atraso com que o servidor vê o corpo simulado por `player` ]]
function NetworkView.Lag(player: Player): number
	return Settings.Client_View_Lag + player:GetNetworkPing() * Settings.Client_View_Ping_Factor
end

--[[
Quanto o corpo andou desde a posição que o servidor vê: velocidade vista × atraso do dono.
@param part - peça do corpo (o root) BasePart
@return Vector3, ou nil se o corpo é do servidor (sem atraso)
]]
function NetworkView.PredictedShift(part: BasePart): Vector3?
	if part.Anchored or not part:IsDescendantOf(workspace) then return nil end
	local ok, owner = pcall(part.GetNetworkOwner, part)
	if not ok or owner == nil then return nil end
	return part.AssemblyLinearVelocity * NetworkView.Lag(owner)
end

return NetworkView

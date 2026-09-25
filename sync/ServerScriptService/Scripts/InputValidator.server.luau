--[[
	InputValidator (SERVIDOR) — única borda de rede do input.
	Valida tipo/faixa/taxa e entrega ao resto do framework:

	  RequestIntent(intent, isDown) -> GestureResolver -> SkillHandler.HandleIntent
	  RequestDir(Vector3)           -> SkillHandler.HandleMovementInput
	  RequestLook(Vector3)          -> SkillHandler.HandleLookInput

	Nada aqui conhece skill, tecla ou dispositivo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")

local Intents = require(ReplicatedStorage.Input.Intents)
local GestureResolver = require(ReplicatedStorage.Input.GestureResolver)
local DataManager = require(Server.EntityData.DataManager)
local AntiCheat = require(Server.Modules.GlobalAntiCheat)
local SkillHandler = require(Server.Modules.SkillHandler)
local InputSessions = require(Server.Modules.InputSessions)

local Remotes = ReplicatedStorage.RemoteEvents
local RequestIntent = Remotes.RequestIntent
local RequestDir = Remotes.RequestDir
local RequestLook = Remotes.RequestLook
local SkillFired = Remotes.SkillFired

local MAX_AXIS_MAGNITUDE = 1.5 -- direções chegam ~normalizadas; folga para float

local function isVectorInRange(value: any, min: number, max: number): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local magnitude = value.Magnitude
	return magnitude >= min and magnitude <= max
end

--[[ Único ponto onde um InputEvent vira ação no framework (chamado pelo resolver, inclusive em timers). ]]
local function dispatch(player: Player, event)
	if not player.Parent then
		return
	end
	local ID = AntiCheat.GetEntityID(player)
	if not ID then
		return
	end

	local success, skillName, cooldown = SkillHandler.HandleIntent(ID, event)
	if success and skillName and cooldown then
		-- A UI é por SLOT, não por skill: manda a intent (o botão da tela carrega o mesmo atributo).
		-- Assim trocar de personagem/forma ou roubar uma skill não exige nenhum elemento novo de UI.
		SkillFired:FireClient(player, event.Intent, cooldown)
	end
end

local function getResolver(player: Player, session, intent: string)
	local resolver = session.resolvers[intent]
	if not resolver then
		resolver = GestureResolver.new(intent, function(event)
			dispatch(player, event)
		end)
		session.resolvers[intent] = resolver
	end
	return resolver
end

--=============================================================================
--  INTENTS (botões)
--=============================================================================

RequestIntent.OnServerEvent:Connect(function(player: Player, intent: any, isDown: any)
	if typeof(isDown) ~= "boolean" or not Intents.IsButton(intent) then
		return
	end

	local ID = AntiCheat.GetEntityID(player)
	if not ID then
		return
	end

	local session = InputSessions.GetSession(player)
	local resolver = getResolver(player, session, intent)

	-- Release NUNCA passa por rate limit: perder um Release deixaria a skill presa em "segurado".
	-- Não abre brecha: Release sem Press correspondente é no-op no resolver.
	if not isDown then
		resolver:Release(os.clock())
		return
	end

	-- Rate limit por intent (antes era um único relógio por player: dois botões no mesmo frame perdiam um)
	if not AntiCheat.CheckInput(player, session.lastPress[intent] or 0) then
		return
	end
	session.lastPress[intent] = os.clock()

	local entityCore = DataManager.Get(ID)
	if not entityCore then
		return
	end

	-- A spec é lida AGORA e fica congelada no resolver durante o ciclo (trocar de slot no meio não afeta)
	local spec = GestureResolver.Normalize(SkillHandler.GetGestureSpec(entityCore, intent))
	resolver:Press(os.clock(), spec)
end)

--=============================================================================
--  EIXOS (Move / Look)
--=============================================================================

RequestDir.OnServerEvent:Connect(function(player: Player, direction: any)
	if not isVectorInRange(direction, 0, MAX_AXIS_MAGNITUDE) then
		return
	end

	local session = InputSessions.GetSession(player)

	local ID
	if direction.Magnitude < 0.01 then
		ID = AntiCheat.GetEntityID(player) -- "parar" nunca passa por rate limit
	else
		ID = AntiCheat.CheckInput(player, session.lastMove)
	end
	if not ID then
		return
	end

	session.lastMove = os.clock()
	SkillHandler.HandleMovementInput(ID, direction)
end)

--[[
RequestLook não passa pelo rate limit de propósito: essa direção só influencia a TRAJETÓRIA
do PRÓPRIO caster durante uma Force com Direction dinâmico. (Chega por UnreliableRemoteEvent.)
]]
RequestLook.OnServerEvent:Connect(function(player: Player, look: any)
	if not isVectorInRange(look, 0.5, MAX_AXIS_MAGNITUDE) then
		return
	end

	local ID = AntiCheat.GetEntityID(player)
	if not ID then
		return
	end

	SkillHandler.HandleLookInput(ID, look.Unit)
end)

--=============================================================================
--  CICLO DE VIDA
--=============================================================================

local function trackPlayer(player: Player)
	-- Respawn: a entidade antiga ainda existe neste instante, então o Release chega e as skills seguradas encerram limpo.
	player.CharacterRemoving:Connect(function()
		InputSessions.CancelActiveGestures(player, false)
	end)
end

Players.PlayerAdded:Connect(trackPlayer)
for _, player in Players:GetPlayers() do
	trackPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	InputSessions.CancelActiveGestures(player, true)
end)

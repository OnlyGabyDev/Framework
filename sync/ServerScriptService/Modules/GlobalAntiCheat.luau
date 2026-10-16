--====================== GLOBAL ANTI CHEAT ======================--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService")
local DataManager = require(Server.EntityData.DataManager)
local Settings = require(Server.Modules.Physics.Settings)
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

--=====VALIDAÇÃO DE MOVIMENTO (F05)=====--
--[[
O corpo nativo do player é simulado pelo cliente (modelo B do F05). A cada Heartbeat o servidor
compara o deslocamento desde a última posição aceita com o que dava para andar: WalkSpeed do
SERVIDOR (o cliente muda o dele, mas isso não replica), Forces ativas e chão móvel. O que passa
disso vira correção: o corpo volta à última posição aceita.

Crédito (token bucket): enche na velocidade permitida, até Movement_Burst_Seconds dela, e é gasto
pelo movimento aceito. A dívida (até Movement_Excess_Limit) não é perdoada na correção, então na
média ninguém passa da velocidade permitida; o máximo ganho de uma vez é crédito + excesso.

Movimento feito pelo servidor não vira correção: no servidor, o CFrame-changed da raiz só dispara
para escrita de script. A física do cliente, inclusive um CFrame forçado por exploit, não dispara
(medido em 16/10). Cada escrita abre Movement_Trust_Seconds de confiança; a correção do próprio
validador é descontada (SelfWrites).

Fora de escopo (F05): noclip (CheckNoClip), subida contínua até a velocidade de pulo (voo),
compensação de latência, empurrão físico fora das Forces (colisão, Explosion) e veículos (com o
player sentado o corpo não é validado).
]]

--[[
Liga a validação à raiz do corpo nativo. Dono do formato de tracked.Move:
{
	Root: BasePart, Humanoid: Humanoid,
	Entity: EntityCore?,            -- corpo nativo (orçamento das Forces)
	Conn: RBXScriptConnection,      -- CFrame-changed da raiz (escrita de script no servidor)
	Params: RaycastParams,          -- raycast do chão, sem o próprio personagem
	LastValid: Vector3,             -- última posição aceita
	Credit: number,                 -- crédito horizontal (studs); negativo = dívida
	CreditUp: number,               -- crédito de subida (studs)
	PeakH: number, PeakHUntil: number, -- velocidade horizontal permitida, segurada pela janela de latência
	PeakV: number, PeakVUntil: number, -- idem, subida
	TrustUntil: number,             -- os.clock(): fim da confiança depois de movimento do servidor
	SelfWrites: number, SelfWriteAt: number, -- correções ainda não vistas pelo sinal
	Owned: boolean,                 -- o corpo era do player no frame anterior
	LastWarnAt: number,
}
]]
local function bindMovement(tracked, root: BasePart, humanoid: Humanoid)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }

	local move = {
		Root = root,
		Humanoid = humanoid,
		Entity = DataManager.Get(tracked.NativeID),
		Params = params,
		LastValid = root.Position,
		Credit = 0,
		CreditUp = 0,
		PeakH = 0, PeakHUntil = 0,
		PeakV = 0, PeakVUntil = 0,
		TrustUntil = os.clock() + Settings.Movement_Trust_Seconds, -- spawn: o servidor acabou de posicionar o corpo
		SelfWrites = 0, SelfWriteAt = 0,
		Owned = false,
		LastWarnAt = -math.huge,
	}
	move.Conn = root:GetPropertyChangedSignal("CFrame"):Connect(function()
		if move.SelfWrites > 0 and os.clock() - move.SelfWriteAt < 1 then
			move.SelfWrites -= 1 -- correção do próprio validador
			return
		end
		move.SelfWrites = 0
		move.TrustUntil = os.clock() + Settings.Movement_Trust_Seconds
	end)
	tracked.Move = move
	return move
end

local function unbindMovement(tracked)
	local move = tracked.Move
	if move then
		move.Conn:Disconnect()
		tracked.Move = nil
	end
end

-- Aceita a posição atual sem conferir (corpo do servidor, janela de confiança)
local function rebase(move)
	move.LastValid = move.Root.Position
	move.Credit = 0
	move.CreditUp = 0
end

-- Velocidade permitida com memória curta: uma maior (um Dash que acabou de terminar no servidor)
-- segue valendo por Movement_Latency_Window, porque o cliente ainda está aplicando a Force.
local function holdPeak(peak: number, peakUntil: number, value: number, now: number): (number, number)
	if value >= peak or now >= peakUntil then
		return value, now + Settings.Movement_Latency_Window
	end
	return peak, peakUntil
end

local function jumpSpeed(humanoid: Humanoid): number
	if humanoid.UseJumpPower then
		return humanoid.JumpPower
	end
	return math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
end

-- Velocidade do chão sob o player (plataforma móvel, esteira com AssemblyLinearVelocity)
local function groundSpeed(move): (number, number)
	local root, humanoid = move.Root, move.Humanoid
	local depth = humanoid.HipHeight + root.Size.Y / 2 + Settings.Movement_Ground_Probe
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -depth, 0), move.Params)
	if not hit then return 0, 0 end
	local v = hit.Instance:GetVelocityAtPosition(hit.Position)
	return Vector3.new(v.X, 0, v.Z).Magnitude, math.abs(v.Y)
end

local function correct(player: Player, tracked, move, now: number)
	local root = move.Root
	move.SelfWrites += 1
	move.SelfWriteAt = now
	root.CFrame = CFrame.new(move.LastValid) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	tracked.Corrections += 1
	if now - move.LastWarnAt >= Settings.Movement_Warn_Interval then
		move.LastWarnAt = now
		warn(("[AntiCheat] Movimento recusado: %s voltou à última posição válida (%d correções)"):format(player.Name, tracked.Corrections))
	end
end

local function validateMovement(player: Player, tracked, dt: number, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or root.Anchored or not root:IsDescendantOf(workspace) or humanoid.Health <= 0 or humanoid.SeatPart then
		unbindMovement(tracked) -- sem corpo validável agora: religa (e rebaseia) quando voltar
		return
	end

	local move = tracked.Move
	if not move or move.Root ~= root then
		unbindMovement(tracked)
		move = bindMovement(tracked, root, humanoid)
	end

	-- Corpo do servidor (possessão) não é validado: o servidor já manda nele. Quando ele volta ao
	-- player abre a janela de confiança, porque o servidor o moveu enquanto era o dono.
	if root:GetNetworkOwner() ~= player then
		move.Owned = false
		rebase(move)
		return
	elseif not move.Owned then
		move.Owned = true
		move.TrustUntil = now + Settings.Movement_Trust_Seconds
	end

	if now < move.TrustUntil then
		rebase(move)
		return
	end

	-- O Lock corta o input no servidor mas não zera o WalkSpeed: a caminhada e o pulo saem daqui
	local walk = tracked.Locked and 0 or humanoid.WalkSpeed * Settings.Movement_Speed_Tolerance
	local jump = tracked.Locked and 0 or jumpSpeed(humanoid)
	local forceH, forceV = 0, 0
	local entity = move.Entity
	-- Dependência opcional do MovementComponent (regra 16): sem ele, nenhuma Force soma
	if entity and entity.Active and entity:HasComponent(entity.ComponentKey.Movement) then
		forceH, forceV = entity.GetForceSpeedBudget()
	end
	local groundH, groundV = groundSpeed(move)
	local slack = Settings.Movement_Speed_Slack
	move.PeakH, move.PeakHUntil = holdPeak(move.PeakH, move.PeakHUntil, walk + forceH + groundH + slack, now)
	move.PeakV, move.PeakVUntil = holdPeak(move.PeakV, move.PeakVUntil, jump + forceV + groundV + slack, now)

	local burst = Settings.Movement_Burst_Seconds
	local credit = math.min(move.Credit + move.PeakH * dt, move.PeakH * burst)
	local creditUp = math.min(move.CreditUp + move.PeakV * dt, move.PeakV * burst)

	local delta = root.Position - move.LastValid
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local rise = math.max(delta.Y, 0) -- cair é livre

	local limit = Settings.Movement_Excess_Limit
	if horizontal > credit + limit or rise > creditUp + limit then
		-- Recusado: o movimento não gasta crédito, e a dívida que já existia continua
		move.Credit, move.CreditUp = credit, creditUp
		correct(player, tracked, move, now)
		return
	end
	move.Credit = credit - horizontal
	move.CreditUp = creditUp - rise
	move.LastValid = root.Position
end

--=====REGISTRO DE PLAYERS=====--

function AntiCheat.Register(Player)
	local ID = Player.Character and Player.Character:GetAttribute("EntityID")
	if not ID then return end
	local entityCore = DataManager.Get(ID)
	if not entityCore then return end

	-- Respawn recria o estado: solta o sinal da raiz antiga antes
	local previous = TrackedPlayers[Player]
	if previous then unbindMovement(previous) end

	TrackedPlayers[Player] = {
		ID = ID,
		NativeID = ID,
		Locked = false,
		PreLockID = nil,
		SuspendNative = false, -- o cliente desliga o WASD nativo (está dirigindo outro corpo)
		Move = nil, -- validação de movimento do corpo nativo (formato em bindMovement); liga no próximo Heartbeat
		Corrections = 0, -- movimentos recusados desde o spawn (GetMovementCorrections)
	}
end

function AntiCheat.Unregister(Player)
	local tracked = TrackedPlayers[Player]
	if tracked then unbindMovement(tracked) end
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

--[[ Quantas vezes o movimento do player foi recusado (e o corpo devolvido) desde o spawn ]]
function AntiCheat.GetMovementCorrections(Player): number
	local tracked = TrackedPlayers[Player]
	return tracked and tracked.Corrections or 0
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

-- A checagem de posição é a validação de movimento (seção VALIDAÇÃO DE MOVIMENTO acima)

function AntiCheat.CheckNoClip()
end

function AntiCheat.UpdatePlayerInputData()
end

--=====HEARTBEAT=====--

function AntiCheat._Update(dt)
	if not Settings.Movement_Validation_Enabled then return end
	local now = os.clock()
	for player, tracked in TrackedPlayers do
		local ok, err = pcall(validateMovement, player, tracked, dt, now)
		if not ok then
			warn("[AntiCheat] Erro validando movimento:", player.Name, err)
		end
	end
end

AntiCheat.Init()

return AntiCheat

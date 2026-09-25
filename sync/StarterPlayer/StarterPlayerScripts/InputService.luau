--[[
	InputService (CLIENTE)
	Traduz inputs fisicos do player em intenções, não se importa com double tap, press,hold...

	FONTES
	  - Teclado/mouse/gamepad:            lookup derivado de InputConfig.Bindings
	  - Botão de tela (mobile/UI):        qualquer GuiButton com a tag e o atributo de InputConfig
	  - Código (npcs):                    InputService.Press(intent, source) / Release(intent, source)


]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Intents = require(ReplicatedStorage.Input.Intents)
local InputConfig = require(ReplicatedStorage.Config.InputConfig)

local Remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
local RequestIntent = Remotes:WaitForChild("RequestIntent")
local RequestDir = Remotes:WaitForChild("RequestDir")

local MOVE_SEND_INTERVAL = 1 / 20 -- Hz máximo de RequestDir (parar sempre sai na hora)
local MOVE_EPSILON = 0.01 -- variação mínima de direção para valer um envio 

local InputService = {}

local active: { [string]: { [any]: true } } = {} -- [intent][fonte] = true
local lookup: { [EnumItem]: { string } } = {} -- [código físico] = { intents }
local bindings: { [string]: { EnumItem } } = {} -- cópia mutável de InputConfig.Bindings
local started = false


--=============================================================================
--  ESTADO DAS INTENTS
--=============================================================================

--[[
@param intent - Intents.Id
@param source - qualquer valor único da fonte (EnumItem, InputObject, GuiButton...)
]]
function InputService.Press(intent: string, source: any)
	local sources = active[intent]
	if not sources then
		sources = {}
		active[intent] = sources
	end
	if sources[source] then
		return
	end

	local wasIdle = next(sources) == nil
	sources[source] = true
	if wasIdle then
		RequestIntent:FireServer(intent, true)
	end
end

function InputService.Release(intent: string, source: any)
	local sources = active[intent]
	if not sources or not sources[source] then
		return
	end

	sources[source] = nil
	if next(sources) == nil then
		RequestIntent:FireServer(intent, false)
	end
end

local function releaseIntent(intent: string)
	local sources = active[intent]
	if sources and next(sources) ~= nil then
		table.clear(sources)
		RequestIntent:FireServer(intent, false)
	end
end

--[[ Solta tudo (alt-tab, troca de personagem). O servidor ignora Release sem Press. ]]
function InputService.ReleaseAll()
	for intent in active do
		releaseIntent(intent)
	end
end

--=============================================================================
--  BINDINGS
--=============================================================================

local function rebuildLookup()
	table.clear(lookup)
	for intent, codes in bindings do
		for _, code in codes do
			local list = lookup[code]
			if not list then
				list = {}
				lookup[code] = list
			end
			table.insert(list, intent)
		end
	end
end

--[[
Troca os códigos físicos de uma intent em runtime (tela de remap).
@param codes - lista de Enum.KeyCode / Enum.UserInputType
]]
function InputService.Rebind(intent: string, codes: { EnumItem })
	assert(Intents.IsButton(intent), `[InputService] intent inválida: {tostring(intent)}`)
	releaseIntent(intent)
	bindings[intent] = table.clone(codes)
	rebuildLookup()
end


local usesKeyCode = {
	[Enum.UserInputType.Keyboard] = true,

	[Enum.UserInputType.Gamepad1] = true,
	[Enum.UserInputType.Gamepad2] = true,
	[Enum.UserInputType.Gamepad3] = true,
	[Enum.UserInputType.Gamepad4] = true,
	[Enum.UserInputType.Gamepad5] = true,
	[Enum.UserInputType.Gamepad6] = true,
	[Enum.UserInputType.Gamepad7] = true,
	[Enum.UserInputType.Gamepad8] = true,
}

local function codeOf(input: InputObject): EnumItem
	if usesKeyCode[input.UserInputType] then
		return input.KeyCode
	end

	return input.UserInputType
end

--=============================================================================
--  BOTÕES DE TELA (mobile / UI)
--=============================================================================

local function bindButton(button: Instance)
	-- Templates em StarterGui existem no cliente mas nunca recebem input: só o clone em PlayerGui importa.
	if button:IsDescendantOf(StarterGui) then
		return
	end

	if not button:IsA("GuiButton") then
		warn(`[InputService] {button:GetFullName()} tem a tag '{InputConfig.ButtonTag}' mas não é GuiButton`)
		return
	end

	local intent = button:GetAttribute(InputConfig.ButtonIntentAttribute)
	if not Intents.IsButton(intent) then
		warn(`[InputService] {button:GetFullName()} sem atributo '{InputConfig.ButtonIntentAttribute}' válido`)
		return
	end

	button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end

		-- A fonte é o InputObject (um por dedo): multitoque no mesmo botão não solta cedo.
		InputService.Press(intent, input)

		-- Escuta o FIM do próprio input, não o InputEnded do botão: o dedo pode soltar fora dele.
		local connection: RBXScriptConnection
		connection = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
			local state = input.UserInputState
			if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				connection:Disconnect()
				InputService.Release(intent, input)
			end
		end)
	end)
end

--=============================================================================
--  EIXO DE MOVIMENTO
--=============================================================================

local function startMoveAxis()
	local player = Players.LocalPlayer
	local lastSent = Vector3.zero
	local lastSentAt = 0

	-- Personagem novo = EntityCore novo no servidor, com Direction zerada. O InputHandler antigo se
	-- ressincronizava sozinho por viver em StarterCharacterScripts; este módulo persiste, então reseta aqui.
	player.CharacterAdded:Connect(function()
		lastSent = Vector3.zero
	end)

	local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	local Controls = PlayerModule:GetControls()
	
	local ControlStateChanged = ReplicatedStorage.RemoteEvents:WaitForChild("ControlStateChanged")
	ControlStateChanged.OnClientEvent:Connect(function(isLocked: boolean, entityID: string?, suspendNative: boolean?)
		-- Força a atualização do input no próximo frame. Se o player não estiver segurando nada,
		-- lastSent = 999.. vai fazer 'stopped = true' e enviar Vector3.zero, sobrescrevendo
		-- qualquer input residual (ex: a AI que estava andando reto).
		lastSent = Vector3.new(999, 999, 999)
	end)

	RunService.Heartbeat:Connect(function()
		local direction = Controls.inputMoveVector or Vector3.zero

		local now = os.clock()
		local stopped = direction == Vector3.zero and lastSent ~= Vector3.zero

		-- Parar sai na hora; o resto respeita o intervalo. Como é polling, o "trailing send"
		-- (último valor depois do intervalo) sai de graça no próximo frame.
		if not stopped then
			if (direction - lastSent).Magnitude < MOVE_EPSILON or now - lastSentAt < MOVE_SEND_INTERVAL then
				return
			end
		end

		lastSent = direction
		lastSentAt = now
		RequestDir:FireServer(direction)
	end)
end

--=============================================================================
--  INIT
--=============================================================================

function InputService.Init()
	if started then
		return
	end
	started = true

	for intent, codes in InputConfig.Bindings do
		if Intents.IsButton(intent) then
			bindings[intent] = table.clone(codes)
		else
			warn(`[InputService] InputConfig.Bindings tem intent inválida: {tostring(intent)}`)
		end
	end
	rebuildLookup()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		-- processed = chat, TextBox, botão de GUI... Só o BEGIN respeita isso.
		if processed then
			return
		end
		local code = codeOf(input)
		local intents = lookup[code]
		if intents then
			for _, intent in intents do
				InputService.Press(intent, code)
			end
		end
	end)

	-- Propositalmente SEM checar `processed`: soltar sobre a GUI não pode deixar a intent presa.
	-- Se o Begin foi ignorado, Release não acha fonte ativa e vira no-op.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local code = codeOf(input)
		local intents = lookup[code]
		if intents then
			for _, intent in intents do
				InputService.Release(intent, code)
			end
		end
	end)

	UserInputService.WindowFocusReleased:Connect(InputService.ReleaseAll)
	Players.LocalPlayer.CharacterRemoving:Connect(InputService.ReleaseAll)

	CollectionService:GetInstanceAddedSignal(InputConfig.ButtonTag):Connect(bindButton)
	for _, button in CollectionService:GetTagged(InputConfig.ButtonTag) do
		bindButton(button)
	end

	startMoveAxis()
end

return InputService

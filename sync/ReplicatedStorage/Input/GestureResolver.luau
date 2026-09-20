--[[
	GestureResolver — máquina de estados para os gestos de uma intent

	não conhece input do Roblox, player nem skill: recebe Press/Release
	com timestamp e devolve o evento equivalente.

	só tem delay a skill que declarar double tap, caso contrário o fluxo segue normal
	Sem spec (nil) o resolver é raw: Activate(Press) no instante do Press,)

	CONTRATO (por ciclo Press -> Release)
	  Raw press : Activate(Press) ....................... Release
	  Hold      : Activate(Hold) [após N s] ............. Release  |  ou Activate(Tap) no Release
	  DoubleTap : Activate(DoubleTap) [no 2º Press] ..... Release  |  ou Activate(Tap) após a janela
	  Release só é emitido se algo foi ativado ENQUANTO o botão estava apertado
	  (Tap ativa depois de soltar, então nunca é seguido de Release).
]]

local Intents = require(script.Parent.Intents)

local Kind, Gesture, Defaults = Intents.Kind, Intents.Gesture, Intents.Defaults

export type Config = {
	hold: number?,
	doubleTap: number?,
	tap: boolean,
}

local KNOWN_KEYS = { Hold = true, DoubleTap = true, Tap = true }

local GestureResolver = {}
GestureResolver.__index = GestureResolver

local function toSeconds(value: (boolean | number)?, default: number): number?
	if value == true then
		return default
	end
	if type(value) == "number" and value > 0 then
		return value
	end
	return nil
end

local function cancelThread(thread: thread?)
	if thread then
		task.cancel(thread)
	end
end

--[[
Converte o data.input da skill em Config interna.
@param spec - Intents.GestureSpec ou nil
@return Config, ou nil quando não há gesto declarado (raw press)
]]
function GestureResolver.Normalize(spec: Intents.GestureSpec?): Config?
	if not spec then
		return nil
	end

	for key in spec do
		if not KNOWN_KEYS[key] then
			warn(`[GestureResolver] chave desconhecida em data.input: '{key}'`)
		end
	end

	local hold = toSeconds(spec.Hold, Defaults.HoldTime)
	local doubleTap = toSeconds(spec.DoubleTap, Defaults.DoubleTapWindow)
	if not hold and not doubleTap then
		return nil
	end

	return { hold = hold, doubleTap = doubleTap, tap = spec.Tap ~= false }
end

--[[
@param intent - id da intent (Intents.Id) que este resolver acompanha
@param sink - recebe cada InputEvent emitido
]]
function GestureResolver.new(intent: string, sink: (Intents.InputEvent) -> ())
	return setmetatable({
		_intent = intent,
		_sink = sink,
		_cfg = nil, -- Config do ciclo atual (snapshot: trocar a skill de slot no meio não afeta)
		_down = false,
		_downAt = 0,
		_activated = false, -- algo foi ativado enquanto apertado -> Release precisa ser emitido
		_pendingTap = false, -- 1º toque esperando um 2º
		_holdThread = nil,
		_tapThread = nil,
	}, GestureResolver)
end

function GestureResolver:_fire(kind: Intents.Kind, gesture: Intents.Gesture?, heldTime: number?)
	self._sink(Intents.NewEvent(self._intent, kind, gesture, heldTime))
end

function GestureResolver:_clearTap()
	cancelThread(self._tapThread)
	self._tapThread = nil
	self._pendingTap = false
end

function GestureResolver:_clearHold()
	cancelThread(self._holdThread)
	self._holdThread = nil
end

--[[
@param now - timestamp do evento (servidor: os.clock() na chegada)
@param cfg - Config normalizada da skill que está no slot de agora
]]
function GestureResolver:Press(now: number, cfg: Config?)
	-- Release perdido/duplicado: fecha o ciclo anterior antes de abrir outro
	if self._down then
		self:Release(now)
	end

	self._down = true
	self._downAt = now

	-- 2º toque dentro da janela
	if self._pendingTap then
		self:_clearTap()
		self._activated = true
		self:_fire(Kind.Activate, Gesture.DoubleTap, 0)
		return
	end

	self._cfg = cfg
	self._activated = false

	if not cfg then
		self._activated = true
		self:_fire(Kind.Activate, Gesture.Press, 0)
		return
	end

	if cfg.hold then
		local hold = cfg.hold
		self._holdThread = task.delay(hold, function()
			self._holdThread = nil
			if not self._down or self._activated then
				return
			end
			self._activated = true
			self:_fire(Kind.Activate, Gesture.Hold, hold)
		end)
	end
end

function GestureResolver:Release(now: number)
	if not self._down then
		return
	end

	self._down = false
	self:_clearHold()
	local held = now - self._downAt

	if self._activated then
		self._activated = false
		self:_fire(Kind.Release, nil, held)
		return
	end

	-- Nada ativou ainda: foi um toque
	local cfg = self._cfg :: Config
	if cfg.doubleTap and held <= Defaults.TapMaxTime then
		self._pendingTap = true
		self._tapThread = task.delay(cfg.doubleTap, function()
			self._tapThread = nil
			self._pendingTap = false
			if cfg.tap then
				self:_fire(Kind.Activate, Gesture.Tap, held)
			end
		end)
	elseif cfg.tap then
		self:_fire(Kind.Activate, Gesture.Tap, held)
	end
end

--[[
Encerra tudo sem esperar (respawn, morte, saída do player).
@param silent - true = não emite Release (usar quando a entidade já não existe)
]]
function GestureResolver:Cancel(now: number, silent: boolean?)
	self:_clearHold()
	self:_clearTap()

	local mustRelease = self._down and self._activated and not silent
	local held = now - self._downAt

	self._down = false
	self._activated = false

	if mustRelease then
		self:_fire(Kind.Release, nil, held)
	end
end

return GestureResolver
